package com.mediagrab.mediagrab.playback

/** Monotonic time, independent of media position, playback speed and wall clock. */
internal class SleepDeadline(private val now: () -> Long) {
    private var deadline: Long? = null
    fun set(minutes: Int) { deadline = if (minutes <= 0) null else now() + minutes.coerceAtMost(1440) * 60_000L }
    fun remaining(): Long = deadline?.let { (it - now()).coerceAtLeast(0L) } ?: 0L
    fun active(): Boolean = deadline != null
    fun expired(): Boolean = active() && remaining() == 0L
    fun clear() { deadline = null }
    fun gain(fade: Boolean): Float = if (!active() || !fade) 1f else (remaining() / 5000f).coerceIn(0f, 1f)
}
