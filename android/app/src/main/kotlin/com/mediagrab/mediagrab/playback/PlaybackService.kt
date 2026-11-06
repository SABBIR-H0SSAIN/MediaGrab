package com.mediagrab.mediagrab.playback

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Surface
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.datasource.FileDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.CommandButton
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.mediagrab.mediagrab.MainActivity
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Owns the only Android production player, even when the Flutter view is absent. */
@UnstableApi
class PlaybackService : MediaSessionService() {
    companion object {
        const val LOCAL_BIND = "com.mediagrab.mediagrab.PLAYBACK_BIND"
        const val ACTION_STOP = "com.mediagrab.mediagrab.PLAYBACK_STOP"
        const val NOTIFICATION_ID = 190001
        var instance: PlaybackService? = null
            private set
    }
    inner class LocalBinder : Binder() { val service: PlaybackService get() = this@PlaybackService }
    private val binder = LocalBinder()
    private lateinit var player: ExoPlayer
    private lateinit var bookmarks: PlaybackBookmarks
    private var lastBookmarkWrite = 0L
    private var session: MediaSession? = null
    private val handler = Handler(Looper.getMainLooper())
    private val artworkWorker = Executors.newSingleThreadExecutor()
    private val timer = SleepDeadline(SystemClock::elapsedRealtime)
    private val readiness = PlaybackReadiness()
    private var prefs: Map<String, Any?> = emptyMap()
    private var queue: List<Map<String, Any?>> = emptyList()
    private var generation = 0L
    private var error: String? = null
    private var visible = true
    private var inPip = false
    private var audioOnly = false
    private var userVolume = 1f
    private var videoWidth = 0
    private var videoHeight = 0
    private var output: Surface? = null
    private var stopped = false
    private var closing = false
    private var selectedIndex = 0
    private var defaultSpeed = 1f
    private var heldSpeed: Float? = null
    private var autoInitialSpeed = 1f
    private var lastIndex = -1
    private val failedItems = mutableSetOf<Int>()
    var listener: ((Map<String, Any?>) -> Unit)? = null
        set(value) { field = value; if (::player.isInitialized) emit() }

    private fun flag(name: String, fallback: Boolean = true) = prefs[name] as? Boolean ?: fallback
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF && (!flag("background") || !flag("screenOff"))) {
                player.pause()
            }
        }
    }
    private val ticker = object : Runnable {
        override fun run() {
            if (stopped) return
            evaluateTimer()
            if (player.isPlaying && SystemClock.elapsedRealtime() - lastBookmarkWrite >= 5000) savePosition()
            if ((visible || inPip) && (player.isPlaying || timer.active())) emit()
            handler.postDelayed(this, if (((visible || inPip) && player.isPlaying) || (timer.active() && timer.remaining() <= 5000)) 200L else 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        bookmarks = PlaybackBookmarks(getSharedPreferences("mediagrab_playback_history_v1", MODE_PRIVATE))
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this)
            .setChannelId("mediagrab_playback")
            .setNotificationId(NOTIFICATION_ID)
            .build())
        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(FileDataSource.Factory()))
            .build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
            addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) {
                    if (stopped || closing) return
                    if (events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION) && lastIndex != player.currentMediaItemIndex) {
                        readiness.reset()
                        videoWidth = 0; videoHeight = 0
                        if (lastIndex >= 0 && lastIndex != player.currentMediaItemIndex) {
                            heldSpeed = null
                            this@PlaybackService.player.setPlaybackSpeed(defaultSpeed)
                        }
                        lastIndex = player.currentMediaItemIndex
                        updateRendering()
                        prepareArtwork(lastIndex)
                    }
                    readiness.update(player.playbackState)
                    if (events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED) && player.playbackState == Player.STATE_READY) error = null
                    emit()
                }
                override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
                    if (!closing && reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION &&
                        oldPosition.mediaItemIndex != newPosition.mediaItemIndex) {
                        queue.getOrNull(oldPosition.mediaItemIndex)?.get("filePath")?.let { path ->
                            bookmarks.save(File(path as String), 0, 1)
                        }
                    }
                }
                override fun onTracksChanged(tracks: Tracks) {
                    if (stopped || tracks.isEmpty) return
                    val index = player.currentMediaItemIndex
                    if (index !in queue.indices) return
                    val actualAudio = tracks.groups.any { it.type == C.TRACK_TYPE_AUDIO } &&
                        tracks.groups.none { it.type == C.TRACK_TYPE_VIDEO }
                    if (actualAudio && queue[index]["isAudio"] != true) {
                        queue = queue.mapIndexed { i, item -> if (i == index) item + ("isAudio" to true) else item }
                        updateRendering(); emit()
                    }
                }
                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (stopped) return
                    videoWidth = (videoSize.width * videoSize.pixelWidthHeightRatio).toInt()
                    videoHeight = videoSize.height
                    emit()
                }
                override fun onPlayerError(playbackError: PlaybackException) {
                    if (stopped) return
                    readiness.reset()
                    error = "Cannot play this local file (${playbackError.errorCodeName}). Try an external player."
                    failedItems.add(player.currentMediaItemIndex)
                    emit()
                    // Bound the search to this queue; never loop through broken files.
                    val next = ((player.currentMediaItemIndex + 1) until queue.size)
                        .firstOrNull { it !in failedItems && validFile(queue[it]["filePath"] as? String) }
                    val token = generation
                    val continuePlaying = player.playWhenReady
                    if (next != null) handler.post {
                        if (!stopped && token == generation && next in queue.indices) {
                            player.seekToDefaultPosition(next)
                            player.prepare()
                            if (continuePlaying) command("play", emptyMap())
                        }
                    }
                }
            })
        }
        ContextCompat.registerReceiver(this, screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED)
        handler.post(ticker)
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == LOCAL_BIND) binder else super.onBind(intent)

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    private fun updateSession() {
        val wanted = flag("background") || flag("notifications")
        if (wanted && session == null) {
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("openPlayback", true)
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val controlledPlayer = object : ForwardingPlayer(player) {
                override fun play() { command("play", emptyMap()) }
                override fun pause() { command("pause", emptyMap()) }
                override fun setPlayWhenReady(playWhenReady: Boolean) {
                    command(if (playWhenReady) "play" else "pause", emptyMap())
                }
                override fun stop() { handler.post { close() } }
            }
            session = MediaSession.Builder(this, controlledPlayer)
                .setCallback(object : MediaSession.Callback {
                    override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
                        // Remote controls may control this queue, never inject arbitrary URIs.
                        return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                            .setAvailablePlayerCommands(MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS.buildUpon()
                                .remove(Player.COMMAND_SET_MEDIA_ITEM).remove(Player.COMMAND_CHANGE_MEDIA_ITEMS).build())
                            .build()
                    }
                })
                .setMediaButtonPreferences(listOf(CommandButton.Builder(CommandButton.ICON_STOP)
                    .setDisplayName("Stop playback").setPlayerCommand(Player.COMMAND_STOP).build()))
                .setSessionActivity(PendingIntent.getActivity(this, 190002, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                .build().also { addSession(it) }
        } else if (!wanted && session != null) {
            session?.let { removeSession(it); it.release() }
            session = null
        }
    }

    private fun validFile(path: String?): Boolean = path != null && File(path).let { it.isAbsolute && it.isFile && it.canRead() && it.length() > 0 }

    @Suppress("UNCHECKED_CAST")
    fun load(arguments: Map<String, Any?>) {
        restoreHeldSpeed()
        val selected = (arguments["index"] as? Number)?.toInt() ?: 0
        val incoming = (arguments["queue"] as? List<*>)?.map { raw ->
            val item = raw as? Map<String, Any?> ?: throw IllegalArgumentException("Invalid playback item")
            val path = item["filePath"] as? String ?: ""
            require(File(path).isAbsolute && !path.contains("://")) { "Only absolute local media files are accepted" }
            mapOf("id" to (item["id"] as? String ?: path), "filePath" to path,
                "title" to (item["title"] as? String ?: "MediaGrab"),
                "isAudio" to (item["isAudio"] == true),
                "artworkPath" to (item["artworkPath"] as? String)?.takeIf { validFile(it) })
        } ?: emptyList()
        require(incoming.isNotEmpty() && selected in incoming.indices) { "Invalid playback queue" }
        savePosition()
        generation = (arguments["generation"] as Number).toLong()
        closing = false; selectedIndex = selected
        readiness.reset()
        player.pause()
        player.clearMediaItems()
        userVolume = 1f; audioOnly = false; error = null
        queue = incoming; failedItems.clear(); lastIndex = -1; videoWidth = 0; videoHeight = 0
        prefs = arguments["preferences"] as? Map<String, Any?> ?: emptyMap()
        defaultSpeed = ((if (flag("rememberSpeed")) prefs["lastSpeed"] else prefs["defaultSpeed"]) as? Number)?.toFloat() ?: 1f
        autoInitialSpeed = defaultSpeed
        updateSession()
        if (!validFile(queue[selected]["filePath"] as? String)) {
            error = "File not found or not readable on device"
            emit(); return
        }
        val items = queue.map(::mediaItem)
        player.setMediaItems(items, selected, if (flag("rememberPosition")) bookmarks.read(File(queue[selected]["filePath"] as String)) else 0L)
        player.setPlaybackSpeed(autoInitialSpeed)
        applyVolume()
        updateRendering()
        player.prepare()
        if (visible || (flag("background") && screenAllowed())) player.play()
        emit()
    }

    private fun mediaItem(item: Map<String, Any?>): MediaItem = MediaItem.Builder()
        .setMediaId(item["id"] as String)
        .setUri(Uri.fromFile(File(item["filePath"] as String)))
        .setMediaMetadata(MediaMetadata.Builder().setTitle(item["title"] as String)
            .setArtworkUri((item["artworkPath"] as? String)?.let { Uri.fromFile(File(it)) }).build())
        .build()

    private fun screenAllowed() = flag("screenOff") || (getSystemService(POWER_SERVICE) as PowerManager).isInteractive

    @Suppress("UNCHECKED_CAST")
    fun command(name: String, arguments: Map<String, Any?>) {
        if (name == "close") {
            generation = (arguments["generation"] as? Number)?.toLong() ?: generation + 1
            close(); return
        }
        if ((arguments["generation"] as? Number)?.toLong()?.let { it != generation } == true) return
        when (name) {
            "play" -> {
                if (timer.expired()) { evaluateTimer(); return }
                if (!visible && !inPip && (!flag("background") || !screenAllowed())) return
                if (player.playbackState == Player.STATE_ENDED) player.seekToDefaultPosition()
                if (player.playbackState == Player.STATE_IDLE && queue.isNotEmpty()) player.prepare()
                player.play()
            }
            "pause" -> { restoreHeldSpeed(); player.pause(); savePosition() }
            "seek" -> { player.seekTo((arguments["position"] as Number).toLong().coerceIn(0, duration())); savePosition() }
            "speed" -> {
                val speed = (arguments["speed"] as Number).toFloat().coerceIn(.25f, 2f)
                if (arguments["temporary"] == true && arguments["holding"] == true) {
                    if (visible && heldSpeed == null) heldSpeed = player.playbackParameters.speed
                    if (!visible) return
                } else heldSpeed = null
                player.setPlaybackSpeed(speed)
                if (arguments["temporary"] != true && flag("rememberSpeed")) defaultSpeed = speed
            }
            "volume" -> { userVolume = (arguments["volume"] as Number).toFloat().coerceIn(0f, 1f); applyVolume() }
            "loop" -> player.repeatMode = if (arguments["loop"] == true) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            "next" -> if (player.hasNextMediaItem()) { restoreHeldSpeed(); savePosition(); error = null; player.seekToNextMediaItem(); player.prepare() }
            "previous" -> if (player.hasPreviousMediaItem()) { restoreHeldSpeed(); savePosition(); error = null; player.seekToPreviousMediaItem(); player.prepare() }
            "audioOnly" -> { audioOnly = arguments["enabled"] == true && flag("audioOnly"); updateRendering() }
            "visible" -> setVisible(arguments["visible"] == true)
            "timer" -> {
                if (arguments["onlyIfInactive"] != true || !timer.active()) {
                    timer.set((arguments["minutes"] as Number).toInt()); applyVolume()
                }
            }
            "preferences" -> {
                prefs = arguments
                defaultSpeed = ((if (flag("rememberSpeed")) prefs["lastSpeed"] else prefs["defaultSpeed"]) as? Number)?.toFloat() ?: 1f
                if (!flag("audioOnly")) audioOnly = false
                updateSession()
                if (!visible && !inPip && (!flag("background") || !screenAllowed())) player.pause()
                updateRendering(); applyVolume()
            }
        }
        emit()
    }

    fun setVisible(value: Boolean) {
        if (!value) restoreHeldSpeed()
        if (!value) savePosition()
        visible = value
        evaluateTimer()
        if (!visible && !inPip && (!flag("background") || !screenAllowed())) player.pause()
        updateRendering()
        emit()
    }
    private fun restoreHeldSpeed() {
        val speed = heldSpeed ?: return
        heldSpeed = null
        player.setPlaybackSpeed(speed)
    }
    fun setPip(value: Boolean) { restoreHeldSpeed(); inPip = value; updateRendering(); emit() }
    fun setSurface(surface: Surface?) { output = surface; updateRendering() }
    fun canPip(): Boolean = flag("pip") && queue.isNotEmpty() &&
        queue.getOrNull(player.currentMediaItemIndex)?.get("isAudio") != true && !audioOnly && player.isPlaying
    fun playing(): Boolean = player.isPlaying
    fun showVideo(): Boolean = queue.isNotEmpty() && queue.getOrNull(player.currentMediaItemIndex)?.get("isAudio") != true && !audioOnly && (visible || inPip)
    fun dimensions(): Pair<Int, Int> = Pair(videoWidth, videoHeight)
    fun surfaceDimensions(): Pair<Int, Int> = Pair(player.videoSize.width, player.videoSize.height)
    fun rotationCorrection(): Int = player.videoFormat?.rotationDegrees?.takeIf { it == 0 || it == 90 || it == 180 || it == 270 } ?: 0

    private fun updateRendering() {
        val render = showVideo()
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, !render).build()
        if (render && output?.isValid == true) player.setVideoSurface(output) else player.clearVideoSurface()
    }
    private fun applyVolume() { player.volume = userVolume * timer.gain(flag("fadeOut", false)) }
    private fun evaluateTimer() {
        if (timer.expired()) {
            // pause() clears playWhenReady so audio-focus gain cannot restart it.
            player.pause(); timer.clear(); player.volume = userVolume; emit()
        } else if (timer.active()) applyVolume()
    }
    private fun savePosition() {
        if (!::bookmarks.isInitialized || !::player.isInitialized || !flag("rememberPosition") || error != null || !readiness.initialized) return
        val path = queue.getOrNull(player.currentMediaItemIndex)?.get("filePath") as? String ?: return
        bookmarks.save(File(path), player.currentPosition, duration())
        lastBookmarkWrite = SystemClock.elapsedRealtime()
    }

    private fun duration(): Long = player.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0L
    fun snapshot(): Map<String, Any?> = mapOf(
        "queue" to queue, "index" to (if (player.mediaItemCount == 0) selectedIndex else player.currentMediaItemIndex.coerceAtLeast(0)),
        "closed" to closing,
        "generation" to generation, "initialized" to (error == null && readiness.initialized),
        "playing" to (error == null && readiness.showPause(player.playWhenReady, player.playbackState)), "playRequested" to player.playWhenReady, "loading" to (player.playbackState == Player.STATE_BUFFERING),
        "position" to player.currentPosition.coerceAtLeast(0), "duration" to duration(),
        "speed" to player.playbackParameters.speed.toDouble(), "volume" to userVolume.toDouble(),
        "loop" to (player.repeatMode == Player.REPEAT_MODE_ONE),
        "audioOnly" to (audioOnly || queue.getOrNull(player.currentMediaItemIndex)?.get("isAudio") == true),
        "width" to videoWidth, "height" to videoHeight, "pip" to inPip,
        "timerRemaining" to timer.remaining(), "error" to error)
    private fun emit() { if (!stopped && ::player.isInitialized) listener?.invoke(snapshot()) }

    private fun prepareArtwork(index: Int) {
        if (stopped || closing) return
        val item = queue.getOrNull(index) ?: return
        if (item["artworkPath"] != null) return
        val token = generation
        val path = item["filePath"] as String
        artworkWorker.execute {
            val retriever = MediaMetadataRetriever()
            try {
                val source = File(path)
                val hash = MessageDigest.getInstance("SHA-256").digest("$path:${source.length()}:${source.lastModified()}".toByteArray())
                    .joinToString("") { "%02x".format(it) }
                val folder = File(cacheDir, "playback-artwork").apply { mkdirs() }
                val destination = File(folder, "$hash.jpg")
                if (!destination.isFile) {
                    // A bounded playback-owned cache; never touch original media.
                    folder.listFiles()?.sortedBy { it.lastModified() }?.let { files ->
                        if (files.size >= 64) files.take(files.size - 63).forEach { it.delete() }
                    }
                    retriever.setDataSource(path)
                    val embedded = retriever.embeddedPicture
                    val bitmap = if (embedded == null && item["isAudio"] != true)
                        if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 320, 180)
                        else retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { frame ->
                            val scaled = Bitmap.createScaledBitmap(frame, 320, 180, true)
                            if (scaled !== frame) frame.recycle()
                            scaled
                        }
                        else null
                    if (embedded != null && embedded.size <= 2 * 1024 * 1024) destination.writeBytes(embedded)
                    else if (bitmap != null) {
                        destination.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                        bitmap.recycle()
                    }
                }
                if (destination.isFile) handler.post {
                    if (stopped || token != generation || queue.getOrNull(index)?.get("filePath") != path) return@post
                    queue = queue.mapIndexed { i, old -> if (i == index) old + ("artworkPath" to destination.absolutePath) else old }
                    if (index < player.mediaItemCount) player.replaceMediaItem(index, mediaItem(queue[index]))
                    emit()
                }
            } catch (_: Exception) { /* Placeholder artwork is valid offline behavior. */ }
            catch (_: OutOfMemoryError) { /* Large/invalid embedded artwork must not stop playback. */ }
            finally { retriever.release() }
        }
    }

    fun close() {
        savePosition()
        closing = true
        readiness.reset()
        timer.clear(); player.pause(); player.clearMediaItems(); queue = emptyList(); error = null
        audioOnly = false; inPip = false; videoWidth = 0; videoHeight = 0
        emit()
        session?.let { removeSession(it); it.release() }; session = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!flag("background") || !player.playWhenReady) close()
    }
    override fun onDestroy() {
        savePosition()
        stopped = true
        handler.removeCallbacksAndMessages(null)
        unregisterReceiver(screenReceiver)
        artworkWorker.shutdownNow()
        session?.let { removeSession(it); it.release() }; session = null
        player.release(); listener = null; output = null
        if (instance === this) instance = null
        super.onDestroy()
    }
}
