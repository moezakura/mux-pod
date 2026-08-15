import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/herdr/herdr_errors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

const kStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

const kStatusProtocol16 =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":16,"compatible":false,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

// 実測: server 非稼働時の `herdr status --json`（protocol が null）。
const kStatusNotRunning =
    '{"client":{"version":"0.7.5","channel":"stable","protocol":17,'
    '"binary":"/lab/herdr","session":null},"server":{"status":"not_running",'
    '"running":false,"version":null,"protocol":null,"capabilities":null,'
    '"compatible":null,"socket":"/home/lab/.config/herdr/herdr.sock",'
    '"session":null,"restart_needed":false},"update":{"restart_needed":false}}';

const kSnapshotOk =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"protocol":17,'
    '"version":"0.7.5","focused_workspace_id":"w1","focused_tab_id":"w1:t1",'
    '"focused_pane_id":"w1:p1","workspaces":[{"workspace_id":"w1",'
    '"label":"lab-ws1","number":1,"focused":true,"agent_status":"unknown",'
    '"pane_count":1,"tab_count":1,"active_tab_id":"w1:t1"}],'
    '"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"1","number":1,'
    '"focused":true,"agent_status":"unknown","pane_count":1}],'
    '"panes":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",'
    '"focused":true,"agent_status":"unknown","cwd":"/tmp",'
    '"foreground_cwd":"/tmp","revision":0,"terminal_id":"term_x"}]},'
    '"type":"session_snapshot"}}';

// T0 実測⑥の mutation 応答内 layout JSON（compact 版）。
const kMutationLayoutJson = '{"area":{"height":59,"width":78,"x":26,"y":1},'
    '"focused_pane_id":"w5:p1","panes":['
    '{"focused":true,"pane_id":"w5:p1",'
    '"rect":{"height":59,"width":39,"x":26,"y":1}}],'
    '"splits":[{"direction":"right","id":"split_0_root","ratio":0.5,'
    '"rect":{"height":59,"width":78,"x":26,"y":1}}],'
    '"tab_id":"w5:t1","workspace_id":"w5","zoomed":false}';

// T0 実測 4-c: resize 応答（layout 込み）。
const kResizeOk = '{"id":"cli:pane:resize","result":{"resize":{'
    '"changed":true,"focused_pane_id":"w5:p1","layout":$kMutationLayoutJson,'
    '"pane_id":"w5:p1"},"type":"pane_resize"}}';

// T0 実測 5-b: focus の soft 失敗（no_neighbor・layout 込み）。
const kFocusNoNeighbor = '{"id":"cli:pane:focus","result":{"focus":{'
    '"changed":false,"focused_pane_id":"w5:p1","layout":$kMutationLayoutJson,'
    '"reason":"no_neighbor","source_pane_id":"w5:p1"},'
    '"type":"pane_focus_direction"}}';

// T0 実測 5-a: edges 応答（layout 込み）。
const kEdgesOk = '{"id":"cli:pane:edges","result":{"edges":{'
    '"down":true,"layout":$kMutationLayoutJson,"left":true,'
    '"pane_id":"w5:p1","right":false,"up":true},"type":"pane_edges"}}';

// T0 実測 6-a: zoom 応答（zoom_changed）。
const kZoomOk = '{"id":"cli:pane:zoom","result":{"zoom":{'
    '"zoom_changed":true,"focus_changed":false,"zoomed":true},'
    '"type":"pane_zoom"}}';

void main() {
  group('HerdrAdapter.preflight', () {
    test('returns status when protocol is 17', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusOk;

      final adapter = HerdrAdapter(client);
      final status = await adapter.preflight();

      expect(status.serverProtocol, 17);
      expect(status.clientProtocol, 17);
      expect(status.compatible, isTrue);
    });

    test('throws HerdrProtocolMismatchException when protocol is not 17',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusProtocol16;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrProtocolMismatchException>()
              .having((e) => e.actual, 'actual', 16)
              .having((e) => e.supported, 'supported', 17),
        ),
      );
    });

    test('throws HerdrServerNotRunningException when server is not running',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusNotRunning;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(isA<HerdrServerNotRunningException>()),
      );
    });

    test('throws HerdrCommandException when herdr binary is missing',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = '';
      client.execExitCodes['herdr status --json'] = 127;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>().having((e) => e.exitCode, 'exitCode', 127),
        ),
      );
    });

    test('throws HerdrCommandException when stderr is non-empty', () async {
      final client = _FakeSshClientWithStderr('herdr: command not found');

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(
          isA<HerdrCommandException>()
              .having((e) => e.message, 'message', contains('command not found')),
        ),
      );
    });

    test('throws HerdrCommandException when output is not valid status JSON',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = 'garbage output';

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.preflight(),
        throwsA(isA<HerdrCommandException>()),
      );
    });
  });

  group('HerdrAdapter.snapshot', () {
    test('parses a snapshot response', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;

      final adapter = HerdrAdapter(client);
      final snapshot = await adapter.snapshot();

      expect(snapshot.protocol, 17);
      expect(snapshot.version, '0.7.5');
      expect(snapshot.workspaces, hasLength(1));
      expect(snapshot.workspaces.first.id, 'w1');
      expect(snapshot.tabs, hasLength(1));
      expect(snapshot.panes, hasLength(1));
      expect(snapshot.panes.first.cwd, '/tmp');
    });

    test(
      'throws SshConnectionError when the channel closes without exit status '
      'or output (SSH/transport anomaly, not a herdr command failure)',
      () async {
        final client = _FakeSshClientNullExit();

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.snapshot(),
          throwsA(isA<SshConnectionError>()),
        );
      },
    );

    test(
      'treats exit code null with non-empty stdout as success '
      '(output obtained, exit status lost)',
      () async {
        final client = _FakeSshClientNullExitWithOutput(kSnapshotOk);

        final adapter = HerdrAdapter(client);
        final snapshot = await adapter.snapshot();

        expect(snapshot.workspaces, hasLength(1));
        expect(snapshot.workspaces.first.id, 'w1');
      },
    );

    test('throws HerdrTargetNotFoundException for workspace_not_found code',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] =
          '{"error":{"code":"workspace_not_found","message":"no ws"},'
          '"id":"cli:api:snapshot"}';
      client.execExitCodes['herdr api snapshot'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.workspace)
              .having((e) => e.errorCode, 'errorCode', 'workspace_not_found')
              .having(
                (e) => e.message,
                'message',
                contains('workspace_not_found'),
              ),
        ),
      );
    });

    test('throws HerdrCommandException with errorCode for non-target error code',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] =
          '{"error":{"code":"internal_error","message":"boom"},'
          '"id":"cli:api:snapshot"}';
      client.execExitCodes['herdr api snapshot'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(
          isA<HerdrCommandException>()
              .having((e) => e.errorCode, 'errorCode', 'internal_error')
              .having((e) => e.message, 'message', contains('internal_error')),
        ),
      );
    });

    test('extracts error code from stderr', () async {
      final client = _FakeSshClientWithStderr(
        '{"error":{"code":"pane_not_found","message":"no pane"},'
        '"id":"cli:pane:get"}',
      );

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1'),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.pane)
              .having((e) => e.errorCode, 'errorCode', 'pane_not_found'),
        ),
      );
    });

    test('throws HerdrCommandException when output is malformed', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = 'not json';

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.snapshot(),
        throwsA(isA<HerdrCommandException>()),
      );
    });
  });

  group('HerdrAdapter executable resolution', () {
    test('prefixes commands with the user executable path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;
      client.userExecutablePath = '/usr/local/bin/herdr';

      final adapter = HerdrAdapter(client);
      await adapter.snapshot();

      expect(client.execCommands, isNotEmpty);
      expect(
        client.execCommands.first,
        startsWith('/usr/local/bin/herdr api snapshot'),
      );
    });

    test('keeps plain herdr when no user path is set', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr api snapshot'] = kSnapshotOk;

      final adapter = HerdrAdapter(client);
      await adapter.snapshot();

      expect(client.execCommands.first, 'herdr api snapshot');
    });

    test('explicit userExecutablePath wins over backend path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr status --json'] = kStatusOk;
      client.userExecutablePath = '/from/backend/herdr';

      final adapter = HerdrAdapter(
        client,
        userExecutablePath: '/from/constructor/herdr',
      );
      await adapter.preflight();

      expect(
        client.execCommands.first,
        startsWith('/from/constructor/herdr status --json'),
      );
    });
  });

  group('HerdrAdapter.paneRead', () {
    test('reads pane content with default options', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\nworld\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1');

      expect(client.execCommands, contains('herdr pane read w1:p1 --source recent'));
      expect(content.rawText, 'hello\nworld');
      expect(content.lines, ['hello', 'world']);
      expect(content.hasAnsi, isFalse);
    });

    test('passes source, lines, and --raw through to the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\n';

      final adapter = HerdrAdapter(client);
      await adapter.paneRead('w1:p1', source: 'visible', lines: 120, ansi: true);

      expect(
        client.execCommands,
        contains('herdr pane read w1:p1 --source visible --lines 120 --raw'),
      );
    });

    test('marks content as ANSI when --raw is requested', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '\x1b[32mok\x1b[0m\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1', ansi: true);

      expect(content.hasAnsi, isTrue);
    });

    test('throws HerdrCommandException on non-zero exit', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = '';
      client.execExitCodes['herdr pane read'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1'),
        throwsA(
          isA<HerdrCommandException>().having((e) => e.exitCode, 'exitCode', 1),
        ),
      );
    });

    test('prefixes pane read with the user executable path', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\n';
      client.userExecutablePath = '/usr/local/bin/herdr';

      final adapter = HerdrAdapter(client);
      await adapter.paneRead('w1:p1');

      expect(
        client.execCommands.first,
        startsWith('/usr/local/bin/herdr pane read w1:p1'),
      );
    });

    test('viaPersistent: true は execPersistentWithExitCode 経由で取得する', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] = 'hello\n';

      final adapter = HerdrAdapter(client);
      final content = await adapter.paneRead('w1:p1', viaPersistent: true);

      expect(content.rawText, 'hello');
      // FakeSshClient.execPersistentWithExitCode は execPersistentCommands に記録する。
      expect(
        client.execPersistentCommands,
        contains('herdr pane read w1:p1 --source recent'),
      );
    });

    test('viaPersistent でも target-not-found の例外分類は維持される', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane read'] =
          '{"error":{"code":"pane_not_found","message":"no pane"}}';
      client.execExitCodes['herdr pane read'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.paneRead('w1:p1', viaPersistent: true),
        throwsA(
          isA<HerdrTargetNotFoundException>().having(
            (e) => e.kind,
            'kind',
            HerdrTargetNotFoundKind.pane,
          ),
        ),
      );
    });
  });

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

    test('sendKey throws HerdrCommandException with invalid_key code (R9)',
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
    });

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
        contains('herdr pane resize --direction right --amount 0.1 --pane w5:p1'),
      );
    });

    test('edges parses directional booleans alongside layout (T0 実測 5-a)',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr pane edges'] = kEdgesOk;

      final adapter = HerdrAdapter(client);
      final result = await adapter.edges('w5:p1');

      expect(result.changed, isTrue);
      expect(result.layout, isNotNull);
      expect(result.layout!.splits.single.ratio, closeTo(0.5, 1e-9));
    });

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

    test('closePane throws HerdrTargetNotFoundException on pane_not_found',
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
    });

    test('splitPane passes ratio and cwd and succeeds with empty stdout',
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
    });

    test('mutation throws SshConnectionError when the channel closes '
        'without exit status or output (server-down 分類へ)', () async {
      final client = _FakeSshClientNullExit();

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

  group('HerdrAdapter tab CRUD (T12)', () {
    test('tabCreate builds the command and succeeds with empty stdout',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab create'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.tabCreate('w1', label: 'logs');

      expect(result.changed, isTrue);
      expect(result.layout, isNull);
      expect(
        client.execCommands,
        contains("herdr tab create --workspace w1 --label 'logs'"),
      );
    });

    test('tabCreate passes cwd and focus flags', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab create'] = '';

      final adapter = HerdrAdapter(client);
      await adapter.tabCreate('w1', cwd: '/tmp/work dir', focus: true);

      expect(
        client.execCommands,
        contains(
          "herdr tab create --workspace w1 --cwd '/tmp/work dir' --focus",
        ),
      );
    });

    test('tabClose throws HerdrTargetNotFoundException on tab_not_found',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab close'] =
          '{"error":{"code":"tab_not_found","message":"no tab"},'
          '"id":"cli:tab:close"}';
      client.execExitCodes['herdr tab close'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.tabClose('w1:t1'),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.tab)
              .having((e) => e.errorCode, 'errorCode', 'tab_not_found'),
        ),
      );
    });

    test('tabRename passes the quoted label', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab rename'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.tabRename('w1:t1', 'my tab');

      expect(result.changed, isTrue);
      expect(
        client.execCommands,
        contains("herdr tab rename w1:t1 'my tab'"),
      );
    });

    test('tabFocus builds the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab focus'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.tabFocus('w1:t1');

      expect(result.changed, isTrue);
      expect(client.execCommands, contains('herdr tab focus w1:t1'));
    });
  });

  group('HerdrAdapter workspace CRUD (T12)', () {
    test('workspaceCreate succeeds and ignores the layout-less response',
        () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace create'] =
          '{"id":"cli:workspace:create","result":{"workspace":{'
          '"workspace_id":"w6","label":"api","number":2,"focused":true},'
          '"tab":{"tab_id":"w6:t1","workspace_id":"w6","label":"1","number":1},'
          '"root_pane":{"pane_id":"w6:p1","workspace_id":"w6","tab_id":"w6:t1",'
          '"cwd":"/tmp"}},"type":"workspace_created"}';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceCreate(label: 'api');

      expect(result.changed, isTrue);
      expect(result.layout, isNull);
      expect(
        client.execCommands,
        contains("herdr workspace create --label 'api'"),
      );
    });

    test('workspaceCreate passes cwd and focus flags', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace create'] = '';

      final adapter = HerdrAdapter(client);
      await adapter.workspaceCreate(cwd: '/tmp/work dir', focus: true);

      expect(
        client.execCommands,
        contains(
          "herdr workspace create --cwd '/tmp/work dir' --focus",
        ),
      );
    });

    test('workspaceClose throws HerdrTargetNotFoundException on '
        'workspace_not_found', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace close'] =
          '{"error":{"code":"workspace_not_found","message":"no ws"},'
          '"id":"cli:workspace:close"}';
      client.execExitCodes['herdr workspace close'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.workspaceClose('w1'),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.workspace)
              .having((e) => e.errorCode, 'errorCode', 'workspace_not_found'),
        ),
      );
    });

    test('workspaceRename passes the quoted label', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace rename'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceRename('w1', 'my ws');

      expect(result.changed, isTrue);
      expect(
        client.execCommands,
        contains("herdr workspace rename w1 'my ws'"),
      );
    });

    test('workspaceFocus builds the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace focus'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceFocus('w1');

      expect(result.changed, isTrue);
      expect(client.execCommands, contains('herdr workspace focus w1'));
    });
  });
}

/// stderr を返す [FakeSshClient] のスタブ。
class _FakeSshClientWithStderr extends FakeSshClient {
  final String stderr;
  _FakeSshClientWithStderr(this.stderr);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: stderr, exitCode: 0);
  }
}

/// exitCode null・出力なしで戻す [FakeSshClient] のスタブ。
///
/// SSH exec チャネルが終了コードも出力も返さず閉じた（SSH 断・transport 層の
/// 異常）ケースを模す。実機では `herdr command failed (exit code: null)` として
/// 「No herdr pane found」に誤って swallow されていた経路（TERM-HERDR 診断）。
class _FakeSshClientNullExit extends FakeSshClient {
  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: '', exitCode: null);
  }
}

/// exitCode null だが stdout は返す [FakeSshClient] のスタブ。
///
/// 出力は得られたが終了コードだけ欠落したケース（dartssh2 の exit-status
/// 欠落）を模し、stdout が成功扱いで返ることを検証する。
class _FakeSshClientNullExitWithOutput extends FakeSshClient {
  final String output;
  _FakeSshClientNullExitWithOutput(this.output);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: output, stderr: '', exitCode: null);
  }
}
