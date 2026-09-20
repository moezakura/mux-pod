import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

/// ヘッダー直下の 2px 赤バー（状態表示専用・タップ不可）を探すファインダー。
/// `Container(height: 2, color: ...)` はコンストラクタ内で
/// `constraints == BoxConstraints.tightFor(height: 2)` に統合される。
Finder _disconnectBarFinder() {
  return find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.color == DesignColors.error &&
        w.constraints?.minHeight == 2 &&
        w.constraints?.maxHeight == 2,
  );
}

void main() {
  group('TerminalScreen disconnect UI (Issue #118)', () {
    testWidgets(
      'disconnected state shows termDisconnected, Retry and red bar',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 切断状態へ遷移（isReconnecting = false / isConnected = false）
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.disconnected,
          isReconnecting: false,
        );
        await tester.pump();

        // 右上インジケーター: termDisconnected + 再試行ボタン
        expect(find.text('Disconnected'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // ヘッダー直下の赤バー（height 2）
        expect(_disconnectBarFinder(), findsOneWidget);
      },
    );

    testWidgets(
      'provider error transition shows one disconnect toast and suppresses '
      'repeats',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 初回の error 遷移（接続中 → エラー、再接続ループ相当）で 1 回表示
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: first',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect failed: first'), findsOneWidget);
        // アクション文言は専用の termReconnectNow（'Reconnect now'）
        expect(find.text('Reconnect now'), findsOneWidget);

        // 同一 error の再遷移（値が同一）は遷移条件により再表示されない
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: first',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // 別文言でも 5 秒以内の再遷移はレート制限で抑制される（積まれない）
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: second',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect failed: second'), findsNothing);

        // 現在の Toast を閉じても、抑制された Toast はキューに積まれておらず
        // 次に表示されることはない（スパム対策の実効性検証）。
        ScaffoldMessenger.of(
          tester.element(find.byType(TerminalScreen)),
        ).hideCurrentSnackBar();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'continuous failure does not re-toast after the error-null cycle '
      '(reviewer R1-1)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 再接続ループ 1 サイクル目: 失敗（error 設定）→ Toast 1 回
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: boom',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect now'), findsOneWidget);

        // reconnect() 相当: isReconnecting のまま error のみ null クリア
        // （SshState.copyWith は error を無条件に書き込むため error が消える）
        notifier.state = notifier.state.copyWith(
          error: null,
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // 同一文言で再失敗（次のバックオフサイクル）→ 再表示されない
        // （抑止状態は真の復帰時のみリセットされる）
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: boom',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // 真の復帰（isConnected）で抑止状態がリセットされ、表示中の切断
        // Toast も自動で閉じる（退場アニメーション分の時間を進める）。
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.connected,
          error: null,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(SnackBar), findsNothing);

        // 復帰後の別切断では再度 1 回だけ通知される。旧実装（error == null で
        // リセット）では同一文言にレート制限が残り再通知されないため、
        // この検証で固定版と識別できる。
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: boom',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect failed: boom'), findsOneWidget);
        expect(find.text('Reconnect now'), findsOneWidget);
      },
    );

    testWidgets(
      'initial connection failure shows only the existing error snackbar '
      '(reviewer R1-2)',
      (tester) async {
        // 存在しない接続 ID で初期接続を失敗させる（実コードの
        // _connectAndSetup → _showErrorSnackBar 経路）。
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connectionId: 'no-such-conn',
        );

        // 既存 _showErrorSnackBar の 1 件のみ（新 Toast は発火しない）
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Reconnect now'), findsNothing);

        // provider 側の初期接続失敗状態遷移（connecting → error、
        // isReconnecting = false）を再現しても新 Toast は発火しない
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.connecting,
          error: null,
          isReconnecting: false,
        );
        await tester.pump();
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'connect failed: boom',
          isReconnecting: false,
        );
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect now'), findsNothing);
      },
    );

    testWidgets(
      'manual retry after initial failure re-fires the disconnect toast '
      '(reviewer R2-1)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 初期接続失敗の状態遷移（connecting → error, isReconnecting=false）
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.connecting,
          error: null,
          isReconnecting: false,
        );
        await tester.pump();
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Initial failure: A',
          isReconnecting: false,
        );
        await tester.pump();
        // 初期接続失敗自体では新 Toast は発火しない（既存 _showErrorSnackBar が担当）
        expect(find.byType(SnackBar), findsNothing);

        // インジケーターの Retry（reconnectNow）相当: previous が hasError のまま
        // 再失敗 → 今回の追加条件（previous.hasError）で Toast が 1 回表示される
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: B',
          isReconnecting: false,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Reconnect failed: B'), findsOneWidget);
        expect(find.text('Reconnect now'), findsOneWidget);
      },
    );

    testWidgets('connected state hides the red bar', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;

      // 接続中（isConnected）は赤バーが表示されない
      expect(_disconnectBarFinder(), findsNothing);

      // 切断すると表示され、接続復帰で消える
      notifier.state = notifier.state.copyWith(
        connectionState: SshConnectionState.disconnected,
      );
      await tester.pump();
      expect(_disconnectBarFinder(), findsOneWidget);

      notifier.state = notifier.state.copyWith(
        connectionState: SshConnectionState.connected,
        error: null,
      );
      await tester.pump();
      expect(_disconnectBarFinder(), findsNothing);
    });

    testWidgets('disconnect snackbar does not persist beyond timeout', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      final notifier = container.read(sshProvider.notifier) as FakeSshNotifier;

      // 切断検知 → 切断 Toast 表示
      notifier.state = notifier.state.copyWith(
        connectionState: SshConnectionState.error,
        error: 'Reconnect failed: first',
        isReconnecting: true,
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      // Flutter 3.44+ では action 付き SnackBar はデフォルトで persist=true
      // （タイムアウトで消えない）になる。切断 Toast は 4 秒のタイムアウトで
      // 自然消滅し、復帰時の自動クローズ（close）と二重で担保するため
      // persist: false を明示する。
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.persist, isFalse);
      expect(snackBar.duration, const Duration(milliseconds: 4000));
    });

    testWidgets(
      'reconnect countdown shows compact Ns (C) and updates every second',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 自動再接続の待機中（nextRetryAt が未来）: カウントダウン形式で表示し、
        // 「Reconnecting」の文字は出ない（接続処理中のみ出る）。
        notifier.state = notifier.state.copyWith(
          isReconnecting: true,
          reconnectAttempt: 3,
          nextRetryAt: DateTime.now().add(const Duration(seconds: 5)),
        );
        await tester.pump();
        expect(find.text('5s (3)'), findsOneWidget);
        expect(find.text('Reconnecting'), findsNothing);
        expect(find.text('Reconnecting (3)'), findsNothing);

        // 1 秒経過でカウントダウンが減る（state 遷移なしで毎秒更新）
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('4s (3)'), findsOneWidget);

        // 待機終了 → 接続処理中の表示に戻る（カウンタが 0 になったら非表示）
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Reconnecting (3)'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the reconnecting indicator shows a tooltip with details',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        notifier.state = notifier.state.copyWith(
          isReconnecting: true,
          reconnectAttempt: 2,
          nextRetryAt: DateTime.now().add(const Duration(seconds: 5)),
        );
        await tester.pump();

        // 待機中インジケーターをタップ → 詳細（カウントダウン + 試行回数）
        await tester.tap(find.text('5s (2)'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Reconnecting in 5s (Attempt 2)'), findsOneWidget);
      },
    );

    testWidgets(
      'disconnect toast auto-closes when auto-reconnect restores connection',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;

        // 切断検知 → 切断 Toast 表示
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.error,
          error: 'Reconnect failed: first',
          isReconnecting: true,
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // 自動再接続で復帰 → 表示中の Toast が自動で閉じる
        notifier.state = notifier.state.copyWith(
          connectionState: SshConnectionState.connected,
          error: null,
          isReconnecting: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });
}
