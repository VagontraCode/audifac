import 'dart:convert';
import 'dart:math' as math;

import 'audio_info.dart';
import 'play_stats.dart';
import 'song.dart';
import 'song_source.dart';

enum SmartKind { text, choice, number, days, flag }

/// What a rule looks at.
enum SmartField {
  title('Title', SmartKind.text),
  artist('Artist', SmartKind.text),
  album('Album', SmartKind.text),
  genre('Genre', SmartKind.text),
  folder('Folder', SmartKind.text),
  quality('Quality', SmartKind.choice),
  codec('Codec', SmartKind.choice),
  source('Source', SmartKind.choice),
  year('Year', SmartKind.number),
  duration('Length (minutes)', SmartKind.number),
  plays('Play count', SmartKind.number),
  added('Added', SmartKind.days),
  lastPlayed('Last played', SmartKind.days),
  favorite('Favorite', SmartKind.flag);

  const SmartField(this.label, this.kind);
  final String label;
  final SmartKind kind;

  List<SmartOp> get ops => switch (kind) {
        SmartKind.text => const [SmartOp.contains, SmartOp.equals, SmartOp.notContains],
        SmartKind.choice => const [SmartOp.equals, SmartOp.notEquals],
        SmartKind.number => const [SmartOp.atLeast, SmartOp.atMost],
        SmartKind.days => [SmartOp.within, SmartOp.notWithin, if (this == SmartField.lastPlayed) SmartOp.never],
        SmartKind.flag => const [SmartOp.yes, SmartOp.no],
      };

  /// Values to pick from (choice fields).
  List<(String value, String label)> choices(Iterable<String> codecs) => switch (this) {
        SmartField.quality => [
            for (final q in [AudioQuality.hiRes, AudioQuality.lossless, AudioQuality.lossy]) (q.name, q.label),
          ],
        SmartField.codec => [for (final c in codecs) (c, c)],
        SmartField.source => [for (final s in SourceCategory.values) (s.name, s.label)],
        _ => const [],
      };
}

enum SmartOp {
  contains('contains'),
  notContains('doesn\'t contain'),
  equals('is'),
  notEquals('is not'),
  atLeast('at least'),
  atMost('at most'),
  within('in the last (days)'),
  notWithin('not in the last (days)'),
  never('never'),
  yes('yes'),
  no('no');

  const SmartOp(this.label);
  final String label;

  bool get needsValue => this != never && this != yes && this != no;
}

class SmartRule {
  const SmartRule(this.field, this.op, [this.value = '']);

  final SmartField field;
  final SmartOp op;
  final String value;

  SmartRule copyWith({SmartField? field, SmartOp? op, String? value}) =>
      SmartRule(field ?? this.field, op ?? this.op, value ?? this.value);

  /// A sensible starting rule for [field].
  factory SmartRule.forField(SmartField field) => switch (field.kind) {
        SmartKind.choice => SmartRule(field, SmartOp.equals, field == SmartField.quality ? AudioQuality.lossless.name : ''),
        SmartKind.number => SmartRule(field, SmartOp.atLeast, field == SmartField.year ? '2000' : '1'),
        SmartKind.days => SmartRule(field, SmartOp.within, '30'),
        SmartKind.flag => SmartRule(field, SmartOp.yes),
        SmartKind.text => SmartRule(field, SmartOp.contains),
      };

  String describe() {
    final shown = field.kind == SmartKind.choice
        ? field.choices(const []).where((c) => c.$1 == value).firstOrNull?.$2 ?? value
        : value;
    return switch (op) {
      SmartOp.within => '${field.label} in the last $value days',
      SmartOp.notWithin => '${field.label} over $value days ago',
      SmartOp.never => field == SmartField.lastPlayed ? 'Never played' : '${field.label} never',
      SmartOp.yes => field.label,
      SmartOp.no => 'Not ${field.label.toLowerCase()}',
      _ => '${field.label} ${op.label}${shown.isEmpty ? '' : ' $shown'}',
    };
  }

  Map<String, Object?> toJson() => {'field': field.name, 'op': op.name, 'value': value};

  static SmartRule? fromJson(Map<String, dynamic> j) {
    final field = SmartField.values.asNameMap()[j['field']];
    final op = SmartOp.values.asNameMap()[j['op']];
    if (field == null || op == null) return null;
    return SmartRule(field, op, j['value'] as String? ?? '');
  }
}

enum SmartSort {
  mostPlayed('Most played'),
  recentlyPlayed('Recently played'),
  recentlyAdded('Recently added'),
  title('Title'),
  artist('Artist'),
  random('Random');

  const SmartSort(this.label);
  final String label;
}

/// What a rule can know about a song besides its tags.
class SmartContext {
  const SmartContext({required this.info, required this.stats, required this.favorites, required this.now});

  final AudioInfo Function(Song song) info;
  final Map<int, SongStats> stats;
  final Set<int> favorites;
  final DateTime now;
}

class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.name,
    this.rules = const [],
    this.matchAll = true,
    this.sort = SmartSort.mostPlayed,
    this.limit,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final List<SmartRule> rules;

  /// All rules must match (else: any).
  final bool matchAll;
  final SmartSort sort;

  /// At most this many songs.
  final int? limit;
  final bool builtIn;

  SmartPlaylist copyWith({
    String? id,
    String? name,
    List<SmartRule>? rules,
    bool? matchAll,
    SmartSort? sort,
    int? Function()? limit,
    bool? builtIn,
  }) =>
      SmartPlaylist(
        id: id ?? this.id,
        name: name ?? this.name,
        rules: rules ?? this.rules,
        matchAll: matchAll ?? this.matchAll,
        sort: sort ?? this.sort,
        limit: limit == null ? this.limit : limit(),
        builtIn: builtIn ?? this.builtIn,
      );

  String describe() {
    if (rules.isEmpty) return 'All songs';
    return rules.map((r) => r.describe()).join(matchAll ? ' · ' : ' or ');
  }

  /// The matching songs, sorted and limited.
  List<Song> songsFrom(List<Song> library, SmartContext ctx) {
    final matching = library.where((s) {
      if (rules.isEmpty) return true;
      return matchAll ? rules.every((r) => _matches(r, s, ctx)) : rules.any((r) => _matches(r, s, ctx));
    }).toList();
    int plays(Song s) => ctx.stats[s.id]?.plays ?? 0;
    int last(Song s) => ctx.stats[s.id]?.lastPlayed?.millisecondsSinceEpoch ?? 0;
    switch (sort) {
      case SmartSort.mostPlayed:
        matching.sort((a, b) => plays(b).compareTo(plays(a)));
      case SmartSort.recentlyPlayed:
        matching.sort((a, b) => last(b).compareTo(last(a)));
      case SmartSort.recentlyAdded:
        matching.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case SmartSort.title:
        matching.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SmartSort.artist:
        matching.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : a.album.toLowerCase().compareTo(b.album.toLowerCase());
        });
      case SmartSort.random:
        // Stable for the day, so the list doesn't reshuffle on every rebuild.
        final seed = DateTime(ctx.now.year, ctx.now.month, ctx.now.day).millisecondsSinceEpoch ~/ 1000;
        matching.shuffle(math.Random(seed ^ id.hashCode));
    }
    return limit == null ? matching : matching.take(limit!).toList();
  }

  static bool _matches(SmartRule r, Song s, SmartContext ctx) {
    String text() => switch (r.field) {
          SmartField.title => s.title,
          SmartField.artist => s.artist,
          SmartField.album => s.album,
          SmartField.genre => ctx.info(s).genre ?? '',
          SmartField.folder => s.folder ?? '',
          _ => '',
        };
    String choice() => switch (r.field) {
          SmartField.quality => ctx.info(s).quality.name,
          SmartField.codec => ctx.info(s).codec,
          SmartField.source => SongSource.of(s).category.name,
          _ => '',
        };
    num? number() => switch (r.field) {
          SmartField.year => int.tryParse((ctx.info(s).year ?? '').padRight(4).substring(0, 4).trim()),
          SmartField.duration => s.duration.inSeconds / 60,
          SmartField.plays => ctx.stats[s.id]?.plays ?? 0,
          _ => null,
        };
    DateTime? date() => switch (r.field) {
          SmartField.added => s.dateAdded,
          SmartField.lastPlayed => ctx.stats[s.id]?.lastPlayed,
          _ => null,
        };

    final v = r.value.trim().toLowerCase();
    switch (r.op) {
      case SmartOp.contains:
        return text().toLowerCase().contains(v);
      case SmartOp.notContains:
        return !text().toLowerCase().contains(v);
      case SmartOp.equals:
        return r.field.kind == SmartKind.text
            ? text().toLowerCase() == v
            : choice().toLowerCase() == v || (r.field == SmartField.quality && v == 'lossless' && choice() == 'hiRes');
      case SmartOp.notEquals:
        return !(choice().toLowerCase() == v || (r.field == SmartField.quality && v == 'lossless' && choice() == 'hiRes'));
      case SmartOp.atLeast || SmartOp.atMost:
        final n = number();
        final limit = num.tryParse(v);
        if (n == null || limit == null) return false;
        return r.op == SmartOp.atLeast ? n >= limit : n <= limit;
      case SmartOp.within || SmartOp.notWithin:
        final days = int.tryParse(v);
        if (days == null) return false;
        final d = date();
        final inside = d != null && !d.isBefore(ctx.now.subtract(Duration(days: days)));
        return r.op == SmartOp.within ? inside : !inside;
      case SmartOp.never:
        return date() == null;
      case SmartOp.yes:
        return ctx.favorites.contains(s.id);
      case SmartOp.no:
        return !ctx.favorites.contains(s.id);
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'rules': [for (final r in rules) r.toJson()],
        'matchAll': matchAll,
        'sort': sort.name,
        'limit': limit,
      };

  static SmartPlaylist? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || name == null) return null;
    return SmartPlaylist(
      id: id,
      name: name,
      rules: [
        for (final r in (j['rules'] as List? ?? const []).cast<Map<String, dynamic>>())
          if (SmartRule.fromJson(r) case final rule?) rule,
      ],
      matchAll: j['matchAll'] as bool? ?? true,
      sort: SmartSort.values.asNameMap()[j['sort']] ?? SmartSort.mostPlayed,
      limit: (j['limit'] as num?)?.toInt(),
    );
  }

  static String encodeAll(List<SmartPlaylist> lists) => jsonEncode([for (final l in lists) l.toJson()]);

  static List<SmartPlaylist> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          if (fromJson(j) case final l?) l,
      ];
    } catch (_) {
      return const [];
    }
  }

  static const builtIns = [
    SmartPlaylist(
      id: 'b_lossless',
      name: 'Lossless',
      rules: [SmartRule(SmartField.quality, SmartOp.equals, 'lossless')],
      sort: SmartSort.artist,
      builtIn: true,
    ),
    SmartPlaylist(
      id: 'b_hires',
      name: 'Hi-Res',
      rules: [SmartRule(SmartField.quality, SmartOp.equals, 'hiRes')],
      sort: SmartSort.artist,
      builtIn: true,
    ),
    SmartPlaylist(
      id: 'b_most',
      name: 'Most played',
      rules: [SmartRule(SmartField.plays, SmartOp.atLeast, '1')],
      limit: 50,
      builtIn: true,
    ),
    SmartPlaylist(
      id: 'b_forgotten',
      name: 'Not played in 30 days',
      rules: [
        SmartRule(SmartField.plays, SmartOp.atLeast, '1'),
        SmartRule(SmartField.lastPlayed, SmartOp.notWithin, '30'),
      ],
      sort: SmartSort.random,
      builtIn: true,
    ),
    SmartPlaylist(
      id: 'b_new',
      name: 'Added this week',
      rules: [SmartRule(SmartField.added, SmartOp.within, '7')],
      sort: SmartSort.recentlyAdded,
      builtIn: true,
    ),
    SmartPlaylist(
      id: 'b_never',
      name: 'Never played',
      rules: [SmartRule(SmartField.lastPlayed, SmartOp.never)],
      sort: SmartSort.random,
      builtIn: true,
    ),
  ];
}
