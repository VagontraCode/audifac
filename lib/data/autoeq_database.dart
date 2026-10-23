import 'dart:convert';
import 'dart:io';

/// One headphone correction in the AutoEQ project's results: [name], who
/// measured it ([source], e.g. "oratory1990" or "crinacle on GRAS 43AG-7")
/// and where it lives ([path], URL-encoded, relative to the results).
class AutoEqEntry {
  const AutoEqEntry({required this.name, required this.source, required this.path});

  final String name;
  final String source;
  final String path;

  /// Over-ear / in-ear / earbud, from the folder the result is in.
  String get form {
    final folder = Uri.decodeComponent(path.split('/').length > 1 ? path.split('/')[1] : '');
    if (folder.contains('in-ear')) return 'in-ear';
    if (folder.contains('earbud')) return 'earbud';
    if (folder.contains('over-ear')) return 'over-ear';
    return '';
  }
}

/// The AutoEQ database (github.com/jaakkopasanen/AutoEq): about 9 000
/// headphones and earphones measured by several reviewers, each with a
/// ready-made correction to the Harman target. Downloaded on demand (the
/// index once per session), searched locally.
class AutoEqDatabase {
  static const _base = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/';

  List<AutoEqEntry>? _index;

  /// `- [Name](./source/form/Name) by source` lines of INDEX.md.
  static List<AutoEqEntry> parseIndex(String markdown) {
    final line = RegExp(r'^- \[(.+)\]\(\./(.+)\) by (.+)$');
    return [
      for (final l in const LineSplitter().convert(markdown))
        if (line.firstMatch(l.trim()) case final m?) AutoEqEntry(name: m.group(1)!, path: m.group(2)!, source: m.group(3)!),
    ];
  }

  /// Entries whose name contains every word of [query] (case-insensitive), best first.
  static List<AutoEqEntry> search(List<AutoEqEntry> index, String query, {int limit = 100}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final hits = index.where((e) {
      final n = e.name.toLowerCase();
      return words.every(n.contains);
    }).toList()
      // Shorter names first: "HD 600" before "HD 600 (worn pads)".
      ..sort((a, b) => a.name.length.compareTo(b.name.length));
    return hits.take(limit).toList();
  }

  Future<List<AutoEqEntry>> index() async => _index ??= parseIndex(await _get('${_base}INDEX.md'));

  /// The entry's correction as an Equalizer APO / AutoEQ `ParametricEQ.txt`.
  Future<String> parametricEq(AutoEqEntry entry) => _get(parametricEqUrl(entry));

  static String parametricEqUrl(AutoEqEntry entry) {
    final folder = entry.path;
    final file = folder.split('/').last; // already URL-encoded, like the folder
    return '$_base$folder/$file%20ParametricEQ.txt';
  }

  Future<String> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}
