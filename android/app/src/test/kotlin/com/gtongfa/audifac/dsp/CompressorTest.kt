package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

class CompressorTest {
    private val rate = 48_000

    private fun levelDb(amp: Double, config: DspConfig): Double {
        val frames = rate
        val buf = FloatArray(frames * 2) { i -> (amp * sin(2 * PI * 1000.0 * (i / 2) / rate)).toFloat() }
        DspProcessor(rate, 2) { config to 0L }.process(buf, frames)
        var s = 0.0
        for (f in frames / 2 until frames) s += buf[f * 2].toDouble() * buf[f * 2]
        return 20 * log10(sqrt(s / (frames / 2)))
    }

    @Test
    fun loudAndQuietComeCloser() {
        val off = DspConfig(enabled = true, limiter = false, preampDb = -0.01)
        val inputGap = levelDb(0.5, off) - levelDb(0.5 / 31.6, off) // 30 dB
        assertEquals(30.0, inputGap, 0.1)
        for (strength in 1..3) {
            val c = off.copy(compressor = strength)
            val gap = levelDb(0.5, c) - levelDb(0.5 / 31.6, c)
            assertTrue("strength $strength: $gap dB", gap < 30.0 - 5 * strength)
        }
    }

    @Test
    fun softKneeCurve() {
        val c = Compressor(rate, 3) // −30 dB, 4:1, 6 dB knee
        assertEquals(0.0, c.reductionDb(-40.0), 1e-9)
        assertEquals(0.0, c.reductionDb(-33.0), 1e-9)
        assertTrue(c.reductionDb(-30.0) in 0.1..1.0)
        assertEquals(15.0 * 0.75, c.reductionDb(-15.0), 1e-9)
    }
}
