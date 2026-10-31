import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/soiree.dart';
import '../../models/song.dart';
import '../../models/song_features.dart';
import '../../providers/library_providers.dart';
import '../../providers/soiree_plan_provider.dart';
import '../../providers/soiree_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/playlist_dialogs.dart';
import 'soiree_play.dart';

/// Library → Playlists → Plan a soirée: an evening from the phone's songs,
/// shaped by a curve, that the owner adjusts before (and while) it plays.
class SoireeScreen extends ConsumerStatefulWidget {
  const SoireeScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SoireeScreen()));

  @override
  ConsumerState<SoireeScreen> createState() => _SoireeScreenState();
}

class _SoireeScreenState extends ConsumerState<SoireeScreen> {
  @override
  void initState() {
    super.initState();
    // The analysis starts with the first soirée and keeps the library current.
    ref.read(songFeaturesProvider.notifier).enable();
    if (ref.read(soireeProvider).plan.isEmpty) {
      Future.microtask(() => ref.read(soireeProvider.notifier).rebuild());
    }
    // While the analysis is still going, newly analysed songs join the plan:
    // at once while it doesn't fill the evening, then each time ~10 % more
    // of the library is known, and when the analysis ends — unless the
    // owner has locked songs (their work is kept).
    _builtWith = ref.read(soireeFeaturesProvider).length;
    void refill() {
      final s = ref.read(soireeProvider);
      final known = ref.read(soireeFeaturesProvider).length;
      final running = ref.read(rhythmStatusProvider).running;
      if (s.building || s.live || s.plan.any((x) => x.locked) || known == _builtWith) return;
      final short = s.total < s.length * 0.9;
      final grown = known >= _builtWith * 1.1 + 5;
      if (!short && !grown && running) return;
      _refill?.cancel();
      _refill = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        _builtWith = ref.read(soireeFeaturesProvider).length;
        ref.read(soireeProvider.notifier).rebuild();
      });
    }

    _features = ref.listenManual(soireeFeaturesProvider, (_, _) => refill());
    _status = ref.listenManual(rhythmStatusProvider, (_, _) => refill());
  }

  ProviderSubscription<Map<String, SongFeatures>>? _features;
  ProviderSubscription<RhythmStatus>? _status;
  Timer? _refill;
  var _builtWith = 0;

  @override
  void dispose() {
    _refill?.cancel();
    _features?.close();
    _status?.close();
    super.dispose();
  }

  static String shapeName(AppLocalizations l10n, SoireeShape s) => switch (s) {
        SoireeShape.houseParty => l10n.shapeHouseParty,
        SoireeShape.dinnerToDance => l10n.shapeDinnerToDance,
        SoireeShape.straightToTheFloor => l10n.shapeStraightToFloor,
        SoireeShape.withCoolDown => l10n.shapeWithCoolDown,
        SoireeShape.windDown => l10n.shapeWindDown,
      };

  Future<void> _saveAsPlaylist(SoireeState s) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final name = await showPlaylistNameDialog(context, initial: l10n.soireeTitle);
    if (name == null) return;
    await ref.read(playlistsProvider.notifier).create(name, songIds: [for (final slot in s.plan) slot.song.id]);
    messenger.showSnackBar(SnackBar(content: Text(l10n.savedAs(name))));
  }

  Future<void> _swap(int index) async {
    final notifier = ref.read(soireeProvider.notifier);
    final slot = ref.read(soireeProvider).plan[index];
    final alts = notifier.alternatives(index);
    final features = ref.read(soireeFeaturesProvider);
    final song = await showModalBottomSheet<Song>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(context.l10n.insteadOf(slot.song.title), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (alts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(context.l10n.noAlternatives),
              ),
            for (final c in alts)
              ListTile(
                leading: Artwork.song(c.song, size: 44, radius: 8),
                title: Text(c.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_details(context, c.song, features[c.song.key]?.bpm)),
                onTap: () => Navigator.pop(context, c.song),
              ),
          ],
        ),
      ),
    );
    if (song != null) notifier.swap(index, song);
  }

  Future<void> _addSong() async {
    final s = ref.read(soireeProvider);
    final features = ref.read(soireeFeaturesProvider);
    final inPlan = {for (final slot in s.plan) slot.song.id};
    final songs = [
      for (final song in ref.read(songsProvider))
        if (features.containsKey(song.key) && !inPlan.contains(song.id)) song,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final picked = await showModalBottomSheet<Song>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _SongPicker(songs: songs),
    );
    if (picked != null) ref.read(soireeProvider.notifier).add(picked);
  }

  String _details(BuildContext context, Song song, double? bpm) => [
        song.artist,
        if (bpm != null && bpm > 0) '${bpm.round()} BPM',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final s = ref.watch(soireeProvider);
    final notifier = ref.read(soireeProvider.notifier);
    final status = ref.watch(rhythmStatusProvider);
    final features = ref.watch(soireeFeaturesProvider);
    final playlists = ref.watch(playlistsProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted);

    Widget chips<T>(List<T> values, T? selected, String Function(T) label, void Function(T) onTap) => SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final v in values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => onTap(v)),
                ),
            ],
          ),
        );

    final header = Column(
      key: const ValueKey('header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.running || features.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              status.running ? l10n.soireeAnalysingBanner(status.done, status.total) : l10n.soireeNothingYet,
              style: muted,
            ),
          ),
        chips([1, 2, 3, 4, 5], s.length.inHours, (h) => l10n.hoursShort(h), (h) => notifier.setLength(Duration(hours: h))),
        const SizedBox(height: 6),
        chips(SoireeShape.values, s.shape, (v) => shapeName(l10n, v), notifier.setShape),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _CurveEditor(state: s, onDrag: notifier.setPoint),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(l10n.curveHint, style: muted),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
          child: Row(
            children: [
              Text(l10n.songsFrom, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int?>(
                  isExpanded: true,
                  value: playlists.any((p) => p.id == s.playlistId) ? s.playlistId : null,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l10n.wholeLibrary)),
                    for (final p in playlists) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: notifier.setPlaylist,
                ),
              ),
            ],
          ),
        ),
        if (!s.building && s.plan.isNotEmpty && s.total < s.length * 0.9)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l10n.soireeTooShort(formatTotalDuration(s.total)), style: muted?.copyWith(color: palette.hiRes)),
          ),
        if (s.building) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.soireeTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: l10n.regenerate,
            onPressed: s.building ? null : () => notifier.rebuild(newSeed: true),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedShuffle, color: palette.ink, size: 24),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'add' => _addSong(),
              _ => _saveAsPlaylist(s),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'add', child: Text(l10n.addSong)),
              PopupMenuItem(value: 'save', enabled: s.plan.isNotEmpty, child: Text(l10n.saveAsPlaylist)),
            ],
          ),
        ],
      ),
      body: ReorderableListView.builder(
        header: header,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: s.plan.length,
        onReorderItem: notifier.move,
        itemBuilder: (context, i) {
          final slot = s.plan[i];
          final f = features[slot.song.key];
          final fits = (slot.level - slot.target).abs() <= 20;
          return ListTile(
            key: ValueKey('${slot.song.id}-$i'),
            contentPadding: const EdgeInsets.only(left: 20, right: 4),
            leading: Artwork.song(slot.song, size: 44, radius: 8),
            title: Text(slot.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${_details(context, slot.song, f?.bpm)} · ${l10n.levelOf(slot.level.round())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fits ? palette.inkMuted : palette.hiRes),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: slot.locked ? l10n.unlock : l10n.lock,
                  onPressed: () => notifier.toggleLock(i),
                  icon: HugeIcon(
                    icon: slot.locked ? HugeIcons.strokeRoundedSquareLock02 : HugeIcons.strokeRoundedSquareUnlock02,
                    color: slot.locked ? palette.ink : palette.inkMuted,
                    size: 20,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'swap' ? _swap(i) : notifier.remove(i),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'swap', child: Text(l10n.swap)),
                    PopupMenuItem(value: 'remove', child: Text(l10n.remove)),
                  ],
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: HugeIcon(icon: HugeIcons.strokeRoundedDragDropVertical, color: palette.inkMuted, size: 20),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.soireeSummary(s.plan.length, formatTotalDuration(s.total)),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: s.plan.isEmpty || s.building ? null : () => playSoiree(context, ref),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedPlay, color: palette.onInk, size: 20),
                label: Text(l10n.playSoiree),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The evening's curve, each song as a dot at its level, and the curve's
/// points to drag up or down.
class _CurveEditor extends StatefulWidget {
  const _CurveEditor({required this.state, required this.onDrag});

  final SoireeState state;
  final void Function(int index, double level, {bool done}) onDrag;

  @override
  State<_CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<_CurveEditor> {
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        const height = 140.0;
        final width = box.maxWidth;
        Offset pointAt((double, double) p) => Offset(p.$1 * width, height - p.$2 / 100 * height);
        return GestureDetector(
          // Vertical drags (not pans): they win against the list's scrolling.
          onVerticalDragStart: (d) {
            final points = widget.state.curve.points;
            var best = 0;
            var bestDistance = double.infinity;
            for (final (i, p) in points.indexed) {
              final distance = (pointAt(p) - d.localPosition).distance;
              if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
              }
            }
            _dragging = bestDistance < 48 ? best : null;
          },
          onVerticalDragUpdate: (d) {
            final i = _dragging;
            if (i == null) return;
            widget.onDrag(i, (height - d.localPosition.dy) / height * 100);
          },
          onVerticalDragEnd: (_) {
            final i = _dragging;
            if (i == null) return;
            widget.onDrag(i, widget.state.curve.points[i].$2, done: true);
            _dragging = null;
          },
          child: CustomPaint(
            size: Size(width, height),
            painter: _CurvePainter(
              state: widget.state,
              line: palette.ink,
              dot: palette.hiRes,
              grid: palette.line,
              dragging: _dragging,
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.state, required this.line, required this.dot, required this.grid, this.dragging});

  final SoireeState state;
  final Color line;
  final Color dot;
  final Color grid;
  final int? dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(0, size.height * y), Offset(size.width, size.height * y), g);
    }
    // The songs: a dot at each song's middle, at its level.
    final total = state.length.inMilliseconds;
    if (total > 0) {
      var elapsed = 0;
      final p = Paint()..color = dot.withValues(alpha: 0.85);
      for (final s in state.plan) {
        final mid = (elapsed + s.song.duration.inMilliseconds / 2) / total;
        elapsed += s.song.duration.inMilliseconds;
        if (mid > 1.05) break;
        canvas.drawCircle(Offset(mid.clamp(0, 1) * size.width, size.height - s.level / 100 * size.height), 3.5, p);
      }
    }
    // The curve.
    final path = Path();
    for (var i = 0; i <= 100; i++) {
      final t = i / 100;
      final o = Offset(t * size.width, size.height - state.curve.at(t) / 100 * size.height);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    for (final (i, pt) in state.curve.points.indexed) {
      final o = Offset(pt.$1 * size.width, size.height - pt.$2 / 100 * size.height);
      canvas.drawCircle(o, i == dragging ? 11 : 8, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}

class _SongPicker extends StatefulWidget {
  const _SongPicker({required this.songs});

  final List<Song> songs;

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = widget.songs.where((s) => q.isEmpty || '${s.title} ${s.artist}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(hintText: context.l10n.addSong, prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => ListTile(
                leading: Artwork.song(shown[i], size: 40, radius: 8),
                title: Text(shown[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(shown[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, shown[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
