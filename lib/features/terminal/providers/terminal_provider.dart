import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../../../core/services/event_store.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/services/user_environment.dart';
import '../../time_travel/providers/timeline_provider.dart';

const _uuid = Uuid();

/// Provides the terminal instance and PTY process.
final terminalProvider = Provider.autoDispose<TerminalSession>((ref) {
  final eventStore = ref.read(eventStoreProvider);
  final timelineNotifier = ref.read(timelineProvider.notifier);
  final soundService = ref.read(soundServiceProvider);
  final sessionNotifier = ref.read(sessionProvider.notifier);
  final sessionState = ref.read(sessionProvider);
  final session = TerminalSession(
    eventStore: eventStore,
    onEvent: () => timelineNotifier.recordEvent(),
    soundService: soundService,
    sessionNotifier: sessionNotifier,
    isMultiplayerHost: sessionState.isActive && sessionState.isHost,
  );
  // Wire multiplayer peer input to PTY
  sessionNotifier.onPeerInput = (data) => session.handlePeerInput(data);
  ref.onDispose(() {
    sessionNotifier.onPeerInput = null;
    session.dispose();
  });

  // Listen for multiplayer state changes to wire input relay
  ref.listen<SessionState>(sessionProvider, (prev, next) {
    session.isMultiplayerHost = next.isActive && next.isHost;
  });

  return session;
});

/// Bundles a Terminal (state engine) with a Pty (system shell),
/// records all I/O to the event store for time-travel.
class TerminalSession {
  late final Terminal terminal;
  late final Pty pty;
  final EventStore eventStore;
  final VoidCallback? onEvent;
  final SoundService soundService;
  final SessionNotifier sessionNotifier;
  bool isMultiplayerHost;

  /// Strip ANSI escape sequences and control characters from terminal output
  /// so AI context and error detection see clean text.
  static final _ansiPattern = RegExp(
    r'\x1B\[[0-9;]*[a-zA-Z]'   // CSI sequences (colors, cursor, etc.)
    r'|\x1B\][^\x07]*\x07'     // OSC sequences (title setting, etc.)
    r'|\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]' // extended CSI
    r'|\x1B[^[\]].?'           // other two-char escapes
    r'|[\x00-\x08\x0B\x0C\x0E-\x1F]', // control chars (keep \n \r \t)
  );
  static String _stripAnsi(String input) => input.replaceAll(_ansiPattern, '');

  /// Recent output lines for AI context.
  final List<String> recentOutput = [];
  static const _maxRecentOutput = 1000;

  /// Buffer for detecting errors in output.
  String _outputBuffer = '';
  static const _errorPatterns = [
    'error:',
    'Error:',
    'ERROR:',
    'fatal:',
    'FATAL:',
    'command not found',
    'No such file or directory',
    'Permission denied',
    'segmentation fault',
    'Traceback (most recent call last)',
    'panic:',
    'FAILED',
    'npm ERR!',
    'cargo error',
    'SyntaxError:',
    'TypeError:',
    'ReferenceError:',
  ];

  /// Callback to report detected errors for AI auto-explanation.
  void Function(String error)? onErrorDetected;

  /// Cooldown to avoid spamming error sounds on multi-line errors.
  DateTime _lastErrorTime = DateTime(0);

  TerminalSession({
    required this.eventStore,
    this.onEvent,
    required this.soundService,
    required this.sessionNotifier,
    this.isMultiplayerHost = false,
  }) {
    terminal = Terminal(
      maxLines: 10000,
      platform: Platform.isMacOS
          ? TerminalTargetPlatform.macos
          : TerminalTargetPlatform.unknown,
    );
    terminal.resize(120, 80, 0, 0);
    final home = userEnvironment['HOME'] ?? '/';
    pty = Pty.start(
      _defaultShell,
      arguments: const ['-l'],
      columns: 120,
      rows: 80,
      workingDirectory: home,
      environment: {
        ...userEnvironment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    // Shell output (Uint8List) -> terminal state + event recording
    pty.output.listen((data) {
      final decoded = utf8.decode(data, allowMalformed: true);
      terminal.write(decoded);

      // Record output event
      eventStore.record(TerminalEvent(
        id: _uuid.v4(),
        type: EventType.output,
        timestamp: DateTime.now(),
        data: decoded,
      ));
      onEvent?.call();

      // Track recent output for AI context (stripped of ANSI escapes)
      final clean = _stripAnsi(decoded);
      final lines = clean.split('\n');
      recentOutput.addAll(lines);
      if (recentOutput.length > _maxRecentOutput) {
        recentOutput.removeRange(0, recentOutput.length - _maxRecentOutput);
      }

      // Broadcast to multiplayer peers if hosting
      if (isMultiplayerHost) {
        sessionNotifier.broadcastOutput(decoded);
      }

      // Error detection — buffer clean output and check for patterns
      _outputBuffer += clean;
      if (decoded.contains('\n')) {
        _checkForErrors(_outputBuffer);
        _outputBuffer = '';
      }
    });

    // Terminal input (String) -> shell + event recording
    terminal.onOutput = (data) {
      pty.write(utf8.encode(data));

      // Record input event
      eventStore.record(TerminalEvent(
        id: _uuid.v4(),
        type: EventType.input,
        timestamp: DateTime.now(),
        data: data,
      ));
      onEvent?.call();

      // Play keystroke sound (contextual: space, enter, backspace get unique samples)
      soundService.playKeystroke(char: data.isNotEmpty ? data[0] : null);
    };

    // Terminal resize -> PTY resize + multiplayer broadcast
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      pty.resize(height, width);
      if (isMultiplayerHost) {
        sessionNotifier.broadcastResize(width, height);
      }
    };
  }

  /// Check buffered output for error patterns (3s cooldown between alerts).
  void _checkForErrors(String output) {
    final now = DateTime.now();
    if (now.difference(_lastErrorTime).inSeconds < 3) return;

    for (final pattern in _errorPatterns) {
      if (output.contains(pattern)) {
        final errorLines = output
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(10);
        if (errorLines.isNotEmpty) {
          _lastErrorTime = now;
          onErrorDetected?.call(errorLines.join('\n'));
        }
        break;
      }
    }
  }

  /// Write input from a multiplayer peer directly to PTY.
  void handlePeerInput(String data) {
    pty.write(utf8.encode(data));
  }

  /// Get working directory (best effort).
  String get workingDirectory {
    try {
      return Directory.current.path;
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    pty.kill();
  }

  static String get _defaultShell {
    return userEnvironment['SHELL'] ?? '/bin/sh';
  }
}
