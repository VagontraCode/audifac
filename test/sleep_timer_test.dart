import 'package:audifac/providers/sleep_timer_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fade: full until the fade starts, silent at the end, squared in between', () {
    const fade = Duration(seconds: 30);
    expect(sleepFadeVolume(const Duration(minutes: 5), fade), 1);
    expect(sleepFadeVolume(fade, fade), 1);
    expect(sleepFadeVolume(const Duration(seconds: 15), fade), closeTo(0.25, 1e-9));
    expect(sleepFadeVolume(Duration.zero, fade), 0);
    expect(sleepFadeVolume(const Duration(seconds: -3), fade), 0);
  });
}
