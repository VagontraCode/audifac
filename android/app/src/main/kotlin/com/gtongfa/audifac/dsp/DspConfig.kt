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
) {
    /** True when processing would not change the signal at all. */
    val isTransparent: Boolean
        get() = !enabled || (
            preampDb == 0.0 && balance == 0.0 && !mono && crossfeed == 0.0 &&
                bands.all { it.gainDb == 0.0 && (it.type == FilterType.PEAKING || it.type == FilterType.LOW_SHELF || it.type == FilterType.HIGH_SHELF) }
            )

    companion object {
        val OFF = DspConfig()

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
            )
        }
    }
}

/** Process-wide settings shared by every player's sink. */
object DspEngine {
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

    fun update(newConfig: DspConfig) {
        config = newConfig
        version++
    }
}
