package ir.honarmardomi.tamasyar

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/** Background checks can be deferred by Android battery optimization. */
class TamasUpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        if (!TamasPreferences(applicationContext).autoUpdates) return Result.success()
        return if (TamasUpdater.backgroundCheck(applicationContext))
            Result.success() else Result.retry()
    }

    companion object {
        private const val WORK = "tamasyar-official-update-check"
        fun configure(context: Context) {
            val wm = WorkManager.getInstance(context.applicationContext)
            if (!TamasPreferences(context).autoUpdates) {
                wm.cancelUniqueWork(WORK)
                return
            }
            val request = PeriodicWorkRequestBuilder<TamasUpdateWorker>(12, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            wm.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
