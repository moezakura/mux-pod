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
        HerdrCommands.paneRead(
          'w1:p1',
          source: 'visible',
          lines: 50,
          ansi: true,
        ),
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

  group('HerdrCommands mutation builders（T0 実測の CLI 形式）', () {
    test('paneSendText quotes the text for shell safety', () {
      expect(
        HerdrCommands.paneSendText('w1:p1', 'hello'),
        "herdr pane send-text w1:p1 'hello'",
      );
    });

    test('paneSendText handles multi-line and unicode text', () {
      // 改行（0x0A）は制御文字のため ANSI-C quoting（$'...'）で送る
      expect(
        HerdrCommands.paneSendText('w1:p1', 'line1\nline2 \u3042'),
        r"herdr pane send-text w1:p1 $'line1\x0aline2 あ'",
      );
    });

    test('paneSendText escapes control chars with ANSI-C quoting', () {
      // 制御文字（Ctrl+O = 0x0F など）は readline に吸われないよう \xHH で送る
      expect(
        HerdrCommands.paneSendText('w1:p1', '\x0f'),
        r"herdr pane send-text w1:p1 $'\x0f'",
      );
    });

    test('paneSendText escapes all Ctrl+A-Z control chars (0x01-0x1A)', () {
      // Ctrl+[A-Z] の制御文字（0x01-0x1A）がすべて $'\xHH' 形式で送られること
      for (var i = 1; i <= 26; i++) {
        final ctrl = String.fromCharCode(i);
        final hex = i.toRadixString(16).padLeft(2, '0');
        expect(
          HerdrCommands.paneSendText('w1:p1', ctrl),
          "herdr pane send-text w1:p1 \$'\\x$hex'",
          reason: 'Ctrl+${String.fromCharCode(0x40 + i)} (0x$hex) のエスケープ',
        );
      }
    });

    test('paneSendText ANSI-C quoting escapes backslash and quote', () {
      expect(
        HerdrCommands.paneSendText('w1:p1', '\\\x01'),
        r"herdr pane send-text w1:p1 $'\\\x01'",
      );
    });

    test('paneSendText escapes single quotes inside the text', () {
      expect(
        HerdrCommands.paneSendText('w1:p1', "it's"),
        r"herdr pane send-text w1:p1 'it'\''s'",
      );
    });

    test('paneSendKeys passes the key name through', () {
      expect(
        HerdrCommands.paneSendKeys('w1:p1', 'F5'),
        'herdr pane send-keys w1:p1 F5',
      );
    });

    test('paneFocus uses --direction and --pane', () {
      expect(
        HerdrCommands.paneFocus('w1:p1', 'right'),
        'herdr pane focus --direction right --pane w1:p1',
      );
    });

    test('paneEdges uses --pane', () {
      expect(HerdrCommands.paneEdges('w1:p1'), 'herdr pane edges --pane w1:p1');
    });

    test('paneResize passes direction and float amount', () {
      expect(
        HerdrCommands.paneResize('w1:p1', 'right', 0.1),
        'herdr pane resize --direction right --amount 0.1 --pane w1:p1',
      );
      expect(
        HerdrCommands.paneResize('w1:p1', 'left', 0.05),
        'herdr pane resize --direction left --amount 0.05 --pane w1:p1',
      );
    });

    test('paneZoom supports toggle/on/off modes', () {
      expect(
        HerdrCommands.paneZoom('w1:p1'),
        'herdr pane zoom --pane w1:p1 --toggle',
      );
      expect(
        HerdrCommands.paneZoom('w1:p1', mode: 'on'),
        'herdr pane zoom --pane w1:p1 --on',
      );
      expect(
        HerdrCommands.paneZoom('w1:p1', mode: 'off'),
        'herdr pane zoom --pane w1:p1 --off',
      );
    });

    test('paneRename quotes the label', () {
      expect(
        HerdrCommands.paneRename('w1:p1', 'my pane'),
        "herdr pane rename w1:p1 'my pane'",
      );
    });

    test('paneClose uses the plain pane id', () {
      expect(HerdrCommands.paneClose('w1:p1'), 'herdr pane close w1:p1');
    });

    test('paneSplit supports direction, ratio and cwd', () {
      expect(
        HerdrCommands.paneSplit('w1:p1', 'right'),
        'herdr pane split w1:p1 --direction right',
      );
      expect(
        HerdrCommands.paneSplit('w1:p1', 'down', ratio: 0.5),
        'herdr pane split w1:p1 --direction down --ratio 0.5',
      );
      expect(
        HerdrCommands.paneSplit('w1:p1', 'right', cwd: '/tmp/work dir'),
        "herdr pane split w1:p1 --direction right --cwd '/tmp/work dir'",
      );
    });

    test('tabCreate emits --workspace with optional label/cwd/focus', () {
      expect(HerdrCommands.tabCreate('w1'), 'herdr tab create --workspace w1');
      expect(
        HerdrCommands.tabCreate('w1', label: 'logs'),
        "herdr tab create --workspace w1 --label 'logs'",
      );
      expect(
        HerdrCommands.tabCreate('w1', cwd: '/tmp/work dir', label: 'logs'),
        "herdr tab create --workspace w1 --cwd '/tmp/work dir' --label 'logs'",
      );
      expect(
        HerdrCommands.tabCreate('w1', label: 'logs', focus: true),
        "herdr tab create --workspace w1 --label 'logs' --focus",
      );
      expect(
        HerdrCommands.tabCreate('w1', focus: false),
        'herdr tab create --workspace w1 --no-focus',
      );
    });

    test('tabClose uses the plain tab id', () {
      expect(HerdrCommands.tabClose('w1:t1'), 'herdr tab close w1:t1');
    });

    test('tabRename quotes the label', () {
      expect(
        HerdrCommands.tabRename('w1:t1', 'my tab'),
        "herdr tab rename w1:t1 'my tab'",
      );
    });

    test('tabFocus uses the plain tab id', () {
      expect(HerdrCommands.tabFocus('w1:t1'), 'herdr tab focus w1:t1');
    });

    test('workspaceCreate emits optional label/cwd/focus', () {
      expect(HerdrCommands.workspaceCreate(), 'herdr workspace create');
      expect(
        HerdrCommands.workspaceCreate(label: 'api'),
        "herdr workspace create --label 'api'",
      );
      expect(
        HerdrCommands.workspaceCreate(cwd: '/tmp/work dir', label: 'api'),
        "herdr workspace create --cwd '/tmp/work dir' --label 'api'",
      );
      expect(
        HerdrCommands.workspaceCreate(label: 'api', focus: true),
        "herdr workspace create --label 'api' --focus",
      );
      expect(
        HerdrCommands.workspaceCreate(focus: false),
        'herdr workspace create --no-focus',
      );
    });

    test('workspaceClose uses the plain workspace id', () {
      expect(HerdrCommands.workspaceClose('w1'), 'herdr workspace close w1');
    });

    test('workspaceRename quotes the label', () {
      expect(
        HerdrCommands.workspaceRename('w1', 'my ws'),
        "herdr workspace rename w1 'my ws'",
      );
    });

    test('workspaceFocus uses the plain workspace id', () {
      expect(HerdrCommands.workspaceFocus('w1'), 'herdr workspace focus w1');
    });
  });

  group('HerdrPreflight', () {
    HerdrStatus status({
      int client = 17,
      int server = 17,
      bool running = true,
    }) => HerdrStatus(
      clientProtocol: client,
      serverProtocol: server,
      running: running,
    );

    test('accepts protocol 17 on both client and server', () {
      final result = HerdrPreflight.validate(status());
      expect(result.serverProtocol, 17);
      expect(result.clientProtocol, 17);
    });

    test(
      'throws HerdrServerNotRunningException when server is not running',
      () {
        expect(
          () => HerdrPreflight.validate(status(running: false)),
          throwsA(isA<HerdrServerNotRunningException>()),
        );
      },
    );

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

    test(
      'throws HerdrProtocolMismatchException when server protocol is 16',
      () {
        expect(
          () => HerdrPreflight.validate(status(server: 16)),
          throwsA(
            isA<HerdrProtocolMismatchException>()
                .having((e) => e.actual, 'actual', 16)
                .having((e) => e.supported, 'supported', 17),
          ),
        );
      },
    );

    test('accepts protocol 18 on client (18 >= minimum 17)', () {
      final result = HerdrPreflight.validate(status(client: 18));
      expect(result.clientProtocol, 18);
      expect(result.serverProtocol, 17);
    });

    test('reports client as actual when server is new but client is old', () {
      expect(
        () => HerdrPreflight.validate(status(client: 16, server: 18)),
        throwsA(
          isA<HerdrProtocolMismatchException>()
              .having((e) => e.actual, 'actual', 16)
              .having((e) => e.supported, 'supported', 17),
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
