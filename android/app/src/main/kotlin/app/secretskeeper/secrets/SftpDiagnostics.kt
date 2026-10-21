package app.secretskeeper.secrets

import com.jcraft.jsch.JSchAlgoNegoFailException
import com.jcraft.jsch.SftpException
import java.net.*
import java.security.NoSuchAlgorithmException

/** Fixed categories only. Never expose raw SSH/provider messages, endpoints or credentials. */
class SftpConnectionException(val diagnostic: String, message: String) : IllegalStateException(message)

enum class SftpStage { SETUP, CONNECT, KEY_EXCHANGE, HOST_VERIFIED, AUTHENTICATION, AUTHENTICATED, SFTP_CHANNEL, DIRECTORY }

class SftpTrace {
    var stage = SftpStage.SETUP
    fun event(message: String) {
        when {
            message.startsWith("SSH_MSG_KEXINIT") -> stage = SftpStage.KEY_EXCHANGE
            message.startsWith("SSH_MSG_NEWKEYS") -> stage = SftpStage.HOST_VERIFIED
            message.startsWith("Authentications that can continue:") || message.startsWith("Next authentication method:") -> stage = SftpStage.AUTHENTICATION
            message.startsWith("Authentication succeeded") -> stage = SftpStage.AUTHENTICATED
        }
    }
    fun failure(error: Exception): SftpConnectionException {
        var cause: Throwable? = error
        var reason = "UNKNOWN"
        repeat(8) {
            val current = cause ?: return@repeat
            val classified = when (current) {
                is UnknownHostException -> "DNS"
                is SocketTimeoutException -> "TIMEOUT"
                is NoRouteToHostException -> "NO_ROUTE"
                is ConnectException -> "CONNECTION_REFUSED"
                is ClassNotFoundException, is NoSuchAlgorithmException -> "CRYPTO_UNAVAILABLE"
                is JSchAlgoNegoFailException -> "ALGORITHM_NEGOTIATION"
                is SecurityException -> "DEVICE_PERMISSION"
                is SftpException -> when (current.id) { 2 -> "DIRECTORY_NOT_FOUND"; 3 -> "PERMISSION_DENIED"; else -> "SFTP_PROTOCOL" }
                else -> {
                    // Inspect in memory for classification; never retain, display or log the text.
                    val text = current.message.orEmpty().take(2048).lowercase(java.util.Locale.ROOT)
                    when {
                        text.contains("auth fail") || text.contains("auth cancel") -> "AUTHENTICATION_REJECTED"
                        text.contains("algorithm negotiation fail") -> "ALGORITHM_NEGOTIATION"
                        text.contains("invalid server's version") -> "NOT_SSH"
                        text.contains("timeout") || text.contains("timed out") -> "TIMEOUT"
                        text.contains("connection refused") -> "CONNECTION_REFUSED"
                        text.contains("classnotfoundexception") || text.contains("nosuchalgorithmexception") -> "CRYPTO_UNAVAILABLE"
                        text.contains("session is down") || text.contains("connection is closed") || text.contains("end of io stream") -> "CONNECTION_CLOSED"
                        else -> null
                    }
                }
            }
            if (classified != null) reason = classified
            cause = current.cause
        }
        val guidance = when (reason) {
            "DNS" -> "Server name could not be resolved. Check the host address."
            "TIMEOUT", "NO_ROUTE", "CONNECTION_REFUSED" -> "Server connection failed. Check the host, port, Wi-Fi and server firewall."
            "AUTHENTICATION_REJECTED" -> "SSH login was rejected. Check the username and password or private key."
            "CRYPTO_UNAVAILABLE", "ALGORITHM_NEGOTIATION" -> "SSH cryptographic negotiation failed. Report this diagnostic code; host verification has not been bypassed."
            "DIRECTORY_NOT_FOUND", "PERMISSION_DENIED", "SFTP_PROTOCOL" -> "SFTP directory access failed. Check the backup path and server permissions."
            "NOT_SSH" -> "The port did not provide a valid SSH service."
            else -> "SSH connection failed. Report this diagnostic code to investigate."
        }
        val code = "$stage/$reason"
        return SftpConnectionException(code, "$guidance [SFTP $code]")
    }
}
