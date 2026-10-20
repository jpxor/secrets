package app.secretskeeper.secrets

import android.content.Context
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Tasks
import com.jcraft.jsch.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

data class RemoteFile(val name: String, val locator: String)
interface RemoteProvider : AutoCloseable {
    fun list(): List<RemoteFile>
    fun read(file: RemoteFile): String
    fun put(name: String, envelope: String)
    fun delete(file: RemoteFile)
    override fun close() {}
}

object Providers {
    const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.appdata"
    private val pattern = Regex("secrets-[0-9]{19}-[0-9a-f]{16}\\.secrets")
    fun isSnapshot(name: String) = pattern.matches(name)
    fun sorted(files: List<RemoteFile>) = files.filter { isSnapshot(it.name) }.sortedByDescending { it.name }
    fun open(context: Context, config: JSONObject, saveConfig: ((JSONObject) -> Unit)? = null): RemoteProvider = when (config.getString("type")) {
        "Google Drive", "OneDrive", "Dropbox" -> CloudProvider(context, config, saveConfig)
        "SFTP" -> SftpProvider(config)
        "Git" -> GitProvider(context, config)
        else -> fail("Unknown backup provider.")
    }
}

class CloudProvider(private val context: Context, private val config: JSONObject,
                    private val saveConfig: ((JSONObject) -> Unit)?) : RemoteProvider {
    private val type = config.getString("type")
    private val http = OkHttpClient.Builder().connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS).callTimeout(90, TimeUnit.SECONDS).build()
    private var accessToken: String? = null
    private fun token(): String {
        accessToken?.let { return it }
        if (type == "Google Drive") {
            val builder = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(Providers.DRIVE_SCOPE)))
            val account = config.optString("account")
            if (account.isNotEmpty()) builder.setAccount(android.accounts.Account(account, "com.google"))
            val result = Tasks.await(Identity.getAuthorizationClient(context).authorize(builder.build()), 60, TimeUnit.SECONDS)
            ensure(!result.hasResolution()) { "Google Drive needs authorization. Reconnect the provider in Settings." }
            return (result.accessToken ?: fail("Google Drive did not provide an access token.")).also { accessToken = it }
        }
        val endpoint = if (type == "OneDrive") "https://login.microsoftonline.com/consumers/oauth2/v2.0/token" else "https://api.dropboxapi.com/oauth2/token"
        val form = okhttp3.FormBody.Builder().add("grant_type", "refresh_token")
            .add("refresh_token", config.getString("refreshToken")).add("client_id", config.getString("clientId"))
        if (type == "OneDrive") form.add("scope", "Files.ReadWrite.AppFolder offline_access")
        val request = Request.Builder().url(endpoint).post(form.build()).build()
        val result = json(request, authorized = false)
        if (result.has("refresh_token")) {
            config.put("refreshToken", result.getString("refresh_token"))
            saveConfig?.invoke(config)
        }
        return result.getString("access_token").also { accessToken = it }
    }
    private fun bytes(request: Request, authorized: Boolean = true): ByteArray {
        val req = if (authorized) request.newBuilder().header("Authorization", "Bearer ${token()}").build() else request
        http.newCall(req).execute().use { response ->
            if (!response.isSuccessful) {
                if (type == "Google Drive") {
                    // Inspect only a bounded body; no provider text is surfaced or logged.
                    fail(GoogleDriveErrors.http(response.code, response.peekBody(16384).string()))
                }
                val hint = when (response.code) {
                    401, 403 -> "Authorization expired or access denied; reconnect the provider."
                    409 -> "The destination changed or the account has insufficient space."
                    429 -> "Provider rate limit reached; backup will retry."
                    507 -> "Backup storage is full."
                    else -> "Backup provider returned HTTP ${response.code}."
                }
                fail(hint)
            }
            val stream = response.body?.byteStream() ?: return ByteArray(0)
            return stream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    ensure(output.size() + n <= LocalStore.MAX_BYTES) { "Remote response is too large." }
                    output.write(buffer, 0, n)
                }
                output.toByteArray()
            }
        }
    }
    private fun json(request: Request, authorized: Boolean = true) = JSONObject(bytes(request, authorized).toString(Charsets.UTF_8))
    private fun post(url: String, json: JSONObject) = Request.Builder().url(url)
        .post(json.toString().toRequestBody("application/json".toMediaType())).build()

    override fun list(): List<RemoteFile> {
        val files = mutableListOf<RemoteFile>()
        when (type) {
            "Google Drive" -> {
                var page: String? = null
                do {
                    val url = "https://www.googleapis.com/drive/v3/files".toHttpUrl().newBuilder()
                        .addQueryParameter("spaces", "appDataFolder").addQueryParameter("q", "trashed = false")
                        .addQueryParameter("fields", "files(id,name),nextPageToken").addQueryParameter("pageSize", "1000")
                    if (page != null) url.addQueryParameter("pageToken", page)
                    val result = json(Request.Builder().url(url.build()).build())
                    val array = result.getJSONArray("files")
                    for (i in 0 until array.length()) { val f = array.getJSONObject(i); files += RemoteFile(f.getString("name"), f.getString("id")) }
                    page = result.optString("nextPageToken").ifEmpty { null }
                } while (page != null)
            }
            "OneDrive" -> {
                var url: String? = "https://graph.microsoft.com/v1.0/me/drive/special/approot/children?\$select=id,name&\$top=200"
                do {
                    val next = url!!.toHttpUrl()
                    ensure(next.isHttps && next.host == "graph.microsoft.com") { "Invalid provider pagination URL." }
                    val result = json(Request.Builder().url(next).build())
                    val array = result.getJSONArray("value")
                    for (i in 0 until array.length()) { val f = array.getJSONObject(i); files += RemoteFile(f.getString("name"), f.getString("id")) }
                    url = result.optString("@odata.nextLink").ifEmpty { null }
                } while (url != null)
            }
            "Dropbox" -> {
                var cursor: String? = null
                do {
                    val result = json(post("https://api.dropboxapi.com/2/files/" + if (cursor == null) "list_folder" else "list_folder/continue",
                        if (cursor == null) JSONObject().put("path", "") else JSONObject().put("cursor", cursor)))
                    val array = result.getJSONArray("entries")
                    for (i in 0 until array.length()) { val f = array.getJSONObject(i); if (f.optString(".tag") == "file") files += RemoteFile(f.getString("name"), f.getString("path_lower")) }
                    cursor = if (result.getBoolean("has_more")) result.getString("cursor") else null
                } while (cursor != null)
            }
        }
        return Providers.sorted(files)
    }
    override fun read(file: RemoteFile): String {
        val builder = when (type) {
            "Google Drive" -> Request.Builder().url("https://www.googleapis.com/drive/v3/files/${file.locator}?alt=media")
            "OneDrive" -> Request.Builder().url("https://graph.microsoft.com/v1.0/me/drive/items/${file.locator}/content")
            else -> Request.Builder().url("https://content.dropboxapi.com/2/files/download")
                .header("Dropbox-API-Arg", JSONObject().put("path", file.locator).toString()).post(ByteArray(0).toRequestBody())
        }
        return bytes(builder.build()).toString(Charsets.UTF_8)
    }
    override fun put(name: String, envelope: String) {
        ensure(Providers.isSnapshot(name))
        val content = envelope.toByteArray()
        val req = when (type) {
            "Google Drive" -> {
                val body = MultipartBody.Builder().setType("multipart/related".toMediaType())
                    .addPart(JSONObject().put("name", name).put("parents", JSONArray().put("appDataFolder")).toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                    .addPart(content.toRequestBody("application/octet-stream".toMediaType())).build()
                Request.Builder().url("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart").post(body).build()
            }
            "OneDrive" -> Request.Builder().url("https://graph.microsoft.com/v1.0/me/drive/special/approot:/$name:/content")
                .put(content.toRequestBody("application/octet-stream".toMediaType())).build()
            else -> Request.Builder().url("https://content.dropboxapi.com/2/files/upload")
                .header("Dropbox-API-Arg", JSONObject().put("path", "/$name").put("mode", "add").put("autorename", false).toString())
                .post(content.toRequestBody("application/octet-stream".toMediaType())).build()
        }
        bytes(req)
    }
    override fun delete(file: RemoteFile) {
        val request = when (type) {
            "Google Drive" -> Request.Builder().url("https://www.googleapis.com/drive/v3/files/${file.locator}").delete().build()
            "OneDrive" -> Request.Builder().url("https://graph.microsoft.com/v1.0/me/drive/items/${file.locator}").delete().build()
            else -> post("https://api.dropboxapi.com/2/files/delete_v2", JSONObject().put("path", file.locator))
        }
        bytes(request)
    }
}

fun secureJsch(config: JSONObject): JSch = JSch().apply {
    val pin = config.optString("fingerprint").trim()
    setHostKeyRepository(object : HostKeyRepository {
        override fun check(host: String?, key: ByteArray): Int {
            val actual = "SHA256:" + java.util.Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(key))
            ensure(pin.isNotEmpty() && MessageDigest.isEqual(actual.toByteArray(), pin.toByteArray())) {
                "SSH host key not trusted or changed. Verify this fingerprint independently, then enter it explicitly: $actual"
            }
            return HostKeyRepository.OK
        }
        override fun add(hostkey: HostKey?, ui: UserInfo?) = Unit
        override fun remove(host: String?, type: String?) = Unit
        override fun remove(host: String?, type: String?, key: ByteArray?) = Unit
        override fun getKnownHostsRepositoryID() = "Secrets pinned server key"
        override fun getHostKey(): Array<HostKey> = emptyArray()
        override fun getHostKey(host: String?, type: String?): Array<HostKey> = emptyArray()
    })
    val privateKey = config.optString("privateKey")
    if (privateKey.isNotBlank()) addIdentity("Secrets", privateKey.toByteArray(), null,
        config.optString("keyPassphrase").takeIf { it.isNotEmpty() }?.toByteArray())
}

class SftpProvider(config: JSONObject) : RemoteProvider {
    private val session = secureJsch(config).getSession(config.getString("username"), config.getString("host"), config.optInt("port", 22))
    private val sftp: ChannelSftp
    init {
        session.setConfig("StrictHostKeyChecking", "yes")
        session.setConfig("PreferredAuthentications", "publickey,password,keyboard-interactive")
        config.optString("password").takeIf { it.isNotEmpty() }?.let { session.setPassword(it) }
        session.timeout = 30000
        session.connect(30000)
        try {
            sftp = (session.openChannel("sftp") as ChannelSftp).apply { connect(30000) }
            val directory = config.optString("directory", "Secrets").trim()
            ensure(directory.isNotEmpty() && directory.split('/').none { it == ".." }) { "Invalid backup directory." }
            if (directory.startsWith('/')) sftp.cd("/")
            directory.split('/').filter { it.isNotEmpty() && it != "." }.forEach { part ->
                try { sftp.cd(part) } catch (e: SftpException) {
                    if (e.id != ChannelSftp.SSH_FX_NO_SUCH_FILE) throw e
                    sftp.mkdir(part); sftp.cd(part)
                }
            }
        } catch (e: Exception) { session.disconnect(); throw e }
    }
    override fun list(): List<RemoteFile> = Providers.sorted(sftp.ls(".").mapNotNull {
        val item = it as ChannelSftp.LsEntry
        if (!item.attrs.isDir) RemoteFile(item.filename, item.filename) else null
    })
    override fun read(file: RemoteFile): String {
        ensure(Providers.isSnapshot(file.locator) && sftp.stat(file.locator).size <= LocalStore.MAX_BYTES) { "Invalid or oversized remote backup." }
        return sftp.get(file.locator).use { input ->
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) { val n = input.read(buffer); if (n < 0) break; ensure(out.size() + n <= LocalStore.MAX_BYTES); out.write(buffer, 0, n) }
            out.toString("UTF-8")
        }
    }
    override fun put(name: String, envelope: String) {
        ensure(Providers.isSnapshot(name))
        val temporary = ".upload-${UUID.randomUUID()}"
        try { sftp.put(ByteArrayInputStream(envelope.toByteArray()), temporary); sftp.rename(temporary, name) }
        finally { try { sftp.rm(temporary) } catch (_: SftpException) {} }
    }
    override fun delete(file: RemoteFile) { ensure(Providers.isSnapshot(file.locator)); sftp.rm(file.locator) }
    override fun close() { sftp.disconnect(); session.disconnect() }
}
