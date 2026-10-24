package com.gtongfa.audifac.dsp

import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.util.UnstableApi
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.log10
import kotlin.math.min
import kotlin.math.pow

/** Volume matching (ReplayGain) settings, chosen in the app. */
data class VolumeMatching(
    val mode: Mode = Mode.OFF,
    /** Added to every gain (ReplayGain's "pre-amp"). */
    val preampDb: Double = 0.0,
    /** Never raise a track past its peak (no clipping, no limiter needed). */
    val preventClipping: Boolean = true,
    /** Gain for files with neither tags nor a scan. */
    val untaggedGainDb: Double = 0.0,
) {
    enum class Mode { OFF, TRACK, ALBUM }

    /**
     * Linear gain for a file with [gains] (null = nothing known). Album mode
     * falls back to the track gain and vice versa.
     */
    fun linearGain(gains: Gains?): Double {
        val mode = gains?.mode ?: mode
        if (mode == Mode.OFF) return 1.0
        val album = mode == Mode.ALBUM
        val gainDb = if (album) gains?.albumGainDb ?: gains?.trackGainDb else gains?.trackGainDb ?: gains?.albumGainDb
        val peak = if (album) gains?.albumPeak ?: gains?.trackPeak else gains?.trackPeak ?: gains?.albumPeak
        var db = (gainDb ?: untaggedGainDb) + preampDb
        if (preventClipping && gainDb != null && peak != null && peak > 0) db = min(db, -20 * log10(peak))
        return 10.0.pow(db / 20)
    }

    companion object {
        fun fromMap(m: Map<*, *>): VolumeMatching = VolumeMatching(
            mode = Mode.entries.firstOrNull { it.name.equals(m["mode"] as? String, ignoreCase = true) } ?: Mode.OFF,
            preampDb = ((m["preampDb"] as? Number)?.toDouble() ?: 0.0).coerceIn(-15.0, 15.0),
            preventClipping = m["preventClipping"] as? Boolean ?: true,
            untaggedGainDb = ((m["untaggedGainDb"] as? Number)?.toDouble() ?: 0.0).coerceIn(-15.0, 15.0),
        )
    }
}

/** Process-wide volume matching state, read by every DSP sink. */
@OptIn(UnstableApi::class)
object Loudness {
    @Volatile
    var settings = VolumeMatching()
        private set

    /** Gains the app measured or read, by [SourceUri] key. */
    private val known = ConcurrentHashMap<String, Gains>()

    /** Incremented on every change so sinks recompute the current track's gain. */
    @Volatile
    var version: Long = 0
        private set

    /**
     * Incremented when the user changes the settings (mode, pre-amp…): those
     * apply at once. New measurements only bump [version]: a sink doesn't
     * change the level of a song already playing for them.
     */
    @Volatile
    var settingsVersion: Long = 0
        private set

    fun update(newSettings: VolumeMatching) {
        if (newSettings == settings) return
        settings = newSettings
        settingsVersion++
        version++
    }

    fun putGains(entries: Map<String, Gains>, replace: Boolean) {
        // A remembered mode that changes for a file applies at once, like a setting.
        val modeChanged = entries.any { (key, gains) -> known[key]?.mode != gains.mode } ||
            (replace && known.any { (key, gains) -> gains.mode != null && key !in entries })
        if (replace) known.keys.retainAll(entries.keys)
        known.putAll(entries)
        if (modeChanged) settingsVersion++
        version++
    }

    /**
     * Tags in the stream first (exact for this file), completed by what the
     * app knows (scans, album gains it combined from scanned tracks).
     */
    fun gainsFor(format: Format): Gains? {
        val tags = ReplayGain.fromMetadata(format.metadata)
        val app = SourceUri.of(format)?.let { known[it] } ?: return tags
        if (tags == null) return app
        return Gains(
            trackGainDb = tags.trackGainDb ?: app.trackGainDb,
            trackPeak = tags.trackPeak ?: app.trackPeak,
            albumGainDb = tags.albumGainDb ?: app.albumGainDb,
            albumPeak = tags.albumPeak ?: app.albumPeak,
            mode = app.mode,
        )
    }
}
