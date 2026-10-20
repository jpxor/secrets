package app.secretskeeper.secrets

import org.junit.Assert.*
import org.junit.Test

class BackupEngineTest {
    private class Remote : RemoteProvider {
        val data = sortedMapOf<String, String>()
        var fail = false
        var writes = 0
        override fun list() = Providers.sorted(data.keys.map { RemoteFile(it, it) })
        override fun read(file: RemoteFile) = data.getValue(file.name)
        override fun put(name: String, envelope: String) { if (fail) error("Network interrupted"); data[name] = envelope; writes++ }
        override fun delete(file: RemoteFile) { data.remove(file.name) }
    }
    private fun snapshot(sequence: Long, id: String = "vault") = Snapshot(sequence, """{"header":{"id":"$id"},"encrypted":"$sequence"}""")

    @Test fun interruptedUploadKeepsPreviousBackupAndRetryIsIdempotent() {
        val remote = Remote()
        val old = snapshot(1)
        val next = snapshot(2)
        remote.data[old.name] = old.envelope
        var acknowledged = false
        remote.fail = true
        try { BackupEngine.upload(remote, next, old.name) { acknowledged = true }; fail("Expected failed upload") } catch (_: IllegalStateException) {}
        assertFalse(acknowledged)
        assertEquals(old.envelope, remote.data[old.name])
        remote.fail = false
        BackupEngine.upload(remote, next, old.name) { acknowledged = true }
        assertTrue(acknowledged)
        // Simulates process death after upload but before the local acknowledgment committed.
        BackupEngine.upload(remote, next, old.name) {}
        assertEquals(1, remote.writes)
    }

    @Test fun staleOrForeignUploadsNeverOverwriteRemoteData() {
        val remote = Remote()
        val newest = snapshot(3)
        remote.data[newest.name] = newest.envelope
        try { BackupEngine.upload(remote, snapshot(2), snapshot(1).name) {}; fail("Expected conflict") } catch (_: IllegalStateException) {}
        try { BackupEngine.upload(remote, snapshot(4, "other"), newest.name) {}; fail("Expected foreign vault rejection") } catch (_: IllegalStateException) {}
        assertEquals(0, remote.writes)
        assertEquals(newest.envelope, remote.data[newest.name])
    }
}
