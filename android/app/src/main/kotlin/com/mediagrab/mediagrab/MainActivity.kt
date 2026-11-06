package com.mediagrab.mediagrab

import android.content.Intent
import android.content.res.Configuration
import androidx.media3.common.util.UnstableApi
import com.mediagrab.mediagrab.playback.PlaybackBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

@UnstableApi
class MainActivity : FlutterActivity() {
    private var playback: PlaybackBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playback = PlaybackBridge(this, flutterEngine)
        if (intent?.getBooleanExtra("openPlayback", false) == true) playback?.requestRestore()
    }
    override fun onStart() { super.onStart(); playback?.setVisible(true) }
    override fun onStop() { playback?.setVisible(false); super.onStop() }
    override fun onUserLeaveHint() { playback?.onUserLeave(); super.onUserLeaveHint() }
    override fun onPictureInPictureModeChanged(inPip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(inPip, configuration)
        playback?.setPip(inPip)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("openPlayback", false)) playback?.requestRestore()
    }
    override fun onDestroy() { playback?.dispose(); playback = null; super.onDestroy() }
}
