package com.pdg.galaxymicrolaunchpad

import android.app.Service
import android.media.RingtoneManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MainActivityTest {
    @Test
    fun remoteUsageField_preservesCachedValueWhenWireFieldIsAbsent() {
        assertEquals(67, mergeRemoteUsageInt(fieldPresent = false, fieldIsNull = false, fieldValue = null, current = 67))
    }

    @Test
    fun remoteUsageField_updatesWhenPresentAndClearsOnlyWhenExplicitlyNull() {
        assertEquals(54, mergeRemoteUsageInt(fieldPresent = true, fieldIsNull = false, fieldValue = 54, current = 67))
        assertEquals(null, mergeRemoteUsageInt(fieldPresent = true, fieldIsNull = true, fieldValue = null, current = 67))
    }

    @Test
    fun screenOffConnectionOptions_useTenMinuteStepsAndAlways() {
        assertEquals("30m", DefaultScreenOffConnectionOptionKey)
        assertEquals(10 * 60 * 1_000L, screenOffConnectionOption("10m").timeoutMillis)
        assertEquals(20 * 60 * 1_000L, screenOffConnectionOption("20m").timeoutMillis)
        assertEquals(30 * 60 * 1_000L, screenOffConnectionOption("30m").timeoutMillis)
        assertEquals(120 * 60 * 1_000L, screenOffConnectionOption("120m").timeoutMillis)
        assertEquals(Long.MAX_VALUE, screenOffConnectionOption("always").timeoutMillis)
        assertEquals(DefaultScreenOffConnectionOptionKey, screenOffConnectionOption("unknown").key)
        assertTrue(screenOffConnectionOptions.dropLast(1).all { it.timeoutMillis % (10 * 60 * 1_000L) == 0L })
        assertEquals("always", screenOffConnectionOptions.last().key)
    }

    @Test
    fun sleepWindow_handlesDaytimeAndOvernightRanges() {
        assertFalse(isWithinSleepWindow(false, 23 * 60, 7 * 60, 23 * 60 + 30))
        assertTrue(isWithinSleepWindow(true, 9 * 60, 18 * 60, 12 * 60))
        assertFalse(isWithinSleepWindow(true, 9 * 60, 18 * 60, 18 * 60))
        assertTrue(isWithinSleepWindow(true, 23 * 60, 7 * 60, 23 * 60 + 30))
        assertTrue(isWithinSleepWindow(true, 23 * 60, 7 * 60, 6 * 60 + 30))
        assertFalse(isWithinSleepWindow(true, 23 * 60, 7 * 60, 12 * 60))
    }

    @Test
    fun screenOffPolicy_onlySchedulesDisconnectWhenScreenIsOff() {
        assertEquals(ScreenOffConnectionAction.Resume, screenOffConnectionAction(isInteractive = true))
        assertEquals(ScreenOffConnectionAction.ScheduleDisconnect, screenOffConnectionAction(isInteractive = false))
    }

    @Test
    fun idleBlackout_requiresTheSettingAndInactivityTimeout() {
        assertFalse(
            shouldEnterIdleBlackout(
                enabled = false,
                nowElapsedMillis = 120_000L,
                lastInteractionElapsedMillis = 0L
            )
        )
        assertFalse(
            shouldEnterIdleBlackout(
                enabled = true,
                nowElapsedMillis = IdleBlackoutTimeoutMillis - 1L,
                lastInteractionElapsedMillis = 0L
            )
        )
        assertTrue(
            shouldEnterIdleBlackout(
                enabled = true,
                nowElapsedMillis = IdleBlackoutTimeoutMillis,
                lastInteractionElapsedMillis = 0L
            )
        )
    }

    @Test
    fun remoteBridgeService_isStickyAcrossBackgroundProcessReclaim() {
        assertEquals(Service.START_STICKY, remoteBridgeServiceStartMode())
    }

    @Test
    fun completionEvent_isRaisedOnlyWhenEnteringCompleted() {
        assertTrue(shouldRevealCodex(previousActivity = "running", currentActivity = "completed"))
        assertTrue(shouldRevealCodex(previousActivity = null, currentActivity = "completed"))
        assertFalse(shouldRevealCodex(previousActivity = "completed", currentActivity = "completed"))
        assertFalse(shouldRevealCodex(previousActivity = "running", currentActivity = "idle"))
    }

    @Test
    fun initialRunningState_revealsCodexAfterAppRestart() {
        assertTrue(shouldRevealCodex(previousActivity = null, currentActivity = "running"))
        assertFalse(shouldRevealCodex(previousActivity = "running", currentActivity = "running"))
    }

    @Test
    fun runningReveal_doesNotSwitchAwayFromButtons() {
        assertFalse(shouldAutoRevealCodexPage(CodexRevealReason.Running))
        assertTrue(shouldAutoRevealCodexPage(CodexRevealReason.Completion))
        assertTrue(shouldAutoRevealCodexPage(CodexRevealReason.Approval))
        assertTrue(shouldAutoRevealCodexPage(CodexRevealReason.Explicit))
        assertFalse(
            shouldAutoRevealCodexPage(
                reason = CodexRevealReason.Completion,
                nowElapsedMillis = 1_000L,
                suppressUntilElapsedMillis = 1_500L
            )
        )
        assertTrue(
            shouldAutoRevealCodexPage(
                reason = CodexRevealReason.Completion,
                nowElapsedMillis = 1_500L,
                suppressUntilElapsedMillis = 1_500L
            )
        )
    }

    @Test
    fun activeStateAfterReconnect_revealsCodexEvenWhenActivityDidNotChange() {
        assertTrue(shouldRevealCodexAfterReconnect(forceReveal = true, currentActivity = "running"))
        assertTrue(shouldRevealCodexAfterReconnect(forceReveal = true, currentActivity = "waitingForApproval"))
        assertFalse(shouldRevealCodexAfterReconnect(forceReveal = true, currentActivity = "idle"))
        assertFalse(shouldRevealCodexAfterReconnect(forceReveal = false, currentActivity = "running"))
    }

    @Test
    fun idleToRunningState_revealsCodexWhenTaskStartsAfterAnIdleConnection() {
        assertTrue(
            "Codex should reveal the working motion when an idle connection starts a task",
            shouldRevealCodex(previousActivity = "idle", currentActivity = "running")
        )
    }

    @Test
    fun approvalEvent_isRaisedOnlyWhenEnteringApprovalWait() {
        assertTrue(shouldRevealCodex(previousActivity = "running", currentActivity = "waitingForApproval"))
        assertTrue(shouldRevealCodex(previousActivity = null, currentActivity = "waitingForApproval"))
        assertFalse(shouldRevealCodex(previousActivity = "waitingForApproval", currentActivity = "waitingForApproval"))
    }

    @Test
    fun desktopCompletionEvent_revealsCodexEvenWhileAggregateActivityIsRunning() {
        assertTrue(
            shouldRevealCodex(
                previousActivity = "running",
                currentActivity = "running",
                previousCompletionEventId = 4,
                currentCompletionEventId = 5
            )
        )
        assertFalse(
            shouldRevealCodex(
                previousActivity = "running",
                currentActivity = "running",
                previousCompletionEventId = 5,
                currentCompletionEventId = 5
            )
        )
    }

    @Test
    fun codexCompletionEvent_isDetectedFromCompletedStateOrCompletionCounter() {
        assertTrue(
            isCodexCompletionEvent(
                previousActivity = "running",
                currentActivity = "completed",
                previousCompletionEventId = 3,
                currentCompletionEventId = 3
            )
        )
        assertTrue(
            isCodexCompletionEvent(
                previousActivity = "running",
                currentActivity = "running",
                previousCompletionEventId = 3,
                currentCompletionEventId = 4
            )
        )
        assertFalse(
            isCodexCompletionEvent(
                previousActivity = "completed",
                currentActivity = "completed",
                previousCompletionEventId = 4,
                currentCompletionEventId = 4
            )
        )
    }

    @Test
    fun codexHeaderPulse_isOnlyActiveWhileCodexIsRunning() {
        assertTrue(codexHeaderPulseAlpha(activity = "running", progress = 0f) < 1f)
        assertTrue(codexHeaderPulseAlpha(activity = "running", progress = 1f) > codexHeaderPulseAlpha("running", 0f))
        assertEquals(1f, codexHeaderPulseAlpha(activity = "completed", progress = 0.2f), 0.001f)
        assertEquals(1f, codexHeaderPulseAlpha(activity = "idle", progress = 0.8f), 0.001f)
    }

    @Test
    fun codexCompletionSound_usesTheSystemNotificationStream() {
        assertEquals(RingtoneManager.TYPE_NOTIFICATION, completionNotificationSoundType())
    }

    @Test
    fun remoteActivity_aliases_areNormalizedToRenderableStates() {
        assertTrue(normalizeRemoteActivity("working") == "running")
        assertTrue(normalizeRemoteActivity("in_progress") == "running")
        assertTrue(normalizeRemoteActivity("inProgress") == "running")
        assertTrue(normalizeRemoteActivity("processing") == "running")
        assertTrue(normalizeRemoteActivity("waiting-for-approval") == "waitingForApproval")
        assertTrue(normalizeRemoteActivity("done") == "completed")
    }

    @Test
    fun remoteActivity_camelCaseApprovalState_isNormalizedToRenderableState() {
        assertEquals("waitingForApproval", normalizeRemoteActivity("waitingForApproval"))
    }

    @Test
    fun horizontalSwipe_wrapsBetweenButtonsAndCodex() {
        assertEquals(1, horizontalSwipeTarget(currentIndex = 0, pageCount = 2, dragDistance = -120f))
        assertEquals(0, horizontalSwipeTarget(currentIndex = 1, pageCount = 2, dragDistance = -120f))
        assertEquals(0, horizontalSwipeTarget(currentIndex = 1, pageCount = 2, dragDistance = 120f))
        assertEquals(1, horizontalSwipeTarget(currentIndex = 0, pageCount = 2, dragDistance = 120f))
    }

    @Test
    fun horizontalSwipe_repeatedSameDirectionContinuesCycling() {
        var pageIndex = 0
        repeat(4) {
            pageIndex = horizontalSwipeTarget(currentIndex = pageIndex, pageCount = 2, dragDistance = -40f)
        }
        assertEquals(0, pageIndex)
    }

    @Test
    fun horizontalSwipe_ignoresShortDrags() {
        assertEquals(0, horizontalSwipeTarget(currentIndex = 0, pageCount = 2, dragDistance = 28f))
        assertEquals(1, horizontalSwipeTarget(currentIndex = 1, pageCount = 2, dragDistance = -28f))
        assertEquals(1, horizontalSwipeTarget(currentIndex = 0, pageCount = 2, dragDistance = -32f))
    }

    @Test
    fun horizontalSwipeCommitDistance_scalesFromDpToPixels() {
        assertEquals(32f, horizontalSwipeCommitDistancePx(density = 1f), 0.001f)
        assertEquals(96f, horizontalSwipeCommitDistancePx(density = 3f), 0.001f)
    }

    @Test
    fun horizontalSwipeTransitionDirection_followsFingerMovement() {
        assertEquals(1, horizontalSwipeTransitionDirection(dragDistance = -40f))
        assertEquals(-1, horizontalSwipeTransitionDirection(dragDistance = 40f))
    }

    @Test
    fun smartphoneIconMapping_handlesSymbolsBeyondTheDefaultButtonSet() {
        val fallback = iconForSymbol("unrecognised-symbol")
        listOf("safari", "folder.fill", "camera.fill", "gear", "chart.line.uptrend.xyaxis", "icloud.and.arrow.up", "icloud.and.arrow.down").forEach { symbol ->
            assertFalse("$symbol should not fall back to the overflow icon", iconForSymbol(symbol) == fallback)
        }
        assertTrue(iconForSymbol("folder") == iconForSymbol("folder.fill"))
    }

    @Test
    fun emptySmartphoneSymbol_isRenderedWithoutAnIcon() {
        assertTrue(isIconlessSymbol(""))
        assertTrue(isIconlessSymbol("  "))
        assertFalse(isIconlessSymbol("square"))
    }

    @Test
    fun emptySmartphoneButtonTitle_isNotRenderedAsAButton() {
        assertTrue(isSmartphoneButtonPlaceholder(""))
        assertTrue(isSmartphoneButtonPlaceholder("   "))
        assertFalse(isSmartphoneButtonPlaceholder("Files"))
    }

    @Test
    fun remoteBridgeReadTimeout_disconnectsAfterHeartbeatAlsoGoesUnanswered() {
        assertFalse(shouldDisconnectAfterReadTimeout(consecutiveTimeouts = 1))
        assertTrue(shouldDisconnectAfterReadTimeout(consecutiveTimeouts = 2))
    }

    @Test
    fun usageMeterValues_areExpectedToBeDisplayedAsRemainingPercent() {
        assertEquals(80, clampUsagePercent(80))
        assertEquals(0, clampUsagePercent(-4))
        assertEquals(100, clampUsagePercent(140))
        assertEquals(null, clampUsagePercent(null))
    }

}
