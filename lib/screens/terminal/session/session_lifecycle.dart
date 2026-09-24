// リスナー・ライフサイクル連携（session-lifecycle・移設元 L801-1034）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../l10n/l10n_ext.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart';
import '../../../../services/network/network_monitor.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/ssh_provider.dart';
import '../../../../providers/tmux_provider.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// Provider リスナーとライフサイクル（poll pause/resume・keepScreenOn）を担う。
///
/// root State の `WidgetsBindingObserver` 実装は root に残し、ここは
/// 「postFrame 初期化」「provider 購読」「ポーズ/復帰」「keepScreenOn」の
/// 実行ロジックを提供する。購読（ProviderSubscription）の登録は root（P3）が行う。
class SessionLifecycle {
  SessionLifecycle(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  /// postFrame の初期化（`initState` 内 postFrame コールバック・移設元 L810-820）。
  ///
  /// リードを await しない（fire-and-forget・初期表示の即時性を保つ）。
  void initPostFrame() {
    setupListeners();
    env.onInitialConnect?.call();
    applyKeepScreenOn();
  }

  /// Provider リスナー設定（`_setupListeners`・移設元 L943-1034）。
  ///
  /// 注意: SSH/tmux/settings/network の 4 購読は root が `ref.listen` し、
  /// ここは反応ロジック（コールバック）を `SessionHost` へ登録するだけ。
  void setupListeners() {
    // SSH 状態変化
    env.ref.listenManual<SshState>(sshProvider, (previous, next) {
      if (!env.host.isMounted || env.host.isDisposed) return;
      runtime.sshState = next;
      env.host.markNeedsBuild();

      // #125: 切断検知 / 再接続失敗の error 遷移で通信エラーパネルを表示する。
      // 初期接続失敗（previous 未接続 かつ isReconnecting=false）は
      // connectAndSetup 側のエラー処理がカバーするため対象外。
      if (previous != null &&
          previous.error != next.error &&
          next.error != null &&
          (previous.isConnected || next.isReconnecting || previous.hasError)) {
        env.host.showCommErrorPanel(
          title: previous.isConnected
              ? env.host.context.l10n.termConnectionLostTitle
              : env.host.context.l10n.termReconnectFailedTitle,
          body: env.host.context.l10n.termConnectionLostBody,
          detail: next.error!,
          onRetry: () => env.ref.read(sshProvider.notifier).reconnectNow(),
        );
      }
      // 真の接続回復時（isConnected）のみ抑止状態をリセットしてパネルを閉じる。
      if (next.isConnected) {
        env.host.onConnectionRestored();
      }
      // 再接続待機中のカウントダウン表示を同期する（非再接続時はパネルを閉じる）。
      env.host.syncReconnectCountdown(
        isReconnecting: next.isReconnecting,
        isWaitingForNetwork: next.isWaitingForNetwork,
        nextRetryAt: next.nextRetryAt,
      );
    }, fireImmediately: true);

    // Tmux 状態変化（親 setState 不要・Consumer widget が watch）
    env.ref.listenManual<TmuxState>(tmuxProvider, (previous, next) {
      // no-op（Consumer widget が直接 watch）
    }, fireImmediately: true);

    // 設定変化（keepScreenOn / directInput / caret 再構成 / autoResize）
    env.ref.listenManual<AppSettings>(settingsProvider, (previous, next) {
      if (!env.host.isMounted || env.host.isDisposed) return;
      if (previous?.keepScreenOn != next.keepScreenOn) {
        applyKeepScreenOn();
      }
      if (previous?.directInputEnabled != next.directInputEnabled) {
        runtime.directInputEnabled = next.directInputEnabled;
        env.host.markNeedsBuild();
      }
      if (next.isAutoResize &&
          (previous?.fontSize != next.fontSize ||
              previous?.zoomFactor != next.zoomFactor)) {
        final pane = env.ref.read(tmuxProvider).activePane;
        if (pane != null) {
          final fn = runtime.executeAutoResize;
          if (fn != null) {
            fn(pane);
          }
        }
      }
    }, fireImmediately: false);

    // 初期値を明示的に設定
    runtime.directInputEnabled = env.ref
        .read(settingsProvider)
        .directInputEnabled;

    // ネットワーク状態変化
    env.ref.listenManual<AsyncValue<NetworkStatus>>(networkStatusProvider, (
      previous,
      next,
    ) {
      if (!env.host.isMounted || env.host.isDisposed) return;
      final prevStatus = previous?.value;
      final nextStatus = next.value;
      if (prevStatus != nextStatus) {
        env.host.markNeedsBuild();
      }
    }, fireImmediately: true);

    // 再接続成功時の処理
    final sshNotifier = env.ref.read(sshProvider.notifier);
    sshNotifier.onReconnectSuccess = env.onReconnectSuccess;

    // ダウンロード転送の SnackBar 報告リスナーを常駐登録
    env.afterListenersSetup?.call();
  }

  // ---------------------------------------------------------------------------
  // ライフサイクル（poll pause/resume・keepScreenOn・G2 復元スケジュール）
  // ---------------------------------------------------------------------------

  /// `_applyKeepScreenOn`（移設元 L933-942）。
  void applyKeepScreenOn() {
    final settings = env.ref.read(settingsProvider);
    if (settings.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// `_pausePolling`（移設元 L908-917）。
  void pausePolling() {
    runtime.isInBackground = true;
    runtime.cancelPollTimers();
    WakelockPlus.disable();
  }

  /// `_resumePolling`（移設元 L918-933）。
  void resumePolling() {
    if (!runtime.isInBackground || env.host.isDisposed) return;
    runtime.isInBackground = false;
    // herdr: tmux 専用のツリー更新は起動しない（A7）。server-down 停止状態からの
    // 復帰は server 復旧を再検証して再開する。ここでは pollingSuspended 解除。
    runtime.resumePolling();
    runtime.startPolling();
    // TERM-LIFE-013: tmux は 10 秒ごとのツリー更新を再開する（HEAD 同等）。
    if (runtime.backendKind != MultiplexerBackendKind.herdr) {
      runtime.startTreeRefresh?.call();
    }
    env.onResumePolling?.call();
    applyKeepScreenOn();
  }
}
