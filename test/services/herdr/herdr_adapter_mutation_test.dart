import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/herdr/herdr_errors.dart';
import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_ssh_client.dart';
import 'helpers/herdr_adapter_fixtures.dart';
import 'helpers/herdr_adapter_fakes.dart';

void main() {
  group('HerdrAdapter mutation (_execMutation)', () {
    test('sendText succeeds with empty stdout (R7)', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane send-text'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.sendText('w1:p1', 'hello');

      expect(result.changed, isTrue);
      expect(result.reason, isNull);
      expect(result.layout, isNull);
      expect(
        client.execCommands,
        contains("herdr pane send-text w1:p1 'hello'"),
      );
    });

    test('sendText passes multi-line unicode through quoted args', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane send-text'] = '';

      final adapter = HerdrAdapter(client);
      await adapter.sendText('w1:p1', 'line1\nline2 \u3042');

      // 改行（0x0A）は制御文字のため ANSI-C quoting（$'...'）で送る
      expect(
        client.execCommands,
        contains(r"herdr pane send-text w1:p1 $'line1\x0aline2 あ'"),
      );
    });

    test('sendText treats non-JSON stdout with rc=0 as success (R7)', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane send-text'] = 'some diagnostic text';

      final adapter = HerdrAdapter(client);
      final result = await adapter.sendText('w1:p1', 'x');

      expect(result.changed, isTrue);
    });

    test(
      'sendKey throws HerdrCommandException with invalid_key code (R9)',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr pane send-keys'] =
            '{"error":{"code":"invalid_key","message":"unsupported key Home"},'
            '"id":"cli:request"}';
        client.execExitCodes['herdr pane send-keys'] = 1;

        final adapter = HerdrAdapter(client);
        try {
          await adapter.sendKey('w1:p1', 'Home');
          fail('expected HerdrCommandException');
        } on HerdrCommandException catch (e) {
          expect(e.errorCode, 'invalid_key');
          expect(e.exitCode, 1);
          expect(isHerdrInvalidKey(e), isTrue);
        }
      },
    );

    test('focusDirection returns no_neighbor soft failure (S4)', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane focus'] = kFocusNoNeighbor;

      final adapter = HerdrAdapter(client);
      final result = await adapter.focusDirection('w5:p1', 'right');

      expect(result.changed, isFalse);
      expect(result.reason, 'no_neighbor');
      expect(result.isNoNeighbor, isTrue);
      expect(result.isUnchanged, isTrue);
    });

    test('resizePane parses the response layout (T0 実測 4-c)', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane resize'] = kResizeOk;

      final adapter = HerdrAdapter(client);
      final result = await adapter.resizePane('w5:p1', 'right', 0.1);

      expect(result.changed, isTrue);
      expect(result.layout, isNotNull);
      expect(result.layout!.workspaceId, 'w5');
      expect(result.layout!.tabId, 'w5:t1');
      expect(result.layout!.focusedPaneId, 'w5:p1');
      expect(result.layout!.panes.single.rect.width, 39);
      expect(
        client.execCommands,
        contains(
          'herdr pane resize --direction right --amount 0.1 --pane w5:p1',
        ),
      );
    });

    test(
      'edges parses directional booleans alongside layout (T0 実測 5-a)',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr pane edges'] = kEdgesOk;

        final adapter = HerdrAdapter(client);
        final result = await adapter.edges('w5:p1');

        expect(result.changed, isTrue);
        expect(result.layout, isNotNull);
        expect(result.layout!.splits.single.ratio, closeTo(0.5, 1e-9));
      },
    );

    test('zoomPane reads zoom_changed as changed (T0 実測 6-a)', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane zoom'] = kZoomOk;

      final adapter = HerdrAdapter(client);
      final result = await adapter.zoomPane('w5:p1', mode: 'on');

      expect(result.changed, isTrue);
      expect(
        client.execCommands,
        contains('herdr pane zoom --pane w5:p1 --on'),
      );
    });

    test(
      'closePane throws HerdrTargetNotFoundException on pane_not_found',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr pane close'] =
            '{"error":{"code":"pane_not_found","message":"no pane"},'
            '"id":"cli:pane:close"}';
        client.execExitCodes['herdr pane close'] = 1;

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.closePane('w5:p1'),
          throwsA(
            isA<HerdrTargetNotFoundException>()
                .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.pane)
                .having((e) => e.errorCode, 'errorCode', 'pane_not_found'),
          ),
        );
      },
    );

    test(
      'splitPane passes ratio and cwd and succeeds with empty stdout',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr pane split'] = '';

        final adapter = HerdrAdapter(client);
        final result = await adapter.splitPane(
          'w1:p1',
          'right',
          ratio: 0.5,
          cwd: '/tmp',
        );

        expect(result.changed, isTrue);
        expect(
          client.execCommands,
          contains(
            "herdr pane split w1:p1 --direction right --ratio 0.5 --cwd '/tmp'",
          ),
        );
      },
    );

    test('mutation throws SshConnectionError when the channel closes '
        'without exit status or output (server-down 分類へ)', () async {
      final client = FakeSshClientNullExit();

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.sendText('w1:p1', 'x'),
        throwsA(isA<SshConnectionError>()),
      );
    });

    test('mutation throws HerdrCommandException on non-zero exit', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane send-text'] = '';
      client.execExitCodes['herdr pane send-text'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.sendText('w1:p1', 'x'),
        throwsA(
          isA<HerdrCommandException>().having((e) => e.exitCode, 'exitCode', 1),
        ),
      );
    });
  });
}
