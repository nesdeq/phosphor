import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/phosphor_theme.dart';
import '../../../../app/widgets/crt_button.dart';
import '../../../../app/widgets/crt_dialog.dart';
import '../../../../app/widgets/crt_text_field.dart';
import '../../../../core/services/ai_service.dart';

/// Cmd+K command palette — natural language to shell command.
class CommandPalette extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;

  const CommandPalette({
    super.key,
    required this.onClose,
    required this.onSubmit,
  });

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _generatedCommand;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _generatedCommand = null;
    });

    try {
      final response = await ref.read(aiServiceProvider).chat([
        {
          'role': 'user',
          'content': 'Generate a single shell command for: $query\n\n'
              'Return ONLY the command, no explanation, no markdown, no backticks.'
        },
      ]);
      setState(() {
        _generatedCommand = response.trim();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(phosphorPaletteProvider).colors;

    return CrtDialog(
      title: 'COMMAND PALETTE',
      width: 500,
      onClose: widget.onClose,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: CrtTextField(
            controller: _controller,
            focusNode: _focusNode,
            prefix: '> ',
            fontSize: 14,
            hintText: 'Describe what you want to do...',
            onSubmitted: (_) => _generate(),
          ),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Generating...',
              style: TextStyle(fontSize: 12, color: colors.textDim),
            ),
          ),
        if (_generatedCommand != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.text, width: 1),
                  ),
                  child: Text(
                    '\$ $_generatedCommand',
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CrtButton(
                      label: 'CANCEL',
                      onTap: widget.onClose,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 8),
                    CrtButton(
                      label: 'RUN',
                      onTap: () => widget.onSubmit(_generatedCommand!),
                      filled: true,
                      fontSize: 12,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 11, color: colors.textDim),
            ),
          ),
      ],
    );
  }
}
