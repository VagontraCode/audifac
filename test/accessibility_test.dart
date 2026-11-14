import 'package:audifac/widgets/spoken_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

void main() {
  testWidgets('player chips are buttons with a name, a value and a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerChip(
            icon: HugeIcons.strokeRoundedRepeat,
            label: '1.5×',
            tooltip: 'Playback speed',
            onTap: () => taps++,
          ),
        ),
      ),
    ));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Playback speed')),
      matchesSemantics(
        isButton: true,
        label: 'Playback speed',
        value: '1.5×',
        hasTapAction: true,
        isFocusable: false,
      ),
    );
    await tester.tap(find.byType(PlayerChip));
    expect(taps, 1);
    handle.dispose();
  });
}
