import 'dart:io';

/// User's full shell environment, sourced from a login shell at startup.
///
/// On macOS/Linux, GUI apps launched from Finder/desktop get a minimal
/// environment (no custom PATH, no API keys, etc.). This runs the user's
/// login shell to capture the real environment.
Map<String, String> userEnvironment = Map.unmodifiable(Platform.environment);

/// Valid env var name pattern — compiled once.
final _envKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Run the user's login shell to capture their full environment.
/// Call once at app startup before providers are created.
Future<void> loadUserEnvironment() async {
  if (!Platform.isMacOS && !Platform.isLinux) return;

  final shell = Platform.environment['SHELL'] ?? '/bin/sh';
  try {
    final result = await Process.run(
      shell,
      ['-l', '-i', '-c', 'command env'],
    ).timeout(const Duration(seconds: 5));

    if (result.exitCode == 0) {
      final env = <String, String>{};
      for (final line in result.stdout.toString().split('\n')) {
        final idx = line.indexOf('=');
        if (idx > 0) {
          final key = line.substring(0, idx);
          if (_envKeyPattern.hasMatch(key)) {
            env[key] = line.substring(idx + 1);
          }
        }
      }
      if (env.isNotEmpty) {
        userEnvironment = Map.unmodifiable({...Platform.environment, ...env});
      }
    }
  } catch (_) {
    // Fall back to Platform.environment
  }
}
