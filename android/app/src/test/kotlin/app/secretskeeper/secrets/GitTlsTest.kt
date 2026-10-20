package app.secretskeeper.secrets

import com.sun.net.httpserver.HttpsServer
import com.sun.net.httpserver.HttpsConfigurator
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.file.Files
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException

class GitTlsTest {
    @Test fun httpsGitRejectsUntrustedCertificatesBeforeSendingCredentials() {
        val root = Files.createTempDirectory("secrets-tls-test-")
        val password = "public-test-fixture".toCharArray()
        val store = root.resolve("test-server.p12")
        val requests = AtomicInteger()
        var server: HttpsServer? = null
        try {
            val executable = java.io.File(System.getProperty("java.home"), "bin/keytool" + if (System.getProperty("os.name").orEmpty().startsWith("Windows")) ".exe" else "")
            val process = ProcessBuilder(executable.path, "-genkeypair", "-storetype", "PKCS12", "-keystore", store.toString(),
                "-alias", "test-server", "-keyalg", "RSA", "-keysize", "2048", "-validity", "1", "-dname", "CN=localhost",
                "-ext", "SAN=ip:127.0.0.1", "-storepass", String(password), "-keypass", String(password)).redirectErrorStream(true).start()
            process.inputStream.use { it.readBytes() }
            assertEquals("Test certificate generation", 0, process.waitFor())
            val keyStore = KeyStore.getInstance("PKCS12").apply { Files.newInputStream(store).use { load(it, password) } }
            val keys = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(keyStore, password) }
            val tls = SSLContext.getInstance("TLS").apply { init(keys.keyManagers, null, null) }
            server = HttpsServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
                httpsConfigurator = HttpsConfigurator(tls)
                createContext("/") { exchange -> requests.incrementAndGet(); exchange.sendResponseHeaders(200, -1); exchange.close() }
                start()
            }
            val config = JSONObject().put("url", "https://127.0.0.1:${server.address.port}/vault.git")
                .put("branch", "main").put("directory", "Secrets").put("username", "tester").put("password", "test-token")
            var failure: Exception? = null
            try { GitProvider(root.resolve("cache").toFile().apply { mkdirs() }, config).use {} }
            catch (e: Exception) { failure = e }
            assertNotNull("Self-signed TLS must be rejected", failure)
            assertTrue("Failure must be certificate verification, not a Git protocol error",
                generateSequence(failure as Throwable?) { it.cause }.any { it is SSLHandshakeException })
            assertEquals("Credentials must not be sent over unverified TLS", 0, requests.get())
        } finally { server?.stop(0); password.fill('\u0000'); root.toFile().deleteRecursively() }
    }
}
