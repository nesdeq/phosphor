import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../core/services/event_store.dart';

/// State for the timeline scrubber / replay engine.
class TimelineState {
  /// Current playback position in milliseconds from session start.
  final int currentTimeMs;

  /// Total session duration in milliseconds.
  final int durationMs;

  final bool isPlaying;
  final bool isReplaying;
  final int speed; // 1, 2, 4, 8, 16

  const TimelineState({
    this.currentTimeMs = 0,
    this.durationMs = 0,
    this.isPlaying = false,
    this.isReplaying = false,
    this.speed = 1,
  });

  TimelineState copyWith({
    int? currentTimeMs,
    int? durationMs,
    bool? isPlaying,
    bool? isReplaying,
    int? speed,
  }) {
    return TimelineState(
      currentTimeMs: currentTimeMs ?? this.currentTimeMs,
      durationMs: durationMs ?? this.durationMs,
      isPlaying: isPlaying ?? this.isPlaying,
      isReplaying: isReplaying ?? this.isReplaying,
      speed: speed ?? this.speed,
    );
  }
}

final timelineProvider =
    StateNotifierProvider<TimelineNotifier, TimelineState>((ref) {
  final eventStore = ref.read(eventStoreProvider);
  return TimelineNotifier(eventStore);
});

class TimelineNotifier extends StateNotifier<TimelineState> {
  final EventStore eventStore;
  Timer? _playTimer;
  Timer? _seekDebounce;

  /// The replay terminal — renders recorded output bytes.
  Terminal? replayTerminal;

  /// Cached events from the current session.
  List<TerminalEvent> _events = [];

  /// Session start time (timestamp of first event).
  DateTime? _sessionStart;

  /// How far the replay terminal has been built up to (event index).
  int _replayedUpToIndex = 0;

  TimelineNotifier(this.eventStore) : super(const TimelineState());

  /// Called by terminal_provider whenever an event is recorded.
  void recordEvent() {
    // During replay, timeline state is owned by the replay engine — don't touch it
    if (state.isReplaying) return;
    final events = eventStore.currentEvents;
    if (events.isEmpty) return;
    final first = events.first.timestamp;
    final last = events.last.timestamp;
    final durationMs = last.difference(first).inMilliseconds;
    state = state.copyWith(durationMs: durationMs, currentTimeMs: durationMs);
  }

  /// Enter replay mode — load events, start at the end (current state).
  Future<void> enterReplayMode() async {
    _events = eventStore.currentEvents;
    if (_events.isEmpty) return;

    _sessionStart = _events.first.timestamp;
    final durationMs =
        _events.last.timestamp.difference(_sessionStart!).inMilliseconds;

    replayTerminal = Terminal(maxLines: 10000)
      ..resize(kInitialTerminalCols, kInitialTerminalRows, 0, 0);
    _replayedUpToIndex = 0;

    // Replay everything to show current state
    _replayUpToTime(durationMs);

    state = state.copyWith(
      isReplaying: true,
      currentTimeMs: durationMs,
      durationMs: durationMs,
    );
  }

  /// Exit replay mode and return to live terminal.
  void exitReplayMode() {
    _playTimer?.cancel();
    _seekDebounce?.cancel();
    replayTerminal = null;
    _events = [];
    _sessionStart = null;
    _replayedUpToIndex = 0;
    state = state.copyWith(
      isReplaying: false,
      isPlaying: false,
    );
  }

  /// Seek to a time position in milliseconds.
  void seekTo(int timeMs, {bool immediate = false}) {
    final target = timeMs.clamp(0, state.durationMs);
    state = state.copyWith(currentTimeMs: target);

    if (!state.isReplaying || replayTerminal == null || _events.isEmpty) return;

    if (immediate) {
      _replayUpToTime(target);
    } else {
      _seekDebounce?.cancel();
      _seekDebounce = Timer(const Duration(milliseconds: 30), () {
        _replayUpToTime(target);
      });
    }
  }

  /// Binary search for the count of events at or before [time].
  /// Returns the exclusive upper bound index.
  int _eventIndexAtTime(DateTime time) {
    int lo = 0, hi = _events.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_events[mid].timestamp.isAfter(time)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Find the event index corresponding to a time offset, then replay up to it.
  /// Concatenates output between current position and target into a single
  /// Terminal.write call — much cheaper than N small writes for full rebuilds.
  void _replayUpToTime(int timeMs) {
    if (replayTerminal == null || _sessionStart == null) return;

    final targetTime = _sessionStart!.add(Duration(milliseconds: timeMs));
    final targetIndex = _eventIndexAtTime(targetTime);

    // xterm has no rewind primitive — backward seek requires rebuild.
    if (targetIndex < _replayedUpToIndex) {
      replayTerminal = Terminal(maxLines: 10000)
        ..resize(kInitialTerminalCols, kInitialTerminalRows, 0, 0);
      _replayedUpToIndex = 0;
    }

    if (_replayedUpToIndex == targetIndex) return;

    final buf = StringBuffer();
    for (var i = _replayedUpToIndex; i < targetIndex; i++) {
      final event = _events[i];
      if (event.type == EventType.output) buf.write(event.data);
    }
    if (buf.isNotEmpty) replayTerminal!.write(buf.toString());
    _replayedUpToIndex = targetIndex;
  }

  Future<void> seekToStart() async {
    if (!state.isReplaying) {
      await enterReplayMode();
      if (!state.isReplaying) return;
    }
    seekTo(0, immediate: true);
  }

  void seekToEnd() {
    if (state.isReplaying) {
      exitReplayMode();
    }
  }

  /// Step to the next event's timestamp.
  Future<void> stepForward() => _step(forward: true);

  /// Step to the previous event's timestamp.
  Future<void> stepBack() => _step(forward: false);

  Future<void> _step({required bool forward}) async {
    if (!state.isReplaying) {
      await enterReplayMode();
      if (!state.isReplaying) return;
    }
    if (_sessionStart == null || _events.isEmpty) return;

    final currentTime =
        _sessionStart!.add(Duration(milliseconds: state.currentTimeMs));
    final idx = _eventIndexAtTime(currentTime);

    int? targetIdx;
    if (forward) {
      // _eventIndexAtTime returns first event strictly AFTER currentTime.
      if (idx < _events.length) targetIdx = idx;
    } else {
      // Scan back for first event strictly BEFORE currentTime.
      for (var i = idx - 1; i >= 0; i--) {
        if (_events[i].timestamp.isBefore(currentTime)) {
          targetIdx = i;
          break;
        }
      }
    }

    final targetMs = targetIdx == null
        ? 0
        : _events[targetIdx]
            .timestamp
            .difference(_sessionStart!)
            .inMilliseconds;
    seekTo(targetMs, immediate: true);
  }

  Future<void> togglePlay() async {
    if (!state.isReplaying) {
      await enterReplayMode();
      if (!state.isReplaying) return; // No events to replay
      seekTo(0, immediate: true);
      _startPlayback();
      return;
    }

    if (state.isPlaying) {
      _playTimer?.cancel();
      state = state.copyWith(isPlaying: false);
    } else {
      // If at the end, restart from beginning
      if (state.currentTimeMs >= state.durationMs) {
        seekTo(0, immediate: true);
      }
      _startPlayback();
    }
  }

  void _startPlayback() {
    if (_sessionStart == null || _events.isEmpty) return;
    state = state.copyWith(isPlaying: true);

    // Use periodic timer at ~60fps for smooth, reliable playback
    _playTimer?.cancel();
    _playTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _onPlaybackTick();
    });
  }

  void _onPlaybackTick() {
    if (!state.isPlaying || _sessionStart == null) {
      _playTimer?.cancel();
      return;
    }

    final newTimeMs = state.currentTimeMs + 16 * state.speed;

    if (newTimeMs >= state.durationMs) {
      // Reached the end — show final state and stop
      seekTo(state.durationMs, immediate: true);
      _playTimer?.cancel();
      state = state.copyWith(isPlaying: false);
      return;
    }

    seekTo(newTimeMs, immediate: true);
  }

  void cycleSpeed() {
    const speeds = [1, 2, 4, 8, 16];
    final idx = speeds.indexOf(state.speed);
    final next = speeds[(idx + 1) % speeds.length];
    state = state.copyWith(speed: next);
    // No need to restart timer — _onPlaybackTick reads speed from state each tick
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _seekDebounce?.cancel();
    super.dispose();
  }
}
