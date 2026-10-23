package com.gtongfa.audifac.dsp

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Metadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.audio.AudioSink
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.pow

/** Gapless trimming and crossfade, with a fake delegate recording what it's given. */
class DspAudioSinkTest {
    private val rate = 44_100

    /** What reached the "AudioTrack": samples (left channel) and each buffer's timestamp. */
    private class Recorder {
        val left = ArrayList<Float>()
        val pts = ArrayList<Pair<Int, Long>>() // (sample index where the buffer starts, pts)
        var acceptLimit = Int.MAX_VALUE // buffers accepted before refusing (backpressure test)
        val encodings = ArrayList<Int>() // each configure's PCM encoding
        val rates = ArrayList<Int>() // each configure's sample rate
        var positionUs = 0L // playback position the "AudioTrack" reports

        /** Frames the "AudioTrack" buffers; when full it refuses, and a little time passes (decoding outruns playback). */
        var capacity = Int.MAX_VALUE
        var played = 0

        val sink: AudioSink = Proxy.newProxyInstance(AudioSink::class.java.classLoader, arrayOf(AudioSink::class.java)) { _, m, args ->
            when (m.name) {
                "configure" -> {
                    encodings += (args[0] as Format).pcmEncoding
                    rates += (args[0] as Format).sampleRate
                    null
                }
                "handleBuffer" -> {
                    if (acceptLimit-- <= 0) return@newProxyInstance false
                    if (left.size - played >= capacity) {
                        played += maxOf(1, capacity / 8)
                        return@newProxyInstance false
                    }
                    val b = (args[0] as ByteBuffer).order(ByteOrder.nativeOrder())
                    pts += left.size to (args[1] as Long)
                    if (encodings.lastOrNull() == C.ENCODING_PCM_16BIT) {
                        val s = b.asShortBuffer()
                        while (s.hasRemaining()) {
                            left += s.get() / 32768f
                            s.get() // right
                        }
                    } else {
                        val f = b.asFloatBuffer()
                        while (f.hasRemaining()) {
                            left += f.get()
                            f.get() // right
                        }
                    }
                    b.position(b.limit())
                    true
                }
                "isEnded" -> true
                "hasPendingData" -> false
                "getFormatSupport" -> AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY
                "supportsFormat" -> true
                "getCurrentPositionUs" -> positionUs
                else -> when (m.returnType) {
                    java.lang.Boolean.TYPE -> false
                    Integer.TYPE -> 0
                    java.lang.Long.TYPE -> 0L
                    java.lang.Float.TYPE -> 0f
                    else -> null
                }
            }
        } as AudioSink
    }

    private fun format(delay: Int = 0, padding: Int = 0, uri: String? = null) = Format.Builder()
        .setSampleMimeType(MimeTypes.AUDIO_RAW)
        .setPcmEncoding(C.ENCODING_PCM_16BIT)
        .setSampleRate(rate)
        .setChannelCount(2)
        .setEncoderDelay(delay)
        .setEncoderPadding(padding)
        .apply { if (uri != null) setMetadata(Metadata(SourceUri(uri))) }
        .build()

    /** Feeds [frames] 16-bit stereo frames, sample value = [value] (or the frame index when null), in chunks. */
    private fun feed(sink: DspAudioSink, frames: Int, startPts: Long, value: Short? = null, chunk: Int = 1000) {
        var done = 0
        while (done < frames) {
            val n = minOf(chunk, frames - done)
            val b = ByteBuffer.allocate(n * 4).order(ByteOrder.LITTLE_ENDIAN)
            repeat(n) { i ->
                val v = value ?: (done + i).toShort()
                b.putShort(v).putShort(v)
            }
            b.flip()
            val pts = startPts + done * 1_000_000L / rate
            while (!sink.handleBuffer(b, pts, 1)) { /* retry, as ExoPlayer does */ }
            done += n
        }
    }

    private val defaultMixerRate = Resampling.mixerRate

    @After
    fun tearDown() {
        Crossfade.seconds = 0.0
        Crossfade.setAlbums(emptyMap())
        DspEngine.update(DspConfig.OFF)
        Resampling.enabled = false
        Resampling.mixerRate = defaultMixerRate
        Loudness.update(VolumeMatching())
        Loudness.putGains(emptyMap(), replace = true)
    }

    @Test
    fun trimsEncoderDelayAndPaddingExactly() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(delay = 100, padding = 50), 0, null)
        feed(sink, 1000, 0, chunk = 300)
        sink.playToEndOfStream()
        assertEquals(850, r.left.size)
        // Frame i carries the value i / 32768: the first kept frame is #100.
        assertEquals(100f / 32768f, r.left.first(), 1e-7f)
        assertEquals(949f / 32768f, r.left.last(), 1e-7f)
        // Timestamps: the first audible frame is presented at 100 frames in.
        assertEquals(100 * 1_000_000L / rate, r.pts.first().second)
    }

    @Test
    fun gaplessBetweenTracksDropsPaddingOnce() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(padding = 30), 0, null)
        feed(sink, 500, 0, value = 1000)
        sink.configure(format(delay = 20), 0, null)
        feed(sink, 500, 500 * 1_000_000L / rate, value = 2000)
        sink.playToEndOfStream()
        // 500 − 30 padding + 500 − 20 delay, with no gap and no repeat.
        assertEquals(950, r.left.size)
        assertEquals(470, r.left.count { abs(it - 1000f / 32768f) < 1e-6 })
    }

    /** Plays out everything, as ExoPlayer does (calls again until done). */
    private fun playToEnd(sink: DspAudioSink) {
        var calls = 0
        do {
            sink.playToEndOfStream()
        } while (!sink.isEnded && ++calls < 10_000)
    }


    @Test
    fun resamplesToTheMixerRate() {
        Resampling.enabled = true
        Resampling.mixerRate = { 48_000 }
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(), 0, null)
        feed(sink, rate, 0, value = 8192) // 1 s of 0.25 at 44.1 kHz
        playToEnd(sink)
        assertEquals(listOf(48_000), r.rates.distinct())
        assertEquals(48_000, r.left.size)
        // Away from the edges (the filter's run-in), the level is exact.
        for (i in 1000 until 47_000) assertEquals(0.25f, r.left[i], 1e-3f)
    }

    @Test
    fun songsOfDifferentRatesJoinWithoutAGap() {
        Resampling.enabled = true
        Resampling.mixerRate = { 48_000 }
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null) // 44.1 kHz → resampled
        feed(sink, rate, 0, value = 8192)
        val b = format(uri = "b").buildUpon().setSampleRate(48_000).build()
        sink.configure(b, 0, null) // 48 kHz: as is
        val bb = ByteBuffer.allocate(48_000 * 4).order(ByteOrder.LITTLE_ENDIAN)
        repeat(48_000) { bb.putShort(16384).putShort(16384) }
        bb.flip()
        while (!sink.handleBuffer(bb, 1_000_000L, 1)) { /* retry */ }
        playToEnd(sink)
        // One output rate throughout (no AudioTrack rebuild), nothing lost.
        assertEquals(listOf(48_000), r.rates.distinct())
        assertEquals(96_000, r.left.size)
        assertEquals(0.25f, r.left[24_000], 1e-3f)
        assertEquals(0.5f, r.left[72_000], 1e-6f)
    }

    @Test
    fun crossfadeMixesTheTailIntoTheNextSong() {
        Crossfade.seconds = 0.1 // up to 4410 frames
        val r = Recorder()
        r.capacity = 2000
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 20_000, 0, value = 16384) // 0.5
        sink.configure(format(uri = "b"), 0, null)
        val bStart = 20_000 * 1_000_000L / rate
        feed(sink, 20_000, bStart, value = 8192) // 0.25
        playToEnd(sink)

        // The reserve is what the AudioTrack hadn't taken yet when B came.
        val fade = 40_000 - r.left.size
        assertTrue("fade of $fade frames", fade in 2000..4410)
        // Before the fade: A alone; after it: B alone.
        assertEquals(0.5f, r.left[20_000 - fade - 1], 1e-6f)
        assertEquals(0.25f, r.left[20_000 - fade + fade + 10], 1e-6f)
        // Halfway: equal-power mix (both at cos 45°).
        val mid = r.left[20_000 - fade + fade / 2]
        assertEquals((0.5 + 0.25) * 0.7071, mid.toDouble(), 0.01)
        // The mixed audio is presented on B's clock (the player moves on to B).
        val mixStart = r.pts.first { it.first >= 20_000 - fade }
        assertEquals(20_000 - fade, mixStart.first)
        assertEquals(bStart, mixStart.second)
    }

    @Test
    fun turningCrossfadeOnMidSongNeverStarvesTheAudioTrack() {
        val r = Recorder()
        r.capacity = rate / 2
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, rate, 0, value = 1000)
        // 12 s of reserve wanted while the AudioTrack plays in real time:
        // holding back would leave it silent until 12 s were decoded.
        Crossfade.seconds = 12.0
        for (chunk in 0 until 20) {
            r.played += rate / 10
            feed(sink, rate / 10, 1_000_000L + chunk * 100_000L, value = 1000)
            assertTrue("chunk $chunk: the AudioTrack ran dry", r.left.size >= r.played)
        }
    }

    @Test
    fun aHeldTailPlaysOutWhenTheNextSongHasAnotherFormat() {
        Crossfade.seconds = 0.1 // up to 4410 frames held at the end of A
        val r = Recorder()
        r.capacity = 2000
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 20_000, 0, value = 16384)
        val mono48k = format(uri = "b").buildUpon().setSampleRate(48_000).setChannelCount(1).build()
        sink.configure(mono48k, 0, null)
        // B's first buffer: A's stereo tail must go out whole, read as stereo.
        val b = ByteBuffer.allocate(1000 * 2).order(ByteOrder.LITTLE_ENDIAN)
        repeat(1000) { b.putShort(8192) }
        b.flip()
        while (!sink.handleBuffer(b, 1_000_000L, 1)) { /* retry, as ExoPlayer does */ }
        assertTrue(r.left.size >= 20_000)
        assertEquals(20_000, r.left.count { abs(it - 0.5f) < 1e-6 })
    }

    @Test
    fun theCrossfadeReservePlaysOutWhileWaitingForTheNextSong() {
        Crossfade.seconds = 1.0
        val r = Recorder()
        r.capacity = rate / 10
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 2 * rate, 0, value = 8192)
        // The song's input has ended; the next one isn't delivered yet. Only
        // the position is polled while the AudioTrack plays what it has.
        repeat(1000) { sink.getCurrentPositionUs(false) }
        assertEquals(2 * rate, r.left.size)
    }

    @Test
    fun eqChangesReachAudioAlreadyHeldForTheCrossfade() {
        Crossfade.seconds = 1.0
        val r = Recorder()
        r.capacity = rate / 10
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 2 * rate, 0, value = 8192) // 0.25; about the last second is held back
        // Turned on after that second was decoded, before it plays.
        DspEngine.update(DspConfig(enabled = true, preampDb = -6.0))
        playToEnd(sink)
        val quieter = 0.25f * 10.0.pow(-6.0 / 20).toFloat()
        assertEquals(quieter, r.left.last(), 2e-3f)
    }

    @Test
    fun noCrossfadeWithinAnAlbum() {
        Crossfade.seconds = 0.1
        Crossfade.setAlbums(mapOf("a" to 7L, "b" to 7L))
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 10_000, 0, value = 16384)
        sink.configure(format(uri = "b"), 0, null)
        feed(sink, 10_000, 10_000 * 1_000_000L / rate, value = 8192)
        sink.playToEndOfStream()
        assertEquals(20_000, r.left.size)
        assertTrue(r.left.all { abs(it - 0.5f) < 1e-6 || abs(it - 0.25f) < 1e-6 })
        assertEquals(10_000, r.left.count { abs(it - 0.5f) < 1e-6 })
    }

    @Test
    fun backpressureLosesNothing() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(), 0, null)
        r.acceptLimit = 3
        val b = ByteBuffer.allocate(4000).order(ByteOrder.LITTLE_ENDIAN)
        repeat(1000) { b.putShort(it.toShort()).putShort(it.toShort()) }
        var pts = 0L
        var accepted = 0
        repeat(10) {
            b.rewind()
            if (sink.handleBuffer(b, pts, 1)) {
                accepted++
                pts += 1000 * 1_000_000L / rate
            }
        }
        assertEquals(3, accepted) // then the delegate refused and the same input was retried
        r.acceptLimit = Int.MAX_VALUE
        b.rewind()
        assertTrue(sink.handleBuffer(b, pts, 1))
        assertEquals(4000, r.left.size)
    }

    @Test
    fun changedSpeedSwitchesTheDelegateTo16BitAndBack() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(), 0, null)
        feed(sink, 1000, 0L, value = 8192)
        sink.setPlaybackParameters(PlaybackParameters(1.5f))
        feed(sink, 1000, 1000 * 1_000_000L / rate, value = 8192)
        sink.setPlaybackParameters(PlaybackParameters.DEFAULT)
        feed(sink, 1000, 2000 * 1_000_000L / rate, value = 8192)
        // Float, then 16-bit for ExoPlayer's Sonic, then float again: nothing lost, same level.
        assertEquals(listOf(C.ENCODING_PCM_FLOAT, C.ENCODING_PCM_16BIT, C.ENCODING_PCM_FLOAT), r.encodings)
        assertEquals(3000, r.left.size)
        assertTrue(r.left.all { abs(it - 0.25f) < 1e-3f })
    }

    @Test
    fun sixteenBitPcmLabelledAsFloatIsReadAs16Bit() {
        // What a Samsung decoder does: reports float, writes 16-bit.
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format().buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build(), 0, null)
        feed(sink, 1000, 0L, value = -8192)
        assertEquals(1000, r.left.size)
        assertTrue(r.left.all { abs(it + 0.25f) < 1e-3f })
    }

    @Test
    fun realFloatInputIsLeftAlone() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format().buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build(), 0, null)
        val b = ByteBuffer.allocate(1000 * 8).order(ByteOrder.LITTLE_ENDIAN)
        repeat(1000) { i -> val v = if (i % 2 == 0) -0.5f else 0.9f; b.putFloat(v).putFloat(v) }
        b.flip()
        assertTrue(sink.handleBuffer(b, 0L, 1))
        assertEquals(1000, r.left.size)
        assertEquals(-0.5f, r.left[0], 1e-6f)
        assertEquals(0.9f, r.left[1], 1e-6f)
    }

    @Test
    fun aMeasurementArrivingMidSongWaitsForTheNextTrack() {
        Loudness.update(VolumeMatching(mode = VolumeMatching.Mode.TRACK))
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, rate, 0L, value = 8192) // 1 s at unity: nothing known yet
        // The scan of this song lands mid-song: -6 dB.
        Loudness.putGains(mapOf("a" to Gains(trackGainDb = -6.0)), replace = false)
        feed(sink, rate, 1_000_000L, value = 8192)
        assertTrue("no level jump mid-song", r.left.takeLast(1000).all { abs(it - 0.25f) < 1e-3f })

        // The next time it starts, the song gets its gain.
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, rate / 2, 2_000_000L, value = 8192)
        val half = 0.25f * 10.0.pow(-6.0 / 20).toFloat()
        assertTrue(abs(r.left.last() - half) < 2e-3f)
    }

    @Test
    fun settingsChangesApplyAtOnce() {
        Loudness.update(VolumeMatching(mode = VolumeMatching.Mode.TRACK))
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "b"), 0, null)
        feed(sink, rate, 0L, value = 8192)
        Loudness.update(VolumeMatching(mode = VolumeMatching.Mode.TRACK, untaggedGainDb = -6.0))
        feed(sink, rate, 1_000_000L, value = 8192)
        val half = 0.25f * 10.0.pow(-6.0 / 20).toFloat()
        assertTrue(abs(r.left.last() - half) < 2e-3f)
    }

    @Test
    fun speedSetBeforeTheTrackConfigures16Bit() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.setPlaybackParameters(PlaybackParameters(0.8f))
        sink.configure(format(), 0, null)
        assertEquals(listOf(C.ENCODING_PCM_16BIT), r.encodings)
    }
}
