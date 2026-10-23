import 'package:audifac/data/autoeq_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _index = '''
# Index
This is a list of all equalization profiles.

- [1MORE Aero (ANC Off)](./HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)) by HypetheSonics on GRAS RA0045
- [Sennheiser HD 600](./oratory1990/over-ear/Sennheiser%20HD%20600) by oratory1990
- [Sennheiser HD 600](./crinacle/GRAS%2043AG-7%20over-ear/Sennheiser%20HD%20600) by crinacle on GRAS 43AG-7
- [Sennheiser HD 600 (worn earpads)](./oratory1990/over-ear/Sennheiser%20HD%20600%20(worn%20earpads)) by oratory1990
- [Sennheiser HD 650](./oratory1990/over-ear/Sennheiser%20HD%20650) by oratory1990
''';

void main() {
  final entries = AutoEqDatabase.parseIndex(_index);

  test('parses every entry with its source and path', () {
    expect(entries.length, 5);
    expect(entries.first.name, '1MORE Aero (ANC Off)');
    expect(entries.first.source, 'HypetheSonics on GRAS RA0045');
    expect(entries.first.form, 'in-ear');
    expect(entries[1].form, 'over-ear');
  });

  test('search matches every word, shortest names first', () {
    final hits = AutoEqDatabase.search(entries, 'hd 600');
    expect(hits.map((e) => e.name), ['Sennheiser HD 600', 'Sennheiser HD 600', 'Sennheiser HD 600 (worn earpads)']);
    expect(AutoEqDatabase.search(entries, 'sennheiser 650').single.name, 'Sennheiser HD 650');
    expect(AutoEqDatabase.search(entries, '   '), isEmpty);
  });

  test('correction URL (checked against the live repository)', () {
    expect(
      AutoEqDatabase.parametricEqUrl(entries[1]),
      'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/oratory1990/over-ear/Sennheiser%20HD%20600/Sennheiser%20HD%20600%20ParametricEQ.txt',
    );
  });
}
