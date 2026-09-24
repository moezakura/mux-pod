// P5 helper: herdr テスト共通の接続生成・監視読み出し・pump / 対話ヘルパー（H2）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/terminal_test_scaffold.dart';
import 'dart:async';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'herdr_snapshot_fixtures.dart';

Connection herdrConnection() {
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

// A8 最小監視のテスト: `_TerminalScreenState` のリングバッファを
// `@visibleForTesting` フック（herdrSwitchEventsForTesting）経由で読み出す。
// イベント文字列には `[HerdrSwitch]` プレフィックスが含まれ、debugPrint に
// 出力される文字列と同一である。
List<String> herdrSwitchEvents(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(TerminalScreen));
  return List<String>.from(state.herdrSwitchEventsForTesting());
}

// M2: pane indicator（右上ミニマップ）の描画判定。`_PaneLayoutPainter` は
// `terminal_screen.dart` の private クラスのため runtimeType 名で特定する。
Finder paneIndicatorPainter() => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_PaneLayoutPainter',
);

/// herdr（mutation 解禁）のターミナルを起動して返す。
Future<FakeSshClient> pumpHerdrTerminal(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  Map<String, int> execExitCodes = const {},
  Map<String, List<String>> execOutputQueues = const {},
  Map<String, Exception> execExceptions = const {},
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: herdrConnection(),
    sessionName: 'lab-ws1',
    execOutputs: {
      'herdr api snapshot': kHerdrSnapshotFixture,
      'herdr pane read': 'hello\n',
      ...execOutputs,
    },
    execExitCodes: execExitCodes,
    execOutputQueues: execOutputQueues,
    execExceptions: execExceptions,
    settle: false,
  );
  // 初回接続 + 初回ポーリング分だけ進める。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Pane 1'), findsOneWidget);
  return client;
}

/// herdr（mutation 解禁）のターミナルを起動し、pane セレクタを開く。
Future<void> pumpHerdrAndOpenPaneSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  FakeImageTransferNotifier? imageTransferNotifier,
}) async {
  await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: herdrConnection(),
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
Future<FakeSshClient> pumpHerdrAndOpenTabSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: herdrConnection(),
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

Future<FakeSshClient> pumpHerdrAndOpenWorkspaceSelector(
  WidgetTester tester, {
  Map<String, String> execOutputs = const {},
  Map<String, List<String>> execOutputQueues = const {},
  FakeSshClient Function()? clientFactory,
}) async {
  final client = await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: herdrConnection(),
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
Future<void> tapHeaderResizeAndOpenChooser(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Resize Pane'));
  // `_closeSelectorThen` の 200ms 遅延後に選択モーダルが開く。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Resize Pane'), findsOneWidget);
}

/// 選択モーダルの Resize ボタンでリサイズダイアログ
/// （[HerdrResizePaneDialog]）へ進める（ダイアログ連鎖・R7）。
Future<void> tapChooserResize(WidgetTester tester) async {
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
Future<void> tapResizeDialogAndConfirm(
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

/// herdr（mutation 解禁）のターミナルを起動し、workspace セレクタ
/// （Select Session 相当）を開く。コマンド検証用に [FakeSshClient] を返す。
/// [ManagedPtyProcess] の UI テスト用 fake（成功経路の bridge 検証）。
class UiFakeManagedPty implements ManagedPtyProcess {
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
class StartPtyResizeClient extends FakeSshClient {
  final List<UiFakeManagedPty> managedProcesses = [];

  @override
  Future<ManagedPtyProcess> startManagedPty(
    String command, {
    required int cols,
    required int rows,
  }) async {
    final p = UiFakeManagedPty();
    managedProcesses.add(p);
    return p;
  }
}

/// `herdr pane resize` コマンド文字列から `--amount` の値をパースする。
///
/// 実装（herdr_commands.dart）は `amount.toString()` をそのまま文字列化する
/// ため、浮動小数点誤差（例: 0.020000000000000018）が現れうる。期待値の照合は
/// この実測値をパースし `closeTo` で行う（テスト戦略・実測ベース）。
double? amountOf(String command) {
  final match = RegExp(r'--amount ([-0-9.eE+]+)').firstMatch(command);
  return match == null ? null : double.parse(match.group(1)!);
}

/// 期待する方向・対象 pane・相対量（[expectedAmount] と closeTo）で
/// `herdr pane resize` コマンドが発行されているかを判定する。
bool hasResizeCommand(
  List<String> commands, {
  required String direction,
  required String paneId,
  required double expectedAmount,
}) {
  return commands.any((c) {
    if (!c.startsWith('herdr pane resize')) return false;
    if (!c.contains('--direction $direction')) return false;
    if (!c.contains('--pane $paneId')) return false;
    final amount = amountOf(c);
    return amount != null && (amount - expectedAmount).abs() < 1e-9;
  });
}
