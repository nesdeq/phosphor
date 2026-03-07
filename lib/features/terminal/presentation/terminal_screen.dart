import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sound_service.dart';
import '../../ai_assistant/presentation/ai_panel.dart';
import '../../ai_assistant/presentation/widgets/command_palette.dart';
import '../../ai_assistant/providers/ai_provider.dart';
import '../../multiplayer/presentation/session_lobby.dart';
import '../../multiplayer/presentation/widgets/participant_overlay.dart';
import '../../settings/presentation/settings_screen.dart';
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

    // Determine which terminal to show: peer view, replay, or live
    final Terminal displayTerminal;
    if (isPeerMode) {
      displayTerminal = ref.read(sessionProvider.notifier).peerTerminal ??
          session.terminal;
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
                              textStyle: const TerminalStyle(
                                fontSize: 16,
                                fontFamily: 'PhosphorMono',
                              ),
                            ),
                          ),
                        ),
                        // AI side panel
                        if (_showAiPanel)
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.35,
                            child: AiPanel(
                              onClose: () =>
                                  setState(() => _showAiPanel = false),
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
              Positioned(
                top: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.glow.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(sessionProvider.notifier).leaveSession(),
                      child: Text(
                        'PEER MODE [ENCRYPTED] — click to leave',
                        style: TextStyle(
                          fontFamily: 'PhosphorMono',
                          fontSize: 11,
                          color: colors.background,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Replay mode indicator
            if (timeline.isReplaying)
              Positioned(
                top: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3333).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(timelineProvider.notifier).exitReplayMode(),
                      child: const Text(
                        'REPLAY MODE — click to return to live',
                        style: TextStyle(
                          fontFamily: 'PhosphorMono',
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
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

  Widget _buildErrorBanner(CrtColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        border: Border.all(color: const Color(0xFFFF3333), width: 1),
      ),
      child: Row(
        children: [
          const Text(
            'ERROR DETECTED',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 11,
              color: Color(0xFFFF3333),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastError!.split('\n').first,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 11,
                color: Color(0xFFFF6666),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _explainError,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF3333)),
              ),
              child: const Text(
                'EXPLAIN',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 10,
                  color: Color(0xFFFF3333),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _errorBannerVisible = false),
            child: const Text(
              '[X]',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 10,
                color: Color(0xFFFF6666),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(CrtColorScheme colors, TimelineState timeline) {
    return Container(
      height: 28,
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            'PHOSPHOR',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
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
                fontFamily: 'PhosphorMono',
                fontSize: 10,
                color: colors.text.withValues(alpha: 0.6),
              ),
            ),
          ],
          const Spacer(),
          _toolbarButton(
            'TIMELINE',
            _showTimeline,
            () => setState(() => _showTimeline = !_showTimeline),
            colors,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            'SHARE',
            _showSessionLobby,
            () => setState(() => _showSessionLobby = !_showSessionLobby),
            colors,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            'ALAN',
            _showAiPanel,
            () => setState(() => _showAiPanel = !_showAiPanel),
            colors,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            'SETTINGS',
            _showSettings,
            () => setState(() => _showSettings = !_showSettings),
            colors,
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(
    String label,
    bool active,
    VoidCallback onTap,
    CrtColorScheme colors,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? colors.text : Colors.transparent,
          border: Border.all(
            color: active ? colors.text : colors.textDim,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'PhosphorMono',
            fontSize: 10,
            color: active ? colors.background : colors.textDim,
          ),
        ),
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
    if (meta &&
        !shift &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      setState(() => _showCommandPalette = !_showCommandPalette);
      return true;
    }
    // Cmd+Shift+K -> AI panel
    if (meta &&
        shift &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      setState(() => _showAiPanel = !_showAiPanel);
      return true;
    }
    // Cmd+T -> Timeline
    if (meta && event.logicalKey == LogicalKeyboardKey.keyT) {
      setState(() => _showTimeline = !_showTimeline);
      return true;
    }
    // Ctrl/Cmd+F -> Toggle fullscreen
    if (meta &&
        !shift &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      windowManager.isFullScreen().then((isFullScreen) {
        windowManager.setFullScreen(!isFullScreen);
      });
      return true;
    }
    return false;
  }

  TerminalTheme _terminalTheme(CrtColorScheme colors) {
    return TerminalTheme(
      cursor: colors.cursor,
      selection: colors.selection,
      foreground: colors.text,
      background: colors.background,
      black: const Color(0xFF0A0A0A),
      red: const Color(0xFFFF3333),
      green: const Color(0xFF33FF33),
      yellow: const Color(0xFFFFFF33),
      blue: const Color(0xFF3333FF),
      magenta: const Color(0xFFFF33FF),
      cyan: const Color(0xFF33FFFF),
      white: const Color(0xFFE0E0E0),
      brightBlack: const Color(0xFF555555),
      brightRed: const Color(0xFFFF6666),
      brightGreen: const Color(0xFF66FF66),
      brightYellow: const Color(0xFFFFFF66),
      brightBlue: const Color(0xFF6666FF),
      brightMagenta: const Color(0xFFFF66FF),
      brightCyan: const Color(0xFF66FFFF),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: colors.selection,
      searchHitBackgroundCurrent: colors.text,
      searchHitForeground: colors.background,
    );
  }
}
