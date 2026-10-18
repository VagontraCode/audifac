import 'package:audifac/models/app_settings.dart';
import 'package:audifac/models/saved_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedSession', () {
    const session = SavedSession(
      songIds: [10, 20, 30, 40],
      index: 2,
      position: Duration(seconds: 42),
      shuffle: true,
      repeat: 'all',
    );

    test('encodes and decodes', () {
      final decoded = SavedSession.decode(session.encode())!;
      expect(decoded.songIds, session.songIds);
      expect(decoded.index, 2);
      expect(decoded.position, const Duration(seconds: 42));
      expect(decoded.shuffle, isTrue);
      expect(decoded.repeat, 'all');
    });

    test('rejects missing or corrupt data', () {
      expect(SavedSession.decode(null), isNull);
      expect(SavedSession.decode(''), isNull);
      expect(SavedSession.decode('{not json'), isNull);
      expect(SavedSession.decode('{"songIds": []}'), isNull);
    });

    test('clamps an out-of-range index', () {
      final decoded = SavedSession.decode('{"songIds": [1, 2], "index": 9}')!;
      expect(decoded.index, 1);
    });

    test('retainWhere keeps the current song when it still exists', () {
      final kept = session.retainWhere((id) => id != 10)!;
      expect(kept.songIds, [20, 30, 40]);
      expect(kept.index, 1); // still song 30
      expect(kept.position, const Duration(seconds: 42));
    });

    test('retainWhere moves to the next song and restarts when current is gone', () {
      final kept = session.retainWhere((id) => id != 30)!;
      expect(kept.songIds, [10, 20, 40]);
      expect(kept.songIds[kept.index], 40);
      expect(kept.position, Duration.zero);
    });

    test('retainWhere returns null when nothing survives', () {
      expect(session.retainWhere((_) => false), isNull);
    });
  });

  group('AppSettings', () {
    test('round-trips through key/values', () {
      const settings = AppSettings(themeMode: ThemeMode.dark, songSort: SongSort.dateAdded);
      final restored = AppSettings.fromKeyValues(settings.toKeyValues());
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.songSort, SongSort.dateAdded);
    });

    test('falls back to defaults for unknown values', () {
      final restored = AppSettings.fromKeyValues({'themeMode': 'neon', 'songSort': '?'});
      expect(restored.themeMode, ThemeMode.system);
      expect(restored.songSort, SongSort.title);
    });
  });
}
