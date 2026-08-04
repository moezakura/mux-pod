import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiplexerConfig', () {
    test('tmux convenience constructor sets backend and path', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      expect(config.backend, BackendType.tmux);
      expect(config.executablePath, '/usr/bin/tmux');
    });

    test('tmux convenience constructor allows null path', () {
      const config = MultiplexerConfig.tmux();
      expect(config.backend, BackendType.tmux);
      expect(config.executablePath, isNull);
    });

    test('toJson serializes backend and path', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      expect(config.toJson(), {
        'backend': 'tmux',
        'executablePath': '/usr/bin/tmux',
      });
    });

    test('toJson preserves null executablePath', () {
      const config = MultiplexerConfig.tmux();
      expect(config.toJson(), {
        'backend': 'tmux',
        'executablePath': null,
      });
    });

    test('fromJson restores a tmux config', () {
      final config = MultiplexerConfig.fromJson({
        'backend': 'tmux',
        'executablePath': '/usr/bin/tmux',
      });
      expect(config.backend, BackendType.tmux);
      expect(config.executablePath, '/usr/bin/tmux');
    });

    test('fromJson treats missing executablePath as null', () {
      final config = MultiplexerConfig.fromJson({
        'backend': 'tmux',
      });
      expect(config.backend, BackendType.tmux);
      expect(config.executablePath, isNull);
    });

    test('fromJson throws FormatException for unknown backend', () {
      expect(
        () => MultiplexerConfig.fromJson({
          'backend': 'unknown',
          'executablePath': '/usr/bin/tmux',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws FormatException when backend is not a string', () {
      expect(
        () => MultiplexerConfig.fromJson({
          'backend': 123,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith updates backend', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      final updated = config.copyWith(backend: BackendType.herdr);
      expect(updated.backend, BackendType.herdr);
      expect(updated.executablePath, '/usr/bin/tmux');
    });

    test('copyWith updates executablePath', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      final updated = config.copyWith(executablePath: '/opt/bin/tmux');
      expect(updated.backend, BackendType.tmux);
      expect(updated.executablePath, '/opt/bin/tmux');
    });

    test('copyWith can clear executablePath to null', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      final updated = config.copyWith(executablePath: null);
      expect(updated.backend, BackendType.tmux);
      expect(updated.executablePath, isNull);
    });

    test('copyWith preserves values when called with no arguments', () {
      const config = MultiplexerConfig.tmux('/usr/bin/tmux');
      final updated = config.copyWith();
      expect(updated, config);
    });

    test('equality and hashCode are value-based', () {
      const a = MultiplexerConfig.tmux('/usr/bin/tmux');
      const b = MultiplexerConfig(backend: BackendType.tmux, executablePath: '/usr/bin/tmux');
      const c = MultiplexerConfig.tmux('/opt/bin/tmux');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('herdr config round-trips through JSON', () {
      const config = MultiplexerConfig(
        backend: BackendType.herdr,
        executablePath: '/usr/bin/herdr',
      );
      final restored = MultiplexerConfig.fromJson(config.toJson());
      expect(restored, config);
    });
  });
}
