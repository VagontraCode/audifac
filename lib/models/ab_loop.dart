/// A–B repeat: a section of one song played over and over.
///
/// Tapping the A–B button steps through: off → A marked → A–B looping → off.
class AbLoop {
  const AbLoop({this.songId, this.a, this.b});

  static const off = AbLoop();

  /// Shortest loop accepted: a second tap within this keeps waiting for B.
  static const minLength = Duration(seconds: 1);

  /// The song the marks belong to; the loop ends when another song plays.
  final int? songId;
  final Duration? a;
  final Duration? b;

  bool get isOff => a == null;
  bool get waitingForB => a != null && b == null;
  bool get isLooping => a != null && b != null;

  /// The next state when the button is tapped at [position] of [song].
  AbLoop tap(int song, Duration position) {
    final start = a;
    if (start == null || songId != song) return AbLoop(songId: song, a: position);
    if (b != null) return off;
    // B before A: the two marks are swapped.
    final (from, to) = position < start ? (position, start) : (start, position);
    if (to - from < minLength) return this;
    return AbLoop(songId: song, a: from, b: to);
  }

  /// Whether playback at [position] has reached B and must go back to A.
  bool shouldJump(Duration position) => isLooping && position >= b!;

  @override
  bool operator ==(Object other) => other is AbLoop && other.songId == songId && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(songId, a, b);
}
