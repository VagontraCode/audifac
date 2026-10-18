# audifac

[![CI](https://github.com/VagontraCode/audifac/actions/workflows/ci.yml/badge.svg)](https://github.com/VagontraCode/audifac/actions/workflows/ci.yml)

A local music player for Android, built with Flutter, for people who care how their music sounds. It finds every audio file on the phone, shows which ones are lossless, and has a parametric equalizer that works on full-resolution audio.

| | |
|---|---|
| **App ID** | `com.gtongfa.audifac` |
| **Version** | 0.1.0 |
| **Platforms** | Android 7.0+ (iOS builds compile but have no music library yet) |
| **Formats** | MP3, AAC / M4A / M4B, ALAC, FLAC, WAV, Ogg Vorbis, Opus, AMR, 3GP, MKA, WebM audio |

## Features

**Library**
- Scans the **whole phone and SD card**, not only the Music folder. Files that Android's media index missed are found and indexed automatically.
- Hidden (`.nomedia`) folders, such as WhatsApp voice notes, can be added once through the system folder picker.
- Songs, albums, artists and playlists, with instant search.
- Filters to hide ringtones, short clips and voice recordings, and to exclude folders.

**Audio quality**
- Reads the real codec from the audio stream, not the file extension (so ALAC and AAC inside `.m4a` are told apart). Shows sample rate, bit depth and bitrate.
- Labels like `FLAC 24/96` (Hi-Res), `FLAC 16/44.1` (lossless) and `MP3 320` (lossy) on every song.
- Filter by quality (Hi-Res / Lossless / Lossy), by codec or by source (Downloads, WhatsApp, Music…).
- A song info sheet with every tag and technical detail.

**Equalizer / DSP**
- Up to 20 parametric bands (peak, low/high shelf, low/high-pass, notch), plus preamp, crossfeed, balance, mono and a limiter.
- Processes 16/24/32-bit and float audio in double precision. When the EQ is off or flat, the audio passes through bit-exact.
- **Two layers:**
  - a **device correction** chosen automatically per output (phone speaker, wired headphones, each Bluetooth or USB device);
  - a **sound preset** on top.
- 16 built-in presets. Your own presets can be a 10-band graphic EQ or fully parametric, and can be imported from or exported to **AutoEQ** / Equalizer APO.
- Rules: a song, album, artist, genre or source can each have its own preset. When you start listening and no rule applies, a quick picker offers your presets.
- A live frequency-response curve with draggable points, and A/B comparison with the original.

**Playback**
- Background playback with notification, lock-screen and headset/Bluetooth controls, and gapless playback.
- A queue you can reorder, plus "Play next" and "Add to queue" that also work while shuffling.
- Remembers your queue and position between launches.
- Favorites, playlists, recently played and recently added.

**Design**
- Light and dark themes, with player colors taken from the album art.
- Smooth animations: a mini player that expands into the full player, and a player you can drag down to close.

## Build

Requirements: Flutter 3.47 (stable), JDK 17+, and the Android SDK with API 36.

```sh
flutter pub get
flutter run                      # debug build on a connected device
flutter test                     # Dart tests
cd android && ./gradlew :app:testDebugUnitTest   # DSP tests (JVM)
flutter build apk --release --split-per-abi      # release APKs
```

Release builds are signed with the key described in `android/key.properties`, a file that is never committed. Without it, release builds fall back to the debug key.

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull request:

1. Analyze, then run the Dart tests.
2. Summarize the commits and files changed since the last release.
3. Build signed Android APKs (one per CPU architecture) and an App Bundle, and run the DSP tests.
4. Build iOS, packaged as an unsigned IPA.

All build files can be downloaded from the run's page. Pushing a tag such as `v0.1.0` also publishes a **GitHub Release** with every file and the release notes.

Signing secrets used by the workflow: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.

## Project layout

```
lib/
  core/        theme, audio handler (just_audio + audio_service), queue logic
  data/        MediaStore / storage scanner channel, SQLite database, DSP channel
  models/      songs, albums, audio info, EQ presets & rules, settings
  providers/   Riverpod state
  features/    home, library, player, equalizer, search, favorites, settings…
  widgets/     shared UI (artwork, song tile, mini player, EQ curve…)
android/app/src/main/kotlin/com/gtongfa/audifac/
  MediaLibraryChannel.kt   library, storage scan, folder picker, artwork
  AudioInspector.kt        codec / sample rate / bit depth detection
  dsp/                     equalizer, crossfeed, limiter, audio sink
packages/just_audio/       just_audio 0.10.6 with a small patch (audio-sink hook for the DSP)
```

`PLAN.md` has the full roadmap, design decisions and the device test checklist.

## Credits

- [just_audio](https://github.com/ryanheise/just_audio) (MIT). A patched copy lives in `packages/just_audio`.
- [audio_service](https://github.com/ryanheise/audio_service).
- [AutoEQ](https://github.com/jaakkopasanen/AutoEq), for the headphone correction format.
