package com.gtongfa.audifac

import android.app.Application
import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
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
        JustAudioHooks.audioSinkDecorator = object : JustAudioHooks.AudioSinkDecorator {
            override fun decorate(context: Context, sink: AudioSink): AudioSink = DspAudioSink(sink)
        }
    }
}
