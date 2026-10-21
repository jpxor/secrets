package app.secretskeeper.secrets

import com.jcraft.jsch.JSchException
import com.jcraft.jsch.SftpException
import org.junit.Assert.*
import org.junit.Test

class SftpDiagnosticsTest {
    @Test fun diagnosticCategoriesNeverExposeProviderTextOrCredentials() {
        val privateText = "synthetic-password-and-private-provider-text"
        val trace = SftpTrace()
        trace.event("Next authentication method: password $privateText")
        val denied = trace.failure(JSchException("Auth fail $privateText"))
        assertEquals("AUTHENTICATION/AUTHENTICATION_REJECTED", denied.diagnostic)
        assertTrue(denied.message!!.contains("login was rejected"))
        assertFalse(denied.message!!.contains(privateText))
        assertNull(denied.cause)
        val unknown = trace.failure(JSchException(privateText))
        assertEquals("AUTHENTICATION/UNKNOWN", unknown.diagnostic)
        assertFalse(unknown.message!!.contains(privateText))
    }

    @Test fun nestedTransportAndCryptoFailuresStayDistinctFromLoginFailures() {
        val trace = SftpTrace().apply { stage = SftpStage.CONNECT }
        assertEquals("CONNECT/DNS", trace.failure(JSchException("private host", java.net.UnknownHostException())).diagnostic)
        assertEquals("CONNECT/TIMEOUT", trace.failure(JSchException("private host", java.net.SocketTimeoutException())).diagnostic)
        trace.event("SSH_MSG_KEXINIT sent")
        assertEquals("KEY_EXCHANGE/CRYPTO_UNAVAILABLE", trace.failure(JSchException("private algorithm", ClassNotFoundException())).diagnostic)
        trace.stage = SftpStage.DIRECTORY
        val denied = trace.failure(SftpException(3, "private directory"))
        assertEquals("DIRECTORY/PERMISSION_DENIED", denied.diagnostic)
        assertFalse(denied.message!!.contains("private directory"))
    }

    @Test fun appPackagingErrorsDoNotTellUsersToChangeTheirServer() {
        val trace = SftpTrace().apply { stage = SftpStage.KEY_EXCHANGE }
        val failure = trace.failure(JSchException("synthetic private detail", IllegalAccessException("synthetic class detail")))
        assertEquals("KEY_EXCHANGE/CLIENT_CRYPTO_ERROR", failure.diagnostic)
        assertTrue(failure.message!!.contains("Update Secrets"))
        assertFalse(failure.message!!.contains("synthetic"))
        val unknown = trace.failure(JSchException("unrecognized private detail"))
        assertTrue(unknown.message!!.contains("server's SSH log"))
        assertTrue(unknown.message!!.contains("before login"))
        assertFalse(unknown.message!!.contains("Report this"))
    }

    @Test fun serverAlgorithmFailuresIdentifyTheConfigurationCategoryWithoutEchoingProposals() {
        val constructor = com.jcraft.jsch.JSchAlgoNegoFailException::class.java
            .getDeclaredConstructor(Int::class.javaPrimitiveType, String::class.java, String::class.java)
            .apply { isAccessible = true }
        val trace = SftpTrace().apply { stage = SftpStage.KEY_EXCHANGE }
        for ((index, reason) in listOf(0 to "KEY_EXCHANGE_ALGORITHMS", 1 to "HOST_KEY_ALGORITHMS", 2 to "CIPHER_ALGORITHMS", 4 to "MAC_ALGORITHMS")) {
            val failure = trace.failure(constructor.newInstance(index, "private client proposal", "private server proposal"))
            assertEquals("KEY_EXCHANGE/$reason", failure.diagnostic)
            assertTrue(failure.message!!.contains("server's KexAlgorithms"))
            assertFalse(failure.message!!.contains("private"))
        }
    }

    @Test fun fileAndSubsystemFailuresExplainSelfServiceChecks() {
        val trace = SftpTrace().apply { stage = SftpStage.UPLOAD }
        val quota = trace.failure(SftpException(4, "private server response"))
        assertEquals("UPLOAD/SERVER_FILE_FAILURE", quota.diagnostic)
        assertTrue(quota.message!!.contains("quota"))
        trace.stage = SftpStage.DIRECTORY
        assertTrue(trace.failure(SftpException(2, "private path")).message!!.contains("chroot"))
        trace.stage = SftpStage.SFTP_CHANNEL
        assertTrue(trace.failure(JSchException("failed to send channel request")).message!!.contains("SFTP subsystem"))
    }
}
