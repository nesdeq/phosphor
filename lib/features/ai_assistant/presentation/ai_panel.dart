import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../core/services/sound_service.dart';
import '../providers/ai_provider.dart';

/// Slide-out AI chat side panel (Cmd+Shift+K).
class AiPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const AiPanel({super.key, required this.onClose});

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _prevInputLength = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(soundServiceProvider).playKeystroke(char: '\r');
    ref.read(aiChatProvider.notifier).sendMessage(text);
    _controller.clear();
    _prevInputLength = 0;
    // Scroll to bottom after a frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(phosphorPaletteProvider);
    final colors = palette.colors;
    final messages = ref.watch(aiChatProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.textDim, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: colors.textDim, width: 1)),
            ),
            child: Row(
              children: [
                Text(
                  'ALAN',
                  style: TextStyle(
                    fontFamily: 'PhosphorMono',
                    fontSize: 12,
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Text(
                    '[X]',
                    style: TextStyle(
                      fontFamily: 'PhosphorMono',
                      fontSize: 12,
                      color: colors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'ALAN — ghost in the machine.\n\n'
                        'Ask me anything about commands,\n'
                        'tools, or errors.\n\n'
                        'Try: "What does this error mean?"\n'
                        'Or:  "How do I find large files?"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'PhosphorMono',
                          fontSize: 12,
                          color: colors.textDim,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _ChatBubble(msg: msg, colors: colors);
                    },
                  ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: colors.textDim, width: 1)),
            ),
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
                    onSubmitted: (_) => _send(),
                    onChanged: (value) {
                      _prevInputLength = ref
                          .read(soundServiceProvider)
                          .handleTextFieldKeystroke(_prevInputLength, value);
                    },
                    style: TextStyle(
                      fontFamily: 'PhosphorMono',
                      fontSize: 13,
                      color: colors.text,
                    ),
                    cursorColor: colors.cursor,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Ask ALAN...',
                      hintStyle: TextStyle(
                        fontFamily: 'PhosphorMono',
                        fontSize: 13,
                        color: colors.textDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final AiChatMessage msg;
  final CrtColorScheme colors;

  const _ChatBubble({required this.msg, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? '> YOU' : '> ALAN',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 10,
              color: colors.textDim,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(
                color: isUser ? colors.textDim : colors.text,
                width: 1,
              ),
            ),
            child: Text(
              msg.content,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 12,
                color: isUser ? colors.textDim : colors.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
