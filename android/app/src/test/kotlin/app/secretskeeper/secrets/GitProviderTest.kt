package app.secretskeeper.secrets

import org.apache.sshd.server.SshServer
import org.apache.sshd.server.Environment
import org.apache.sshd.server.ExitCallback
import org.apache.sshd.server.channel.ChannelSession
import org.apache.sshd.server.command.Command
import org.apache.sshd.server.command.CommandFactory
import org.apache.sshd.server.keyprovider.SimpleGeneratorHostKeyProvider
import org.apache.sshd.common.config.keys.KeyUtils
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.transport.UploadPack
import org.eclipse.jgit.transport.ReceivePack
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import kotlin.concurrent.thread

class GitProviderTest {
    @Test fun genericGitSshCanCreatePushCloneAndRestoreWithoutHostingApi() {
        val root = Files.createTempDirectory("secrets-git-test-")
        val bare = root.resolve("vault.git").toFile()
        Git.init().setDirectory(bare).setBare(true).setInitialBranch("main").call().close()
        val cache = root.resolve("cache").toFile().apply { mkdirs() }
        val keys = SimpleGeneratorHostKeyProvider(root.resolve("hostkey")).apply { algorithm = "EC" }
        val server = SshServer.setUpDefaultServer().apply {
            host = "127.0.0.1"; port = 0; keyPairProvider = keys
            passwordAuthenticator = org.apache.sshd.server.auth.password.PasswordAuthenticator { u, p, _ -> u == "tester" && p == "test-password" }
            commandFactory = CommandFactory { _, command ->
                check(command.startsWith("git-upload-pack ") || command.startsWith("git-receive-pack "))
                check(command.substringAfter(' ').trim().trim('\'').trimStart('/') == "vault.git")
                object : Command {
                    lateinit var input: InputStream
                    lateinit var output: OutputStream
                    lateinit var errors: OutputStream
                    lateinit var callback: ExitCallback
                    override fun setInputStream(value: InputStream) { input = value }
                    override fun setOutputStream(value: OutputStream) { output = value }
                    override fun setErrorStream(value: OutputStream) { errors = value }
                    override fun setExitCallback(value: ExitCallback) { callback = value }
                    override fun start(channel: ChannelSession, env: Environment) {
                        thread(isDaemon = true) {
                            try {
                                Git.open(bare).use { git ->
                                    if (command.startsWith("git-upload-pack")) UploadPack(git.repository).upload(input, output, errors)
                                    else ReceivePack(git.repository).receive(input, output, errors)
                                }
                                output.flush(); callback.onExit(0)
                            } catch (_: Exception) { callback.onExit(1) }
                        }
                    }
                    override fun destroy(channel: ChannelSession) { input.close(); output.close(); errors.close() }
                }
            }
        }
        try {
            server.start()
            val config = JSONObject().put("url", "ssh://tester@127.0.0.1:${server.port}/vault.git")
                .put("branch", "main").put("directory", "Secrets").put("username", "tester")
                .put("password", "test-password").put("fingerprint", KeyUtils.getFingerPrint(keys.loadKeys(null).first().public))
            val snapshot = Snapshot(100, """{"header":{"id":"test-vault"},"ciphertext":"test-fixture"}""")
            GitProvider(cache, config).use { provider ->
                assertTrue(provider.list().isEmpty())
                provider.put(snapshot.name, snapshot.envelope)
            }
            GitProvider(cache, config).use { provider ->
                assertEquals(snapshot.envelope, provider.read(provider.list().single()))
            }
            assertEquals(0, cache.listFiles()!!.size)
        } finally { server.stop(true); root.toFile().deleteRecursively() }
    }
}
