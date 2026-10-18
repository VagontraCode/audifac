import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

void main() {
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
