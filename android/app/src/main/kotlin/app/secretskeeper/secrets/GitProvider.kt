package app.secretskeeper.secrets

import android.content.Context
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.transport.*
import org.eclipse.jgit.transport.ssh.jsch.JschConfigSessionFactory
import org.eclipse.jgit.transport.ssh.jsch.OpenSshConfig
import org.eclipse.jgit.util.FS
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Standard Git wire protocols, not a hosting-provider REST API. */
class GitProvider(cacheDirectory: File, private val config: JSONObject) : RemoteProvider {
    constructor(context: Context, config: JSONObject) : this(context.cacheDir, config)
    private val directory = File(cacheDirectory, "git-${UUID.randomUUID()}")
    private val branch = config.optString("branch", "main")
    private val relative = config.optString("directory", "Secrets").trim('/')
    private val repo: Git
    private val credentials = UsernamePasswordCredentialsProvider(config.optString("username"), config.optString("password"))
    private val transportCallback = org.eclipse.jgit.api.TransportConfigCallback { transport ->
        transport.timeout = 45
        if (transport is SshTransport) {
            transport.sshSessionFactory = object : JschConfigSessionFactory() {
                override fun createDefaultJSch(fs: FS): JSch = secureJsch(config)
                override fun configure(host: OpenSshConfig.Host, session: Session) {
                    session.setConfig("StrictHostKeyChecking", "yes")
                    if (config.optString("password").isNotEmpty()) session.setPassword(config.getString("password"))
                }
            }
        }
    }
    private val folder: File
    init {
        val original = URIish(config.getString("url"))
        val uri = if (original.scheme == "ssh" && original.user.isNullOrEmpty() && config.optString("username").isNotBlank()) original.setUser(config.getString("username")) else original
        val url = uri.toString()
        ensure(uri.scheme in listOf("https", "ssh") && uri.host != null && uri.pass == null) {
            "Use an https:// or ssh:// repository URL without embedded passwords."
        }
        ensure(org.eclipse.jgit.lib.Repository.isValidRefName("refs/heads/$branch")) { "Invalid Git branch." }
        ensure(relative.isNotEmpty() && relative.split('/').none { it == ".." || it == ".git" || it.contains('\\') }) { "Invalid Git backup directory." }
        try {
            val refs = Git.lsRemoteRepository().setRemote(url).setCredentialsProvider(credentials)
                .setTransportConfigCallback(transportCallback).call()
            val existing = refs.any { it.name == "refs/heads/$branch" }
            ensure(existing || refs.isEmpty()) { "Branch does not exist. Create it on the server or use an empty repository." }
            if (existing) {
                repo = Git.cloneRepository().setURI(url).setDirectory(directory).setBranch(branch)
                    .setCloneAllBranches(false).setCredentialsProvider(credentials).setTransportConfigCallback(transportCallback).call()
            } else {
                repo = Git.init().setDirectory(directory).setInitialBranch(branch).call()
                repo.repository.config.apply {
                    setString("remote", "origin", "url", url)
                    setString("remote", "origin", "fetch", "+refs/heads/$branch:refs/remotes/origin/$branch")
                    save()
                }
            }
            folder = File(directory, relative)
            ensure(folder.canonicalPath.startsWith(directory.canonicalPath + File.separator))
            // Never follow symlinks controlled by the remote repository.
            var current = folder
            while (current != directory) {
                ensure(!java.nio.file.Files.isSymbolicLink(current.toPath())) { "Git backup directory must not contain symlinks." }
                current = current.parentFile ?: fail("Invalid repository path.")
            }
            folder.mkdirs()
        } catch (e: Exception) { removeCache(); throw e }
    }
    override fun list(): List<RemoteFile> = Providers.sorted(folder.listFiles()?.filter {
        it.isFile && !java.nio.file.Files.isSymbolicLink(it.toPath())
    }?.map { RemoteFile(it.name, it.name) } ?: emptyList())
    override fun read(file: RemoteFile): String {
        ensure(Providers.isSnapshot(file.locator))
        val target = File(folder, file.locator)
        ensure(!java.nio.file.Files.isSymbolicLink(target.toPath()) && target.length() <= LocalStore.MAX_BYTES)
        return target.readText()
    }
    override fun put(name: String, envelope: String) {
        ensure(Providers.isSnapshot(name))
        val target = File(folder, name)
        ensure(!java.nio.file.Files.isSymbolicLink(target.toPath()))
        target.writeText(envelope)
        repo.add().addFilepattern("$relative/$name").call()
        commitAndPush("Back up encrypted Secrets vault")
    }
    override fun delete(file: RemoteFile) {
        ensure(Providers.isSnapshot(file.locator))
        repo.rm().addFilepattern("$relative/${file.locator}").call()
        commitAndPush("Prune encrypted Secrets snapshot; Git history retained")
    }
    private fun commitAndPush(message: String) {
        repo.commit().setMessage(message).setAuthor("Secrets", "secrets@localhost")
            .setCommitter("Secrets", "secrets@localhost").call()
        val results = repo.push().setRemote("origin").setRefSpecs(RefSpec("refs/heads/$branch:refs/heads/$branch"))
            .setCredentialsProvider(credentials).setTransportConfigCallback(transportCallback).call()
        results.forEach { result -> result.remoteUpdates.forEach { update ->
            ensure(update.status in listOf(RemoteRefUpdate.Status.OK, RemoteRefUpdate.Status.UP_TO_DATE)) {
                "Git push rejected. Remote data was preserved; reconnect or restore before retrying."
            }
        } }
    }
    private fun removeCache() {
        // Git pack files can be read-only on Windows. Never traverse remote-controlled symlinks.
        val root = directory.toPath()
        if (!java.nio.file.Files.exists(root, java.nio.file.LinkOption.NOFOLLOW_LINKS)) return
        java.nio.file.Files.walkFileTree(root, object : java.nio.file.SimpleFileVisitor<java.nio.file.Path>() {
            override fun visitFile(file: java.nio.file.Path, attrs: java.nio.file.attribute.BasicFileAttributes): java.nio.file.FileVisitResult {
                if (!attrs.isSymbolicLink) file.toFile().setWritable(true)
                java.nio.file.Files.delete(file)
                return java.nio.file.FileVisitResult.CONTINUE
            }
            override fun postVisitDirectory(dir: java.nio.file.Path, error: java.io.IOException?): java.nio.file.FileVisitResult {
                if (error != null) throw error
                java.nio.file.Files.delete(dir)
                return java.nio.file.FileVisitResult.CONTINUE
            }
        })
    }
    override fun close() { repo.close(); removeCache() }
}
