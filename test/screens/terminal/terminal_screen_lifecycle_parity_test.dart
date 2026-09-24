// P4 回帰テスト（パリティ）: 既存テストが掴まない「deactivate 切断・App ライフサイクル・
// エラー Retry」の HEAD 挙動を固定する。
//
// 対象修正（P4 独立レビュー指摘）:
// - NG-2: deactivate で SSH を切断（popUntil 等で pop された場合も）
// - NG-4: inactive → 600ms 猶予の背景復元 / paused・hidden → 即時復元 /
//         resumed → 背景復元フラグがある場合に force 再フィット（TERM-RESIZE-001）
// - NG-5: エラー SnackBar の Retry は接続フロー（connectAndSetup）を再実行する
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart'
    show SshConnectionState;

import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_parity_pump.dart';

/// deactivate の切断を観測するための counting notifier。
class _CountingSshNotifier extends FakeSshNotifier {
  _CountingSshNotifier();

  int checkConnectionCalls = 0;
  int disconnectCalls = 0;

  @override
  bool checkConnection() {
    checkConnectionCalls++;
    return client?.isConnected ?? false;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    // ProviderScope 破棄後（pop 後の非同期完了）に来るため、state 書込を伴う
    // 実装（UnmountedRefException）を踏まないよう理想的な副作用のみ記録する。
    (client as FakeSshClient?)?.setConnected(SshConnectionState.disconnected);
  }
}

void main() {
  group('P4 parity: deactivate とライフサイクル（NG-2/NG-4）', () {
    testWidgets('deactivate（pop）で SSH 接続が切断される（checkConnection → disconnect）', (
      tester,
    ) async {
      final ssh = _CountingSshNotifier();
      await TerminalParityPump.pumpTerminalScreen(
        tester,
        sshNotifierFactory: (client) {
          ssh.client = client;
          return ssh;
        },
      );

      final client = ssh.client;
      expect(client?.isConnected, isTrue);

      // ルートから pop（widget を unmount）→ deactivate → restore → 切断
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();

      expect(ssh.checkConnectionCalls, greaterThanOrEqualTo(1));
      expect(ssh.disconnectCalls, 1);
      expect(client?.isConnected, isFalse);
    });

    testWidgets('inactive は 600ms 猶予後に背景復元を実行し、それまでは実行しない', (tester) async {
      final client = await TerminalParityPump.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      int restores() => client.restoreWindowCommands.length;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      // 600ms 未満では復元しない
      await tester.pump(const Duration(milliseconds: 599));
      expect(restores(), 0, reason: '600ms 猶予の前には復元しない');

      // 600ms 経過で復元
      await tester.pump(const Duration(milliseconds: 100));
      expect(restores(), greaterThan(0), reason: '600ms 経過で背景復元');
    });

    testWidgets('inactive の早期復帰（resumed）は背景復元をキャンセルする', (tester) async {
      final client = await TerminalParityPump.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      int restores() => client.restoreWindowCommands.length;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // 猶予タイマーはキャンセルされ、復元は実行されない
      await tester.pump(const Duration(milliseconds: 700));
      expect(restores(), 0, reason: '早期復帰で背景復元がキャンセルされる');
    });

    testWidgets('paused は猶予を待たず即時に背景復元を実行する', (tester) async {
      final client = await TerminalParityPump.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      int restores() => client.restoreWindowCommands.length;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));

      expect(restores(), greaterThan(0), reason: 'paused は即時復元する');
    });

    testWidgets('resumed は背景復元フラグがある場合に force 再フィットする', (tester) async {
      final client = await TerminalParityPump.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'autoResize',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      int resizeWindows() => client.execCommands
          .where((c) => c.contains('resize-window') && !c.contains('-A'))
          .length;
      final before = resizeWindows();
      expect(before, greaterThanOrEqualTo(1), reason: '初期 autoResize の発行');

      // paused → 復元（flag が立つ）→ resumed → force 再フィット
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        resizeWindows(),
        greaterThan(before),
        reason: '復帰後に force 再フィット（TERM-RESIZE-001）',
      );
    });
  });

  group('P4 parity: エラー Retry（NG-5）', () {
    testWidgets('認証エラー SnackBar の Retry は接続フローを再実行する', (tester) async {
      // key 認証 + 鍵が読めない接続 → SshAuthenticationError → エラー SnackBar
      final keyConnection = Connection(
        id: 'test-conn',
        name: 'KeyAuth',
        host: 'testhost',
        port: 22,
        username: 'user',
        authMethod: 'key',
        keyId: 'k1',
        createdAt: DateTime(2025, 1, 1),
      );
      await TerminalParityPump.pumpTerminalScreen(
        tester,
        connection: keyConnection,
        settings: const AppSettings(keepScreenOn: false),
      );

      // 1 度目の認証失敗 → エラー SnackBar 表示（画面のエラー表現とは別に SnackBar が出る）
      Finder snackError() => find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Private key is not readable'),
      );
      expect(snackError(), findsOneWidget);
      final retry = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Retry'),
      );
      expect(retry, findsOneWidget);

      // Retry → connectAndSetup の再実行 → 再度認証失敗（= 新しい試行が起きた）
      await tester.tap(retry);
      await tester.pump();
      // 1 つ目を dismiss させて 2 つ目（再試行の結果）を表示状態にする
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        snackError(),
        findsWidgets,
        reason: 'Retry が接続フローを再実行して再度エラーを表示する（ポーリング再開のみではない）',
      );
    });
  });
}
