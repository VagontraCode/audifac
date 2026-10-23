# audifac — MVP Plan

Goal: a local music player for Android that plays common audio formats, with a polished UI and fluid animations.

## Starting point (audit, 2026-10-18)

| Area | State before this plan |
|---|---|
| Build | Did not compile (`library_screen.dart` referenced undefined `_tabController`, `ArtistTab`, …) |
| Playback | None — play/pause toggled a bool. Audio packages were visualizer/recorder toys |
| Library | 5 hardcoded songs, dead placeholder image URLs, no permissions |
| Navigation | Home & Library were the same screen; Player/Album unreachable; double bottom nav bars |
| Theme | `ThemeData.dark()` on a light background; colors hardcoded per widget |
| State | No shared player state |
| Search / Favorites | Placeholder text |

## Key technical decisions

- **Audio engine:** `just_audio` (ExoPlayer on Android → MP3, AAC/M4A, FLAC, OGG Vorbis, Opus, WAV) wrapped by **`audio_service`** for background playback, media notification, lock screen and headset/Bluetooth controls. The UI only talks to our own `AudioHandler` so the engine can be swapped later (e.g. `media_kit` for APE/WMA/DSD).
- **Library scanning:** a small in-house Kotlin MethodChannel over Android `MediaStore` (no unmaintained third-party plugin). Artwork loaded on demand and cached in memory (LRU, per album).
- **State management:** Riverpod.
- **Persistence:** `sqflite` (no code generation). Favorites, playlists, history, settings and the last session are preloaded before the first frame, so there is no theme/data flicker.
- **Platform scope for MVP:** Android first. iOS/desktop later.

## Folder structure

```
lib/
  core/theme/      app_theme.dart (light + dark), app_colors.dart (AppPalette tokens)
  core/audio/      audio_handler.dart (just_audio + audio_service), queue_logic.dart (pure, tested)
  data/            media_library.dart (MediaStore channel), app_database.dart (sqflite), artwork_colors.dart
  models/          song, album, artist, playlist, app_settings, saved_session
  providers/       library, player, user data (favorites/playlists/history/settings), session_controller
  features/
    shell/  home/  library/  collection/ (album, artist, playlist)  player/  search/  favorites/
  widgets/         mini_player, artwork, seek_bar, song_tile, song_actions_sheet, playlist_dialogs, entrance, ...
```

## Phases

### Phase 0 — Get it building ✅
- [x] Remove visualizer/recorder packages (`audio_waveforms`, `flutter_audio_visualizer`, `waveform`)
- [x] Design tokens (`AppPalette`) + theme; no hardcoded colors in widgets
- [x] Single app shell: one bottom nav + docked mini player; remove fake nav bars from screens
- [x] Android toolchain bumped to what Flutter 3.47 requires: Gradle 8.14.3, AGP 8.11.1, Kotlin 2.3.20 (`compilerOptions` DSL)
- [ ] Delete `legacy/` and `lib/screens/` (old mock screens & icons, kept for reference — nothing imports them)
- [ ] `git init` + first commit (owner: you)

### Phase 1 — Real playback ✅
- [x] `just_audio`, `audio_service`, `audio_session`, `flutter_riverpod`
- [x] Android manifest: `AudioService` + `MediaButtonReceiver`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`; `MainActivity` extends `AudioServiceActivity`
- [x] `AudioHandler`: queue, play/pause, next/prev, seek, shuffle, repeat; streams for position/state
- [x] Audio session: pause on headphones unplugged, duck/pause on interruptions (calls)
- [x] Player screen wired to real state (seek bar, times, controls)

### Phase 2 — Real library ✅
- [x] Permissions via `permission_handler` (`READ_MEDIA_AUDIO` on 13+, `READ_EXTERNAL_STORAGE` ≤12)
- [x] MediaStore query: songs, grouped into albums & artists; embedded artwork thumbnails
- [x] Library tabs: Songs / Albums / Artists / Playlists; album & artist pages
- [x] Empty / loading / permission-denied states (re-checked when returning from Settings)
- [x] Search: instant local filter over songs, albums, artists
- [x] Pull-to-refresh on every tab; song sort (title / artist / album / recently added), persisted

### Phase 2b — Whole-device scanning ✅
Android's own index (MediaStore) can be stale: on the test phone it held **zero** of the 7 songs in `Download`.
- [x] Own storage walk of internal storage + SD cards (skips `Android/`, dot-folders, excluded folders)
- [x] Files Android missed are handed to its media scanner → indexed with tags & artwork (7/7 on the test phone, 0.9 s)
- [x] All audio types, not just "music": ringtones/alarms/notifications always hidden; recordings & voice notes behind a toggle; minimum length (Off / 15 / 30 / 60 s, default 30 s)
- [x] Hidden (`.nomedia`) folders: Android 11+ won't let apps list them, so Settings → Folders → **Add a folder** uses the system folder picker (persistent, Play-compliant grant); files play via their document URI, tags read natively and cached (`file_meta`)
- [x] Settings → Folders: every folder with audio, untick to exclude (hidden + skipped by scans)
- [x] Auto-update: MediaStore change observer, rescan on app open / resume (at most every 15 min), pull-to-refresh / "Scan device for audio"
- [x] Artwork fallback when Android refuses thumbnails (it won't for `Download`), and cached cover files so the notification / lock screen shows artwork for every song
- [x] Formats listed = what ExoPlayer plays: mp3, m4a/m4b/aac, flac, ogg/oga/opus, wav, amr/awb, 3gp/3ga, mka, weba

### Phase 2c — Song info, codec filters, source labels ✅
- [x] Native `AudioInspector`: real codec from the stream (MediaExtractor — so .m4a is told apart as AAC vs ALAC), sample rate, channels, bitrate, bit depth (FLAC STREAMINFO / WAV `fmt ` headers, Android 12+ metadata), genre, year, composer, album artist, disc
- [x] Analysed once per file in the background, cached in `audio_info` (DB v4) keyed by location + size + mtime; progress in Settings; instant fallback guess from MIME/extension
- [x] Quality classes: **Hi-Res** (lossless > 48 kHz or > 16-bit), **Lossless** (FLAC / ALAC / WAV), **Lossy**
- [x] Song info sheet (song menu & player ⋮): audio, tags, file (name, folder, source, size, dates, index origin), copy path
- [x] Songs tab filters: All / Hi-Res / Lossless / Lossy + per-codec chips with counts + source chips (shown when > 1 choice); persisted; Shuffle plays the filtered list; "Clear filters"
- [x] Row labels: source category (Music, Downloads, WhatsApp, Telegram, Bluetooth, Recordings, Podcasts, Audiobooks, Hidden folder, or the folder name) + SD-card marker + codec badge (`FLAC 24/96` gold, `FLAC 16/44.1` green, `MP3 320` muted); toggle in Settings
- [x] Verified on the Nokia: 1 × FLAC 16/44.1 (Lossless) + 6 × MP3 128/256, all "Downloads"

### Phase 2d — Audiophile equalizer / DSP ✅
**Engine:** `just_audio` is vendored in `packages/just_audio` (pubspec `dependency_overrides`) with one patch: `JustAudioHooks` lets the app wrap ExoPlayer's audio sink. ExoPlayer only runs custom AudioProcessors on 16-bit PCM, so `DspAudioSink` instead receives the decoder's full-resolution PCM (16/24/32-bit or float), processes it in double precision and feeds 32-bit float to `DefaultAudioSink` (float output), handling encoder delay/padding trimming itself so gapless still works. Installed in `AudifacApplication.onCreate`.
- [x] Chain: preamp → parametric EQ (≤ 20 bands: peak, low/high shelf, low/high-pass, notch; RBJ biquads, TDF-II, double) → mono / balance → crossfeed → peak limiter (−0.1 dBFS)
- [x] Bit-exact pass-through when off / flat (limiter skipped); ~20 ms cross-fade on every change (no clicks); A/B "hold to compare"
- [x] 11 JVM tests (`android/gradlew :app:testDebugUnitTest`) measure real signals: +6 dB really is +6.0 ± 0.1 dB, shelves, passes, preamp, limiter ceiling, mono/balance, crossfeed, click-free changes, bypass
- [x] Two layers: **device correction** (auto-selected per output: phone speaker, wired, each Bluetooth / USB device by name) + **sound preset**; combined with automatic headroom (never stacks on an existing preamp)
- [x] 16 built-in sound presets + "No correction"; custom presets (duplicate, rename, delete), 10-band graphic or free parametric mode
- [x] AutoEQ / Equalizer APO `ParametricEQ.txt`: import from file or clipboard, export to clipboard
- [x] Rules: song → album → artist → genre → source → all music; "this session" choice overrides until a new queue
- [x] Start-of-listening picker (only when a new queue starts, you have your own presets, and no rule decides; "don't ask" option)
- [x] UI: equalizer screen (live response curve with draggable / pinchable points, layer cards, gain, crossfeed / balance / mono), quick preset sheet (player chip, song menu, prompt), rules & devices screen, Settings entry
- [x] Verified on the Nokia: FLAC decoded straight to float into the DSP, Bass boost active with −7.1 dB auto headroom, no errors / underruns, live curve editing heard instantly
- [ ] Later: ReplayGain (needs own tag reader), DSP on the notification "preset" action, per-preset loudness compensation

### Phase 2e — Gapless tuning (planned, not started)
Today: ExoPlayer plays the queue as one concatenated timeline and pre-buffers the next track; `DspAudioSink` trims encoder delay / padding (MP3 LAME/Xing & iTunSMPB, AAC edit lists, Opus pre-skip come from the extractors) and keeps the DSP filter state across tracks of the same rate. What's left is *proving* it and fixing the edge cases:
1. **Test set + measurement (first, so every fix is verified).** Generate a continuous 440 Hz sine (and a pink-noise "live album" crossfade) split into 5 tracks, encoded as MP3 (LAME), AAC (iTunes-style), FLAC, Opus and Vorbis. Add a debug-only PCM tap in `DspAudioSink` that writes what reaches the AudioTrack; a JVM/desktop check finds phase jumps or silence at boundaries (gap in ms, click energy). Run on the Nokia + an emulator.
2. **Track boundaries in the sink.** Verify the held-back padding is dropped exactly once (also on skip-next, seek near the end, and when the next track's `configure` arrives early); unit-test `DspAudioSink` with synthetic buffers.
3. **Sample-rate / channel changes** (e.g. 44.1 kHz album → 48 kHz track) force an AudioTrack rebuild = audible gap. Option: resample to a fixed output rate inside the DSP (high-quality polyphase/sinc) when the rate changes mid-queue, or only flag it ("not gapless: rate change") in the queue.
4. **Album-aware shuffle.** Shuffle breaks gapless albums; add "Shuffle albums" (album order shuffled, tracks kept in order) and keep consecutive tracks of one album together.
5. **Optional crossfade** (0–12 s, off by default, automatically disabled between consecutive tracks of the same album) using the DSP sink — the only place where two tracks' PCM can be mixed.
6. **Pre-load earlier** for slow storage (SD cards): raise the playlist's look-ahead buffer in the load control so the next track is decoded before the current one ends.
7. Settings: "Gapless playback" (on), "Crossfade" (off), "Keep albums together when shuffling" (on).

### Phase 3 — Persistence & remaining features ✅
- [x] Local DB (sqflite): favorites, playlists, recently played, key/value settings
- [x] Favorites: heart in the player, song menu, Favorites tab + Home tile
- [x] Playlists: create, rename, delete, add (from any song menu), swipe to remove, drag to reorder
- [x] Home: Shuffle all, Favorites, Recently played, Recently added albums, Your playlists
- [x] Restore last queue + track + position + shuffle/repeat on app start
- [x] Queue sheet: Now playing / Up next in real play order, drag to reorder, swipe to remove, tap to jump
- [x] Song menu (long-press or ⋮): Play next, Add to queue, Add to playlist, Favorite, Go to album / artist
- [x] "Play next" / "Add to queue" also work while shuffling (custom `QueueShuffleOrder`)

### Phase 4 — Make it slick ✅
- [x] Mini player → full player: slide-up route + Hero artwork (tap or flick up)
- [x] Full player follows the finger when dragged down (rounded corners, springs back or closes)
- [x] Dynamic colors extracted from artwork (`material_color_utilities`), animated on track change
- [x] `AnimatedSwitcher` on title/artwork, artwork scale on pause, swipe artwork / mini player to skip
- [x] Animated equalizer as "now playing" indicator in lists and queue
- [x] Seek bar: track thickens and thumb grows while scrubbing, accent-tinted
- [x] Staggered list entrance animations (first display only, respects "reduce motion")
- [x] Dark mode (System / Light / Dark in Settings, persisted)
- [x] Heart pop animation, press-scale + haptics on controls, tabs and menus
- [ ] Later: interactive drag *up* from the mini player; real waveform via `just_waveform`

### Phase 5 — MVP release checklist
- [x] Unplayable/corrupt file → skipped with a snackbar, never stuck
- [x] App icon: adaptive + Android 13 themed icon + legacy PNGs; splash screen for Android 12+ and older, light/dark
- [x] Unit tests: queue / shuffle / repeat logic, session & settings persistence, parsing (24 tests)
- [x] Release signing config (reads `android/key.properties`, falls back to the debug key)
- [ ] **Hands-on test on device** (owner: you) — see checklist below
- [x] App ID `com.gtongfa.audifac` (Android applicationId / namespace / Kotlin package, iOS / macOS bundle id, Linux id, notification channel)
- [x] Release keystore created (`C:\Users\Georges\.audifac-signing\audifac-release.jks`, RSA 4096, alias `audifac`) — **back it up** with its password (in `android/key.properties`)
- [x] GitHub Actions CI/CD (`.github/workflows/ci.yml`) — see "Release & CI" below
- [ ] iOS code signing (needs an Apple Developer account)

### Phase 6 — Post-release roadmap (v0.2 → v1.0)
Ordered so each step builds on the previous ones. Size: S ≈ hours, M ≈ a day, L ≈ days, XL ≈ weeks.

| # | Feature | Size | Depends on / notes |
|---|---|---|---|
| 6.1 ✅ | **CI upkeep** — current action majors (Node 24), Ubuntu runner pin | S | — |
| 6.2 ✅ | **Backup & restore** — favorites, playlists, history, EQ presets/rules/devices, settings → one JSON file (SAF save/open) | M | — |
| 6.3a ✅ | **FFmpeg fallback decoder** — Jellyfin media3-ffmpeg-decoder 1.9.0+1 (media3 1.9.4) as extension renderer: AC-3/E-AC-3/DTS/TrueHD/ALAC/MP2… wherever the phone's codecs fail | M | vendored just_audio (renderers + extractors hooks) |
| 6.3b ✅ | **AIFF + DSD** — own media3 extractors: AIFF/AIFC (PCM, sowt, fl32/fl64) and DSF/DFF → 176.4 kHz float (table-driven 512-tap FIR, ~48× real time on desktop, playback thread ~20–30 % on the G100); ID3 tags read by the app (Android ignores them) | L | verified on device |
| 6.3c ✅ | **WMA (v1/v2, Pro, Lossless) / APE / WavPack / TTA** — own minimal FFmpeg 7.1.1 (tools/ffmpeg/build.sh: static libavformat + libavcodec with only those demuxers / decoders, built in CI with NDK r28c, cached) behind a JNI reader (cpp/ffmpeg_reader.cpp) and `FfmpegExtractor`: demux + decode natively, raw PCM to ExoPlayer (16-bit exact for ≤16-bit lossless, float otherwise), so EQ / volume matching / crossfade apply. Seeking by time. Tags + duration for the library (AudioHeaders). +1.4 MB per ABI | L | verified on device: all 7 kinds incl. 24/96 WavPack and 8-ch WMA Pro, seek, labels |
| 6.4 ✅ | **Volume matching** — ReplayGain tags (ID3 TXXX, Vorbis/FLAC comments, Opus R128_*, iTunes freeform, LAME header) read from ExoPlayer's own metadata + EBU R128 scan (MediaCodec decode, ~60× real time on the G100) for untagged files, cached (DB v6); Off / Track / Album / Smart, pre-amp, untagged gain, prevent clipping; album gain combined from tracks. Gain chosen at each track's first sample in the DSP sink (extractor tags every Format with its file → gapless-exact), glides 5 ms, limiter guards boosts | L | verified on device: tagged −8.3 dB, measured −11.8 / −10.6 dB per song |
| 6.5 ✅ | **Play counts & stats** — count a play at 50 % / 4 min, last played; Stats screen (top songs/artists/albums, listening time) | M | DB v6 |
| 6.6 ✅ | **Smart playlists** — rule builder (codec/quality, genre, artist, year, added, play count, last played, duration, source) + presets ("Lossless", "Most played", "Not played in 30 days", "Added this week") | M | 6.5, audio info |
| 6.7 ✅ | **Sleep timer** — minutes / end of track / end of queue, gradual fade-out | S | DSP gain or player volume |
| 6.8 ✅ | **Lyrics** — embedded (USLT / LYRICS / ©lyr) + `.lrc` beside the file; synced scrolling view in the player, tap a line to seek | M | native tag reader |
| 6.9 ✅ | **Folder view** — browse by folder tree in Library | S | — |
| 6.10 ✅ | **Audiobooks & podcasts** — speed (0.5–3×, pitch kept), per-book resume, `.m4b` chapters, skip ±15/30 s | M | — |
| 6.11 ✅ | **Gapless tuning + crossfade + album shuffle** (Phase 2e) | L | DSP sink |
| 6.12 ✅ | **Spectrum analyzer / VU meter + output info** — FFT tap in the DSP sink → player visualizer; "FLAC 24/96 → resampled 48 kHz → Bluetooth (codec)" panel | M | DSP sink |
| 6.13 ✅ | **Home-screen widget** — artwork, title, play/pause/next | M | — |
| 6.14 ✅ | **Android Auto** — browsable tree (recent, playlists, albums, artists) through audio_service | M | needs a car / DHU to verify |
| 6.15 ✅ | **Translations** — move all UI text to ARB (gen-l10n), English + French | L | touches every screen |
| 6.16 ✅ | **Last.fm scrobbling** — now playing + scrobble at 50 % / 4 min, offline queue | M | **you** register a Last.fm API key |
| 6.17 ✅ | **Casting** — Chromecast (Cast SDK + local HTTP server for files) and DLNA/UPnP renderers | XL | Google Cast app ID (default receiver works for testing) |
| 6.18 ✅ | **Google Play listing** — privacy policy, data-safety answers, store text, screenshots, feature graphic | M | **you** own the Play Console account ($25 once) |
| 6.19 ✅ | **Real iOS support** — Files/Documents + Apple Music library source, AVAudioEngine EQ, background audio | XL | can't be built or tested on this Windows PC; needs a Mac or CI + a device |
| 6.20 ✅ | **Bit-perfect USB DAC** — own USB Audio Class 2 driver (libusb) bypassing the Android mixer | XL | research spike first; few apps do this |


#### Phase 6 status (October 2026)
All steps are implemented and committed one per step. Checked on the Nokia G100 (Android 12) unless noted:

| Step | Verified on device | Not verified yet |
|---|---|---|
| 6.5 Stats | play counted after half the song, stats screen | — |
| 6.6 Smart playlists | built-ins and descriptions | editor on a big library |
| 6.7 Sleep timer | end-of-song fade + pause | long timers |
| 6.8 Lyrics | attached .lrc, synced, tap to seek | embedded USLT / LYRICS from real files (unit-tested) |
| 6.9 Folders | tab renders | big trees |
| 6.10 Audiobooks | 2× speed on the float path, resume, skip buttons | .m4b chapters on a real book (parser unit-tested) |
| 6.11 Crossfade | 4 s crossfade between two songs, seek while holding | sample-rate change mid-queue |
| 6.12 Spectrum | analyzer, meters, signal path | — |
| 6.13 Widget | pinned, shows artwork, next / pause work | other launchers |
| 6.14 Android Auto | — | needs a car or the Desktop Head Unit |
| 6.15 French | all screens switch | — |
| 6.16 Last.fm | real API round trip (invalid key → error 10) | a real account (needs your API key) |
| 6.17 Casting | discovery runs; DLNA flow end-to-end in a unit test | a real Chromecast / DLNA TV (none on the test Wi-Fi) |
| 6.18 Play listing | graphics, screenshots, texts ready in `store/` | upload (your Play Console account) |
| 6.19 iOS | — | compiled by CI only (no Mac here); needs an iPhone |
| 6.20 Bit-perfect USB | harmless on Android 12 | Android 14+ with a USB DAC |

### Phase 7 — Audiophile features (branch `audiophile`, one commit per step)
Started 2026-10-23, built step by step without supervision. Rules from the owner: **never modify music files** (tag edits and loudness data stay in the app's database), test on the Galaxy S24+ with the **media volume at 0**, no hearing test. Already done elsewhere (not repeated here): folder view (6.9), queue/position restore (Phase 3), bit-perfect USB (6.20), spectrum + VU (6.12).

| # | Feature | Size | Notes |
|---|---|---|---|
| 7.0 ✅ | **Crossfade / DSP fixes** — no freezes at song ends, EQ after the crossfade reserve, MP3 duration-correction stutter | M | prerequisite; verified on the S24+ |
| 7.1 ✅ | **Dither** — TPDF whenever the output is reduced to 16-bit (speed changes) | S | DSP sink |
| 7.2 ✅ | **High-quality resampler** — windowed-sinc polyphase in the DSP to the device's mixer rate (Android otherwise resamples, usually to 48 kHz, with its own filter); quality / phase options; output rate choice (device rate, 96, 192 kHz); same output rate for every song → gapless across sample-rate changes | L | off while bit-perfect is active |
| 7.3 | **Clip counter + richer signal path** — limiter activity and clipped samples per song; file → decoder → resampler → DSP → mixer → device, rate / depth at each step | S | signal sheet |
| 7.4 | **Tone controls** — loudness compensation (ISO 226, follows the volume), tilt EQ, bass / treble shelves | M | device layer |
| 7.5 | **Stereo tools** — width (mid / side), per-channel delay and polarity | S | device layer |
| 7.6 | **Convolution** — load an impulse response (WAV, mono / stereo / true-stereo) for room or headphone correction; partitioned FFT | L | device layer |
| 7.7 | **Linear-phase EQ** — option to render the EQ as a linear-phase FIR (no phase shift, adds latency) | M | uses 7.6 |
| 7.8 | **Compressor** — gentle dynamic range compression for noisy places / night, off by default | M | after EQ, before limiter |
| 7.9 | **Target-curve EQ** — search a headphone model in the AutoEQ database (online), pick a target, import the correction | L | needs network |
| 7.10 | **Multichannel downmix** — 5.1 / 7.1 / quad files folded to stereo with proper coefficients | M | DSP |
| 7.11 | **DR meter + transcode detection** — dynamic range (DR14-style) per track / album, and "fake lossless" detection (lossy-style frequency cutoff in a lossless file) during the loudness scan | M | song info, filters |
| 7.12 | **Sort / filter by resolution** — bit depth, sample rate, bitrate, DR | S | Songs tab |
| 7.13 | **Duplicates** — same song in several files / formats, best version suggested | M | library |
| 7.14 | **Tag editor (in-app)** — edit title / artist / album / album artist / genre / year / track; stored as overrides in the DB, files untouched | M | DB migration |
| 7.15 | **Artwork viewer** — full-resolution cover, pinch to zoom | S | player |
| 7.16 | **M3U / M3U8** — import and export playlists | M | SAF |
| 7.17 | **CUE sheets** — one-file albums split into tracks in the library and played gaplessly | L | library + clipping |
| 7.18 | **Per-album / artist memory** — volume matching mode and speed remembered | S | rules |
| 7.19 | **Waveform seek bar** — loudness envelope computed in the background, cached | M | scanner |
| 7.20 | **Spectrogram + goniometer** — scrolling spectrogram and stereo-image scope next to the spectrum | M | visualizer tap |
| 7.21 | **USB DAC hardware volume** — keep full digital resolution, volume in the DAC | M | needs Android 14+ and a DAC to verify |
| 7.22 | **DSD over PCM (DoP)** — native DSD to USB DACs instead of converting to PCM | L | bit-perfect path; needs a DoP DAC to verify |
| 7.23 | **More tags** — Opus / MKA / DSF / DFF metadata in the library | S | tag reader |

#### Phase 7 status
| Step | Verified | Not verified yet |
|---|---|---|
| 7.0 | S24+: crossfade at song ends, no stuck / skip, MP3 stutter gone | — |
| 7.1 | unit-tested: 0.3 LSB survives on average, error within ±1.5 LSB, clamps | on device (only used while the speed is changed) |
| 7.2 | Nokia: 44.1 kHz MP3 → 48 kHz on the speaker, AudioTrack at 48 kHz, 0 underruns; NEON loop verified against Kotlin at first use; playback thread 11 % → 13.7 % of a core (Kotlin loop: 26–30 %); unit-tested: −80 dB accuracy and phase, flat to 18 kHz, −80 dB alias rejection, exact frame counts, gapless 44.1 → 48 kHz | headphone jack (the Nokia has one; not plugged in) |

### Device test checklist
1. Permission prompt → allow → library appears (Home, Library tabs). Copy a song into some random folder (e.g. `Documents/x`) → it appears after pull-to-refresh. Add WhatsApp's voice-notes folder via Settings → Folders → Add a folder and enable "Show recordings".
2. Deny, then "Allow access" → after "Don't ask again", "Open settings" → enable → come back: library loads.
3. Play from Songs / album / artist / search / favorites / playlist; shuffle all.
4. Mini player: tap and flick up open the player; swipe sideways skips.
5. Player: drag down slowly (springs back) and quickly (closes); colors follow artwork; heart; shuffle/repeat; seek.
6. Queue sheet: reorder, swipe to remove, tap to jump; "Play next" / "Add to queue" from a song menu (with and without shuffle).
7. Background: lock the screen, use notification and lock-screen controls, Bluetooth/headset buttons, unplug headphones (pauses), receive a call (pauses).
8. Kill the app and reopen: same queue, track and position; theme and sort kept; favorites, playlists and history kept.
9. Settings: System / Light / Dark.
10. A large library (1000+ songs): scan time, smooth scrolling.
11. A broken / renamed-extension file: skipped with a message.

### Known limitations / tech notes
- `permission_handler` pinned to ^12 — v13+ pulls an Android plugin compiled against SDK 37, which AGP 8.11 can't resolve. Revisit when moving to AGP 9.
- Flutter warns that Gradle < 9.1 / AGP < 9.0.1 support will be dropped soon: plan an AGP 9 migration (new DSL, built-in Kotlin) after the MVP.
- No "All files access" (`MANAGE_EXTERNAL_STORAGE`) by design — Google Play rejects it for music players. Consequence: other apps' private data (`Android/data`) is never scanned, and hidden folders need a one-time "Add a folder".
- MIDI files are not supported. WMA / APE / WavPack / TTA play through our FFmpeg (6.3c), but Android doesn't recognise .wv / .tta as audio, so apps can't see them: their folder must be added once (Settings → Folders → Add a folder). AIFF and DSD (DSF/DFF, DSD64–256; not DST-compressed DFF) play through the app's own extractors. Building FFmpeg locally needs Linux / WSL: `bash tools/ffmpeg/build.sh <ndk>`.
- Volume matching can't measure DSD / AIFF / FFmpeg-only files yet (Android's MediaCodec has no decoder): they use the "songs without loudness data" gain unless tagged. Fix: measure them through our own parsers (`DsdToPcm`, AIFF reader).
- A song analysed while it's already playing keeps its level until it plays again (a mid-song level jump was heard as a dropout, especially on Bluetooth); new measurements apply only in a song's first 0.3 s. Settings changes (mode, pre-amp) apply at once. The loudness scanner doesn't ask decoders for float (Samsung's mislabel it): scans from before that (scanVersion 1) are redone.
- Casting: the TV plays the original file (no EQ / volume matching); notification / headset buttons still control the phone while casting.
- iOS: no DSP / EQ (needs an AVAudioEngine-based player), no document picker (backups are saved into Documents), no widget.
- "Unknown artist" / "Unknown album" placeholders stay in English (they are data values).
- Generated l10n methods take placeholders in **alphabetical** order — check call sites when adding multi-placeholder messages (`test/l10n_test.dart` covers the current ones).
- Battery (measured on the Nokia G100, release build, playing): library with the now-playing bars ~40 % of one core in total (raster 19 %, was 73 %), full player 5 fps, raster 10 % (was 16 fps, 28 %), Home tab 1 fps, screen off ~28 % (decoding + playback loop). How: the bars tick at 12 fps from one shared clock and stop when paused, in the background, on hidden tabs or under the player (TickerMode); the mini player progress updates once a second; position ticks are dropped in the background; artwork uses RRect shadows / clips; ExoPlayer dynamic scheduling (the playback loop no longer runs every 10 ms). Measure with `top -H` on a release build: profile builds are debuggable, so their Java/Kotlin runs interpreted and looks several times slower.
- Bluetooth: dropouts once per song were reported (wired fine). Media-session updates (AVRCP metadata / cover art) now only go out at a song's start (artwork prefetched for the next song, late artwork kept for next time, no queue re-send for artwork), and while media plays to Bluetooth the AudioTrack buffer is 0.75 s (not 0.32 s) and the playback loop wakes at least every 50 ms (BluetoothOutput). Not reproduced here (no Bluetooth headset on the test phones): confirm with the reporter.
- Reordering the queue is disabled while shuffling (the order is random by design); removing still works.
- Playlists reference MediaStore ids: a song deleted from the device disappears from playlists (kept in storage, hidden).
- Tested on a Nokia G100 (Android 12) and a Galaxy S24+ (Android 17). Samsung decoders write 16-bit PCM when asked for float: they are not asked (HonestPcmAudioRenderer), and any other decoder caught doing it is detected in the DSP sink and remembered (DecoderQuirks).
- Old Flutter launcher PNGs backed up in `legacy/android-icons/`.

- `packages/just_audio` is a patched copy of just_audio 0.10.6: when upgrading just_audio, re-apply the `JustAudioHooks` patch (AudioPlayer.ensurePlayerInitialized + `api` media3 dependency) and keep the app's media3 version (android/app/build.gradle.kts) identical.
- Android resamples to its mixer rate (usually 48 kHz) unless bit-perfect USB output (Android 14+, see 6.20) is on and active.
- Gradle wrapper must stay on 8.14.3 while AGP is 8.11 (an IDE extension rewrote it to 9.7.1 once; AGP 8.x can't run on Gradle ≥ 9.6).

### Out of scope for MVP
Lyrics, gapless tuning, streaming/cloud, tag editing, iOS polish, desktop.

## Release & CI

### What runs (`.github/workflows/ci.yml`)
| Trigger | Jobs |
|---|---|
| Push to `main`/`master`, pull request, manual run | **Analyze & test** (`flutter analyze`, Dart tests + coverage) · **Changes** (commits + files changed since the last `v*` tag → run summary + `CHANGES.md`) · **Android** (signed split APKs + AAB, DSP JVM tests, SHA-256 sums) · **iOS** (release build, unsigned IPA) |
| Push a tag `v1.2.3` | All of the above, then **GitHub Release** "audifac 1.2.3" with every APK/AAB/IPA, `CHANGES.md` as notes + GitHub's generated notes |

Build artifacts are on each run's page (Actions → run → Artifacts). Version = pubspec version (or the tag), build number = CI run number.

### One-time setup
1. Create the GitHub repo, `git init`, commit, push (owner: you). Before the first commit, check `git status` does **not** list `android/key.properties` or any `.jks` (both are git-ignored).
2. Repo → Settings → Secrets and variables → Actions → *New repository secret*:
   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | contents of `C:\Users\Georges\.audifac-signing\keystore.base64.txt` |
   | `ANDROID_KEYSTORE_PASSWORD` | `storePassword` from `android/key.properties` |
   | `ANDROID_KEY_PASSWORD` | `keyPassword` from `android/key.properties` (same value) |
   | `ANDROID_KEY_ALIAS` | `audifac` |
   Without these, CI still builds but signs with the debug key (warning in the log).
3. Back up `audifac-release.jks` + the password somewhere safe (password manager / encrypted drive). Losing them = you can never update the app on Google Play.

### Releasing
```
# bump "version:" in pubspec.yaml if you like (CI uses the tag anyway)
git tag v0.1.0
git push origin v0.1.0
```

### iOS signing (later)
The IPA from CI is **unsigned**: it proves the iOS build compiles and can be sideloaded with a re-signing tool (e.g. Sideloadly / AltStore with your Apple ID), but can't be installed directly or sent to TestFlight. Real signing needs an Apple Developer account ($99/year): export a distribution certificate (`.p12`) + provisioning profile, add them as secrets (`IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`), import them into a temporary keychain in the iOS job and switch to `flutter build ipa --export-options-plist ios/ExportOptions.plist`.
**Note:** the library scanner, folder picker and DSP are Android-native code; on iOS the app builds and opens, but it has no music source until an iOS media layer (Files / MPMediaLibrary) is written.

## Running

```
flutter pub get
flutter run        # on an Android device/emulator with some music in its storage
```

Release build for testing: `flutter build apk --release --split-per-abi` (smaller APKs), or `flutter build appbundle` for Google Play.

To sign releases, create a keystore (keep it and its passwords safe — losing it means you can't update the app on Play):
```
keytool -genkey -v -keystore %USERPROFILE%\audifac.jks -keyalg RSA -keysize 2048 -validity 10000 -alias audifac
```
then `android/key.properties` (already git-ignored):
```
storeFile=C:/Users/<you>/audifac.jks
storePassword=...
keyAlias=audifac
keyPassword=...
```

On an emulator, push test files with `adb push song.mp3 /sdcard/Music/` then trigger a media scan (or reboot the emulator).
