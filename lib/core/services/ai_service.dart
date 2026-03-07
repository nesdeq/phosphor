import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'user_environment.dart';

/// Supported AI providers.
enum AiProvider {
  anthropic('Anthropic', 'ANTHROPIC_API_KEY', 'https://api.anthropic.com'),
  openai('OpenAI', 'OPENAI_API_KEY', 'https://api.openai.com'),
  ollama('Ollama (local)', '', 'http://localhost:11434');

  const AiProvider(this.label, this.envKey, this.defaultBaseUrl);
  final String label;
  final String envKey;
  final String defaultBaseUrl;

  /// Read API key from user's shell environment.
  String get apiKey =>
      envKey.isNotEmpty ? (userEnvironment[envKey] ?? '') : '';

  bool get hasKey => apiKey.isNotEmpty || this == AiProvider.ollama;
}

/// AI backend configuration.
class AiConfig {
  final AiProvider provider;
  final String model;

  const AiConfig({
    required this.provider,
    required this.model,
  });

  String get apiKey => provider.apiKey;
  String get baseUrl => provider.defaultBaseUrl;

  AiConfig copyWith({AiProvider? provider, String? model}) {
    return AiConfig(
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }

  /// Pick the best provider based on available env keys.
  static AiConfig fromEnvironment() {
    if (AiProvider.anthropic.hasKey) {
      return const AiConfig(
        provider: AiProvider.anthropic,
        model: '', // will be set once models are fetched
      );
    }
    if (AiProvider.openai.hasKey) {
      return const AiConfig(
        provider: AiProvider.openai,
        model: '',
      );
    }
    return const AiConfig(
      provider: AiProvider.ollama,
      model: '',
    );
  }
}

final aiConfigProvider = StateProvider<AiConfig>((ref) {
  return AiConfig.fromEnvironment();
});

/// Fetches models for ALL providers once on startup, caches the results.
/// No re-fetching on provider switch — just a map lookup.
final allModelsProvider =
    FutureProvider<Map<AiProvider, List<String>>>((ref) async {
  final results = <AiProvider, List<String>>{};
  // Fetch all providers in parallel
  final futures = AiProvider.values.map((p) async {
    results[p] = await AiService.fetchModels(p);
  });
  await Future.wait(futures);
  return results;
});

/// Models for the currently selected provider (reads from cache).
final availableModelsProvider = FutureProvider<List<String>>((ref) async {
  final config = ref.watch(aiConfigProvider);
  final allModels = await ref.watch(allModelsProvider.future);
  return allModels[config.provider] ?? [];
});

final aiServiceProvider = Provider<AiService>((ref) {
  final config = ref.watch(aiConfigProvider);
  return AiService(config);
});

/// Handles communication with LLM APIs.
class AiService {
  final AiConfig config;

  AiService(this.config);

  /// Fetch available models from a provider's API.
  static Future<List<String>> fetchModels(AiProvider provider) async {
    try {
      return switch (provider) {
        AiProvider.anthropic => _fetchOpenAICompatibleModels(provider, {
            'x-api-key': provider.apiKey,
            'anthropic-version': '2023-06-01',
          }),
        AiProvider.openai => _fetchOpenAICompatibleModels(provider, {
            'Authorization': 'Bearer ${provider.apiKey}',
          }),
        AiProvider.ollama => _fetchOllamaModels(provider),
      };
    } catch (e) {
      return [];
    }
  }

  /// Fetch models from APIs using the OpenAI-compatible /v1/models format.
  static Future<List<String>> _fetchOpenAICompatibleModels(
    AiProvider provider,
    Map<String, String> headers,
  ) async {
    if (!provider.hasKey) return [];
    final response = await http
        .get(
          Uri.parse('${provider.defaultBaseUrl}/v1/models'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    final models = (data['data'] as List?)
            ?.map((m) => m['id'] as String)
            .toList() ??
        [];
    models.sort();
    return models;
  }

  static Future<List<String>> _fetchOllamaModels(AiProvider provider) async {
    try {
      final response = await http
          .get(Uri.parse('${provider.defaultBaseUrl}/api/tags'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final models = (data['models'] as List?)
              ?.map((m) => m['name'] as String)
              .toList() ??
          [];
      models.sort();
      return models;
    } catch (_) {
      return [];
    }
  }

  static const _systemPrompt =
      'You are ALAN, the ghost in the machine inside PHOSPHOR, a retro CRT terminal emulator. '
      'You help users with shell commands, explain errors, suggest tools, and provide concise answers. '
      'Rules: '
      '- Always return valid shell commands for the user\'s detected shell and OS. '
      '- Be concise. Terminal users want short, actionable answers. '
      '- When suggesting commands, wrap them in backticks. '
      '- Warn about destructive operations (rm -rf, dd, etc). '
      '- If you don\'t know something, say so. Don\'t hallucinate flags.';

  Future<String> chat(List<Map<String, String>> messages) async {
    if (!config.provider.hasKey) {
      return 'No API key found.\n\n'
          'Set one of these environment variables:\n'
          '  export ANTHROPIC_API_KEY="sk-ant-..."\n'
          '  export OPENAI_API_KEY="sk-..."\n\n'
          'Then relaunch PHOSPHOR.';
    }

    if (config.model.isEmpty) {
      return 'No model selected.\n\n'
          'Open Settings (Cmd+,) and pick a model.';
    }

    return switch (config.provider) {
      AiProvider.anthropic => _chatAnthropic(messages),
      AiProvider.openai => _chatOpenAI(messages),
      AiProvider.ollama => _chatOllama(messages),
    };
  }

  Future<String> _chatAnthropic(List<Map<String, String>> messages) async {
    final response = await http
        .post(
          Uri.parse('${config.baseUrl}/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': config.apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': config.model,
            'max_tokens': 1024,
            'system': _systemPrompt,
            'messages': messages,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
          'Anthropic ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['content'][0]['text'] as String;
  }

  /// Whether the model is a reasoning model that requires max_completion_tokens
  /// and rejects the legacy max_tokens parameter.
  static bool _isReasoningModel(String model) {
    return model.startsWith('gpt-5') ||
        model.startsWith('o1') ||
        model.startsWith('o3') ||
        model.startsWith('o4');
  }

  Future<String> _chatOpenAI(List<Map<String, String>> messages) async {
    final allMessages = [
      {'role': 'system', 'content': _systemPrompt},
      ...messages,
    ];

    final reasoning = _isReasoningModel(config.model);

    final response = await http
        .post(
          Uri.parse('${config.baseUrl}/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.model,
            'messages': allMessages,
            // GPT-5 and reasoning models require max_completion_tokens;
            // they reject the legacy max_tokens parameter entirely.
            if (reasoning) 'max_completion_tokens': 8192 else 'max_tokens': 1024,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
          'OpenAI ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _chatOllama(List<Map<String, String>> messages) async {
    final allMessages = [
      {'role': 'system', 'content': _systemPrompt},
      ...messages,
    ];

    final response = await http
        .post(
          Uri.parse('${config.baseUrl}/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': config.model,
            'messages': allMessages,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
          'Ollama ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['message']['content'] as String;
  }
}
