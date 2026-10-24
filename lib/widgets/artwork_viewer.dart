import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/l10n.dart';
import '../providers/library_providers.dart';

/// The cover at full resolution: pinch or double-tap to zoom, with its
/// size, format and weight (a 300 px cover in a hi-res file shows here).
class ArtworkViewer extends ConsumerStatefulWidget {
  const ArtworkViewer({super.key, required this.songId, required this.albumId});

  final int songId;
  final int albumId;

  static Future<void> open(BuildContext context, {required int songId, required int albumId}) {
    HapticFeedback.selectionClick();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => ArtworkViewer(songId: songId, albumId: albumId),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  /// "JPEG" / "PNG" / "WebP" / "GIF" / "BMP" from the file's first bytes.
  static String? format(Uint8List b) {
    bool starts(List<int> magic, [int at = 0]) {
      if (b.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts([0xFF, 0xD8, 0xFF])) return 'JPEG';
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'PNG';
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) return 'WebP';
    if (starts([0x47, 0x49, 0x46, 0x38])) return 'GIF';
    if (starts([0x42, 0x4D])) return 'BMP';
    return null;
  }

  /// 312 KB, 1.4 MB.
  static String size(int bytes) =>
      bytes < 1000 * 1000 ? '${(bytes / 1000).round()} KB' : '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';

  @override
  ConsumerState<ArtworkViewer> createState() => _ArtworkViewerState();
}

class _ArtworkViewerState extends ConsumerState<ArtworkViewer> with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(() => _zoom.value = _zoomTween?.evaluate(_animation) ?? _zoom.value);
  Matrix4Tween? _zoomTween;
  TapDownDetails? _doubleTap;

  Uint8List? _full;
  bool _loaded = false;
  ({int width, int height})? _pixels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await ref.read(mediaLibraryProvider).fullArtwork(widget.songId);
    ({int width, int height})? pixels;
    if (bytes != null) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        pixels = (width: descriptor.width, height: descriptor.height);
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {
        // Not an image Flutter can read: the smaller cover stays.
      }
    }
    if (!mounted) return;
    setState(() {
      _full = pixels == null ? null : bytes;
      _pixels = pixels;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    final at = _doubleTap?.localPosition ?? Offset.zero;
    const scale = 3.0;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
            ..scaleByDouble(scale, scale, 1, 1));
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: target);
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaLibraryProvider);
    final preview = library.peekArtwork(widget.albumId)?.bytes;
    final bytes = _full ?? preview;
    final full = _full;
    final pixels = _pixels;
    final caption = [
      if (pixels != null) '${pixels.width} × ${pixels.height}',
      if (full != null) ?ArtworkViewer.format(full),
      if (full != null) ArtworkViewer.size(full.length),
    ].join(' · ');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTap = d,
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _zoom,
                maxScale: 10,
                child: Center(
                  child: bytes == null
                      ? (_loaded
                            ? Text(context.l10n.noArtwork, style: const TextStyle(color: Colors.white70))
                            : const CircularProgressIndicator(color: Colors.white54))
                      : Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.high,
                        ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: DecoratedBox(
              // Keeps the close button and caption readable over a zoomed cover.
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xAA000000), Color(0x00000000)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: context.l10n.close,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: Colors.white, size: 26),
                      ),
                      const Spacer(),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            caption,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
