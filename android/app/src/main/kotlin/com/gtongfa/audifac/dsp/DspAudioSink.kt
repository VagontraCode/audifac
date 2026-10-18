package com.gtongfa.audifac.dsp

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Sits between the decoder and ExoPlayer's DefaultAudioSink.
 *
 * ExoPlayer only runs custom AudioProcessors on 16-bit integer PCM, so instead
 * this sink receives the decoder's full-resolution PCM (16/24/32-bit or
 * float), runs [DspProcessor] in double precision, and hands 32-bit float to
 * the delegate (built with float output enabled). It also performs the
 * encoder delay / padding trimming that DefaultAudioSink skips on its float
 * path, so gapless albums stay gapless.
 */
@OptIn(UnstableApi::class)
class DspAudioSink(private val delegate: AudioSink) : ForwardingAudioSink(delegate) {
    private var active = false
    private var encoding = C.ENCODING_INVALID
    private var channels = 0
    private var inFrameBytes = 0
    private var processor: DspProcessor? = null

    // Gapless trimming (in frames).
    private var trimStartRemaining = 0
    private var paddingFrames = 0
    private var tail = FloatArray(0)
    private var tailFrames = 0

    private var samples = FloatArray(0)
    private var output: ByteBuffer = ByteBuffer.allocateDirect(0)
    private var pending = false

    override fun supportsFormat(format: Format): Boolean = delegate.supportsFormat(format)

    override fun getFormatSupport(format: Format): Int {
        if (MimeTypes.AUDIO_RAW == format.sampleMimeType && isSupportedPcm(format.pcmEncoding)) {
            return AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY
        }
        return delegate.getFormatSupport(format)
    }

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        val pcm = MimeTypes.AUDIO_RAW == inputFormat.sampleMimeType &&
            isSupportedPcm(inputFormat.pcmEncoding) && outputChannels == null
        // A new item starts: its predecessor's held-back tail is encoder padding.
        tailFrames = 0
        pending = false
        if (!pcm) {
            active = false
            processor = null
            delegate.configure(inputFormat, specifiedBufferSize, outputChannels)
            return
        }
        Log.i(TAG, "PCM in: encoding=${inputFormat.pcmEncoding} ${inputFormat.sampleRate} Hz × ${inputFormat.channelCount}, delay=${inputFormat.encoderDelay} padding=${inputFormat.encoderPadding} → float")
        active = true
        encoding = inputFormat.pcmEncoding
        channels = inputFormat.channelCount
        inFrameBytes = bytesPerSample(encoding) * channels
        trimStartRemaining = inputFormat.encoderDelay
        paddingFrames = inputFormat.encoderPadding
        if (processor == null || processorRate != inputFormat.sampleRate || processorChannels != channels) {
            processor = DspProcessor(inputFormat.sampleRate, channels)
            processorRate = inputFormat.sampleRate
            processorChannels = channels
        }
        val floatFormat = inputFormat.buildUpon()
            .setPcmEncoding(C.ENCODING_PCM_FLOAT)
            .setEncoderDelay(0)
            .setEncoderPadding(0)
            .build()
        delegate.configure(floatFormat, 0, null)
    }

    // Same rate & channels between tracks: keep the processor (and its filter
    // state) so gapless transitions don't click.
    private var processorRate = 0
    private var processorChannels = 0

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (!active) return delegate.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)

        if (!pending) {
            prepareOutput(buffer)
            pending = true
        }
        if (!output.hasRemaining()) {
            pending = false
            buffer.position(buffer.limit())
            return true
        }
        val consumed = delegate.handleBuffer(output, presentationTimeUs, encodedAccessUnitCount)
        if (consumed) {
            pending = false
            buffer.position(buffer.limit())
        }
        return consumed
    }

    /** Decodes [buffer] to float, trims, processes, and fills [output]. */
    private fun prepareOutput(buffer: ByteBuffer) {
        val frames = buffer.remaining() / inFrameBytes
        ensureSamples((frames + tailFrames) * channels)

        // Held-back tail of the previous buffer goes first.
        System.arraycopy(tail, 0, samples, 0, tailFrames * channels)
        var count = tailFrames

        val src = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val skip = minOf(trimStartRemaining, frames)
        trimStartRemaining -= skip
        src.position(src.position() + skip * inFrameBytes)
        val decoded = frames - skip
        readFloats(src, samples, count * channels, decoded * channels)

        // Process only the new frames (the held tail was processed last time).
        processor?.let { p -> if (!p.isPassThrough()) p.process(samples, decoded, count * channels) }
        count += decoded

        // Keep the last [paddingFrames] back: if the stream ends here they are
        // encoder padding and must not be played.
        val hold = minOf(paddingFrames, count)
        val emit = count - hold
        if (tail.size < hold * channels) tail = FloatArray(hold * channels)
        System.arraycopy(samples, emit * channels, tail, 0, hold * channels)
        tailFrames = hold

        val bytes = emit * channels * 4
        if (output.capacity() < bytes) {
            output = ByteBuffer.allocateDirect(bytes * 2).order(ByteOrder.nativeOrder())
        }
        output.clear()
        output.order(ByteOrder.nativeOrder())
        output.asFloatBuffer().put(samples, 0, emit * channels)
        output.limit(bytes)
    }

    private fun ensureSamples(size: Int) {
        if (samples.size < size) samples = FloatArray(size * 2)
    }

    private fun readFloats(src: ByteBuffer, dst: FloatArray, offset: Int, count: Int) {
        var o = offset
        when (encoding) {
            C.ENCODING_PCM_16BIT -> repeat(count) { dst[o++] = src.short / 32768f }
            C.ENCODING_PCM_24BIT -> repeat(count) {
                val b0 = src.get().toInt() and 0xFF
                val b1 = src.get().toInt() and 0xFF
                val b2 = src.get().toInt() // sign-extends
                dst[o++] = ((b2 shl 16) or (b1 shl 8) or b0) / 8388608f
            }
            C.ENCODING_PCM_32BIT -> repeat(count) { dst[o++] = (src.int / 2147483648.0).toFloat() }
            C.ENCODING_PCM_FLOAT -> repeat(count) { dst[o++] = src.float }
            C.ENCODING_PCM_8BIT -> repeat(count) { dst[o++] = ((src.get().toInt() and 0xFF) - 128) / 128f }
        }
    }

    override fun playToEndOfStream() {
        tailFrames = 0 // The held-back frames are encoder padding: dropped.
        delegate.playToEndOfStream()
    }

    override fun flush() {
        pending = false
        tailFrames = 0
        trimStartRemaining = 0
        processor?.reset()
        delegate.flush()
    }

    override fun reset() {
        pending = false
        tailFrames = 0
        processor = null
        active = false
        delegate.reset()
    }

    companion object {
        private const val TAG = "AudifacDsp"

        fun isSupportedPcm(encoding: Int) = encoding == C.ENCODING_PCM_16BIT ||
            encoding == C.ENCODING_PCM_24BIT || encoding == C.ENCODING_PCM_32BIT ||
            encoding == C.ENCODING_PCM_FLOAT || encoding == C.ENCODING_PCM_8BIT

        fun bytesPerSample(encoding: Int) = when (encoding) {
            C.ENCODING_PCM_8BIT -> 1
            C.ENCODING_PCM_16BIT -> 2
            C.ENCODING_PCM_24BIT -> 3
            else -> 4
        }
    }
}
