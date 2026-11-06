package com.mediagrab.mediagrab.playback

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PipControlsTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    @Test fun transportHasCenteredPauseAndNoDuplicateClose() {
        val actions = PipControls.actions(context, true, 1, 3)
        assertEquals(listOf("Previous", "Pause", "Next"), actions.map { it.title.toString() })
        assertEquals(listOf("previous", "pause", "next"), actions.map {
            shadowOf(it.actionIntent).savedIntent.getStringExtra("command") })
        assertTrue(actions.all { it.isEnabled })
    }
    @Test fun queueBoundariesDisableUnavailableNavigation() {
        val first = PipControls.actions(context, false, 0, 2)
        assertFalse(first[0].isEnabled)
        assertEquals("Play", first[1].title.toString())
        assertTrue(first[2].isEnabled)
        val last = PipControls.actions(context, true, 1, 2)
        assertTrue(last[0].isEnabled)
        assertFalse(last[2].isEnabled)
        val single = PipControls.actions(context, true, 0, 1)
        assertFalse(single[0].isEnabled)
        assertFalse(single[2].isEnabled)
    }
}
