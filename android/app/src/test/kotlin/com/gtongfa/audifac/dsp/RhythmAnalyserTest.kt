package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

class RhythmAnalyserTest {
    private val rate = 22_050

    /** A stereo excerpt of [seconds] with hits from [hits] (time in s → mono sample). */
    private fun render(seconds: Int, voice: (Double) -> Double): FloatArray {
        val n = seconds * rate
        val out = FloatArray(n * 2)
        for (i in 0 until n) {
            val v = voice(i.toDouble() / rate).toFloat().coerceIn(-1f, 1f)
            out[2 * i] = v
            out[2 * i + 1] = v
        }
        return out
    }

    private val noise = Random(1)
    private val noiseTable = DoubleArray(1 shl 16) { noise.nextDouble() * 2 - 1 }
    private fun noiseAt(t: Double) = noiseTable[((t * rate).toInt()) and 0xFFFF]

    private fun kick(dt: Double) = if (dt < 0) 0.0 else 0.9 * sin(2 * PI * 55 * dt) * exp(-dt * 18) + 0.3 * noiseAt(dt) * exp(-dt * 400)
    private fun snare(dt: Double) = if (dt < 0) 0.0 else 0.45 * noiseAt(dt + 3) * exp(-dt * 25)
    private fun hat(dt: Double) = if (dt < 0) 0.0 else 0.15 * noiseAt(dt + 7) * exp(-dt * 90)
    private fun pluck(dt: Double) = if (dt < 0) 0.0 else 0.25 * sin(2 * PI * 880 * dt) * exp(-dt * 30)

    /** Time since the last event of a grid of [period] s, offset [phase] s. */
    private fun since(t: Double, period: Double, phase: Double = 0.0): Double {
        val x = t - phase
        if (x < 0) return -1.0
        return x % period
    }

    private fun analyse(excerpts: Int = 3, voice: (Double) -> Double): RhythmAnalyser.Result? {
        val a = RhythmAnalyser()
        repeat(excerpts) {
            a.startExcerpt()
            a.format(rate, 2)
            val pcm = render(20, voice)
            a.add(pcm, pcm.size / 2)
        }
        return a.result().also { r -> println("rhythm: bpm=${r?.bpm} conf=${r?.confidence} groove=${r?.groove} bass=${r?.bassPunch} energy=${r?.energy} dance=${r?.danceability}") }
    }

    @Test
    fun fourOnTheFloorAt128() {
        val beat = 60.0 / 128
        val r = analyse { t -> kick(since(t, beat)) + hat(since(t, beat, beat / 2)) }!!
        assertEquals(128.0, r.bpm, 1.5)
        assertTrue("groove ${r.groove}", r.groove > 60)
        assertTrue("danceability ${r.danceability}", r.danceability > 60)
    }

    @Test
    fun kicksAndEighthHatsAt105StayAt105() {
        val beat = 60.0 / 105
        val r = analyse { t -> kick(since(t, beat)) + hat(since(t, beat / 2)) + snare(since(t, beat * 2, beat)) }!!
        assertEquals(105.0, r.bpm, 1.5)
    }

    @Test
    fun fastGuitarSixteenthsAt135AreNotDoubleTime() {
        // Ndombolo-like: a busy sebene over a kick on every beat.
        val beat = 60.0 / 135
        val r = analyse { t -> kick(since(t, beat)) + pluck(since(t, beat / 4)) + snare(since(t, beat * 2, beat)) }!!
        assertEquals(135.0, r.bpm, 2.0)
    }

    @Test
    fun halfTimeKicksStillReadAsTheDanceTempo() {
        // Kick on 1 and 3, snare on 2 and 4, at 110: the pulse a dancer feels is 110.
        val beat = 60.0 / 110
        val r = analyse { t -> kick(since(t, beat * 2)) + snare(since(t, beat * 2, beat)) + hat(since(t, beat / 2)) }!!
        assertEquals(110.0, r.bpm, 1.5)
    }

    @Test
    fun noiseHasNoGroove() {
        val r = analyse { t -> 0.3 * noiseAt(t * 1.37 + 11) }!!
        assertTrue("groove ${r.groove}", r.groove < 35)
        assertTrue("danceability ${r.danceability}", r.danceability < 55)
    }

    @Test
    fun silenceGivesNothing() {
        assertNull(analyse { 0.0 })
    }

    @Test
    fun tempoPriorsAndExcerpts() {
        assertEquals(1.0, RhythmAnalyser.prior(110.0), 0.0)
        assertTrue(RhythmAnalyser.prior(220.0) < 0.25 && RhythmAnalyser.prior(65.0) < 0.3)
        assertEquals(1.0, RhythmAnalyser.danceTempoFit(105.0), 0.0)
        assertEquals(1.0, RhythmAnalyser.danceTempoFit(132.0), 0.0)
        assertTrue(RhythmAnalyser.danceTempoFit(70.0) < 0.1)
        val x = RhythmAnalyser.excerpts(240_000)
        assertEquals(listOf(45_000L to 75_000L, 105_000L to 135_000L, 165_000L to 195_000L), x)
        assertEquals(listOf(0L to 50_000L), RhythmAnalyser.excerpts(50_000))
    }
}
