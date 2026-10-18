import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../providers/library_providers.dart';
import '../providers/lyrics_provider.dart';
import '../providers/player_providers.dart';
import 'empty_state.dart';
import '../l10n/l10n.dart';

/// The current song's lyrics. Synced (LRC) lyrics follow playback — the
/// current line lit, tap any line to jump there.
class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const LyricsSheet(),
      );

  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  final _scroll = ScrollController();
  final _keys = <GlobalKey>[];
  int _current = -1;

  /// After the user scrolls by hand, stop following for a moment.
  DateTime _manualUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index == _current) return;
    _current = index;
    if (index < 0 || index >= _keys.length || DateTime.now().isBefore(_manualUntil)) return;
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  Future<void> _attach(Song song) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notLyrics = context.l10n.notALyricsFile;
    try {
      final doc = await ref.read(mediaLibraryProvider).openTextDocument(anyType: true);
      if (doc == null) return;
      await setPickedLyrics(ref, song, doc.text);
    } on PlatformException {
      messenger?.showSnackBar(SnackBar(content: Text(notLyrics)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    final theme = Theme.of(context);
    final palette = context.palette;
    final lyrics = song == null ? const AsyncValue<Lyrics?>.data(null) : ref.watch(lyricsProvider(song));
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final data = lyrics.value;
    final index = data?.indexAt(position + const Duration(milliseconds: 200)) ?? -1;
    if (data != null) {
      while (_keys.length < data.lines.length) {
        _keys.add(GlobalKey());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(index);
      });
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.lyrics, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        if (song != null)
                          Text(
                            '${song.title} · ${song.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                          ),
                      ],
                    ),
                  ),
                  if (song != null)
                    PopupMenuButton<String>(
                      tooltip: context.l10n.lyricsOptions,
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 22),
                      onSelected: (v) => v == 'attach' ? _attach(song) : setPickedLyrics(ref, song, null),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'attach', child: Text(context.l10n.useLyricsFile)),
                        if (data?.source == LyricsSource.picked)
                          PopupMenuItem(value: 'remove', child: Text(context.l10n.removeAttachedFile)),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (lyrics) {
                AsyncLoading() => const Center(child: CircularProgressIndicator()),
                _ when data == null || song == null => Center(
                    child: SingleChildScrollView(
                      child: EmptyState(
                        icon: HugeIcons.strokeRoundedQuoteDown,
                        title: context.l10n.noLyrics,
                        message: context.l10n.noLyricsHint,
                        actionLabel: song == null ? null : context.l10n.chooseLyricsFile,
                        onAction: song == null ? null : () => _attach(song),
                      ),
                    ),
                  ),
                _ => NotificationListener<UserScrollNotification>(
                    onNotification: (_) {
                      _manualUntil = DateTime.now().add(const Duration(seconds: 4));
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, line) in data.lines.indexed)
                            _Line(
                              key: _keys[i],
                              text: line.text,
                              synced: data.synced,
                              state: !data.synced ? 0 : (i == index ? 1 : (i < index ? -1 : 0)),
                              onTap: line.time == null ? null : () => ref.read(audioHandlerProvider).seek(line.time!),
                            ),
                        ],
                      ),
                    ),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.text, required this.synced, required this.state, this.onTap});

  final String text;
  final bool synced;

  /// −1 sung, 0 upcoming (or unsynced), 1 current.
  final int state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = Theme.of(context).textTheme;
    final style = synced
        ? base.titleLarge!.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: switch (state) {
              1 => palette.ink,
              -1 => palette.inkMuted.withValues(alpha: 0.75),
              _ => palette.inkMuted.withValues(alpha: 0.45),
            },
          )
        : base.bodyLarge!.copyWith(height: 1.5, color: palette.ink);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: synced ? 8 : 1),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: style,
          child: AnimatedScale(
            scale: state == 1 ? 1.0 : 0.96,
            alignment: Alignment.centerLeft,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: Text(text.isEmpty ? (synced ? '♪' : ' ') : text),
          ),
        ),
      ),
    );
  }
}
