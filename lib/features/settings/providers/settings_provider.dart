import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../core/services/ai_service.dart';

/// CRT effect intensity (0.0 = clean, 1.0 = maximum retro).
/// Lives here (not in crt_overlay.dart) because settings state must not
/// depend on presentation widgets.
final crtIntensityProvider = StateProvider<double>((ref) => 0.75);

/// CRT effect settings — controls shader uniforms.
class CrtSettings {
  final double intensity;
  final bool scanlines;
  final bool curvature;
  final bool chromaticAberration;
  final bool flicker;
  final double soundVolume;
  final bool keyboardSounds;
  final bool bootSound;
  final bool ambientHum;
  final double fontScale;
  final String relayServerUrl;
  final String relayCertPath;

  const CrtSettings({
    this.intensity = 0.75,
    this.scanlines = true,
    this.curvature = true,
    this.chromaticAberration = true,
    this.flicker = true,
    this.soundVolume = 0.5,
    this.keyboardSounds = true,
    this.bootSound = true,
    this.ambientHum = true,
    this.fontScale = 1.5,
    this.relayServerUrl = '',
    this.relayCertPath = '',
  });

  CrtSettings copyWith({
    double? intensity,
    bool? scanlines,
    bool? curvature,
    bool? chromaticAberration,
    bool? flicker,
    double? soundVolume,
    bool? keyboardSounds,
    bool? bootSound,
    bool? ambientHum,
    double? fontScale,
    String? relayServerUrl,
    String? relayCertPath,
  }) {
    return CrtSettings(
      intensity: intensity ?? this.intensity,
      scanlines: scanlines ?? this.scanlines,
      curvature: curvature ?? this.curvature,
      chromaticAberration: chromaticAberration ?? this.chromaticAberration,
      flicker: flicker ?? this.flicker,
      soundVolume: soundVolume ?? this.soundVolume,
      keyboardSounds: keyboardSounds ?? this.keyboardSounds,
      bootSound: bootSound ?? this.bootSound,
      ambientHum: ambientHum ?? this.ambientHum,
      fontScale: fontScale ?? this.fontScale,
      relayServerUrl: relayServerUrl ?? this.relayServerUrl,
      relayCertPath: relayCertPath ?? this.relayCertPath,
    );
  }
}

/// SharedPreferences instance — initialized at app startup.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

/// Global CRT settings state with persistence.
final crtSettingsProvider =
    StateNotifierProvider<CrtSettingsNotifier, CrtSettings>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return CrtSettingsNotifier(prefs, ref);
});

class CrtSettingsNotifier extends StateNotifier<CrtSettings> {
  final SharedPreferences _prefs;
  final Ref _ref;

  CrtSettingsNotifier(this._prefs, this._ref)
      : super(CrtSettings(
          intensity: _prefs.getDouble('crt_intensity') ?? 0.75,
          scanlines: _prefs.getBool('crt_scanlines') ?? true,
          curvature: _prefs.getBool('crt_curvature') ?? true,
          chromaticAberration: _prefs.getBool('crt_chromatic') ?? true,
          flicker: _prefs.getBool('crt_flicker') ?? true,
          soundVolume: _prefs.getDouble('sound_volume') ?? 0.5,
          keyboardSounds: _prefs.getBool('keyboard_sounds') ?? true,
          bootSound: _prefs.getBool('boot_sound') ?? true,
          ambientHum: _prefs.getBool('ambient_hum') ?? true,
          fontScale: _prefs.getDouble('font_scale') ?? 1.5,
          relayServerUrl:
              _prefs.getString('relay_server_url') ?? '',
          relayCertPath:
              _prefs.getString('relay_cert_path') ?? '',
        )) {
    // Sync CRT intensity to the overlay provider on init
    Future.microtask(() {
      _ref.read(crtIntensityProvider.notifier).state = state.intensity;
    });

    // Restore palette
    final paletteIdx = _prefs.getInt('phosphor_palette');
    if (paletteIdx != null && paletteIdx < PhosphorPalette.values.length) {
      Future.microtask(() {
        _ref.read(phosphorPaletteProvider.notifier).state =
            PhosphorPalette.values[paletteIdx];
      });
    }

    // Restore AI config
    final providerIdx = _prefs.getInt('ai_provider');
    final model = _prefs.getString('ai_model');
    if (providerIdx != null && providerIdx < AiProvider.values.length) {
      Future.microtask(() {
        _ref.read(aiConfigProvider.notifier).state = AiConfig(
          provider: AiProvider.values[providerIdx],
          model: model ?? '',
        );
      });
    }

    // Auto-persist AI config whenever it changes
    _ref.listen<AiConfig>(aiConfigProvider, (_, next) {
      _prefs.setInt('ai_provider', next.provider.index);
      _prefs.setString('ai_model', next.model);
    });

    // Auto-persist palette whenever it changes
    _ref.listen<PhosphorPalette>(phosphorPaletteProvider, (_, next) {
      _prefs.setInt('phosphor_palette', next.index);
    });
  }

  void _save() {
    _prefs.setDouble('crt_intensity', state.intensity);
    _prefs.setBool('crt_scanlines', state.scanlines);
    _prefs.setBool('crt_curvature', state.curvature);
    _prefs.setBool('crt_chromatic', state.chromaticAberration);
    _prefs.setBool('crt_flicker', state.flicker);
    _prefs.setDouble('sound_volume', state.soundVolume);
    _prefs.setBool('keyboard_sounds', state.keyboardSounds);
    _prefs.setBool('boot_sound', state.bootSound);
    _prefs.setBool('ambient_hum', state.ambientHum);
    _prefs.setDouble('font_scale', state.fontScale);
    _prefs.setString('relay_server_url', state.relayServerUrl);
    _prefs.setString('relay_cert_path', state.relayCertPath);
  }

  void setIntensity(double value) {
    state = state.copyWith(intensity: value.clamp(0.0, 1.0));
    _save();
  }

  void toggleScanlines() {
    state = state.copyWith(scanlines: !state.scanlines);
    _save();
  }

  void toggleCurvature() {
    state = state.copyWith(curvature: !state.curvature);
    _save();
  }

  void toggleChromaticAberration() {
    state = state.copyWith(chromaticAberration: !state.chromaticAberration);
    _save();
  }

  void toggleFlicker() {
    state = state.copyWith(flicker: !state.flicker);
    _save();
  }

  void setSoundVolume(double value) {
    state = state.copyWith(soundVolume: value.clamp(0.0, 1.0));
    _save();
  }

  void setFontScale(double value) {
    state = state.copyWith(fontScale: value.clamp(0.5, 3.0));
    _save();
  }

  void toggleKeyboardSounds() {
    state = state.copyWith(keyboardSounds: !state.keyboardSounds);
    _save();
  }

  void toggleBootSound() {
    state = state.copyWith(bootSound: !state.bootSound);
    _save();
  }

  void toggleAmbientHum() {
    state = state.copyWith(ambientHum: !state.ambientHum);
    _save();
  }

  void setRelayServerUrl(String value) {
    state = state.copyWith(relayServerUrl: value.trim());
    _save();
  }

  void setRelayCertPath(String value) {
    state = state.copyWith(relayCertPath: value.trim());
    _save();
  }
}
