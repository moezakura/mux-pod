import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerBackendKind', () {
    test('exposes unknown, tmux and herdr', () {
      expect(MultiplexerBackendKind.values, hasLength(3));
      expect(
        MultiplexerBackendKind.values,
        containsAll([
          MultiplexerBackendKind.unknown,
          MultiplexerBackendKind.tmux,
          MultiplexerBackendKind.herdr,
        ]),
      );
    });

    test('unknown is the connection-pending initial value', () {
      // 接続前の画面ローカル初期値としてのみ使う（A7 / L0-b-14）。
      // 永続化はしない: JSON 化は ActiveSession.toJson の backend.name
      // 経由だが、unknown が永続化される経路は存在しない。
      expect(
        MultiplexerBackendKind.values.first,
        MultiplexerBackendKind.unknown,
      );
    });
  });
}
