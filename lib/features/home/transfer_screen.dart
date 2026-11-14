import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../cast/cast_server.dart';
import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../providers/library_providers.dart';
import '../../transfer/transfer_server.dart';
import '../../transfer/upload_page.dart';

/// Settings → Add music from a computer: shows an address to open in the
/// computer's browser (same Wi-Fi); dropped files land in Music/audifac.
/// The server runs only while this screen is open.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferScreen()));

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

enum _State { starting, noWifi, unsupported, ready, failed }

class _TransferScreenState extends ConsumerState<TransferScreen> {
  TransferServer? _server;
  StreamSubscription<ReceivedFile>? _sub;
  var _state = _State.starting;
  String? _url;
  final _files = <ReceivedFile>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final library = ref.read(mediaLibraryProvider);
    final l10n = context.l10n;
    if (!await library.canImportAudio()) return _set(_State.unsupported);
    final host = await CastServer.localAddress();
    if (host == null) return _set(_State.noWifi);
    final server = TransferServer(
      import: (File temp, String name) => library.importAudio(temp.path, name),
      page: uploadPage((
        title: l10n.transferPageTitle,
        drop: l10n.transferPageDrop,
        choose: l10n.transferPageChoose,
        done: l10n.transferPageDone,
        failed: l10n.transferPageFailed,
        notAudio: l10n.transferPageNotAudio,
      )),
    );
    try {
      // A fixed port when free: the address stays the same next time.
      try {
        await server.start(port: 8765);
      } on SocketException {
        await server.start();
      }
    } on SocketException {
      return _set(_State.failed);
    }
    if (!mounted) return server.dispose();
    _server = server;
    _sub = server.received.listen((f) {
      if (mounted) setState(() => _files.insert(0, f));
      if (f.error == null) ref.read(libraryProvider.notifier).reload();
    });
    setState(() {
      _url = 'http://$host:${server.port}/${server.token}/';
      _state = _State.ready;
    });
  }

  void _set(_State state) {
    if (mounted) setState(() => _state = state);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _server?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final saved = _files.where((f) => f.error == null).length;

    Widget message(String text) =>
        Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge)));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transferTitle)),
      body: SafeArea(
        child: switch (_state) {
          _State.starting => const Center(child: CircularProgressIndicator()),
          _State.unsupported => message(l10n.transferNeedsAndroid10),
          _State.noWifi => message(l10n.transferNoWifi),
          _State.failed => message(l10n.transferFailed),
          _State.ready => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(l10n.transferStep1, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _url!,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.copy,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _url!));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
                        },
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, color: palette.ink, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.transferStep2, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                Text(l10n.transferKeepOpen, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
                const SizedBox(height: 24),
                if (_files.isEmpty)
                  Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text(l10n.transferWaiting, style: theme.textTheme.bodyMedium),
                    ],
                  )
                else ...[
                  Text(l10n.transferReceived(saved), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final f in _files)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: HugeIcon(
                        icon: f.error == null ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedAlertCircle,
                        color: f.error == null ? palette.lossless : palette.inkMuted,
                        size: 22,
                      ),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(f.error == null ? formatBytes(f.bytes) : l10n.transferRefused(f.error!)),
                    ),
                ],
              ],
            ),
        },
      ),
    );
  }
}
