package com.ryanheise.just_audio;

import android.content.Context;
import androidx.media3.exoplayer.audio.AudioSink;

/**
 * audifac patch: lets the host app wrap the player's audio sink, e.g. to run
 * its own DSP on full-resolution PCM before it reaches the AudioTrack.
 *
 * Set {@link #audioSinkDecorator} before the first player is created
 * (Application.onCreate).
 */
public final class JustAudioHooks {
    private JustAudioHooks() {}

    public interface AudioSinkDecorator {
        /** Returns the sink the player should use, usually wrapping {@code sink}. */
        AudioSink decorate(Context context, AudioSink sink);

        /** Whether the wrapped sink should accept 32-bit float PCM. */
        default boolean enableFloatOutput() {
            return true;
        }
    }

    public static volatile AudioSinkDecorator audioSinkDecorator;
}
