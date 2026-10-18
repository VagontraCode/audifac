package com.ryanheise.just_audio;

import android.content.Context;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.extractor.ExtractorsFactory;

/**
 * audifac patch: lets the host app customise the player without forking
 * more of just_audio. Set the fields before the first player is created
 * (Application.onCreate).
 */
public final class JustAudioHooks {
    private JustAudioHooks() {}

    /** Wraps the player's audio sink, e.g. to run DSP on full-resolution PCM. */
    public interface AudioSinkDecorator {
        /** Returns the sink the player should use, usually wrapping {@code sink}. */
        AudioSink decorate(Context context, AudioSink sink);

        /** Whether the wrapped sink should accept 32-bit float PCM. */
        default boolean enableFloatOutput() {
            return true;
        }
    }

    /** Adds container parsers (extractors) on top of ExoPlayer's defaults. */
    public interface ExtractorsDecorator {
        ExtractorsFactory decorate(ExtractorsFactory defaults);
    }

    public static volatile AudioSinkDecorator audioSinkDecorator;
    public static volatile ExtractorsDecorator extractorsDecorator;

    /**
     * {@link DefaultRenderersFactory#EXTENSION_RENDERER_MODE_OFF} / _ON / _PREFER:
     * whether decoder extensions on the classpath (e.g. FFmpeg) are used.
     */
    public static volatile int extensionRendererMode = DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF;
}
