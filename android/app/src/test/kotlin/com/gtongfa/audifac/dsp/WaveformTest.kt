package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class WaveformTest {
    /** [seconds] of a stereo sine at [amplitude], 1 kHz rate. */
    private fun tone(w: Waveform, seconds: Int, amplitude: Double) {
        val frames = seconds * 1000
        val buf = FloatArray(frames * 2) { (amplitude * sin(2 * PI * 50 * (it / 2) / 1000.0)).toFloat() }
        w.add(buf, frames)
    }

    @Test
    fun loudAndQuietSlicesOn20DbScale() {
        val w = Waveform(durationUs = 4_000_000, points = 4)
        w.format(1000, 2)
        tone(w, 1, 1.0)
        tone(w, 1, 0.5) // −6 dB
        tone(w, 1, 0.0) // silence
        tone(w, 1, 0.1) // −20 dB
        val l = w.levels().map { it.toInt() and 0xFF }
        assertEquals(255, l[0])
        assertEquals(255.0 * 14 / 20, l[1].toDouble(), 2.0)
        assertEquals(0, l[2])
        assertTrue(l[3] <= 1)
    }

    @Test
    fun aRangeStartsAtItsOwnBeginning() {
        // A 2 s slice (a CUE track): its own first second lands in the first half.
        val w = Waveform(durationUs = 2_000_000, points = 2)
        w.format(1000, 2)
        tone(w, 1, 1.0)
        tone(w, 1, 0.1)
        val l = w.levels().map { it.toInt() and 0xFF }
        assertEquals(255, l[0])
        assertTrue(l[1] in 0..2) // −20 dB: the bottom
    }

    @Test
    fun framesPastTheDurationGoToTheLastSlice() {
        val w = Waveform(durationUs = 1_000_000, points = 2)
        w.format(1000, 2)
        tone(w, 2, 1.0)
        assertEquals(2, w.levels().size)
    }
}
