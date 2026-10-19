package com.gtongfa.audifac

import android.app.Application
import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import android.net.Uri
import android.util.Log
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import com.gtongfa.audifac.extract.AiffExtractor
import com.gtongfa.audifac.extract.DsdExtractor
import com.gtongfa.audifac.extract.FfmpegExtractor
import com.gtongfa.audifac.extract.SourceTaggingExtractor
import com.gtongfa.audifac.dsp.SourceUri
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import com.gtongfa.audifac.dsp.DspAudioSink
import com.ryanheise.just_audio.JustAudioHooks

/**
 * Installs the DSP sink before any player exists (audio_service may start the
 * Flutter engine — and playback — before MainActivity is configured).
 */
class AudifacApplication : Application() {
    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        com.gtongfa.audifac.dsp.BitPerfect.context = applicationContext
        com.gtongfa.audifac.dsp.DecoderQuirks.load(applicationContext)
        JustAudioHooks.audioSinkDecorator = object : JustAudioHooks.AudioSinkDecorator {
            override fun decorate(context: Context, sink: AudioSink): AudioSink = DspAudioSink(sink)
        }
        // FFmpeg decoders (AC-3, E-AC-3, DTS, TrueHD, MP2, ALAC on any phone…)
        // as a fallback after the phone's own decoders.
        JustAudioHooks.extensionRendererMode = DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
        // Our own container parsers, tried after ExoPlayer's: AIFF and DSD.
        // Every track is also tagged with its file, for per-song volume matching.
        JustAudioHooks.extractorsDecorator = JustAudioHooks.ExtractorsDecorator { defaults ->
            object : ExtractorsFactory {
                override fun createExtractors(): Array<Extractor> = defaults.createExtractors() + extra()

                override fun createExtractors(uri: Uri, responseHeaders: Map<String, List<String>>): Array<Extractor> {
                    val key = SourceUri.keyOf(uri)
                    // FFmpeg (WMA / APE / WavPack / TTA) first: it only claims
                    // those exact signatures, which ExoPlayer's parsers don't know.
                    val ffmpeg = FfmpegExtractor(applicationContext, uri)
                    return (arrayOf<Extractor>(ffmpeg) + defaults.createExtractors(uri, responseHeaders) + extra())
                        .map { SourceTaggingExtractor(it, key) }
                        .toTypedArray()
                }

                private fun extra(): Array<Extractor> = arrayOf(AiffExtractor(), DsdExtractor())
            }
        }
        Log.i("AudifacDsp", "FFmpeg decoders: available=${FfmpegLibrary.isAvailable()} version=${FfmpegLibrary.getVersion()}")
    }
}
