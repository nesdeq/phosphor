import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ai_service.dart';
import '../../../core/services/sound_service.dart';
import '../../terminal/presentation/widgets/crt_overlay.dart';

/// The PHOSPHOR boot sequence — a love letter to 1980s POST screens.
/// Shows real system stats for an authentic feel.
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  final List<_BootLine> _lines = [];
  bool _showCursor = true;
  bool _canSkip = false;
  bool _isComplete = false;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    // Play CRT power-on sound IMMEDIATELY — before any visuals
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(soundServiceProvider).play(SoundEffect.crtOn);
    });
    _cursorTimer = Timer.periodic(
      const Duration(milliseconds: 530),
      (_) => setState(() => _showCursor = !_showCursor),
    );
    _runBootSequence();
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    super.dispose();
  }

  Future<void> _runBootSequence() async {
    // Gather real system info while the CRT warms up
    final sysInfo = await _SystemInfo.gather();

    // Brief CRT warm-up delay (sound is already playing)
    await _delay(800);
    _canSkip = true;

    // POST header
    await _addLine('PHOSPHOR BIOS v1.0', style: _BootStyle.bright);
    await _addLine('Copyright (c) 2026 Phosphor Systems Inc.');
    await _addLine('');

    // Real memory check — count up to actual RAM
    final ramMB = sysInfo.ramMB;
    await _addLine('Checking system memory...', newline: false);
    await _delay(200);
    final steps = _memorySteps(ramMB);
    for (final step in steps) {
      await _updateLastLine('Checking system memory... $step');
      await _delay(60);
    }
    await _updateLastLine(
      'Checking system memory... ${_formatBytes(ramMB)} OK',
      style: _BootStyle.bright,
    );
    await _addLine('');

    // Real hardware detection
    await _addLine('Detecting peripherals...');
    await _detectDevice('Processor', sysInfo.cpu);
    await _detectDevice('Cores', '${sysInfo.cores} logical');
    await _detectDevice('System', sysInfo.os);
    await _detectDevice('Shell', sysInfo.shell);
    await _detectDevice('Display', sysInfo.display);

    // AI coprocessor — show configured provider or "Not found"
    final aiConfig = ref.read(aiConfigProvider);
    final aiLabel = aiConfig.provider.hasKey
        ? '${aiConfig.provider.label} [ALAN]'
        : 'Not detected';
    await _detectDevice('AI Coprocessor', aiLabel);
    await _addLine('');

    // Loading bar
    await _addLine('Loading PHOSPHOR.SYS...', newline: false);
    for (var i = 0; i <= 100; i += 5) {
      final bar = '${'=' * (i ~/ 5)}>${' ' * (20 - i ~/ 5)}';
      await _updateLastLine('Loading PHOSPHOR.SYS... [$bar] $i%');
      final d = (i == 65) ? 600 : 40; // dramatic pause at 67%
      await _delay(d);
    }
    await _addLine('');

    // ASCII logo
    await _addLine('');
    for (final line in _asciiLogo) {
      await _addLine(line, style: _BootStyle.bright, typewriter: true);
    }
    await _addLine('');

    // Ready
    await _delay(300);
    await _addLine('Welcome to PHOSPHOR Terminal v0.1.5');
    await _addLine('The future of the terminal, rendered in phosphor.');
    await _addLine('');
    await _addLine('Ready.', style: _BootStyle.bright);

    await _delay(1200);
    _navigateToTerminal();
  }

  Future<void> _detectDevice(String name, String value) async {
    final padded = name.padRight(20, '.');
    await _addLine('  $padded ', newline: false);
    await _delay(120);
    await _updateLastLine('  $padded $value [OK]',
        style: _BootStyle.normal);
  }

  Future<void> _addLine(
    String text, {
    _BootStyle style = _BootStyle.normal,
    bool newline = true,
    bool typewriter = false,
  }) async {
    if (_isComplete) return;

    if (typewriter && text.isNotEmpty) {
      _lines.add(_BootLine('', style));
      for (var i = 0; i <= text.length; i++) {
        if (_isComplete) return;
        _lines.last = _BootLine(text.substring(0, i), style);
        setState(() {});
        await _delay(12);
      }
    } else {
      _lines.add(_BootLine(text, style));
      setState(() {});
    }
    if (newline) await _delay(30);
  }

  Future<void> _updateLastLine(String text, {_BootStyle? style}) async {
    if (_isComplete || _lines.isEmpty) return;
    _lines.last = _BootLine(text, style ?? _lines.last.style);
    setState(() {});
  }

  Future<void> _delay(int ms) async {
    if (_isComplete) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  void _navigateToTerminal() {
    if (!mounted || _isComplete) return;
    _isComplete = true;
    context.go('/terminal');
  }

  void _skip() {
    if (_canSkip && !_isComplete) {
      _navigateToTerminal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CrtOverlay(
        child: GestureDetector(
          onTap: _skip,
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) _skip();
              return KeyEventResult.handled;
            },
            child: Container(
              color: const Color(0xFF0A0A0A),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _lines.length,
                      itemBuilder: (context, index) {
                        final line = _lines[index];
                        final isLast = index == _lines.length - 1;
                        return Text.rich(
                          TextSpan(
                            text: line.text,
                            children: [
                              if (isLast && _showCursor)
                                const TextSpan(
                                  text: '\u2588',
                                  style: TextStyle(
                                    color: Color(0xFF33FF33),
                                  ),
                                ),
                            ],
                          ),
                          style: TextStyle(
                            fontFamily: 'PhosphorMono',
                            fontSize: 14,
                            height: 1.4,
                            color: switch (line.style) {
                              _BootStyle.bright => const Color(0xFF33FF33),
                              _BootStyle.normal => const Color(0xFF1A8C1A),
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  if (_canSkip && !_isComplete)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Press any key to skip...',
                        style: TextStyle(
                          fontFamily: 'PhosphorMono',
                          fontSize: 11,
                          color: Color(0xFF0E4D0E),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System info gathering
// ---------------------------------------------------------------------------

class _SystemInfo {
  final int ramMB;
  final String cpu;
  final int cores;
  final String os;
  final String shell;
  final String display;

  const _SystemInfo({
    required this.ramMB,
    required this.cpu,
    required this.cores,
    required this.os,
    required this.shell,
    required this.display,
  });

  static Future<_SystemInfo> gather() async {
    final cores = Platform.numberOfProcessors;
    final shell = (Platform.environment['SHELL'] ?? '/bin/sh').split('/').last;

    int ramMB = 0;
    String cpu = 'Unknown';
    String os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    String display = 'CRT';

    try {
      if (Platform.isMacOS) {
        // RAM
        final memResult =
            await Process.run('sysctl', ['-n', 'hw.memsize']);
        if (memResult.exitCode == 0) {
          final bytes = int.tryParse(memResult.stdout.toString().trim());
          if (bytes != null) ramMB = bytes ~/ (1024 * 1024);
        }
        // CPU
        final cpuResult =
            await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        if (cpuResult.exitCode == 0) {
          cpu = cpuResult.stdout.toString().trim();
        }
        // macOS version name
        final swResult = await Process.run('sw_vers', ['-productVersion']);
        if (swResult.exitCode == 0) {
          os = 'macOS ${swResult.stdout.toString().trim()}';
        }
        // Screen resolution
        final screenResult = await Process.run('system_profiler',
            ['SPDisplaysDataType', '-detailLevel', 'mini']);
        if (screenResult.exitCode == 0) {
          final output = screenResult.stdout.toString();
          final resMatch =
              RegExp(r'(\d{3,5})\s*x\s*(\d{3,5})').firstMatch(output);
          if (resMatch != null) {
            display = '${resMatch.group(1)} x ${resMatch.group(2)}';
          }
        }
      } else if (Platform.isLinux) {
        // RAM
        final memFile = File('/proc/meminfo');
        if (await memFile.exists()) {
          final content = await memFile.readAsString();
          final match =
              RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(content);
          if (match != null) {
            ramMB = (int.parse(match.group(1)!) / 1024).round();
          }
        }
        // CPU
        final cpuFile = File('/proc/cpuinfo');
        if (await cpuFile.exists()) {
          final content = await cpuFile.readAsString();
          final match =
              RegExp(r'model name\s*:\s*(.+)').firstMatch(content);
          if (match != null) cpu = match.group(1)!.trim();
        }
        // Kernel
        final unameResult = await Process.run('uname', ['-r']);
        if (unameResult.exitCode == 0) {
          os = 'Linux ${unameResult.stdout.toString().trim()}';
        }
      }
    } catch (_) {
      // Fallback to defaults on any error
    }

    // Truncate long CPU names for the retro display
    if (cpu.length > 42) cpu = '${cpu.substring(0, 39)}...';

    return _SystemInfo(
      ramMB: ramMB > 0 ? ramMB : 640, // fallback to the classic 640K
      cpu: cpu,
      cores: cores,
      os: os,
      shell: shell,
      display: display,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Generate retro memory count-up steps (powers of 2 up to actual RAM).
List<String> _memorySteps(int totalMB) {
  final steps = <String>[];
  // Count in KB for small amounts, MB for larger, GB for modern systems
  if (totalMB >= 1024) {
    // Count in GB steps
    final totalGB = totalMB / 1024;
    var gb = 1.0;
    while (gb < totalGB) {
      steps.add('${gb.toStringAsFixed(0)} GB');
      gb *= 2;
      if (gb > totalGB) break;
    }
  } else {
    // Count in MB
    var mb = 64;
    while (mb < totalMB) {
      steps.add('$mb MB');
      mb *= 2;
    }
  }
  return steps;
}

/// Format MB into a human-readable string.
String _formatBytes(int mb) {
  if (mb >= 1024) {
    final gb = mb / 1024;
    // Show as integer if it's a whole number, otherwise one decimal
    if (gb == gb.roundToDouble()) {
      return '${gb.round()} GB';
    }
    return '${gb.toStringAsFixed(1)} GB';
  }
  return '$mb MB';
}

enum _BootStyle { bright, normal }

class _BootLine {
  final String text;
  final _BootStyle style;
  const _BootLine(this.text, this.style);
}

const _asciiLogo = [
  r' ____  _   _  ___  ____  ____  _   _  ___  ____  ',
  r'|  _ \| | | |/ _ \/ ___||  _ \| | | |/ _ \|  _ \ ',
  r'| |_) | |_| | | | \___ \| |_) | |_| | | | | |_) |',
  r'|  __/|  _  | |_| |___) |  __/|  _  | |_| |  _ < ',
  r'|_|   |_| |_|\___/|____/|_|   |_| |_|\___/|_| \_\',
];
