package com.gtongfa.audifac.dsp

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import java.io.File
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
        var meter: LoudnessMeter? = null
        var dynamics: DynamicsMeter? = null
        var sampleRate = 0
        val decoded = PcmDecoder.decode(context, location, object : PcmDecoder.Sink {
            override fun format(rate: Int, channels: Int) {
                // (A mid-stream change restarts the measurement — rare and harmless.)
                meter = LoudnessMeter(rate, channels)
                dynamics = DynamicsMeter(rate, channels)
                sampleRate = rate
            }

            override fun samples(samples: FloatArray, frames: Int) {
                meter!!.add(samples, frames)
                dynamics!!.add(samples, frames)
            }
        })
        if (!decoded) return null
        val m = meter ?: return null
        val lufs = m.integratedLufs() ?: return null
        return Measurement(lufs, m.peak, dynamics?.dr(), dynamics?.cutoff(), sampleRate)
    }

    companion object {
        private const val TAG = "AudifacLoudness"
    }
}
