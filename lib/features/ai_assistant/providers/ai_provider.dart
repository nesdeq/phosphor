import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ai_service.dart';
import '../../../core/services/cli_intelligence.dart';
import 'context_provider.dart';

enum ChatRole { user, assistant }

class AiChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;

  AiChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Chat message history for the AI side panel.
final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, List<AiChatMessage>>((ref) {
  return AiChatNotifier(ref);
});

class AiChatNotifier extends StateNotifier<List<AiChatMessage>> {
  final Ref _ref;

  AiChatNotifier(this._ref) : super([]);

  Future<void> sendMessage(String text) async {
    state = [
      ...state,
      AiChatMessage(role: ChatRole.user, content: text),
    ];

    final aiService = _ref.read(aiServiceProvider);
    try {
      // Build shell context for the AI (use cached providers, not raw scans)
      final shellContext = _ref.read(shellContextProvider);
      final tools = await _ref.read(toolRegistryProvider.future);
      final projectType = await _ref.read(projectTypeProvider.future);

      final contextStr = shellContext.buildContextString(
        tools: tools,
        projectType: projectType,
      );

      // Prepend context to the first user message
      final messages = state
          .map((m) => {'role': m.role.name, 'content': m.content})
          .toList();

      // Inject context into the system via the first message
      if (messages.isNotEmpty) {
        messages.insert(0, {
          'role': 'user',
          'content': contextStr,
        });
        messages.insert(1, {
          'role': 'assistant',
          'content':
              'I have your shell context. How can I help?',
        });
      }

      final response = await aiService.chat(messages);
      state = [
        ...state,
        AiChatMessage(role: ChatRole.assistant, content: response),
      ];
    } catch (e) {
      state = [
        ...state,
        AiChatMessage(
          role: ChatRole.assistant,
          content: 'Error: $e\n\n'
              'Check Settings (Cmd+,) to configure ALAN.',
        ),
      ];
    }
  }

  void clear() => state = [];
}
