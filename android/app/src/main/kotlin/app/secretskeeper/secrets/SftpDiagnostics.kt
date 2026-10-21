package app.secretskeeper.secrets

import com.jcraft.jsch.JSchAlgoNegoFailException
import com.jcraft.jsch.JSchSessionDisconnectException
import com.jcraft.jsch.SftpException
import java.net.*
import java.security.NoSuchAlgorithmException

/** Fixed categories only. Never expose raw SSH/provider messages, endpoints or credentials. */
class SftpConnectionException(val diagnostic: String, message: String) : IllegalStateException(message)

enum class SftpStage { SETUP, CONNECT, KEY_EXCHANGE, HOST_VERIFIED, AUTHENTICATION, AUTHENTICATED, SFTP_CHANNEL, DIRECTORY, LIST, DOWNLOAD, UPLOAD, DELETE }

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
                is IllegalAccessException, is InstantiationException, is ClassCastException -> "CLIENT_CRYPTO_ERROR"
                is ClassNotFoundException, is NoSuchAlgorithmException -> "CRYPTO_UNAVAILABLE"
                is JSchAlgoNegoFailException -> when (current.algorithmName) {
                    "kex" -> "KEY_EXCHANGE_ALGORITHMS"
                    "server_host_key" -> "HOST_KEY_ALGORITHMS"
                    "cipher.c2s", "cipher.s2c" -> "CIPHER_ALGORITHMS"
                    "mac.c2s", "mac.s2c" -> "MAC_ALGORITHMS"
                    else -> "ALGORITHM_NEGOTIATION"
                }
                is JSchSessionDisconnectException -> "SERVER_DISCONNECTED"
                is SecurityException -> "DEVICE_PERMISSION"
                is SftpException -> when (current.id) { 2 -> "PATH_NOT_FOUND"; 3 -> "PERMISSION_DENIED"; 4 -> "SERVER_FILE_FAILURE"; else -> "SFTP_PROTOCOL" }
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
                        text.contains("invalid privatekey") || text.contains("invalid private key") -> "INVALID_PRIVATE_KEY"
                        text.startsWith("verify: false") -> "SERVER_SIGNATURE_INVALID"
                        stage == SftpStage.SFTP_CHANNEL && text.contains("channel") -> "SFTP_UNAVAILABLE"
                        text.contains("session is down") || text.contains("connection is closed") || text.contains("end of io stream") -> "CONNECTION_CLOSED"
                        else -> null
                    }
                }
            }
            if (classified != null) reason = classified
            cause = current.cause
        }
        val guidance = when (reason) {
            "DNS" -> "Server name could not be resolved. Correct the hostname or try the server's IP address; check your DNS or VPN."
            "TIMEOUT", "NO_ROUTE" -> "Server did not respond. Check the address and port, SSH service, firewall and VPN. A private LAN address requires the same network or a VPN route."
            "CONNECTION_REFUSED" -> "Server refused the connection. Start the SSH service and check its listening port and firewall rules."
            "AUTHENTICATION_REJECTED" -> "SSH login was rejected. Check the username and password or private-key passphrase. On the server, check that this account and authentication method are allowed; check its SSH authentication log."
            "CLIENT_CRYPTO_ERROR", "CRYPTO_UNAVAILABLE" -> "The app could not load an SSH cryptographic implementation. Update Secrets. This is an app compatibility problem; changing your password or server permissions will not fix it."
            "KEY_EXCHANGE_ALGORITHMS", "HOST_KEY_ALGORITHMS", "CIPHER_ALGORITHMS", "MAC_ALGORITHMS", "ALGORITHM_NEGOTIATION" -> "The app and server have no compatible SSH algorithms in this category. Update the app and SSH server; check the server's KexAlgorithms, HostKeyAlgorithms, Ciphers and MACs settings. Do not enable obsolete algorithms or disable host verification."
            "PATH_NOT_FOUND" -> "The SFTP path was not found. Check the directory as seen by this SFTP account; a chroot's / may differ from the server's filesystem root."
            "PERMISSION_DENIED" -> "SFTP access was denied. Check this account's directory ownership, permissions and ACLs. Backups need list, read, create, rename and delete access."
            "SERVER_FILE_FAILURE", "SFTP_PROTOCOL" -> "The SFTP server could not complete the file operation. Check free disk space, account quota, read-only mounts and the SFTP server log."
            "SFTP_UNAVAILABLE" -> "SSH connected but the SFTP channel failed. Enable the server's SFTP subsystem and allow this account to use it; check SSH Match or ForceCommand rules and the server log."
            "INVALID_PRIVATE_KEY" -> "The private key could not be read. Supply a complete supported private key, including its header and footer, and check its passphrase. A public key file cannot be used here."
            "SERVER_SIGNATURE_INVALID" -> "The server's SSH signature could not be verified. Stop and check the server's host-key configuration and SSH log; do not bypass verification."
            "DEVICE_PERMISSION" -> "Android denied the connection. Check the app's network permissions and any device firewall or work-profile restrictions."
            "NOT_SSH" -> "This port did not provide SSH. Use the SSH/SFTP port, not an FTP, FTPS or web port."
            "SERVER_DISCONNECTED", "CONNECTION_CLOSED" -> "The SSH server closed the connection. Check its SSH log at the time of this attempt, account restrictions, connection limits and firewall rules."
            else -> when (stage) {
                SftpStage.KEY_EXCHANGE, SftpStage.HOST_VERIFIED -> "SSH key exchange failed before login. Check the server's SSH log at the time of this attempt and update the app and server. Changing your password will not fix this stage. Keep host verification enabled."
                SftpStage.SFTP_CHANNEL -> "SSH connected but SFTP could not start. Check the server's SFTP subsystem, account restrictions and SSH log."
                SftpStage.SETUP -> "SSH setup failed. Check the host, port and private-key format, if supplied."
                else -> "SSH operation failed. Check the server's SSH/SFTP log at the time of this attempt, network connection and account restrictions."
            }
        }
        val code = "$stage/$reason"
        return SftpConnectionException(code, "$guidance [SFTP $code]")
    }
}
