package com.pdg.galaxymicrolaunchpad

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.json.JSONObject

/**
 * Optional usage fields are update-like values on the bridge wire. Swift's
 * Codable encoder omits nil optionals, so an absent field must not erase a
 * value that was received in an earlier state snapshot. Only an explicit
 * JSON null clears the cached value.
 */
internal fun mergeRemoteUsageInt(state: JSONObject, key: String, current: Int?): Int? {
    return mergeRemoteUsageInt(
        fieldPresent = state.has(key),
        fieldIsNull = state.isNull(key),
        fieldValue = state.optInt(key),
        current = current
    )
}

internal fun mergeRemoteUsageInt(
    fieldPresent: Boolean,
    fieldIsNull: Boolean,
    fieldValue: Int?,
    current: Int?
): Int? {
    if (!fieldPresent) return current
    if (fieldIsNull) return null
    return fieldValue
}

internal fun mergeRemoteUsageDouble(state: JSONObject, key: String, current: Double?): Double? {
    if (!state.has(key)) return current
    if (state.isNull(key)) return null
    return state.optDouble(key)
}

internal fun parseRemoteApproval(state: JSONObject): RemoteApproval? {
    val approval = state.optJSONObject("approval") ?: return null
    return RemoteApproval(
        title = approval.optString("title", "Codex 승인 필요"),
        detail = approval.optString("detail", "계속 진행하려면 확인이 필요합니다.")
    )
}

internal data class DecodedSmartphoneIcon(
    val encodedData: String,
    val image: ImageBitmap
)

internal fun parseSmartphonePages(
    state: JSONObject,
    iconBitmapCache: MutableMap<String, DecodedSmartphoneIcon> = mutableMapOf(),
    iconAssets: JSONObject? = null
): List<ButtonPage>? {
    val pageArray = state.optJSONArray("smartphonePages") ?: return null
    val parsedPages = buildList {
        for (pageIndex in 0 until pageArray.length()) {
            val pageObject = pageArray.optJSONObject(pageIndex) ?: continue
            val buttonArray = pageObject.optJSONArray("buttons") ?: continue
            val buttons = buildList {
                for (buttonIndex in 0 until buttonArray.length()) {
                    val buttonObject = buttonArray.optJSONObject(buttonIndex) ?: continue
                    val title = buttonObject.optString("title", "")
                    val isPlaceholder = isSmartphoneButtonPlaceholder(title)
                    val actionObject = buttonObject.optJSONObject("action")
                    val kind = actionObject?.optString("kind", "none") ?: "none"
                    val buttonID = buttonObject.optString("id", "smartphone_page_${pageIndex}_button_${buttonIndex}")
                    add(
                        ControlAction(
                            label = title,
                            icon = iconForSymbol(buttonObject.optString("symbol", "")),
                            command = "smartphoneButton",
                            accent = Color.White,
                            id = buttonID,
                            actionKind = kind,
                            actionValue = actionObject?.optString("value", "") ?: "",
                            targetAppBundleIdentifier = actionObject?.optString("targetAppBundleIdentifier", "") ?: "",
                            launchTargetAppIfNeeded = actionObject?.optBoolean("launchTargetAppIfNeeded", true) ?: true,
                            iconBitmap = if (isPlaceholder) null else parseSmartphoneIconAsset(state, buttonID, iconBitmapCache, iconAssets),
                            isPlaceholder = isPlaceholder,
                            isIconless = isIconlessSymbol(buttonObject.optString("symbol", ""))
                        )
                    )
                }
            }
            if (buttons.isNotEmpty()) {
                add(
                    ButtonPage(
                        id = pageObject.optString("id", "smartphone_page_${pageIndex}"),
                        label = pageObject.optString("name", "PAGE ${String.format("%02d", pageIndex + 1)}"),
                        actions = buttons
                    )
                )
            }
        }
    }
    return parsedPages.takeIf { it.isNotEmpty() }
}

internal fun isSmartphoneButtonPlaceholder(title: String): Boolean = title.isBlank()

private fun parseSmartphoneIconAsset(
    state: JSONObject,
    buttonID: String,
    iconBitmapCache: MutableMap<String, DecodedSmartphoneIcon>,
    iconAssetsOverride: JSONObject?
): ImageBitmap? {
    val asset = (iconAssetsOverride ?: state.optJSONObject("smartphoneIconAssets"))?.optJSONObject(buttonID) ?: return null
    if (asset.optString("mimeType", "image/png") != "image/png") return null
    val encoded = asset.optString("data", "")
    if (encoded.isEmpty()) return null
    iconBitmapCache[buttonID]?.takeIf { it.encodedData == encoded }?.let { return it.image }
    val bytes = runCatching { Base64.decode(encoded, Base64.DEFAULT) }.getOrNull() ?: return null
    val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() ?: return null
    iconBitmapCache[buttonID] = DecodedSmartphoneIcon(encodedData = encoded, image = image)
    return image
}

internal fun normalizeRemoteActivity(rawActivity: String): String {
    return when (rawActivity.trim().lowercase(java.util.Locale.ROOT)) {
        "working", "work", "in_progress", "in-progress", "inprogress", "processing", "executing", "active", "busy" -> "running"
        "waiting", "waiting_for_approval", "waiting-for-approval", "waitingforapproval" -> "waitingForApproval"
        "complete", "done", "finished" -> "completed"
        "error", "errored" -> "failed"
        "" -> "idle"
        else -> rawActivity.trim().lowercase(java.util.Locale.ROOT)
    }
}

internal enum class CodexRevealReason {
    Running,
    Completion,
    Approval,
    Explicit
}

internal fun shouldAutoRevealCodexPage(
    reason: CodexRevealReason,
    nowElapsedMillis: Long = Long.MAX_VALUE,
    suppressUntilElapsedMillis: Long = 0L
): Boolean {
    if (reason == CodexRevealReason.Running) return false
    return nowElapsedMillis >= suppressUntilElapsedMillis
}

internal fun shouldRevealCodex(
    previousActivity: String?,
    currentActivity: String,
    previousCompletionEventId: Int? = null,
    currentCompletionEventId: Int? = null
): Boolean {
    val activeActivities = setOf("running", "completed", "waitingForApproval")
    val enteringRunning = currentActivity == "running"
        && previousActivity !in setOf("running", "waitingForApproval")
    return enteringRunning
        || currentActivity in activeActivities
        && previousActivity == null
        || currentActivity in setOf("completed", "waitingForApproval") && previousActivity != currentActivity
        || previousCompletionEventId != null
        && currentCompletionEventId != null
        && currentCompletionEventId > previousCompletionEventId
}

/**
 * A reconnect can replay the same active state that was already visible before
 * the socket dropped. In that case the activity value does not transition, but
 * the phone still needs to return to the Codex page so its working motion is
 * visible again.
 */
internal fun shouldRevealCodexAfterReconnect(forceReveal: Boolean, currentActivity: String): Boolean {
    if (!forceReveal) return false
    return normalizeRemoteActivity(currentActivity) in setOf("running", "waitingForApproval", "completed")
}

internal fun isCodexCompletionEvent(
    previousActivity: String?,
    currentActivity: String,
    previousCompletionEventId: Int?,
    currentCompletionEventId: Int?
): Boolean {
    val enteredCompleted = currentActivity == "completed" && previousActivity != "completed"
    val completionCounterAdvanced = previousCompletionEventId != null
        && currentCompletionEventId != null
        && currentCompletionEventId > previousCompletionEventId
    return enteredCompleted || completionCounterAdvanced
}

internal fun codexHeaderPulseAlpha(activity: String, progress: Float): Float {
    if (normalizeRemoteActivity(activity) != "running") return 1f
    return 0.58f + progress.coerceIn(0f, 1f) * 0.42f
}
