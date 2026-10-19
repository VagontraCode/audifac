import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/artwork_colors.dart';
import '../../models/eq.dart';
import '../../providers/eq_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/seek_bar.dart';
import '../../widgets/lyrics_sheet.dart';
import '../../widgets/cast_sheet.dart';
import '../../providers/cast_provider.dart';
import '../../cast/cast_target.dart';
import '../../core/format.dart';
import '../../widgets/signal_sheet.dart';
import '../../widgets/song_labels.dart';
import '../../providers/audio_info_providers.dart';
import '../../widgets/sleep_timer_sheet.dart';
import '../../widgets/spoken_widgets.dart';
import '../../providers/spoken_providers.dart';
import '../../widgets/song_actions_sheet.dart';
import '../equalizer/equalizer_screen.dart';
import '../equalizer/quick_eq_sheet.dart';
import 'queue_sheet.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  /// Shared between the mini player and this screen so the artwork flies
  /// between them.
  static const artworkHeroTag = 'now-playing-artwork';

  /// True while this screen fully covers the app (opened, not being dragged
  /// or closing): the app shell mutes its animations meanwhile.
  static final coversApp = ValueNotifier<bool>(false);

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        // Non-opaque so the app stays visible behind while dragging to close.
        opaque: false,
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const PlayerScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with SingleTickerProviderStateMixin {
  /// How far the page has been dragged down, in pixels.
  double _drag = 0;
  double _settleFrom = 0;
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
    ..addListener(() {
      setState(() => _drag = _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value)));
      if (_settle.isCompleted) _updateCover();
    });

  /// Last known artwork seed; kept while the next track's color loads.
  int? _seed;
  bool _closing = false;

  Animation<double>? _routeAnimation;
  StreamSubscription<void>? _queueEnded;

  @override
  void initState() {
    super.initState();
    // The queue ran out: nothing left to show here, back to the library
    // (the mini player stays, ready to replay).
    _queueEnded = ref.read(audioHandlerProvider).queueEnded.listen((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !ref.read(isPlayingProvider)) _close();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = animation?..addStatusListener(_onRouteStatus);
      _updateCover();
    }
  }

  void _onRouteStatus(AnimationStatus _) => _updateCover();

  void _updateCover() {
    PlayerScreen.coversApp.value =
        _routeAnimation?.status == AnimationStatus.completed && _drag == 0 && !_closing;
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _queueEnded?.cancel();
    PlayerScreen.coversApp.value = false;
    _settle.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _updateCover();
    Navigator.of(context).pop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _settle.stop();
    setState(() => _drag = math.max(0, _drag + d.delta.dy));
    _updateCover();
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (velocity > 700 || _drag > 140) {
      _close();
    } else {
      _settleFrom = _drag;
      _settle.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemProvider).value;
    if (item == null) {
      // Nothing loaded anymore (e.g. stopped from the notification).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
      return const SizedBox.shrink();
    }

    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
    final songId = item.extras?['songId'] as int? ?? 0;
    final albumId = item.extras?['albumId'] as int? ?? 0;

    final seed = ref.watch(artworkSeedProvider((songId: songId, albumId: albumId)));
    if (seed.hasValue) _seed = seed.value;
    final colors = _seed == null ? null : ArtworkColors.fromSeed(_seed!, brightness);

    final radius = math.min(_drag / 4, 28.0);

    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _drag),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors?.tint ?? palette.background, palette.background],
                stops: const [0.0, 0.85],
              ),
            ),
            child: _AnimatedAccent(
              accent: colors?.accent ?? palette.ink,
              onAccent: colors?.onAccent ?? palette.onInk,
              builder: (accent, onAccent) => Material(
                type: MaterialType.transparency,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artSize = math.min(constraints.maxWidth - 64, constraints.maxHeight * 0.42);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            _Header(album: item.album, onClose: _close),
                            const Spacer(),
                            _AnimatedArtwork(item: item, size: artSize),
                            const Spacer(),
                            _TrackInfo(item: item, songId: songId),
                            const SizedBox(height: 24),
                            Consumer(
                              builder: (context, ref, _) {
                                final cast = ref.watch(castProvider);
                                if (!cast.active) return SeekBar(duration: item.duration, color: accent);
                                return ListTile(
                                  onTap: () => CastSheet.show(context),
                                  leading: HugeIcon(icon: HugeIcons.strokeRoundedCast, color: accent, size: 24),
                                  title: Text(context.l10n.castingTo(cast.target!.name),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    '${formatDuration(cast.status.position)} / ${formatDuration(cast.status.duration ?? item.duration ?? Duration.zero)}',
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            _Controls(accent: accent, onAccent: onAccent),
                            const SizedBox(height: 18),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(child: _EqChip()),
                                SizedBox(width: 8),
                                SleepChip(),
                                SpeedChip(),
                                ChapterChip(),
                              ],
                            ),
                            const Spacer(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Smoothly animates the accent colors when the track (and artwork) changes.
class _AnimatedAccent extends StatelessWidget {
  const _AnimatedAccent({required this.accent, required this.onAccent, required this.builder});

  final Color accent;
  final Color onAccent;
  final Widget Function(Color accent, Color onAccent) builder;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 600);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: duration,
      builder: (context, a, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: onAccent),
        duration: duration,
        builder: (context, on, _) => builder(a ?? accent, on ?? onAccent),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.album, required this.onClose});

  final String? album;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: context.l10n.close,
            onPressed: onClose,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, color: palette.ink, size: 28),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  context.l10n.nowPlaying.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.6,
                    color: palette.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (album != null)
                  Text(
                    album!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final casting = ref.watch(castProvider.select((s) => s.active));
              return IconButton(
                tooltip: context.l10n.cast,
                onPressed: () => CastSheet.show(context),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCast, color: casting ? palette.hiRes : palette.ink, size: 24),
              );
            },
          ),
          IconButton(
            tooltip: context.l10n.lyrics,
            onPressed: () => LyricsSheet.show(context),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedQuoteDown, color: palette.ink, size: 24),
          ),
          IconButton(
            tooltip: context.l10n.equalizer,
            onPressed: () => EqualizerScreen.open(context),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSlidersHorizontal, color: palette.ink, size: 24),
          ),
          IconButton(
            tooltip: context.l10n.queue,
            onPressed: () => QueueSheet.show(context),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedPlaylist02, color: palette.ink, size: 26),
          ),
        ],
      ),
    );
  }
}

/// Artwork that breathes with playback (shrinks on pause) and can be swiped
/// sideways to change track.
class _AnimatedArtwork extends ConsumerWidget {
  const _AnimatedArtwork({required this.item, required this.size});

  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final handler = ref.read(audioHandlerProvider);

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) handler.skipToNext();
        if (v > 300) handler.skipToPrevious();
      },
      child: AnimatedScale(
        scale: playing ? 1 : 0.86,
        duration: const Duration(milliseconds: 500),
        curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
        child: Hero(
          tag: PlayerScreen.artworkHeroTag,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
            ),
            child: Artwork(
              key: ValueKey(item.id),
              songId: item.extras?['songId'] as int? ?? 0,
              albumId: item.extras?['albumId'] as int? ?? 0,
              size: size,
              radius: 28,
              shadow: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackInfo extends ConsumerWidget {
  const _TrackInfo({required this.item, required this.songId});

  final MediaItem item;
  final int songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final song = ref.watch(currentSongProvider);
    final favorite = ref.watch(isFavoriteProvider(songId));

    return Row(
      children: [
        IconButton(
          tooltip: favorite ? context.l10n.removeFromFavorites : context.l10n.addToFavorites,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(favoritesProvider.notifier).toggle(songId);
          },
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
              child: child,
            ),
            child: favorite
                ? Icon(Icons.favorite_rounded, key: const ValueKey(true), color: palette.ink, size: 28)
                : HugeIcon(
                    key: const ValueKey(false),
                    icon: HugeIcons.strokeRoundedFavourite,
                    color: palette.ink,
                    size: 26,
                  ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(item.id),
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  item.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: palette.inkMuted, fontWeight: FontWeight.w500),
                ),
                if (song != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: context.l10n.signalPathAndSpectrum,
                    child: GestureDetector(
                      onTap: () => SignalSheet.show(context),
                      child: QualityBadge(info: ref.watch(songAudioInfoProvider(song)), large: true),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: context.l10n.more,
          onPressed: song == null ? null : () => SongActionsSheet.show(context, song, allowNavigation: false),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontalCircle01, color: palette.ink, size: 26),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.accent, required this.onAccent});

  final Color accent;
  final Color onAccent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final palette = context.palette;
    final state = ref.watch(playbackStateProvider).value;
    final cast = ref.watch(castProvider);
    final castNotifier = ref.read(castProvider.notifier);
    final playing = cast.active ? cast.status.playback == CastPlayback.playing : (state?.playing ?? false);
    final shuffle = state?.shuffleMode == AudioServiceShuffleMode.all;
    final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final spoken = ref.watch(currentIsLongFormProvider);
    void skip(int seconds) {
      final from = cast.active ? cast.status.position : handler.position;
      var target = from + Duration(seconds: seconds);
      if (target < Duration.zero) target = Duration.zero;
      cast.active ? castNotifier.seek(target) : handler.seek(target);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (spoken)
          _ToggleButton(
            tooltip: context.l10n.back15,
            icon: HugeIcons.strokeRoundedGoBackward15Sec,
            active: false,
            activeColor: accent,
            onPressed: () => skip(-15),
          )
        else
          _ToggleButton(
            tooltip: context.l10n.shuffle,
            icon: HugeIcons.strokeRoundedShuffle,
            active: shuffle,
            activeColor: accent,
            onPressed: handler.toggleShuffle,
          ),
        _PressScale(
          onTap: cast.active ? castNotifier.previous : handler.skipToPrevious,
          child: HugeIcon(icon: HugeIcons.strokeRoundedPrevious, color: palette.ink, size: 36),
        ),
        _PressScale(
          onTap: () {
            HapticFeedback.mediumImpact();
            cast.active ? castNotifier.togglePlay() : handler.togglePlayPause();
          },
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, a) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(a),
                child: ScaleTransition(scale: a, child: child),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                color: onAccent,
                size: 40,
                semanticLabel: playing ? context.l10n.pause : context.l10n.play,
              ),
            ),
          ),
        ),
        _PressScale(
          onTap: cast.active ? castNotifier.next : handler.skipToNext,
          child: HugeIcon(icon: HugeIcons.strokeRoundedNext, color: palette.ink, size: 36),
        ),
        if (spoken)
          _ToggleButton(
            tooltip: context.l10n.forward30,
            icon: HugeIcons.strokeRoundedGoForward30Sec,
            active: false,
            activeColor: accent,
            onPressed: () => skip(30),
          )
        else
          _ToggleButton(
            tooltip: context.l10n.repeat,
            icon: repeat == AudioServiceRepeatMode.one
                ? HugeIcons.strokeRoundedRepeatOne01
                : HugeIcons.strokeRoundedRepeat,
            active: repeat != AudioServiceRepeatMode.none,
            activeColor: accent,
            onPressed: handler.cycleRepeat,
          ),
      ],
    );
  }
}

/// Shuffle / repeat button: tinted with a dot underneath when active.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  final String tooltip;
  final List<List<dynamic>> icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: _PressScale(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: icon, color: active ? activeColor : palette.inkMuted, size: 24),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 4 : 0,
                height: 4,
                decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shrinks slightly while pressed — gives controls a tactile feel.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Shows the active sound (and device correction) and why; tap to switch,
/// long-press for the full equalizer.
class _EqChip extends ConsumerWidget {
  const _EqChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(eqSettingsProvider.select((s) => s.enabled));
    final sound = ref.watch(activeSoundProvider);
    final device = ref.watch(activeDevicePresetProvider);
    final song = ref.watch(currentSongProvider);
    final palette = context.palette;

    final text = !enabled
        ? context.l10n.equalizerOff
        : [
            '${context.l10n.presetName(sound.preset)} · ${context.l10n.eqReason(sound.reason)}',
            if (device.id != BuiltInPresets.deviceNone.id) context.l10n.presetName(device),
          ].join('  ·  ');

    return GestureDetector(
      onTap: () => QuickEqSheet.show(context, song: song),
      onLongPress: () => EqualizerScreen.open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? palette.ink.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSlidersHorizontal,
              color: enabled ? palette.ink : palette.inkMuted,
              size: 16,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? palette.ink : palette.inkMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
