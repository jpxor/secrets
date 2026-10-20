package app.secretskeeper.secrets

import org.json.JSONObject

/** Only fixed messages and numeric status codes leave this boundary. */
object GoogleDriveErrors {
    fun authorization(code: Int?, canceled: Boolean = false): String = when {
        canceled || code == 16 || code == 12501 -> "Google authorization was canceled. No backup destination was changed."
        code == 10 -> "Google Drive is not configured for this app build. The maintainer must register its package and signing fingerprint and enable Drive API."
        code == 7 -> "Google authorization could not connect. Check the internet connection and try again."
        else -> "Google authorization failed${code?.let { " (code $it)" } ?: ""}. Check Google Play services and the app's Google Cloud registration."
    }

    fun http(code: Int, body: String): String {
        val reasons = runCatching {
            val errors = JSONObject(body).optJSONObject("error")?.optJSONArray("errors")
            (0 until (errors?.length() ?: 0)).map { errors!!.optJSONObject(it)?.optString("reason") }
        }.getOrDefault(emptyList())
        return when {
            "storageQuotaExceeded" in reasons -> "Google Drive storage is full. Free space in this Google account, then retry backup. Your local vault is safe."
            "accessNotConfigured" in reasons || "serviceDisabled" in reasons -> "Google Drive API is not enabled for this app's Google Cloud project. Contact the app maintainer."
            "rateLimitExceeded" in reasons || "userRateLimitExceeded" in reasons || code == 429 -> "Google Drive rate limit reached. Backup will retry."
            code == 401 -> "Google Drive authorization expired. Reconnect Google Drive in Settings."
            code == 403 -> "Google Drive denied access. Check account permissions or reconnect Google Drive in Settings."
            else -> "Google Drive returned HTTP $code. Backup has not been confirmed."
        }
    }
}
