package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

class LinearPhaseEqTest {
    private val rate = 48_000
    private val bands = listOf(
        Band(FilterType.LOW_SHELF, 100.0, 6.0, 0.7),
        Band(FilterType.PEAKING, 1000.0, -4.0, 1.4),
        Band(FilterType.HIGH_SHELF, 9000.0, 3.0, 0.7),
    )

    @Test
    fun firMatchesTheBiquadsMagnitudeAndIsSymmetric() {
        val fir = LinearPhaseEq.fir(bands, rate)
        val n = fir.size
        for (k in 1 until n / 2) assertEquals(fir[n / 2 + k], fir[n / 2 - k], 1e-6f)
        val coefficients = bands.map { Coefficients.of(it, rate) }
        for (f in listOf(40.0, 100.0, 300.0, 1000.0, 3000.0, 9000.0, 18000.0)) {
            val w = 2 * PI * f / rate
            var re = 0.0
            var im = 0.0
            for (t in fir.indices) {
                re += fir[t] * cos(w * t)
                im -= fir[t] * sin(w * t)
            }
            val firDb = 20 * log10(sqrt(re * re + im * im))
            var biquad = 1.0
            for (c in coefficients) biquad *= LinearPhaseEq.magnitude(c, w)
            assertEquals("$f Hz", 20 * log10(biquad), firDb, 0.1)
        }
    }

    private fun rmsDb(config: DspConfig, freq: Double): Double {
        val frames = rate
        val buf = FloatArray(frames * 2) { i -> (0.25 * sin(2 * PI * freq * (i / 2) / rate)).toFloat() }
        val p = DspProcessor(rate, 2) { config to 0L }
        p.process(buf, frames)
        var s = 0.0
        for (f in frames / 2 until frames) s += buf[f * 2].toDouble() * buf[f * 2]
        return 20 * log10(sqrt(s / (frames / 2)) / (0.25 / sqrt(2.0)))
    }

    @Test
    fun linearPhaseSoundsLikeTheBiquadsInLevel() {
        val peak = DspConfig(enabled = true, limiter = false, bands = listOf(Band(FilterType.PEAKING, 1000.0, 6.0, 1.0)))
        for (f in listOf(200.0, 1000.0, 5000.0)) {
            assertEquals("$f Hz", rmsDb(peak, f), rmsDb(peak.copy(linearPhase = true), f), 0.1)
        }
    }

    @Test
    fun updatingTheResponseFadesWithoutAGap() {
        val one = FloatArray(1).also { it[0] = 1f }
        val c = Convolver(ImpulseResponse("x", rate, listOf(one)), rate, 2, native = false, normalise = false)
        val input = FloatArray(8192 * 2) { 0.5f }
        c.process(input, 4096)
        c.update(listOf(FloatArray(1).also { it[0] = 0.5f }))
        c.process(input, 8192 - 4096, 4096 * 2)
        // After the first block's latency: never silent, ends at half level, no jumps.
        for (f in c.block until 8192 - 1) {
            assertTrue("gap at $f", input[f * 2] > 0.2f)
            assertTrue("jump at $f", abs(input[(f + 1) * 2] - input[f * 2]) < 0.01f)
        }
        assertEquals(0.25f, input[8191 * 2], 1e-4f)
    }
}
