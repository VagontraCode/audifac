package com.gtongfa.audifac.dsp

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit

/**
 * Finds a file's loudness for volume matching: its ReplayGain / R128 tags if
 * it has them (instant), else an EBU R128 measurement of the decoded audio.
 *
 * `location` is an absolute path or a content:// URI.
 */
class LoudnessScanner(private val context: Context) {

    fun analyse(location: String): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["location"] = location
        val tags = try {
            readTags(location)
        } catch (e: Exception) {
            null
        }
        // Decoded even when tagged: dynamic range and spectrum need the audio.
        val measured = try {
            measure(location)
        } catch (e: Exception) {
            Log.w(TAG, "loudness scan failed for $location: $e")
            null
        }
        measured?.let { m ->
            m.dr?.let { out["dr"] = it }
            m.cutoff?.let { (hz, wall) ->
                out["cutoffHz"] = hz
                out["brickwall"] = wall
            }
            out["sampleRate"] = m.sampleRate
        }
        if (tags != null) {
            out.putAll(tags.toMap())
            out["source"] = "tags"
            out["ok"] = true
            return out
        }
        // Real music measures between about -70 and 0 LUFS, with a finite peak.
        if (measured != null && !(measured.lufs in -70.0..0.5 && measured.peak.isFinite())) {
            Log.w(TAG, "implausible loudness ${measured.lufs} LUFS / peak ${measured.peak} for $location: ignored")
            out["ok"] = false
            return out
        }
        if (measured != null) {
            out["lufs"] = measured.lufs
            out["trackGainDb"] = LoudnessMeter.REFERENCE_LUFS - measured.lufs
            out["trackPeak"] = measured.peak
            out["source"] = "scan"
        }
        out["ok"] = measured != null
        return out
    }

    /** What decoding a file measured. */
    private class Measurement(
        val lufs: Double,
        val peak: Double,
        val dr: Int?,
        val cutoff: Pair<Int, Boolean>?,
        val sampleRate: Int,
    )

    private fun uriOf(location: String): Uri =
        if (location.startsWith("content://")) Uri.parse(location) else Uri.fromFile(File(location))

    @OptIn(UnstableApi::class)
    private fun readTags(location: String): Gains? {
        MetadataRetriever.Builder(context, MediaItem.fromUri(uriOf(location))).build().use { retriever ->
            val groups = retriever.retrieveTrackGroups().get(15, TimeUnit.SECONDS)
            for (g in 0 until groups.length) {
                val group = groups[g]
                for (t in 0 until group.length) {
                    val format = group.getFormat(t)
                    if (format.sampleMimeType?.startsWith("audio/") != true) continue
                    ReplayGain.fromMetadata(format.metadata)?.let { return it }
                }
            }
        }
        return null
    }

    /** Loudness, peak, dynamics and spectrum of the first audio track, or null if it can't be decoded / is silent. */
    private fun measure(location: String): Measurement? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (location.startsWith("content://")) extractor.setDataSource(context, Uri.parse(location), null)
            else extractor.setDataSource(location)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            // No float request: 16-bit is plenty for loudness, and Samsung's
            // decoders write 16-bit while reporting float when asked for it
            // (which measured garbage).
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }

            val info = MediaCodec.BufferInfo()
            var meter: LoudnessMeter? = null
            var dynamics: DynamicsMeter? = null
            var rate = 0
            var channels = 0
            var float = false
            var samples = FloatArray(0)
            var shorts = ShortArray(0)
            var inputDone = false

            fun startMeter(f: MediaFormat) {
                channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                    f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                // (A mid-stream change restarts the measurement — rare and harmless.)
                rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                meter = LoudnessMeter(rate, channels)
                dynamics = DynamicsMeter(rate, channels)
            }

            /** Takes one output buffer; true at end of stream. */
            fun drain(index: Int): Boolean {
                if (meter == null) startMeter(codec.outputFormat)
                val buffer = codec.getOutputBuffer(index)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                buffer.order(ByteOrder.nativeOrder())
                val count = if (float) info.size / 4 else info.size / 2
                if (samples.size < count) {
                    samples = FloatArray(count)
                    shorts = ShortArray(count)
                }
                if (float) {
                    buffer.asFloatBuffer().get(samples, 0, count)
                } else {
                    buffer.asShortBuffer().get(shorts, 0, count)
                    for (i in 0 until count) samples[i] = shorts[i] / 32768f
                }
                meter!!.add(samples, count / channels)
                dynamics!!.add(samples, count / channels)
                codec.releaseOutputBuffer(index, false)
                return info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            }

            // Keep every input slot full and take every ready output; only
            // wait when the codec has nothing for us (a lock-step loop with
            // timeouts spends most of its time waiting).
            var ended = false
            while (!ended) {
                var progressed = false
                while (!inputDone) {
                    val index = codec.dequeueInputBuffer(0)
                    if (index < 0) break
                    val buffer = codec.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                    progressed = true
                }
                while (!ended) {
                    val index = codec.dequeueOutputBuffer(info, if (progressed) 0 else TIMEOUT_US)
                    when {
                        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> startMeter(codec.outputFormat)
                        index >= 0 -> ended = drain(index)
                        else -> break // Nothing ready.
                    }
                    progressed = true
                }
            }

            val m = meter ?: return null
            val lufs = m.integratedLufs() ?: return null
            return Measurement(lufs, m.peak, dynamics?.dr(), dynamics?.cutoff(), rate)
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }

    companion object {
        private const val TAG = "AudifacLoudness"
        private const val TIMEOUT_US = 10_000L
    }
}
