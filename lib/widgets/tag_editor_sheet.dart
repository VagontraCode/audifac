import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n.dart';
import '../models/audio_info.dart';
import '../models/song.dart';
import '../models/tag_edit.dart';
import '../providers/audio_info_providers.dart';
import '../providers/library_providers.dart';

/// Song menu → Edit tags. Corrections are kept in the app's database; the
/// file itself is never written. A cleared field goes back to the file's tag.
class TagEditorSheet extends ConsumerStatefulWidget {
  const TagEditorSheet({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: TagEditorSheet(song: song),
        ),
      );

  @override
  ConsumerState<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends ConsumerState<TagEditorSheet> {
  /// The song as its file tags it (no edits).
  late final Song _file = (ref.read(libraryProvider).value ?? const <Song>[])
      .firstWhere((s) => s.id == widget.song.id, orElse: () => widget.song);
  late final AudioInfo _fileInfo = ref.read(audioInfoProvider)[_file.location] ?? AudioInfo.guess(_file);
  late final TagEdit _edit = ref.read(tagEditsProvider)[_file.key] ?? const TagEdit();

  late final _title = TextEditingController(text: _edit.title ?? _file.title);
  late final _artist = TextEditingController(text: _edit.artist ?? _file.artist);
  late final _album = TextEditingController(text: _edit.album ?? _file.album);
  late final _albumArtist = TextEditingController(text: _edit.albumArtist ?? _fileInfo.albumArtist ?? '');
  late final _genre = TextEditingController(text: _edit.genre ?? _fileInfo.genre ?? '');
  late final _year = TextEditingController(text: _edit.year ?? _fileInfo.year ?? '');
  late final _track = TextEditingController(text: _trackText(_edit.track ?? _file.trackNumber));

  static String _trackText(int track) => track % 1000 == 0 ? '' : '${track % 1000}';

  List<TextEditingController> get _all => [_title, _artist, _album, _albumArtist, _genre, _year, _track];

  @override
  void initState() {
    super.initState();
    // "In the file: …" appears as soon as a field differs.
    for (final c in _all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(TagEdit edit) async {
    await ref.read(tagEditsProvider.notifier).set(_file, edit);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;

    Widget field(TextEditingController c, String label, String? fileValue, {bool number = false, bool compact = false}) {
      final original = (fileValue ?? '').trim();
      final edited = c.text.trim().isNotEmpty && c.text.trim() != original;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: label,
            // A blank field means the file's tag.
            hintText: original.isEmpty ? null : original,
            // What the file says, next to a correction.
            helperText: edited && original.isNotEmpty && !compact ? l10n.inFile(original) : null,
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.editTags, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(l10n.editTagsHint, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
            const SizedBox(height: 8),
            field(_title, l10n.fieldTitle, _file.title),
            field(_artist, l10n.fieldArtist, _file.artist),
            field(_album, l10n.fieldAlbum, _file.album),
            field(_albumArtist, l10n.fieldAlbumArtist, _fileInfo.albumArtist),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: field(_genre, l10n.fieldGenre, _fileInfo.genre, compact: true)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: field(_year, l10n.fieldYear, _fileInfo.year, number: true, compact: true)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: field(_track, l10n.fieldTrack, _trackText(_file.trackNumber), number: true, compact: true)),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => _save(
                TagEdit.diff(
                  file: _file,
                  fileInfo: _fileInfo,
                  title: _title.text,
                  artist: _artist.text,
                  album: _album.text,
                  albumArtist: _albumArtist.text,
                  genre: _genre.text,
                  year: _year.text,
                  track: _track.text,
                ),
              ),
              child: Text(l10n.save),
            ),
            if (!_edit.isEmpty)
              TextButton(onPressed: () => _save(const TagEdit()), child: Text(l10n.restoreFileTags)),
          ],
        ),
      ),
    );
  }
}
