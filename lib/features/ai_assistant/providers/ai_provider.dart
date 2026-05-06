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
    NotifierProvider<AiChatNotifier, List<AiChatMessage>>(AiChatNotifier.new);

class AiChatNotifier extends Notifier<List<AiChatMessage>> {
  @override
  List<AiChatMessage> build() => [];

  Future<void> sendMessage(String text) async {
    state = [
      ...state,
      AiChatMessage(role: ChatRole.user, content: text),
    ];

    final aiService = ref.read(aiServiceProvider);
    try {
      // Build shell context — passed via the system prompt, not fake turns.
      final shellContext = ref.read(shellContextProvider);
      final tools = await ref.read(toolRegistryProvider.future);
      final projectType = await ref.read(projectTypeProvider.future);
      final extraSystem = shellContext.buildContextString(
        tools: tools,
        projectType: projectType,
      );

      final messages = state
          .map((m) => {'role': m.role.name, 'content': m.content})
          .toList();

      final response = await aiService.chat(messages, extraSystem: extraSystem);
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
