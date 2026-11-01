import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/playlist.dart';
import '../../models/religious.dart';
import '../../models/soiree.dart';
import '../../providers/library_providers.dart';
import '../../providers/religious_provider.dart';
import '../../providers/soiree_plan_provider.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import 'soiree_screen.dart';

/// A new soirée from [source] only (a folder's or a playlist's menu).
Future<void> planSoireeFrom(BuildContext context, WidgetRef ref, String source) {
  ref.read(soireeProvider.notifier).startFrom({source});
  return SoireeScreen.open(context);
}

/// "Songs from": Whole library, or the sources' names.
String sourcesLabel(AppLocalizations l10n, Set<String> sources, List<Playlist> playlists) {
  if (sources.isEmpty) return l10n.wholeLibrary;
  final names = [
    for (final src in sources)
      if (src == SoireeSources.favorites)
        l10n.favorites
      else if (SoireeSources.playlistIdOf(src) case final id?)
        ...playlists.where((p) => p.id == id).map((p) => p.name)
      else if (SoireeSources.folderOf(src) case final f?)
        f.split('/').last,
  ];
  return names.isEmpty ? l10n.wholeLibrary : names.join(', ');
}

/// Pick the soirée's sources: Favourites, playlists, folders. Returns the
/// new set, or null when dismissed.
class SoireeSourcesSheet extends ConsumerStatefulWidget {
  const SoireeSourcesSheet({super.key, required this.initial});

  final Set<String> initial;

  static Future<Set<String>?> pick(BuildContext context, Set<String> initial) => showModalBottomSheet<Set<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => SoireeSourcesSheet(initial: initial),
  );

  @override
  ConsumerState<SoireeSourcesSheet> createState() => _SoireeSourcesSheetState();
}

class _SoireeSourcesSheetState extends ConsumerState<SoireeSourcesSheet> {
  late final _sources = {...widget.initial};

  void _toggle(String source, bool on) => setState(() => on ? _sources.add(source) : _sources.remove(source));

  Future<void> _addFolder() async {
    final path = await FolderPickerSheet.pick(context);
    if (path != null) _toggle(SoireeSources.folder(path), true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final playlists = ref.watch(playlistsProvider);
    final folders = [for (final s in _sources) ?SoireeSources.folderOf(s)]..sort();
    final heading = theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: palette.inkMuted);

    Widget check(String label, String source, {String? subtitle}) => CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      value: _sources.contains(source),
      onChanged: (v) => _toggle(source, v ?? false),
    );

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.chooseSources, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                FilledButton(onPressed: () => Navigator.pop(context, _sources), child: Text(l10n.ok)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(l10n.chooseSourcesHint, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
          ),
          Expanded(
            child: ListView(
              children: [
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(l10n.wholeLibrary, style: const TextStyle(fontWeight: FontWeight.w700)),
                  value: _sources.isEmpty,
                  onChanged: (_) => setState(_sources.clear),
                ),
                check(l10n.favorites, SoireeSources.favorites),
                if (playlists.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(l10n.playlistsTitle.toUpperCase(), style: heading),
                  ),
                for (final p in playlists) check(p.name, SoireeSources.playlist(p.id), subtitle: l10n.songs(p.songIds.length)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(l10n.foldersTitle.toUpperCase(), style: heading),
                ),
                for (final f in folders) check(f.split('/').last, SoireeSources.folder(f), subtitle: f),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: HugeIcon(icon: HugeIcons.strokeRoundedFolderAdd, color: palette.ink, size: 22),
                  title: Text(l10n.addFolder),
                  onTap: _addFolder,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Walk the folder tree and pick one (its subfolders come with it).
class FolderPickerSheet extends ConsumerStatefulWidget {
  const FolderPickerSheet({super.key});

  static Future<String?> pick(BuildContext context) => showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const FolderPickerSheet(),
  );

  @override
  ConsumerState<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<FolderPickerSheet> {
  final _path = <String>[];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final tree = ref.watch(folderTreeProvider);
    final here = _path.lastOrNull;
    final entries = here != null
        ? tree.foldersIn(here)
        : tree.roots.length == 1
        ? tree.foldersIn(tree.roots.single)
        : [for (final r in tree.roots) tree.entry(r)];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.back,
                  onPressed: here == null ? () => Navigator.pop(context) : () => setState(_path.removeLast),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 24),
                ),
                Expanded(
                  child: Text(
                    here == null ? l10n.foldersTitle : here.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (here != null) FilledButton(onPressed: () => Navigator.pop(context, here), child: Text(l10n.useThisFolder)),
              ],
            ),
          ),
          if (here != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${l10n.songs(tree.allUnder(here).length)} · $here',
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final e in entries)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, color: palette.ink, size: 22),
                    title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(l10n.songs(e.songCount)),
                    trailing: e.folderCount > 0
                        ? HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20)
                        : null,
                    onTap: () => setState(() => _path.add(e.path)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The songs "Leave out religious music" finds, each with why; untick to
/// keep one in. [show] returns whether what's left out changed.
class ReligiousCheckSheet extends ConsumerWidget {
  const ReligiousCheckSheet({super.key});

  static Future<bool> show(BuildContext context, WidgetRef ref) async {
    final before = ref.read(religiousLeftOutProvider);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const ReligiousCheckSheet(),
    );
    return !setEquals(before, ref.read(religiousLeftOutProvider));
  }

  static String reason(AppLocalizations l10n, ReligiousMatch m) => switch (m.reason) {
    ReligiousReason.genre => l10n.reasonGenreIs(m.why),
    ReligiousReason.words => l10n.reasonWordIs(m.why),
    ReligiousReason.artist => l10n.reasonArtistMost(m.why),
    ReligiousReason.album => l10n.reasonAlbumMost(m.why),
    ReligiousReason.marked => l10n.reasonMarkedByYou,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final matches = ref.watch(religiousSongsProvider);
    final keep = ref.watch(religiousFilterProvider.select((f) => f.keep));
    final songs = [
      for (final s in ref.watch(songsProvider))
        if (matches.containsKey(s.key)) s,
    ]..sort((a, b) => '${a.artist}\n${a.title}'.toLowerCase().compareTo('${b.artist}\n${b.title}'.toLowerCase()));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.religiousTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.ok)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(l10n.religiousHint, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                final out = !keep.contains(song.key);
                return CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  secondary: Artwork.song(song, size: 40, radius: 8),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${song.artist} · ${reason(l10n, matches[song.key]!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: out ? palette.inkMuted : palette.hiRes),
                  ),
                  value: out,
                  onChanged: (v) => ref.read(religiousFilterProvider.notifier).setLeftOut(song, v ?? false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
