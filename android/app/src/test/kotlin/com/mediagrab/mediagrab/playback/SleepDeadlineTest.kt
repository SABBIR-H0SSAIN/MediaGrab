package com.mediagrab.mediagrab.playback

import org.junit.Assert.*
import org.junit.Test

class SleepDeadlineTest {
    @Test fun deadlineUsesElapsedTimeAndExpiresWhileMediaIsPaused() {
        var elapsed = 10_000L
        val timer = SleepDeadline { elapsed }
        timer.set(5)
        assertEquals(300_000L, timer.remaining())
        elapsed += 299_000
        assertEquals(1000L, timer.remaining())
        assertFalse(timer.expired())
        elapsed += 1001
        assertTrue(timer.expired())
        assertEquals(0L, timer.remaining())
        timer.clear()
        assertFalse(timer.active())
        assertFalse(timer.expired())
    }
    @Test fun fadeIsOnlyAppliedDuringFinalFiveSecondsAndResetRestoresGain() {
        var elapsed = 0L
        val timer = SleepDeadline { elapsed }
        timer.set(1)
        assertEquals(1f, timer.gain(true))
        elapsed = 57_500
        assertEquals(.5f, timer.gain(true))
        assertEquals(1f, timer.gain(false))
        timer.clear()
        assertEquals(1f, timer.gain(true))
        timer.set(10)
        assertEquals(600_000L, timer.remaining())
    }
    @Test fun cancelAndDurationBounds() {
        var elapsed = 0L
        val timer = SleepDeadline { elapsed }
        timer.set(2000)
        assertEquals(86_400_000L, timer.remaining())
        timer.set(0)
        assertFalse(timer.active())
        elapsed = Long.MAX_VALUE / 2
        timer.set(1)
        assertEquals(60_000L, timer.remaining())
    }
}
