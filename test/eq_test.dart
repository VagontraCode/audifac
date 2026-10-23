import 'package:audifac/models/eq.dart';
import 'package:audifac/models/eq_rules.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({int id = 1, int albumId = 10, String artist = 'Artist', String path = '/storage/emulated/0/Music/a.flac'}) =>
    Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: path,
      title: 'Title',
      artist: artist,
      artistId: 1,
      album: 'Album',
      albumId: albumId,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime(2024),
    );

void main() {
  group('EqMath (same formulas as the native DSP)', () {
    test('peaking: full gain at the centre, none far away', () {
      const b = [EqBand(frequency: 1000, gainDb: 6, q: 1)];
      expect(EqMath.responseDb(b, 1000), closeTo(6, 0.01));
      expect(EqMath.responseDb(b, 30), closeTo(0, 0.1));
      expect(EqMath.responseDb(b, 18000), closeTo(0, 0.2));
    });

    test('shelves and passes', () {
      const low = [EqBand(type: EqFilterType.lowShelf, frequency: 200, gainDb: -6, q: 0.707)];
      expect(EqMath.responseDb(low, 25), closeTo(-6, 0.2));
      expect(EqMath.responseDb(low, 200), closeTo(-3, 0.3)); // half gain at corner
      const lp = [EqBand(type: EqFilterType.lowPass, frequency: 1000, q: 0.707)];
      expect(EqMath.responseDb(lp, 1000), closeTo(-3.01, 0.05));
      expect(EqMath.responseDb(lp, 8000), lessThan(-30));
      const notch = [EqBand(type: EqFilterType.notch, frequency: 3000, q: 4)];
      expect(EqMath.responseDb(notch, 3000), lessThan(-40));
    });

    test('bands add up and maxBoost finds the peak', () {
      const bands = [
        EqBand(frequency: 100, gainDb: 4, q: 1),
        EqBand(frequency: 100, gainDb: 3, q: 1),
      ];
      expect(EqMath.responseDb(bands, 100), closeTo(7, 0.02));
      expect(EqMath.maxBoostDb(bands), closeTo(7, 0.1));
      expect(EqMath.maxBoostDb(const [EqBand(frequency: 100, gainDb: -5)]), 0);
    });
  });

  group('AutoEQ', () {
    const sample = '''
Preamp: -6.4 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 2: ON PK Fc 2484 Hz Gain -3.1 dB Q 2.05
Filter 3: OFF PK Fc 3000 Hz Gain 9 dB Q 1
Filter 4: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.70
Filter 5: ON HPQ Fc 20 Hz Q 0.71
''';

    test('parses ParametricEQ.txt, skipping OFF filters', () {
      final p = EqPreset.fromAutoEq(sample, id: 'x', name: 'HD 650')!;
      expect(p.preampDb, -6.4);
      expect(p.kind, EqPresetKind.device);
      expect(p.bands.length, 4);
      expect(p.bands[0].type, EqFilterType.lowShelf);
      expect(p.bands[0].gainDb, 5.5);
      expect(p.bands[1].frequency, 2484);
      expect(p.bands[1].q, 2.05);
      expect(p.bands[3].type, EqFilterType.highPass);
    });

    test('round-trips through export', () {
      final p = EqPreset.fromAutoEq(sample, id: 'x', name: 'HD 650')!;
      final again = EqPreset.fromAutoEq(p.toAutoEq(), id: 'y', name: 'copy')!;
      expect(again.preampDb, p.preampDb);
      expect(again.bands.length, p.bands.length);
      for (var i = 0; i < p.bands.length; i++) {
        expect(again.bands[i].type, p.bands[i].type);
        expect(again.bands[i].frequency, closeTo(p.bands[i].frequency, 0.1));
        expect(again.bands[i].gainDb, closeTo(p.bands[i].gainDb, 0.05));
        expect(again.bands[i].q, closeTo(p.bands[i].q, 0.005));
      }
    });

    test('rejects text without filters', () {
      expect(EqPreset.fromAutoEq('hello world', id: 'x', name: 'n'), isNull);
    });
  });

  group('presets', () {
    test('built-ins are 10-band graphic and valid', () {
      for (final p in BuiltInPresets.sound) {
        expect(p.graphic, isTrue, reason: p.name);
        expect(p.bands.length, 10, reason: p.name);
        expect(p.builtIn, isTrue);
      }
      expect(BuiltInPresets.soundFlat.isFlat, isTrue);
      expect(BuiltInPresets.sound.map((p) => p.id).toSet().length, BuiltInPresets.sound.length);
    });

    test('JSON round-trip and duplicate', () {
      final p = BuiltInPresets.sound[5];
      final back = EqPreset.fromJson(p.toJson());
      expect(back.name, p.name);
      expect(back.bands.map((b) => b.gainDb), p.bands.map((b) => b.gainDb));
      final copy = p.duplicate(id: 'u_1');
      expect(copy.builtIn, isFalse);
      expect(copy.name, '${p.name} (copy)');
    });
  });

  group('combine layers', () {
    const device = EqPreset(
      id: 'd',
      name: 'HD 650',
      kind: EqPresetKind.device,
      preampDb: -6,
      bands: [EqBand(frequency: 100, gainDb: 5.5, q: 0.7)],
      crossfeed: 0.4,
    );
    final sound = EqPreset.graphicPreset('s', 'Bass', [3, 3, 0, 0, 0, 0, 0, 0, 0, 0]);

    test('stacks bands and takes output options from the device', () {
      final c = combineForNative(enabled: true, device: device, sound: sound, autoPreamp: false);
      expect((c['bands'] as List).length, 11);
      expect(c['preampDb'], -6);
      expect(c['crossfeed'], 0.4);
    });

    test('automatic headroom never stacks on an existing preamp', () {
      final boost = EqMath.maxBoostDb([...device.bands, ...sound.bands]);
      final c = combineForNative(enabled: true, device: device, sound: sound, autoPreamp: true);
      final preamp = c['preampDb'] as double;
      expect(preamp, closeTo(-boost < -6 ? -boost : -6, 1e-9));
      final flat = combineForNative(enabled: true, device: BuiltInPresets.deviceNone, sound: BuiltInPresets.soundFlat, autoPreamp: true);
      expect(flat['preampDb'], 0);
    });
  });

  group('tone', () {
    test('adds shelves, counted in the automatic headroom', () {
      const tone = Tone(bassDb: 6, trebleDb: -3, tiltDb: 2);
      expect(tone.bands.length, 4);
      final c = combineForNative(
        enabled: true,
        device: BuiltInPresets.deviceNone,
        sound: BuiltInPresets.soundFlat,
        autoPreamp: true,
        tone: tone,
      );
      expect((c['bands'] as List).length, BuiltInPresets.soundFlat.bands.length + 4);
      expect(c['preampDb'] as double, closeTo(-EqMath.maxBoostDb(tone.bands), 1e-9)); // the tone's biggest boost
      expect(c['loudness'], isFalse);
    });

    test('neutral adds nothing; loudness is a flag for the native side', () {
      expect(const Tone().bands, isEmpty);
      expect(const Tone().isNeutral, isTrue);
      final c = combineForNative(
        enabled: true,
        device: BuiltInPresets.deviceNone,
        sound: BuiltInPresets.soundFlat,
        autoPreamp: true,
        tone: const Tone(loudness: true),
      );
      expect((c['bands'] as List).length, BuiltInPresets.soundFlat.bands.length);
      expect(c['loudness'], isTrue);
    });

    test('saved with the settings, clamped when read', () {
      const s = EqSettings(tone: Tone(bassDb: 4.5, trebleDb: -2, tiltDb: 1, loudness: true));
      final back = EqSettings.decode(s.encode());
      expect(back.tone.bassDb, 4.5);
      expect(back.tone.trebleDb, -2);
      expect(back.tone.tiltDb, 1);
      expect(back.tone.loudness, isTrue);
      expect(Tone.fromJson({'bass': 40}).bassDb, Tone.maxDb);
      expect(EqSettings.decode('{"enabled":true}').tone.isNeutral, isTrue);
    });
  });

  group('rules', () {
    final presets = {'p_song', 'p_album', 'p_artist', 'p_genre', 'p_source', 'p_default', 'p_queue'};
    bool valid(String id) => presets.contains(id);
    final song = _song();

    EqRule rule(EqScope s, String presetId) => EqRule(
          scope: s,
          key: EqRule.keyFor(s, song, genre: 'Jazz')!,
          label: '',
          presetId: presetId,
        );

    test('most specific wins', () {
      final rules = [
        rule(EqScope.source, 'p_source'),
        rule(EqScope.genre, 'p_genre'),
        rule(EqScope.artist, 'p_artist'),
        rule(EqScope.album, 'p_album'),
      ];
      var r = resolveSoundPreset(
          song: song, genre: 'jazz ', rules: rules, queueOverride: null, defaultPresetId: 'p_default', isValid: valid);
      expect(r.presetId, 'p_album');
      expect(r.reason, EqReason.album);

      r = resolveSoundPreset(
          song: song, genre: 'Jazz', rules: [...rules, rule(EqScope.song, 'p_song')], queueOverride: null,
          defaultPresetId: 'p_default', isValid: valid);
      expect(r.reason, EqReason.song);

      r = resolveSoundPreset(
          song: song, genre: 'Jazz', rules: rules.take(2).toList(), queueOverride: null,
          defaultPresetId: 'p_default', isValid: valid);
      expect(r.reason, EqReason.genre);
    });

    test('session choice beats rules; default when nothing matches; deleted presets ignored', () {
      final rules = [rule(EqScope.album, 'p_album')];
      expect(
        resolveSoundPreset(song: song, genre: null, rules: rules, queueOverride: 'p_queue', defaultPresetId: 'p_default', isValid: valid).reason,
        EqReason.queue,
      );
      final other = _song(id: 2, albumId: 99, artist: 'Someone else', path: '/storage/emulated/0/Download/b.mp3');
      expect(
        resolveSoundPreset(song: other, genre: null, rules: rules, queueOverride: null, defaultPresetId: 'p_default', isValid: valid).presetId,
        'p_default',
      );
      final dangling = [EqRule(scope: EqScope.album, key: '10', label: '', presetId: 'gone')];
      expect(
        resolveSoundPreset(song: song, genre: null, rules: dangling, queueOverride: null, defaultPresetId: 'p_default', isValid: valid).reason,
        EqReason.defaultPreset,
      );
    });

    test('no genre / unknown artist produce no key', () {
      expect(EqRule.keyFor(EqScope.genre, song), isNull);
      expect(EqRule.keyFor(EqScope.artist, _song(artist: Song.unknownArtist)), isNull);
      expect(EqRule.keyFor(EqScope.source, song), 'music');
    });
  });

  test('settings persist devices and flags', () {
    const s = EqSettings(
      enabled: true,
      defaultSoundId: 'b_vocal',
      askOnPlay: false,
      autoPreamp: false,
      devices: {'bt:WH-1000XM4': EqDevice(key: 'bt:WH-1000XM4', name: 'WH-1000XM4', kind: 'bluetooth', presetId: 'u_1')},
    );
    final back = EqSettings.decode(s.encode());
    expect(back.enabled, isTrue);
    expect(back.defaultSoundId, 'b_vocal');
    expect(back.askOnPlay, isFalse);
    expect(back.autoPreamp, isFalse);
    expect(back.devices['bt:WH-1000XM4']!.presetId, 'u_1');
    expect(EqSettings.decode('garbage').enabled, isFalse);
  });
}
