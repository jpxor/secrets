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
    @Test fun hostTrustRequiresApprovalBeforeAuthenticationAndRejectsChangedKeys() {
        val root = Files.createTempDirectory("secrets-sftp-trust-")
        val keyGenerator = java.security.KeyPairGenerator.getInstance("EC").apply { initialize(256) }
        val firstKey = keyGenerator.generateKeyPair()
        val secondKey = keyGenerator.generateKeyPair()
        var passwordAttempts = 0
        var activeKey = firstKey
        val server = SshServer.setUpDefaultServer().apply {
            port = 0
            host = "127.0.0.1"
            keyPairProvider = org.apache.sshd.common.keyprovider.KeyPairProvider { _ -> listOf(activeKey) }
            passwordAuthenticator = org.apache.sshd.server.auth.password.PasswordAuthenticator { user, password, _ ->
                passwordAttempts++; user == "tester" && password == "test-password"
            }
            subsystemFactories = listOf(SftpSubsystemFactory.Builder().build())
            fileSystemFactory = VirtualFileSystemFactory(root)
        }
        try {
            server.start()
            val config = JSONObject().put("type", "SFTP").put("host", "127.0.0.1").put("port", server.port)
                .put("username", "tester").put("password", "test-password").put("directory", "backups")
            fun challenge(): SshHostKeyException {
                try { SftpProvider(config).use {}; fail("Untrusted key must reject the connection") }
                catch (e: SshHostKeyException) { return e }
                throw AssertionError("Missing host challenge")
            }
            val first = challenge()
            assertEquals(KeyUtils.getFingerPrint(firstKey.public), first.fingerprint)
            assertEquals("", first.previousFingerprint)
            assertEquals(0, passwordAttempts)
            assertFalse(Files.exists(root.resolve("backups")))
            config.put("fingerprint", first.fingerprint)
            SftpProvider(config).use { assertTrue(it.list().isEmpty()) }
            assertEquals(1, passwordAttempts)
            activeKey = secondKey
            val changed = challenge()
            assertEquals(first.fingerprint, changed.previousFingerprint)
            assertEquals(KeyUtils.getFingerPrint(secondKey.public), changed.fingerprint)
            assertEquals(1, passwordAttempts)
            config.put("fingerprint", changed.fingerprint)
            SftpProvider(config).use { assertTrue(it.list().isEmpty()) }
            assertEquals(2, passwordAttempts)
        } finally { server.stop(true); root.toFile().deleteRecursively() }
    }

    @Test fun savedTrustIsScopedToTheExactHostAndPort() {
        val saved = JSONObject().put("type", "SFTP").put("host", "server.local").put("port", 2222).put("fingerprint", "saved-key")
        fun request(host: String, port: Int) = JSONObject().put("type", "SFTP").put("host", host).put("port", port)
        val same = request("SERVER.LOCAL", 2222)
        SshHostTrust.reuseSavedPin(same, saved)
        assertEquals("saved-key", same.getString("fingerprint"))
        for (different in listOf(request("other.local", 2222), request("server.local", 22))) {
            SshHostTrust.reuseSavedPin(different, saved)
            assertFalse(different.has("fingerprint"))
        }
        val approved = request("server.local", 2222).put("fingerprint", "explicit-new-key")
        SshHostTrust.reuseSavedPin(approved, saved)
        assertEquals("explicit-new-key", approved.getString("fingerprint"))
    }

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
