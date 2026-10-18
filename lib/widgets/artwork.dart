import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';
import '../models/song.dart';
import '../providers/library_providers.dart';

/// Embedded album artwork with a placeholder and a soft fade-in.
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    required this.songId,
    required this.albumId,
    required this.size,
    this.radius = 12,
    this.circle = false,
    this.shadow = false,
    this.placeholderIcon,
  });

  Artwork.song(
    Song song, {
    Key? key,
    required double size,
    double radius = 12,
    bool circle = false,
    bool shadow = false,
  }) : this(
          key: key,
          songId: song.id,
          albumId: song.albumId,
          size: size,
          radius: radius,
          circle: circle,
          shadow: shadow,
        );

  final int songId;
  final int albumId;
  final double size;
  final double radius;
  final bool circle;
  final bool shadow;
  final List<List<dynamic>>? placeholderIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(mediaLibraryProvider);
    final cached = library.peekArtwork(albumId);
    final content = cached != null
        ? _image(context, cached.bytes)
        : FutureBuilder<Uint8List?>(
            future: library.artworkFor(songId: songId, albumId: albumId),
            builder: (context, snapshot) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: snapshot.connectionState == ConnectionState.done
                  ? _image(context, snapshot.data)
                  : ArtworkPlaceholder(size: size, icon: placeholderIcon),
            ),
          );

    // Box decoration + RRect / oval clip rather than a shape path: the
    // renderer draws rounded-rect shadows and clips analytically, while a
    // path shadow is a full blur pass on every frame (the player screen
    // repaints several times a second for its seek bar).
    final borderRadius = circle ? null : BorderRadius.circular(radius);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: size / 8,
                  offset: Offset(0, size / 18),
                ),
              ]
            : null,
      ),
      child: circle
          ? ClipOval(child: content)
          : ClipRRect(borderRadius: borderRadius!, child: content),
    );
  }

  Widget _image(BuildContext context, Uint8List? bytes) {
    if (bytes == null) return ArtworkPlaceholder(size: size, icon: placeholderIcon);
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.memory(
      bytes,
      key: ValueKey(albumId),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: pixels,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({super.key, required this.size, this.icon, this.radius});

  final double size;
  final List<List<dynamic>>? icon;

  /// Set to clip the placeholder itself (when used outside [Artwork]).
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: const ValueKey('placeholder'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius == null ? null : BorderRadius.circular(radius!),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.artwork, const Color(0xFF1C1C1E)],
        ),
      ),
      child: Center(
        child: HugeIcon(
          icon: icon ?? HugeIcons.strokeRoundedMusicNote01,
          color: Colors.white.withValues(alpha: 0.4),
          size: size * 0.38,
        ),
      ),
    );
  }
}
