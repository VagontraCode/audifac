package com.gtongfa.audifac.dsp

/**
 * The final processing settings, already combined by the app from the
 * device-correction layer and the sound-preset layer.
 */
data class DspConfig(
    val enabled: Boolean = false,
    val preampDb: Double = 0.0,
    val bands: List<Band> = emptyList(),
    /** -1 = full left … 0 = centre … 1 = full right. */
    val balance: Double = 0.0,
    val mono: Boolean = false,
    /** 0 = off … 1 = strongest headphone crossfeed. */
    val crossfeed: Double = 0.0,
    val limiter: Boolean = true,
    /** Loudness compensation (bass / treble that follow the volume, see LoudnessCompensation). */
    val loudness: Boolean = false,
    /** Stereo width: 0 = mono, 1 = as recorded, 2 = twice the side signal. */
    val width: Double = 1.0,
    /** Channel delay in ms: positive delays the right channel, negative the left. */
    val delayMs: Double = 0.0,
    val invertLeft: Boolean = false,
    val invertRight: Boolean = false,
    /** Impulse response to convolve with (room / headphone correction), null for none. */
    val ir: ImpulseResponse? = null,
    /** Render the EQ bands as one linear-phase FIR (LinearPhaseEq) instead of biquads. */
    val linearPhase: Boolean = false,
) {
    /** True when processing would not change the signal at all. */
    val isTransparent: Boolean
        get() = !enabled || (
            preampDb == 0.0 && balance == 0.0 && !mono && crossfeed == 0.0 && width == 1.0 &&
                delayMs == 0.0 && !invertLeft && !invertRight && ir == null &&
                bands.all { it.gainDb == 0.0 && (it.type == FilterType.PEAKING || it.type == FilterType.LOW_SHELF || it.type == FilterType.HIGH_SHELF) }
            )

    companion object {
        val OFF = DspConfig()

        /** Longest channel delay (ms). */
        const val MAX_DELAY_MS = 20.0

        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): DspConfig {
            fun num(key: String, m: Map<String, Any?> = map) = (m[key] as? Number)?.toDouble() ?: 0.0
            val bands = (map["bands"] as? List<Map<String, Any?>>).orEmpty().mapNotNull { b ->
                val type = FilterType.entries.firstOrNull { it.name == b["type"] } ?: return@mapNotNull null
                Band(type, num("frequency", b), num("gainDb", b), (b["q"] as? Number)?.toDouble() ?: 0.707)
            }
            return DspConfig(
                enabled = map["enabled"] as? Boolean ?: false,
                preampDb = num("preampDb"),
                bands = bands,
                balance = num("balance").coerceIn(-1.0, 1.0),
                mono = map["mono"] as? Boolean ?: false,
                crossfeed = num("crossfeed").coerceIn(0.0, 1.0),
                limiter = map["limiter"] as? Boolean ?: true,
                loudness = map["loudness"] as? Boolean ?: false,
                width = ((map["width"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 2.0),
                delayMs = num("delayMs").coerceIn(-MAX_DELAY_MS, MAX_DELAY_MS),
                invertLeft = map["invertLeft"] as? Boolean ?: false,
                invertRight = map["invertRight"] as? Boolean ?: false,
                ir = (map["irPath"] as? String)?.let { ImpulseResponse.load(it) },
                linearPhase = map["linearPhase"] as? Boolean ?: false,
            )
        }
    }
}

/** Process-wide settings shared by every player's sink. */
object DspEngine {
    /** The settings as the app sent them. */
    @Volatile
    var base: DspConfig = DspConfig.OFF
        private set

    /** What the processors use: [base] plus loudness compensation for the current volume. */
    @Volatile
    var config: DspConfig = DspConfig.OFF
        private set

    /** A/B comparison: temporarily hear the unprocessed signal. */
    @Volatile
    var bypass: Boolean = false

    /** Incremented on every change so processors know to rebuild. */
    @Volatile
    var version: Long = 0
        private set

    /** How far the media volume is below full, in dB (positive). */
    @Volatile
    var attenuationDb: Double = 0.0
        private set

    @Synchronized
    fun update(newConfig: DspConfig) {
        base = newConfig
        rebuild()
    }

    /** The media volume changed (loudness compensation follows it). */
    @Synchronized
    fun setAttenuation(db: Double) {
        val clamped = db.coerceIn(0.0, 100.0)
        if (kotlin.math.abs(clamped - attenuationDb) < 0.5) return
        attenuationDb = clamped
        if (base.loudness) rebuild()
    }

    private fun rebuild() {
        config = LoudnessCompensation.apply(base, attenuationDb)
        SignalPath.loudnessBassDb = if (base.loudness && base.enabled) LoudnessCompensation.bassDb(attenuationDb) else 0.0
        SignalPath.convolution = if (base.enabled) base.ir?.name ?: "" else ""
        SignalPath.linearPhase = base.enabled && base.linearPhase
        version++
    }
}

/**
 * Loudness compensation: the ear loses bass (and some treble) faster than
 * mids as the level drops (ISO 226 equal-loudness contours), so music played
 * quietly sounds thin. Shelves follow the volume: nothing near full volume,
 * up to +12 dB of bass / +4 dB of treble when very quiet. The pre-amp drops by
 * the larger boost, so it never clips.
 */
object LoudnessCompensation {
    /** Attenuation (dB below full volume) where compensation starts. */
    const val REFERENCE_DB = 10.0

    fun bassDb(attenuationDb: Double) = ((attenuationDb - REFERENCE_DB) * 0.35).coerceIn(0.0, 12.0)
    fun trebleDb(attenuationDb: Double) = ((attenuationDb - REFERENCE_DB) * 0.12).coerceIn(0.0, 4.0)

    fun apply(config: DspConfig, attenuationDb: Double): DspConfig {
        if (!config.loudness || !config.enabled) return config
        val bass = bassDb(attenuationDb)
        val treble = trebleDb(attenuationDb)
        if (bass == 0.0 && treble == 0.0) return config
        return config.copy(
            preampDb = config.preampDb - maxOf(bass, treble),
            bands = config.bands + listOf(
                Band(FilterType.LOW_SHELF, 100.0, bass, 0.7),
                Band(FilterType.HIGH_SHELF, 9000.0, treble, 0.7),
            ),
        )
    }
}
