import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/sound_service.dart';
import '../theme/phosphor_theme.dart';

/// CRT-styled text field — handles keystroke sound internally so callers
/// don't have to track previous input length manually.
///
/// Used by the AI panel, command palette, session lobby, and settings.
class CrtTextField extends ConsumerStatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? prefix;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final double fontSize;
  final double? letterSpacing;
  final bool playEnterSoundOnSubmit;
  final EdgeInsetsGeometry contentPadding;
  final BoxDecoration? decoration;

  const CrtTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.prefix,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.onChanged,
    this.fontSize = 13,
    this.letterSpacing,
    this.playEnterSoundOnSubmit = true,
    this.contentPadding = EdgeInsets.zero,
    this.decoration,
  });

  @override
  ConsumerState<CrtTextField> createState() => _CrtTextFieldState();
}

class _CrtTextFieldState extends ConsumerState<CrtTextField> {
  int _prevLength = 0;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(phosphorPaletteProvider).colors;
    final sound = ref.read(soundServiceProvider);

    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textCapitalization: widget.textCapitalization,
      cursorColor: colors.cursor,
      style: TextStyle(
        fontSize: widget.fontSize,
        color: colors.text,
        letterSpacing: widget.letterSpacing,
      ),
      onChanged: (value) {
        _prevLength = sound.handleTextFieldKeystroke(_prevLength, value);
        widget.onChanged?.call(value);
      },
      onSubmitted: (value) {
        if (widget.playEnterSoundOnSubmit) {
          sound.playKeystroke(char: '\r');
        }
        widget.onSubmitted?.call(value);
      },
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: widget.contentPadding,
        hintText: widget.hintText,
        hintStyle: TextStyle(
          fontSize: widget.fontSize,
          color: colors.textDim,
          letterSpacing: widget.letterSpacing,
        ),
      ),
    );

    final inner = widget.prefix != null
        ? Row(
            children: [
              Text(
                widget.prefix!,
                style: TextStyle(fontSize: widget.fontSize, color: colors.text),
              ),
              Expanded(child: field),
            ],
          )
        : field;

    if (widget.decoration == null) return inner;
    return Container(
      decoration: widget.decoration,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: inner,
    );
  }
}
