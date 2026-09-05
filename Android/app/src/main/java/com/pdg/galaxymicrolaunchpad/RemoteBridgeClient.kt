package com.pdg.galaxymicrolaunchpad

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.UUID
import java.util.concurrent.Executors

/** App-scoped owner shared by the foreground service and the visible activity. */
internal object RemoteBridgeRuntime {
    @Volatile private var sharedClient: RemoteBridgeClient? = null

    fun client(context: Context): RemoteBridgeClient {
        return sharedClient ?: synchronized(this) {
            sharedClient ?: RemoteBridgeClient(context.applicationContext).also { sharedClient = it }
        }
    }
}

enum class RemoteConnectionState {
    Disconnected,
    Searching,
    Connecting,
    Connected
}

internal fun shouldDisconnectAfterReadTimeout(consecutiveTimeouts: Int): Boolean = consecutiveTimeouts >= 2

internal data class RemoteApproval(
    val title: String,
    val detail: String
)

class RemoteBridgeClient(context: Context) {
    companion object {
        private const val SERVICE_TYPE = "_micro-launchpad._tcp."
        private const val CONNECT_TIMEOUT_MS = 2_000
        private const val READ_TIMEOUT_MS = 5_000
        private const val RETRY_DELAY_MS = 3_000L
    }

    private val appContext = context.applicationContext
    private val nsdManager = appContext.getSystemService(NsdManager::class.java)
    private val executor = Executors.newSingleThreadExecutor()
    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val resetScheduler = CodexResetScheduler(appContext)
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var socket: Socket? = null
    private var writer: OutputStreamWriter? = null
    private var started = false
    @Volatile private var lastActivity: String? = null
    @Volatile private var lastCompletionEventId: Int? = null
    @Volatile private var hasReceivedRemoteState = false
    /** Set when a reconnect may replay the same active state without a transition. */
    @Volatile private var forceCodexRevealAfterReconnect = false
    // Usage values are optional on the wire. Keep a transport-level cache so
    // an activity-only update cannot blank values that were already received.
    @Volatile private var cachedUsedPercent: Int? = null
    @Volatile private var cachedRemainingPercent: Int? = null
    @Volatile private var cachedFiveHourRemainingPercent: Int? = null
    @Volatile private var cachedResetsAt: Double? = null
    @Volatile private var cachedFiveHourResetsAt: Double? = null
    private val iconBitmapCache = mutableMapOf<String, DecodedSmartphoneIcon>()
    private var smartphoneIconAssets = JSONObject()
    private var lastStateObject: JSONObject? = null

    /** Called on the main thread when a Codex task completion is observed. */
    var onCodexCompletion: (() -> Unit)? = null
    /** Called on the main thread when Codex enters running state. */
    var onCodexRunning: (() -> Unit)? = null

    var codexRevealEventId by mutableStateOf(0)
    internal var codexRevealReason by mutableStateOf(CodexRevealReason.Running)
        private set

    var connectionState by mutableStateOf(RemoteConnectionState.Disconnected)
        private set
    var codexConnected by mutableStateOf(false)
        private set
    var activity by mutableStateOf("idle")
        private set
    var message by mutableStateOf("Mac을 찾는 중…")
        private set
    var commandSucceeded by mutableStateOf<Boolean?>(null)
        private set
    var usedPercent by mutableStateOf<Int?>(null)
        private set
    var remainingPercent by mutableStateOf<Int?>(null)
        private set
    var fiveHourRemainingPercent by mutableStateOf<Int?>(null)
        private set
    var resetsAt by mutableStateOf<Double?>(null)
        private set
    var fiveHourResetsAt by mutableStateOf<Double?>(null)
        private set
    internal var pendingApproval by mutableStateOf<RemoteApproval?>(null)
        private set
    internal var activeSessionCount by mutableStateOf(0)
        private set
    internal var smartphonePages by mutableStateOf(buttonPages)
        private set

    fun start() {
        if (started) return
        started = true
        discover()
    }

    fun stop() {
        hasReceivedRemoteState = false
        forceCodexRevealAfterReconnect = false
        started = false
        discoveryListener?.let { listener ->
            runCatching { nsdManager.stopServiceDiscovery(listener) }
        }
        discoveryListener = null
        executor.execute { socket?.close() }
        socket = null
        writer = null
        clearRemoteState("Mac 연결 해제됨")
        setConnection(RemoteConnectionState.Disconnected)
    }

    private fun discover() {
        if (!started) return
        setConnection(RemoteConnectionState.Searching)
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        if (started && connectionState != RemoteConnectionState.Connected) {
                            discoveryListener?.let { listener ->
                                runCatching { nsdManager.stopServiceDiscovery(listener) }
                            }
                            connect(resolved)
                        }
                    }

                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
                })
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                setConnection(RemoteConnectionState.Disconnected)
                retryDiscovery()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }
        discoveryListener = listener
        runCatching {
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        }.onFailure {
            discoveryListener = null
            setConnection(RemoteConnectionState.Disconnected)
            retryDiscovery()
        }
    }

    private fun connect(serviceInfo: NsdServiceInfo) {
        setConnection(RemoteConnectionState.Connecting)
        executor.execute {
            try {
                val target = Socket()
                target.connect(InetSocketAddress(serviceInfo.host, serviceInfo.port), CONNECT_TIMEOUT_MS)
                target.soTimeout = READ_TIMEOUT_MS
                socket = target
                writer = OutputStreamWriter(target.getOutputStream(), Charsets.UTF_8)
                writer?.append("{\"type\":\"hello\",\"protocolVersion\":1}\n")
                writer?.flush()
                setConnection(RemoteConnectionState.Connected)
                readLoop(target)
            } catch (_: Exception) {
                setConnection(RemoteConnectionState.Disconnected)
            } finally {
                runCatching { socket?.close() }
                socket = null
                writer = null
                iconBitmapCache.clear()
                smartphoneIconAssets = JSONObject()
                lastStateObject = null
                if (started && hasReceivedRemoteState) {
                    // Make the first replayed active state reveal Codex again.
                    forceCodexRevealAfterReconnect = true
                }
                // Keep an active Codex state across a transient bridge
                // reconnect. Clearing it here makes the phone stop its
                // running motion during a short read timeout, even though
                // the Mac will replay the authoritative state on reconnect.
                preserveActiveStateDuringReconnect()
                if (started) {
                    setConnection(RemoteConnectionState.Disconnected)
                    retryDiscovery()
                }
            }
        }
    }

    private fun readLoop(target: Socket) {
        val reader = BufferedReader(InputStreamReader(target.getInputStream(), Charsets.UTF_8))
        var consecutiveTimeouts = 0
        while (started && !target.isClosed) {
            try {
                val line = reader.readLine() ?: break
                consecutiveTimeouts = 0
                parseState(line)
            } catch (_: SocketTimeoutException) {
                consecutiveTimeouts += 1
                if (shouldDisconnectAfterReadTimeout(consecutiveTimeouts)) break
                val currentWriter = writer ?: break
                synchronized(currentWriter) {
                    currentWriter.append("{\"type\":\"hello\",\"protocolVersion\":1}\n")
                    currentWriter.flush()
                }
            }
        }
    }

    private fun parseState(line: String) {
        runCatching {
            val state = JSONObject(line)
            if (state.optString("type") == "commandResult") {
                val succeeded = state.optBoolean("success", false)
                val resultMessage = state.optString("message", "Mac 명령 처리 완료")
                mainHandler.post {
                    commandSucceeded = succeeded
                    message = resultMessage
                }
                return
            }
            if (state.optString("type") == "smartphoneIconAssets") {
                smartphoneIconAssets = state.optJSONObject("assets") ?: JSONObject()
                lastStateObject?.let { currentState ->
                    parseSmartphonePages(currentState, iconBitmapCache, smartphoneIconAssets)?.let { refreshedPages ->
                        mainHandler.post { smartphonePages = refreshedPages }
                    }
                }
                return
            }
            if (state.optString("type") != "state") return
            hasReceivedRemoteState = true
            val nextUsed = mergeRemoteUsageInt(state, "usedPercent", cachedUsedPercent)
            val nextRemaining = mergeRemoteUsageInt(state, "remainingPercent", cachedRemainingPercent)
            val nextFiveHourRemaining = mergeRemoteUsageInt(state, "fiveHourRemainingPercent", cachedFiveHourRemainingPercent)
            // State refreshes may omit activity while the Mac is busy doing
            // file/tool work. Do not turn that transiently incomplete packet
            // into idle and hide the running motion.
            val nextActivity = if (state.has("activity")) {
                normalizeRemoteActivity(state.optString("activity"))
            } else {
                lastActivity ?: "idle"
            }
            if (state.has("smartphoneIconAssets")) {
                smartphoneIconAssets = state.optJSONObject("smartphoneIconAssets") ?: JSONObject()
            }
            lastStateObject = state
            val nextSmartphonePages = parseSmartphonePages(state, iconBitmapCache, smartphoneIconAssets)
            val nextApproval = parseRemoteApproval(state)
            val nextCompletionEventId = state.optInt("completionEventID", 0)
            val nextActiveSessionCount = state.optInt("activeSessionCount", 0).coerceAtLeast(0)
            val reconnectReveal = shouldRevealCodexAfterReconnect(
                forceReveal = forceCodexRevealAfterReconnect,
                currentActivity = nextActivity
            )
            val revealEvent = shouldRevealCodex(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                previousCompletionEventId = lastCompletionEventId,
                currentCompletionEventId = nextCompletionEventId
            ) || reconnectReveal
            if (reconnectReveal) {
                forceCodexRevealAfterReconnect = false
            }
            val completionEvent = isCodexCompletionEvent(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                previousCompletionEventId = lastCompletionEventId,
                currentCompletionEventId = nextCompletionEventId
            )
            val revealReason = when {
                completionEvent || nextActivity == "completed" && revealEvent -> CodexRevealReason.Completion
                nextActivity == "waitingForApproval" && revealEvent -> CodexRevealReason.Approval
                else -> CodexRevealReason.Running
            }
            val runningTransition = shouldWakeForCodexRunningTransition(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                reconnectReveal = reconnectReveal
            )
            lastActivity = nextActivity
            lastCompletionEventId = nextCompletionEventId
            val nextResetsAt = mergeRemoteUsageDouble(state, "resetsAt", cachedResetsAt)
            val nextFiveHourReset = mergeRemoteUsageDouble(state, "fiveHourResetsAt", cachedFiveHourResetsAt)
            cachedUsedPercent = nextUsed
            cachedRemainingPercent = nextRemaining
            cachedFiveHourRemainingPercent = nextFiveHourRemaining
            cachedResetsAt = nextResetsAt
            cachedFiveHourResetsAt = nextFiveHourReset
            resetScheduler.scheduleFiveHourReset(nextFiveHourReset)
            mainHandler.post {
                codexConnected = state.optBoolean("codexConnected", false)
                activity = nextActivity
                message = state.optString("message", "Mac에 연결됨")
                commandSucceeded = null
                if (nextSmartphonePages != null) smartphonePages = nextSmartphonePages
                usedPercent = nextUsed
                remainingPercent = nextRemaining
                fiveHourRemainingPercent = nextFiveHourRemaining
                resetsAt = nextResetsAt
                fiveHourResetsAt = nextFiveHourReset
                pendingApproval = nextApproval
                activeSessionCount = nextActiveSessionCount
                if (revealEvent) {
                    codexRevealReason = revealReason
                    codexRevealEventId += 1
                }
                if (runningTransition) {
                    onCodexRunning?.invoke()
                }
                if (completionEvent) {
                    onCodexCompletion?.invoke()
                }
            }
        }
    }

    fun sendCommand(command: String) {
        sendCommand(command, null)
    }

    internal fun sendSmartphoneButton(action: ControlAction) {
        sendCommand("smartphoneButton", action)
    }

    internal fun sendCodexApproval(decision: String) {
        sendCommand("codexApproval", null, decision)
    }

    private fun sendCommand(command: String, action: ControlAction?, decision: String? = null) {
        if (connectionState != RemoteConnectionState.Connected) {
            mainHandler.post {
                commandSucceeded = false
                message = "Mac에 연결된 후 버튼을 눌러주세요."
            }
            return
        }
        val commandObject = JSONObject()
            .put("type", "command")
            .put("protocolVersion", 1)
            .put("id", UUID.randomUUID().toString())
            .put("command", command)
        if (action != null) {
            commandObject.put("buttonID", action.id)
            commandObject.put(
                "action",
                JSONObject()
                    .put("kind", action.actionKind)
                    .put("value", action.actionValue)
                    .put("targetAppBundleIdentifier", action.targetAppBundleIdentifier)
                    .put("launchTargetAppIfNeeded", action.launchTargetAppIfNeeded)
            )
        }
        if (decision != null) {
            commandObject.put("decision", decision)
        }
        commandExecutor.execute {
            val currentWriter = writer ?: return@execute
            runCatching {
                synchronized(currentWriter) {
                    currentWriter.append(commandObject.toString()).append('\n')
                    currentWriter.flush()
                }
            }.onFailure {
                mainHandler.post {
                    commandSucceeded = false
                    message = "Mac 명령을 전달하지 못했습니다."
                }
            }
        }
    }

    fun requestCodexReveal() {
        mainHandler.post {
            codexRevealReason = CodexRevealReason.Explicit
            codexRevealEventId += 1
        }
    }

    private fun setConnection(next: RemoteConnectionState) {
        mainHandler.post { connectionState = next }
    }

    private fun clearRemoteState(nextMessage: String = "Mac을 찾는 중…") {
        lastActivity = null
        lastCompletionEventId = null
        cachedUsedPercent = null
        cachedRemainingPercent = null
        cachedFiveHourRemainingPercent = null
        cachedResetsAt = null
        cachedFiveHourResetsAt = null
        mainHandler.post {
            codexConnected = false
            activity = "idle"
            message = nextMessage
            commandSucceeded = null
            usedPercent = null
            remainingPercent = null
            fiveHourRemainingPercent = null
            resetsAt = null
            fiveHourResetsAt = null
            pendingApproval = null
            activeSessionCount = 0
            smartphonePages = buttonPages
        }
    }

    private fun preserveActiveStateDuringReconnect() {
        val active = lastActivity == "running" || lastActivity == "waitingForApproval"
        if (!active) {
            clearRemoteState()
            return
        }
        mainHandler.post {
            codexConnected = false
            message = "Mac 연결을 재시도하는 중…"
            commandSucceeded = null
        }
    }

    private fun retryDiscovery() {
        mainHandler.postDelayed({ if (started && connectionState != RemoteConnectionState.Connected) discover() }, RETRY_DELAY_MS)
    }
}
