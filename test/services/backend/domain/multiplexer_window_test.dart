import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerWindow', () {
    test('stores all display fields', () {
      const pane = MultiplexerPane(index: 0, id: '%0', currentPath: '/home');
      const window = MultiplexerWindow(
        index: 1,
        id: 'w1:t1',
        name: 'editor',
        active: true,
        paneCount: 1,
        panes: [pane],
      );
      expect(window.index, 1);
      expect(window.id, 'w1:t1');
      expect(window.name, 'editor');
      expect(window.active, isTrue);
      expect(window.paneCount, 1);
      expect(window.panes, hasLength(1));
      expect(window.panes.single, equals(pane));
    });

    test('uses default values', () {
      const window = MultiplexerWindow(index: 0, name: 'shell');
      expect(window.id, isNull);
      expect(window.active, isFalse);
      expect(window.paneCount, 0);
      expect(window.panes, isEmpty);
    });

    test('copyWith replaces fields and keeps others', () {
      const window = MultiplexerWindow(index: 0, name: 'a');
      final copy = window.copyWith(name: 'b', active: true);
      expect(copy.name, 'b');
      expect(copy.active, isTrue);
      expect(copy.index, 0);
      expect(copy.id, isNull);
    });

    test('equality and hashCode are based on index+id (mirrors TmuxWindow)',
        () {
      const a = MultiplexerWindow(index: 1, id: 'w1:t1', name: 'a');
      const b = MultiplexerWindow(index: 1, id: 'w1:t1', name: 'b');
      const c = MultiplexerWindow(index: 2, id: 'w1:t2', name: 'a');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
