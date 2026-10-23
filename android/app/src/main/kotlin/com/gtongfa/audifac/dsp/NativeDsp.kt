package com.gtongfa.audifac.dsp

import android.util.Log

/** The DSP's hot loops in C++ / NEON (cpp/dsp.cpp); absent in JVM tests. */
internal object NativeDsp {
    val loaded: Boolean = try {
        System.loadLibrary("audifac_dsp")
        true
    } catch (t: Throwable) {
        false
    }

    /** Polyphase filter for stereo (see Resampler.produce); returns the frames written to [out]. */
    @JvmStatic
    external fun produceStereo(
        tableRev: FloatArray, taps: Int, up: Int, down: Int, delay: Long,
        left: FloatArray, right: FloatArray, histStart: Long, lastIn: Long, outCount: Long, max: Int,
        out: FloatArray,
    ): Int

    fun info(message: String) {
        try {
            Log.i("AudifacDsp", message)
        } catch (_: Throwable) {
        }
    }

    fun warn(message: String) {
        try {
            Log.w("AudifacDsp", message)
        } catch (_: Throwable) {
        }
    }
}
