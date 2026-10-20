package app.secretskeeper.secrets

import android.app.Activity
import android.app.KeyguardManager
import android.content.*
import android.os.*
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.openid.appauth.*
import org.json.JSONObject
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.concurrent.withLock

class MainActivity : FlutterFragmentActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val store by lazy { LocalStore(applicationContext) }
    private lateinit var channel: MethodChannel
    private lateinit var oauth: AuthorizationService
    private var pending: MethodChannel.Result? = null
    private var candidate: JSONObject? = null
    private var candidateRemote: String? = null
    private var candidateVaultId: String? = null
    private var authCandidate: JSONObject? = null
    private var authProvider: String? = null
    private var clipboardGeneration = 0L
    private var observedClipboardChange = false
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF && ::channel.isInitialized) channel.invokeMethod("screenLocked", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        oauth = AuthorizationService(this)
        ContextCompat.registerReceiver(this, receiver, IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED)
        BackupWorker.schedule(applicationContext)
    }
    override fun onResume() {
        super.onResume()
        if (::channel.isInitialized && (getSystemService(KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked) channel.invokeMethod("screenLocked", null)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.secretskeeper.secrets/platform")
        channel.setMethodCallHandler(::handle)
    }
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try { val value = block(); handler.post { result.success(value) } }
            catch (e: Exception) { handler.post { result.error("secrets", BackupWorker.safeError(e), null) } }
            catch (_: LinkageError) { handler.post { result.error("platform", "This operation is incompatible with this Android runtime. Use encrypted export and report the device/Android version.", null) } }
        }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "readVault" -> background(result) { store.snapshot()?.envelope }
                "writeVault" -> background(result) {
                    val replacement = call.argument<Boolean>("replacement") == true
                    if (replacement) BackupWorker.providerLock.withLock { store.save(call.argument<String>("envelope")!!, true) }
                    else store.save(call.argument<String>("envelope")!!, false)
                    BackupWorker.schedule(applicationContext)
                    null
                }
                "status" -> background(result) { store.status() }
                "setLockDelay" -> { store.setLockSeconds(call.argument<Int>("seconds")!!); result.success(null) }
                "copySecret" -> { copySecret(call.argument<String>("value")!!); result.success(null) }
                "enableBiometrics" -> enableBiometrics(call.argument<ByteArray>("key")!!, call.argument<String>("id")!!, result)
                "biometricKey" -> biometricKey(result)
                "disableBiometrics" -> { store.clearBiometrics(); result.success(null) }
                "exportVault" -> {
                    ensure(pending == null) { "Another system dialog is open." }
                    ensure(store.snapshot() != null) { "No vault to export." }
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE); type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, "Secrets-${java.time.LocalDate.now()}.secrets")
                    }, EXPORT)
                }
                "importVault" -> {
                    ensure(pending == null) { "Another system dialog is open." }
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, IMPORT)
                }
                "backupNow" -> { BackupWorker.schedule(applicationContext, immediate = true); result.success(null) }
                "disconnectBackup" -> background(result) { BackupWorker.providerLock.withLock { store.disconnect() }; null }
                "connectBackup" -> {
                    ensure(pending == null) { "Another authorization is in progress." }
                    candidate = null; candidateRemote = null; candidateVaultId = null
                    @Suppress("UNCHECKED_CAST")
                    val config = JSONObject(call.arguments as Map<String, Any>)
                    when (config.getString("type")) {
                        "Google Drive" -> authorizeGoogle(config, result)
                        "OneDrive", "Dropbox" -> authorizeOAuth(config, result)
                        else -> inspect(config, result)
                    }
                }
                "activateBackup" -> background(result) {
                    BackupWorker.providerLock.withLock {
                        val config = candidate ?: fail("Connect a destination first.")
                        val local = store.snapshot() ?: fail("Create or restore a vault before enabling backup.")
                        Providers.open(applicationContext, config) { updated -> candidate = updated }.use { provider ->
                            val newest = provider.list().firstOrNull()
                            ensure(newest?.name == candidateRemote) { "Destination changed during setup. Connect again." }
                            if (newest != null) ensure(candidateVaultId == local.id) {
                                "Restore the remote vault before enabling backup to this destination."
                            }
                        }
                        store.activate(config, candidateRemote)
                        candidate = null; candidateRemote = null; candidateVaultId = null
                    }
                    BackupWorker.schedule(applicationContext, immediate = true)
                    null
                }
                "downloadBackup" -> background(result) {
                    BackupWorker.providerLock.withLock {
                        val config = store.config() ?: fail("No backup provider configured.")
                        Providers.open(applicationContext, config, store::setConfig).use { provider ->
                            provider.list().firstOrNull()?.let { provider.read(it) } ?: fail("No backup found.")
                        }
                    }
                }
                "candidateBackup" -> background(result) {
                    BackupWorker.providerLock.withLock {
                        val config = candidate ?: fail("Connect a destination first.")
                        val name = call.argument<String>("name")!!
                        Providers.open(applicationContext, config) { updated -> candidate = updated }.use { provider ->
                            val file = provider.list().firstOrNull { it.name == name } ?: fail("Backup no longer exists. Connect again.")
                            val text = provider.read(file)
                            candidateVaultId = JSONObject(text).getJSONObject("header").getString("id")
                            text
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            if (pending === result) { pending = null; authCandidate = null; authProvider = null }
            result.error("secrets", BackupWorker.safeError(e), null)
        }
    }

    private fun inspect(config: JSONObject, result: MethodChannel.Result) = background(result) {
        BackupWorker.providerLock.withLock {
            Providers.open(applicationContext, config) { updated -> config.put("refreshToken", updated.getString("refreshToken")) }.use { provider ->
                val files = provider.list()
                val latest = files.firstOrNull()
                val envelope = latest?.let { provider.read(it) }
                candidate = config; candidateRemote = latest?.name
                candidateVaultId = envelope?.let { runCatching { JSONObject(it).getJSONObject("header").getString("id") }.getOrNull() }
                mapOf("exists" to (latest != null), "backup" to envelope,
                    "backups" to files.map { it.name },
                    "matchesLocal" to (candidateVaultId != null && runCatching { store.snapshot()?.id }.getOrNull() == candidateVaultId))
            }
        }
    }

    private fun authorizeGoogle(config: JSONObject, result: MethodChannel.Result) {
        pending = result; authCandidate = config; authProvider = "Google Drive"
        val request = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(Providers.DRIVE_SCOPE))).build()
        Identity.getAuthorizationClient(this).authorize(request).addOnSuccessListener { response ->
            if (response.hasResolution()) {
                try { startIntentSenderForResult(response.pendingIntent!!.intentSender, GOOGLE, null, 0, 0, 0) }
                catch (e: Exception) { finishAuthError("Google authorization could not open. Check Google Play services and OAuth setup.") }
            } else finishGoogle(response)
        }.addOnFailureListener { finishAuthError("Google authorization failed. Register this APK's package/signing fingerprint and enable Drive API.") }
    }
    private fun finishGoogle(response: com.google.android.gms.auth.api.identity.AuthorizationResult) {
        val result = pending ?: return
        val config = authCandidate ?: return
        @Suppress("DEPRECATION")
        response.toGoogleSignInAccount()?.account?.name?.let { config.put("account", it) }
        pending = null; authCandidate = null; authProvider = null
        inspect(config, result)
    }
    private fun authorizeOAuth(config: JSONObject, result: MethodChannel.Result) {
        val type = config.getString("type")
        val client = config.optString("clientId").trim()
        ensure(client.isNotEmpty()) { "A public OAuth client ID is required. See docs/PROVIDERS.md or enter your own app registration ID." }
        val service = if (type == "OneDrive") AuthorizationServiceConfiguration(
            android.net.Uri.parse("https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize"),
            android.net.Uri.parse("https://login.microsoftonline.com/consumers/oauth2/v2.0/token"))
        else AuthorizationServiceConfiguration(android.net.Uri.parse("https://www.dropbox.com/oauth2/authorize"), android.net.Uri.parse("https://api.dropboxapi.com/oauth2/token"))
        val builder = net.openid.appauth.AuthorizationRequest.Builder(service, client, ResponseTypeValues.CODE,
            android.net.Uri.parse("app.secretskeeper.secrets:/oauth2redirect"))
            .setScope(if (type == "OneDrive") "Files.ReadWrite.AppFolder offline_access" else "files.metadata.read files.content.read files.content.write")
        if (type == "Dropbox") builder.setAdditionalParameters(mapOf("token_access_type" to "offline"))
        // AppAuth automatically generates PKCE verifier/challenge and validates OAuth state.
        pending = result; authCandidate = config; authProvider = type
        startActivityForResult(oauth.getAuthorizationRequestIntent(builder.build()), OAUTH)
    }
    private fun finishAuthError(message: String) {
        val result = pending
        pending = null; authCandidate = null; authProvider = null
        result?.error("authorization", message, null)
    }

    private fun enableBiometrics(key: ByteArray, id: String, result: MethodChannel.Result) {
        ensure(BiometricManager.from(this).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS) {
            "Enroll a strong fingerprint/biometric in Android Settings first."
        }
        store.clearBiometrics()
        val builder = KeyGenParameterSpec.Builder("secrets.biometric", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true).setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= 30) builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        else { @Suppress("DEPRECATION") builder.setUserAuthenticationValidityDurationSeconds(-1) }
        val protectedKey = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(builder.build()) }.generateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, protectedKey) }
        prompt(cipher, result) { authenticated ->
            try { authenticated.updateAAD(id.toByteArray())
                store.saveBiometric(JSONObject().put("id", id).put("iv", LocalStore.base64(authenticated.iv))
                .put("data", LocalStore.base64(authenticated.doFinal(key)))); null }
            finally { key.fill(0) }
        }
    }
    private fun biometricKey(result: MethodChannel.Result) {
        val blob = store.biometric() ?: fail("Biometric unlock is not enabled. Use the master passphrase.")
        ensure(store.snapshot()?.id == blob.getString("id")) { "Biometric binding belongs to another vault." }
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = ks.getKey("secrets.biometric", null) as? SecretKey ?: fail("Biometric key unavailable. Use the master passphrase.")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, LocalStore.unbase64(blob.getString("iv"))))
        }
        prompt(cipher, result) {
            it.updateAAD(blob.getString("id").toByteArray())
            it.doFinal(LocalStore.unbase64(blob.getString("data")))
        }
    }
    private fun prompt(cipher: Cipher, result: MethodChannel.Result, success: (Cipher) -> Any?) {
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                try { result.success(success(auth.cryptoObject!!.cipher!!)) }
                catch (e: Exception) {
                    // Only exception types and code locations: never log key material or exception messages.
                    android.util.Log.e("SecretsBiometric", e.javaClass.simpleName + " at " + e.stackTrace.take(5).joinToString(" | "))
                    result.error("biometric", "Biometric setup/unlock failed (${e.javaClass.simpleName}). Use the master passphrase and enable biometrics again.", null)
                }
            }
            override fun onAuthenticationError(code: Int, message: CharSequence) { result.error("biometric", message.toString(), null) }
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("Unlock Secrets")
            .setSubtitle("Your master passphrase is still required for recovery")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).setNegativeButtonText("Use passphrase").build(), BiometricPrompt.CryptoObject(cipher))
    }

    private fun copySecret(value: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboardListener?.let { clipboard.removePrimaryClipChangedListener(it) }
        val generation = ++clipboardGeneration
        val clip = ClipData.newPlainText("Secrets", value)
        clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
        clipboard.setPrimaryClip(clip)
        observedClipboardChange = false
        val listener = ClipboardManager.OnPrimaryClipChangedListener { observedClipboardChange = true }
        clipboardListener = listener
        clipboard.addPrimaryClipChangedListener(listener)
        handler.postDelayed({
            if (generation == clipboardGeneration) {
                val current = clipboard.primaryClip
                if (!observedClipboardChange && current?.description?.label == "Secrets" && current.itemCount == 1 && current.getItemAt(0).text?.toString() == value) {
                    if (Build.VERSION.SDK_INT >= 28) clipboard.clearPrimaryClip() else clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                }
                clipboard.removePrimaryClipChangedListener(listener)
                clipboardListener = null
            }
        }, 30000)
    }

    @Deprecated("Activity result API bridge for Flutter platform integration")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val result = pending ?: return
        when (requestCode) {
            IMPORT, EXPORT -> {
                pending = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
                background(result) {
                    if (requestCode == EXPORT) {
                        val envelope = store.snapshot()?.envelope ?: fail("No vault to export.")
                        contentResolver.openOutputStream(uri, "wt")!!.use { it.write(envelope.toByteArray()) }; null
                    } else contentResolver.openInputStream(uri)!!.use { stream ->
                        val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                        while (true) { val n = stream.read(buffer); if (n < 0) break; ensure(out.size() + n <= LocalStore.MAX_BYTES) { "Import exceeds 8 MiB." }; out.write(buffer, 0, n) }
                        out.toString("UTF-8")
                    }
                }
            }
            GOOGLE -> {
                try { finishGoogle(Identity.getAuthorizationClient(this).getAuthorizationResultFromIntent(data)) }
                catch (_: Exception) { finishAuthError("Google authorization canceled or failed.") }
            }
            OAUTH -> {
                val response = data?.let { AuthorizationResponse.fromIntent(it) }
                if (response == null) { finishAuthError("Authorization canceled or failed."); return }
                oauth.performTokenRequest(response.createTokenExchangeRequest()) { token, error ->
                    if (error != null || token?.refreshToken == null) { finishAuthError("Provider did not grant background access. Check the app registration and reconnect.") }
                    else {
                        val config = authCandidate ?: return@performTokenRequest
                        config.put("refreshToken", token.refreshToken)
                        pending = null; authCandidate = null; authProvider = null
                        inspect(config, result)
                    }
                }
            }
        }
    }
    override fun onDestroy() {
        unregisterReceiver(receiver)
        if (::oauth.isInitialized) oauth.dispose()
        clipboardListener?.let { (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).removePrimaryClipChangedListener(it) }
        io.shutdown()
        super.onDestroy()
    }
    companion object { const val IMPORT = 301; const val EXPORT = 302; const val OAUTH = 303; const val GOOGLE = 304 }
}
