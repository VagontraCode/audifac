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

/** Gapless trimming and crossfade, with a fake delegate recording what it's given. */
class DspAudioSinkTest {
    private val rate = 44_100

    /** What reached the "AudioTrack": samples (left channel) and each buffer's timestamp. */
    private class Recorder {
        val left = ArrayList<Float>()
        val pts = ArrayList<Pair<Int, Long>>() // (sample index where the buffer starts, pts)
        var acceptLimit = Int.MAX_VALUE // buffers accepted before refusing (backpressure test)
        val encodings = ArrayList<Int>() // each configure's PCM encoding

        val sink: AudioSink = Proxy.newProxyInstance(AudioSink::class.java.classLoader, arrayOf(AudioSink::class.java)) { _, m, args ->
            when (m.name) {
                "configure" -> {
                    encodings += (args[0] as Format).pcmEncoding
                    null
                }
                "handleBuffer" -> {
                    if (acceptLimit-- <= 0) return@newProxyInstance false
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
                "getCurrentPositionUs" -> 0L
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

    @After
    fun tearDown() {
        Crossfade.seconds = 0.0
        Crossfade.setAlbums(emptyMap())
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

    @Test
    fun crossfadeMixesTheTailIntoTheNextSong() {
        Crossfade.seconds = 0.1 // 4410 frames
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.configure(format(uri = "a"), 0, null)
        feed(sink, 20_000, 0, value = 16384) // 0.5
        sink.configure(format(uri = "b"), 0, null)
        val bStart = 20_000 * 1_000_000L / rate
        feed(sink, 20_000, bStart, value = 8192) // 0.25
        sink.playToEndOfStream()

        val fade = 4410
        assertEquals(40_000 - fade, r.left.size)
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
    fun speedSetBeforeTheTrackConfigures16Bit() {
        val r = Recorder()
        val sink = DspAudioSink(r.sink)
        sink.setPlaybackParameters(PlaybackParameters(0.8f))
        sink.configure(format(), 0, null)
        assertEquals(listOf(C.ENCODING_PCM_16BIT), r.encodings)
    }
}
