package app.secretskeeper.secrets

import org.apache.sshd.server.SshServer
import org.apache.sshd.server.keyprovider.SimpleGeneratorHostKeyProvider
import org.apache.sshd.common.file.virtualfs.VirtualFileSystemFactory
import org.apache.sshd.common.config.keys.KeyUtils
import org.apache.sshd.sftp.server.SftpSubsystemFactory
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class SftpProviderTest {
    @Test fun pinnedSftpRoundTripAndChangedHostKeyRejection() {
        val root = Files.createTempDirectory("secrets-sftp-test-")
        val keys = SimpleGeneratorHostKeyProvider(root.resolve("hostkey")).apply { algorithm = "EC" }
        val server = SshServer.setUpDefaultServer().apply {
            port = 0
            host = "127.0.0.1"
            keyPairProvider = keys
            passwordAuthenticator = org.apache.sshd.server.auth.password.PasswordAuthenticator { user, password, _ -> user == "tester" && password == "test-password" }
            subsystemFactories = listOf(SftpSubsystemFactory.Builder().build())
            fileSystemFactory = VirtualFileSystemFactory(root)
        }
        try {
            server.start()
            val fingerprint = KeyUtils.getFingerPrint(keys.loadKeys(null).first().public)
            val config = JSONObject().put("host", "127.0.0.1").put("port", server.port)
                .put("username", "tester").put("password", "test-password")
                .put("directory", "backups").put("fingerprint", fingerprint)
            val snapshot = Snapshot(123, """{"header":{"id":"test-vault"},"ciphertext":"test-fixture"}""")
            SftpProvider(config).use { provider ->
                provider.put(snapshot.name, snapshot.envelope)
                val files = provider.list()
                assertEquals(1, files.size)
                assertEquals(snapshot.envelope, provider.read(files.single()))
                assertFalse(Files.list(root.resolve("backups")).use { list -> list.anyMatch { it.fileName.toString().startsWith(".upload-") } })
                provider.delete(files.single())
                assertTrue(provider.list().isEmpty())
            }
            config.put("fingerprint", "SHA256:wrong-key")
            try { SftpProvider(config).use {}; fail("Changed host key must not be accepted") } catch (_: Exception) {}
        } finally { server.stop(true); root.toFile().deleteRecursively() }
    }
}
