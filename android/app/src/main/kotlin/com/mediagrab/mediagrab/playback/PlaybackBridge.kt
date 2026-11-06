package com.mediagrab.mediagrab.playback

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Rational
import android.view.WindowManager
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import com.mediagrab.mediagrab.MainActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

@UnstableApi
class PlaybackBridge(private val activity: MainActivity, engine: FlutterEngine) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(engine.dartExecutor.binaryMessenger, "mediagrab/playback")
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, "mediagrab/playback/events")
    private val textures = engine.renderer
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var sink: EventChannel.EventSink? = null
    private var service: PlaybackService? = null
    private var bound = false
    private var binding = false
    private var visible = true
    private var fullPlayer = false
    private var pip = false
    private var sourceRect: Rect? = null
    private var restoreRequested = false
    private val pending = mutableListOf<Pair<() -> Unit, (String) -> Unit>>()
    private val handler = Handler(Looper.getMainLooper())
    private var lastPipKey = ""
    private var disposed = false
    private var physicalLandscape: Boolean = activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    private var manualOrientation: Boolean? = null
    private fun followSystemRotation(force: Boolean = false) {
        val layoutLandscape = activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        val autoRotate = android.provider.Settings.System.getInt(activity.contentResolver,
            android.provider.Settings.System.ACCELEROMETER_ROTATION, 0) == 1
        // Keep an explicit button choice until the device catches up with that
        // choice. Releasing immediately while still held upright bounces a
        // landscape request straight back to portrait.
        val target = manualOrientation
        val caughtUp = physicalLandscape == layoutLandscape &&
            (target == null || (target == physicalLandscape && target == layoutLandscape))
        if (fullPlayer && visible && autoRotate && (force || caughtUp)) {
            manualOrientation = null
            if (activity.requestedOrientation != android.content.pm.ActivityInfo.SCREEN_ORIENTATION_USER) {
                activity.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_USER
            }
        }
    }
    private val orientationSensor = object : android.view.OrientationEventListener(activity) {
        override fun onOrientationChanged(orientation: Int) {
            when {
                orientation in 60..120 || orientation in 240..300 -> physicalLandscape = true
                orientation in 0..30 || orientation in 150..210 || orientation in 330..359 -> physicalLandscape = false
                else -> return
            }
            followSystemRotation()
        }
    }
    private fun updateOrientationSensor() {
        if (fullPlayer && visible && orientationSensor.canDetectOrientation()) orientationSensor.enable()
        else orientationSensor.disable()
    }
    private val rotationObserver = object : android.database.ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { followSystemRotation(force = true) }
    }
    private val supportsPip get() = Build.VERSION.SDK_INT >= 26 && activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (disposed) return
            binding = false
            service = (binder as PlaybackService.LocalBinder).service
            attachSurface()
            service?.setVisible(visible)
            service?.listener = ::publish
            val waiting = pending.toList(); pending.clear()
            waiting.forEach { it.first() }
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null; binding = false
            val waiting = pending.toList(); pending.clear()
            waiting.forEach { it.second("Playback service disconnected") }
            sink?.success(mapOf("queue" to emptyList<Any>(), "error" to "Playback service disconnected"))
        }
    }
    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.getStringExtra("command")) {
                "close" -> close()
                "play", "pause", "next", "previous" -> service?.command(intent.getStringExtra("command")!!, emptyMap())
            }
        }
    }
    init {
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
        activity.contentResolver.registerContentObserver(android.provider.Settings.System.getUriFor(
            android.provider.Settings.System.ACCELEROMETER_ROTATION), false, rotationObserver)
        ContextCompat.registerReceiver(activity, actionReceiver,
            IntentFilter("com.mediagrab.mediagrab.PLAYBACK_ACTION"), ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    private fun ensureService(action: () -> Unit, failure: (String) -> Unit) {
        if (service != null) { action(); return }
        pending.add(action to failure)
        if (binding) return
        binding = true
        val intent = Intent(activity, PlaybackService::class.java).setAction(PlaybackService.LOCAL_BIND)
        bound = activity.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        if (!bound) {
            binding = false
            val waiting = pending.toList(); pending.clear()
            waiting.forEach { it.second("Could not connect to playback service") }
        }
    }
    private fun attachSurface() {
        if (producer == null) {
            producer = textures.createSurfaceProducer().also { p ->
                p.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                    override fun onSurfaceAvailable() { service?.setSurface(p.surface); service?.snapshot()?.let(::publish) }
                    override fun onSurfaceCleanup() { service?.setSurface(null) }
                })
            }
        }
        producer?.let { service?.setSurface(it.surface) }
    }
    private fun publish(state: Map<String, Any?>) {
        if (disposed) return
        // Keep source-resolution buffers through full/mini transitions. Layout
        // bounds are only a PiP hint and must never reduce decoder resolution.
        service?.surfaceDimensions()?.let { (width, height) ->
            producer?.let { p ->
                if (width > 0 && height > 0 && (p.width != width || p.height != height)) {
                    p.setSize(width, height)
                }
            }
        }
        // MediaCodec determines the output buffer geometry. SurfaceProducer's
        // backend owns crop/rotation when supported; otherwise Flutter applies
        // the same format-based correction as video_player_android 2.12.2.
        val awake = visible && service?.showVideo() == true && state["playing"] == true
        if (awake) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        updatePip()
        sink?.success(state + mapOf("textureId" to producer?.id(), "pip" to pip,
            "pipSupported" to supportsPip, "restoreRequested" to restoreRequested,
            "rotation" to (if (producer?.handlesCropAndRotation() == true) 0 else service?.rotationCorrection() ?: 0)))
        restoreRequested = false
        if (state["closed"] == true) {
            val closingService = service
            handler.post { if (service === closingService && service?.snapshot()?.get("closed") == true) disconnect() }
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (PlaybackService.instance != null) ensureService({ service?.snapshot()?.let(::publish) }, { sink?.error("playback", it, null) })
    }
    override fun onCancel(arguments: Any?) { sink = null }
    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<String, Any?> ?: emptyMap()
        try {
            when (call.method) {
                "snapshot" -> {
                    if (PlaybackService.instance == null) result.success(mapOf("queue" to emptyList<Any>(), "pipSupported" to supportsPip))
                    else ensureService({ result.success(service!!.snapshot() + mapOf("textureId" to producer?.id(), "pipSupported" to supportsPip, "pip" to pip,
                        "rotation" to (if (producer?.handlesCropAndRotation() == true) 0 else service?.rotationCorrection() ?: 0))) }, { result.error("playback", it, null) })
                }
                "load" -> ensureService({
                    try { service!!.load(arguments); result.success(null) }
                    catch (e: Exception) { result.error("playback", e.message, null) }
                }, { result.error("playback", it, null) })
                "close" -> { service?.command("close", arguments); disconnect(); result.success(null) }
                "disconnect" -> { disconnect(); result.success(null) }
                "pip" -> {
                    if (enterPip()) result.success(null)
                    else result.error("pip_unavailable", "Picture-in-picture is unavailable or disabled", null)
                }
                "bounds" -> {
                    sourceRect = Rect((arguments["left"] as Number).toInt(), (arguments["top"] as Number).toInt(),
                        (arguments["right"] as Number).toInt(), (arguments["bottom"] as Number).toInt())
                    lastPipKey = ""; updatePip(); result.success(null)
                }
                "brightness" -> {
                    activity.window.attributes = activity.window.attributes.apply { screenBrightness = (arguments["brightness"] as Number).toFloat() }
                    result.success(null)
                }
                "getBrightness" -> {
                    val window = activity.window.attributes.screenBrightness
                    val level = if (window >= 0f) window else android.provider.Settings.System.getInt(
                        activity.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                    result.success(level.coerceIn(0f, 1f).toDouble())
                }
                "followSystemRotation" -> {
                    followSystemRotation()
                    result.success(null)
                }
                "orientationRequest" -> {
                    manualOrientation = arguments["landscape"] as? Boolean
                    result.success(null)
                }
                "presentation" -> {
                    fullPlayer = arguments["fullPlayer"] == true
                    if (!fullPlayer) manualOrientation = null
                    updateOrientationSensor()
                    result.success(null)
                }
                else -> { service?.command(call.method, arguments); result.success(null) }
            }
        } catch (e: Exception) { result.error("playback", e.message, null) }
    }
    private fun close() {
        service?.close(); disconnect()
        if (pip) activity.moveTaskToBack(true)
    }
    private fun disconnect() {
        service?.listener = null
        service?.setSurface(null)
        service = null
        if (bound) activity.unbindService(connection)
        bound = false; binding = false
        producer?.release(); producer = null
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        resetBrightness()
        lastPipKey = ""
        updatePip()
    }
    fun setVisible(value: Boolean) {
        visible = value
        updateOrientationSensor()
        service?.setVisible(value)
        if (!value) resetBrightness()
        if (value && PlaybackService.instance != null && service == null) ensureService({}, {})
    }
    private fun resetBrightness() {
        activity.window.attributes = activity.window.attributes.apply { screenBrightness = -1f }
    }
    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
        val size = service?.dimensions()
        val w = size?.first ?: 0; val h = size?.second ?: 0
        val ratio = if (w > 0 && h > 0) (w.toFloat() / h).coerceIn(1f / 2.39f, 2.39f) else 16f / 9
        builder.setAspectRatio(Rational((ratio * 10000).toInt(), 10000))
        sourceRect?.takeIf { !it.isEmpty }?.let { builder.setSourceRectHint(it) }
        val playing = service?.playing() == true
        val state = service?.snapshot()
        val index = (state?.get("index") as? Number)?.toInt() ?: 0
        val count = (state?.get("queue") as? List<*>)?.size ?: 0
        builder.setActions(PipControls.actions(activity, playing, index, count))
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setAutoEnterEnabled(service?.canPip() == true)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }
    private fun updatePip() {
        if (!supportsPip) return
        val state = service?.snapshot()
        val key = "${service?.canPip()}:${service?.playing()}:${service?.dimensions()}:${state?.get("index")}:${(state?.get("queue") as? List<*>)?.size}:$sourceRect"
        if (key == lastPipKey) return
        lastPipKey = key
        try { activity.setPictureInPictureParams(pipParams()) } catch (_: IllegalStateException) { }
    }
    fun enterPip(): Boolean {
        if (!supportsPip || service?.canPip() != true || pip) return false
        return try {
            val entered = activity.enterPictureInPictureMode(pipParams())
            if (entered) setPip(true)
            entered
        } catch (_: IllegalStateException) { false }
    }
    fun onUserLeave() { if (Build.VERSION.SDK_INT < 31) enterPip() }
    fun setPip(value: Boolean) {
        pip = value
        service?.setPip(value)
        if (!value) {
            handler.postDelayed({
                if (!disposed && !visible) service?.command("pause", emptyMap())
            }, 300)
        }
        service?.snapshot()?.let(::publish)
    }
    fun requestRestore() { restoreRequested = true; service?.snapshot()?.let(::publish) }
    fun dispose() {
        disposed = true
        orientationSensor.disable()
        activity.contentResolver.unregisterContentObserver(rotationObserver)
        handler.removeCallbacksAndMessages(null)
        pending.forEach { it.second("Playback view disposed") }; pending.clear()
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
        disconnect()
        activity.unregisterReceiver(actionReceiver)
    }
}
