package com.mediagrab.mediagrab.playback

import android.app.Application
import android.content.Context
import org.robolectric.Shadows.shadowOf
import androidx.media3.common.util.UnstableApi
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.io.File

/** Native ownership/policy tests, not hardware decoder or device playback tests. */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class PlaybackServiceTest {
    private lateinit var controller: ServiceController<PlaybackService>
    private lateinit var service: PlaybackService
    private lateinit var media: File
    private val foregroundPrefs = mapOf("background" to false, "notifications" to false,
        "screenOff" to false, "rememberSpeed" to false, "defaultSpeed" to 1.25)
    @Before fun setup() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        // Robolectric does not automatically grant AndroidX's merged signature
        // permission, unlike an installed APK (verified in both merged manifests).
        shadowOf(application).grantPermissions("${application.packageName}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
        controller = Robolectric.buildService(PlaybackService::class.java).create()
        service = controller.get()
        val context = ApplicationProvider.getApplicationContext<Context>()
        media = File.createTempFile("playback-policy-", ".wav", context.cacheDir)
        // Policy tests do not claim decoder support. Keep the local source nonempty.
        media.writeBytes(ByteArray(128) { 0 })
    }
    @After fun cleanup() {
        if (this::service.isInitialized) controller.destroy()
        if (this::media.isInitialized) media.delete()
    }
    private fun load(preferences: Map<String, Any?> = foregroundPrefs) {
        service.load(mapOf("generation" to 8L, "index" to 0, "preferences" to preferences,
            "queue" to listOf(mapOf("id" to "local", "filePath" to media.absolutePath,
                "title" to "Offline fixture", "isAudio" to false))))
    }
    @Test fun acceptsOnlyLocalAbsoluteSources() {
        for (path in listOf("https://example.com/video.mp4", "relative.mp4")) {
            assertThrows(IllegalArgumentException::class.java) {
                service.load(mapOf("generation" to 1L, "index" to 0,
                    "queue" to listOf(mapOf("filePath" to path))))
            }
        }
        assertTrue((service.snapshot()["queue"] as List<*>).isEmpty())
    }
    @Test fun foregroundOnlyPausesOnStopAndRestoresRenderingWithoutReplacingQueue() {
        load()
        assertEquals(1.25, service.snapshot()["speed"])
        assertTrue(service.showVideo())
        assertEquals(true, service.snapshot()["playRequested"])
        service.command("pause", mapOf("generation" to 7L))
        assertEquals(true, service.snapshot()["playRequested"])
        val before = service.snapshot()["queue"]
        service.setVisible(false)
        assertFalse(service.showVideo())
        assertEquals(false, service.snapshot()["playRequested"])
        service.command("play", mapOf("generation" to 8L))
        assertEquals(false, service.snapshot()["playRequested"])
        service.setVisible(true)
        assertTrue(service.showVideo())
        assertEquals(before, service.snapshot()["queue"])
        assertEquals(0, service.getSessions().size)
    }
    @Test fun temporarySpeedRestoresOnBackgroundAndPipWithoutReplacingQueue() {
        load(foregroundPrefs + mapOf("rememberSpeed" to true, "lastSpeed" to 1.75))
        val queue = service.snapshot()["queue"]
        service.command("speed", mapOf("generation" to 8L, "speed" to 2.0,
            "temporary" to true, "holding" to true))
        assertEquals(2.0, service.snapshot()["speed"])
        service.setVisible(false)
        assertEquals(1.75, service.snapshot()["speed"])
        service.setVisible(true)
        service.command("speed", mapOf("generation" to 8L, "speed" to 2.0,
            "temporary" to true, "holding" to true))
        service.setPip(true)
        assertEquals(1.75, service.snapshot()["speed"])
        assertEquals(queue, service.snapshot()["queue"])
    }

    @Test fun backgroundPlaybackRequiresSessionAndClosePreservesSource() {
        load(foregroundPrefs + mapOf("background" to true, "screenOff" to true))
        assertEquals(1, service.getSessions().size)
        service.command("timer", mapOf("generation" to 8L, "minutes" to 10))
        assertTrue((service.snapshot()["timerRemaining"] as Long) > 0)
        service.command("audioOnly", mapOf("generation" to 8L, "enabled" to true))
        assertFalse(service.showVideo())
        service.close()
        assertEquals(true, service.snapshot()["closed"])
        assertTrue((service.snapshot()["queue"] as List<*>).isEmpty())
        assertEquals(0L, service.snapshot()["timerRemaining"])
        assertEquals(0, service.getSessions().size)
        assertEquals(128L, media.length())
    }
    @Test fun unreadableSelectionProducesErrorWithoutStartingAnotherItem() {
        service.load(mapOf("generation" to 2L, "index" to 1, "preferences" to foregroundPrefs,
            "queue" to listOf(
                mapOf("id" to "ok", "title" to "Existing", "filePath" to media.absolutePath),
                mapOf("id" to "missing", "title" to "Missing", "filePath" to "${media.absolutePath}.missing"))))
        assertEquals(1, service.snapshot()["index"])
        assertNotNull(service.snapshot()["error"])
        assertEquals(false, service.snapshot()["initialized"])
        assertEquals(false, service.snapshot()["playing"])
        assertEquals(false, service.snapshot()["playRequested"])
    }
    @Test fun preferencesChangeSessionAndAudioOnlyWithoutReplacingMedia() {
        load()
        val originalQueue = service.snapshot()["queue"]
        service.command("audioOnly", mapOf("generation" to 8L, "enabled" to true))
        assertFalse(service.showVideo())
        service.command("preferences", foregroundPrefs + mapOf("generation" to 8L, "notifications" to true, "audioOnly" to false))
        assertTrue(service.showVideo())
        assertEquals(originalQueue, service.snapshot()["queue"])
        assertEquals(1, service.getSessions().size)
        service.command("preferences", foregroundPrefs + mapOf("generation" to 8L))
        assertEquals(0, service.getSessions().size)
        service.command("preferences", foregroundPrefs + mapOf("generation" to 8L, "background" to true))
        assertEquals(1, service.getSessions().size)
    }

    @Test fun changingTheQueueDoesNotResetAnActiveSleepDeadline() {
        load()
        service.command("timer", mapOf("generation" to 8L, "minutes" to 1))
        val remaining = service.snapshot()["timerRemaining"] as Long
        load()
        service.command("timer", mapOf("generation" to 8L, "minutes" to 30, "onlyIfInactive" to true))
        val after = service.snapshot()["timerRemaining"] as Long
        assertTrue(after > 0 && after <= remaining)
        service.close()
        assertEquals(0L, service.snapshot()["timerRemaining"])
    }

    @Test fun explicitOpenReadsSavedTimestampAfterServiceRecreationAndHonorsOptOut() {
        controller.destroy()
        val context = ApplicationProvider.getApplicationContext<Context>()
        PlaybackBookmarks(context.getSharedPreferences("mediagrab_playback_history_v1", Context.MODE_PRIVATE))
            .save(media, 42000, 300000)
        controller = Robolectric.buildService(PlaybackService::class.java).create()
        service = controller.get()
        load()
        assertEquals(42000L, service.snapshot()["position"])
        load(foregroundPrefs + mapOf("rememberPosition" to false))
        assertEquals(0L, service.snapshot()["position"])
        assertEquals(128L, media.length())
    }

}
