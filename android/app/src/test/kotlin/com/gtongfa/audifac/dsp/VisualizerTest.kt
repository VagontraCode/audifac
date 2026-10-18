package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin

class VisualizerTest {
    @Test
    fun fullScaleSineReadsZeroDbInItsBand() {
        val rate = 48_000
        Visualizer.enabled = true
        Visualizer.reset()
        val n = 8192
        val buf = FloatArray(n * 2) { i -> sin(2 * PI * 1000 * (i / 2) / rate).toFloat() }
        Visualizer.feed(buf, n, 2, rate, 0)
        Visualizer.playheadUs = n * 1_000_000L / rate
        val s = Visualizer.snapshot()!!
        assertEquals(0f, s.peakL, 0.1f)
        assertEquals(0f, s.rmsL, 0.2f)
        // The 1 kHz band: lo · (hi/lo)^(b/32) with lo = 30, hi = 20 000.
        val band = (32 * log10(1000.0 / 30) / log10(20_000.0 / 30)).toInt()
        assertEquals(0f, s.bands[band], 1.5f)
        assertTrue("far bands are quiet", s.bands[2] < -40 && s.bands[30] < -40)
        Visualizer.enabled = false
    }

    @Test
    fun followsThePlayheadNotTheWriteHead() {
        val rate = 48_000
        Visualizer.enabled = true
        Visualizer.reset()
        // 0.2 s of silence, then 0.2 s of tone; the playhead is still in the silence.
        val half = rate / 5
        val buf = FloatArray(half * 4) { i -> if (i / 2 < half) 0f else 0.5f * sin(2 * PI * 440 * (i / 2) / rate).toFloat() }
        Visualizer.feed(buf, half * 2, 2, rate, 0)
        Visualizer.playheadUs = 150_000 // 0.15 s
        assertTrue(Visualizer.snapshot()!!.peakL < -90)
        Visualizer.playheadUs = 400_000
        assertEquals(20 * log10(0.5), Visualizer.snapshot()!!.peakL.toDouble(), 0.2)
        Visualizer.enabled = false
        assertTrue(2.0.pow(11) == Visualizer.FFT_SIZE.toDouble())
    }
}
