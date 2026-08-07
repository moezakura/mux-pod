import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerBackendKind', () {
    test('exposes tmux and herdr', () {
      expect(MultiplexerBackendKind.values, hasLength(2));
      expect(
        MultiplexerBackendKind.values,
        containsAll([MultiplexerBackendKind.tmux, MultiplexerBackendKind.herdr]),
      );
    });
  });
}
