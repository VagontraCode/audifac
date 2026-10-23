package com.gtongfa.audifac.dsp

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

class ResamplerTest {
    private fun sine(freq: Double, rate: Int, frames: Int, channels: Int = 2, amp: Double = 0.5) =
        FloatArray(frames * channels) { i -> (amp * sin(2 * PI * freq * (i / channels) / rate)).toFloat() }

    /** All output of [r] for [input], fed in [chunk]-frame pieces, then flushed. */
    private fun run(r: Resampler, input: FloatArray, channels: Int = 2, chunk: Int = 1000): FloatArray {
        val out = ArrayList<Float>()
        val frames = input.size / channels
        var done = 0
        while (done < frames) {
            val n = minOf(chunk, frames - done)
            val got = r.process(input, n, done * channels)
            for (i in 0 until got * channels) out += r.out[i]
            done += n
        }
        val got = r.flush()
        for (i in 0 until got * channels) out += r.out[i]
        return out.toFloatArray()
    }

    /** RMS error (dB relative to the signal) of channel 0 against an ideal sine, away from the ends. */
    private fun errorDb(out: FloatArray, freq: Double, rate: Int, channels: Int = 2, amp: Double = 0.5): Double {
        val frames = out.size / channels
        var err = 0.0
        var sig = 0.0
        for (k in frames / 4 until frames * 3 / 4) {
            val ideal = amp * sin(2 * PI * freq * k / rate)
            val d = out[k * channels] - ideal
            err += d * d
            sig += ideal * ideal
        }
        return 10 * log10(err / sig)
    }

    private fun rmsDb(out: FloatArray, channels: Int = 2): Double {
        val frames = out.size / channels
        var s = 0.0
        var n = 0
        for (k in frames / 4 until frames * 3 / 4) {
            s += out[k * channels].toDouble() * out[k * channels]
            n++
        }
        return 20 * log10(sqrt(s / n) / (0.5 / sqrt(2.0)))
    }

    @Test
    fun cdToDeviceRateIsAccurateAndOnTime() {
        // 44.1 → 48 kHz: the result is the same 1 kHz sine at 48 kHz, in phase
        // (filter delay compensated), error far below audibility.
        val out = run(Resampler(44_100, 48_000, 2), sine(1000.0, 44_100, 44_100))
        assertTrue("error ${errorDb(out, 1000.0, 48_000)} dB", errorDb(out, 1000.0, 48_000) < -80)
    }

    @Test
    fun hiResDownToDeviceRate() {
        val out = run(Resampler(96_000, 48_000, 2), sine(1000.0, 96_000, 96_000))
        assertTrue(errorDb(out, 1000.0, 48_000) < -80)
    }

    @Test
    fun passbandIsFlat() {
        for (f in listOf(100.0, 10_000.0, 18_000.0)) {
            val out = run(Resampler(44_100, 48_000, 2), sine(f, 44_100, 44_100))
            assertEquals("$f Hz", 0.0, rmsDb(out), 0.05)
        }
        val edge = run(Resampler(44_100, 48_000, 2), sine(19_500.0, 44_100, 44_100))
        assertEquals("19.5 kHz", 0.0, rmsDb(edge), 0.5)
    }

    @Test
    fun contentAboveTheNewNyquistIsRemoved() {
        // 48 → 44.1 kHz: 23 kHz can't exist at 44.1 kHz and must not alias back.
        val out = run(Resampler(48_000, 44_100, 2), sine(23_000.0, 48_000, 48_000))
        assertTrue("${rmsDb(out)} dB", rmsDb(out) < -80)
    }

    @Test
    fun frameCountIsExact() {
        for ((a, b) in listOf(44_100 to 48_000, 48_000 to 44_100, 96_000 to 48_000, 22_050 to 48_000)) {
            val out = run(Resampler(a, b, 2), sine(440.0, a, 12_345))
            val expected = Math.ceilDiv(12_345L * b, a.toLong())
            assertEquals("$a → $b", expected, (out.size / 2).toLong())
        }
    }

    @Test
    fun chunkingDoesNotChangeTheResult() {
        val input = sine(3000.0, 44_100, 20_000)
        val whole = run(Resampler(44_100, 48_000, 2), input, chunk = 20_000)
        val pieces = run(Resampler(44_100, 48_000, 2), input, chunk = 37)
        assertArrayEquals(whole, pieces, 0f)
    }

    @Test
    fun channelsStayApart() {
        val input = FloatArray(10_000 * 2) { i -> if (i % 2 == 0) 0.5f else 0f }
        val out = run(Resampler(44_100, 48_000, 2), input)
        for (k in out.size / 8 until out.size * 3 / 8) assertEquals(0f, out[k * 2 + 1], 1e-6f)
        for (k in out.size / 8 until out.size * 3 / 8) assertEquals(0.5f, out[k * 2], 1e-3f)
    }

    @Test
    fun oddRatiosAreLimited() {
        assertTrue(Resampler.supports(44_100, 48_000))
        assertTrue(Resampler.supports(11_025, 48_000))
        assertTrue(!Resampler.supports(44_101, 48_000))
        assertTrue(abs(1) == 1)
    }
}
