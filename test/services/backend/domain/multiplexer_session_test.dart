import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerSession', () {
    test('stores all display fields', () {
      const window = MultiplexerWindow(index: 0, name: 'shell');
      const session = MultiplexerSession(
        name: 'work',
        id: '\$0',
        windowCount: 1,
        attached: true,
        windows: [window],
      );
      expect(session.name, 'work');
      expect(session.id, '\$0');
      expect(session.windowCount, 1);
      expect(session.attached, isTrue);
      expect(session.windows, hasLength(1));
      expect(session.windows.single, equals(window));
    });

    test('uses default values', () {
      const session = MultiplexerSession(name: 'empty');
      expect(session.id, isNull);
      expect(session.windowCount, 0);
      expect(session.attached, isFalse);
      expect(session.windows, isEmpty);
    });

    test('copyWith replaces fields and keeps others', () {
      const session = MultiplexerSession(name: 'a');
      final copy = session.copyWith(name: 'b', attached: true);
      expect(copy.name, 'b');
      expect(copy.attached, isTrue);
      expect(copy.id, isNull);
      expect(copy.windowCount, 0);
    });

    test('equality and hashCode are based on name (mirrors TmuxSession)', () {
      const a = MultiplexerSession(name: 's', attached: true);
      const b = MultiplexerSession(name: 's');
      const c = MultiplexerSession(name: 'other');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
