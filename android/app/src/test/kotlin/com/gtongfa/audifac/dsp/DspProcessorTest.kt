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

class DspProcessorTest {
    private val rate = 48000

    private fun sine(freq: Double, frames: Int, amp: Double = 0.25, channels: Int = 2) =
        FloatArray(frames * channels) { i -> (amp * sin(2 * PI * freq * (i / channels) / rate)).toFloat() }

    private fun processor(config: DspConfig, channels: Int = 2): Pair<DspProcessor, (DspConfig) -> Unit> {
        var cfg = config
        var version = 0L
        val p = DspProcessor(rate, channels) { cfg to version }
        return p to { c: DspConfig -> cfg = c; version++ }
    }

    /** RMS of channel 0 over the second half (filters settled). */
    private fun rms(samples: FloatArray, channels: Int = 2): Double {
        val frames = samples.size / channels
        var sum = 0.0
        var n = 0
        for (f in frames / 2 until frames) {
            val s = samples[f * channels].toDouble()
            sum += s * s
            n++
        }
        return sqrt(sum / n)
    }

    private fun gainDb(freq: Double, config: DspConfig): Double {
        val input = sine(freq, rate)
        val output = input.copyOf()
        processor(config).first.process(output, rate)
        return 20 * log10(rms(output) / rms(input))
    }

    @Test
    fun offIsBitExact() {
        val input = sine(1000.0, 4800)
        val output = input.copyOf()
        processor(DspConfig.OFF).first.process(output, 4800)
        assertArrayEquals(input, output, 0f)
    }

    @Test
    fun flatEnabledConfigIsBitExact() {
        val flat = DspConfig(enabled = true, bands = listOf(Band(FilterType.PEAKING, 1000.0, 0.0, 1.0)))
        val input = sine(1000.0, 4800, amp = 0.999)
        val output = input.copyOf()
        processor(flat).first.process(output, 4800)
        assertArrayEquals(input, output, 0f)
    }

    @Test
    fun peakingBoostsItsCentreFrequency() {
        val boost = DspConfig(enabled = true, limiter = false, bands = listOf(Band(FilterType.PEAKING, 1000.0, 6.0, 1.0)))
        assertEquals(6.0, gainDb(1000.0, boost), 0.1)
        assertEquals(0.0, gainDb(60.0, boost), 0.3)
        assertEquals(0.0, gainDb(16000.0, boost), 0.3)
    }

    @Test
    fun cutsAndShelves() {
        val cut = DspConfig(enabled = true, bands = listOf(Band(FilterType.PEAKING, 3000.0, -9.0, 2.0)))
        assertEquals(-9.0, gainDb(3000.0, cut), 0.15)

        val lowShelf = DspConfig(enabled = true, limiter = false, bands = listOf(Band(FilterType.LOW_SHELF, 200.0, 6.0, 0.707)))
        assertEquals(6.0, gainDb(30.0, lowShelf), 0.3)
        assertEquals(0.0, gainDb(8000.0, lowShelf), 0.2)

        val highShelf = DspConfig(enabled = true, limiter = false, bands = listOf(Band(FilterType.HIGH_SHELF, 4000.0, -6.0, 0.707)))
        assertEquals(-6.0, gainDb(16000.0, highShelf), 0.4)
        assertEquals(0.0, gainDb(100.0, highShelf), 0.2)
    }

    @Test
    fun lowPassAndHighPassAttenuate() {
        val lp = DspConfig(enabled = true, bands = listOf(Band(FilterType.LOW_PASS, 1000.0, 0.0, 0.707)))
        assertTrue(gainDb(8000.0, lp) < -30)
        assertEquals(0.0, gainDb(100.0, lp), 0.2)

        val hp = DspConfig(enabled = true, bands = listOf(Band(FilterType.HIGH_PASS, 100.0, 0.0, 0.707)))
        assertTrue(gainDb(20.0, hp) < -20)
    }

    @Test
    fun preampAppliesGain() {
        val preamp = DspConfig(enabled = true, preampDb = -6.0)
        assertEquals(-6.0, gainDb(1000.0, preamp), 0.05)
    }

    @Test
    fun limiterKeepsPeaksBelowCeiling() {
        val loud = DspConfig(enabled = true, preampDb = 12.0, limiter = true)
        val output = sine(1000.0, rate, amp = 0.8)
        processor(loud).first.process(output, rate)
        val peak = output.maxOf { abs(it) }
        assertTrue("peak $peak", peak <= 0.99f)
        assertTrue("limiter should not crush: ${rms(output)}", rms(output) > 0.5)
    }

    @Test
    fun monoAndBalance() {
        val frames = 4800
        val stereo = FloatArray(frames * 2) { i -> if (i % 2 == 0) 0.5f else 0f }
        val mono = stereo.copyOf()
        processor(DspConfig(enabled = true, mono = true, limiter = false)).first.process(mono, frames)
        assertEquals(0.25f, mono[0], 1e-6f)
        assertEquals(0.25f, mono[1], 1e-6f)

        val right = FloatArray(frames * 2) { 0.5f }
        processor(DspConfig(enabled = true, balance = 0.5, limiter = false)).first.process(right, frames)
        assertEquals(0.25f, right[0], 1e-6f) // left attenuated
        assertEquals(0.5f, right[1], 1e-6f)
    }

    @Test
    fun crossfeedLeaksOppositeChannel() {
        val frames = rate
        val leftOnly = FloatArray(frames * 2) { i -> if (i % 2 == 0) (0.5 * sin(2 * PI * 200.0 * (i / 2) / rate)).toFloat() else 0f }
        processor(DspConfig(enabled = true, crossfeed = 1.0, limiter = false)).first.process(leftOnly, frames)
        var rightEnergy = 0.0
        for (f in frames / 2 until frames) rightEnergy += leftOnly[f * 2 + 1].toDouble().let { it * it }
        assertTrue(rightEnergy > 1.0)
    }

    @Test
    fun changingSettingsDoesNotClick() {
        val (p, set) = processor(DspConfig(enabled = true, limiter = false))
        val frames = 4800
        val first = sine(440.0, frames)
        p.process(first, frames)
        set(DspConfig(enabled = true, limiter = false, bands = listOf(Band(FilterType.PEAKING, 440.0, 12.0, 1.0))))
        val second = FloatArray(frames * 2) { i -> (0.25 * sin(2 * PI * 440.0 * (frames + i / 2) / rate)).toFloat() }
        p.process(second, frames)
        // Largest sample-to-sample step across the change stays close to the
        // sine's own maximum slope (amp * 2π f / rate, ×4 for the +12 dB boost).
        val maxSlope = 0.25 * 2 * PI * 440 / rate * 4 * 1.2
        var worst = abs(second[0] - first[(frames - 1) * 2]).toDouble()
        for (f in 1 until frames) worst = maxOf(worst, abs(second[f * 2] - second[(f - 1) * 2]).toDouble())
        assertTrue("step $worst > $maxSlope", worst <= maxSlope)
    }

    @Test
    fun bypassFadesToDry() {
        val boosted = DspConfig(enabled = true, preampDb = -12.0)
        var bypass = false
        var version = 0L
        val p = DspProcessor(rate, 2) { (if (bypass) DspConfig.OFF else boosted) to version * 2 + (if (bypass) 1 else 0) }
        val a = sine(1000.0, rate)
        p.process(a, rate)
        bypass = true
        val input = sine(1000.0, rate)
        val b = input.copyOf()
        p.process(b, rate)
        assertEquals(rms(input), rms(b), 1e-4) // after the fade, untouched
    }

    @Test
    fun levelStatsCountLimitingAndClipping() {
        val boost = DspConfig(enabled = true, preampDb = 12.0)
        val loud = sine(1000.0, rate, amp = 0.5)
        val (limited, _) = processor(boost)
        limited.process(loud.copyOf(), rate)
        val s = limited.takeStats()
        assertTrue("peak ${s.peak}", s.peak > 1.9) // +12 dB on 0.5 before the limiter
        assertTrue("limited ${s.limited}", s.limited > rate / 2)
        assertEquals(0L, s.clipped)
        assertEquals(rate.toLong(), s.frames)
        // Taken: starts over.
        assertEquals(0L, limited.takeStats().frames)

        val (unlimited, _) = processor(boost.copy(limiter = false))
        unlimited.process(loud.copyOf(), rate)
        assertTrue(unlimited.takeStats().clipped > rate / 2)

        val (quiet, _) = processor(DspConfig(enabled = true, preampDb = -6.0))
        quiet.process(sine(1000.0, rate, amp = 0.5), rate)
        val q = quiet.takeStats()
        assertEquals(0L, q.limited)
        assertEquals(0L, q.clipped)
    }

    /** One stereo frame (l, r) through [config], after the filters settle on DC. */
    private fun stereo(config: DspConfig, l: Float, r: Float): Pair<Float, Float> {
        val frames = 100
        val buf = FloatArray(frames * 2) { if (it % 2 == 0) l else r }
        processor(config).first.process(buf, frames)
        return buf[(frames - 1) * 2] to buf[(frames - 1) * 2 + 1]
    }

    @Test
    fun widthPolarityAndDelay() {
        val on = DspConfig(enabled = true, limiter = false)
        // Width 0: mono; 2: side doubled (L 0.5 / R 0.1 → mid 0.3, side 0.2 → 0.4).
        val (ml, mr) = stereo(on.copy(width = 0.0), 0.5f, 0.1f)
        assertEquals(0.3f, ml, 1e-6f)
        assertEquals(0.3f, mr, 1e-6f)
        val (wl, wr) = stereo(on.copy(width = 2.0), 0.5f, 0.1f)
        assertEquals(0.7f, wl, 1e-6f)
        assertEquals(-0.1f, wr, 1e-6f)
        // Polarity.
        val (il, ir) = stereo(on.copy(invertLeft = true), 0.5f, 0.1f)
        assertEquals(-0.5f, il, 1e-6f)
        assertEquals(0.1f, ir, 1e-6f)
        // 1 ms on the right at 48 kHz: an impulse comes out 48 frames later.
        val impulse = FloatArray(200 * 2).also { it[0] = 1f; it[1] = 1f }
        processor(on.copy(delayMs = 1.0)).first.process(impulse, 200)
        assertEquals(1f, impulse[0], 0f)
        assertEquals(0f, impulse[1], 0f)
        assertEquals(1f, impulse[48 * 2 + 1], 0f)
        // Neutral settings stay bit-exact pass-through.
        assertTrue(DspConfig(enabled = true, width = 1.0).isTransparent)
        assertTrue(!DspConfig(enabled = true, delayMs = 0.5).isTransparent)
    }
}
