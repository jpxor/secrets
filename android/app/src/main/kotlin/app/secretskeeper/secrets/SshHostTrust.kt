package app.secretskeeper.secrets

import org.json.JSONObject

/** Public host-key metadata only; never credentials or provider response text. */
class SshHostKeyException(val fingerprint: String, val previousFingerprint: String) :
    IllegalStateException("SSH host key needs explicit approval.")

object SshHostTrust {
    fun reuseSavedPin(config: JSONObject, saved: JSONObject?) {
        if (config.optString("type") != "SFTP" || config.optString("fingerprint").isNotBlank() ||
            saved?.optString("type") != "SFTP") return
        if (config.optString("host").trim().equals(saved.optString("host").trim(), ignoreCase = true) &&
            config.optInt("port", 22) == saved.optInt("port", 22)) {
            config.put("fingerprint", saved.optString("fingerprint"))
        }
    }
}
