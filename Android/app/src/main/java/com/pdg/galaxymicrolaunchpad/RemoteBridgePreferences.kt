package com.pdg.galaxymicrolaunchpad

import android.content.Context

internal data class ScreenOffConnectionOption(
    val key: String,
    val label: String,
    val timeoutMillis: Long
)

internal const val MinScreenOffTimeoutMinutes = 10
internal const val MaxScreenOffTimeoutMinutes = 12 * 60
internal const val ScreenOffTimeoutStepMinutes = 10
internal const val DefaultScreenOffConnectionOptionKey = "30m"
internal const val IdleBlackoutTimeoutMillis = 2 * 60 * 1_000L
internal const val DefaultIdleBlackoutEnabled = false

internal val screenOffConnectionOptions =
    (MinScreenOffTimeoutMinutes..MaxScreenOffTimeoutMinutes step ScreenOffTimeoutStepMinutes)
        .map { minutes -> ScreenOffConnectionOption("${minutes}m", "${minutes}분", minutes * 60 * 1_000L) } +
        ScreenOffConnectionOption("always", "계속 유지", Long.MAX_VALUE)

internal enum class ScreenOffConnectionAction {
    Resume,
    ScheduleDisconnect
}

internal fun screenOffConnectionAction(isInteractive: Boolean): ScreenOffConnectionAction {
    return if (isInteractive) ScreenOffConnectionAction.Resume else ScreenOffConnectionAction.ScheduleDisconnect
}

internal class RemoteBridgePreferences(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    var screenOffOptionKey: String
        get() = preferences.getString(KEY_SCREEN_OFF_OPTION, DefaultScreenOffConnectionOptionKey)
            ?.takeIf(::isValidScreenOffOptionKey)
            ?: DefaultScreenOffConnectionOptionKey
        set(value) {
            if (isValidScreenOffOptionKey(value)) {
                preferences.edit().putString(KEY_SCREEN_OFF_OPTION, value).apply()
            }
        }

    val screenOffTimeoutMillis: Long
        get() = screenOffConnectionOption(screenOffOptionKey).timeoutMillis

    var sleepWindowEnabled: Boolean
        get() = preferences.getBoolean(KEY_SLEEP_WINDOW_ENABLED, false)
        set(value) { preferences.edit().putBoolean(KEY_SLEEP_WINDOW_ENABLED, value).apply() }

    var idleBlackoutEnabled: Boolean
        get() = preferences.getBoolean(KEY_IDLE_BLACKOUT_ENABLED, DefaultIdleBlackoutEnabled)
        set(value) { preferences.edit().putBoolean(KEY_IDLE_BLACKOUT_ENABLED, value).apply() }

    var sleepWindowStartMinutes: Int
        get() = preferences.getInt(KEY_SLEEP_WINDOW_START, 23 * 60)
        set(value) { preferences.edit().putInt(KEY_SLEEP_WINDOW_START, value.coerceIn(0, 23 * 60 + 59)).apply() }

    var sleepWindowEndMinutes: Int
        get() = preferences.getInt(KEY_SLEEP_WINDOW_END, 7 * 60)
        set(value) { preferences.edit().putInt(KEY_SLEEP_WINDOW_END, value.coerceIn(0, 23 * 60 + 59)).apply() }

    var screenOffStartedAtMillis: Long?
        get() = preferences.getLong(KEY_SCREEN_OFF_STARTED_AT, -1L).takeIf { it >= 0L }
        set(value) {
            preferences.edit().putLong(KEY_SCREEN_OFF_STARTED_AT, value ?: -1L).apply()
        }

    fun isWithinSleepWindow(nowMinutes: Int): Boolean {
        return isWithinSleepWindow(
            enabled = sleepWindowEnabled,
            startMinutes = sleepWindowStartMinutes,
            endMinutes = sleepWindowEndMinutes,
            nowMinutes = nowMinutes
        )
    }

    companion object {
        private const val PREFERENCES_NAME = "remote_bridge_preferences"
        private const val KEY_SCREEN_OFF_OPTION = "screen_off_option"
        private const val KEY_SLEEP_WINDOW_ENABLED = "sleep_window_enabled"
        private const val KEY_IDLE_BLACKOUT_ENABLED = "idle_blackout_enabled"
        private const val KEY_SLEEP_WINDOW_START = "sleep_window_start"
        private const val KEY_SLEEP_WINDOW_END = "sleep_window_end"
        private const val KEY_SCREEN_OFF_STARTED_AT = "screen_off_started_at"
    }
}

internal fun shouldEnterIdleBlackout(
    enabled: Boolean,
    nowElapsedMillis: Long,
    lastInteractionElapsedMillis: Long,
    timeoutMillis: Long = IdleBlackoutTimeoutMillis
): Boolean {
    if (!enabled || timeoutMillis <= 0L) return false
    return nowElapsedMillis - lastInteractionElapsedMillis >= timeoutMillis
}

internal fun screenOffConnectionOption(key: String): ScreenOffConnectionOption {
    if (key == "always") return ScreenOffConnectionOption("always", "계속 유지", Long.MAX_VALUE)
    val minutes = key.removeSuffix("m").toIntOrNull()
        ?.takeIf { it in MinScreenOffTimeoutMinutes..MaxScreenOffTimeoutMinutes && it % ScreenOffTimeoutStepMinutes == 0 }
        ?: DefaultScreenOffConnectionOptionKey.removeSuffix("m").toInt()
    return ScreenOffConnectionOption("${minutes}m", "${minutes}분", minutes * 60 * 1_000L)
}

private fun isValidScreenOffOptionKey(key: String): Boolean {
    return key == "always" || screenOffConnectionOption(key).key == key
}

internal fun isWithinSleepWindow(
    enabled: Boolean,
    startMinutes: Int,
    endMinutes: Int,
    nowMinutes: Int
): Boolean {
    if (!enabled) return false
    return if (startMinutes <= endMinutes) {
        nowMinutes in startMinutes until endMinutes
    } else {
        nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}
