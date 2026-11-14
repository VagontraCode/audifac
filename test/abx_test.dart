import 'dart:math' as math;

import 'package:audifac/models/abx.dart';
import 'package:audifac/models/eq.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('binomial tail matches known values', () {
    expect(binomialTail(10, 0), 1);
    expect(binomialTail(10, 10), closeTo(1 / 1024, 1e-12));
    expect(binomialTail(10, 9), closeTo(11 / 1024, 1e-12));
    expect(binomialTail(10, 8), closeTo(56 / 1024, 1e-12)); // 5.5 %: not quite enough
    expect(binomialTail(10, 11), 0);
  });

  test('9 / 10 counts as heard, 8 / 10 does not', () {
    AbxTest run(int right) {
      final t = AbxTest(random: math.Random(1));
      for (var i = 0; i < 10; i++) {
        t.answer(saysB: i < right ? t.xIsB : !t.xIsB);
      }
      return t;
    }

    expect(run(9).heard, isTrue);
    expect(run(8).heard, isFalse);
    expect(run(9).correct, 9);
    expect(() => run(9).answer(saysB: true), throwsStateError);
  });

  test('X is random across rounds', () {
    final t = AbxTest(trials: 200, random: math.Random(7));
    var b = 0;
    for (var i = 0; i < 200; i++) {
      if (t.xIsB) b++;
      t.answer(saysB: true);
    }
    expect(b, inInclusiveRange(70, 130));
  });

  test('EQ level: flat is the preamp, a broad boost is louder', () {
    expect(eqLevelDb(const [], -3), -3);
    final flat = eqLevelDb(const [EqBand(frequency: 1000, gainDb: 0)], 0);
    expect(flat, closeTo(0, 1e-9));
    // +6 dB low shelf with −6 dB headroom: overall quieter than the original.
    final bass = eqLevelDb(const [EqBand(type: EqFilterType.lowShelf, frequency: 200, gainDb: 6)], -6);
    expect(bass, lessThan(0));
    expect(bass, greaterThan(-6));
  });

  test('level matching only turns the louder one down', () {
    final louderB = levelMatchedVolumes(6);
    expect(louderB.a, 1);
    expect(louderB.b, closeTo(0.501, 0.001));
    final louderA = levelMatchedVolumes(-6);
    expect(louderA.b, 1);
    expect(louderA.a, closeTo(0.501, 0.001));
  });
}
