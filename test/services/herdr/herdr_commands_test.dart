import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HerdrCommands', () {
    test('snapshot returns the api snapshot command', () {
      expect(HerdrCommands.snapshot(), 'herdr api snapshot');
    });

    test('preflightCommand uses status with --json', () {
      expect(HerdrCommands.preflightCommand(), 'herdr status --json');
    });

    test('paneRead builds the default recent-source command', () {
      expect(
        HerdrCommands.paneRead('w1:p1'),
        'herdr pane read w1:p1 --source recent',
      );
    });

    test('paneRead appends --lines when given', () {
      expect(
        HerdrCommands.paneRead('w1:p1', lines: 120),
        'herdr pane read w1:p1 --source recent --lines 120',
      );
    });

    test('paneRead appends --raw when ansi is requested', () {
      expect(
        HerdrCommands.paneRead('w1:p1', source: 'visible', lines: 50, ansi: true),
        'herdr pane read w1:p1 --source visible --lines 50 --raw',
      );
    });

    test('paneRead keeps visible source without --raw by default', () {
      expect(
        HerdrCommands.paneRead('w1:p1', source: 'visible'),
        'herdr pane read w1:p1 --source visible',
      );
    });

    test('supported protocol constant is 17', () {
      expect(kHerdrSupportedProtocol, 17);
      expect(HerdrPreflight.supportedProtocol, 17);
    });
  });

  group('HerdrPreflight', () {
    HerdrStatus status({
      int client = 17,
      int server = 17,
      bool running = true,
    }) =>
        HerdrStatus(
          clientProtocol: client,
          serverProtocol: server,
          running: running,
        );

    test('accepts protocol 17 on both client and server', () {
      final result = HerdrPreflight.validate(status());
      expect(result.serverProtocol, 17);
      expect(result.clientProtocol, 17);
    });

    test('throws HerdrServerNotRunningException when server is not running',
        () {
      expect(
        () => HerdrPreflight.validate(status(running: false)),
        throwsA(isA<HerdrServerNotRunningException>()),
      );
    });

    test('server-not-running check wins over protocol mismatch', () {
      // 実測の未稼働 JSON 相当（running:false + protocol:0）でも
      // protocol mismatch ではなく server 未稼働例外になる。
      expect(
        () => HerdrPreflight.validate(
          status(client: 0, server: 0, running: false),
        ),
        throwsA(isA<HerdrServerNotRunningException>()),
      );
    });

    test('throws HerdrProtocolMismatchException when server protocol is 16',
        () {
      expect(
        () => HerdrPreflight.validate(status(server: 16)),
        throwsA(
          isA<HerdrProtocolMismatchException>()
              .having((e) => e.actual, 'actual', 16)
              .having((e) => e.supported, 'supported', 17),
        ),
      );
    });

    test('throws HerdrProtocolMismatchException when client protocol is 18',
        () {
      expect(
        () => HerdrPreflight.validate(status(client: 18)),
        throwsA(
          isA<HerdrProtocolMismatchException>()
              .having((e) => e.actual, 'actual', 18),
        ),
      );
    });

    test('throws when protocol fields are missing (0)', () {
      expect(
        () => HerdrPreflight.validate(status(client: 0, server: 0)),
        throwsA(isA<HerdrProtocolMismatchException>()),
      );
    });
  });

  group('Herdr exceptions', () {
    test('HerdrProtocolMismatchException toString reports both numbers', () {
      final e = HerdrProtocolMismatchException(supported: 17, actual: 16);
      expect(e.toString(), contains('16'));
      expect(e.toString(), contains('17'));
    });

    test('HerdrServerNotRunningException message guides the user', () {
      final e = HerdrServerNotRunningException();
      expect(e.message, contains("Start it with 'herdr server'"));
      expect(e.message, contains('server is not running'));
      expect(e.toString(), contains('server is not running'));
    });

    test('HerdrCommandException carries exit code and message', () {
      final e = HerdrCommandException('boom', exitCode: 127);
      expect(e.message, 'boom');
      expect(e.exitCode, 127);
      expect(e.toString(), contains('boom'));
    });
  });
}
