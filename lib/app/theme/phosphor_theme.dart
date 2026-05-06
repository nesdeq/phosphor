import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/settings_provider.dart';
import 'crt_colors.dart';

/// Current phosphor palette selection.
final phosphorPaletteProvider =
    NotifierProvider<PhosphorPaletteNotifier, PhosphorPalette>(
  PhosphorPaletteNotifier.new,
);

class PhosphorPaletteNotifier extends Notifier<PhosphorPalette> {
  @override
  PhosphorPalette build() => PhosphorPalette.green;

  void set(PhosphorPalette palette) => state = palette;
}

/// Builds the app-wide ThemeData from the active phosphor palette and
/// terminal font. Setting `fontFamily` on ThemeData cascades to every
/// descendant Text widget — call sites should not repeat it.
final phosphorThemeProvider = Provider<ThemeData>((ref) {
  final palette = ref.watch(phosphorPaletteProvider);
  final colors = palette.colors;
  final font = ref.watch(crtSettingsProvider.select((s) => s.terminalFont));

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.dark(
      primary: colors.text,
      secondary: colors.glow,
      surface: colors.background,
    ),
    fontFamily: font.family,
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: colors.text, fontSize: 16, height: 1.2),
      bodyMedium: TextStyle(color: colors.text, fontSize: 14, height: 1.2),
      bodySmall: TextStyle(color: colors.textDim, fontSize: 12, height: 1.2),
    ),
  );
});
