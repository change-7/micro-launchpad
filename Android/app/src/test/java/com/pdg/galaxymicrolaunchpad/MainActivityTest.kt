package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MainActivityTest {
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
    fun remoteActivity_aliases_areNormalizedToRenderableStates() {
        assertTrue(normalizeRemoteActivity("working") == "running")
        assertTrue(normalizeRemoteActivity("in_progress") == "running")
        assertTrue(normalizeRemoteActivity("inProgress") == "running")
        assertTrue(normalizeRemoteActivity("processing") == "running")
        assertTrue(normalizeRemoteActivity("waiting-for-approval") == "waitingForApproval")
        assertTrue(normalizeRemoteActivity("done") == "completed")
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
    fun remoteState_disconnectAfterValidState_doesNotEraseRunningStateDuringReconnect() {
        assertFalse(shouldClearRemoteStateAfterDisconnect(hasReceivedState = true))
        assertTrue(shouldClearRemoteStateAfterDisconnect(hasReceivedState = false))
    }

    @Test
    fun usageMeterValues_areExpectedToBeDisplayedAsRemainingPercent() {
        assertEquals(80, clampUsagePercent(80))
        assertEquals(0, clampUsagePercent(-4))
        assertEquals(100, clampUsagePercent(140))
        assertEquals(null, clampUsagePercent(null))
    }

}
