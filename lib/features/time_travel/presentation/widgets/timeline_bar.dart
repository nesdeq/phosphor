import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/crt_colors.dart';
import '../../../../app/theme/phosphor_theme.dart';
import '../../../../app/widgets/crt_button.dart';
import '../../providers/timeline_provider.dart';

/// Horizontal timeline scrubber bar at the bottom of the terminal.
class TimelineBar extends ConsumerWidget {
  const TimelineBar({super.key});

  static String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(phosphorPaletteProvider).colors;
    final timeline = ref.watch(timelineProvider);
    final notifier = ref.read(timelineProvider.notifier);

    Widget control(String label, VoidCallback onTap, {bool active = false}) =>
        CrtButton(
          label: label,
          onTap: onTap,
          filled: active,
          dimBorder: true,
          fontSize: 9,
          width: 24,
          height: 24,
        );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.textDim, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          control('|<', notifier.seekToStart),
          const SizedBox(width: 4),
          control('<', notifier.stepBack),
          const SizedBox(width: 4),
          control(timeline.isPlaying ? '||' : '>', notifier.togglePlay,
              active: timeline.isPlaying),
          const SizedBox(width: 4),
          control('>', notifier.stepForward),
          const SizedBox(width: 4),
          control('>|', notifier.seekToEnd),
          const SizedBox(width: 12),
          // Speed
          GestureDetector(
            onTap: notifier.cycleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: colors.textDim),
              ),
              child: Text(
                '${timeline.speed}x',
                style: TextStyle(fontSize: 10, color: colors.text),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // LIVE button (only while replaying)
          if (timeline.isReplaying)
            GestureDetector(
              onTap: notifier.exitReplayMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: crtErrorRed,
                  border: Border.all(color: crtErrorRed),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.background,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            _formatTime(timeline.currentTimeMs),
            style: TextStyle(fontSize: 10, color: colors.text),
          ),
          const SizedBox(width: 8),
          // Scrubber
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor:
                    timeline.isReplaying ? crtErrorRed : colors.text,
                inactiveTrackColor: colors.textDim.withValues(alpha: 0.3),
                thumbColor: timeline.isReplaying ? crtErrorRed : colors.text,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: timeline.currentTimeMs.toDouble(),
                min: 0,
                max: timeline.durationMs.toDouble().clamp(1, double.infinity),
                onChanged: (v) => notifier.seekTo(v.round()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(timeline.durationMs),
            style: TextStyle(fontSize: 10, color: colors.textDim),
          ),
        ],
      ),
    );
  }
}
