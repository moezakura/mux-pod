import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerPane', () {
    test('stores all display fields', () {
      const pane = MultiplexerPane(
        index: 1,
        id: 'w1:p1',
        active: true,
        currentPath: '/tmp',
      );
      expect(pane.index, 1);
      expect(pane.id, 'w1:p1');
      expect(pane.active, isTrue);
      expect(pane.currentPath, '/tmp');
    });

    test('uses default values', () {
      const pane = MultiplexerPane(index: 0, id: '%0');
      expect(pane.active, isFalse);
      expect(pane.currentPath, isNull);
    });

    test('copyWith replaces fields and keeps others', () {
      const pane = MultiplexerPane(index: 0, id: '%0');
      final copy = pane.copyWith(index: 2, currentPath: '/home');
      expect(copy.index, 2);
      expect(copy.currentPath, '/home');
      expect(copy.id, '%0');
      expect(copy.active, isFalse);
    });

    test('equality and hashCode are based on id (mirrors TmuxPane)', () {
      const a = MultiplexerPane(index: 1, id: 'p1', active: true);
      const b = MultiplexerPane(index: 1, id: 'p1', active: false);
      const c = MultiplexerPane(index: 2, id: 'p2');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
