import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../app/widgets/crt_button.dart';
import '../../../app/widgets/crt_dialog.dart';
import '../../../app/widgets/crt_text_field.dart';
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
    final n = ref.read(crtSettingsProvider.notifier);

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
                  n.setFontScale,
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
                    n.setIntensity(v);
                  },
                  colors,
                ),
                _toggleRow(
                    'Scanlines', settings.scanlines, n.toggleScanlines, colors),
                _toggleRow(
                    'Curvature', settings.curvature, n.toggleCurvature, colors),
                _toggleRow('Chromatic Aberr.', settings.chromaticAberration,
                    n.toggleChromaticAberration, colors),
                _toggleRow(
                    'Flicker', settings.flicker, n.toggleFlicker, colors),
                const SizedBox(height: 16),
                _sectionHeader('PHOSPHOR COLOR', colors),
                const SizedBox(height: 8),
                ...PhosphorPalette.values.map(
                  (p) => _radioRow(
                    p.label,
                    p == palette,
                    () => ref.read(phosphorPaletteProvider.notifier).state = p,
                    colors,
                    previewColor: p.colors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader('FONT', colors),
                const SizedBox(height: 8),
                ...TerminalFont.values.map(
                  (f) => _radioRow(
                    f.label,
                    f == settings.terminalFont,
                    () => n.setTerminalFont(f),
                    colors,
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader('AUDIO', colors),
                const SizedBox(height: 8),
                _sliderRow('Master Volume', settings.soundVolume,
                    n.setSoundVolume, colors),
                _toggleRow('Keyboard Sounds', settings.keyboardSounds,
                    n.toggleKeyboardSounds, colors),
                _toggleRow('Boot Sound', settings.bootSound, n.toggleBootSound,
                    colors),
                _toggleRow('Ambient Hum', settings.ambientHum,
                    n.toggleAmbientHum, colors),
                const SizedBox(height: 16),
                _buildAiSection(ref, colors),
                const SizedBox(height: 16),
                _sectionHeader('MULTIPLAYER', colors),
                const SizedBox(height: 8),
                _RelayField(
                  label: 'Relay Server',
                  hint: 'wss://your-server:8766',
                  initialValue: settings.relayServerUrl,
                  onSubmitted: n.setRelayServerUrl,
                ),
                _RelayField(
                  label: 'Server Cert',
                  hint: '~/.phosphor/public.pem',
                  initialValue: settings.relayCertPath,
                  onSubmitted: n.setRelayCertPath,
                ),
                const SizedBox(height: 24),
                Center(
                  child: CrtButton(
                    label: '[ CLOSE ]',
                    onTap: onClose,
                    fontSize: 14,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
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
        fontSize: 14,
        color: colors.text,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  static const _labelWidth = 160.0;

  Widget _label(String text, CrtColorScheme colors) => SizedBox(
        width: _labelWidth,
        child:
            Text(text, style: TextStyle(fontSize: 13, color: colors.textDim)),
      );

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
          _label(label, colors),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: colors.text,
                inactiveTrackColor: colors.textDim.withValues(alpha: 0.3),
                thumbColor: colors.text,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
              style: TextStyle(fontSize: 13, color: colors.text),
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
            _label(label, colors),
            Text(
              value ? '[ON ]' : '[off]',
              style: TextStyle(
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

    void setProvider(AiProvider p) =>
        ref.read(aiConfigProvider.notifier).state =
            aiConfig.copyWith(provider: p, model: '');
    void setModel(String m) =>
        ref.read(aiConfigProvider.notifier).state = aiConfig.copyWith(model: m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ALAN', colors),
        const SizedBox(height: 8),
        _selectorRow(
          'Provider',
          AiProvider.values.map((p) => p.label).toList(),
          aiConfig.provider.label,
          (label) => setProvider(
              AiProvider.values.firstWhere((p) => p.label == label)),
          colors,
        ),
        const SizedBox(height: 4),
        modelsAsync.when(
          loading: () => _infoRow('Model', 'Fetching models...', colors),
          error: (_, __) => _infoRow('Model', 'Failed to fetch models', colors),
          data: (models) {
            if (models.isEmpty) {
              return _infoRow(
                'Model',
                hasKey ? 'No models found' : 'No API key',
                colors,
              );
            }
            final current =
                aiConfig.model.isNotEmpty && models.contains(aiConfig.model)
                    ? aiConfig.model
                    : models.first;
            if (aiConfig.model != current) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setModel(current);
              });
            }
            return _selectorRow('Model', models, current, setModel, colors);
          },
        ),
        const SizedBox(height: 4),
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
        modelsAsync.whenOrNull(
              data: (models) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const SizedBox(width: _labelWidth),
                    Text(
                      '${models.length} models available',
                      style: TextStyle(fontSize: 11, color: colors.textDim),
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
          _label(label, colors),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
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
    Widget arrow(String text, int delta) => GestureDetector(
          onTap: () => onChanged(
              options[(idx + delta + options.length) % options.length]),
          child: Text(text, style: TextStyle(fontSize: 13, color: colors.text)),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _label(label, colors),
          arrow('< ', -1),
          SizedBox(
            width: 200,
            child: Text(
              current,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.text),
            ),
          ),
          arrow(' >', 1),
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
              style: TextStyle(fontSize: 13, color: colors.text),
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

/// Labeled relay text field — owns its own controller seeded with the
/// persisted value and commits changes on submit.
class _RelayField extends ConsumerStatefulWidget {
  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onSubmitted;

  const _RelayField({
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onSubmitted,
  });

  @override
  ConsumerState<_RelayField> createState() => _RelayFieldState();
}

class _RelayFieldState extends ConsumerState<_RelayField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(phosphorPaletteProvider).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 13, color: colors.textDim),
            ),
          ),
          Expanded(
            child: CrtTextField(
              controller: _controller,
              hintText: widget.hint,
              onSubmitted: widget.onSubmitted,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: colors.textDim),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
