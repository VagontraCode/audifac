import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qr/qr.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../providers/guest_requests_provider.dart';
import '../../providers/queue_actions.dart';
import '../../widgets/artwork.dart';

/// Soirée → Guest requests: a QR code guests scan (same Wi-Fi) to ask for
/// songs; the host accepts (added to the queue / the soirée) or declines.
class GuestRequestsScreen extends ConsumerWidget {
  const GuestRequestsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GuestRequestsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final state = ref.watch(guestRequestsProvider);
    final notifier = ref.read(guestRequestsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    void toggle(bool on) => on
        ? notifier.start((
            title: l10n.guestPageTitle,
            name: l10n.guestPageName,
            search: l10n.guestPageSearch,
            request: l10n.guestPageRequest,
            sent: l10n.guestPageSent,
            tooMany: l10n.guestPageTooMany,
            failed: l10n.guestPageFailed,
            nothing: l10n.guestPageNothing,
          ))
        : notifier.stop();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.guestRequests)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: palette.onInk,
              activeTrackColor: palette.ink,
              title: Text(l10n.guestRequestsOn, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l10n.guestRequestsPrivacy),
              value: state.on,
              onChanged: toggle,
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(state.error == 'wifi' ? l10n.transferNoWifi : l10n.transferFailed, style: theme.textTheme.bodyMedium),
              ),
            if (state.url case final url?) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: SizedBox.square(
                    dimension: 220,
                    child: Semantics(
                      image: true,
                      label: l10n.guestQrLabel,
                      child: CustomPaint(painter: _QrPainter(url)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.guestScan, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              SelectableText(url, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
              const SizedBox(height: 24),
              Text(l10n.guestPending(state.pending.length), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (state.pending.isEmpty)
                Text(l10n.guestNoRequests, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
              for (final p in state.pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Artwork.song(p.song, size: 44, radius: 8),
                  title: Text(p.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [p.song.artist, if (p.from.isNotEmpty) l10n.guestFrom(p.from.join(', '))].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.guestDecline,
                        onPressed: () => notifier.resolve(p.song),
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: palette.inkMuted, size: 20),
                      ),
                      IconButton(
                        tooltip: l10n.guestAccept,
                        onPressed: () async {
                          notifier.resolve(p.song);
                          final how = await enqueueSongs(ref, [p.song], next: false);
                          messenger.showSnackBar(SnackBar(
                            content: Text(how == Enqueued.soireeSpread ? l10n.spreadInSoiree(1) : l10n.addedToQueue),
                          ));
                        },
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, color: palette.ink, size: 22),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Draws [data] as a QR code (black on the white card around it).
class _QrPainter extends CustomPainter {
  _QrPainter(this.data) : _image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));

  final String data;
  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
