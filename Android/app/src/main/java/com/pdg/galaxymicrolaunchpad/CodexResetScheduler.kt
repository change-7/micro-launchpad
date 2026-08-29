package com.pdg.galaxymicrolaunchpad

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import kotlin.math.roundToLong

internal class CodexResetScheduler(context: Context) {
    companion object {
        const val ACTION_RESET_WAKE = "com.pdg.galaxymicrolaunchpad.ACTION_RESET_WAKE"
        const val EXTRA_REVEAL_CODEX = "com.pdg.galaxymicrolaunchpad.EXTRA_REVEAL_CODEX"
        private const val REQUEST_CODE = 5_001
    }

    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)
    private var scheduledAtMillis: Long? = null

    fun scheduleFiveHourReset(epochSeconds: Double?) {
        val resetMillis = epochSeconds
            ?.takeIf { it.isFinite() && it > 0 }
            ?.times(1_000.0)
            ?.roundToLong()
            ?: return
        if (resetMillis <= System.currentTimeMillis() || scheduledAtMillis == resetMillis) return

        runCatching {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                resetMillis,
                pendingIntent()
            )
            scheduledAtMillis = resetMillis
        }
    }

    private fun pendingIntent(): PendingIntent {
        // Launch the activity directly from AlarmManager. This avoids Android's
        // background-activity-start restrictions when a receiver runs while the
        // phone is asleep or the app is on another page.
        val intent = Intent(appContext, MainActivity::class.java).apply {
            action = ACTION_RESET_WAKE
            putExtra(EXTRA_REVEAL_CODEX, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            appContext,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

}

internal class CodexResetReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != CodexResetScheduler.ACTION_RESET_WAKE) return
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = CodexResetScheduler.ACTION_RESET_WAKE
            putExtra(CodexResetScheduler.EXTRA_REVEAL_CODEX, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(launchIntent)
    }
}
