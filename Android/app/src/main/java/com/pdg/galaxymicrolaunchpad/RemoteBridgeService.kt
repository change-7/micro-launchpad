package com.pdg.galaxymicrolaunchpad

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.IBinder
import android.os.PowerManager
import android.content.pm.PackageManager
import java.util.Calendar
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

internal fun remoteBridgeServiceStartMode(): Int = Service.START_STICKY

/** Keeps the Mac bridge alive independently of the Compose activity lifecycle. */
class RemoteBridgeService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var preferences: RemoteBridgePreferences
    private lateinit var notificationManager: NotificationManager
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenOffDisconnectRunnable: Runnable? = null
    private var screenReceiverRegistered = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> scheduleScreenOffDisconnect()
                Intent.ACTION_SCREEN_ON -> resumeConnection()
                ACTION_TIMEOUT_CHANGED -> applyCurrentScreenState()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        preferences = RemoteBridgePreferences(this)
        notificationManager = getSystemService(NotificationManager::class.java)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        registerScreenReceiver()
        applyCurrentScreenState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android can recreate this service after reclaiming the process while
        // the screen is off; keep the bridge loop running in that case.
        applyCurrentScreenState()
        return remoteBridgeServiceStartMode()
    }

    override fun onDestroy() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        if (screenReceiverRegistered) unregisterReceiver(screenReceiver)
        screenReceiverRegistered = false
        RemoteBridgeRuntime.client(this).stop()
        releaseNetworkLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerScreenReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(ACTION_TIMEOUT_CHANGED)
        }
        ContextCompat.registerReceiver(this, screenReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        screenReceiverRegistered = true
    }

    private fun resumeConnection() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        preferences.screenOffStartedAtMillis = null
        acquireNetworkLocks()
        RemoteBridgeRuntime.client(this).start()
        updateNotification("Mac bridge active")
    }

    private fun applyCurrentScreenState() {
        when (screenOffConnectionAction(getSystemService(PowerManager::class.java).isInteractive)) {
            ScreenOffConnectionAction.Resume -> resumeConnection()
            ScreenOffConnectionAction.ScheduleDisconnect -> scheduleScreenOffDisconnect()
        }
    }

    private fun scheduleScreenOffDisconnect() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        val now = Calendar.getInstance()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val nowMillis = now.timeInMillis
        val screenOffStartedAt = preferences.screenOffStartedAtMillis ?: nowMillis.also {
            preferences.screenOffStartedAtMillis = it
        }
        if (preferences.isWithinSleepWindow(nowMinutes)) {
            pauseConnection()
            return
        }
        val timeoutMillis = preferences.screenOffTimeoutMillis
        if (timeoutMillis == Long.MAX_VALUE) return
        val remainingTimeout = timeoutMillis - (nowMillis - screenOffStartedAt)
        if (remainingTimeout <= 0L) {
            pauseConnection()
            return
        }
        val delayUntilSleepWindow = millisUntilSleepWindowStart(now, nowMinutes)
        val delay = minOf(remainingTimeout, delayUntilSleepWindow ?: remainingTimeout)
        screenOffDisconnectRunnable = Runnable { pauseConnection() }.also {
            mainHandler.postDelayed(it, delay)
        }
    }

    private fun millisUntilSleepWindowStart(now: Calendar, nowMinutes: Int): Long? {
        if (!preferences.sleepWindowEnabled) return null
        val start = preferences.sleepWindowStartMinutes
        if (preferences.isWithinSleepWindow(nowMinutes)) return 0L
        val minutesUntilStart = if (start > nowMinutes) start - nowMinutes else 24 * 60 - nowMinutes + start
        val nextStart = (now.clone() as Calendar).apply {
            add(Calendar.MINUTE, minutesUntilStart)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return (nextStart.timeInMillis - now.timeInMillis).coerceAtLeast(1_000L)
    }

    private fun pauseConnection() {
        screenOffDisconnectRunnable = null
        RemoteBridgeRuntime.client(this).stop()
        releaseNetworkLocks()
        updateNotification("Paused until the screen turns on")
    }

    private fun acquireNetworkLocks() {
        if (wakeLock?.isHeld == true && multicastLock?.isHeld == true) return
        val powerManager = getSystemService(PowerManager::class.java)
        if (wakeLock?.isHeld != true) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:remote-bridge"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }

        val wifiManager = getSystemService(WifiManager::class.java)
        if (multicastLock?.isHeld != true) {
            multicastLock = wifiManager.createMulticastLock("$packageName:nsd").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseNetworkLocks() {
        wakeLock?.let { lock -> if (lock.isHeld) lock.release() }
        wakeLock = null
        multicastLock?.let { lock -> if (lock.isHeld) lock.release() }
        multicastLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Mac bridge connection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the Micro Launchpad connection available while the screen is off."
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun updateNotification(message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        notificationManager.notify(NOTIFICATION_ID, buildNotification(message))
    }

    private fun buildNotification(): Notification {
        return buildNotification("Mac bridge active")
    }

    private fun buildNotification(message: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_micro)
            .setContentTitle("Micro Launchpad")
            .setContentText(message)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        const val ACTION_START = "com.pdg.galaxymicrolaunchpad.START_REMOTE_BRIDGE"
        const val ACTION_TIMEOUT_CHANGED = "com.pdg.galaxymicrolaunchpad.REMOTE_BRIDGE_TIMEOUT_CHANGED"
        private const val CHANNEL_ID = "mac_bridge_connection"
        private const val NOTIFICATION_ID = 43123
    }
}
