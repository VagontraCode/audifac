import 'song.dart';

/// Why a song counts as religious music (gospel, worship, louange…) for the
/// soirée filter. The sound can't tell: it's what the files say.
enum ReligiousReason { genre, words, artist, album, marked }

class ReligiousMatch {
  const ReligiousMatch(this.reason, this.why);

  final ReligiousReason reason;

  /// The genre, word, artist or album that matched.
  final String why;
}

/// Genre tags that mean religious music (matched inside the folded genre:
/// "Gospel & Worship", "Musique chrétienne", "Louange / Adoration"…).
const religiousGenres = [
  'gospel', 'christian', 'chretien', 'worship', 'praise', 'louange', 'adoration', 'religio', 'religieu', //
  'spiritual', 'spirituel', 'hymn', 'cantique', 'ccm', 'church', 'eglise', 'sacred', 'inspirational', 'evangeli', 'chorale',
];

/// Whole words in a title, album or artist. Words that party songs use too
/// ("God", "Oluwa", "Dieu" alone, "Lord") are left out: too many Afrobeats
/// and rumba songs would go.
const religiousWords = {
  'jesus', 'jesu', 'yesu', 'yezu', 'jezu', 'christ', 'kristo', 'seigneur', 'yahweh', 'yahve', 'jehovah', 'elohim', //
  'adonai', 'shaddai', 'messiah', 'messie', 'alleluia', 'alleluya', 'hallelujah', 'halleluyah', 'hosanna', 'hosana',
  'amen', 'psaume', 'psaumes', 'psalm', 'psalms', 'cantique', 'cantiques', 'louange', 'louanges', 'adoration',
  'worship', 'gospel', 'nzambe', 'nzambi', 'mungu', 'nkembo', 'olorun', 'chineke', 'eglise', 'evangile', 'pasteur',
  'pastor', 'chorale', 'choir', 'ministries', 'ministere',
};

/// Several words together.
const religiousPhrases = [
  'saint esprit', 'holy spirit', 'holy ghost', 'praise the lord', 'thank you lord', 'dieu est', 'gloire a dieu', //
  'fils de dieu', 'enfant de dieu', 'dieu tout puissant', 'tata nzambe', 'bwana yesu', 'praise and worship',
];

/// Lowercase, without accents, letters and digits only (one space between words).
String fold(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    final u = c.codeUnitAt(0);
    b.write((u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39) ? c : ' ');
  }
  return b.toString().split(' ').where((w) => w.isNotEmpty).join(' ');
}

/// What in [genre] or in the song's words looks religious, or null.
ReligiousMatch? religiousMatchOf(Song song, {String? genre}) {
  if (genre != null) {
    final g = fold(genre);
    for (final term in religiousGenres) {
      if (g.contains(term)) return ReligiousMatch(ReligiousReason.genre, genre.trim());
    }
  }
  for (final field in [song.title, song.album, song.artist]) {
    final text = fold(field);
    if (text.isEmpty) continue;
    for (final word in text.split(' ')) {
      if (religiousWords.contains(word)) return ReligiousMatch(ReligiousReason.words, word);
    }
    final spaced = ' $text ';
    for (final phrase in religiousPhrases) {
      if (spaced.contains(' $phrase ')) return ReligiousMatch(ReligiousReason.words, phrase);
    }
  }
  return null;
}

/// Religious songs among [songs], by [Song.key]: those whose genre or words
/// say so, those [marked] by the owner, then every song of an artist or
/// album when at least two and half of theirs match (a gospel singer's
/// songs don't all say "Jésus").
Map<String, ReligiousMatch> religiousSongs(
  Iterable<Song> songs, {
  String? Function(Song)? genreOf,
  Set<String> marked = const {},
}) {
  final out = <String, ReligiousMatch>{};
  for (final s in songs) {
    if (marked.contains(s.key)) {
      out[s.key] = const ReligiousMatch(ReligiousReason.marked, '');
    } else if (religiousMatchOf(s, genre: genreOf?.call(s)) case final m?) {
      out[s.key] = m;
    }
  }
  void spread(String? Function(Song) groupOf, ReligiousReason reason) {
    final groups = <String, List<Song>>{};
    for (final s in songs) {
      if (groupOf(s) case final g?) groups.putIfAbsent(g, () => []).add(s);
    }
    for (final group in groups.values) {
      final matched = group.where((s) => out.containsKey(s.key)).length;
      if (matched < 2 || matched * 2 < group.length) continue;
      final why = reason == ReligiousReason.artist ? group.first.artist : group.first.album;
      for (final s in group) {
        out.putIfAbsent(s.key, () => ReligiousMatch(reason, why));
      }
    }
  }

  spread((s) => s.artist == Song.unknownArtist ? null : s.artist.trim().toLowerCase(), ReligiousReason.artist);
  spread((s) => s.album == Song.unknownAlbum ? null : '${s.albumId}', ReligiousReason.album);
  return out;
}

/// The owner's switch and corrections (by [Song.key]).
class ReligiousFilter {
  const ReligiousFilter({this.on = false, this.keep = const {}, this.marked = const {}});

  final bool on;

  /// Matched, but kept in soirées.
  final Set<String> keep;

  /// Religious by the owner's word (what the tags and words miss).
  final Set<String> marked;

  ReligiousFilter copyWith({bool? on, Set<String>? keep, Set<String>? marked}) =>
      ReligiousFilter(on: on ?? this.on, keep: keep ?? this.keep, marked: marked ?? this.marked);

  Map<String, dynamic> toJson() => {'on': on, 'keep': keep.toList(), 'marked': marked.toList()};

  static ReligiousFilter fromJson(Map<String, dynamic> j) => ReligiousFilter(
        on: j['on'] == true,
        keep: {for (final k in (j['keep'] as List? ?? const [])) k as String},
        marked: {for (final k in (j['marked'] as List? ?? const [])) k as String},
      );
}
