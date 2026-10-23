package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class DitherTest {
    private val lsb = 1f / 32767f

    @Test
    fun detailBelowOneLsbSurvivesOnAverage() {
        // 0.3 LSB: plain rounding gives 0 every time; dither keeps it on average.
        val d = Dither()
        val n = 200_000
        var sum = 0.0
        repeat(n) { sum += d.toPcm16(0.3f * lsb) }
        assertEquals(0.3, sum / n, 0.01)
    }

    @Test
    fun errorStaysWithinTriangularRange() {
        val d = Dither()
        var x = -0.9f
        while (x < 0.9f) {
            val err = d.toPcm16(x) - x * 32767f
            assertTrue("error $err at $x", abs(err) <= 1.5f)
            x += 0.000731f
        }
    }

    @Test
    fun fullScaleClampsWithoutWrapping() {
        val d = Dither()
        repeat(1000) {
            assertTrue(d.toPcm16(1f) >= 32766)
            assertTrue(d.toPcm16(-1f) <= -32766)
            assertEquals(32767.toShort(), d.toPcm16(2f).let { if (it < 32766) 0 else 32767 }.toShort())
        }
    }
}
