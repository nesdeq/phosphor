import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/boot_sequence/presentation/boot_screen.dart';
import '../features/terminal/presentation/terminal_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/boot',
    routes: [
      GoRoute(
        path: '/boot',
        builder: (context, state) => const BootScreen(),
      ),
      GoRoute(
        path: '/terminal',
        builder: (context, state) => const TerminalScreen(),
      ),
    ],
  );
});
