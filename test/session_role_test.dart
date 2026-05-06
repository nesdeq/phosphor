import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor/core/services/session_service.dart';

void main() {
  group('SessionRole', () {
    test('shortLabel returns expected single character', () {
      expect(SessionRole.host.shortLabel, 'H');
      expect(SessionRole.editor.shortLabel, 'E');
      expect(SessionRole.viewer.shortLabel, 'V');
    });

    test('label returns uppercase name', () {
      expect(SessionRole.host.label, 'HOST');
      expect(SessionRole.editor.label, 'EDITOR');
      expect(SessionRole.viewer.label, 'VIEWER');
    });

    test('parse handles known values', () {
      expect(SessionRole.parse('host'), SessionRole.host);
      expect(SessionRole.parse('editor'), SessionRole.editor);
      expect(SessionRole.parse('viewer'), SessionRole.viewer);
    });

    test('parse falls back to viewer for unknown strings', () {
      expect(SessionRole.parse(''), SessionRole.viewer);
      expect(SessionRole.parse('moderator'), SessionRole.viewer);
      expect(SessionRole.parse('HOST'), SessionRole.viewer); // case-sensitive
    });
  });
}
