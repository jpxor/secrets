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
    fun requireSupported(type: String) {
        ensure(type == "Google Drive" || type == "SFTP") {
            "This backup provider is no longer supported. Export your vault and choose Google Drive or SFTP."
        }
    }
    private val pattern = Regex("secrets-[0-9]{19}-[0-9a-f]{16}\\.secrets")
    fun isSnapshot(name: String) = pattern.matches(name)
    fun sorted(files: List<RemoteFile>) = files.filter { isSnapshot(it.name) }.sortedByDescending { it.name }
    fun open(context: Context, config: JSONObject): RemoteProvider = when (config.getString("type")) {
        "Google Drive" -> GoogleDriveProvider(context, config)
        "SFTP" -> SftpProvider(config)
        else -> fail("This backup provider is no longer supported. Export your vault and choose Google Drive or SFTP.")
    }
}

class GoogleDriveProvider(private val context: Context, private val config: JSONObject) : RemoteProvider {
    private val http = OkHttpClient.Builder().connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS).callTimeout(90, TimeUnit.SECONDS).build()
    private var accessToken: String? = null
    private fun token(): String {
        accessToken?.let { return it }
        val builder = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(Providers.DRIVE_SCOPE)))
        val account = config.optString("account")
        if (account.isNotEmpty()) builder.setAccount(android.accounts.Account(account, "com.google"))
        val result = Tasks.await(Identity.getAuthorizationClient(context).authorize(builder.build()), 60, TimeUnit.SECONDS)
        ensure(!result.hasResolution()) { "Google Drive needs authorization. Reconnect the provider in Settings." }
        return (result.accessToken ?: fail("Google Drive did not provide an access token.")).also { accessToken = it }
    }
    private fun bytes(request: Request): ByteArray {
        val req = request.newBuilder().header("Authorization", "Bearer ${token()}").build()
        http.newCall(req).execute().use { response ->
            if (!response.isSuccessful) {
                // Inspect only a bounded body; no provider text is surfaced or logged.
                fail(GoogleDriveErrors.http(response.code, response.peekBody(16384).string()))
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
    private fun json(request: Request) = JSONObject(bytes(request).toString(Charsets.UTF_8))
    override fun list(): List<RemoteFile> {
        val files = mutableListOf<RemoteFile>()
        var page: String? = null
        do {
            val url = "https://www.googleapis.com/drive/v3/files".toHttpUrl().newBuilder()
                .addQueryParameter("spaces", "appDataFolder").addQueryParameter("q", "trashed = false")
                .addQueryParameter("fields", "nextPageToken,files(id,name)").addQueryParameter("pageSize", "1000")
            if (page != null) url.addQueryParameter("pageToken", page)
            val result = json(Request.Builder().url(url.build()).build())
            val array = result.getJSONArray("files")
            for (i in 0 until array.length()) { val f = array.getJSONObject(i); files += RemoteFile(f.getString("name"), f.getString("id")) }
            page = result.optString("nextPageToken").ifEmpty { null }
        } while (page != null)
        return Providers.sorted(files)
    }
    override fun read(file: RemoteFile): String = bytes(Request.Builder()
        .url("https://www.googleapis.com/drive/v3/files/${file.locator}?alt=media").build()).toString(Charsets.UTF_8)
    override fun put(name: String, envelope: String) {
        ensure(Providers.isSnapshot(name))
        val body = MultipartBody.Builder().setType("multipart/related".toMediaType())
            .addPart(JSONObject().put("name", name).put("parents", JSONArray().put("appDataFolder")).toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
            .addPart(envelope.toByteArray().toRequestBody("application/octet-stream".toMediaType())).build()
        bytes(Request.Builder().url("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart").post(body).build())
    }
    override fun delete(file: RemoteFile) {
        bytes(Request.Builder().url("https://www.googleapis.com/drive/v3/files/${file.locator}").delete().build())
    }
}

fun secureJsch(config: JSONObject, onUntrusted: (SshHostKeyException) -> Unit = {}): JSch = JSch().apply {
    val pin = config.optString("fingerprint").trim()
    setHostKeyRepository(object : HostKeyRepository {
        override fun check(host: String?, key: ByteArray): Int {
            val actual = "SHA256:" + java.util.Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(key))
            if (pin.isEmpty() || !MessageDigest.isEqual(actual.toByteArray(), pin.toByteArray())) {
                val challenge = SshHostKeyException(actual, pin)
                onUntrusted(challenge)
                throw challenge
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
    private var hostKeyChallenge: SshHostKeyException? = null
    private val session = secureJsch(config) { hostKeyChallenge = it }.getSession(config.getString("username"), config.getString("host"), config.optInt("port", 22))
    private val sftp: ChannelSftp
    init {
        session.setConfig("StrictHostKeyChecking", "yes")
        session.setConfig("PreferredAuthentications", "publickey,password,keyboard-interactive")
        config.optString("password").takeIf { it.isNotEmpty() }?.let { session.setPassword(it) }
        session.timeout = 30000
        try {
            try { session.connect(30000) } catch (e: Exception) { throw (hostKeyChallenge ?: e) }
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
