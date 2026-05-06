import 'package:flutter/material.dart';

/// Universal error/alert red used by error banners, REPLAY indicator,
/// and the ANSI red cell color. Outside the phosphor palette by design.
const Color crtErrorRed = Color(0xFFFF3333);

/// VT100-standard initial terminal dimensions. Used as the bootstrap size
/// for the live terminal, peer-side terminal, and replay terminal — any
/// real layout overrides this on the first frame.
const int kInitialTerminalCols = 80;
const int kInitialTerminalRows = 24;

/// Terminal display font. Each variant maps to a Flutter font family
/// declared in pubspec.yaml; all three are Nerd Font patched.
enum TerminalFont {
  departureMono('Departure Mono', 'DepartureMono'),
  ibm3270('IBM 3270', 'IBM3270'),
  jetBrainsMono('JetBrains Mono', 'JetBrainsMono');

  const TerminalFont(this.label, this.family);
  final String label;
  final String family;
}

/// Color set for a single phosphor palette.
class CrtColorScheme {
  final Color text;
  final Color textDim;
  final Color background;
  final Color glow;
  final Color cursor;
  final Color selection;

  const CrtColorScheme({
    required this.text,
    required this.textDim,
    required this.background,
    required this.glow,
    required this.cursor,
    required this.selection,
  });
}

/// Available phosphor palettes, modeled after real CRT phosphor types.
enum PhosphorPalette {
  /// P1 phosphor — classic green terminal
  green(
    label: 'Green (P1)',
    colors: CrtColorScheme(
      text: Color(0xFF33FF33),
      textDim: Color(0xFF1A8C1A),
      background: Color(0xFF0A0A0A),
      glow: Color(0xFF00FF41),
      cursor: Color(0xFF33FF33),
      selection: Color(0xFF1A5C1A),
    ),
  ),

  /// P3 phosphor — warm amber
  amber(
    label: 'Amber (P3)',
    colors: CrtColorScheme(
      text: Color(0xFFFFB000),
      textDim: Color(0xFF8C6000),
      background: Color(0xFF0A0800),
      glow: Color(0xFFFFC000),
      cursor: Color(0xFFFFB000),
      selection: Color(0xFF5C4000),
    ),
  ),

  /// P4 phosphor — cool white
  white(
    label: 'White (P4)',
    colors: CrtColorScheme(
      text: Color(0xFFE0E0E0),
      textDim: Color(0xFF707070),
      background: Color(0xFF0A0A0C),
      glow: Color(0xFFFFFFFF),
      cursor: Color(0xFFE0E0E0),
      selection: Color(0xFF303040),
    ),
  );

  const PhosphorPalette({required this.label, required this.colors});

  final String label;
  final CrtColorScheme colors;
}
