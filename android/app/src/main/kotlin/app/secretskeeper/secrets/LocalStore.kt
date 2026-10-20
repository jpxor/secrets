package app.secretskeeper.secrets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class Snapshot(val sequence: Long, val envelope: String) {
    val id: String get() = JSONObject(envelope).getJSONObject("header").getString("id")
    val name: String get() {
        val hash = MessageDigest.getInstance("SHA-256").digest(envelope.toByteArray()).take(8)
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return "secrets-${sequence.toString().padStart(19, '0')}-$hash.secrets"
    }
}

class LocalStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("status", Context.MODE_PRIVATE)
    private val vaultFile get() = AtomicFile(File(context.filesDir, "vault.enc"))
    private val configFile get() = AtomicFile(File(context.noBackupFilesDir, "provider.enc"))
    private val bioFile get() = AtomicFile(File(context.noBackupFilesDir, "biometric.json"))

    fun snapshot(): Snapshot? = synchronized(fileLock) {
        if (!atomicExists(vaultFile)) return@synchronized null
        val json = JSONObject(vaultFile.openRead().use { it.readBytes().toString(Charsets.UTF_8) })
        Snapshot(json.getLong("sequence"), json.getString("envelope"))
    }

    fun save(envelope: String, replacement: Boolean) = synchronized(fileLock) {
        ensure(envelope.toByteArray().size <= MAX_BYTES) { "Vault exceeds supported size." }
        val header = JSONObject(envelope).getJSONObject("header")
        ensure(header.getString("format") == "Secrets" && header.getInt("version") == 1)
        val hadVault = atomicExists(vaultFile)
        val previous = try { snapshot() } catch (e: Exception) { if (!replacement) throw e else null }
        val sequence = maxOf(System.currentTimeMillis(), (previous?.sequence ?: 0) + 1, prefs.getLong("remoteSequence", 0) + 1)
        atomicWrite(vaultFile, JSONObject().put("sequence", sequence).put("envelope", envelope).toString().toByteArray())
        if (replacement && hadVault) {
            // Only change bindings after a successful atomic vault replacement.
            disconnect()
            runCatching { clearBiometrics() }
        }
    }

    fun config(): JSONObject? = synchronized(fileLock) {
        if (!atomicExists(configFile)) return@synchronized null
        val json = JSONObject(configFile.openRead().use { it.readBytes().toString(Charsets.UTF_8) })
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, credentialKey(), GCMParameterSpec(128, unbase64(json.getString("iv"))))
        JSONObject(cipher.doFinal(unbase64(json.getString("data"))).toString(Charsets.UTF_8))
    }

    fun setConfig(config: JSONObject) = synchronized(fileLock) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, credentialKey())
        val encrypted = cipher.doFinal(config.toString().toByteArray())
        atomicWrite(configFile, JSONObject().put("iv", base64(cipher.iv)).put("data", base64(encrypted)).toString().toByteArray())
    }

    private fun credentialKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey("secrets.provider", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("secrets.provider", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    fun status(): Map<String, Any?> = synchronized(fileLock) {
        val snapshot = snapshot()
        val configured = atomicExists(configFile)
        mapOf("provider" to prefs.getString("provider", null), "configured" to configured,
            "pending" to (configured && snapshot != null && snapshot.sequence > prefs.getLong("ack", 0)),
            "lastBackup" to prefs.getLong("lastBackup", 0), "error" to prefs.getString("error", null),
            "biometrics" to bioFile.baseFile.exists(), "lockSeconds" to prefs.getInt("lockSeconds", 30))
    }
    fun activate(config: JSONObject, remoteName: String?) = synchronized(fileLock) {
        setConfig(config)
        prefs.edit().putString("provider", config.getString("type")).putLong("ack", 0)
            .putString("remoteName", remoteName).putLong("remoteSequence", remoteName?.split('-')?.getOrNull(1)?.toLongOrNull() ?: 0)
            .remove("error").remove("lastBackup").commit()
        // Restore remains ordered even if the new phone's clock is behind the old phone.
        snapshot()?.let { save(it.envelope, false) }
    }
    fun remoteName(): String? = prefs.getString("remoteName", null)
    fun acknowledged(snapshot: Snapshot) {
        prefs.edit().putLong("ack", snapshot.sequence).putString("remoteName", snapshot.name)
            .putLong("lastBackup", System.currentTimeMillis()).remove("error").commit()
    }
    fun error(message: String) { prefs.edit().putString("error", message).commit() }
    fun disconnect() = synchronized(fileLock) {
        configFile.delete()
        prefs.edit().remove("provider").remove("error").remove("lastBackup").remove("remoteName").putLong("ack", 0).commit()
    }
    fun setLockSeconds(seconds: Int) {
        ensure(seconds in listOf(0, 15, 30, 60, 120, 300))
        prefs.edit().putInt("lockSeconds", seconds).commit()
    }
    fun biometric(): JSONObject? = if (bioFile.baseFile.exists())
        JSONObject(bioFile.openRead().use { it.readBytes().toString(Charsets.UTF_8) }) else null
    fun saveBiometric(data: JSONObject) { atomicWrite(bioFile, data.toString().toByteArray()) }
    fun clearBiometrics() {
        bioFile.delete()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); if (containsAlias("secrets.biometric")) deleteEntry("secrets.biometric") }
    }
    companion object {
        const val MAX_BYTES = 8 * 1024 * 1024
        val fileLock = Any()
        fun atomicExists(file: AtomicFile) = file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()
        fun base64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
        fun unbase64(value: String): ByteArray = Base64.decode(value, Base64.NO_WRAP)
        fun atomicWrite(file: AtomicFile, bytes: ByteArray) {
            val stream = file.startWrite()
            try { stream.write(bytes); file.finishWrite(stream) } catch (e: Exception) { file.failWrite(stream); throw e }
        }
    }
}
