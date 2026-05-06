import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cli_intelligence.dart';
import '../../../core/services/user_environment.dart';
import '../../terminal/providers/terminal_provider.dart';

/// Assembles shell context for AI prompts.
final shellContextProvider = Provider<ShellContext>((ref) {
  final session = ref.watch(terminalProvider);
  return ShellContext(session: session);
});

class ShellContext {
  final TerminalSession session;

  ShellContext({required this.session});

  /// Build a context string to prepend to AI system prompts.
  String buildContextString({
    List<CliTool>? tools,
    ProjectType? projectType,
  }) {
    final buf = StringBuffer();

    buf.writeln('=== SHELL CONTEXT ===');
    buf.writeln('Shell: ${userEnvironment['SHELL'] ?? 'unknown'}');
    buf.writeln(
        'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('CWD: ${session.workingDirectory}');

    if (projectType != null && projectType != ProjectType.unknown) {
      buf.writeln('Project type: ${projectType.label}');
      buf.writeln('Related tools: ${projectType.relatedTools.join(', ')}');
    }

    if (tools != null && tools.isNotEmpty) {
      final toolNames = tools.map((t) => t.name).take(30).join(', ');
      buf.writeln('Installed tools: $toolNames');
    }

    if (session.recentOutput.isNotEmpty) {
      final out = session.recentOutput;
      final start = out.length > 200 ? out.length - 200 : 0;
      final lastOutput = out.sublist(start).join('\n').trim();
      if (lastOutput.isNotEmpty) {
        buf.writeln('');
        buf.writeln('Recent terminal output:');
        buf.writeln(lastOutput);
      }
    }

    buf.writeln('=== END CONTEXT ===');
    return buf.toString();
  }
}
