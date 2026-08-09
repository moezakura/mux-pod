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

    test('equality and hashCode use ID+NAME combined key', () {
      // 同一の id+name → 等価
      const a = MultiplexerSession(name: 'tmp', id: 'w3', attached: true);
      const b = MultiplexerSession(name: 'tmp', id: 'w3');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      // 同名でも id が異なれば非等価（herdr の "tmp" w3/w4）
      const c = MultiplexerSession(name: 'tmp', id: 'w4');
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));

      // 名前が異なれば非等価
      const d = MultiplexerSession(name: 'other', id: 'w3');
      expect(a, isNot(equals(d)));

      // id が null/空なら name 単独で等価（旧データ互換）
      const e = MultiplexerSession(name: 's', attached: true);
      const f = MultiplexerSession(name: 's');
      const g = MultiplexerSession(name: 's', id: '');
      expect(e, equals(f));
      expect(e.hashCode, equals(f.hashCode));
      expect(f, equals(g));
      expect(f.hashCode, equals(g.hashCode));
    });
  });
}
