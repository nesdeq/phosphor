import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/phosphor_theme.dart';

/// CRT-styled button — filled or outlined rectangle with monospace label.
/// Replaces ad-hoc GestureDetector→Container→Text patterns across the app.
class CrtButton extends ConsumerWidget {
  final String label;
  final VoidCallback? onTap;

  /// When true, fills the background with the phosphor text color
  /// (used for primary/active states).
  final bool filled;

  /// When true and not filled, the border uses textDim instead of text.
  final bool dimBorder;

  /// When true and not filled, the label uses textDim instead of text.
  final bool dimLabel;

  final double fontSize;
  final FontWeight? fontWeight;
  final EdgeInsetsGeometry padding;

  /// Stretch to fill available horizontal space (label centered).
  final bool expand;

  /// Optional fixed dimensions (used by the timeline control buttons).
  final double? width;
  final double? height;

  const CrtButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.dimBorder = false,
    this.dimLabel = false,
    this.fontSize = 13,
    this.fontWeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.expand = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(phosphorPaletteProvider).colors;
    final isFixed = width != null || height != null;
    final borderColor =
        filled ? colors.text : (dimBorder ? colors.textDim : colors.text);
    final labelColor =
        filled ? colors.background : (dimLabel ? colors.textDim : colors.text);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: expand ? double.infinity : width,
        height: height,
        alignment: isFixed ? Alignment.center : null,
        padding: isFixed ? null : padding,
        decoration: BoxDecoration(
          color: filled ? colors.text : Colors.transparent,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          textAlign: expand ? TextAlign.center : null,
          style: TextStyle(
            fontSize: fontSize,
            color: labelColor,
            fontWeight: fontWeight,
          ),
        ),
      ),
    );
  }
}
