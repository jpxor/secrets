package app.secretskeeper.secrets

import org.json.JSONObject

/** No Android scheduler dependencies: reliability policy is tested on the JVM. */
object BackupEngine {
    fun upload(provider: RemoteProvider, snapshot: Snapshot, expectedRemote: String?, acknowledge: () -> Unit) {
        val before = provider.list()
        val newest = before.firstOrNull()
        if (newest != null) {
            val remoteText = provider.read(newest)
            val remoteId = runCatching { JSONObject(remoteText).getJSONObject("header").getString("id") }.getOrNull()
            ensure(remoteId == snapshot.id || (remoteId == null && newest.name == expectedRemote)) {
                "Destination contains a different vault. Restore it or select an empty destination."
            }
            ensure(newest.name == expectedRemote || newest.name == snapshot.name) {
                "Remote backup changed outside this installation. Restore or reconnect before uploading."
            }
        } else ensure(expectedRemote == null) { "Remote backup disappeared. Reconnect to approve creating a new backup." }
        if (newest?.name != snapshot.name) provider.put(snapshot.name, snapshot.envelope)
        val after = provider.list()
        val saved = after.firstOrNull { it.name == snapshot.name } ?: fail("Upload has not appeared on the provider; retrying.")
        ensure(provider.read(saved) == snapshot.envelope) { "Uploaded backup did not verify; previous snapshots were preserved." }
        acknowledge()
        // Retention is secondary to a verified backup. A pruning failure must not invalidate success.
        after.drop(5).forEach { old -> try { provider.delete(old) } catch (_: Exception) {} }
    }
}
