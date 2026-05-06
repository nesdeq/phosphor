import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/settings_provider.dart';

/// Sound effects in PHOSPHOR.
enum SoundEffect {
  /// CRT power-on click — the "on" portion only.
  crtOn('sounds/crt_on.mp3');

  const SoundEffect(this.asset);
  final String asset;
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  ref.onDispose(service.dispose);

  // Update settings reactively without recreating the service
  ref.listen<CrtSettings>(crtSettingsProvider, (_, s) {
    service.volume = s.soundVolume;
    service.keyboardEnabled = s.keyboardSounds;
    service.bootEnabled = s.bootSound;
    service.ambientEnabled = s.ambientHum;
  }, fireImmediately: true);

  return service;
});

class SoundService {
  double volume;
  bool keyboardEnabled;
  bool bootEnabled;
  bool ambientEnabled;
  final _random = Random();

  /// Pool of players for overlapping keystroke sounds.
  final List<AudioPlayer> _pool = [];
  static const _poolSize = 4;

  /// Ambient CRT static loop.
  final AudioPlayer _ambientPlayer = AudioPlayer();
  bool _ambientPlaying = false;

  /// One-shot effects.
  final AudioPlayer _effectPlayer = AudioPlayer();

  /// Bucklespring keystroke samples — 8 regular key variants.
  static const _keystrokeFiles = [
    'sounds/keystrokes/key_01_0.wav',
    'sounds/keystrokes/key_02_0.wav',
    'sounds/keystrokes/key_03_0.wav',
    'sounds/keystrokes/key_04_0.wav',
    'sounds/keystrokes/key_05_0.wav',
    'sounds/keystrokes/key_06_0.wav',
    'sounds/keystrokes/key_07_0.wav',
    'sounds/keystrokes/key_08_0.wav',
  ];

  /// Special key sounds.
  static const _spaceFile = 'sounds/keystrokes/space_0.wav';
  static const _enterFile = 'sounds/keystrokes/enter_0.wav';
  static const _backspaceFile = 'sounds/keystrokes/backspace_0.wav';
  static const _tabFile = 'sounds/keystrokes/tab_0.wav';

  SoundService({
    this.volume = 0.5,
    this.keyboardEnabled = true,
    this.bootEnabled = true,
    this.ambientEnabled = true,
  }) {
    for (var i = 0; i < _poolSize; i++) {
      _pool.add(AudioPlayer());
    }
  }

  int _poolIndex = 0;

  AudioPlayer get _nextPlayer {
    final player = _pool[_poolIndex];
    _poolIndex = (_poolIndex + 1) % _poolSize;
    return player;
  }

  /// Play a keystroke sound — picks a random bucklespring sample.
  /// Space, enter, backspace, tab get their own dedicated samples.
  Future<void> playKeystroke({String? char}) async {
    if (volume <= 0 || !keyboardEnabled) return;
    try {
      final String asset;
      if (char == ' ') {
        asset = _spaceFile;
      } else if (char == '\n' || char == '\r') {
        asset = _enterFile;
      } else if (char == '\x7f' || char == '\b') {
        asset = _backspaceFile;
      } else if (char == '\t') {
        asset = _tabFile;
      } else {
        asset = _keystrokeFiles[_random.nextInt(_keystrokeFiles.length)];
      }

      final player = _nextPlayer;
      await player.setVolume(volume * (0.4 + _random.nextDouble() * 0.2));
      await player.play(AssetSource(asset));
    } catch (_) {}
  }

  /// Play a one-shot sound effect.
  Future<void> play(SoundEffect effect) async {
    if (volume <= 0) return;
    if (effect == SoundEffect.crtOn && !bootEnabled) return;
    try {
      await _effectPlayer.setVolume(volume);
      await _effectPlayer.play(AssetSource(effect.asset));
    } catch (_) {}
  }

  /// Handle keystroke sound for a TextField onChanged callback.
  /// Returns the new input length to track.
  int handleTextFieldKeystroke(int prevLength, String value) {
    if (volume <= 0 || !keyboardEnabled) return value.length;
    if (value.length < prevLength) {
      playKeystroke(char: '\b');
    } else if (value.length > prevLength) {
      playKeystroke(char: value.isNotEmpty ? value[value.length - 1] : null);
    }
    return value.length;
  }

  /// Start CRT static noise loop at low volume.
  Future<void> startAmbientStatic() async {
    if (volume <= 0 || !ambientEnabled || _ambientPlaying) return;
    try {
      await _ambientPlayer.setReleaseMode(ReleaseMode.loop);
      await _ambientPlayer.setVolume(volume * 0.2);
      await _ambientPlayer.play(AssetSource('sounds/crt_static.mp3'));
      _ambientPlaying = true;
    } catch (_) {}
  }

  void dispose() {
    for (final player in _pool) {
      player.dispose();
    }
    _ambientPlayer.dispose();
    _effectPlayer.dispose();
  }
}
