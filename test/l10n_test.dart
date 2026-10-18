import 'dart:convert';
import 'dart:io';

import 'package:audifac/l10n/generated/app_localizations.dart';
import 'package:audifac/l10n/labels.dart';
import 'package:audifac/models/smart_playlist.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('multi-placeholder messages get their arguments in the right places', () {
    // Generated methods take placeholders alphabetically: easy to swap.
    final en = lookupAppLocalizations(const Locale('en'));
    final fr = lookupAppLocalizations(const Locale('fr'));
    const added = SmartRule(SmartField.added, SmartOp.within, '7');
    const old = SmartRule(SmartField.lastPlayed, SmartOp.notWithin, '30');
    expect(en.smartRule(added), 'Added in the last 7 days');
    expect(en.smartRule(old), 'Last played over 30 days ago');
    expect(fr.smartRule(added), 'Ajouté ces 7 derniers jours');
    expect(en.shownOfFound(10, 7), '7 shown of 10 found');
    expect(en.rulesDevicesCount(2, 5), '5 rules · 2 devices');
    expect(en.songsOf(3, 12), '3 of 12 songs');
    expect(en.resampled('44.1 kHz', '48 kHz'), 'Resampled 44.1 kHz → 48 kHz');
  });

  test('French has exactly the English keys', () {
    final en = _arb('en').keys.where((k) => !k.startsWith('@')).toSet();
    final fr = _arb('fr').keys.where((k) => !k.startsWith('@')).toSet();
    expect(fr.difference(en), isEmpty, reason: 'only in French');
    expect(en.difference(fr), isEmpty, reason: 'missing in French');
  });

  test('placeholders match in both languages', () {
    final en = _arb('en'), fr = _arb('fr');
    // Placeholders, not plural branches like `=1{play}` / `other{plays}`.
    final names = RegExp(r'(?<![\w=])\{(\w+)[,}]');
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      Set<String> of(String s) => {for (final m in names.allMatches(s)) m.group(1)!};
      expect(of(fr[key] as String), of(en[key] as String), reason: key);
    }
  });
}
