import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/crt_colors.dart';
import '../../../../app/theme/phosphor_theme.dart';
import '../../providers/timeline_provider.dart';

/// Horizontal timeline scrubber bar at the bottom of the terminal.
class TimelineBar extends ConsumerWidget {
  const TimelineBar({super.key});

  static String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(phosphorPaletteProvider);
    final colors = palette.colors;
    final timeline = ref.watch(timelineProvider);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.textDim, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Playback controls
          _controlButton('|<', () => ref.read(timelineProvider.notifier).seekToStart(), colors),
          const SizedBox(width: 4),
          _controlButton('<', () => ref.read(timelineProvider.notifier).stepBack(), colors),
          const SizedBox(width: 4),
          _controlButton(
            timeline.isPlaying ? '||' : '>',
            () => ref.read(timelineProvider.notifier).togglePlay(),
            colors,
            active: timeline.isPlaying,
          ),
          const SizedBox(width: 4),
          _controlButton('>', () => ref.read(timelineProvider.notifier).stepForward(), colors),
          const SizedBox(width: 4),
          _controlButton('>|', () {
            ref.read(timelineProvider.notifier).seekToEnd();
          }, colors),
          const SizedBox(width: 12),
          // Speed
          GestureDetector(
            onTap: () => ref.read(timelineProvider.notifier).cycleSpeed(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: colors.textDim),
              ),
              child: Text(
                '${timeline.speed}x',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 10,
                  color: colors.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Replay indicator / LIVE button
          if (timeline.isReplaying)
            GestureDetector(
              onTap: () => ref.read(timelineProvider.notifier).exitReplayMode(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3333),
                  border: Border.all(color: const Color(0xFFFF3333)),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: 'PhosphorMono',
                    fontSize: 10,
                    color: colors.background,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Current time
          Text(
            _formatTime(timeline.currentTimeMs),
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 10,
              color: colors.text,
            ),
          ),
          const SizedBox(width: 8),
          // Scrubber
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: timeline.isReplaying
                    ? const Color(0xFFFF3333)
                    : colors.text,
                inactiveTrackColor: colors.textDim.withValues(alpha: 0.3),
                thumbColor: timeline.isReplaying
                    ? const Color(0xFFFF3333)
                    : colors.text,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: timeline.currentTimeMs.toDouble(),
                min: 0,
                max: timeline.durationMs.toDouble().clamp(1, double.infinity),
                onChanged: (v) => ref
                    .read(timelineProvider.notifier)
                    .seekTo(v.round()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Total duration
          Text(
            _formatTime(timeline.durationMs),
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 10,
              color: colors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(
    String label,
    VoidCallback onTap,
    CrtColorScheme colors, {
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? colors.text : Colors.transparent,
          border: Border.all(color: colors.textDim, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'PhosphorMono',
            fontSize: 9,
            color: active ? colors.background : colors.text,
          ),
        ),
      ),
    );
  }
}
