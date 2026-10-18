import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/play_stats.dart';
import '../../models/song.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/stats_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/song_actions_sheet.dart';
import '../collection/collection_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Listening stats: time, plays, top songs / artists / albums for a range.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    final summary = ref.watch(statsSummaryProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    var section = 0;
    Widget animated(Widget child) => Entrance(index: section++, child: child);

    Widget title(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: Text(text, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        );

    final topSongs = summary.songs.take(10).toList();
    final maxPlays = topSongs.isEmpty ? 1 : topSongs.first.plays;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: EntranceScope(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 20, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.back,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
                    ),
                    Expanded(child: Text(context.l10n.yourStats, style: theme.textTheme.headlineLarge)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedButton<StatsRange>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: palette.ink,
                    selectedForegroundColor: palette.onInk,
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.line),
                  ),
                  segments: [for (final r in StatsRange.values) ButtonSegment(value: r, label: Text(context.l10n.statsRange(r)))],
                  selected: {range},
                  onSelectionChanged: (s) => ref.read(statsRangeProvider.notifier).set(s.first),
                ),
              ),
              if (summary.plays == 0 && summary.listened == Duration.zero)
                Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: EmptyState(
                    icon: HugeIcons.strokeRoundedChart,
                    title: context.l10n.nothingYet,
                    message: context.l10n.playCountRule,
                  ),
                )
              else ...[
                animated(Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Expanded(child: _Figure(value: _hours(summary.listened), label: context.l10n.listening)),
                      Expanded(child: _Figure(value: '${summary.plays}', label: context.l10n.playsWord(summary.plays))),
                      Expanded(
                        child: _Figure(
                          value: '${summary.activeDays}',
                          label: context.l10n.daysWord(summary.activeDays),
                        ),
                      ),
                    ],
                  ),
                )),
                if (topSongs.isNotEmpty) ...[
                  animated(title(context.l10n.topSongs)),
                  for (final (i, r) in topSongs.indexed)
                    animated(_SongRow(rank: i + 1, ranked: r, fraction: r.plays / maxPlays, all: topSongs)),
                ],
                if (summary.artists.isNotEmpty) ...[
                  animated(title(context.l10n.topArtists)),
                  for (final (i, r) in summary.artists.take(5).indexed)
                    animated(ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: SizedBox(width: 28, child: Text('${i + 1}', style: theme.textTheme.titleMedium)),
                      title: Text(r.item, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${context.l10n.plays(r.plays)} · ${formatTotalDuration(r.listened)}'),
                      onTap: () {
                        final artist = ref.read(artistsProvider).where((a) => a.name == r.item).firstOrNull;
                        if (artist != null) CollectionScreen.openArtist(context, artist);
                      },
                    )),
                ],
                if (summary.albums.isNotEmpty) ...[
                  animated(title(context.l10n.topAlbums)),
                  animated(SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: summary.albums.take(10).length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final r = summary.albums[i];
                        return GestureDetector(
                          onTap: () {
                            final album = ref.read(albumsProvider).where((a) => a.id == r.item.albumId).firstOrNull;
                            if (album != null) CollectionScreen.openAlbum(context, album);
                          },
                          child: SizedBox(
                            width: 130,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Artwork.song(r.item, size: 130, radius: 16),
                                const SizedBox(height: 8),
                                Text(r.item.album,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink)),
                                Text(context.l10n.plays(r.plays),
                                    style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _hours(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inMinutes / 60;
    return h < 10 ? '${h.toStringAsFixed(1)} h' : '${h.round()} h';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: context.palette.inkMuted)),
      ],
    );
  }
}

class _SongRow extends ConsumerWidget {
  const _SongRow({required this.rank, required this.ranked, required this.fraction, required this.all});

  final int rank;
  final Ranked<Song> ranked;
  final double fraction;
  final List<Ranked<Song>> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final song = ranked.item;
    return InkWell(
      onTap: () => ref.read(audioHandlerProvider).playSongs([for (final r in all) r.item], startIndex: rank - 1),
      onLongPress: () => SongActionsSheet.show(context, song),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text('$rank', style: theme.textTheme.titleMedium)),
            Artwork.song(song, size: 48, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink)),
                  Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 3,
                        color: palette.ink,
                        backgroundColor: palette.line,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${ranked.plays}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
