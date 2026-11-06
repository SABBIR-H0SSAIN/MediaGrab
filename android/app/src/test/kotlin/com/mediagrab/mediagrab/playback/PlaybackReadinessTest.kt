package com.mediagrab.mediagrab.playback

import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test

class PlaybackReadinessTest {
    @Test fun rapidSeeksDoNotRemoveInitializedControls() {
        val readiness = PlaybackReadiness()
        readiness.update(Player.STATE_BUFFERING)
        assertFalse(readiness.initialized)
        readiness.update(Player.STATE_READY)
        repeat(3) {
            readiness.update(Player.STATE_BUFFERING)
            assertTrue(readiness.initialized)
            readiness.update(Player.STATE_READY)
        }
        readiness.update(Player.STATE_ENDED)
        assertTrue(readiness.initialized)
    }
    @Test fun newItemsAndTerminalErrorsResetReadiness() {
        val readiness = PlaybackReadiness()
        readiness.update(Player.STATE_READY)
        readiness.reset()
        readiness.update(Player.STATE_BUFFERING)
        assertFalse(readiness.initialized)
        readiness.update(Player.STATE_READY)
        readiness.update(Player.STATE_IDLE)
        assertFalse(readiness.initialized)
    }
    @Test fun bufferingKeepsPauseAvailableUntilUserCancelsPlayback() {
        val readiness = PlaybackReadiness()
        assertTrue(readiness.showPause(true, Player.STATE_BUFFERING))
        assertFalse(readiness.showPause(false, Player.STATE_BUFFERING))
        assertTrue(readiness.showPause(true, Player.STATE_READY))
        assertFalse(readiness.showPause(true, Player.STATE_ENDED))
        assertFalse(readiness.showPause(true, Player.STATE_IDLE))
    }

}
