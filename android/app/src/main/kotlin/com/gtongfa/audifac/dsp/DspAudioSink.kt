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
 *
 * Crossfade: with [Crossfade.seconds] > 0 the last seconds of output are held
 * back; when the next song starts (same format, not the same album) its
 * beginning is mixed with that tail on equal-power curves.
 */
@OptIn(UnstableApi::class)
class DspAudioSink(private val delegate: AudioSink) : ForwardingAudioSink(delegate) {
    private var active = false
    private var encoding = C.ENCODING_INVALID
    private var channels = 0
    private var rate = 0
    private var inFrameBytes = 0
    private var processor: DspProcessor? = null

    // Gapless trimming (in frames).
    private var trimStartRemaining = 0
    private var paddingFrames = 0
    private var tail = FloatArray(0)
    private var tailFrames = 0
    private var tailPts = 0L

    private var samples = FloatArray(0)
    private var chunk = FloatArray(0)
    private var output: ByteBuffer = ByteBuffer.allocateDirect(0)
    private var outputPts = 0L

    /** The current input buffer was taken in; waiting for the delegate to accept it all. */
    private var pending = false

    // Crossfade.
    private var held: HeldAudio? = null
    private var mixer: FadeMixer? = null
    private var fadeArmed = false

    /** A format change: the held audio must play out before the delegate is reconfigured. */
    private var pendingDelegateFormat: Format? = null

    private fun holdFrames() = if (Crossfade.seconds > 0 && rate > 0) (Crossfade.seconds * rate).toInt() else 0

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
        val previous = trackFormat
        if (!pcm) {
            active = false
            processor = null
            held?.clear()
            mixer = null
            delegate.configure(inputFormat, specifiedBufferSize, outputChannels)
            return
        }
        Log.i(TAG, "PCM in: encoding=${inputFormat.pcmEncoding} ${inputFormat.sampleRate} Hz × ${inputFormat.channelCount}, delay=${inputFormat.encoderDelay} padding=${inputFormat.encoderPadding} → float")
        val sameOutput = active && rate == inputFormat.sampleRate && channels == inputFormat.channelCount
        active = true
        encoding = inputFormat.pcmEncoding
        channels = inputFormat.channelCount
        rate = inputFormat.sampleRate
        inFrameBytes = bytesPerSample(encoding) * channels
        trimStartRemaining = inputFormat.encoderDelay
        paddingFrames = inputFormat.encoderPadding
        val fresh = processor == null || processorRate != inputFormat.sampleRate || processorChannels != channels
        if (fresh) {
            processor = DspProcessor(inputFormat.sampleRate, channels)
            processorRate = inputFormat.sampleRate
            processorChannels = channels
        }
        // Configured at this track's first sample: its own volume matching gain.
        trackFormat = inputFormat
        applyGain(immediate = fresh)
        SignalPath.pcmEncoding = encoding
        SignalPath.sampleRate = rate
        SignalPath.channels = channels

        // Bit-perfect USB: when our processing would change nothing, the
        // decoder's PCM goes straight on and the mixer is set to leave it alone.
        val untouched = Crossfade.seconds <= 0 && processor?.isPassThrough() == true
        if (BitPerfect.enabled && untouched && BitPerfect.prepare(rate, channels, encoding)) {
            SignalPath.bitPerfect = true
            active = false
            held?.clear()
            mixer = null
            delegate.configure(inputFormat, specifiedBufferSize, outputChannels)
            return
        }
        SignalPath.bitPerfect = false
        if (BitPerfect.active) BitPerfect.release(if (untouched) "not available" else "processing is on")

        val floatFormat = inputFormat.buildUpon()
            .setPcmEncoding(C.ENCODING_PCM_FLOAT)
            .setEncoderDelay(0)
            .setEncoderPadding(0)
            .build()
        val h = held
        if (sameOutput && h != null && h.frames > 0) {
            // The previous song's tail is held: fade into this one?
            fadeArmed = previous != null && Crossfade.between(SourceUri.of(previous), SourceUri.of(inputFormat))
            delegate.configure(floatFormat, 0, null)
        } else if (h != null && h.frames > 0) {
            // Different rate / channels: play the tail out first, unmixed.
            fadeArmed = false
            pendingDelegateFormat = floatFormat
        } else {
            fadeArmed = false
            held = HeldAudio(channels, rate)
            delegate.configure(floatFormat, 0, null)
        }
        mixer = null
    }

    // Same rate & channels between tracks: keep the processor (and its filter
    // state) so gapless transitions don't click.
    private var processorRate = 0
    private var processorChannels = 0

    private var trackFormat: Format? = null
    private var loudnessVersion = -1L
    private var loggedGain = Double.NaN

    private fun applyGain(immediate: Boolean) {
        val format = trackFormat ?: return
        loudnessVersion = Loudness.version
        val gains = Loudness.gainsFor(format)
        val linear = Loudness.settings.linearGain(gains)
        processor?.setGain(linear, immediate)
        SignalPath.gainDb = 20 * kotlin.math.log10(linear)
        val changed = linear != loggedGain
        loggedGain = linear
        if (changed && Loudness.settings.mode != VolumeMatching.Mode.OFF) {
            Log.i(TAG, "volume matching ${Loudness.settings.mode}: ${"%.2f".format(20 * kotlin.math.log10(linear))} dB ($gains) for ${SourceUri.of(format)}")
        }
    }

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (!active) return delegate.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)

        // A format change waits for the held tail to play out under the old one.
        pendingDelegateFormat?.let { format ->
            if (!drain(keep = 0)) return false
            delegate.configure(format, 0, null)
            pendingDelegateFormat = null
            held = HeldAudio(channels, rate)
        }

        if (!pending) {
            if (loudnessVersion != Loudness.version) applyGain(immediate = false)
            prepareOutput(buffer, presentationTimeUs)
            pending = true
        }
        if (!drain(keep = holdFrames())) return false
        pending = false
        buffer.position(buffer.limit())
        return true
    }

    /**
     * Sends held audio to the delegate until only [keep] frames remain, one
     * continuous run at a time (each with its own timestamp). False if the
     * delegate is full (call again later).
     */
    private fun drain(keep: Int): Boolean {
        val h = held ?: return true
        while (true) {
            if (output.hasRemaining()) {
                if (!delegate.handleBuffer(output, outputPts, 1)) return false
                if (output.hasRemaining()) return false
            }
            val n = h.runLength(maxOf(0, h.frames - keep))
            if (n <= 0) return true
            outputPts = h.frontPts()
            if (chunk.size < n * channels) chunk = FloatArray(n * channels)
            h.copyOut(chunk, 0, n)
            h.drop(n)
            Visualizer.feed(chunk, n, channels, rate, outputPts)
            val bytes = n * channels * 4
            if (output.capacity() < bytes) output = ByteBuffer.allocateDirect(bytes * 2).order(ByteOrder.nativeOrder())
            output.clear()
            output.order(ByteOrder.nativeOrder())
            output.asFloatBuffer().put(chunk, 0, n * channels)
            output.limit(bytes)
        }
    }

    private fun usFor(frames: Int) = frames * 1_000_000L / rate

    /** Decodes [buffer] to float, trims, processes, mixes, and appends to the held audio. */
    private fun prepareOutput(buffer: ByteBuffer, pts: Long) {
        val frames = buffer.remaining() / inFrameBytes
        ensureSamples((frames + tailFrames) * channels)

        // Held-back padding tail of the previous buffer goes first.
        System.arraycopy(tail, 0, samples, 0, tailFrames * channels)
        var count = tailFrames

        val src = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val skip = minOf(trimStartRemaining, frames)
        trimStartRemaining -= skip
        src.position(src.position() + skip * inFrameBytes)
        val decoded = frames - skip
        readFloats(src, samples, count * channels, decoded * channels)
        val startPts = if (tailFrames > 0) tailPts else pts + usFor(skip)

        // Process only the new frames (the held tail was processed last time).
        processor?.let { p ->
            val processing = !p.isPassThrough()
            SignalPath.processing = processing
            if (processing) p.process(samples, decoded, count * channels)
        }
        count += decoded

        // Keep the last [paddingFrames] back: if the stream ends here they are
        // encoder padding and must not be played.
        val hold = minOf(paddingFrames, count)
        val emit = count - hold
        if (tail.size < hold * channels) tail = FloatArray(hold * channels)
        System.arraycopy(samples, emit * channels, tail, 0, hold * channels)
        tailFrames = hold
        tailPts = startPts + usFor(emit)

        val h = held ?: HeldAudio(channels, rate).also { held = it }
        if (fadeArmed && emit > 0) {
            // The previous song's tail fades out under this one's start.
            fadeArmed = false
            mixer = FadeMixer(h.takeAll(), channels)
            Log.i(TAG, "crossfade into ${trackFormat?.let { SourceUri.of(it) }}")
        }
        mixer?.let { m ->
            m.mix(samples, 0, emit)
            if (m.done) mixer = null
        }
        h.append(samples, emit, startPts)
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
        mixer = null
        if (active && !drain(keep = 0)) return // Called again until everything is out.
        delegate.playToEndOfStream()
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long =
        delegate.getCurrentPositionUs(sourceEnded).also { if (active) Visualizer.playheadUs = it }

    override fun isEnded(): Boolean = (held?.frames ?: 0) == 0 && !output.hasRemaining() && delegate.isEnded()

    override fun hasPendingData(): Boolean = (held?.frames ?: 0) > 0 || delegate.hasPendingData()

    override fun flush() {
        pending = false
        tailFrames = 0
        trimStartRemaining = 0
        processor?.reset()
        held?.clear()
        output.clear().limit(0)
        mixer = null
        fadeArmed = false
        pendingDelegateFormat?.let { format ->
            // Nothing left to play out: switch now.
            delegate.configure(format, 0, null)
            pendingDelegateFormat = null
            held = HeldAudio(channels, rate)
        }
        delegate.flush()
    }

    override fun reset() {
        pending = false
        tailFrames = 0
        processor = null
        trackFormat = null
        active = false
        held = null
        output.clear().limit(0)
        mixer = null
        fadeArmed = false
        pendingDelegateFormat = null
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
