import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_handler.dart';
import 'core/theme/app_theme.dart';
import 'data/app_database.dart';
import 'features/shell/app_shell.dart';
import 'providers/player_providers.dart';
import 'providers/user_data_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final (audioHandler, database) = await (initAudioHandler(), AppDatabase.open()).wait;
  final bootstrap = await Bootstrap.load(database);

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        databaseProvider.overrideWithValue(database),
        bootstrapProvider.overrideWithValue(bootstrap),
      ],
      child: const AudifacApp(),
    ),
  );
}

class AudifacApp extends ConsumerWidget {
  const AudifacApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    return MaterialApp(
      title: 'audifac',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: child!,
        );
      },
      home: const AppShell(),
    );
  }
}
