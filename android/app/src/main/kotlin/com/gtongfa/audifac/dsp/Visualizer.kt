package com.gtongfa.audifac.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Spectrum and level meter of what is being played. The DSP sink feeds what
 * it hands to the AudioTrack (with timestamps); [snapshot] analyses the
 * window ending at the current playback position, so the display matches
 * what is heard rather than what was just written.
 */
object Visualizer {
    const val FFT_SIZE = 2048
    const val BANDS = 32

    /** Only collect while someone is watching. */
    @Volatile
    var enabled = false

    private const val RING = 1 shl 16 // ~1.4 s at 48 kHz
    private val left = FloatArray(RING)
    private val right = FloatArray(RING)
    private var written = 0L // total frames written
    private var writtenEndPts = 0L
    private var rate = 48_000

    /** Playback position (µs) reported by the sink. */
    @Volatile
    var playheadUs = 0L

    private val lock = Any()

    fun reset() = synchronized(lock) {
        written = 0
        left.fill(0f)
        right.fill(0f)
    }

    /** [n] interleaved frames of [channels] channels, the first presented at [pts]. */
    fun feed(samples: FloatArray, n: Int, channels: Int, sampleRate: Int, pts: Long) {
        if (!enabled || n <= 0) return
        synchronized(lock) {
            rate = sampleRate
            var w = (written % RING).toInt()
            for (f in 0 until n) {
                val i = f * channels
                left[w] = samples[i]
                right[w] = if (channels > 1) samples[i + 1] else samples[i]
                w = (w + 1) and (RING - 1)
            }
            written += n
            writtenEndPts = pts + n * 1_000_000L / sampleRate
        }
    }

    private val window = DoubleArray(FFT_SIZE) { 0.5 - 0.5 * cos(2 * PI * it / (FFT_SIZE - 1)) }
    private val windowSum = window.sum()
    private val re = DoubleArray(FFT_SIZE)
    private val im = DoubleArray(FFT_SIZE)

    /** Band levels in dBFS (−90…0), and peak / RMS per channel in dBFS. */
    class Snapshot(val bands: FloatArray, val peakL: Float, val peakR: Float, val rmsL: Float, val rmsR: Float, val rate: Int)

    fun snapshot(): Snapshot? {
        val l = DoubleArray(FFT_SIZE)
        val r = DoubleArray(FFT_SIZE)
        val sr: Int
        synchronized(lock) {
            if (written < FFT_SIZE) return null
            sr = rate
            // Frame being heard now: back from the newest written frame by the
            // time still queued in the AudioTrack.
            val lagFrames = ((writtenEndPts - playheadUs).coerceIn(0, 1_000_000) * sr / 1_000_000L)
            val end = written - lagFrames
            if (end < FFT_SIZE || written - end > RING - FFT_SIZE) return null
            var idx = ((end - FFT_SIZE) % RING).toInt()
            for (i in 0 until FFT_SIZE) {
                l[i] = left[idx].toDouble()
                r[i] = right[idx].toDouble()
                idx = (idx + 1) and (RING - 1)
            }
        }
        // Levels over the last ~43 ms.
        var pl = 0.0; var pr = 0.0; var sl = 0.0; var srr = 0.0
        for (i in 0 until FFT_SIZE) {
            pl = max(pl, kotlin.math.abs(l[i])); pr = max(pr, kotlin.math.abs(r[i]))
            sl += l[i] * l[i]; srr += r[i] * r[i]
        }
        // Spectrum of the mono mix.
        for (i in 0 until FFT_SIZE) {
            re[i] = (l[i] + r[i]) * 0.5 * window[i]
            im[i] = 0.0
        }
        fft(re, im)
        val bands = FloatArray(BANDS)
        val nyquist = sr / 2.0
        val lo = 30.0
        val hi = minOf(20_000.0, nyquist)
        for (b in 0 until BANDS) {
            val f0 = lo * (hi / lo).pow(b.toDouble() / BANDS)
            val f1 = lo * (hi / lo).pow((b + 1).toDouble() / BANDS)
            val k0 = max(1, (f0 / sr * FFT_SIZE).toInt())
            val k1 = max(k0 + 1, (f1 / sr * FFT_SIZE).toInt())
            var peak = 0.0
            for (k in k0 until minOf(k1, FFT_SIZE / 2)) peak = max(peak, re[k] * re[k] + im[k] * im[k])
            // Amplitude of a full-scale sine reads 0 dBFS.
            val amp = 2 * sqrt(peak) / windowSum
            bands[b] = db(amp)
        }
        return Snapshot(bands, db(pl), db(pr), db(sqrt(sl / FFT_SIZE) * sqrt(2.0)), db(sqrt(srr / FFT_SIZE) * sqrt(2.0)), sr)
    }

    private fun db(v: Double): Float = if (v <= 1e-5) -100f else (20 * log10(v)).toFloat().coerceIn(-100f, 6f)

    /** In-place radix-2 FFT. */
    fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2 * PI / len
            val wr = cos(ang)
            val wi = sin(ang)
            var i = 0
            while (i < n) {
                var cr = 1.0
                var ci = 0.0
                for (k in 0 until len / 2) {
                    val a = i + k
                    val b = a + len / 2
                    val xr = re[b] * cr - im[b] * ci
                    val xi = re[b] * ci + im[b] * cr
                    re[b] = re[a] - xr; im[b] = im[a] - xi
                    re[a] += xr; im[a] += xi
                    val nr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = nr
                }
                i += len
            }
            len = len shl 1
        }
    }
}

/** What the DSP sink is doing right now, for the "signal path" panel. */
object SignalPath {
    @Volatile var pcmEncoding = 0
    @Volatile var sampleRate = 0
    @Volatile var channels = 0
    @Volatile var processing = false
    @Volatile var gainDb = 0.0
    @Volatile var bitPerfect = false

    /** Rate our resampler converts to (0: not resampling). */
    @Volatile var resampledTo = 0

    /** Rate audio leaves the DSP at (what the AudioTrack gets). */
    @Volatile var outputRate = 0

    // Levels after the EQ for the current song (see SongLevels); levelFrames 0 = none measured.
    @Volatile var peakDb = -100.0
    @Volatile var limitedFraction = 0.0
    @Volatile var clippedFrames = 0L
    @Volatile var levelFrames = 0L

    /** Bass loudness compensation adds now (0: off or near full volume). */
    @Volatile var loudnessBassDb = 0.0

    /** Name of the impulse response being convolved ("" for none). */
    @Volatile var convolution = ""

    /** The EQ runs as a linear-phase FIR. */
    @Volatile var linearPhase = false

    /** Compressor strength in use (0: off). */
    @Volatile var compressor = 0

    /** Surround folded to stereo (Downmix). */
    @Volatile var downmixed = false

    /** What the AudioTrack gets: float, or 16-bit while the speed is changed. */
    @Volatile var outputEncoding = androidx.media3.common.C.ENCODING_PCM_FLOAT

    fun toMap(): Map<String, Any?> = mapOf(
        "bits" to when (pcmEncoding) {
            androidx.media3.common.C.ENCODING_PCM_8BIT -> 8
            androidx.media3.common.C.ENCODING_PCM_16BIT -> 16
            androidx.media3.common.C.ENCODING_PCM_24BIT -> 24
            androidx.media3.common.C.ENCODING_PCM_32BIT -> 32
            androidx.media3.common.C.ENCODING_PCM_FLOAT -> 32
            else -> null
        },
        "float" to (pcmEncoding == androidx.media3.common.C.ENCODING_PCM_FLOAT),
        "sampleRate" to sampleRate,
        "channels" to channels,
        "processing" to processing,
        "gainDb" to gainDb,
        "crossfade" to Crossfade.seconds,
        "bitPerfect" to bitPerfect,
        "resampledTo" to resampledTo,
        "outputRate" to outputRate,
        "peakDb" to peakDb,
        "limitedFraction" to limitedFraction,
        "clippedFrames" to clippedFrames,
        "levelFrames" to levelFrames,
        "loudnessBassDb" to loudnessBassDb,
        "convolution" to convolution,
        "linearPhase" to linearPhase,
        "compressor" to compressor,
        "downmixed" to downmixed,
        "output16" to (outputEncoding == androidx.media3.common.C.ENCODING_PCM_16BIT),
        "bitPerfectReason" to BitPerfect.reason,
        "bitPerfectSupported" to BitPerfect.supported,
    )
}

/** Levels after the EQ for one song, published to [SignalPath] as they add up. */
class SongLevels {
    private var peak = 0.0
    private var limited = 0L
    private var clipped = 0L
    private var frames = 0L

    fun reset() {
        peak = 0.0
        limited = 0
        clipped = 0
        frames = 0
        SignalPath.levelFrames = 0
    }

    fun add(s: LevelStats) {
        if (s.peak > peak) peak = s.peak
        limited += s.limited
        clipped += s.clipped
        frames += s.frames
        SignalPath.peakDb = if (peak > 0) 20 * kotlin.math.log10(peak) else -100.0
        SignalPath.limitedFraction = if (frames > 0) limited.toDouble() / frames else 0.0
        SignalPath.clippedFrames = clipped
        SignalPath.levelFrames = frames
    }
}
