package com.pdg.galaxymicrolaunchpad

import android.media.RingtoneManager

internal const val CodexCompletionWakeDurationMillis = 5_000L

internal fun shouldWakeForCodex(isInteractive: Boolean): Boolean = !isInteractive

internal fun shouldWakeForCodexRunningTransition(
    previousActivity: String?,
    currentActivity: String,
    reconnectReveal: Boolean = false
): Boolean {
    return normalizeRemoteActivity(currentActivity) == "running" &&
        (previousActivity == null || normalizeRemoteActivity(previousActivity) != "running" || reconnectReveal)
}

/** Kept as a compatibility wrapper for the completion-specific tests/callers. */
internal fun shouldWakeForCodexCompletion(isInteractive: Boolean): Boolean = shouldWakeForCodex(isInteractive)

internal fun completionNotificationSoundType(): Int = RingtoneManager.TYPE_NOTIFICATION
