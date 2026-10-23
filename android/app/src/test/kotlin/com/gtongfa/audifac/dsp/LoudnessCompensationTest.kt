package com.gtongfa.audifac.dsp

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Test

class LoudnessCompensationTest {
    private val on = DspConfig(enabled = true, loudness = true)

    @After
    fun tearDown() {
        DspEngine.update(DspConfig.OFF)
        DspEngine.setAttenuation(0.0)
    }

    @Test
    fun nothingNearFullVolume() {
        assertSame(on, LoudnessCompensation.apply(on, 0.0))
        assertSame(on, LoudnessCompensation.apply(on, LoudnessCompensation.REFERENCE_DB))
    }

    @Test
    fun quietListeningGetsBassAndTrebleWithoutClipping() {
        val c = LoudnessCompensation.apply(on, 40.0)
        val bass = c.bands.single { it.type == FilterType.LOW_SHELF }
        val treble = c.bands.single { it.type == FilterType.HIGH_SHELF }
        assertEquals(10.5, bass.gainDb, 1e-9)
        assertEquals(3.6, treble.gainDb, 1e-9)
        assertEquals(-10.5, c.preampDb, 1e-9) // headroom for the boost
        // Very quiet: capped.
        assertEquals(12.0, LoudnessCompensation.apply(on, 90.0).bands.first().gainDb, 1e-9)
    }

    @Test
    fun offOrEqDisabledChangesNothing() {
        val off = on.copy(loudness = false)
        assertSame(off, LoudnessCompensation.apply(off, 40.0))
        val disabled = DspConfig(enabled = false, loudness = true)
        assertSame(disabled, LoudnessCompensation.apply(disabled, 40.0))
    }

    @Test
    fun volumeChangesRebuildOnlyWhenLoudnessIsOn() {
        DspEngine.update(DspConfig(enabled = true))
        val v = DspEngine.version
        DspEngine.setAttenuation(30.0)
        assertEquals(v, DspEngine.version)
        DspEngine.update(on)
        val v2 = DspEngine.version
        DspEngine.setAttenuation(40.0)
        assertNotEquals(v2, DspEngine.version)
        assertEquals(2, DspEngine.config.bands.size)
    }
}
