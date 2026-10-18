package com.gtongfa.audifac.dsp

import android.content.Context
import android.util.Log
import com.ryanheise.just_audio.JustAudioHooks

/**
 * Remembers phone decoders caught reporting float PCM while writing 16-bit
 * (Samsung's do; others may). The renderer stops asking them for float, so
 * from their next track on they report what they really write.
 */
object DecoderQuirks {
    private const val PREFS = "decoder_quirks"
    private const val KEY = "untrusted_float"

    @Volatile
    var context: Context? = null

    fun load(ctx: Context) {
        context = ctx
        val saved = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY, emptySet()).orEmpty()
        JustAudioHooks.untrustedFloatDecoders.addAll(saved)
    }

    /** The current decoder's "float" was 16-bit PCM. */
    fun reportMislabelledFloat() {
        val name = JustAudioHooks.currentAudioDecoder ?: return
        if (!JustAudioHooks.untrustedFloatDecoders.add(name)) return
        Log.w("AudifacDsp", "$name writes 16-bit PCM labelled as float: no more float requests to it")
        val ctx = context ?: return
        try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putStringSet(KEY, HashSet(JustAudioHooks.untrustedFloatDecoders)).apply()
        } catch (_: Exception) {
        }
    }
}
