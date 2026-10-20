package app.secretskeeper.secrets

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class BackupWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = providerLock.withLock {
        val store = LocalStore(applicationContext)
        try {
            val config = store.config() ?: return@withLock Result.success()
            val snapshot = store.snapshot() ?: return@withLock Result.success()
            if (!(store.status()["pending"] as Boolean)) return@withLock Result.success()
            Providers.open(applicationContext, config, store::setConfig).use { provider ->
                BackupEngine.upload(provider, snapshot, store.remoteName()) { store.acknowledged(snapshot) }
            }
            Result.success()
        } catch (e: Exception) {
            // Provider errors are sanitized where possible; never persist HTTP bodies or credentials.
            store.error(safeError(e))
            Result.retry()
        } catch (_: LinkageError) {
            store.error("This backup transport is incompatible with this Android runtime. Use encrypted export and report the device/Android version.")
            Result.failure()
        }
    }
    companion object {
        val providerLock = ReentrantLock()
        private val constraints get() = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        fun schedule(context: Context, immediate: Boolean = false) {
            val manager = WorkManager.getInstance(context)
            manager.enqueueUniquePeriodicWork("secrets.reconcile", ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<BackupWorker>(15, TimeUnit.MINUTES).setConstraints(constraints).build())
            manager.enqueueUniqueWork("secrets.backup", if (immediate) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.APPEND_OR_REPLACE,
                OneTimeWorkRequestBuilder<BackupWorker>().setConstraints(constraints)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build())
        }
        fun safeError(e: Exception): String {
            var cause: Throwable? = e
            repeat(8) {
                if (cause is SecretsException) return cause.message.orEmpty().take(300)
                cause = cause?.cause
            }
            return "Operation failed (${e.javaClass.simpleName}). Check connectivity, credentials, device storage and provider setup."
        }
    }
}
