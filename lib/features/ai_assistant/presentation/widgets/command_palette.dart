import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/crt_colors.dart';
import '../../../../app/theme/phosphor_theme.dart';
import '../../../../app/widgets/crt_dialog.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../core/services/sound_service.dart';

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
  int _prevInputLength = 0;

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
      final aiService = ref.read(aiServiceProvider);
      final response = await aiService.chat([
        {
          'role': 'user',
          'content':
              'Generate a single shell command for: $query\n\n'
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
        // Input
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '> ',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 14,
                  color: colors.text,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: (_) {
                    ref.read(soundServiceProvider).playKeystroke(char: '\r');
                    _generate();
                  },
                  onChanged: (value) {
                    _prevInputLength = ref
                        .read(soundServiceProvider)
                        .handleTextFieldKeystroke(
                            _prevInputLength, value);
                  },
                  style: TextStyle(
                    fontFamily: 'PhosphorMono',
                    fontSize: 14,
                    color: colors.text,
                  ),
                  cursorColor: colors.cursor,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Describe what you want to do...',
                    hintStyle: TextStyle(
                      fontFamily: 'PhosphorMono',
                      fontSize: 14,
                      color: colors.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Result
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Generating...',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 12,
                color: colors.textDim,
              ),
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
                    style: TextStyle(
                      fontFamily: 'PhosphorMono',
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _paletteButton('CANCEL', widget.onClose, colors,
                        primary: false),
                    const SizedBox(width: 8),
                    _paletteButton(
                        'RUN',
                        () => widget.onSubmit(_generatedCommand!),
                        colors,
                        primary: true),
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
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 11,
                color: colors.textDim,
              ),
            ),
          ),
      ],
    );
  }

  Widget _paletteButton(
    String label,
    VoidCallback onTap,
    CrtColorScheme colors, {
    required bool primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: primary ? colors.text : Colors.transparent,
          border: Border.all(color: colors.text),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'PhosphorMono',
            fontSize: 12,
            color: primary ? colors.background : colors.text,
          ),
        ),
      ),
    );
  }
}
