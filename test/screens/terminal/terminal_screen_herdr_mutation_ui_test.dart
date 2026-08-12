import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_client.dart';
import '../../helpers/terminal_test_scaffold.dart';

// T14/T15: herdr の mutation UI テスト。
// - T14（Q-04）: resize は「方向 + ステップ」ダイアログ。絶対値 UI は使わず
//   `herdr pane resize --direction <dir> --amount <step>` を発行する。
//   `changed:false`（分割境界外）は情報通知。
// - T15（Q-06/H7）: paste は `send-text` 複数行・画像転送は SFTP + send-text・
//   copy-mode は herdr では無く（H7）`pane read` 履歴ベースのみ。
// - Q-02（全操作解禁）: pane セレクタの Split / Rename / Zoom と tab セレクタの
//   tab CRUD（New / Rename / Close）の UI 配線。ヘッダー操作の対象は現在表示中
//   pane / 現在 workspace（tmux セレクタと同型）。

// G4 実測の snapshot fixture に layout rect（w1:p1 = 80x24）を追加した版。
// セレクタ / resize ダイアログの「現在サイズ（layout rect）」表示の検証に使う。
const kHerdrSnapshotWithLayoutFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// hidden TUI resize 収束確認用: PTY 120x40 → 実測変換式で area 94x39 の fixture。
// （kHerdrSnapshotWithLayoutFixture の area / rect を 94x39 にした版）
const kHerdrResizedSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":26,"y":1,"width":94,"height":39},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":26,"y":1,"width":94,"height":39}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// resize 応答の `changed:false`（分割境界外・T0 実測 4-b）fixture。
const kHerdrResizeUnchangedFixture =
    '{"result":{"resize":{"changed":false,"reason":"unchanged",'
    '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}},'
    '"type":"pane_resize"}}';

// zoom 状態表示の検証用: layout `zoomed:true`（T0 実測 6-b: zoom 中は rect 不変）。
const kHerdrZoomedSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":true}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// zoom が pane_not_found で失敗する構造化エラー JSON（T19: target-not-found 分類）。
const kPaneNotFoundZoomFixture =
    '{"error":{"code":"pane_not_found","message":"no pane"},'
    '"id":"cli:pane:zoom"}';

// S0 実測形状: create --focus 後の snapshot（旧 tab は残存しつつ新タブが focused）。
// 旧 tab w1:t1（w1:p1）が残っていても、focused_tab_id / focused_pane_id /
// active_tab_id の 3 点で新タブ w1:t8（w1:p2）を指す。New Tab ダイアログの
// 「作成後の表示切替」検証に使う（旧 pane 残存でも followBackendFocus が新 pane
// を優先することを UI 経由で確認）。
const kHerdrNewTabActiveSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t8",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":false,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t8",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":true,"label":"2","number":2,'
    '"pane_count":1,"tab_id":"w1:t8","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t8",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":2,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

Connection _herdrConnection() {
  return Connection(
    id: 'test-conn',
    name: 'Herdr Server',
    host: 'testhost',
    port: 22,
    username: 'user',
    multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
    createdAt: DateTime(2025, 1, 1),
  );
}

/// herdr（mutation 解禁）のターミナルを起動し、pane セレクタを開く。
Future<void> _pumpHerdrAndOpenPaneSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  FakeImageTransferNotifier? imageTransferNotifier,
}) async {
  await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: _herdrConnection(),
    sessionName: 'lab-ws1',
    execOutputs: {
      'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
      'herdr pane read': 'hello\n',
      ...execOutputs,
    },
    imageTransferNotifier: imageTransferNotifier,
    settle: false,
  );

  // pane セグメント（'Pane 1'）タップ → pane セレクタ（第 3 段）。
  await tester.tap(find.text('Pane 1'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Select Pane'), findsOneWidget);
}

/// herdr（mutation 解禁）のターミナルを起動し、tab セレクタを開く。
/// コマンド検証用に [FakeSshClient] を返す。
Future<FakeSshClient> _pumpHerdrAndOpenTabSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: _herdrConnection(),
    sessionName: 'lab-ws1',
    execOutputs: {
      'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
      'herdr pane read': 'hello\n',
      ...execOutputs,
    },
    settle: false,
  );

  // tab セグメント（実ラベル '1'）タップ → tab セレクタ（第 2 段）。
  await tester.tap(find.text('1'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Select Window'), findsOneWidget);
  return client;
}

/// herdr（mutation 解禁）のターミナルを起動し、workspace セレクタ
/// （Select Session 相当）を開く。コマンド検証用に [FakeSshClient] を返す。
/// [ManagedPtyProcess] の UI テスト用 fake（成功経路の bridge 検証）。
class _UiFakeManagedPty implements ManagedPtyProcess {
  final StreamController<void> _doneController =
      StreamController<void>.broadcast();
  final List<(int, int)> resizes = [];

  @override
  Stream<void> get done => _doneController.stream;

  @override
  int? get exitCode => null;

  @override
  String? get exitSignalName => null;

  @override
  String get stderrTail => '';

  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));

  @override
  Future<void> close() async {}
}

/// [SshClient.startManagedPty] を成功させる fake（hidden TUI 起動を模擬）。
class _StartPtyResizeClient extends FakeSshClient {
  final List<_UiFakeManagedPty> managedProcesses = [];

  @override
  Future<ManagedPtyProcess> startManagedPty(
    String command, {
    required int cols,
    required int rows,
  }) async {
    final p = _UiFakeManagedPty();
    managedProcesses.add(p);
    return p;
  }
}

Future<FakeSshClient> _pumpHerdrAndOpenWorkspaceSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  Map<String, List<String>> execOutputQueues = const {},
  FakeSshClient Function()? clientFactory,
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: _herdrConnection(),
    sessionName: 'lab-ws1',
    execOutputs: {
      'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
      'herdr pane read': 'hello\n',
      ...execOutputs,
    },
    execOutputQueues: execOutputQueues,
    clientFactory: clientFactory,
    settle: false,
  );

  // workspace セグメント（ラベル 'lab-ws1'）タップ → workspace セレクタ。
  await tester.tap(find.text('lab-ws1'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Select Session'), findsOneWidget);
  return client;
}

void main() {
  group('T14: herdr resize 方向+ステップ UI（Q-04）', () {
    testWidgets(
      'selector header の Resize ボタンでダイアログが開き、'
      '現在サイズが layout rect から表示される',
      (tester) async {
        await _pumpHerdrAndOpenPaneSelector(tester);

        // ヘッダーの Resize ボタン（tooltip 'Resize Pane'）。
        await tester.tap(find.byTooltip('Resize Pane'));
        // `_closeSelectorThen` の 200ms 遅延後にダイアログが開く。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Resize Pane'), findsOneWidget);
        // 現在サイズ（layout rect 由来: 80 x 24）。
        expect(find.text('Current: 80 x 24'), findsOneWidget);
        expect(find.text('Direction'), findsOneWidget);
        expect(find.text('Step'), findsOneWidget);

        // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('方向 + ステップ（既定 0.1）で pane resize コマンドを発行する', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Resize Pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // 右方向（既定ステップ 0.1）で確定。
      await tester.tap(find.byTooltip('Right'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) =>
              c == 'herdr pane resize --direction right --amount 0.1 --pane w1:p1',
        ),
        isTrue,
        reason: '方向+ステップ UI は herdr pane resize の相対分数コマンドを発行する',
      );

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('ステップ量を 0.2 に変更すると --amount 0.2 で発行される', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Resize Pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // ステップ 0.2 を選択 → 上方向で確定。
      await tester.tap(find.text('0.2'));
      await tester.pump();
      await tester.tap(find.byTooltip('Up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) =>
              c == 'herdr pane resize --direction up --amount 0.2 --pane w1:p1',
        ),
        isTrue,
        reason: '選択したステップ量が --amount に反映されること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('changed:false（分割境界外）は情報 SnackBar を表示する', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
          // resize が分割境界外で changed:false を返す。
          'herdr pane resize': kHerdrResizeUnchangedFixture,
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Resize Pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Right'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('分割境界のため変更なし'),
        findsOneWidget,
        reason: 'changed:false は soft 失敗として情報通知されること',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });
  });

  group('T15: herdr paste / 画像転送 / copy-mode 代替（Q-06/H7）', () {
    testWidgets('Cmd ダイアログの複数行送信は send-text で貼り付ける（Q-06）', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      // SpecialKeysBar の Cmd から入力ダイアログを開き複数行を送信する。
      await tester.tap(find.text('Cmd'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'echo hi');
      await tester.tap(find.text('Execute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) => c.startsWith('herdr pane send-text w1:p1'),
        ),
        isTrue,
        reason: 'paste は PaneWriter.pasteText → send-text で送信されること（Q-06）',
      );

      // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('画像転送（SFTP アップロード + send-text でパス注入）', (
      tester,
    ) async {
      final image = FakeImageTransferNotifier()
        ..uploadResult = '/tmp/upload.png';
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        imageTransferNotifier: image,
        settle: false,
      );

      // SpecialKeysBar の画像ボタン → シートを閉じ → 状態を手動で進める。
      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(20, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      image.emit(const ImageTransferState(phase: ImageTransferPhase.picking));
      await tester.pump();
      image.emit(
        ImageTransferState(
          phase: ImageTransferPhase.confirming,
          pickedImageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
          pickedImageName: 'pixel.png',
          pendingRemotePath: '/tmp/pixel.png',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload Image'), findsOneWidget);
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SFTP アップロード（provider 側）完了後、パスを send-text で注入する。
      expect(
        client.execCommands.any(
          (c) =>
              c.startsWith('herdr pane send-text w1:p1') &&
              c.contains('/tmp/upload.png'),
        ),
        isTrue,
        reason: '画像転送は SFTP + send-text（パス送信）で行われること（Q-06）',
      );

      // SnackBar（Uploaded）の自動クローズまで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets(
      'Scroll & Select は herdr では copy-mode を出さず pane read 履歴のみ',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'history content\n',
          },
          settle: false,
        );

        // 設定メニュー → 'Normal Mode'（スクロールモードへ切替）。
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Normal Mode'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // herdr には copy-mode が無い（H7）: tmux copy-mode コマンドは出ない。
        expect(client.sendKeysCommands, isEmpty);
        // 履歴は pane read（既存）で取得する。要求行数はユーザー設定
        // scrollbackLines（既定 10000・バグ4）と整合する。
        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane read w1:p1') &&
                c.contains('--lines 10000'),
          ),
          isTrue,
          reason: 'Scroll & Select は herdr では pane read 履歴ベースのみ（H7）',
        );

        // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });

  group('Q-02: herdr pane セレクタの Split / Rename / Zoom 配線', () {
    testWidgets(
      'ヘッダーの Split ボタンで方向選択ダイアログが開き、'
      'Split Right で pane split コマンドを発行する',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // ヘッダーの Split ボタン → 方向選択ダイアログ。
        await tester.tap(find.byTooltip('Split Pane'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Split Pane'), findsOneWidget);
        expect(find.text('Split Right'), findsOneWidget);
        expect(find.text('Split Down'), findsOneWidget);

        await tester.tap(find.text('Split Right'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane split w1:p1 --direction right',
          ),
          isTrue,
          reason: 'Split UI は PaneWriter.splitPane（herdr pane split）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('Split Down は herdr pane split --direction down を発行する', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Split Pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Split Down'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        client.execCommands.any(
          (c) => c == 'herdr pane split w1:p1 --direction down',
        ),
        isTrue,
        reason: 'Split Down は vertical 方向の pane split を発行すること',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      'ヘッダーの Rename ボタンで入力ダイアログが開き、'
      'pane rename コマンドを発行する',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byTooltip('Rename Pane'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Rename Pane'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'editor');
        await tester.tap(find.text('Rename'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == "herdr pane rename w1:p1 'editor'",
          ),
          isTrue,
          reason: 'Rename UI は PaneWriter.renamePane（herdr pane rename）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'ヘッダーの Zoom ボタンで pane zoom --toggle を発行する（非 zoom 表示）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 非 zoom（layout zoomed:false）→ zoom_in アイコン + 'Zoom Pane' ツールチップ。
        expect(find.byTooltip('Zoom Pane'), findsOneWidget);
        expect(find.byIcon(Icons.zoom_in), findsOneWidget);

        await tester.tap(find.byTooltip('Zoom Pane'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane zoom --pane w1:p1 --toggle',
          ),
          isTrue,
          reason: 'Zoom UI は PaneWriter.zoomPane（herdr pane zoom --toggle）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'snapshot の zoomed:true では Unzoom 表示になる（zoom 状態の表示）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrZoomedSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // zoom 中（layout zoomed:true）→ zoom_out アイコン + 'Unzoom Pane'。
        expect(find.byTooltip('Unzoom Pane'), findsOneWidget);
        expect(find.byIcon(Icons.zoom_out), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'zoom の pane_not_found は target-not-found 分類で通知される（T19）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
            'herdr pane zoom': kPaneNotFoundZoomFixture,
          },
          execExitCodes: {'herdr pane zoom': 1},
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byTooltip('Zoom Pane'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('対象が消えました。再同期しました'),
          findsOneWidget,
          reason: 'zoom の pane_not_found も target-not-found 分類で通知されること',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
  });

  group('Q-05: herdr tab セレクタの tab CRUD 配線', () {
    testWidgets(
      'ヘッダーの New Tab ボタンでラベル入力ダイアログが開き、空欄 Create で '
      'tab create --focus を発行し、新タブの表示へ自動切替わる',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {'herdr pane read': 'hello\n'},
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotWithLayoutFixture, // 接続時: w1:t1（単一 pane）
              kHerdrNewTabActiveSnapshotFixture, // create --focus 後: 新タブ focused
            ],
          },
          settle: false,
        );

        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsOneWidget);

        expect(find.byTooltip('New Tab'), findsOneWidget);
        await tester.tap(find.byTooltip('New Tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        // ラベル入力ダイアログ（空欄許容・確認ボタン 'Create'）。
        expect(find.text('New Tab'), findsOneWidget);
        await tester.tap(find.text('Create'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // 空欄確定 = デフォルト名（--label なし）+ --focus（従来の即時作成 +
        // フォーカス移動・L-3）。
        expect(
          client.execCommands.any(
            (c) => c == 'herdr tab create --workspace w1 --focus',
          ),
          isTrue,
          reason: 'New Tab は空欄確定で --label なし + --focus の tab create を発行すること',
        );
        // アプリ契約（作成後自動切替）: 旧 pane（w1:p1）が残存しても新タブの
        // focused pane（w1:p2）が表示される。
        expect(
          find.text('Pane 2'),
          findsOneWidget,
          reason: 'New Tab 作成後は新タブへ表示が自動切替わること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'New Tab で空白のみのラベルはデフォルト作成（--label なし + --focus）',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        await tester.tap(find.byTooltip('New Tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.enterText(find.byType(TextField), '   ');
        await tester.tap(find.text('Create'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr tab create --workspace w1 --focus',
          ),
          isTrue,
          reason: '空白のみラベルは trim 正規化で null になり --label なしで作成される',
        );
        expect(
          client.execCommands
              .where((c) => c.startsWith('herdr tab create'))
              .any((c) => c.contains('--label')),
          isFalse,
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'New Tab でラベルを入力すると --label \'<label>\' --focus で作成される',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        await tester.tap(find.byTooltip('New Tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('New Tab'), findsOneWidget);

        // 実ラベル入力（trim 後も非 null になる経路）。
        await tester.enterText(find.byType(TextField), 'logs');
        await tester.tap(find.text('Create'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          client.execCommands.any(
            (c) => c == "herdr tab create --workspace w1 --label 'logs' --focus",
          ),
          isTrue,
          reason: 'ラベル入力ありは trim 後も非 null のため --label \'<label>\' + --focus を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'New Tab ダイアログのキャンセルはコマンドを発行しない',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        await tester.tap(find.byTooltip('New Tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('New Tab'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          client.execCommands.where((c) => c.startsWith('herdr tab create')),
          isEmpty,
          reason: 'キャンセルは mounted ガードでコマンド未発行になること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'タイル ⋮ → Rename Window で tab rename コマンドを発行する',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Rename Window'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // 入力ダイアログ（初期値 = 現在ラベル '1'）→ 変更して確定。
        expect(find.text('Rename Tab'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'work');
        await tester.tap(find.text('Rename'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == "herdr tab rename w1:t1 'work'",
          ),
          isTrue,
          reason: 'Rename Tab UI は PaneWriter.renameTab（herdr tab rename）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'タイル ⋮ → Close Window で連鎖 close 確認後に tab close を発行する',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Close Window'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // 最後の tab（単一 tab fixture）→ workspace 連鎖終了の確認文言。
        expect(find.text('Close Tab?'), findsOneWidget);
        expect(
          find.textContaining('last tab in this workspace'),
          findsOneWidget,
          reason: '最後の tab を閉じる場合は workspace 連鎖 close を確認する（R2）',
        );

        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any((c) => c == 'herdr tab close w1:t1'),
          isTrue,
          reason: 'Close Tab UI は PaneWriter.closeTab（herdr tab close）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });

  group('タスク①: herdr ターミナル全体 resize（Select Session）', () {
    testWidgets(
      'セッションセレクタの Resize で PTY 要求サイズ変更が成功すると hidden TUI 経由で同期される',
      (tester) async {
        final client = await _pumpHerdrAndOpenWorkspaceSelector(
          tester,
          clientFactory: () => _StartPtyResizeClient(),
          execOutputs: {
            // queue 尽きた後のフォールバック（収束確認の再ポーリング・同期）も
            // 94x39（実測変換式 cols-26 / rows-1 の期待値）を返す。
            'herdr api snapshot': kHerdrResizedSnapshotFixture,
          },
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotWithLayoutFixture, // 接続時: area 80x24
              kHerdrSnapshotWithLayoutFixture, // ダイアログ初期値（currentPtySize）
              kHerdrSnapshotWithLayoutFixture, // ensureStarted の currentPtySize
              kHerdrResizedSnapshotFixture, // 収束確認: area 94x39（= 120-26 / 40-1）
              kHerdrResizedSnapshotFixture, // _syncAfterHerdrMutation
            ],
          },
        );

        await tester.tap(find.byTooltip('Resize Terminal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        // プリセット選択 → Resize ボタンで確定（hidden TUI ブリッジ経由）。
        await tester.tap(find.text('120x40 (Wide)'));
        await tester.pump();
        await tester.tap(find.text('Resize'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // 成功: fail closed SnackBar は出ない。
        expect(
          find.textContaining('Resize が反映されませんでした'),
          findsNothing,
          reason: '収束確認が成功した場合は fail closed 通知を出さない',
        );
        // hidden TUI の managed PTY が lazy start され、120x40 が送られた。
        final managed = (client as _StartPtyResizeClient).managedProcesses;
        expect(managed, isNotEmpty, reason: 'lazy start で hidden TUI が起動される');
        expect(
          managed.last.resizes,
          contains((120, 40)),
          reason: 'PTY 要求サイズ 120x40 が managed PTY の window-change で送られる',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'セッションセレクタの Resize で PTY 要求サイズ変更を試みる'
      '（hidden TUI ブリッジ・fail closed 通知）',
      (tester) async {
        await _pumpHerdrAndOpenWorkspaceSelector(tester);

        // ターミナル全体 resize は pane 数に依存しないため、resize 能力が
        // あれば常に表示される。
        expect(find.byTooltip('Resize Terminal'), findsOneWidget);

        await tester.tap(find.byTooltip('Resize Terminal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        // tmux の ResizeWindowDialog と同一構成（サイズ入力行 + プリセット +
        // Cancel/Resize ボタン・グリッドプレビュー省略）+ PTY 要求サイズの文言。
        expect(find.text('Resize Terminal'), findsOneWidget);
        expect(
          find.textContaining('Changes the size of the whole terminal'),
          findsOneWidget,
          reason: 'ユーザー選択 案4: ターミナル全体（PTY）のサイズ変更・全ワークスペースに適用（英語表記）',
        );
        expect(find.text('Cols'), findsOneWidget);
        expect(find.text('Rows'), findsOneWidget);
        expect(find.text('80x24 (Standard)'), findsOneWidget);
        expect(find.text('120x40 (Wide)'), findsOneWidget);

        // プリセット選択 → Resize ボタンで確定（hidden TUI ブリッジ経由）。
        await tester.tap(find.text('120x40 (Wide)'));
        await tester.pump();
        await tester.tap(find.text('Resize'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // FakeSshClient では hidden TUI（managed PTY）を起動できないため、
        // HerdrResizeBridge が start 失敗 → fail closed の SnackBar を表示する。
        expect(
          find.textContaining('Resize が反映されませんでした'),
          findsOneWidget,
          reason: 'resize 不達（他クライアント競合 or 表示設定不一致）は fail closed 通知',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'Resize Terminal ダイアログのキャンセルは resize を試みない',
      (tester) async {
        await _pumpHerdrAndOpenWorkspaceSelector(tester);

        await tester.tap(find.byTooltip('Resize Terminal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Resize Terminal'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // キャンセルは hidden TUI を起動せず resize しない（通知もなし）。
        expect(
          find.textContaining('Resize が反映されませんでした'),
          findsNothing,
          reason: 'キャンセルは bridge を起動しない（mounted ガード）',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
