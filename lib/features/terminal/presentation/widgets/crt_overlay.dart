import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

import '../../../../features/settings/providers/settings_provider.dart';

/// CRT intensity setting (0.0 = clean, 1.0 = maximum retro).
final crtIntensityProvider = StateProvider<double>((ref) => 0.75);

/// Wraps a child widget with CRT post-processing effects:
/// scanlines, phosphor glow, barrel distortion, chromatic aberration, flicker.
class CrtOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const CrtOverlay({super.key, required this.child});

  @override
  ConsumerState<CrtOverlay> createState() => _CrtOverlayState();
}

class _CrtOverlayState extends ConsumerState<CrtOverlay>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = createTicker((elapsed) {
      setState(() {
        _time = elapsed.inMicroseconds / 1000000.0;
      });
    })..start();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/crt.frag');
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (e) {
      // Shader loading can fail on some platforms — fall back to no effects
      debugPrint('CRT shader not available: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intensity = ref.watch(crtIntensityProvider);
    final settings = ref.watch(crtSettingsProvider);

    // No shader loaded or effects disabled — render child directly
    if (_shader == null || intensity <= 0.0) {
      return widget.child;
    }

    return AnimatedSampler(
      enabled: true,
      (ui.Image image, Size size, Canvas canvas) {
        final shader = _shader!;

        // Scale effect strengths by global intensity; individual toggles
        // zero out their respective uniform when disabled in settings.
        shader
          ..setFloat(0, size.width) // uResolution.x
          ..setFloat(1, size.height) // uResolution.y
          ..setFloat(2, _time) // uTime
          ..setFloat(3, settings.curvature ? 0.04 * intensity : 0.0)
          ..setFloat(4, settings.scanlines ? 0.35 * intensity : 0.0)
          ..setFloat(5, 0.15 * intensity) // uGlowStrength (always on)
          ..setFloat(6, settings.chromaticAberration ? 0.0015 * intensity : 0.0)
          ..setFloat(7, settings.flicker ? 0.03 * intensity : 0.0)
          ..setFloat(8, 0.4 * intensity) // uVignetteStrength (always on)
          ..setImageSampler(0, image); // uTerminalTexture

        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..shader = shader,
        );
      },
      child: widget.child,
    );
  }
}
