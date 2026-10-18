package com.gtongfa.audifac.dsp

import java.util.concurrent.ConcurrentHashMap
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Crossfade settings from the app (0 s = gapless, no crossfade). */
object Crossfade {
    @Volatile
    var seconds: Double = 0.0

    /** Album of each queued file (by [SourceUri] key): tracks of one album never crossfade. */
    private val albums = ConcurrentHashMap<String, Long>()

    fun setAlbums(map: Map<String, Long>) {
        albums.keys.retainAll(map.keys)
        albums.putAll(map)
    }

    /** Fade between the files [from] and [to]? */
    fun between(from: String?, to: String?): Boolean {
        if (seconds <= 0.0) return false
        val a = from?.let { albums[it] }
        val b = to?.let { albums[it] }
        return !(a != null && a == b)
    }
}

/**
 * Interleaved float frames waiting to be played, as a ring buffer, with the
 * presentation time of each run of continuous frames (a run starts wherever
 * the stream's timestamps jump, e.g. where a crossfade begins).
 */
class HeldAudio(private val channels: Int, private val rate: Int) {
    private var ring = FloatArray(0)
    private var capacity = 0 // frames
    private var start = 0 // ring index (frames) of the oldest frame
    var frames = 0
        private set

    /** Absolute frame number of the oldest held frame. */
    private var frontAbs = 0L

    /** (absolute frame, presentation time µs) where each run starts. */
    private val anchors = ArrayDeque<Pair<Long, Long>>()

    private fun usFor(frameCount: Long) = frameCount * 1_000_000L / rate

    fun clear() {
        frames = 0
        start = 0
        anchors.clear()
    }

    /** Appends [n] frames from [src] (interleaved, from index 0) presented at [pts]. */
    fun append(src: FloatArray, n: Int, pts: Long) {
        if (n <= 0) return
        ensureCapacity(frames + n)
        val endAbs = frontAbs + frames
        val expected = anchors.lastOrNull()?.let { (abs, t) -> t + usFor(endAbs - abs) }
        if (frames == 0 || expected == null || kotlin.math.abs(expected - pts) > 1000) anchors.addLast(endAbs to pts)
        var write = (start + frames) % capacity
        var done = 0
        while (done < n) {
            val run = minOf(n - done, capacity - write)
            System.arraycopy(src, done * channels, ring, write * channels, run * channels)
            done += run
            write = (write + run) % capacity
        }
        frames += n
    }

    private fun ensureCapacity(needed: Int) {
        if (needed <= capacity) return
        val next = maxOf(needed, capacity * 2, rate / 2)
        val copy = FloatArray(next * channels)
        copyOut(copy, 0, frames)
        ring = copy
        capacity = next
        start = 0
    }

    /** Copies the oldest [n] frames to [dst] (not removing them). */
    fun copyOut(dst: FloatArray, dstFrame: Int, n: Int) {
        var read = start
        var done = 0
        while (done < n) {
            val run = minOf(n - done, capacity - read)
            System.arraycopy(ring, read * channels, dst, (dstFrame + done) * channels, run * channels)
            done += run
            read = (read + run) % capacity
        }
    }

    /** Frames from the front up to the next timestamp jump (at most [max]). */
    fun runLength(max: Int): Int {
        val next = anchors.drop(1).firstOrNull()?.first
        val untilJump = if (next == null) frames.toLong() else next - frontAbs
        return minOf(max.toLong(), untilJump, frames.toLong()).toInt()
    }

    /** Presentation time of the oldest held frame. */
    fun frontPts(): Long {
        val (abs, t) = anchors.first()
        return t + usFor(frontAbs - abs)
    }

    fun drop(n: Int) {
        start = (start + n) % maxOf(capacity, 1)
        frames -= n
        frontAbs += n
        while (anchors.size > 1 && anchors.elementAt(1).first <= frontAbs) anchors.removeFirst()
        if (frames == 0) anchors.clear()
    }

    /** Removes everything into a plain array (the tail to fade out). */
    fun takeAll(): FloatArray {
        val out = FloatArray(frames * channels)
        copyOut(out, 0, frames)
        drop(frames)
        return out
    }
}

/** Equal-power crossfade of [fadeOut] (old song tail) into new frames. */
class FadeMixer(private val fadeOut: FloatArray, private val channels: Int) {
    private val length = fadeOut.size / channels
    private var pos = 0

    val done get() = pos >= length

    /** Mixes into [frames] interleaved frames of [dst] starting at frame [from]. */
    fun mix(dst: FloatArray, from: Int, frames: Int) {
        var f = 0
        while (f < frames && pos < length) {
            val t = (pos + 0.5) / length
            val gin = sin(t * PI / 2).toFloat()
            val gout = cos(t * PI / 2).toFloat()
            val di = (from + f) * channels
            val si = pos * channels
            for (c in 0 until channels) {
                val v = dst[di + c] * gin + fadeOut[si + c] * gout
                dst[di + c] = v.coerceIn(-1f, 1f)
            }
            f++
            pos++
        }
    }
}
