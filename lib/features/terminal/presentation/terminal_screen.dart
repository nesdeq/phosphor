import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../app/widgets/crt_button.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sound_service.dart';
import '../../ai_assistant/presentation/ai_panel.dart';
import '../../ai_assistant/presentation/widgets/command_palette.dart';
import '../../ai_assistant/providers/ai_provider.dart';
import '../../multiplayer/presentation/session_lobby.dart';
import '../../multiplayer/presentation/widgets/participant_overlay.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../time_travel/presentation/widgets/timeline_bar.dart';
import '../../time_travel/providers/timeline_provider.dart';
import '../providers/terminal_provider.dart';
import 'widgets/crt_overlay.dart';

/// Main terminal screen — the core of PHOSPHOR.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  bool _showSettings = false;
  bool _showAiPanel = false;
  bool _showCommandPalette = false;
  bool _showTimeline = false;
  bool _showSessionLobby = false;
  bool _errorBannerVisible = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    // Wire callbacks after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wireErrorDetection();
      // Start ambient CRT hum
      ref.read(soundServiceProvider).startAmbientStatic();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  void _wireErrorDetection() {
    final session = ref.read(terminalProvider);
    session.onErrorDetected = (error) {
      if (!mounted) return;
      setState(() {
        _lastError = error;
        _errorBannerVisible = true;
      });
      // Auto-hide after 8 seconds
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _errorBannerVisible = false);
      });
    };
  }

  void _explainError() {
    if (_lastError == null) return;
    setState(() {
      _showAiPanel = true;
      _errorBannerVisible = false;
    });
    // Send the error to AI for explanation
    ref.read(aiChatProvider.notifier).sendMessage(
          'Explain this error and suggest a fix:\n\n$_lastError',
        );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(terminalProvider);
    final palette = ref.watch(phosphorPaletteProvider);
    final colors = palette.colors;
    final timeline = ref.watch(timelineProvider);
    final sessionState = ref.watch(sessionProvider);
    final isPeerMode = sessionState.isActive && !sessionState.isHost;
    final fontFamily =
        ref.watch(crtSettingsProvider.select((s) => s.terminalFont.family));

    // Determine which terminal to show: peer view, replay, or live
    final Terminal displayTerminal;
    if (isPeerMode) {
      displayTerminal =
          ref.read(sessionProvider.notifier).peerTerminal ?? session.terminal;
    } else if (timeline.isReplaying) {
      displayTerminal = ref.read(timelineProvider.notifier).replayTerminal ??
          session.terminal;
    } else {
      displayTerminal = session.terminal;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Terminal
          SafeArea(
            child: Column(
              children: [
                // Toolbar
                _buildToolbar(colors, timeline),
                // Terminal view
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CrtOverlay(
                          child: TerminalView(
                            displayTerminal,
                            theme: _terminalTheme(colors),
                            textStyle: TerminalStyle(
                              fontSize: 16,
                              fontFamily: fontFamily,
                            ),
                          ),
                        ),
                      ),
                      // AI side panel
                      if (_showAiPanel)
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.35,
                          child: AiPanel(
                            onClose: () => setState(() => _showAiPanel = false),
                          ),
                        ),
                    ],
                  ),
                ),
                // Timeline bar
                if (_showTimeline) const TimelineBar(),
              ],
            ),
          ),
          // Error auto-explanation banner
          if (_errorBannerVisible && _lastError != null)
            Positioned(
              bottom: _showTimeline ? 56 : 8,
              left: 16,
              right: _showAiPanel
                  ? MediaQuery.of(context).size.width * 0.35 + 16
                  : 16,
              child: _buildErrorBanner(colors),
            ),
          // Peer mode indicator
          if (isPeerMode)
            _modeBanner(
              color: colors.glow,
              textColor: colors.background,
              label: 'PEER MODE [ENCRYPTED] — click to leave',
              onTap: () => ref.read(sessionProvider.notifier).leaveSession(),
            ),
          // Replay mode indicator
          if (timeline.isReplaying)
            _modeBanner(
              color: crtErrorRed,
              textColor: Colors.white,
              label: 'REPLAY MODE — click to return to live',
              onTap: () => ref.read(timelineProvider.notifier).exitReplayMode(),
            ),
          // Command palette overlay
          if (_showCommandPalette)
            CommandPalette(
              onClose: () => setState(() => _showCommandPalette = false),
              onSubmit: (command) {
                setState(() => _showCommandPalette = false);
                // Write the command to the terminal
                session.terminal.onOutput?.call('$command\n');
              },
            ),
          // Participant overlay
          const ParticipantOverlay(),
          // Session lobby overlay
          if (_showSessionLobby)
            SessionLobby(
              onClose: () => setState(() => _showSessionLobby = false),
            ),
          // Settings overlay
          if (_showSettings)
            SettingsScreen(
              onClose: () => setState(() => _showSettings = false),
            ),
        ],
      ),
    );
  }

  Widget _modeBanner({
    required Color color,
    required Color textColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Positioned(
      top: 32,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _errorRedDim = Color(0xFFFF6666);

  Widget _buildErrorBanner(CrtColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        border: Border.all(color: crtErrorRed, width: 1),
      ),
      child: Row(
        children: [
          const Text(
            'ERROR DETECTED',
            style: TextStyle(
              fontSize: 11,
              color: crtErrorRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastError!.split('\n').first,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _errorRedDim),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _explainError,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: crtErrorRed),
              ),
              child: const Text(
                'EXPLAIN',
                style: TextStyle(fontSize: 10, color: crtErrorRed),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _errorBannerVisible = false),
            child: const Text(
              '[X]',
              style: TextStyle(fontSize: 10, color: _errorRedDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(CrtColorScheme colors, TimelineState timeline) {
    Widget tab(String label, bool active, VoidCallback onTap) => CrtButton(
          label: label,
          onTap: onTap,
          filled: active,
          dimBorder: true,
          dimLabel: true,
          fontSize: 10,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );

    return Container(
      height: 28,
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            'PHOSPHOR',
            style: TextStyle(
              fontSize: 12,
              color: colors.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (timeline.isReplaying) ...[
            const SizedBox(width: 8),
            Text(
              '[REPLAY]',
              style: TextStyle(
                fontSize: 10,
                color: colors.text.withValues(alpha: 0.6),
              ),
            ),
          ],
          const Spacer(),
          tab('TIMELINE', _showTimeline,
              () => setState(() => _showTimeline = !_showTimeline)),
          const SizedBox(width: 8),
          tab('SHARE', _showSessionLobby,
              () => setState(() => _showSessionLobby = !_showSessionLobby)),
          const SizedBox(width: 8),
          tab('ALAN', _showAiPanel,
              () => setState(() => _showAiPanel = !_showAiPanel)),
          const SizedBox(width: 8),
          tab('SETTINGS', _showSettings,
              () => setState(() => _showSettings = !_showSettings)),
        ],
      ),
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Cmd on macOS, Ctrl on Linux
    final meta = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Cmd+, -> Settings
    if (meta && event.logicalKey == LogicalKeyboardKey.comma) {
      setState(() => _showSettings = !_showSettings);
      return true;
    }
    // Cmd+K -> Command palette
    if (meta && !shift && event.logicalKey == LogicalKeyboardKey.keyK) {
      setState(() => _showCommandPalette = !_showCommandPalette);
      return true;
    }
    // Cmd+Shift+K -> AI panel
    if (meta && shift && event.logicalKey == LogicalKeyboardKey.keyK) {
      setState(() => _showAiPanel = !_showAiPanel);
      return true;
    }
    // Cmd+T -> Timeline
    if (meta && event.logicalKey == LogicalKeyboardKey.keyT) {
      setState(() => _showTimeline = !_showTimeline);
      return true;
    }
    // Ctrl/Cmd+F -> Toggle fullscreen
    if (meta && !shift && event.logicalKey == LogicalKeyboardKey.keyF) {
      windowManager.isFullScreen().then((isFullScreen) {
        windowManager.setFullScreen(!isFullScreen);
      });
      return true;
    }
    return false;
  }

  TerminalTheme _terminalTheme(CrtColorScheme colors) => TerminalTheme(
        cursor: colors.cursor,
        selection: colors.selection,
        foreground: colors.text,
        background: colors.background,
        black: _Ansi.black,
        red: _Ansi.red,
        green: _Ansi.green,
        yellow: _Ansi.yellow,
        blue: _Ansi.blue,
        magenta: _Ansi.magenta,
        cyan: _Ansi.cyan,
        white: _Ansi.white,
        brightBlack: _Ansi.brightBlack,
        brightRed: _Ansi.brightRed,
        brightGreen: _Ansi.brightGreen,
        brightYellow: _Ansi.brightYellow,
        brightBlue: _Ansi.brightBlue,
        brightMagenta: _Ansi.brightMagenta,
        brightCyan: _Ansi.brightCyan,
        brightWhite: _Ansi.brightWhite,
        searchHitBackground: colors.selection,
        searchHitBackgroundCurrent: colors.text,
        searchHitForeground: colors.background,
      );
}

/// Static ANSI cell colors used by xterm. Independent of phosphor palette —
/// programs expect these regardless of the user's CRT tint.
abstract final class _Ansi {
  static const black = Color(0xFF0A0A0A);
  static const red = crtErrorRed;
  static const green = Color(0xFF33FF33);
  static const yellow = Color(0xFFFFFF33);
  static const blue = Color(0xFF3333FF);
  static const magenta = Color(0xFFFF33FF);
  static const cyan = Color(0xFF33FFFF);
  static const white = Color(0xFFE0E0E0);
  static const brightBlack = Color(0xFF555555);
  static const brightRed = Color(0xFFFF6666);
  static const brightGreen = Color(0xFF66FF66);
  static const brightYellow = Color(0xFFFFFF66);
  static const brightBlue = Color(0xFF6666FF);
  static const brightMagenta = Color(0xFFFF66FF);
  static const brightCyan = Color(0xFF66FFFF);
  static const brightWhite = Color(0xFFFFFFFF);
}
