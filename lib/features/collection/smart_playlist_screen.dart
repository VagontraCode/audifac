import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/smart_playlist.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/smart_playlist_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/song_tile.dart';
import 'collection_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Cover for a smart playlist: a gradient with a sparkle, distinct per list.
class SmartCover extends StatelessWidget {
  const SmartCover({super.key, required this.list, required this.size, this.radius = 12});

  final SmartPlaylist list;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hue = (list.id.hashCode % 360).abs().toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.45, 0.42).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.22).toColor(),
          ],
        ),
      ),
      child: Center(child: HugeIcon(icon: HugeIcons.strokeRoundedMagicWand01, color: Colors.white, size: size * 0.4)),
    );
  }
}

/// A smart playlist's songs (always up to date), with edit / delete.
class SmartPlaylistScreen extends ConsumerWidget {
  const SmartPlaylistScreen({super.key, required this.id});

  final String id;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SmartPlaylistScreen(id: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(smartPlaylistProvider(id));
    if (list == null) return const Scaffold(body: SizedBox.shrink());
    final songs = ref.watch(smartSongsProvider(id));
    final handler = ref.read(audioHandlerProvider);
    final palette = context.palette;
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);

    Future<void> edit() async {
      final edited = await SmartPlaylistEditor.open(
        context,
        list.builtIn ? list.copyWith(id: SmartPlaylistsNotifier.newId(), name: context.l10n.smartCopyName(context.l10n.smartName(list)), builtIn: false) : list,
      );
      if (edited == null) return;
      ref.read(smartPlaylistsProvider.notifier).save(edited);
      if (list.builtIn && context.mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => SmartPlaylistScreen(id: edited.id)));
      }
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CollectionAppBar(
            actions: [
              PopupMenuButton<String>(
                tooltip: context.l10n.smartOptions,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 24),
                onSelected: (v) {
                  if (v == 'edit') edit();
                  if (v == 'delete') {
                    Navigator.of(context).pop();
                    ref.read(smartPlaylistsProvider.notifier).delete(id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(list.builtIn ? context.l10n.editCopy : context.l10n.editRules)),
                  if (!list.builtIn) PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: CollectionHeader(
              cover: SmartCover(list: list, size: 210, radius: 22),
              title: context.l10n.smartName(list),
              subtitle: songs.isEmpty
                  ? context.l10n.smartDescribe(list)
                  : '${context.l10n.songs(songs.length)} · ${formatTotalDuration(total)}\n${context.l10n.smartDescribe(list)}',
              onPlay: songs.isEmpty ? null : () => handler.playSongs(songs),
              onShuffle: songs.isEmpty ? null : () => handler.playSongs(songs, shuffle: true),
            ),
          ),
          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: HugeIcons.strokeRoundedMagicWand01,
                  title: context.l10n.noMatchingSongs,
                  message: context.l10n.noMatchingSongsHint,
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                showAlbum: true,
                onTap: () => handler.playSongs(songs, startIndex: i),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// Name, rules, sort and limit of a smart playlist. Pops the edited list.
class SmartPlaylistEditor extends ConsumerStatefulWidget {
  const SmartPlaylistEditor({super.key, required this.initial});

  final SmartPlaylist initial;

  static Future<SmartPlaylist?> open(BuildContext context, SmartPlaylist initial) => Navigator.of(context)
      .push<SmartPlaylist>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SmartPlaylistEditor(initial: initial)));

  static SmartPlaylist blank() => SmartPlaylist(
        id: SmartPlaylistsNotifier.newId(),
        name: 'My smart playlist',
        rules: [SmartRule.forField(SmartField.quality)],
        sort: SmartSort.artist,
      );

  @override
  ConsumerState<SmartPlaylistEditor> createState() => _SmartPlaylistEditorState();
}

class _SmartPlaylistEditorState extends ConsumerState<SmartPlaylistEditor> {
  late SmartPlaylist list = widget.initial;
  late final name = TextEditingController(text: widget.initial.name);

  // Stable widget keys per rule, so removing one doesn't shift the others' text.
  var _nextKey = 0;
  late final _keys = [for (final _ in widget.initial.rules) _nextKey++];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _setRule(int i, SmartRule rule) => setState(() => list = list.copyWith(rules: [...list.rules]..[i] = rule));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final codecs = (ref.watch(filterCountsProvider).codecs.keys.toList()..sort());
    final preview = list.songsFrom(ref.watch(songsProvider), ref.watch(smartContextProvider));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.smartPlaylist),
        actions: [
          TextButton(
            onPressed: () {
              final n = name.text.trim();
              Navigator.of(context).pop(list.copyWith(name: n.isEmpty ? context.l10n.smartPlaylist : n));
            },
            child: Text(context.l10n.save, style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(controller: name, decoration: InputDecoration(labelText: context.l10n.name)),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(context.l10n.match, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: palette.ink,
                  selectedForegroundColor: palette.onInk,
                  foregroundColor: palette.ink,
                  side: BorderSide(color: palette.line),
                ),
                segments: [
                  ButtonSegment(value: true, label: Text(context.l10n.allRules)),
                  ButtonSegment(value: false, label: Text(context.l10n.anyRule)),
                ],
                selected: {list.matchAll},
                onSelectionChanged: (s) => setState(() => list = list.copyWith(matchAll: s.first)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, rule) in list.rules.indexed)
            _RuleCard(
              key: ValueKey('rule-${_keys[i]}-${rule.field.name}'),
              rule: rule,
              codecs: codecs,
              onChanged: (r) => _setRule(i, r),
              onRemove: () => setState(() {
                list = list.copyWith(rules: [...list.rules]..removeAt(i));
                _keys.removeAt(i);
              }),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                list = list.copyWith(rules: [...list.rules, SmartRule.forField(SmartField.artist)]);
                _keys.add(_nextKey++);
              }),
              icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 20),
              label: Text(context.l10n.addRule),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SmartSort>(
                  initialValue: list.sort,
                  decoration: InputDecoration(labelText: context.l10n.order),
                  items: [for (final s in SmartSort.values) DropdownMenuItem(value: s, child: Text(context.l10n.smartSort(s)))],
                  onChanged: (s) => setState(() => list = list.copyWith(sort: s)),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: list.limit?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.l10n.limit, hintText: context.l10n.none),
                  onChanged: (v) => setState(() => list = list.copyWith(limit: () => int.tryParse(v))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            preview.isEmpty ? context.l10n.noSongsMatchYet : context.l10n.songsMatchNow(preview.length),
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({super.key, required this.rule, required this.codecs, required this.onChanged, required this.onRemove});

  final SmartRule rule;
  final List<String> codecs;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final choices = rule.field.choices(codecs);
    final ops = rule.field.ops;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SmartField>(
                  initialValue: rule.field,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.l10n.field, border: InputBorder.none),
                  items: [for (final f in SmartField.values) DropdownMenuItem(value: f, child: Text(context.l10n.smartField(f)))],
                  onChanged: (f) => f == null ? null : onChanged(SmartRule.forField(f)),
                ),
              ),
              IconButton(
                tooltip: context.l10n.removeRule,
                onPressed: onRemove,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: palette.inkMuted, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SmartOp>(
                  initialValue: ops.contains(rule.op) ? rule.op : ops.first,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [for (final o in ops) DropdownMenuItem(value: o, child: Text(context.l10n.smartOp(o)))],
                  onChanged: (o) => o == null ? null : onChanged(rule.copyWith(op: o)),
                ),
              ),
              if (rule.op.needsValue) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: rule.field.kind == SmartKind.choice
                      ? DropdownButtonFormField<String>(
                          initialValue: choices.any((c) => c.$1 == rule.value) ? rule.value : null,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [for (final c in choices) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
                          onChanged: (v) => onChanged(rule.copyWith(value: v ?? '')),
                        )
                      : TextFormField(
                          initialValue: rule.value,
                          keyboardType: rule.field.kind == SmartKind.text ? TextInputType.text : TextInputType.number,
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) => onChanged(rule.copyWith(value: v)),
                        ),
                ),
              ],
              const SizedBox(width: 10),
            ],
          ),
        ],
      ),
    );
  }
}
