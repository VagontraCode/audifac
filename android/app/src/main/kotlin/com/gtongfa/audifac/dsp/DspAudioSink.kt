package com.gtongfa.audifac.dsp

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

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

    /** 16-bit output (while the speed is changed) is dithered, not just rounded. */
    private val dither = Dither()
    private var shorts = ShortArray(0)
    private var output: ByteBuffer = ByteBuffer.allocateDirect(0)
    private var outputPts = 0L

    /** The current input buffer was taken in; waiting for the delegate to accept it all. */
    private var pending = false

    // Is "float" input really float? (see checkFloatLabel)
    private var floatLabelChecked = true
    private var floatEvidence = 0

    // Crossfade.
    private var held: HeldAudio? = null
    private var mixer: FadeMixer? = null
    private var fadeArmed = false

    /** A format change: the held audio must play out before the delegate is reconfigured. */
    private var pendingDelegateFormat: Format? = null

    /**
     * What the delegate is configured with: float, or 16-bit while the speed
     * or pitch is changed (only then does DefaultAudioSink run its Sonic
     * speed processor; asking the AudioTrack to change speed distorts on some
     * phones, e.g. Samsung).
     */
    private var delegateFormat: Format? = null
    private var outEncoding = C.ENCODING_PCM_FLOAT
    private var playbackParameters = PlaybackParameters.DEFAULT

    private fun wantedEncoding() =
        if (playbackParameters == PlaybackParameters.DEFAULT) C.ENCODING_PCM_FLOAT else C.ENCODING_PCM_16BIT

    /**
     * Runs the EQ on audio as it leaves for the delegate: the processor of
     * the format the delegate is configured with (a held tail of another
     * format plays out with its own).
     */
    private var effects: DspProcessor? = null

    /** Levels after the EQ for the current song (signal path: peak, limiter, clipping). */
    private val trackLevels = SongLevels()

    /** Last volume matching gain, given to a new effects processor (its limiter guards boosts). */
    private var lastGain = 1.0

    /** The EQ for [rate] / [channels]: kept while they don't change (filter state, gapless). */
    private fun effectsFor(rate: Int, channels: Int): DspProcessor {
        val e = effects
        if (e != null && e.sampleRate == rate && e.channels == channels) return e
        return DspProcessor(rate, channels).also { it.setGain(lastGain, immediate = true) }
    }

    // Resampling (see Resampling): the rate audio leaves at, and the converter.
    private var outRate = 0
    private var resampler: Resampler? = null

    /** Presentation time of the resampler's input frame 0. */
    private var resampleAnchorUs = C.TIME_UNSET

    private fun configureDelegate(format: Format) {
        effects = effectsFor(format.sampleRate, format.channelCount)
        val out = format.buildUpon().setPcmEncoding(wantedEncoding()).build()
        delegate.configure(out, 0, null)
        delegateFormat = out
        outEncoding = out.pcmEncoding
        SignalPath.outputEncoding = outEncoding
        SignalPath.outputRate = out.sampleRate
    }

    override fun setPlaybackParameters(playbackParameters: PlaybackParameters) {
        this.playbackParameters = playbackParameters
        delegate.setPlaybackParameters(playbackParameters)
    }

    private fun holdFrames() = if (Crossfade.seconds > 0 && outRate > 0) (Crossfade.seconds * outRate).toInt() else 0

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
            resampler = null
            held?.clear()
            mixer = null
            delegate.configure(inputFormat, specifiedBufferSize, outputChannels)
            return
        }
        val target = Resampling.targetRate()
        val newOutRate = if (target != null && target != inputFormat.sampleRate && Resampler.supports(inputFormat.sampleRate, target)) {
            target
        } else {
            inputFormat.sampleRate
        }
        Log.i(TAG, "PCM in: encoding=${inputFormat.pcmEncoding} ${inputFormat.sampleRate} Hz × ${inputFormat.channelCount}, delay=${inputFormat.encoderDelay} padding=${inputFormat.encoderPadding} → float${if (newOutRate != inputFormat.sampleRate) ", resampled to $newOutRate Hz" else ""}")
        val sameOutput = active && outRate == newOutRate && channels == inputFormat.channelCount
        // The previous song's last frames still inside the resampler go out
        // first (a converter for another rate / channel count takes over).
        val r = resampler
        if (active && r != null &&
            (r.inRate != inputFormat.sampleRate || r.outRate != newOutRate || channels != inputFormat.channelCount)
        ) {
            flushResampler()
            resampler = null
        }
        active = true
        encoding = inputFormat.pcmEncoding
        floatLabelChecked = encoding != C.ENCODING_PCM_FLOAT
        floatEvidence = 0
        channels = inputFormat.channelCount
        rate = inputFormat.sampleRate
        outRate = newOutRate
        if (outRate != rate && resampler == null) resampler = Resampler(rate, outRate, channels)
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
        trackFrames = 0
        trackLevels.reset()
        applyGain(immediate = fresh)
        SignalPath.pcmEncoding = encoding
        SignalPath.sampleRate = rate
        SignalPath.channels = channels

        // Bit-perfect USB: when our processing would change nothing, the
        // decoder's PCM goes straight on and the mixer is set to leave it alone.
        val untouched = Crossfade.seconds <= 0 && outRate == rate &&
            processor?.isGainPassThrough() == true && effectsFor(rate, channels).isEffectsPassThrough() &&
            playbackParameters == PlaybackParameters.DEFAULT
        if (BitPerfect.enabled && untouched && BitPerfect.prepare(rate, channels, encoding)) {
            SignalPath.bitPerfect = true
            SignalPath.resampledTo = 0
            active = false
            held?.clear()
            mixer = null
            delegate.configure(inputFormat, specifiedBufferSize, outputChannels)
            return
        }
        SignalPath.bitPerfect = false
        if (BitPerfect.active) BitPerfect.release(if (untouched) "not available" else "processing is on")

        SignalPath.resampledTo = if (outRate != rate) outRate else 0
        val floatFormat = inputFormat.buildUpon()
            .setSampleRate(outRate)
            .setPcmEncoding(C.ENCODING_PCM_FLOAT)
            .setEncoderDelay(0)
            .setEncoderPadding(0)
            .build()
        val h = held
        if (sameOutput && h != null && h.frames > 0) {
            // The previous song's tail is held: fade into this one?
            fadeArmed = previous != null && Crossfade.between(SourceUri.of(previous), SourceUri.of(inputFormat))
            configureDelegate(floatFormat)
        } else if (h != null && h.frames > 0) {
            // Different rate / channels: play the tail out first, unmixed.
            fadeArmed = false
            pendingDelegateFormat = floatFormat
        } else {
            fadeArmed = false
            held = HeldAudio(channels, outRate)
            configureDelegate(floatFormat)
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

    private var settingsVersion = -1L

    /** Frames of the current track taken in so far. */
    private var trackFrames = 0L

    private fun applyGain(immediate: Boolean) {
        val format = trackFormat ?: return
        loudnessVersion = Loudness.version
        settingsVersion = Loudness.settingsVersion
        val gains = Loudness.gainsFor(format)
        val linear = Loudness.settings.linearGain(gains)
        processor?.setGain(linear, immediate)
        effects?.setGain(linear, immediate)
        lastGain = linear
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
            configureDelegate(format)
            pendingDelegateFormat = null
            held = HeldAudio(channels, outRate)
        }

        // The speed changed: switch the delegate between float and 16-bit
        // once the bytes already prepared in the old encoding are taken.
        if (wantedEncoding() != outEncoding && !output.hasRemaining()) {
            delegateFormat?.let { configureDelegate(it) }
        }

        if (!pending) {
            if (loudnessVersion != Loudness.version) {
                // Settings changes apply at once. A new measurement only in a
                // song's first moments: a level jump mid-song is audible (heard
                // as a dropout); the song gets it the next time it plays.
                val early = trackFrames < rate * NEW_GAIN_WINDOW_S
                if (settingsVersion != Loudness.settingsVersion || early) applyGain(immediate = false)
                else loudnessVersion = Loudness.version
            }
            prepareOutput(buffer, presentationTimeUs)
            pending = true
        }
        if (!drain(keep = holdFrames())) return false
        pending = false
        buffer.position(buffer.limit())
        return true
    }

    /**
     * Hands held audio to the delegate for as long as it takes any, one
     * continuous run at a time (each with its own timestamp), in short chunks
     * so the EQ follows settings closely. The crossfade reserve is only what
     * the delegate can't take yet: the AudioTrack is never starved to build it
     * (a starved AudioTrack doesn't even start, and the player, seeing no
     * progress, would call itself stuck and skip the song).
     *
     * True when more input may be taken: up to [keep] frames wait here.
     */
    private fun drain(keep: Int): Boolean {
        val h = held ?: return true
        while (true) {
            if (output.hasRemaining()) {
                if (!delegate.handleBuffer(output, outputPts, 1) || output.hasRemaining()) {
                    return keep > 0 && h.frames <= keep
                }
            }
            // The held audio's own format: a tail of the previous song can still
            // be playing out after a song of another format was configured.
            val channels = h.channels
            val n = h.runLength(maxOf(1, h.rate / CHUNKS_PER_SECOND))
            if (n <= 0) return true
            outputPts = h.frontPts()
            if (chunk.size < n * channels) chunk = FloatArray(n * channels)
            h.copyOut(chunk, 0, n)
            h.drop(n)
            // EQ here, after the crossfade reserve: changes are heard at once.
            effects?.let { p ->
                val processing = !p.isEffectsPassThrough()
                SignalPath.processing = processing || !p.isGainPassThrough()
                if (processing) {
                    p.processEffects(chunk, n)
                    trackLevels.add(p.takeStats())
                }
            }
            Visualizer.feed(chunk, n, channels, h.rate, outputPts)
            val count = n * channels
            val bytes = count * (if (outEncoding == C.ENCODING_PCM_16BIT) 2 else 4)
            if (output.capacity() < bytes) output = ByteBuffer.allocateDirect(bytes * 2).order(ByteOrder.nativeOrder())
            output.clear()
            output.order(ByteOrder.nativeOrder())
            if (outEncoding == C.ENCODING_PCM_16BIT) {
                for (i in 0 until count) output.putShort(i * 2, dither.toPcm16(chunk[i]))
            } else {
                output.asFloatBuffer().put(chunk, 0, count)
            }
            output.limit(bytes)
        }
    }

    private fun usFor(frames: Int) = frames * 1_000_000L / rate

    /** Decodes [buffer] to float, trims, processes, mixes, and appends to the held audio. */
    private fun prepareOutput(buffer: ByteBuffer, pts: Long) {
        if (!floatLabelChecked) checkFloatLabel(buffer)
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

        // Volume matching on the new frames only (the held tail had it last
        // time). Each song gets its own gain before a crossfade mixes them;
        // the EQ runs later, in drain().
        processor?.let { p ->
            if (!p.isGainPassThrough()) p.applyGain(samples, decoded, count * channels)
        }
        count += decoded
        trackFrames += decoded

        // Keep the last [paddingFrames] back: if the stream ends here they are
        // encoder padding and must not be played.
        val hold = minOf(paddingFrames, count)
        val emit = count - hold
        if (tail.size < hold * channels) tail = FloatArray(hold * channels)
        System.arraycopy(samples, emit * channels, tail, 0, hold * channels)
        tailFrames = hold
        tailPts = startPts + usFor(emit)

        // To the output rate (each song before mixing: a crossfade can join
        // songs of different rates).
        var out = samples
        var outFrames = emit
        var outPts = startPts
        val r = resampler
        if (r != null && emit > 0) {
            if (r.taken == 0L || resampleAnchorUs == C.TIME_UNSET) {
                resampleAnchorUs = startPts
            } else {
                // Follow real jumps in the timeline; tiny drifts (rounding) stay.
                val drift = startPts - (resampleAnchorUs + r.taken * 1_000_000L / r.inRate)
                if (abs(drift) > MAX_RESAMPLE_DRIFT_US) resampleAnchorUs += drift
            }
            outPts = resampleAnchorUs + r.produced * 1_000_000L / r.outRate
            outFrames = r.process(samples, emit)
            out = r.out
        }

        val h = held ?: HeldAudio(channels, outRate).also { held = it }
        if (fadeArmed && outFrames > 0) {
            // The previous song's tail fades out under this one's start.
            fadeArmed = false
            mixer = FadeMixer(h.takeAll(), channels)
            Log.i(TAG, "crossfade into ${trackFormat?.let { SourceUri.of(it) }}")
        }
        mixer?.let { m ->
            m.mix(out, 0, outFrames)
            if (m.done) mixer = null
        }
        h.append(out, outFrames, outPts)
    }

    /** The resampler's last frames (the filter's delay) go to the held audio; it starts over. */
    private fun flushResampler() {
        val r = resampler ?: return
        if (r.taken == 0L) return
        val pts = resampleAnchorUs + r.produced * 1_000_000L / r.outRate
        val n = r.flush()
        if (n > 0) held?.append(r.out, n, pts)
        resampleAnchorUs = C.TIME_UNSET
    }

    /**
     * Some phone decoders report float while writing 16-bit PCM (Samsung's,
     * found on a Galaxy S24). Real float audio is finite and near ±1; 16-bit
     * pairs read as float soon give NaN or huge values. The first seconds of
     * each float stream are checked; on a mismatch the bytes are read as
     * 16-bit from this buffer on, and the decoder is no longer asked for float.
     */
    private fun checkFloatLabel(buffer: ByteBuffer) {
        val f = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        while (f.remaining() >= 4) {
            val v = f.float
            if (v.isNaN() || v.isInfinite() || abs(v) > 8f) {
                Log.w(TAG, "\"float\" input is 16-bit PCM: reading it as such")
                encoding = C.ENCODING_PCM_16BIT
                inFrameBytes = 2 * channels
                SignalPath.pcmEncoding = encoding
                floatLabelChecked = true
                DecoderQuirks.reportMislabelledFloat()
                return
            }
            if (abs(v) > 1e-6f) floatEvidence++
        }
        if (floatEvidence >= FLOAT_EVIDENCE_SAMPLES) floatLabelChecked = true
    }

    private fun ensureSamples(size: Int) {
        if (samples.size < size) samples = FloatArray(size * 2)
    }

    private fun readFloats(src: ByteBuffer, dst: FloatArray, offset: Int, count: Int) {
        var o = offset
        when (encoding) {
            // Bulk reads: one bounds check per buffer instead of per sample.
            C.ENCODING_PCM_16BIT -> {
                if (shorts.size < count) shorts = ShortArray(count)
                src.asShortBuffer().get(shorts, 0, count)
                src.position(src.position() + count * 2)
                for (i in 0 until count) dst[o++] = shorts[i] / 32768f
            }
            C.ENCODING_PCM_24BIT -> repeat(count) {
                val b0 = src.get().toInt() and 0xFF
                val b1 = src.get().toInt() and 0xFF
                val b2 = src.get().toInt() // sign-extends
                dst[o++] = ((b2 shl 16) or (b1 shl 8) or b0) / 8388608f
            }
            C.ENCODING_PCM_32BIT -> repeat(count) { dst[o++] = (src.int / 2147483648.0).toFloat() }
            C.ENCODING_PCM_FLOAT -> {
                src.asFloatBuffer().get(dst, o, count)
                src.position(src.position() + count * 4)
            }
            C.ENCODING_PCM_8BIT -> repeat(count) { dst[o++] = ((src.get().toInt() and 0xFF) - 128) / 128f }
        }
    }

    override fun playToEndOfStream() {
        tailFrames = 0 // The held-back frames are encoder padding: dropped.
        mixer = null
        if (active) flushResampler()
        if (active && !drain(keep = 0)) return // Called again until everything is out.
        delegate.playToEndOfStream()
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        // No new input comes at the end of a song until playback nears it,
        // which it can't while the crossfade reserve is held: keep the
        // AudioTrack fed from the reserve (polled here, as handleBuffer isn't
        // called), or playback freezes until the player gives up and skips.
        if (active && pendingDelegateFormat == null) drain(keep = holdFrames())
        return delegate.getCurrentPositionUs(sourceEnded).also { if (active) Visualizer.playheadUs = it }
    }

    override fun isEnded(): Boolean = (held?.frames ?: 0) == 0 && !output.hasRemaining() && delegate.isEnded()

    override fun hasPendingData(): Boolean = (held?.frames ?: 0) > 0 || delegate.hasPendingData()

    override fun flush() {
        pending = false
        tailFrames = 0
        trimStartRemaining = 0
        processor?.reset()
        resampler?.reset()
        resampleAnchorUs = C.TIME_UNSET
        effects?.reset()
        held?.clear()
        output.clear().limit(0)
        mixer = null
        fadeArmed = false
        pendingDelegateFormat?.let { format ->
            // Nothing left to play out: switch now.
            effects = processor
            delegate.configure(format, 0, null)
            pendingDelegateFormat = null
            held = HeldAudio(channels, outRate)
        }
        delegate.flush()
        if (active && wantedEncoding() != outEncoding) delegateFormat?.let { configureDelegate(it) }
    }

    override fun reset() {
        pending = false
        tailFrames = 0
        processor = null
        resampler = null
        outRate = 0
        effects = null
        trackFormat = null
        active = false
        held = null
        output.clear().limit(0)
        mixer = null
        fadeArmed = false
        pendingDelegateFormat = null
        delegateFormat = null
        delegate.reset()
    }

    companion object {
        private const val TAG = "AudifacDsp"

        /** Non-silent samples that must look like real float before the check stops. */
        private const val FLOAT_EVIDENCE_SAMPLES = 1 shl 16

        /** Chunks held audio is handed over in (50 ms): how soon EQ changes are heard. */
        private const val CHUNKS_PER_SECOND = 20

        /** Larger jumps between input timestamps and the resampler's count are followed. */
        private const val MAX_RESAMPLE_DRIFT_US = 20_000L

        /** How early in a song a newly measured gain may still be applied. */
        private const val NEW_GAIN_WINDOW_S = 0.3

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
