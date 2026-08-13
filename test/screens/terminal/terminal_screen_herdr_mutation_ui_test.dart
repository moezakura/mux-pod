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
// - T14（Q-04）: resize は「対象選択モーダル → 相対量ダイアログ」の 2 段階
//   （tmux 準拠・条件1〜12）。絶対値 UI は使わず
//   `herdr pane resize --direction <dir> --amount <step>` を発行する。
//   1 pane でも常に選択モーダルを表示（条件3）・初期選択は現在表示中 pane
//   （条件10）・`changed:false`（分割境界外）は情報通知。
// - T15（Q-06/H7）: paste は `send-text` 複数行・画像転送は SFTP + send-text・
//   copy-mode は herdr では無く（H7）`pane read` 履歴ベースのみ。
// - Q-02（全操作解禁）: pane セレクタは Resize（ヘッダー）+ 分割プレビュー
//   （ビジュアライザ内タップ）経由、tab セレクタの tab CRUD（New / Rename /
//   Close）の UI 配線。ヘッダー操作の対象は現在表示中 pane / 現在 workspace
//   （tmux セレクタと同型）。

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

// 2 pane（w1:p1 / w1:p2・横並び）の layout 付き snapshot fixture。
// 各矩形は 幅>80 かつ 高さ>60（分割プレビューのインライン分割経路が入るサイズ）。
const kHerdrTwoPaneLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":100,"height":70}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":100,"y":0,"width":100,"height":70}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":true,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/b","focused":false,'
    '"foreground_cwd":"/b","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":2,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 3 pane（L 字: w1:p1 左上・w1:p2 右上・w1:p3 左下）の layout 付き snapshot
// fixture。w1:p1 は右隣（p2）と下隣（p3）の両方を持つため、Cols/Rows 両変更時の
// 「Cols→Rows 順の 2 回送信」（ユーザー決定6）の検証に使う。
const kHerdrThreePaneLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":100,"height":35}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":100,"y":0,"width":100,"height":35}},'
    '{"pane_id":"w1:p3","focused":false,'
    '"rect":{"x":0,"y":35,"width":100,"height":35}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":true,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/b","focused":false,'
    '"foreground_cwd":"/b","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_2","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/c","focused":false,'
    '"foreground_cwd":"/c","pane_id":"w1:p3","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_3","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":3,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":3,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

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

/// pane セレクタのヘッダー Resize（tooltip 'Resize Pane'）をタップし、
/// 選択モーダル（[PaneChooserDialog]）が表示されるまで進める。
Future<void> _tapHeaderResizeAndOpenChooser(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Resize Pane'));
  // `_closeSelectorThen` の 200ms 遅延後に選択モーダルが開く。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Resize Pane'), findsOneWidget);
}

/// 選択モーダルの Resize ボタンでリサイズダイアログ
/// （[HerdrResizePaneDialog]）へ進める（ダイアログ連鎖・R7）。
Future<void> _tapChooserResize(WidgetTester tester) async {
  await tester.tap(find.text('Resize'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

/// リサイズダイアログ（絶対値 UI）で Cols/Rows の◀▶ ステッパー、または絶対値
/// プリセットで目標サイズを設定し、Resize ボタンで確定して resize コマンド
/// 発行まで進める。
///
/// - [colsPlus] / [colsMinus]: Cols の ▶ / ◀ のタップ回数（.first が Cols 側）
/// - [rowsPlus] / [rowsMinus]: Rows の ▶ / ◀ のタップ回数（.last が Rows 側）
/// - [presetLabel]: 指定時はプリセットチップをタップ（例: '80x24 (Standard)'）
Future<void> _tapResizeDialogAndConfirm(
  WidgetTester tester, {
  int colsPlus = 0,
  int colsMinus = 0,
  int rowsPlus = 0,
  int rowsMinus = 0,
  String? presetLabel,
}) async {
  if (presetLabel != null) {
    await tester.tap(find.text(presetLabel));
    await tester.pump();
  } else {
    for (var i = 0; i < colsPlus; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pump();
    }
    for (var i = 0; i < colsMinus; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pump();
    }
    for (var i = 0; i < rowsPlus; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right).last);
      await tester.pump();
    }
    for (var i = 0; i < rowsMinus; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left).last);
      await tester.pump();
    }
  }
  await tester.tap(find.text('Resize'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

/// `herdr pane resize` コマンド文字列から `--amount` の値をパースする。
///
/// 実装（herdr_commands.dart）は `amount.toString()` をそのまま文字列化する
/// ため、浮動小数点誤差（例: 0.020000000000000018）が現れうる。期待値の照合は
/// この実測値をパースし `closeTo` で行う（テスト戦略・実測ベース）。
double? _amountOf(String command) {
  final match = RegExp(r'--amount ([-0-9.eE+]+)').firstMatch(command);
  return match == null ? null : double.parse(match.group(1)!);
}

/// 期待する方向・対象 pane・相対量（[expectedAmount] と closeTo）で
/// `herdr pane resize` コマンドが発行されているかを判定する。
bool _hasResizeCommand(
  List<String> commands, {
  required String direction,
  required String paneId,
  required double expectedAmount,
}) {
  return commands.any((c) {
    if (!c.startsWith('herdr pane resize')) return false;
    if (!c.contains('--direction $direction')) return false;
    if (!c.contains('--pane $paneId')) return false;
    final amount = _amountOf(c);
    return amount != null && (amount - expectedAmount).abs() < 1e-9;
  });
}

void main() {
  group('T14: herdr resize 2段階フロー（選択モーダル→絶対値ダイアログ・Q-04）', () {
    testWidgets(
      'ヘッダー Resize → 選択モーダルが開き、1 pane でも常に表示される（条件3）',
      (tester) async {
        await _pumpHerdrAndOpenPaneSelector(tester);

        // ヘッダーの Resize → 選択モーダル表示。
        await _tapHeaderResizeAndOpenChooser(tester);

        // 1 pane でも選択モーダルが開く（条件3・C-1解消・スキップしない）。
        expect(find.text('Resize Pane'), findsOneWidget);
        // 初期選択は現在表示中の pane（currentPaneId = w1:p1・cwd /tmp ラベル）。
        expect(find.text('Selected: /tmp (80x24)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('terminal-resize-pane-w1:p1')),
          findsOneWidget,
        );

        // `_scrollToCaret` の 100ms 遅延タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '選択モーダル → ダイアログ: 絶対値 Cols/Rows 入力・絶対値プリセット'
      '（旧 UI 要素は削除済み）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
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
        await _tapHeaderResizeAndOpenChooser(tester);
        await _tapChooserResize(tester);

        // 絶対値 UI（tmux と同構造）: 概算プレビュー・Cols/Rows 入力・プリセット。
        expect(find.text('概算(estimated)'), findsOneWidget);
        expect(find.text('Cols'), findsOneWidget);
        expect(find.text('Rows'), findsOneWidget);
        expect(find.text('80x24 (Standard)'), findsOneWidget);
        expect(find.text('120x40 (Wide)'), findsOneWidget);
        // 旧 UI 要素は削除（ユーザー決定）: Current 表示・方向パッド・相対量チップ。
        expect(find.text('Current: 80 x 24'), findsNothing);
        expect(find.byTooltip('Right'), findsNothing);
        expect(find.text('+20%'), findsNothing);
        expect(find.text('Direction'), findsNothing);
        expect(find.text('Amount'), findsNothing);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '絶対値入力: Cols を +4 セル変更 → 相対換算 right コマンドを発行する',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _tapHeaderResizeAndOpenChooser(tester);
        await _tapChooserResize(tester);

        // Cols を +4 セル（100 → 104）に変更して確定。
        await _tapResizeDialogAndConfirm(tester, colsPlus: 4);

        // 相対換算: delta = 4 / コンテナ幅(200) = 0.02 → 成長方向は right（右隣）。
        expect(
          _hasResizeCommand(
            client.execCommands,
            direction: 'right',
            paneId: 'w1:p1',
            expectedAmount: 4 / 200,
          ),
          isTrue,
          reason: '絶対値 Cols 変更が相対量（4/コンテナ幅）に換算されて送信される',
        );
        // Rows は変更なし（delta 0）→ 送信は 1 回のみ。
        expect(
          client.execCommands.where((c) => c.startsWith('herdr pane resize')),
          hasLength(1),
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '縮小入力: Cols を -4 セル → 隣接 pane（w1:p2）への成長コマンド（方向反転）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _tapHeaderResizeAndOpenChooser(tester);
        await _tapChooserResize(tester);

        // Cols を -4 セル（100 → 96）に変更して確定。
        await _tapResizeDialogAndConfirm(tester, colsMinus: 4);

        // 縮小は隣接 pane を成長させる（ユーザー決定5）:
        // 対象 w1:p1 の縮小側（right）= w1:p2 を、w1:p2 から見て対象側（left）へ成長。
        expect(
          _hasResizeCommand(
            client.execCommands,
            direction: 'left',
            paneId: 'w1:p2',
            expectedAmount: 4 / 200,
          ),
          isTrue,
          reason: '縮小は隣接 pane への成長として実現される（--pane が w1:p2 に変わる）',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'プリセット 80x24 → Cols 縮小を隣接成長で送信（Rows は縦隣接なしで送信なし）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _tapHeaderResizeAndOpenChooser(tester);
        await _tapChooserResize(tester);

        // 絶対値プリセット 80x24 → Cols 100→80（-20）・Rows 70→24（-46）。
        await _tapResizeDialogAndConfirm(tester, presetLabel: '80x24 (Standard)');

        // Cols: delta = -20/コンテナ幅(200) = -0.1 → 縮小 → 隣接 w1:p2 を left で成長。
        expect(
          _hasResizeCommand(
            client.execCommands,
            direction: 'left',
            paneId: 'w1:p2',
            expectedAmount: 20 / 200,
          ),
          isTrue,
        );
        // Rows: 縮小だが縦方向に隣接が無い → 送信されない（コマンドは 1 回のみ）。
        expect(
          client.execCommands.where((c) => c.startsWith('herdr pane resize')),
          hasLength(1),
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '2 pane: 選択モーダルで w1:p2 を選択 → 警告表示・--pane w1:p2・成長方向 left',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _tapHeaderResizeAndOpenChooser(tester);

        // 初期選択は現在表示中の pane（w1:p1・cwd /a ラベル・条件10）。
        expect(find.text('Selected: /a (100x70)'), findsOneWidget);

        // 選択モーダルで w1:p2 を選択 → 実行前再検証（条件11）で引当成功。
        await tester.tap(
          find.byKey(const ValueKey('terminal-resize-pane-w1:p2')),
        );
        await tester.pump();
        expect(find.text('Selected: /b (100x70)'), findsOneWidget);
        await _tapChooserResize(tester);

        // pane 2 枚以上 → 警告表示（条件4・tmux と同レベル）。
        expect(
          find.text('Other pane sizes may also change.'),
          findsOneWidget,
        );

        // Cols +4 → w1:p2 は左隣（w1:p1）のみ → 成長方向は left。
        await _tapResizeDialogAndConfirm(tester, colsPlus: 4);

        expect(
          _hasResizeCommand(
            client.execCommands,
            direction: 'left',
            paneId: 'w1:p2',
            expectedAmount: 4 / 200,
          ),
          isTrue,
          reason: '選択モーダルで選んだ pane（w1:p2）が --pane に反映・方向は左隣',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'タイル⋮ Resize も選択モーダル経由・初期選択は現在表示中 pane（条件10）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // タイル w1:p2 の ⋮ → Resize Pane（タイル ⋮ 導線）。
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('mux-sel-pane-w1:p2')),
            matching: find.byIcon(Icons.more_vert),
          ),
        );
        // PopupMenu の表示アニメーションを消化する。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Resize Pane'));
        // `_closeSelectorThen` の 200ms 遅延後に選択モーダルが開く。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        // タップしたタイル（w1:p2）ではなく現在表示中 pane（w1:p1）が初期選択
        // （ユーザー決定①・条件10）。
        expect(find.text('Selected: /a (100x70)'), findsOneWidget);
        expect(find.text('Selected: /b (100x70)'), findsNothing);

        // そのまま確定 → 現在表示中 pane が対象になる（Cols +4 → right 成長）。
        await _tapChooserResize(tester);
        await _tapResizeDialogAndConfirm(tester, colsPlus: 4);

        expect(
          _hasResizeCommand(
            client.execCommands,
            direction: 'right',
            paneId: 'w1:p1',
            expectedAmount: 4 / 200,
          ),
          isTrue,
          reason: 'タイル ⋮ 導線も選択モーダル経由・初期選択=currentPaneId に統一',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('changed:false（分割境界外）は情報 SnackBar を表示する', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
          // resize が分割境界外で changed:false を返す。
          'herdr pane resize': kHerdrResizeUnchangedFixture,
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _tapHeaderResizeAndOpenChooser(tester);
      await _tapChooserResize(tester);
      await _tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        find.text('分割境界のため変更なし'),
        findsOneWidget,
        reason: 'changed:false は soft 失敗として情報通知されること',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('単一 pane では隣接が無く resize コマンドを送信しない', (
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
      await _tapHeaderResizeAndOpenChooser(tester);
      await _tapChooserResize(tester);

      // Cols を +4 セル変更しても、隣接 pane が無く方向解決に失敗 → 送信しない。
      await _tapResizeDialogAndConfirm(tester, colsPlus: 4);

      expect(
        client.execCommands.where((c) => c.startsWith('herdr pane resize')),
        isEmpty,
        reason: '隣接 pane が無い場合は方向解決に失敗し送信しない',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      '3 pane: プリセット 120x40 → Cols/Rows 両方変更 → Cols→Rows 順に 2 回送信',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrThreePaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _tapHeaderResizeAndOpenChooser(tester);
        await _tapChooserResize(tester);

        // プリセット 120x40 → Cols 100→120（+20）・Rows 35→40（+5）。
        // w1:p1 は右隣（p2）と下隣（p3）の両方を持つ。
        await _tapResizeDialogAndConfirm(tester, presetLabel: '120x40 (Wide)');

        final resizeCmds = client.execCommands
            .where((c) => c.startsWith('herdr pane resize'))
            .toList();
        expect(resizeCmds, hasLength(2), reason: 'Cols と Rows の両方変更で 2 回送信');
        // Cols → Rows の順（ユーザー決定6）。
        expect(resizeCmds[0], contains('--direction right'));
        expect(resizeCmds[0], contains('--pane w1:p1'));
        expect(_amountOf(resizeCmds[0])!, closeTo(20 / 200, 1e-9));
        expect(resizeCmds[1], contains('--direction down'));
        expect(resizeCmds[1], contains('--pane w1:p1'));
        expect(_amountOf(resizeCmds[1])!, closeTo(5 / 70, 1e-9));

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
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

  group('Q-02: herdr pane セレクタの Split（分割プレビュー経由）配線', () {
    testWidgets(
      '分割プレビューのアクティブ pane タップ → Split Right で '
      'pane split コマンドを発行する',
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

        // 分割プレビュー内タップ（アクティブ pane・矩形 80x24 → インライン分割
        // モード）→ Split Right ボタン。
        await tester.tap(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('terminal-split-right-w1:p1')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane split w1:p1 --direction right',
          ),
          isTrue,
          reason: '分割プレビューは PaneWriter.splitPane（herdr pane split）を発行すること',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      '分割プレビュー内の Split Down は herdr pane split --direction down を発行する',
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

        await tester.tap(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('terminal-split-down-w1:p1')),
        );
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
      },
    );
  });

  group('N-T: herdr pane セレクタの分割プレビュー（新規）', () {
    testWidgets(
      'ヘッダーは Resize のみ + ローディング中 0.7 固定（N-T1）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
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

        // ローディング中: Split / Rename / Zoom のツールチップは存在しない。
        expect(find.byTooltip('Split Pane'), findsNothing);
        expect(find.byTooltip('Rename Pane'), findsNothing);
        expect(find.byTooltip('Zoom Pane'), findsNothing);
        // topExpected: true → ローディング中から maxHeight が画面高の 0.7 固定
        // （top 表示後と同じ高さでジャンプしない）。
        final sheetBox = tester.widget<ConstrainedBox>(
          find
              .ancestor(
                of: find.text('Select Pane'),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        final screenHeight = MediaQuery.sizeOf(
          tester.element(find.text('Select Pane')),
        ).height;
        expect(
          sheetBox.constraints.maxHeight,
          closeTo(screenHeight * 0.7, 0.001),
          reason: 'topExpected によりローディング中から maxHeight 0.7 固定',
        );

        await tester.pump(const Duration(milliseconds: 300));

        // データロード後: ヘッダーは Resize のみ。
        expect(find.byTooltip('Resize Pane'), findsOneWidget);
        expect(find.byTooltip('Split Pane'), findsNothing);
        expect(find.byTooltip('Rename Pane'), findsNothing);
        expect(find.byTooltip('Zoom Pane'), findsNothing);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'herdr ビジュアライザ表示 + アクティブ pane は現在表示中の pane（N-T2）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 分割プレビューが表示される。
        expect(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p2')),
          findsOneWidget,
        );

        // アクティブ pane のハイライトは _targetSource?.currentPaneId（= w1:p1、
        // 現在表示中の pane）基準。非アクティブ pane は黒半透明のまま。
        Color? paneColorOf(String paneId) {
          final container = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byKey(ValueKey('terminal-pane-layout-$paneId')),
              matching: find.byType(AnimatedContainer),
            ),
          );
          return (container.decoration as BoxDecoration).color;
        }

        expect(paneColorOf('w1:p1'), isNot(Colors.black45));
        expect(paneColorOf('w1:p2'), Colors.black45);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('非アクティブ pane タップで対象 pane に切替えてシートが閉じる（N-T3）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);

      // 非アクティブ pane（w1:p2）をタップ → 選択（onPaneSelected）に倒れる。
      await tester.tap(
        find.byKey(const ValueKey('terminal-pane-layout-w1:p2')),
      );
      await tester.pump();
      // シートの閉じアニメーション + 表示切替を進める。
      await tester.pump(const Duration(milliseconds: 400));

      // シートが閉じ、表示対象が w1:p2 に切替わる。
      expect(find.text('Select Pane'), findsNothing);
      expect(find.text('Pane 2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      'オフセット付き rect（x:26 / y:1）でもプレビューが 0 起点で欠けない（N-T4）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrResizedSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final paneFinder = find.byKey(
          const ValueKey('terminal-pane-layout-w1:p1'),
        );
        expect(paneFinder, findsOneWidget);

        // min 正規化: minLeft（26）/ minTop（1）が差し引かれ 0 起点で配置される。
        final positioned = tester.widget<Positioned>(
          find.ancestor(of: paneFinder, matching: find.byType(Positioned)).first,
        );
        expect(
          positioned.left,
          lessThan(1.0),
          reason: 'minLeft（26）が差し引かれ 0 起点で描画されること',
        );
        expect(
          positioned.top,
          lessThan(1.0),
          reason: 'minTop（1）が差し引かれ 0 起点で描画されること',
        );

        // プレビュー右端/下端がプレビュー領域内に収まる（欠けない）。
        final stackRect = tester.getRect(
          find.ancestor(of: paneFinder, matching: find.byType(Stack)).first,
        );
        final paneRect = tester.getRect(paneFinder);
        expect(paneRect.right, lessThanOrEqualTo(stackRect.right + 0.5));
        expect(paneRect.bottom, lessThanOrEqualTo(stackRect.bottom + 0.5));

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'read-only ではアクティブ pane タップが分割モードに入らず選択に倒れる（N-T5）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          readOnly: true,
          settle: false,
        );

        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // read-only では onSplitRequested == null のため、アクティブ pane タップ
        // は分割モードに入らず選択（onPaneSelected）に倒れる。
        await tester.tap(
          find.byKey(const ValueKey('terminal-pane-layout-w1:p1')),
        );
        await tester.pump();
        // シートの閉じアニメーションを進める。
        await tester.pump(const Duration(milliseconds: 400));

        // 分割ボタンは表示されず、シートが閉じる。split コマンドも発行されない。
        expect(
          find.byKey(const ValueKey('terminal-split-right-w1:p1')),
          findsNothing,
        );
        expect(find.text('Select Pane'), findsNothing);
        expect(
          client.execCommands.where((c) => c.startsWith('herdr pane split')),
          isEmpty,
        );

        await tester.pump(const Duration(milliseconds: 200));
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
          find.textContaining(
            'Resize failed. The terminal size could not be applied.',
          ),
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
          find.textContaining(
            'Resize failed. The terminal size could not be applied.',
          ),
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
          find.textContaining(
            'Resize failed. The terminal size could not be applied.',
          ),
          findsNothing,
          reason: 'キャンセルは bridge を起動しない（mounted ガード）',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
