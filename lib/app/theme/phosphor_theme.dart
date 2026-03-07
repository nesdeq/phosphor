import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crt_colors.dart';

/// Current phosphor palette selection.
final phosphorPaletteProvider =
    StateProvider<PhosphorPalette>((ref) => PhosphorPalette.green);

/// Builds the app-wide ThemeData from the active phosphor palette.
final phosphorThemeProvider = Provider<ThemeData>((ref) {
  final palette = ref.watch(phosphorPaletteProvider);
  final colors = palette.colors;

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.dark(
      primary: colors.text,
      secondary: colors.glow,
      surface: colors.background,
    ),
    fontFamily: 'PhosphorMono',
    textTheme: TextTheme(
      bodyLarge: TextStyle(
        color: colors.text,
        fontFamily: 'PhosphorMono',
        fontSize: 16,
        height: 1.2,
      ),
      bodyMedium: TextStyle(
        color: colors.text,
        fontFamily: 'PhosphorMono',
        fontSize: 14,
        height: 1.2,
      ),
      bodySmall: TextStyle(
        color: colors.textDim,
        fontFamily: 'PhosphorMono',
        fontSize: 12,
        height: 1.2,
      ),
    ),
  );
});
