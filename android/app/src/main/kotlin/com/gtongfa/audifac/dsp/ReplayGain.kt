package com.gtongfa.audifac.dsp

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.Metadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.flac.VorbisComment
import androidx.media3.extractor.metadata.id3.InternalFrame
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.mp3.Mp3InfoReplayGain

/**
 * Loudness gains of one file, in ReplayGain 2.0 terms: dB to reach −18 LUFS,
 * peaks as linear sample peaks (1.0 = full scale). Any value may be missing.
 */
data class Gains(
    val trackGainDb: Double? = null,
    val trackPeak: Double? = null,
    val albumGainDb: Double? = null,
    val albumPeak: Double? = null,
    /** Volume matching mode for this file (remembered for its album / artist), null = the app's. */
    val mode: VolumeMatching.Mode? = null,
) {
    val isEmpty: Boolean get() = trackGainDb == null && albumGainDb == null

    fun toMap(): Map<String, Any?> = mapOf(
        "trackGainDb" to trackGainDb,
        "trackPeak" to trackPeak,
        "albumGainDb" to albumGainDb,
        "albumPeak" to albumPeak,
    )

    companion object {
        fun fromMap(m: Map<*, *>): Gains = Gains(
            (m["trackGainDb"] as? Number)?.toDouble(),
            (m["trackPeak"] as? Number)?.toDouble(),
            (m["albumGainDb"] as? Number)?.toDouble(),
            (m["albumPeak"] as? Number)?.toDouble(),
            VolumeMatching.Mode.entries.firstOrNull { it.name.equals(m["mode"] as? String, ignoreCase = true) },
        )
    }
}

/**
 * Marks a track's Format with the file it came from (added by the extractor
 * wrapper), so the DSP sink knows which song's gain applies — exactly at the
 * track's first sample, gapless transitions included.
 */
class SourceUri(val key: String) : Metadata.Entry {
    override fun toString() = "SourceUri($key)"
    override fun equals(other: Any?) = other is SourceUri && other.key == key
    override fun hashCode() = key.hashCode()

    companion object {
        /** Same key on both sides of the channel: the decoded URI string. */
        fun keyOf(uri: Uri): String = Uri.decode(uri.toString())

        @OptIn(UnstableApi::class)
        fun of(format: Format): String? {
            val m = format.metadata ?: return null
            for (i in 0 until m.length()) (m[i] as? SourceUri)?.let { return it.key }
            return null
        }
    }
}

/** Reads ReplayGain / R128 tags from the metadata ExoPlayer's extractors expose. */
@OptIn(UnstableApi::class)
object ReplayGain {
    fun fromMetadata(metadata: Metadata?): Gains? {
        if (metadata == null) return null
        var tg: Double? = null
        var tp: Double? = null
        var ag: Double? = null
        var ap: Double? = null
        var lameTrack: Double? = null
        var lameAlbum: Double? = null
        var lamePeak: Double? = null

        fun put(key: String, value: String) {
            when (key.lowercase()) {
                "replaygain_track_gain" -> tg = parseDb(value) ?: tg
                "replaygain_track_peak" -> tp = parseNumber(value) ?: tp
                "replaygain_album_gain" -> ag = parseDb(value) ?: ag
                "replaygain_album_peak" -> ap = parseNumber(value) ?: ap
                // Opus: Q7.8 dB relative to −23 LUFS → +5 dB for the −18 LUFS reference.
                "r128_track_gain" -> value.trim().toIntOrNull()?.let { tg = tg ?: (it / 256.0 + 5.0) }
                "r128_album_gain" -> value.trim().toIntOrNull()?.let { ag = ag ?: (it / 256.0 + 5.0) }
            }
        }

        for (i in 0 until metadata.length()) {
            when (val e = metadata[i]) {
                is TextInformationFrame ->
                    if (e.id == "TXXX" && e.description != null) put(e.description!!, e.values.firstOrNull() ?: e.value)
                is VorbisComment -> put(e.key, e.value)
                is InternalFrame ->
                    if (e.domain == "com.apple.iTunes") put(e.description, e.text)
                is Mp3InfoReplayGain -> {
                    // LAME header: field "radio" = track, "audiophile" = album.
                    for (f in listOfNotNull(e.field1, e.field2)) {
                        if (f.originator == Mp3InfoReplayGain.GainField.ORIGINATOR_UNSET) continue
                        when (f.name) {
                            Mp3InfoReplayGain.GainField.NAME_RADIO -> lameTrack = f.gain.toDouble()
                            Mp3InfoReplayGain.GainField.NAME_AUDIOPHILE -> lameAlbum = f.gain.toDouble()
                        }
                    }
                    if (e.peak > 0f) lamePeak = e.peak.toDouble()
                }
            }
        }
        // Text tags win over the LAME header (they are what taggers update).
        val gains = Gains(
            trackGainDb = tg ?: lameTrack,
            trackPeak = tp ?: lamePeak,
            albumGainDb = ag ?: lameAlbum,
            albumPeak = ap ?: lamePeak.takeIf { ag == null && lameAlbum != null },
        )
        return gains.takeUnless { it.isEmpty }
    }

    /** "-6.20 dB", "+1,5 dB", "-6.2" → dB. */
    fun parseDb(value: String): Double? =
        parseNumber(value.replace("dB", "", ignoreCase = true))?.takeIf { it in -60.0..60.0 }

    fun parseNumber(value: String): Double? =
        value.trim().replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() }
}
