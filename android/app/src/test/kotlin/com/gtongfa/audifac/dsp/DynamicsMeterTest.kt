package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random
import kotlin.math.PI
import kotlin.math.sin

class DynamicsMeterTest {
    private val rate = 44_100

    private fun feed(m: DynamicsMeter, seconds: Int, sample: (Int) -> Float) {
        val chunk = 4410
        val buf = FloatArray(chunk * 2)
        var t = 0
        while (t < seconds * rate) {
            for (f in 0 until chunk) {
                val x = sample(t + f)
                buf[f * 2] = x
                buf[f * 2 + 1] = x
            }
            m.add(buf, chunk)
            t += chunk
        }
    }

    @Test
    fun steadyToneHasNoDynamicRange() {
        val m = DynamicsMeter(rate, 2)
        feed(m, 12) { t -> (0.5 * sin(2 * PI * 1000 * t / rate)).toFloat() }
        assertEquals(0, m.dr())
    }

    @Test
    fun quietMusicWithPeaksHasHighDr() {
        // A 0.1 tone with one full-scale click per 3 s block: 20 dB.
        val m = DynamicsMeter(rate, 2)
        feed(m, 15) { t -> if (t % (rate * 3) == rate) 1f else (0.1 * sin(2 * PI * 440 * t / rate)).toFloat() }
        assertEquals(20, m.dr())
    }

    @Test
    fun tooShortForDr() {
        val m = DynamicsMeter(rate, 2)
        feed(m, 4) { 0.3f }
        assertNull(m.dr())
    }

    /** Random-phase tones every 50 Hz from 100 Hz up to [topHz]. */
    private fun band(topHz: Int): (Int) -> Float {
        val r = Random(3)
        val freqs = (100..topHz step 50).toList()
        val phases = freqs.map { r.nextDouble() * 2 * PI }
        return { t -> (freqs.indices.sumOf { i -> sin(2 * PI * freqs[i] * t / rate + phases[i]) } * 0.002).toFloat() }
    }

    @Test
    fun lossyStyleCutoffIsABrickWall() {
        val m = DynamicsMeter(rate, 2)
        feed(m, 4, band(16_000))
        val (hz, wall) = m.cutoff()!!
        assertTrue("cutoff $hz", hz in 15_800..16_400)
        assertTrue(wall)
        assertTrue(hz < DynamicsMeter.SUSPICIOUS_BELOW_HZ)
    }

    @Test
    fun fullBandIsNotSuspicious() {
        val m = DynamicsMeter(rate, 2)
        feed(m, 4, band(21_500))
        val (hz, _) = m.cutoff()!!
        assertTrue("cutoff $hz", hz >= 21_000)
        assertFalse(hz < DynamicsMeter.SUSPICIOUS_BELOW_HZ)
    }

    @Test
    fun quietLossyMusicOverNoiseStillShowsItsWall() {
        // A quiet song (−40 dB) cut at 19.5 kHz, with 16-bit-style noise everywhere.
        val m = DynamicsMeter(rate, 2)
        val music = band(19_500)
        val r = Random(5)
        feed(m, 4) { t -> music(t) * 0.01f + (r.nextFloat() - 0.5f) / 32768f }
        val (hz, wall) = m.cutoff()!!
        assertTrue("cutoff $hz", hz in 19_200..19_800)
        assertTrue(wall)
    }
}
