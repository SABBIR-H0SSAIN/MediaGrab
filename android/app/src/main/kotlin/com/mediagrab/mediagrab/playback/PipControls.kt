package com.mediagrab.mediagrab.playback

import android.app.PendingIntent
import android.app.RemoteAction
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon

/** Native PiP owns its close/expand chrome; transport has one centered Play/Pause. */
internal object PipControls {
    fun actions(context: Context, playing: Boolean, index: Int, count: Int): List<RemoteAction> {
        fun action(command: String, title: String, icon: Int, code: Int, enabled: Boolean = true): RemoteAction {
            val intent = Intent("com.mediagrab.mediagrab.PLAYBACK_ACTION")
                .setPackage(context.packageName).putExtra("command", command)
            return RemoteAction(Icon.createWithResource(context, icon), title, title,
                PendingIntent.getBroadcast(context, code, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)).apply { isEnabled = enabled }
        }
        return listOf(
            action("previous", "Previous", android.R.drawable.ic_media_previous, 191003, index > 0),
            action(if (playing) "pause" else "play", if (playing) "Pause" else "Play",
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, 191001),
            action("next", "Next", android.R.drawable.ic_media_next, 191004, index + 1 < count))
    }
}
