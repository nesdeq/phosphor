import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../core/services/event_store.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/services/user_environment.dart';
import '../../time_travel/providers/timeline_provider.dart';

/// Provides the terminal instance and PTY process.
final terminalProvider = Provider.autoDispose<TerminalSession>((ref) {
  final eventStore = ref.read(eventStoreProvider);
  final timelineNotifier = ref.read(timelineProvider.notifier);
  final soundService = ref.read(soundServiceProvider);
  final sessionNotifier = ref.read(sessionProvider.notifier);
  final sessionState = ref.read(sessionProvider);
  final session = TerminalSession(
    eventStore: eventStore,
    onEvent: timelineNotifier.recordEvent,
    soundService: soundService,
    sessionNotifier: sessionNotifier,
    isMultiplayerHost: sessionState.isActive && sessionState.isHost,
  );

  // Pipe peer input straight into the host PTY.
  final peerInputSub =
      sessionNotifier.peerInputStream.listen(session.handlePeerInput);

  ref.onDispose(() {
    peerInputSub.cancel();
    session.dispose();
  });

  // Listen for multiplayer state changes to wire input relay.
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
  StreamSubscription<List<int>>? _outputSub;
  final EventStore eventStore;
  final VoidCallback? onEvent;
  final SoundService soundService;
  final SessionNotifier sessionNotifier;
  bool isMultiplayerHost;

  /// Strip ANSI escape sequences and control characters from terminal output
  /// so AI context and error detection see clean text.
  static final _ansiPattern = RegExp(
    r'\x1B\[[0-9;]*[a-zA-Z]' // CSI sequences (colors, cursor, etc.)
    r'|\x1B\][^\x07]*\x07' // OSC sequences (title setting, etc.)
    r'|\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]' // extended CSI
    r'|\x1B[^[\]].?' // other two-char escapes
    r'|[\x00-\x08\x0B\x0C\x0E-\x1F]', // control chars (keep \n \r \t)
  );
  static String _stripAnsi(String input) => input.replaceAll(_ansiPattern, '');

  /// Recent output lines for AI context.
  final List<String> recentOutput = [];
  static const _maxRecentOutput = 1000;

  /// Buffer for detecting errors in output. Flushed on newline OR when it
  /// exceeds [_outputBufferCap] (e.g. progress streams using only \r).
  String _outputBuffer = '';
  static const _outputBufferCap = 64 * 1024;

  /// Single regex compiled from all error patterns — checked once per
  /// flushed buffer rather than 16 individual `contains` calls.
  static final _errorRegex = RegExp(
    r'(?:'
    r'error:|Error:|ERROR:|fatal:|FATAL:|'
    r'command not found|No such file or directory|Permission denied|'
    r'segmentation fault|Traceback \(most recent call last\)|'
    r'panic:|FAILED|npm ERR!|cargo error|'
    r'SyntaxError:|TypeError:|ReferenceError:'
    r')',
  );

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
    terminal.resize(kInitialTerminalCols, kInitialTerminalRows, 0, 0);
    final home = userEnvironment['HOME'] ?? '/';
    pty = Pty.start(
      _defaultShell,
      arguments: const ['-l'],
      columns: kInitialTerminalCols,
      rows: kInitialTerminalRows,
      workingDirectory: home,
      environment: {
        ...userEnvironment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    // Shell output (Uint8List) -> terminal state + event recording
    _outputSub = pty.output.listen((data) {
      final decoded = utf8.decode(data, allowMalformed: true);
      terminal.write(decoded);

      // Record output event
      eventStore.record(TerminalEvent(
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

      // Error detection — buffer clean output and check on newline or
      // when the buffer exceeds the cap (handles \r-only progress streams).
      _outputBuffer += clean;
      if (decoded.contains('\n') || _outputBuffer.length > _outputBufferCap) {
        _checkForErrors(_outputBuffer);
        _outputBuffer = '';
      }
    });

    // Terminal input (String) -> shell + event recording
    terminal.onOutput = (data) {
      pty.write(utf8.encode(data));

      // Record input event
      eventStore.record(TerminalEvent(
        type: EventType.input,
        timestamp: DateTime.now(),
        data: data,
      ));
      onEvent?.call();

      // Play keystroke sound (contextual: space, enter, backspace get unique samples)
      soundService.playKeystroke(char: data.isNotEmpty ? data[0] : null);
    };

    // Terminal resize -> PTY resize + multiplayer broadcast.
    // pixelWidth/pixelHeight are unused; xterm requires the 4-arg shape.
    terminal.onResize = (width, height, _, __) {
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
    if (!_errorRegex.hasMatch(output)) return;

    final errorLines =
        output.split('\n').where((l) => l.trim().isNotEmpty).take(10);
    if (errorLines.isNotEmpty) {
      _lastErrorTime = now;
      onErrorDetected?.call(errorLines.join('\n'));
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
    _outputSub?.cancel();
    pty.kill();
  }

  static String get _defaultShell {
    return userEnvironment['SHELL'] ?? '/bin/sh';
  }
}
