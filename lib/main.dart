import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/router.dart';
import 'app/theme/phosphor_theme.dart';
import 'core/services/user_environment.dart';
import 'features/settings/providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Source user's full shell environment (API keys, PATH, etc.)
  await loadUserEnvironment();

  // Force dark system chrome to match CRT aesthetic
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  // Initialize window manager for fullscreen toggle
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(640, 400),
      center: true,
      title: 'PHOSPHOR',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // Initialize SharedPreferences for settings persistence
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const PhosphorApp(),
    ),
  );
}

class PhosphorApp extends ConsumerWidget {
  const PhosphorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final theme = ref.watch(phosphorThemeProvider);

    final fontScale = ref.watch(
      crtSettingsProvider.select((s) => s.fontScale),
    );

    return MaterialApp.router(
      title: 'PHOSPHOR',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      builder: (context, child) {
        // Scale ALL text globally — toolbar, boot screen, AI panel, everything
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child!,
        );
      },
    );
  }
}
