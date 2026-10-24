package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownmixTest {
    @Test
    fun fivePointOneFoldsWithItuCoefficients() {
        val (l, r) = Downmix.matrix(6).let { it[0] to it[1] }
        // FL 1, FC −3 dB, BL −3 dB, power-normalised by √2.
        assertEquals(0.7071, l[0], 1e-4)
        assertEquals(0.0, l[1], 0.0)
        assertEquals(0.5, l[2], 1e-4)
        assertEquals(0.0, l[3], 0.0) // LFE left out
        assertEquals(0.5, l[4], 1e-4)
        assertEquals(0.0, l[5], 0.0)
        assertEquals(0.7071, r[1], 1e-4)
        assertEquals(0.5, r[5], 1e-4)
    }

    @Test
    fun centreLandsEquallyInBothSides() {
        val frames = 4
        val src = FloatArray(frames * 6) { i -> if (i % 6 == 2) 0.8f else 0f } // centre only
        val dst = FloatArray(frames * 2)
        Downmix.mix(src, 6, dst, 0, frames)
        for (f in 0 until frames) {
            assertEquals(0.4f, dst[f * 2], 1e-5f)
            assertEquals(0.4f, dst[f * 2 + 1], 1e-5f)
        }
    }

    @Test
    fun onlySurroundIsFoldedAndTheSettingCounts() {
        assertFalse(Downmix.applies(2))
        assertTrue(Downmix.applies(6))
        Downmix.enabled = false
        try {
            assertFalse(Downmix.applies(6))
        } finally {
            Downmix.enabled = true
        }
    }
}
