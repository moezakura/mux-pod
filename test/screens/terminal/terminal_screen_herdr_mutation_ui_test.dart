import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';

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
        // 履歴は pane read（既存）で取得する。
        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane read w1:p1') &&
                c.contains('--lines 100000'),
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
      'ヘッダーの New Tab ボタンで tab create --workspace を発行する',
      (tester) async {
        final client = await _pumpHerdrAndOpenTabSelector(tester);

        expect(find.byTooltip('New Tab'), findsOneWidget);
        await tester.tap(find.byTooltip('New Tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr tab create --workspace w1',
          ),
          isTrue,
          reason: 'New Tab UI は PaneWriter.createTab（herdr tab create --workspace）を発行すること',
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
}
