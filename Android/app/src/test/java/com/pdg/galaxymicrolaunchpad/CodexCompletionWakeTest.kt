package com.pdg.galaxymicrolaunchpad

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexCompletionWakeTest {
    @Test
    fun completionEvent_whenActivityIsVisible_doesNotRequirePowerWakeLock() {
        assertFalse(shouldWakeForCodexCompletion(isInteractive = true))
    }

    @Test
    fun completionEvent_whenScreenIsOff_requiresPowerWakeLock() {
        assertTrue(shouldWakeForCodexCompletion(isInteractive = false))
    }

    @Test
    fun runningEvent_whenScreenIsOff_requiresPowerWakeLock() {
        assertTrue(shouldWakeForCodex(isInteractive = false))
    }

    @Test
    fun runningEvent_whenScreenIsAlreadyOn_doesNotAcquirePowerWakeLock() {
        assertFalse(shouldWakeForCodex(isInteractive = true))
    }

    @Test
    fun runningTransition_fromIdle_requestsWake() {
        assertTrue(shouldWakeForCodexRunningTransition(previousActivity = "idle", currentActivity = "running"))
    }

    @Test
    fun repeatedRunningState_doesNotRequestAnotherWake() {
        assertFalse(shouldWakeForCodexRunningTransition(previousActivity = "running", currentActivity = "running"))
    }

    @Test
    fun reconnectRunningState_requestsWakeAgain() {
        assertTrue(
            shouldWakeForCodexRunningTransition(
                previousActivity = "running",
                currentActivity = "running",
                reconnectReveal = true
            )
        )
    }
}
