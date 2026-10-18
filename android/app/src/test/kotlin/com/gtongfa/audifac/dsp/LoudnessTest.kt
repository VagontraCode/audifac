package com.gtongfa.audifac.dsp

import androidx.media3.common.Metadata
import androidx.media3.extractor.metadata.id3.InternalFrame
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import com.google.common.collect.ImmutableList
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin

/** EBU Tech 3341 reference signals: the meter must read within ±0.1 LU. */
class LoudnessMeterTest {
    private fun stereoSine(meter: LoudnessMeter, rate: Int, dbfs: Double, seconds: Double, freq: Double = 1000.0) {
        val amp = 10.0.pow(dbfs / 20)
        val frames = (rate * seconds).toInt()
        val chunk = FloatArray(4096 * 2)
        var n = 0
        while (n < frames) {
            val count = minOf(4096, frames - n)
            for (i in 0 until count) {
                val s = (amp * sin(2 * PI * freq * (n + i) / rate)).toFloat()
                chunk[2 * i] = s
                chunk[2 * i + 1] = s
            }
            meter.add(chunk, count)
            n += count
        }
    }

    @Test
    fun case1_sineAtMinus23() {
        val m = LoudnessMeter(48000, 2)
        stereoSine(m, 48000, -23.0, 20.0)
        assertEquals(-23.0, m.integratedLufs()!!, 0.1)
    }

    @Test
    fun case2_sineAtMinus33() {
        val m = LoudnessMeter(48000, 2)
        stereoSine(m, 48000, -33.0, 20.0)
        assertEquals(-33.0, m.integratedLufs()!!, 0.1)
    }

    @Test
    fun case3_relativeGateIgnoresQuietParts() {
        // −36 / −23 / −36 dBFS, 10 s / 60 s / 10 s → −23 LUFS.
        val m = LoudnessMeter(48000, 2)
        stereoSine(m, 48000, -36.0, 10.0)
        stereoSine(m, 48000, -23.0, 60.0)
        stereoSine(m, 48000, -36.0, 10.0)
        assertEquals(-23.0, m.integratedLufs()!!, 0.1)
    }

    @Test
    fun case5_absoluteGateIgnoresNearSilence() {
        // −26 / −20 / −26 dBFS with −72 dBFS gaps (below the absolute gate) between.
        val m = LoudnessMeter(48000, 2)
        stereoSine(m, 48000, -26.0, 20.0)
        stereoSine(m, 48000, -20.0, 20.1)
        stereoSine(m, 48000, -26.0, 20.0)
        assertEquals(-23.0, m.integratedLufs()!!, 0.2)
    }

    @Test
    fun otherSampleRatesMatch() {
        for (rate in listOf(44100, 96000, 176400)) {
            val m = LoudnessMeter(rate, 2)
            stereoSine(m, rate, -23.0, 5.0)
            assertEquals("$rate Hz", -23.0, m.integratedLufs()!!, 0.1)
        }
    }

    @Test
    fun peakAndSilence() {
        val m = LoudnessMeter(48000, 2)
        stereoSine(m, 48000, -6.0, 1.0)
        assertEquals(10.0.pow(-6.0 / 20), m.peak, 1e-3)
        val silent = LoudnessMeter(48000, 2)
        silent.add(FloatArray(48000 * 2), 48000)
        assertNull(silent.integratedLufs())
    }
}

class ReplayGainTest {
    private fun txxx(key: String, value: String) = TextInformationFrame("TXXX", key, ImmutableList.of(value))

    @Test
    fun id3Txxx() {
        val g = ReplayGain.fromMetadata(
            Metadata(
                txxx("REPLAYGAIN_TRACK_GAIN", "-6.20 dB"),
                txxx("replaygain_track_peak", "0.988"),
                txxx("REPLAYGAIN_ALBUM_GAIN", "+1,50 dB"),
            ),
        )!!
        assertEquals(-6.2, g.trackGainDb!!, 1e-9)
        assertEquals(0.988, g.trackPeak!!, 1e-9)
        assertEquals(1.5, g.albumGainDb!!, 1e-9)
        assertNull(g.albumPeak)
    }

    @Test
    fun vorbisCommentsAndOpusR128() {
        val flac = ReplayGain.fromMetadata(Metadata(VorbisComment("REPLAYGAIN_TRACK_GAIN", "-3.1 dB")))!!
        assertEquals(-3.1, flac.trackGainDb!!, 1e-9)
        // Opus: −2560 / 256 = −10 dB vs −23 LUFS → −5 dB vs −18 LUFS.
        val opus = ReplayGain.fromMetadata(Metadata(VorbisComment("R128_TRACK_GAIN", "-2560")))!!
        assertEquals(-5.0, opus.trackGainDb!!, 1e-9)
    }

    @Test
    fun itunesFreeform() {
        val g = ReplayGain.fromMetadata(Metadata(InternalFrame("com.apple.iTunes", "replaygain_track_gain", "-7.5 dB")))!!
        assertEquals(-7.5, g.trackGainDb!!, 1e-9)
    }

    @Test
    fun nothingUseful() {
        assertNull(ReplayGain.fromMetadata(null))
        assertNull(ReplayGain.fromMetadata(Metadata(txxx("COMMENT", "hi"), txxx("REPLAYGAIN_TRACK_GAIN", "loud"))))
    }
}

class VolumeMatchingTest {
    private fun db(linear: Double) = 20 * log10(linear)

    @Test
    fun modes() {
        val gains = Gains(trackGainDb = -6.0, trackPeak = 0.5, albumGainDb = -4.0, albumPeak = 0.6)
        assertEquals(0.0, db(VolumeMatching(VolumeMatching.Mode.OFF).linearGain(gains)), 1e-9)
        assertEquals(-6.0, db(VolumeMatching(VolumeMatching.Mode.TRACK).linearGain(gains)), 1e-9)
        assertEquals(-4.0, db(VolumeMatching(VolumeMatching.Mode.ALBUM).linearGain(gains)), 1e-9)
        // Album falls back to track, preamp adds.
        assertEquals(-3.0, db(VolumeMatching(VolumeMatching.Mode.ALBUM, preampDb = 3.0).linearGain(Gains(trackGainDb = -6.0))), 1e-9)
        // Nothing known: the untagged gain.
        assertEquals(-2.0, db(VolumeMatching(VolumeMatching.Mode.TRACK, untaggedGainDb = -2.0).linearGain(null)), 1e-9)
    }

    @Test
    fun preventClippingCapsBoostAtThePeak() {
        val quietTrack = Gains(trackGainDb = 8.0, trackPeak = 0.5) // peak −6 dBFS
        assertEquals(6.0206, db(VolumeMatching(VolumeMatching.Mode.TRACK).linearGain(quietTrack)), 1e-3)
        assertEquals(8.0, db(VolumeMatching(VolumeMatching.Mode.TRACK, preventClipping = false).linearGain(quietTrack)), 1e-9)
    }
}

class DspGainTest {
    @Test
    fun gainAppliesWithEqOffAndLimiterCatchesBoost() {
        val p = DspProcessor(48000, 2) { DspConfig.OFF to 0L }
        assertTrue(p.isPassThrough())
        p.setGain(0.5, immediate = true)
        val buf = FloatArray(2000) { 0.4f }
        assertTrue(!p.isPassThrough())
        p.process(buf, 1000)
        assertEquals(0.2f, buf[1999], 1e-6f)

        // +12 dB on a 0.4 signal would reach 1.6: the limiter holds −0.1 dBFS.
        p.setGain(4.0, immediate = true)
        val loud = FloatArray(20000) { 0.4f }
        p.process(loud, 10000)
        assertTrue(loud.all { abs(it) <= 0.9891f })
    }

    @Test
    fun glidesBetweenTracks() {
        val p = DspProcessor(48000, 1) { DspConfig.OFF to 0L }
        p.setGain(1.0, immediate = true)
        p.setGain(0.5, immediate = false)
        val buf = FloatArray(4800) { 1f }
        p.process(buf, 4800)
        assertTrue("no jump", buf[0] > 0.95f)
        assertEquals(0.5f, buf[4799], 1e-3f) // settled within 100 ms
    }
}

class LoudnessMeterBenchmark {
    @Test
    fun throughput() {
        val rate = 44100
        val seconds = 180
        val chunk = FloatArray(4096 * 2) { (sin(it * 0.01) * 0.3).toFloat() }
        repeat(2) {
            val m = LoudnessMeter(rate, 2)
            val t = System.nanoTime()
            var frames = 0
            while (frames < rate * seconds) {
                m.add(chunk, 4096)
                frames += 4096
            }
            val ms = (System.nanoTime() - t) / 1e6
            println("R128 meter: 3 min stereo 44.1 kHz in ${"%.0f".format(ms)} ms → ${"%.0f".format(seconds * 1000 / ms)}× real time")
        }
    }
}
