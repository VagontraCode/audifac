import 'package:audifac/models/spoken.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resume spot', () {
    test('round trip with the date', () {
      final at = DateTime(2026, 11, 14, 20, 30);
      final spot = decodeResumeSpot(encodeResumeSpot(const Duration(minutes: 42), at))!;
      expect(spot.position, const Duration(minutes: 42));
      expect(spot.savedAt, at);
    });

    test('reads spots saved by older versions (position only)', () {
      final spot = decodeResumeSpot('123456')!;
      expect(spot.position, const Duration(milliseconds: 123456));
      expect(spot.savedAt, isNull);
    });

    test('ignores garbage', () {
      expect(decodeResumeSpot(null), isNull);
      expect(decodeResumeSpot('abc'), isNull);
    });
  });

  group('bookmarks', () {
    test('round trip, sorted by position, notes optional', () {
      final list = [const Bookmark(Duration(minutes: 9), 'Chapter 3 twist'), const Bookmark(Duration(minutes: 2))];
      final decoded = Bookmark.decodeAll(Bookmark.encodeAll(list));
      expect(decoded, [const Bookmark(Duration(minutes: 2)), const Bookmark(Duration(minutes: 9), 'Chapter 3 twist')]);
    });

    test('bad data gives an empty list, bad entries are skipped', () {
      expect(Bookmark.decodeAll(null), isEmpty);
      expect(Bookmark.decodeAll('not json'), isEmpty);
      expect(Bookmark.decodeAll('{"ms": 1}'), isEmpty);
      expect(Bookmark.decodeAll('[{"ms": 1000}, {"x": 1}, 5]'), [const Bookmark(Duration(seconds: 1))]);
    });
  });
}
