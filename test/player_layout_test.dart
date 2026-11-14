import 'package:audifac/core/audio/audio_handler.dart';
import 'package:audifac/core/theme/app_theme.dart';
import 'package:audifac/data/app_database.dart';
import 'package:audifac/features/player/player_screen.dart';
import 'package:audifac/l10n/l10n.dart';
import 'package:audifac/providers/player_providers.dart';
import 'package:audifac/providers/user_data_providers.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full player at phone (portrait / landscape) and tablet-panel sizes:
/// no overflow, no layout exception.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // Platform plugins answer nothing in tests.
  for (final channel in const [
    'com.ryanheise.audio_session',
    'com.ryanheise.just_audio.methods',
    'com.ryanheise.audio_service.client.methods',
    'com.ryanheise.audio_service.handler.methods',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
  }

  const item = MediaItem(
    id: 'content://media/external/audio/media/1',
    title: 'A fairly long song title to test wrapping',
    artist: 'Some Artist',
    album: 'Some Album',
    duration: Duration(minutes: 4, seconds: 12),
    extras: {'songId': 1, 'albumId': 1},
  );

  Future<void> pumpPlayer(WidgetTester tester, Size size, {bool embedded = false}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final handler = AudifacAudioHandler();
    // As in the app: the player opens once a song is loaded.
    final container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        mediaItemProvider.overrideWith((ref) => Stream.value(item)),
        bootstrapProvider.overrideWithValue(const Bootstrap(
          favoriteIds: [],
          playlists: [],
          recentIds: [],
          values: {},
          audioInfo: {},
          eqPresets: [],
          eqRules: [],
        )),
      ],
    );
    addTearDown(container.dispose);
    container.listen(mediaItemProvider, (_, _) {});
    await tester.runAsync(() => container.read(mediaItemProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: embedded
            ? const Scaffold(body: Row(children: [Spacer(), SizedBox(width: 420, child: PlayerScreen(embedded: true))]))
            : const PlayerScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('portrait phone', (tester) async {
    await pumpPlayer(tester, const Size(360, 760));
    expect(tester.takeException(), isNull);
    expect(find.text(item.title), findsOneWidget);
  });

  testWidgets('landscape phone: artwork beside the controls', (tester) async {
    await pumpPlayer(tester, const Size(760, 360));
    expect(tester.takeException(), isNull);
    expect(find.text(item.title), findsOneWidget);
    // Details on the right, artwork on the left.
    expect(tester.getCenter(find.text(item.title)).dx, greaterThan(380));
  });

  testWidgets('small landscape phone', (tester) async {
    await pumpPlayer(tester, const Size(640, 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet side panel: no close button', (tester) async {
    await pumpPlayer(tester, const Size(1280, 800), embedded: true);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Close'), findsNothing);
  });
}
