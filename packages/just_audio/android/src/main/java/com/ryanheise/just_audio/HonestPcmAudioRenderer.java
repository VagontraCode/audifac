package com.ryanheise.just_audio;

import android.content.Context;
import android.media.MediaCrypto;
import android.media.MediaFormat;
import android.os.Build;
import android.os.Handler;
import androidx.annotation.Nullable;
import androidx.media3.common.Format;
import androidx.media3.exoplayer.audio.AudioRendererEventListener;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer;
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;

/**
 * audifac patch: a MediaCodecAudioRenderer that doesn't ask Samsung's audio
 * decoders for float output.
 *
 * Samsung's decoders (e.g. c2.sec.flac.decoder on a Galaxy S24, Android 17)
 * reject media3 1.9's codec configuration but the framework still reports
 * the float output that was asked for — while the decoder writes 16-bit PCM.
 * Read as float, that is loud noise. Without the request they report (and
 * write) their native 16-bit PCM.
 */
final class HonestPcmAudioRenderer extends MediaCodecAudioRenderer {
    HonestPcmAudioRenderer(
            Context context,
            MediaCodecAdapter.Factory codecAdapterFactory,
            MediaCodecSelector mediaCodecSelector,
            boolean enableDecoderFallback,
            @Nullable Handler eventHandler,
            @Nullable AudioRendererEventListener eventListener,
            AudioSink audioSink) {
        super(context, codecAdapterFactory, mediaCodecSelector, enableDecoderFallback, eventHandler, eventListener, audioSink);
    }

    /**
     * Decoders whose float output can't be trusted: Samsung's, and any the
     * app caught mislabelling 16-bit PCM as float (JustAudioHooks).
     */
    static boolean distrustsFloat(String codecName) {
        String name = codecName.toLowerCase(java.util.Locale.ROOT);
        return name.startsWith("c2.sec.") || name.startsWith("omx.sec.")
            || JustAudioHooks.untrustedFloatDecoders.contains(codecName);
    }

    @Override
    protected MediaCodecAdapter.Configuration getMediaCodecConfiguration(
            MediaCodecInfo codecInfo, Format format, @Nullable MediaCrypto crypto, float codecOperatingRate) {
        MediaCodecAdapter.Configuration configuration =
            super.getMediaCodecConfiguration(codecInfo, format, crypto, codecOperatingRate);
        JustAudioHooks.currentAudioDecoder = codecInfo.name;
        MediaFormat mediaFormat = configuration.mediaFormat;
        if (distrustsFloat(codecInfo.name) && mediaFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
            if (Build.VERSION.SDK_INT >= 29) {
                mediaFormat.removeKey(MediaFormat.KEY_PCM_ENCODING);
            } else {
                mediaFormat.setInteger(MediaFormat.KEY_PCM_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT);
            }
            android.util.Log.i("AudifacDsp", codecInfo.name + ": native PCM output (its float output is unreliable)");
        }
        return configuration;
    }
}
