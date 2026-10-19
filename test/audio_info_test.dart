import 'package:audifac/models/app_settings.dart';
import 'package:audifac/models/audio_info.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/models/song_source.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(String path, {String? mime, bool isFile = false, bool isPodcast = false}) => Song(
      id: isFile ? -1 : 1,
      uri: isFile ? Uri.file(path).toString() : 'content://media/external/audio/media/1',
      path: path,
      title: 't',
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: const Duration(minutes: 4),
      dateAdded: DateTime(2024),
      mimeType: mime,
      sizeBytes: 8000000,
      modifiedMs: 1000,
      isPodcast: isPodcast,
    );

void main() {
  group('quality', () {
    test('lossless vs Hi-Res vs lossy', () {
      expect(const AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16).quality, AudioQuality.lossless);
      expect(const AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24).quality, AudioQuality.hiRes);
      expect(const AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 24).quality, AudioQuality.hiRes);
      expect(const AudioInfo(codec: 'ALAC', sampleRate: 48000).quality, AudioQuality.lossless);
      expect(const AudioInfo(codec: 'WAV', sampleRate: 192000).quality, AudioQuality.hiRes);
      expect(const AudioInfo(codec: 'MP3', sampleRate: 96000).quality, AudioQuality.lossy);
      expect(const AudioInfo(codec: 'Unknown').quality, AudioQuality.unknown);
    });
  });

  group('badge', () {
    test('lossless shows depth / rate', () {
      expect(const AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16).badge, 'FLAC 16/44.1');
      expect(const AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24).badge, 'FLAC 24/96');
      expect(const AudioInfo(codec: 'ALAC', sampleRate: 48000).badge, 'ALAC 48 kHz');
      expect(const AudioInfo(codec: 'WAV').badge, 'WAV');
    });

    test('lossy shows kbps', () {
      expect(const AudioInfo(codec: 'MP3', bitrate: 320000).badge, 'MP3 320');
      expect(const AudioInfo(codec: 'AAC', bitrate: 255800).badge, 'AAC 256');
      expect(const AudioInfo(codec: 'Opus').badge, 'Opus');
    });
  });

  test('new formats: AIFF, DSD, AC-3, MP2, TrueHD', () {
    expect(AudioInfo.codecFromMime('audio/x-aiff'), 'AIFF');
    expect(AudioInfo.codecFromMime('audio/x-dsd'), 'DSD');
    expect(AudioInfo.codecFromMime('audio/true-hd'), 'TrueHD');
    expect(AudioInfo.codecFromMime('audio/vnd.dts'), 'DTS');
    expect(const AudioInfo(codec: 'DSD', sampleRate: 2822400, bitDepth: 1).badge, 'DSD64');
    expect(const AudioInfo(codec: 'DSD', sampleRate: 5644800, bitDepth: 1).badge, 'DSD128');
    expect(const AudioInfo(codec: 'DSD', sampleRate: 2822400).quality, AudioQuality.hiRes);
    expect(const AudioInfo(codec: 'AIFF', sampleRate: 44100, bitDepth: 16).badge, 'AIFF 16/44.1');
    expect(const AudioInfo(codec: 'TrueHD', sampleRate: 48000, bitDepth: 24).quality, AudioQuality.hiRes);
    expect(AudioInfo.guess(_song('/x/a.dsf')).codec, 'DSD');
    expect(AudioInfo.guess(_song('/x/a.aiff')).codec, 'AIFF');
    expect(AudioInfo.guess(_song('/x/a.ac3')).codec, 'AC-3');
    expect(AudioInfo.guess(_song('/x/a.mp2')).codec, 'MP2');
  });

  test('codec names come from the stream, not the extension', () {
    expect(AudioInfo.codecFromMime('audio/flac'), 'FLAC');
    expect(AudioInfo.codecFromMime('audio/alac'), 'ALAC');
    expect(AudioInfo.codecFromMime('audio/raw'), 'WAV');
    expect(AudioInfo.codecFromMime('audio/mpeg'), 'MP3');
    expect(AudioInfo.codecFromMime('audio/mp4a-latm'), 'AAC');
    expect(AudioInfo.codecFromMime('audio/mp4a-latm', aacProfile: 5), 'HE-AAC');
    expect(AudioInfo.codecFromMime('audio/opus'), 'Opus');
    expect(AudioInfo.codecFromMime('audio/vorbis'), 'Vorbis');
    expect(AudioInfo.codecFromMime(null), 'Unknown');
  });

  test('guess before analysis uses MIME, then extension', () {
    expect(AudioInfo.guess(_song('/x/a.flac', mime: 'audio/flac')).codec, 'FLAC');
    expect(AudioInfo.guess(_song('/x/a.mp3')).codec, 'MP3');
    expect(AudioInfo.guess(_song('/x/a.m4a')).codec, 'AAC');
    expect(AudioInfo.guess(_song('/x/a.opus')).codec, 'Opus');
    expect(AudioInfo.guess(_song('/x/a.mp3')).analysed, isFalse);
  });

  test('native result: estimates missing bitrate and records the file version', () {
    final song = _song('/x/a.mp3');
    final info = AudioInfo.fromNative({'ok': true, 'codecMime': 'audio/mpeg', 'sampleRate': 44100}, song)!;
    expect(info.codec, 'MP3');
    expect(info.kbpsOrNull, 267); // 8 MB over 4 min
    expect(info.describes(song), isTrue);
    expect(AudioInfo.fromNative({'ok': false}, song), isNull);
  });

  test('JSON round-trip', () {
    const info = AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24, channels: 2, genre: 'Jazz', sizeBytes: 5, modifiedMs: 6);
    final back = AudioInfo.fromJson(info.toJson());
    expect(back.badge, 'FLAC 24/96');
    expect(back.genre, 'Jazz');
    expect(back.sizeBytes, 5);
  });

  group('source category', () {
    SourceCategory cat(Song s) => SongSource.of(s).category;

    test('folders map to categories', () {
      expect(cat(_song('/storage/emulated/0/Download/a.mp3')), SourceCategory.downloads);
      expect(cat(_song('/storage/emulated/0/Music/Rock/a.mp3')), SourceCategory.music);
      expect(cat(_song('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/a.mp3')),
          SourceCategory.whatsapp);
      expect(cat(_song('/storage/emulated/0/Telegram/Telegram Audio/a.mp3')), SourceCategory.telegram);
      expect(cat(_song('/storage/emulated/0/Bluetooth/a.mp3')), SourceCategory.bluetooth);
      expect(cat(_song('/storage/emulated/0/Recordings/a.m4a')), SourceCategory.recordings);
      expect(cat(_song('/storage/emulated/0/Audiobooks/b/a.m4b')), SourceCategory.audiobooks);
      expect(cat(_song('/storage/emulated/0/Stuff/a.mp3', isPodcast: true)), SourceCategory.podcasts);
      expect(cat(_song('/storage/emulated/0/Secret/a.mp3', isFile: true)), SourceCategory.hidden);
      expect(cat(_song('/storage/emulated/0/Mixes/a.mp3')), SourceCategory.other);
    });

    test('voice notes are recordings even inside WhatsApp', () {
      expect(cat(_song('/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/1/a.opus')), SourceCategory.recordings);
    });

    test('"Other" is labelled with its folder, SD cards are flagged', () {
      final s = SongSource.of(_song('/storage/1A2B-3C4D/Mixes/a.mp3'));
      expect(s.label, 'Mixes');
      expect(s.onSdCard, isTrue);
      expect(SongSource.of(_song('/storage/emulated/0/Download/a.mp3')).label, 'Downloads');
    });
  });

  group('SongFilter', () {
    const flac = AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16);
    const hiRes = AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24);
    const mp3 = AudioInfo(codec: 'MP3', bitrate: 320000);
    final downloads = SongSource.of(_song('/storage/emulated/0/Download/a.mp3'));
    final music = SongSource.of(_song('/storage/emulated/0/Music/a.mp3'));

    test('lossless includes Hi-Res; Hi-Res is strict', () {
      const lossless = SongFilter(quality: AudioQuality.lossless);
      expect(lossless.matches(flac, music), isTrue);
      expect(lossless.matches(hiRes, music), isTrue);
      expect(lossless.matches(mp3, music), isFalse);
      const strict = SongFilter(quality: AudioQuality.hiRes);
      expect(strict.matches(flac, music), isFalse);
      expect(strict.matches(hiRes, music), isTrue);
    });

    test('codecs OR, groups AND', () {
      const f = SongFilter(codecs: {'MP3', 'AAC'}, categories: {SourceCategory.downloads});
      expect(f.matches(mp3, downloads), isTrue);
      expect(f.matches(mp3, music), isFalse);
      expect(f.matches(flac, downloads), isFalse);
    });

    test('persists', () {
      const f = SongFilter(quality: AudioQuality.hiRes, codecs: {'FLAC'}, categories: {SourceCategory.music});
      final back = SongFilter.decode(f.encode());
      expect(back.quality, AudioQuality.hiRes);
      expect(back.codecs, {'FLAC'});
      expect(back.categories, {SourceCategory.music});
      expect(SongFilter.decode('nonsense').isEmpty, isTrue);
      expect(AppSettings.fromKeyValues(const AppSettings(showLabels: false).toKeyValues()).showLabels, isFalse);
    });
  });

  group('WMA / APE / WavPack / TTA (our FFmpeg)', () {
    test('codec names from the native MIME types', () {
      expect(AudioInfo.codecFromMime('audio/x-ms-wma'), 'WMA');
      expect(AudioInfo.codecFromMime('audio/x-ms-wma-pro'), 'WMA Pro');
      expect(AudioInfo.codecFromMime('audio/x-ms-wma-lossless'), 'WMA Lossless');
      expect(AudioInfo.codecFromMime('audio/x-ape'), 'APE');
      expect(AudioInfo.codecFromMime('audio/x-wavpack'), 'WavPack');
      expect(AudioInfo.codecFromMime('audio/x-tta'), 'TTA');
    });

    test('guessed from the extension before analysis', () {
      expect(AudioInfo.guess(_song('/m/a.wma', mime: 'audio/x-ms-wma')).codec, 'WMA');
      expect(AudioInfo.guess(_song('/m/a.ape')).codec, 'APE');
      expect(AudioInfo.guess(_song('/m/a.wv')).codec, 'WavPack');
      expect(AudioInfo.guess(_song('/m/a.tta')).codec, 'TTA');
    });

    test('lossless ones count as lossless / Hi-Res', () {
      expect(const AudioInfo(codec: 'APE', sampleRate: 44100, bitDepth: 16).quality, AudioQuality.lossless);
      expect(const AudioInfo(codec: 'WavPack', sampleRate: 96000, bitDepth: 24).quality, AudioQuality.hiRes);
      expect(const AudioInfo(codec: 'WMA Lossless', sampleRate: 44100, bitDepth: 16).quality, AudioQuality.lossless);
      expect(const AudioInfo(codec: 'WMA', sampleRate: 44100).quality, AudioQuality.lossy);
      expect(const AudioInfo(codec: 'WMA Pro', sampleRate: 48000).quality, AudioQuality.lossy);
    });

    test('an unknown bit depth (0) is not shown', () {
      final info = AudioInfo.fromNative(const {'ok': true, 'codecMime': 'audio/x-ms-wma', 'bitDepth': 0, 'sampleRate': 44100}, _song('/m/a.wma'));
      expect(info?.bitDepth, isNull);
    });
  });
}
