import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../app/widgets/crt_dialog.dart';
import '../../../core/services/ai_service.dart';
import '../providers/settings_provider.dart';

/// DOS-style settings panel overlay.
class SettingsScreen extends ConsumerWidget {
  final VoidCallback onClose;

  const SettingsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(crtSettingsProvider);
    final palette = ref.watch(phosphorPaletteProvider);
    final colors = palette.colors;

    return CrtDialog(
      title: ' P H O S P H O R   S E T T I N G S ',
      width: 520,
      onClose: onClose,
      constraints: const BoxConstraints(maxHeight: 600),
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                      _sectionHeader('DISPLAY', colors),
                      const SizedBox(height: 8),
                      _sliderRow(
                        'Font Scale',
                        settings.fontScale,
                        (v) => ref
                            .read(crtSettingsProvider.notifier)
                            .setFontScale(v),
                        colors,
                        min: 0.5,
                        max: 3.0,
                        displayValue: '${settings.fontScale.toStringAsFixed(1)}x',
                      ),
                      _sliderRow(
                        'CRT Intensity',
                        ref.watch(crtIntensityProvider),
                        (v) {
                          ref.read(crtIntensityProvider.notifier).state = v;
                          ref
                              .read(crtSettingsProvider.notifier)
                              .setIntensity(v);
                        },
                        colors,
                      ),
                      _toggleRow(
                        'Scanlines',
                        settings.scanlines,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleScanlines(),
                        colors,
                      ),
                      _toggleRow(
                        'Curvature',
                        settings.curvature,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleCurvature(),
                        colors,
                      ),
                      _toggleRow(
                        'Chromatic Aberr.',
                        settings.chromaticAberration,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleChromaticAberration(),
                        colors,
                      ),
                      _toggleRow(
                        'Flicker',
                        settings.flicker,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleFlicker(),
                        colors,
                      ),
                      const SizedBox(height: 16),
                      _sectionHeader('PHOSPHOR COLOR', colors),
                      const SizedBox(height: 8),
                      ...PhosphorPalette.values.map(
                        (p) => _radioRow(
                          p.label,
                          p == palette,
                          () => ref
                              .read(phosphorPaletteProvider.notifier)
                              .state = p,
                          colors,
                          previewColor: p.colors.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionHeader('AUDIO', colors),
                      const SizedBox(height: 8),
                      _sliderRow(
                        'Master Volume',
                        settings.soundVolume,
                        (v) => ref
                            .read(crtSettingsProvider.notifier)
                            .setSoundVolume(v),
                        colors,
                      ),
                      _toggleRow(
                        'Keyboard Sounds',
                        settings.keyboardSounds,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleKeyboardSounds(),
                        colors,
                      ),
                      _toggleRow(
                        'Boot Sound',
                        settings.bootSound,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleBootSound(),
                        colors,
                      ),
                      _toggleRow(
                        'Ambient Hum',
                        settings.ambientHum,
                        () => ref
                            .read(crtSettingsProvider.notifier)
                            .toggleAmbientHum(),
                        colors,
                      ),
                      const SizedBox(height: 16),
                      _buildAiSection(ref, colors),
                      const SizedBox(height: 16),
                      _sectionHeader('MULTIPLAYER', colors),
                      const SizedBox(height: 8),
                      _RelayUrlField(
                        initialValue: settings.relayServerUrl,
                        colors: colors,
                        label: 'Relay Server',
                        hint: 'wss://your-server:8766',
                        onChanged: (v) => ref
                            .read(crtSettingsProvider.notifier)
                            .setRelayServerUrl(v),
                      ),
                      _RelayUrlField(
                        initialValue: settings.relayCertPath,
                        colors: colors,
                        label: 'Server Cert',
                        hint: '~/.phosphor/public.pem',
                        onChanged: (v) => ref
                            .read(crtSettingsProvider.notifier)
                            .setRelayCertPath(v),
                      ),
                      const SizedBox(height: 24),
                      // Close button
                      Center(
                        child: GestureDetector(
                          onTap: onClose,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.text),
                            ),
                            child: Text(
                              '[ CLOSE ]',
                              style: TextStyle(
                                fontFamily: 'PhosphorMono',
                                fontSize: 14,
                                color: colors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label, CrtColorScheme colors) {
    return Text(
      '[$label]',
      style: TextStyle(
        fontFamily: 'PhosphorMono',
        fontSize: 14,
        color: colors.text,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    ValueChanged<double> onChanged,
    CrtColorScheme colors, {
    double min = 0.0,
    double max = 1.0,
    String? displayValue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.textDim,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: colors.text,
                inactiveTrackColor: colors.textDim.withValues(alpha: 0.3),
                thumbColor: colors.text,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              displayValue ?? '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    String label,
    bool value,
    VoidCallback onToggle,
    CrtColorScheme colors,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onToggle,
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 13,
                  color: colors.textDim,
                ),
              ),
            ),
            Text(
              value ? '[ON ]' : '[off]',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: value ? colors.text : colors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSection(WidgetRef ref, CrtColorScheme colors) {
    final aiConfig = ref.watch(aiConfigProvider);
    final modelsAsync = ref.watch(availableModelsProvider);
    final hasKey = aiConfig.provider.hasKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ALAN', colors),
        const SizedBox(height: 8),
        // Provider selector
        _selectorRow(
          'Provider',
          AiProvider.values.map((p) => p.label).toList(),
          aiConfig.provider.label,
          (label) {
            final provider =
                AiProvider.values.firstWhere((p) => p.label == label);
            ref.read(aiConfigProvider.notifier).state =
                aiConfig.copyWith(provider: provider, model: '');
          },
          colors,
        ),
        const SizedBox(height: 4),
        // Model selector — fetched live from the API
        modelsAsync.when(
          loading: () => _infoRow('Model', 'Fetching models...', colors),
          error: (e, _) =>
              _infoRow('Model', 'Failed to fetch models', colors),
          data: (models) {
            if (models.isEmpty) {
              return _infoRow(
                'Model',
                hasKey ? 'No models found' : 'No API key',
                colors,
              );
            }
            // Auto-select first model if none selected
            final current = aiConfig.model.isNotEmpty &&
                    models.contains(aiConfig.model)
                ? aiConfig.model
                : models.first;
            // Sync selection if it was empty
            if (aiConfig.model != current) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(aiConfigProvider.notifier).state =
                    aiConfig.copyWith(model: current);
              });
            }
            return _selectorRow(
              'Model',
              models,
              current,
              (model) {
                ref.read(aiConfigProvider.notifier).state =
                    aiConfig.copyWith(model: model);
              },
              colors,
            );
          },
        ),
        const SizedBox(height: 4),
        // API key status
        _infoRow(
          'API Key',
          hasKey
              ? '${aiConfig.provider.envKey} [OK]'
              : aiConfig.provider == AiProvider.ollama
                  ? 'Not required'
                  : '${aiConfig.provider.envKey} [MISSING]',
          colors,
          valueColor: hasKey ? colors.text : null,
        ),
        // Model count
        modelsAsync.whenOrNull(
              data: (models) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 160),
                    Text(
                      '${models.length} models available',
                      style: TextStyle(
                        fontFamily: 'PhosphorMono',
                        fontSize: 11,
                        color: colors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ) ??
            const SizedBox.shrink(),
      ],
    );
  }

  Widget _infoRow(
    String label,
    String value,
    CrtColorScheme colors, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.textDim,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: valueColor ?? colors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorRow(
    String label,
    List<String> options,
    String current,
    ValueChanged<String> onChanged,
    CrtColorScheme colors,
  ) {
    final idx = options.indexOf(current).clamp(0, options.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.textDim,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final prev = (idx - 1 + options.length) % options.length;
              onChanged(options[prev]);
            },
            child: Text(
              '< ',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.text,
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              current,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.text,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final next = (idx + 1) % options.length;
              onChanged(options[next]);
            },
            child: Text(
              ' >',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _radioRow(
    String label,
    bool selected,
    VoidCallback onTap,
    CrtColorScheme colors, {
    Color? previewColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              selected ? '(*)' : '( )',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.text,
              ),
            ),
            const SizedBox(width: 8),
            if (previewColor != null)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                color: previewColor,
              ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: selected ? colors.text : colors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stateful text field for relay settings.
class _RelayUrlField extends StatefulWidget {
  final String initialValue;
  final CrtColorScheme colors;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  const _RelayUrlField({
    required this.initialValue,
    required this.colors,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  State<_RelayUrlField> createState() => _RelayUrlFieldState();
}

class _RelayUrlFieldState extends State<_RelayUrlField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 13,
                color: colors.textDim,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colors.textDim),
              ),
              child: TextField(
                controller: _controller,
                onSubmitted: widget.onChanged,
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 13,
                  color: colors.text,
                ),
                cursorColor: colors.cursor,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    fontFamily: 'PhosphorMono',
                    fontSize: 13,
                    color: colors.textDim,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
