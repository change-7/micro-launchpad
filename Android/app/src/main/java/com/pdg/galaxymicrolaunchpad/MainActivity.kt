package com.pdg.galaxymicrolaunchpad

import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.clickable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.view.WindowManager
import kotlin.math.min
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay

private val Black = Color(0xFF050505)
private val Tile = Color(0xFF191919)
private val Line = Color(0xFF777777)
private val TextPrimary = Color(0xFFF2F2F2)
private val TextMuted = Color(0xFF9A9A9A)
private val Green = Color(0xFF32E875)
private val Red = Color(0xFFFF3B30)
private val GaugeTrack = Color(0xFF303030)
private val GaugeMid = Color(0xFFFFB020)
private val GaugeCool = Color(0xFF22C7A8)
private val GaugeHigh = Color(0xFF3B82F6)
private const val HorizontalSwipeCommitDistanceDp = 32f
private const val DefaultHorizontalSwipeCommitDistancePx = HorizontalSwipeCommitDistanceDp
private const val AppPageTransitionDurationMillis = 150
private const val AppPageFadeDurationMillis = 100
private val ButtonTileIconSize = 36.dp
private val ButtonTileContentGap = 4.dp
private val ButtonTileLabelFontSize = 14.sp

internal fun clampUsagePercent(value: Int?): Int? = value?.coerceIn(0, 100)

private enum class AppPage(val label: String) {
    Controls("Buttons"),
    Codex("Codex")
}

internal data class ControlAction(
    val label: String,
    val icon: ImageVector,
    val command: String,
    val accent: Color = TextPrimary,
    val id: String = "",
    val actionKind: String = "none",
    val actionValue: String = "",
    val targetAppBundleIdentifier: String = "",
    val launchTargetAppIfNeeded: Boolean = true,
    val iconBitmap: ImageBitmap? = null,
    val isPlaceholder: Boolean = false,
    val isIconless: Boolean = false
)

internal data class ButtonPage(
    val id: String,
    val label: String,
    val actions: List<ControlAction>
)

private val defaultActions = listOf(
    ControlAction("Run", Icons.Outlined.PlayArrow, "run", Green),
    ControlAction("Pause", Icons.Outlined.Pause, "pause"),
    ControlAction("Stop", Icons.Outlined.Stop, "stop", Red),
    ControlAction("Terminal", Icons.Outlined.Terminal, "terminal"),
    ControlAction("Browser", Icons.Outlined.Language, "browser"),
    ControlAction("Files", Icons.Outlined.Folder, "files"),
    ControlAction("Search", Icons.Outlined.Search, "search"),
    ControlAction("Capture", Icons.Outlined.PhotoCamera, "capture"),
    ControlAction("Clipboard", Icons.Outlined.ContentPaste, "clipboard"),
    ControlAction("Music", Icons.Outlined.MusicNote, "music"),
    ControlAction("Volume", Icons.Outlined.VolumeUp, "volume"),
    ControlAction("Focus", Icons.Outlined.DarkMode, "focus"),
    ControlAction("Settings", Icons.Outlined.Settings, "settings"),
    ControlAction("More", Icons.Outlined.MoreHoriz, "more"),
    ControlAction("Run", Icons.Outlined.PlayArrow, "run", Green),
    ControlAction("Stop", Icons.Outlined.Stop, "stop", Red)
)

private val defaultButtonPages = listOf(
    ButtonPage("smartphone_page_0", "PAGE 01", defaultActions),
    ButtonPage(
        "smartphone_page_1",
        "PAGE 02",
        listOf(
            defaultActions[3], defaultActions[4], defaultActions[5], defaultActions[6],
            defaultActions[7], defaultActions[8], defaultActions[9], defaultActions[10],
            defaultActions[11], defaultActions[12], defaultActions[13], defaultActions[3],
            defaultActions[5], defaultActions[6], defaultActions[10], defaultActions[12]
        )
    ),
    ButtonPage(
        "smartphone_page_2",
        "PAGE 03",
        listOf(
            defaultActions[0], defaultActions[1], defaultActions[2], defaultActions[3],
            defaultActions[6], defaultActions[7], defaultActions[4], defaultActions[5],
            defaultActions[8], defaultActions[9], defaultActions[10], defaultActions[11],
            defaultActions[12], defaultActions[13], defaultActions[0], defaultActions[2]
        )
    )
)

internal val buttonPages = defaultButtonPages.mapIndexed { pageIndex, page ->
    page.copy(actions = page.actions.mapIndexed { buttonIndex, action ->
        action.copy(id = "smartphone_page_${pageIndex}_button_${buttonIndex}")
    })
}

class MainActivity : ComponentActivity() {
    private lateinit var remoteBridge: RemoteBridgeClient
    private var completionWakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        remoteBridge = RemoteBridgeClient(this)
        remoteBridge.onCodexReveal = ::wakeForCodexReveal
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        setContent { GalaxyMicroLaunchpadApp(remoteBridge) }
        remoteBridge.start()
        if (intent.getBooleanExtra(CodexResetScheduler.EXTRA_REVEAL_CODEX, false)) {
            remoteBridge.requestCodexReveal()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(CodexResetScheduler.EXTRA_REVEAL_CODEX, false)) {
            remoteBridge.requestCodexReveal()
        }
    }

    override fun onDestroy() {
        remoteBridge.onCodexReveal = null
        remoteBridge.stop()
        completionWakeLock?.let { wakeLock ->
            if (wakeLock.isHeld) wakeLock.release()
        }
        completionWakeLock = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun wakeForCodexReveal() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        val powerManager = getSystemService(PowerManager::class.java)
        if (!powerManager.isInteractive) {
            completionWakeLock?.let { wakeLock ->
                if (wakeLock.isHeld) wakeLock.release()
            }
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "$packageName:codex-completion"
            ).apply {
                setReferenceCounted(false)
                acquire(5_000L)
            }
            completionWakeLock = wakeLock
            window.decorView.postDelayed({
                if (wakeLock.isHeld) wakeLock.release()
                if (completionWakeLock === wakeLock) completionWakeLock = null
            }, 5_500L)
        }
    }
}

@Composable
private fun GalaxyMicroLaunchpadApp(remoteBridge: RemoteBridgeClient) {
    var page by remember { mutableStateOf(AppPage.Controls) }
    var buttonPageIndex by rememberSaveable { mutableStateOf(0) }
    var localMessage by remember { mutableStateOf("Mac을 찾는 중…") }
    LaunchedEffect(remoteBridge.codexRevealEventId) {
        if (remoteBridge.codexRevealEventId > 0) {
            page = AppPage.Codex
        }
    }
    val headerMessage = if (remoteBridge.connectionState == RemoteConnectionState.Connected) {
        remoteBridge.message
    } else {
        localMessage
    }
    var horizontalDrag by remember { mutableStateOf(0f) }
    var swipeCommitted by remember { mutableStateOf(false) }
    var pageTransitionDirection by remember { mutableStateOf(1) }
    val swipeCommitDistancePx = horizontalSwipeCommitDistancePx(LocalDensity.current.density)

    Surface(color = Black, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .pointerInput(page) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { change, dragAmount ->
                            change.consume()
                            horizontalDrag += dragAmount
                            if (!swipeCommitted && kotlin.math.abs(horizontalDrag) >= swipeCommitDistancePx) {
                                val currentIndex = AppPage.entries.indexOf(page)
                                val nextIndex = horizontalSwipeTarget(
                                    currentIndex = currentIndex,
                                    pageCount = AppPage.entries.size,
                                    dragDistance = horizontalDrag,
                                    commitDistancePx = swipeCommitDistancePx
                                )
                                if (nextIndex != currentIndex) {
                                    pageTransitionDirection = horizontalSwipeTransitionDirection(horizontalDrag)
                                    page = AppPage.entries[nextIndex]
                                    swipeCommitted = true
                                }
                            }
                        },
                        onDragEnd = {
                            if (!swipeCommitted) {
                                val currentIndex = AppPage.entries.indexOf(page)
                                val nextIndex = horizontalSwipeTarget(
                                    currentIndex = currentIndex,
                                    pageCount = AppPage.entries.size,
                                    dragDistance = horizontalDrag,
                                    commitDistancePx = swipeCommitDistancePx
                                )
                                if (nextIndex != currentIndex) {
                                    pageTransitionDirection = horizontalSwipeTransitionDirection(horizontalDrag)
                                    page = AppPage.entries[nextIndex]
                                }
                            }
                            horizontalDrag = 0f
                            swipeCommitted = false
                        },
                        onDragCancel = {
                            horizontalDrag = 0f
                            swipeCommitted = false
                        }
                    )
                }
        ) {
            Header(
                message = headerMessage,
                messageColor = when (remoteBridge.commandSucceeded) {
                    true -> Green
                    false -> Red
                    null -> TextMuted
                },
                connectionState = remoteBridge.connectionState,
                fiveHourRemaining = remoteBridge.fiveHourRemainingPercent,
                weeklyRemaining = remoteBridge.remainingPercent
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                AnimatedContent(
                    targetState = page,
                    modifier = Modifier.fillMaxSize(),
                    transitionSpec = {
                        (slideInHorizontally(animationSpec = tween(AppPageTransitionDurationMillis)) { width -> pageTransitionDirection * (width / 5) } + fadeIn(tween(AppPageFadeDurationMillis))) togetherWith
                            (slideOutHorizontally(animationSpec = tween(AppPageTransitionDurationMillis)) { width -> -pageTransitionDirection * (width / 5) } + fadeOut(tween(AppPageFadeDurationMillis)))
                    },
                    label = "app-page-transition"
                ) { targetPage ->
                    when (targetPage) {
                        AppPage.Controls -> ControlsPage(
                            pages = remoteBridge.smartphonePages,
                            pageIndex = buttonPageIndex,
                            onPageChange = { buttonPageIndex = it },
                            onAction = { action ->
                                if (action.command == "smartphoneButton") {
                                    remoteBridge.sendSmartphoneButton(action)
                                } else {
                                    remoteBridge.sendCommand(action.command)
                                }
                            }
                        )
                        AppPage.Codex -> CodexStatusPage(remoteBridge)
                    }
                }
            }
            BottomNavigation(
                page = page,
                onSelect = { targetPage ->
                    if (targetPage != page) {
                        val currentIndex = AppPage.entries.indexOf(page)
                        val targetIndex = AppPage.entries.indexOf(targetPage)
                        pageTransitionDirection = if (targetIndex > currentIndex) 1 else -1
                        page = targetPage
                    }
                }
            )
        }
    }
}

@Composable
private fun Header(
    message: String,
    messageColor: Color,
    connectionState: RemoteConnectionState,
    fiveHourRemaining: Int?,
    weeklyRemaining: Int?
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .background(
                    if (connectionState == RemoteConnectionState.Connected) Green else TextMuted,
                    RoundedCornerShape(50)
                )
        )
        Spacer(Modifier.width(12.dp))
        Text(
            when (connectionState) {
                RemoteConnectionState.Connected -> "Mac connected"
                RemoteConnectionState.Connecting -> "Connecting to Mac"
                RemoteConnectionState.Searching -> "Searching for Mac"
                RemoteConnectionState.Disconnected -> "Mac disconnected"
            },
            color = TextPrimary,
            fontSize = 16.sp
        )
        Spacer(Modifier.width(18.dp))
        Text(
            message,
            color = messageColor,
            fontSize = 14.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(end = 12.dp)
        )
        UsageMeter(label = "5시간", remainingPercent = fiveHourRemaining, accent = GaugeCool)
        Spacer(Modifier.width(10.dp))
        UsageMeter(label = "주간", remainingPercent = weeklyRemaining, accent = GaugeHigh)
        Spacer(Modifier.width(10.dp))
        IconButton(onClick = {}, modifier = Modifier.size(34.dp)) {
            Icon(Icons.Outlined.Wifi, contentDescription = "Connection", tint = TextMuted)
        }
    }
}

@Composable
private fun UsageMeter(label: String, remainingPercent: Int?, accent: Color) {
    val clampedPercent = clampUsagePercent(remainingPercent)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(label, color = TextMuted, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Box(
            modifier = Modifier
                .width(38.dp)
                .height(15.dp)
                .border(1.dp, TextMuted, RoundedCornerShape(3.dp))
                .padding(2.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth((clampedPercent ?: 0) / 100f)
                    .background(accent, RoundedCornerShape(1.dp))
            )
        }
        Box(
            modifier = Modifier
                .width(2.dp)
                .height(6.dp)
                .background(TextMuted, RoundedCornerShape(1.dp))
        )
        Text(
            clampedPercent?.let { "$it%" } ?: "--",
            color = clampedPercent?.let { accent } ?: TextMuted,
            fontSize = 10.sp,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun ControlsPage(
    pages: List<ButtonPage>,
    pageIndex: Int,
    onPageChange: (Int) -> Unit,
    onAction: (ControlAction) -> Unit
) {
    var verticalDrag by remember { mutableStateOf(0f) }
    Row(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 4.dp)
    ) {
        Column(
            modifier = Modifier
                .width(148.dp)
                .fillMaxHeight()
                .padding(end = 22.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("PAGES", color = TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.Medium)
            Text("Select a button page", color = TextMuted, fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
            pages.forEachIndexed { index, buttonPage ->
                PageSelector(
                    page = buttonPage,
                    selected = index == pageIndex,
                    onClick = { onPageChange(index) }
                )
            }
            Spacer(Modifier.weight(1f))
            Text("Swipe ↑ / ↓", color = TextMuted, fontSize = 12.sp)
            Text("to change page", color = TextMuted, fontSize = 12.sp)
        }
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(pageIndex) {
                    detectVerticalDragGestures(
                        onVerticalDrag = { change, dragAmount ->
                            change.consume()
                            verticalDrag += dragAmount
                        },
                        onDragEnd = {
                            val nextPage = when {
                                verticalDrag < -80f -> (pageIndex + 1) % pages.size
                                verticalDrag > 80f -> (pageIndex - 1 + pages.size) % pages.size
                                else -> pageIndex
                            }
                            if (nextPage != pageIndex) onPageChange(nextPage)
                            verticalDrag = 0f
                        },
                        onDragCancel = { verticalDrag = 0f }
                    )
                }
        ) {
            AnimatedContent(
                targetState = pageIndex,
                modifier = Modifier.fillMaxSize(),
                transitionSpec = {
                    val direction = pageTransitionDirection(initialState, targetState, pages.size)
                    (slideInVertically(animationSpec = tween(260)) { height -> direction * (height / 5) } + fadeIn(tween(180))) togetherWith
                        (slideOutVertically(animationSpec = tween(260)) { height -> -direction * (height / 5) } + fadeOut(tween(180)))
                },
                label = "button-page-transition"
            ) { targetPageIndex ->
                val targetPage = pages[targetPageIndex.coerceIn(pages.indices)]
                val rowCount = (targetPage.actions.size + 3) / 4
                val gap = 10.dp
                val tileHeight = ((maxHeight - gap * (rowCount - 1)) / rowCount).coerceAtLeast(56.dp)
                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    modifier = Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.spacedBy(gap),
                    verticalArrangement = Arrangement.spacedBy(gap),
                    userScrollEnabled = false
                ) {
                    items(targetPage.actions) { action ->
                        ActionTile(action = action, tileHeight = tileHeight, onClick = { onAction(action) })
                    }
                }
            }
        }
    }
}

private fun pageTransitionDirection(initialPage: Int, targetPage: Int, pageCount: Int): Int {
    if (initialPage == targetPage) return 1
    if (initialPage == pageCount - 1 && targetPage == 0) return 1
    if (initialPage == 0 && targetPage == pageCount - 1) return -1
    return if (targetPage > initialPage) 1 else -1
}

@Composable
private fun PageSelector(page: ButtonPage, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .clickable(onClick = onClick)
            .background(if (selected) Tile else Color.Transparent, RoundedCornerShape(3.dp))
            .border(1.dp, if (selected) Line else Color.Transparent, RoundedCornerShape(3.dp))
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(6.dp)
                .background(if (selected) Green else TextMuted, RoundedCornerShape(50))
        )
        Spacer(Modifier.width(10.dp))
        Text(page.label, color = if (selected) TextPrimary else TextMuted, fontSize = 14.sp)
    }
}

@Composable
private fun ActionTile(action: ControlAction, tileHeight: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    androidx.compose.material3.Surface(
        onClick = { if (!action.isPlaceholder) onClick() },
        color = Tile,
        contentColor = action.accent,
        shape = RoundedCornerShape(3.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(tileHeight)
            .border(1.dp, Line, RoundedCornerShape(3.dp))
    ) {
        if (!action.isPlaceholder) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(ButtonTileContentGap, Alignment.CenterVertically)
            ) {
                if (!action.isIconless) {
                    action.iconBitmap?.let { bitmap ->
                        Image(bitmap = bitmap, contentDescription = action.label, modifier = Modifier.size(ButtonTileIconSize))
                    } ?: Icon(action.icon, contentDescription = action.label, modifier = Modifier.size(ButtonTileIconSize))
                }
                Text(
                    action.label,
                    color = action.accent,
                    fontSize = ButtonTileLabelFontSize,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
private fun CodexStatusPage(remoteBridge: RemoteBridgeClient) {
    val activityTitle = when (remoteBridge.activity) {
        "connecting" -> "CONNECTING"
        "running" -> "RUNNING"
        "waitingForApproval" -> "WAITING FOR APPROVAL"
        "completed" -> "COMPLETED"
        "failed" -> "FAILED"
        else -> "IDLE"
    }
    val activityColor = when (remoteBridge.activity) {
        "failed" -> Red
        "waitingForApproval" -> GaugeMid
        "running" -> Green
        "completed" -> GaugeHigh
        else -> TextMuted
    }
    val fiveHourRemaining = remoteBridge.fiveHourRemainingPercent
    val weeklyRemaining = remoteBridge.remainingPercent
    var desktopCompletionPulse by remember { mutableStateOf(false) }
    LaunchedEffect(remoteBridge.completionEventId) {
        if (remoteBridge.completionEventId > 0) {
            desktopCompletionPulse = true
            delay(1_800L)
            desktopCompletionPulse = false
        }
    }
    val motionActivity = if (desktopCompletionPulse) "completed" else remoteBridge.activity
    val motionColor = if (desktopCompletionPulse) GaugeHigh else activityColor
    Row(modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 18.dp)) {
        Column(
            modifier = Modifier.width(300.dp).fillMaxHeight(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("CODEX", color = TextPrimary, fontSize = 28.sp, fontWeight = FontWeight.Medium)
                Text(
                    if (remoteBridge.codexConnected) "Codex connected" else "Codex unavailable",
                    color = TextPrimary,
                    fontSize = 18.sp
                )
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Remaining usage", color = TextMuted, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("5-hour", color = TextMuted, fontSize = 12.sp)
                        Text(
                            fiveHourRemaining?.let { "$it%" } ?: "—",
                            color = usageGaugeColor(fiveHourRemaining),
                            fontSize = 32.sp
                        )
                        Text(
                            formatResetTime(remoteBridge.fiveHourResetsAt, includeDate = false),
                            color = TextPrimary,
                            fontSize = 14.sp,
                            lineHeight = 18.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1
                        )
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text("1-week", color = TextMuted, fontSize = 12.sp)
                        Text(
                            weeklyRemaining?.let { "$it%" } ?: "—",
                            color = usageGaugeColor(weeklyRemaining),
                            fontSize = 32.sp
                        )
                        Text(
                            formatResetTime(remoteBridge.resetsAt, includeDate = true),
                            color = TextPrimary,
                            fontSize = 14.sp,
                            lineHeight = 18.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1
                        )
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
        Column(
            modifier = Modifier.weight(1f).fillMaxHeight().padding(horizontal = 28.dp)
        ) {
            Text("Codex status", color = TextMuted, fontSize = 13.sp)
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusMotion(
                    activity = motionActivity,
                    color = motionColor,
                    motionEventId = remoteBridge.completionEventId
                )
                Spacer(Modifier.width(18.dp))
                Column {
                    Text(activityTitle, color = activityColor, fontSize = 34.sp, fontWeight = FontWeight.Medium)
                    Text(remoteBridge.message, color = TextPrimary, fontSize = 20.sp, maxLines = 1)
                }
            }
            remoteBridge.pendingApproval?.let { approval ->
                Spacer(Modifier.height(14.dp))
                ApprovalPrompt(
                    approval = approval,
                    onDecision = remoteBridge::sendCodexApproval
                )
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                UsageGauge(
                    label = "5-hour remaining",
                    remaining = fiveHourRemaining
                )
                UsageGauge(
                    label = "1-week remaining",
                    remaining = weeklyRemaining
                )
            }
            Spacer(Modifier.weight(0.65f))
            Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                StatusLine(
                    "Mac bridge",
                    if (remoteBridge.connectionState == RemoteConnectionState.Connected) Green else TextMuted
                )
                StatusLine("Codex App Server", if (remoteBridge.codexConnected) Green else TextMuted)
                StatusLine("Activity: $activityTitle", activityColor)
            }
            Spacer(Modifier.height(18.dp))
        }
    }
}

@Composable
private fun ApprovalPrompt(
    approval: RemoteApproval,
    onDecision: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, GaugeMid, RoundedCornerShape(3.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Text(approval.title, color = GaugeMid, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        Text(
            approval.detail,
            color = TextPrimary,
            fontSize = 12.sp,
            maxLines = 3,
            lineHeight = 16.sp
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            androidx.compose.material3.Surface(
                onClick = { onDecision("accept") },
                color = GaugeHigh,
                contentColor = TextPrimary,
                shape = RoundedCornerShape(3.dp),
                modifier = Modifier.height(34.dp)
            ) {
                Box(
                    modifier = Modifier.padding(horizontal = 20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("승인", fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }
            }
            androidx.compose.material3.Surface(
                onClick = { onDecision("decline") },
                color = Tile,
                contentColor = Red,
                shape = RoundedCornerShape(3.dp),
                modifier = Modifier
                    .height(34.dp)
                    .border(1.dp, Red, RoundedCornerShape(3.dp))
            ) {
                Box(
                    modifier = Modifier.padding(horizontal = 20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("거절", fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@Composable
private fun StatusMotion(activity: String, color: Color, motionEventId: Int = 0) {
    val motion = rememberInfiniteTransition(label = "codex-status-$activity")
    val rotation by motion.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(1600), RepeatMode.Restart),
        label = "status-rotation"
    )
    val pulse by motion.animateFloat(
        initialValue = 0.82f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "status-pulse"
    )
    val shake by motion.animateFloat(
        initialValue = -3f,
        targetValue = 3f,
        animationSpec = infiniteRepeatable(tween(150), RepeatMode.Reverse),
        label = "status-shake"
    )
    val checkProgress = remember { Animatable(0f) }
    LaunchedEffect(activity, motionEventId) {
        if (activity == "completed") {
            checkProgress.snapTo(0f)
            checkProgress.animateTo(1f, animationSpec = tween(520))
        } else {
            checkProgress.snapTo(0f)
        }
    }

    Canvas(modifier = Modifier.size(64.dp)) {
        val center = Offset(size.width / 2f, size.height / 2f)
        val radius = size.minDimension * 0.27f
        when (activity) {
            "running" -> {
                rotate(rotation, center) {
                    drawArc(
                        color = color,
                        startAngle = -70f,
                        sweepAngle = 235f,
                        useCenter = false,
                        style = Stroke(width = size.minDimension * 0.055f, cap = StrokeCap.Round)
                    )
                }
                drawCircle(color = color.copy(alpha = 0.18f), radius = radius * pulse, center = center)
                drawCircle(color = color, radius = radius * 0.58f, center = center)
            }
            "waitingForApproval" -> {
                drawCircle(
                    color = color.copy(alpha = 0.38f),
                    radius = radius * pulse,
                    center = center,
                    style = Stroke(width = size.minDimension * 0.055f)
                )
                drawCircle(color = color.copy(alpha = 0.85f), radius = radius * 0.5f, center = center)
            }
            "completed" -> {
                val progress = checkProgress.value
                drawCircle(
                    color = color.copy(alpha = (1f - progress) * 0.45f),
                    radius = radius * (1.15f + progress * 0.3f),
                    center = center,
                    style = Stroke(width = size.minDimension * 0.04f)
                )
                drawCircle(color = color, radius = radius, center = center, style = Stroke(width = size.minDimension * 0.055f))
                val start = Offset(center.x - radius * 0.52f, center.y)
                val middle = Offset(center.x - radius * 0.1f, center.y + radius * 0.42f)
                val end = Offset(center.x + radius * 0.62f, center.y - radius * 0.45f)
                val first = min(progress / 0.45f, 1f)
                val second = ((progress - 0.45f) / 0.55f).coerceIn(0f, 1f)
                if (first > 0f) {
                    drawLine(start = start, end = lerpOffset(start, middle, first), color = color, strokeWidth = size.minDimension * 0.07f, cap = StrokeCap.Round)
                }
                if (second > 0f) {
                    drawLine(start = middle, end = lerpOffset(middle, end, second), color = color, strokeWidth = size.minDimension * 0.07f, cap = StrokeCap.Round)
                }
            }
            "failed" -> {
                translate(left = shake) {
                    drawCircle(color = color.copy(alpha = 0.22f), radius = radius * 1.2f, center = center)
                    drawCircle(color = color, radius = radius, center = center, style = Stroke(width = size.minDimension * 0.055f))
                    drawLine(
                        start = Offset(center.x, center.y - radius * 0.5f),
                        end = Offset(center.x, center.y + radius * 0.14f),
                        color = color,
                        strokeWidth = size.minDimension * 0.07f,
                        cap = StrokeCap.Round
                    )
                    drawCircle(color = color, radius = size.minDimension * 0.04f, center = Offset(center.x, center.y + radius * 0.5f))
                }
            }
            else -> drawCircle(color = color, radius = radius * 0.72f, center = center)
        }
    }
}

private fun lerpOffset(start: Offset, end: Offset, fraction: Float): Offset {
    return Offset(
        x = start.x + (end.x - start.x) * fraction,
        y = start.y + (end.y - start.y) * fraction
    )
}

@Composable
private fun UsageGauge(
    label: String,
    remaining: Int?,
    modifier: Modifier = Modifier
) {
    val tint = usageGaugeColor(remaining)
    val progress = (remaining ?: 0).coerceIn(0, 100) / 100f
    Column(modifier = modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = TextMuted, fontSize = 13.sp)
            Spacer(Modifier.weight(1f))
            Text(remaining?.let { "$it%" } ?: "—", color = tint, fontSize = 13.sp)
        }
        Spacer(Modifier.height(6.dp))
        LinearProgressIndicator(
            progress = { progress },
            color = tint,
            trackColor = GaugeTrack,
            modifier = Modifier.fillMaxWidth().height(6.dp)
        )
    }
}

private val koreaZone = ZoneId.of("Asia/Seoul")
private val resetTimeFormatter = DateTimeFormatter.ofPattern("M월 d일 HH:mm", Locale.KOREA)
private val resetClockFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.KOREA)

private fun formatResetTime(epochSeconds: Double?, includeDate: Boolean): String {
    val seconds = epochSeconds?.toLong() ?: return "—"
    return runCatching {
        val localTime = Instant.ofEpochSecond(seconds).atZone(koreaZone)
        if (includeDate) {
            localTime.format(resetTimeFormatter)
        } else {
            localTime.format(resetClockFormatter)
        }
    }.getOrDefault("—")
}

private fun usageGaugeColor(remaining: Int?): Color {
    val value = remaining?.coerceIn(0, 100) ?: return TextMuted
    return when {
        value <= 20 -> Red
        value <= 50 -> GaugeMid
        value <= 75 -> GaugeCool
        else -> GaugeHigh
    }
}

@Composable
private fun StatusLine(label: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 3.dp)) {
        Box(Modifier.size(5.dp).background(color, RoundedCornerShape(50)))
        Spacer(Modifier.width(7.dp))
        Text(label, color = color.copy(alpha = 0.8f), fontSize = 11.sp)
    }
}

@Composable
private fun BottomNavigation(page: AppPage, onSelect: (AppPage) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp)
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        AppPage.entries.forEach { item ->
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp)
                    .clickable { onSelect(item) },
                contentAlignment = Alignment.Center
            ) {
                Text(item.label, color = if (item == page) TextPrimary else TextMuted, fontSize = 14.sp)
            }
        }
    }
}

internal fun horizontalSwipeCommitDistancePx(density: Float): Float {
    return HorizontalSwipeCommitDistanceDp * density.coerceAtLeast(0f)
}

internal fun horizontalSwipeTransitionDirection(dragDistance: Float): Int {
    return if (dragDistance < 0f) 1 else -1
}

internal fun horizontalSwipeTarget(
    currentIndex: Int,
    pageCount: Int,
    dragDistance: Float,
    commitDistancePx: Float = DefaultHorizontalSwipeCommitDistancePx
): Int {
    if (pageCount <= 0 || kotlin.math.abs(dragDistance) < commitDistancePx) return currentIndex.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
    val normalizedIndex = currentIndex.coerceIn(0, pageCount - 1)
    return if (dragDistance < 0) {
        (normalizedIndex + 1) % pageCount
    } else {
        (normalizedIndex - 1 + pageCount) % pageCount
    }
}
