import 'song.dart';
import 'song_source.dart';

/// What a sound-preset rule is attached to, most specific first.
enum EqScope {
  song('This song'),
  album('This album'),
  artist('This artist'),
  genre('This genre'),
  source('This source');

  const EqScope(this.label);
  final String label;
}

class EqRule {
  const EqRule({required this.scope, required this.key, required this.label, required this.presetId});

  final EqScope scope;

  /// Song id, album id, artist name, lower-cased genre or source category.
  final String key;

  /// Human-readable target, e.g. the album title.
  final String label;
  final String presetId;

  Map<String, Object> toJson() => {'scope': scope.name, 'key': key, 'label': label, 'preset': presetId};

  factory EqRule.fromJson(Map<String, dynamic> j) => EqRule(
        scope: EqScope.values.firstWhere((s) => s.name == j['scope'], orElse: () => EqScope.song),
        key: j['key'] as String,
        label: j['label'] as String? ?? '',
        presetId: j['preset'] as String,
      );

  /// Rule key [scope] would use for [song] (null when not applicable, e.g. no genre).
  static String? keyFor(EqScope scope, Song song, {String? genre}) => switch (scope) {
        EqScope.song => '${song.id}',
        EqScope.album => '${song.albumId}',
        EqScope.artist => song.artist == Song.unknownArtist ? null : song.artist,
        EqScope.genre => (genre == null || genre.trim().isEmpty) ? null : genre.trim().toLowerCase(),
        EqScope.source => SongSource.of(song).category.name,
      };

  static String labelFor(EqScope scope, Song song, {String? genre}) => switch (scope) {
        EqScope.song => song.title,
        EqScope.album => song.album,
        EqScope.artist => song.artist,
        EqScope.genre => genre?.trim() ?? '',
        EqScope.source => SongSource.of(song).category.label,
      };
}

/// Why a sound preset is active.
enum EqReason {
  queue('this session'),
  song('song'),
  album('album'),
  artist('artist'),
  genre('genre'),
  source('source'),
  defaultPreset('default');

  const EqReason(this.label);
  final String label;

  static EqReason of(EqScope scope) => switch (scope) {
        EqScope.song => song,
        EqScope.album => album,
        EqScope.artist => artist,
        EqScope.genre => genre,
        EqScope.source => source,
      };
}

/// Picks the sound preset for [song]: queue choice → song → album → artist →
/// genre → source → default. [isValid] filters out deleted presets.
({String presetId, EqReason reason}) resolveSoundPreset({
  required Song? song,
  required String? genre,
  required List<EqRule> rules,
  required String? queueOverride,
  required String defaultPresetId,
  required bool Function(String id) isValid,
}) {
  if (queueOverride != null && isValid(queueOverride)) {
    return (presetId: queueOverride, reason: EqReason.queue);
  }
  if (song != null) {
    final rule = matchingRule(song: song, genre: genre, rules: rules, isValid: isValid);
    if (rule != null) return (presetId: rule.presetId, reason: EqReason.of(rule.scope));
  }
  return (presetId: defaultPresetId, reason: EqReason.defaultPreset);
}

/// The most specific rule that applies to [song], if any.
EqRule? matchingRule({
  required Song song,
  required String? genre,
  required List<EqRule> rules,
  required bool Function(String id) isValid,
}) {
  for (final scope in EqScope.values) {
    final key = EqRule.keyFor(scope, song, genre: genre);
    if (key == null) continue;
    for (final r in rules) {
      if (r.scope == scope && r.key == key && isValid(r.presetId)) return r;
    }
  }
  return null;
}
