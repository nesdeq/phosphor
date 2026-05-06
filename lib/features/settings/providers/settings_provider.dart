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
  final TerminalFont terminalFont;
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
    this.terminalFont = TerminalFont.departureMono,
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
    TerminalFont? terminalFont,
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
      terminalFont: terminalFont ?? this.terminalFont,
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
          terminalFont: TerminalFont.values[
              (_prefs.getInt('terminal_font') ?? 0)
                  .clamp(0, TerminalFont.values.length - 1)],
          relayServerUrl: _prefs.getString('relay_server_url') ?? '',
          relayCertPath: _prefs.getString('relay_cert_path') ?? '',
        )) {
    _hydrateSiblingProviders();
    _wireSiblingPersistence();
  }

  /// Restore palette + AI config + intensity into their own providers.
  /// Deferred to a microtask because their notifiers may not be reachable
  /// during this notifier's own construction.
  void _hydrateSiblingProviders() {
    Future.microtask(() {
      _ref.read(crtIntensityProvider.notifier).state = state.intensity;

      final paletteIdx = _prefs.getInt('phosphor_palette');
      if (paletteIdx != null && paletteIdx < PhosphorPalette.values.length) {
        _ref.read(phosphorPaletteProvider.notifier).state =
            PhosphorPalette.values[paletteIdx];
      }

      final providerIdx = _prefs.getInt('ai_provider');
      if (providerIdx != null && providerIdx < AiProvider.values.length) {
        _ref.read(aiConfigProvider.notifier).state = AiConfig(
          provider: AiProvider.values[providerIdx],
          model: _prefs.getString('ai_model') ?? '',
        );
      }
    });
  }

  /// AI config and palette live in separate providers; mirror their
  /// changes back to disk so the persistence model stays uniform.
  void _wireSiblingPersistence() {
    _ref.listen<AiConfig>(aiConfigProvider, (_, next) {
      _prefs.setInt('ai_provider', next.provider.index);
      _prefs.setString('ai_model', next.model);
    });
    _ref.listen<PhosphorPalette>(phosphorPaletteProvider, (_, next) {
      _prefs.setInt('phosphor_palette', next.index);
    });
  }

  /// Apply [update] to produce the next state, then persist only the keys
  /// whose values actually changed. Single source of truth — every setter
  /// flows through here so no key is forgotten and no key is rewritten
  /// unnecessarily.
  void _update(CrtSettings Function(CrtSettings) update) {
    final prev = state;
    final next = update(prev);
    if (identical(prev, next)) return;
    state = next;

    if (prev.intensity != next.intensity) {
      _prefs.setDouble('crt_intensity', next.intensity);
    }
    if (prev.scanlines != next.scanlines) {
      _prefs.setBool('crt_scanlines', next.scanlines);
    }
    if (prev.curvature != next.curvature) {
      _prefs.setBool('crt_curvature', next.curvature);
    }
    if (prev.chromaticAberration != next.chromaticAberration) {
      _prefs.setBool('crt_chromatic', next.chromaticAberration);
    }
    if (prev.flicker != next.flicker) {
      _prefs.setBool('crt_flicker', next.flicker);
    }
    if (prev.soundVolume != next.soundVolume) {
      _prefs.setDouble('sound_volume', next.soundVolume);
    }
    if (prev.keyboardSounds != next.keyboardSounds) {
      _prefs.setBool('keyboard_sounds', next.keyboardSounds);
    }
    if (prev.bootSound != next.bootSound) {
      _prefs.setBool('boot_sound', next.bootSound);
    }
    if (prev.ambientHum != next.ambientHum) {
      _prefs.setBool('ambient_hum', next.ambientHum);
    }
    if (prev.fontScale != next.fontScale) {
      _prefs.setDouble('font_scale', next.fontScale);
    }
    if (prev.terminalFont != next.terminalFont) {
      _prefs.setInt('terminal_font', next.terminalFont.index);
    }
    if (prev.relayServerUrl != next.relayServerUrl) {
      _prefs.setString('relay_server_url', next.relayServerUrl);
    }
    if (prev.relayCertPath != next.relayCertPath) {
      _prefs.setString('relay_cert_path', next.relayCertPath);
    }
  }

  void setIntensity(double value) =>
      _update((s) => s.copyWith(intensity: value.clamp(0.0, 1.0)));
  void toggleScanlines() => _update((s) => s.copyWith(scanlines: !s.scanlines));
  void toggleCurvature() => _update((s) => s.copyWith(curvature: !s.curvature));
  void toggleChromaticAberration() =>
      _update((s) => s.copyWith(chromaticAberration: !s.chromaticAberration));
  void toggleFlicker() => _update((s) => s.copyWith(flicker: !s.flicker));
  void setSoundVolume(double value) =>
      _update((s) => s.copyWith(soundVolume: value.clamp(0.0, 1.0)));
  void setFontScale(double value) =>
      _update((s) => s.copyWith(fontScale: value.clamp(0.5, 3.0)));
  void toggleKeyboardSounds() =>
      _update((s) => s.copyWith(keyboardSounds: !s.keyboardSounds));
  void toggleBootSound() => _update((s) => s.copyWith(bootSound: !s.bootSound));
  void toggleAmbientHum() =>
      _update((s) => s.copyWith(ambientHum: !s.ambientHum));
  void setTerminalFont(TerminalFont value) =>
      _update((s) => s.copyWith(terminalFont: value));
  void setRelayServerUrl(String value) =>
      _update((s) => s.copyWith(relayServerUrl: value.trim()));
  void setRelayCertPath(String value) =>
      _update((s) => s.copyWith(relayCertPath: value.trim()));
}
