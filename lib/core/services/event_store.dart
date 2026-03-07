import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'user_environment.dart';

/// Terminal event types for time-travel recording.
enum EventType { input, output }

/// A single recorded terminal event.
class TerminalEvent {
  final String id;
  final EventType type;
  final DateTime timestamp;
  final String data;

  TerminalEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
      };
}

/// Simple file-based event store.
/// Stores events as JSONL (one JSON object per line) for fast append.
/// Also keeps events in memory for time-travel replay.
final eventStoreProvider = Provider<EventStore>((ref) {
  return EventStore();
});

class EventStore {
  late final String _sessionDir;
  File? _eventLog;

  /// Guards against concurrent _initSession() calls.
  Future<void>? _pendingInit;

  /// In-memory event list for time-travel replay.
  final List<TerminalEvent> _events = [];

  EventStore() {
    final home = userEnvironment['HOME'] ?? '/tmp';
    _sessionDir = p.join(home, '.phosphor', 'sessions');
  }

  /// Get all current session events (for replay).
  List<TerminalEvent> get currentEvents => List.unmodifiable(_events);

  /// Initialize a new session log.
  Future<void> _initSession() async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = Directory(p.join(_sessionDir, sessionId));
    await dir.create(recursive: true);
    _eventLog = File(p.join(dir.path, 'events.jsonl'));
  }

  /// Append an event — memory add is synchronous so callers see it
  /// immediately; file persistence is async and best-effort.
  void record(TerminalEvent event) {
    _events.add(event);
    _persistEvent(event);
  }

  Future<void> _persistEvent(TerminalEvent event) async {
    _pendingInit ??= _initSession();
    await _pendingInit;
    final line = jsonEncode(event.toJson());
    await _eventLog!.writeAsString('$line\n', mode: FileMode.append);
  }
}
