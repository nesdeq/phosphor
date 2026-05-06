import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/phosphor_theme.dart';
import '../../../../core/services/session_service.dart';

/// Small overlay showing connected participants in the top-right corner.
class ParticipantOverlay extends ConsumerWidget {
  const ParticipantOverlay({super.key});

  static const _colors = [
    Color(0xFF33FF33), // green
    Color(0xFFFFB000), // amber
    Color(0xFF33FFFF), // cyan
    Color(0xFFFF33FF), // magenta
    Color(0xFFFFFF33), // yellow
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.isActive || session.participants.length <= 1) {
      return const SizedBox.shrink();
    }

    final palette = ref.watch(phosphorPaletteProvider);
    final colors = palette.colors;

    return Positioned(
      top: 32,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.textDim, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${session.participants.length} connected',
              style: TextStyle(
                fontSize: 9,
                color: colors.textDim,
              ),
            ),
            const SizedBox(height: 2),
            ...session.participants.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              final dotColor = _colors[idx % _colors.length];
              final roleTag = p.role.shortLabel;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '[$roleTag]',
                      style: TextStyle(
                        fontSize: 8,
                        color: colors.textDim,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
