import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_providers.dart';

/// The wallpaper-based system accent (Android 12+), or null. Re-read when the
/// app comes back (the wallpaper may have changed).
final systemAccentProvider = FutureProvider<int?>((ref) => ref.read(mediaLibraryProvider).systemAccent());
