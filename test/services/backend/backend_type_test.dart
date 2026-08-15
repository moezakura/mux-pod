import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackendType', () {
    test('toJson returns the enum name', () {
      expect(BackendType.tmux.toJson(), 'tmux');
      expect(BackendType.herdr.toJson(), 'herdr');
    });

    test('fromJson parses known backend strings', () {
      expect(BackendType.fromJson('tmux'), BackendType.tmux);
      expect(BackendType.fromJson('herdr'), BackendType.herdr);
    });

    test('parse is an alias for fromJson', () {
      expect(BackendType.parse('tmux'), BackendType.tmux);
      expect(BackendType.parse('herdr'), BackendType.herdr);
    });

    test('fromJson throws FormatException for unknown backend', () {
      expect(
        () => BackendType.fromJson('unknown'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BackendType.fromJson('tmuxx'),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws FormatException for empty string', () {
      expect(() => BackendType.fromJson(''), throwsA(isA<FormatException>()));
    });
  });
}
