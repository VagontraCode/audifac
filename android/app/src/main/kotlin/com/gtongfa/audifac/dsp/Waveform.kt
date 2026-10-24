package com.gtongfa.audifac.dsp

import android.content.Context
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * A song's loudness over time for the seek bar: the RMS level of [POINTS]
 * equal slices, as bytes (0 = silent … 255 = the loudest slice), on a 20 dB
 * scale below the loudest slice: loud masters vary by a few dB only, and
 * quieter passages show as clearly lower.
 */
class Waveform(private val durationUs: Long, private val points: Int = POINTS) {
    private val sumSq = DoubleArray(points)
    private val counts = LongArray(points)
    private var rate = 0
    private var channels = 0
    var frame = 0L
        private set

    fun format(rate: Int, channels: Int) {
        // Keep the position across a mid-stream format change.
        if (this.rate != 0 && this.rate != rate) frame = frame * rate / this.rate
        this.rate = rate
        this.channels = channels
    }

    fun add(samples: FloatArray, frames: Int) {
        if (rate == 0 || durationUs <= 0) return
        var i = 0
        for (f in 0 until frames) {
            var s = 0.0
            for (c in 0 until channels) {
                val x = samples[i + c].toDouble()
                s += x * x
            }
            i += channels
            val us = (frame + f) * 1_000_000 / rate
            val slice = (us * points / durationUs).toInt().coerceIn(0, points - 1)
            sumSq[slice] += s / channels
            counts[slice]++
        }
        frame += frames
    }

    fun levels(): ByteArray {
        val db = DoubleArray(points) { if (counts[it] == 0L) Double.NEGATIVE_INFINITY else 10 * log10(max(sumSq[it] / counts[it], 1e-12)) }
        val top = db.maxOrNull() ?: Double.NEGATIVE_INFINITY
        return ByteArray(points) {
            if (db[it] == Double.NEGATIVE_INFINITY || top == Double.NEGATIVE_INFINITY) 0
            else (((db[it] - top + RANGE_DB) / RANGE_DB).coerceIn(0.0, 1.0) * 255).toInt().toByte()
        }
    }

    companion object {
        const val POINTS = 200
        private const val RANGE_DB = 20.0

        /** [location] between [startMs] and [endMs] (null = the end, [durationMs] long), or null if it can't be decoded. */
        fun of(context: Context, location: String, startMs: Long, endMs: Long?, durationMs: Long): ByteArray? {
            val wave = Waveform(durationMs * 1000)
            val ok = PcmDecoder.decode(context, location, object : PcmDecoder.Sink {
                override fun format(rate: Int, channels: Int) = wave.format(rate, channels)
                override fun samples(samples: FloatArray, frames: Int) = wave.add(samples, frames)
            }, startUs = startMs * 1000, endUs = endMs?.let { it * 1000 } ?: Long.MAX_VALUE)
            return if (ok && wave.frame > 0) wave.levels() else null
        }
    }
}
