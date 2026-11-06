package com.mediagrab.mediagrab.playback

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlaybackBookmarksTest {
    @Test fun explicitReopenRestoresTimestampAcrossStoreRecreation() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("bookmark-test-reopen", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val file = File.createTempFile("bookmark", ".mp4", context.cacheDir).apply { writeText("local media") }
        try {
            PlaybackBookmarks(prefs).save(file, 42000, 300000)
            assertEquals(42000L, PlaybackBookmarks(prefs).read(file))
            // Replacing a source under the same path must not reuse its timestamp.
            file.appendText("replacement")
            assertEquals(0L, PlaybackBookmarks(prefs).read(file))
        } finally { file.delete() }
    }
    @Test fun completedItemsRestartAndOtherItemsKeepIndependentPositions() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("bookmark-test-completion", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val first = File.createTempFile("first", ".mp3", context.cacheDir).apply { writeText("a") }
        val second = File.createTempFile("second", ".mp4", context.cacheDir).apply { writeText("b") }
        try {
            val store = PlaybackBookmarks(prefs)
            store.save(first, 23000, 90000)
            store.save(second, 89999, 90000)
            assertEquals(23000L, store.read(first))
            assertEquals(0L, store.read(second))
            assertEquals("a", first.readText())
            assertEquals("b", second.readText())
        } finally { first.delete(); second.delete() }
    }
    @Test fun corruptHistoryDoesNotBlockPlayback() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("bookmark-test-corrupt", Context.MODE_PRIVATE)
        prefs.edit().putString("positions_v1", "invalid JSON").commit()
        assertEquals(0L, PlaybackBookmarks(prefs).read(File(context.cacheDir, "missing.mp4")))
    }
}
