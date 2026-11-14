import 'dart:math' as math;

import 'eq.dart';

/// Blind ABX test: A = the original sound, B = your sound (EQ), X = one of
/// them at random. Guessing gets about half right; scoring well enough that
/// luck is unlikely (p < 0.05) means the difference is really heard.
class AbxTest {
  AbxTest({this.trials = 10, math.Random? random}) : _random = random ?? math.Random() {
    _x = _random.nextBool();
  }

  final int trials;
  final math.Random _random;

  /// Whether X is B (your sound) in the current trial.
  late bool _x;
  final answers = <bool>[];

  int get done => answers.length;
  int get correct => answers.where((ok) => ok).length;
  bool get finished => done >= trials;
  bool get xIsB => _x;

  /// Records "X is B" (true) or "X is A" (false); returns whether it was
  /// right and starts the next trial.
  bool answer({required bool saysB}) {
    if (finished) throw StateError('Test finished');
    final ok = saysB == _x;
    answers.add(ok);
    _x = _random.nextBool();
    return ok;
  }

  /// Chance of at least [correct] right out of [done] by pure guessing.
  double get pValue => binomialTail(done, correct);

  /// The difference was heard (not luck), once finished.
  bool get heard => finished && pValue < 0.05;
}

/// P(at least [k] successes in [n] fair coin flips).
double binomialTail(int n, int k) {
  if (k <= 0) return 1;
  if (k > n) return 0;
  var sum = 0.0;
  var c = 1.0; // C(n, i), built up from C(n, 0).
  for (var i = 0; i <= n; i++) {
    if (i >= k) sum += c;
    c = c * (n - i) / (i + 1);
  }
  return sum / math.pow(2, n);
}

/// About how much louder (dB) [bands] + [preampDb] make music, for level
/// matching: the response's average power over 40 Hz – 16 kHz, with equal
/// weight per octave (music's energy is roughly "pink").
double eqLevelDb(List<EqBand> bands, double preampDb) {
  if (bands.isEmpty) return preampDb;
  const points = 64;
  final lo = math.log(40), hi = math.log(16000);
  var power = 0.0;
  for (var i = 0; i < points; i++) {
    final f = math.exp(lo + (hi - lo) * i / (points - 1));
    power += math.pow(10, EqMath.responseDb(bands, f) / 10);
  }
  return preampDb + 10 * math.log(power / points) / math.ln10;
}

/// Player volumes that level-match A (original) and B (EQ): the louder one
/// is turned down by the difference (volume only ever attenuates).
({double a, double b}) levelMatchedVolumes(double eqLevelDb) {
  double gain(double db) => math.pow(10, -db.abs() / 20).toDouble();
  return eqLevelDb >= 0 ? (a: 1.0, b: gain(eqLevelDb)) : (a: gain(eqLevelDb), b: 1.0);
}
