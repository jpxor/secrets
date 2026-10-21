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
}
