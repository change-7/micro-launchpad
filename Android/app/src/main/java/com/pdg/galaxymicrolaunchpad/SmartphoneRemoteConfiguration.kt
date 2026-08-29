package com.pdg.galaxymicrolaunchpad

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.json.JSONObject

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
        "waiting", "waiting_for_approval", "waiting-for-approval" -> "waitingForApproval"
        "complete", "done", "finished" -> "completed"
        "error", "errored" -> "failed"
        "" -> "idle"
        else -> rawActivity.trim().lowercase(java.util.Locale.ROOT)
    }
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
