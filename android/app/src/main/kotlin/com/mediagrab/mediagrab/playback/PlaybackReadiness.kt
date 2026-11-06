package com.mediagrab.mediagrab.playback

import androidx.media3.common.Player

/** Timeline readiness survives a seek's transient buffering state. */
internal class PlaybackReadiness {
    var initialized = false
        private set

    // Buffering and transient focus suppression still need a Pause action so
    // the user can cancel the pending playback intent.
    fun showPause(playWhenReady: Boolean, state: Int): Boolean =
        playWhenReady && (state == Player.STATE_READY || state == Player.STATE_BUFFERING)

    fun reset() { initialized = false }
    fun update(state: Int) {
        when (state) {
            Player.STATE_READY, Player.STATE_ENDED -> initialized = true
            Player.STATE_IDLE -> initialized = false
            // BUFFERING before the first ready frame is loading; after ready it
            // is a seek/rebuffer and must not remove the transport controls.
        }
    }
}
