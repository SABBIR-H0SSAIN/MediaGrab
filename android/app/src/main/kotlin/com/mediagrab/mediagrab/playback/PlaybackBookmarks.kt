package com.mediagrab.mediagrab.playback

import android.content.SharedPreferences
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Playback-owned history only. Never edits a media file or the download registry. */
internal class PlaybackBookmarks(private val preferences: SharedPreferences) {
    private val entries = try { JSONObject(preferences.getString("positions_v1", "{}") ?: "{}") }
        catch (_: Exception) { JSONObject() }
    private fun key(file: File): String = MessageDigest.getInstance("SHA-256")
        .digest(file.absolutePath.toByteArray()).joinToString("") { "%02x".format(it) }
    fun read(file: File): Long {
        val value = entries.optJSONObject(key(file)) ?: return 0
        if (!file.isFile || value.optLong("size") != file.length() || value.optLong("modified") != file.lastModified()) return 0
        return value.optLong("position").coerceAtLeast(0)
    }
    fun save(file: File, position: Long, duration: Long) {
        if (!file.isFile || duration <= 0) return
        // A completed item replays from the beginning on the next explicit open.
        val resume = if (position >= duration - 1500) 0 else position.coerceIn(0, duration)
        entries.put(key(file), JSONObject().put("size", file.length()).put("modified", file.lastModified())
            .put("position", resume).put("updated", System.currentTimeMillis()))
        val keys = entries.keys().asSequence().toList().sortedBy { entries.getJSONObject(it).optLong("updated") }
        keys.take((keys.size - 100).coerceAtLeast(0)).forEach { entries.remove(it) }
        preferences.edit().putString("positions_v1", entries.toString()).apply()
    }
}
