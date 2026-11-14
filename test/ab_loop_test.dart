import 'package:audifac/models/ab_loop.dart';
import 'package:flutter_test/flutter_test.dart';

Duration s(int seconds) => Duration(seconds: seconds);

void main() {
  test('off → A → A–B → off', () {
    var loop = AbLoop.off.tap(7, s(10));
    expect(loop.waitingForB, isTrue);
    expect(loop.a, s(10));
    loop = loop.tap(7, s(25));
    expect(loop.isLooping, isTrue);
    expect((loop.a, loop.b), (s(10), s(25)));
    expect(loop.tap(7, s(30)).isOff, isTrue);
  });

  test('B before A swaps the marks', () {
    final loop = AbLoop.off.tap(1, s(40)).tap(1, s(12));
    expect((loop.a, loop.b), (s(12), s(40)));
  });

  test('a loop shorter than a second keeps waiting for B', () {
    final a = AbLoop.off.tap(1, s(5));
    expect(a.tap(1, s(5) + const Duration(milliseconds: 400)), a);
  });

  test('a tap on another song starts over at A', () {
    final loop = AbLoop.off.tap(1, s(5)).tap(1, s(9)).tap(2, s(3));
    expect((loop.songId, loop.a, loop.b), (2, s(3), null));
  });

  test('jumps back once B is reached', () {
    final loop = AbLoop.off.tap(1, s(5)).tap(1, s(9));
    expect(loop.shouldJump(s(8)), isFalse);
    expect(loop.shouldJump(s(9)), isTrue);
    expect(AbLoop.off.tap(1, s(5)).shouldJump(s(100)), isFalse);
  });
}
