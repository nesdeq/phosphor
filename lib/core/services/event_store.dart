import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'user_environment.dart';

/// Terminal event types for time-travel recording.
enum EventType { input, output }

/// A single recorded terminal event.
class TerminalEvent {
  final EventType type;
  final DateTime timestamp;
  final String data;

  const TerminalEvent({
    required this.type,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
      };
}

/// Simple file-based event store.
/// Stores events as JSONL (one JSON object per line) for fast append.
/// Also keeps a bounded ring of recent events in memory for replay.
final eventStoreProvider = Provider<EventStore>((ref) {
  return EventStore();
});

class EventStore {
  /// In-memory cap. Beyond this, oldest events are evicted; the JSONL on
  /// disk keeps the full history. At ~100 bytes per event this caps RAM
  /// usage at ~10 MB so a long-running session doesn't OOM.
  static const _memoryCap = 100000;

  late final String _sessionDir;
  File? _eventLog;

  /// Guards against concurrent _initSession() calls.
  Future<void>? _pendingInit;

  /// Serialises file appends — each call chains onto the previous future
  /// so writeAsString invocations never overlap.
  Future<void> _writeChain = Future.value();

  /// Bounded ring of recent events for time-travel replay.
  final Queue<TerminalEvent> _events = Queue<TerminalEvent>();

  EventStore() {
    final home = userEnvironment['HOME'] ?? '/tmp';
    _sessionDir = p.join(home, '.phosphor', 'sessions');
  }

  /// Snapshot of in-memory events (capped — see [_memoryCap]).
  List<TerminalEvent> get currentEvents => List.unmodifiable(_events);

  /// Initialize a new session log.
  Future<void> _initSession() async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = Directory(p.join(_sessionDir, sessionId));
    await dir.create(recursive: true);
    _eventLog = File(p.join(dir.path, 'events.jsonl'));
  }

  /// Append an event. Memory add is synchronous so callers see it
  /// immediately; file persistence is async, serialised, and best-effort.
  void record(TerminalEvent event) {
    _events.add(event);
    while (_events.length > _memoryCap) {
      _events.removeFirst();
    }
    _persistEvent(event);
  }

  void _persistEvent(TerminalEvent event) {
    _pendingInit ??= _initSession();
    // Chain onto _writeChain so concurrent record() calls serialise.
    _writeChain = _writeChain.then((_) async {
      await _pendingInit;
      final line = jsonEncode(event.toJson());
      await _eventLog!.writeAsString('$line\n', mode: FileMode.append);
    }).catchError((_) {
      // Best-effort; swallow persistence errors so the live session
      // continues even if the disk is full or read-only.
    });
  }
}
