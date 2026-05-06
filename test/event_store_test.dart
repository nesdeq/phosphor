import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor/core/services/event_store.dart';

void main() {
  group('TerminalEvent', () {
    test('toJson serialises type, timestamp, data', () {
      final event = TerminalEvent(
        type: EventType.output,
        timestamp: DateTime.utc(2026, 5, 6, 12, 0, 0),
        data: 'hello',
      );
      final json = event.toJson();
      expect(json['type'], 'output');
      expect(json['timestamp'], '2026-05-06T12:00:00.000Z');
      expect(json['data'], 'hello');
      expect(json.containsKey('id'), isFalse, reason: 'id field was removed');
    });

    test('input and output events round-trip distinctly', () {
      final input = TerminalEvent(
        type: EventType.input,
        timestamp: DateTime.now(),
        data: 'ls\n',
      );
      final output = TerminalEvent(
        type: EventType.output,
        timestamp: DateTime.now(),
        data: 'README.md\n',
      );
      expect(input.toJson()['type'], 'input');
      expect(output.toJson()['type'], 'output');
    });
  });
}
