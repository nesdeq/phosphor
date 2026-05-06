import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/phosphor_theme.dart';

/// Reusable CRT-styled modal dialog with backdrop, Escape key handling,
/// and inverted title bar. Used by CommandPalette, SessionLobby, SettingsScreen.
class CrtDialog extends ConsumerWidget {
  final String title;
  final double width;
  final VoidCallback onClose;
  final List<Widget> children;
  final BoxConstraints? constraints;

  const CrtDialog({
    super.key,
    required this.title,
    required this.width,
    required this.onClose,
    required this.children,
    this.constraints,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(phosphorPaletteProvider).colors;

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: width,
                constraints: constraints,
                decoration: BoxDecoration(
                  color: colors.background,
                  border: Border.all(color: colors.text, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: colors.text,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.background,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
