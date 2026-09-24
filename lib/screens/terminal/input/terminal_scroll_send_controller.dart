import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../services/backend/domain/wheel_encoder.dart'
    show ScrollSendKind;
import '../../../services/herdr/herdr_commands.dart' show HerdrCommandException;
import 'terminal_input_ports.dart'
    show TerminalInputCapabilities, TerminalInputHost, TerminalPaneSendPort;

/// scrollSend の合流送信状態の単一所有者（TERM-SCROLL-006〜011・C6）。
///
/// 累積ティック・100ms 合流タイマー・flush 実行中フラグ・最後に観測した
/// paneMode・送信方式判定（テスト override 含む）を所有する。I/O は
/// [TerminalPaneSendPort] 経由、能力判定は [TerminalInputCapabilities] 経由。
/// モードのゲート（mode==scrollSend / copy-mode 検出）は呼び出し側
/// （[TerminalInputCoordinator]）または [copyModeDetected] で行う。
class TerminalScrollSendController {
  TerminalScrollSendController({
    required this.ref,
    required this.send,
    required this.caps,
    required this.host,
    required bool Function() copyModeDetected,
  }) : _copyModeDetected = copyModeDetected;

  final WidgetRef ref;
  final TerminalPaneSendPort send;
  final TerminalInputCapabilities caps;
  final TerminalInputHost host;
  final bool Function() _copyModeDetected;

  // 符号付き累積ティック（+ = 上スクロール送信 / - = 下スクロール送信）。
  int _pendingScrollTicks = 0;

  // 100ms 周期の合流フラッシュタイマー（最大 8 ティックを 1 コマンドに連結・D6）。
  Timer? _scrollSendTimer;

  // フラッシュの実行中フラグ（await 中の再入を防ぐ）。
  bool _scrollSendFlushInFlight = false;

  // 最後のポーリングで観測した paneMode（flush 時 paneMode 空確認・H4②）。
  String _lastPolledPaneMode = '';

  // テストフック（C9）: 送信方式の判定をテストから強制する。null なら通常判定。
  ScrollSendKind? _overrideScrollSendKindForTesting;

  /// ティックを積む（方向反転・タイマー生成含む・HEAD `_onScrollSendTicks` と
  /// 同一。mode / copy-mode ゲートは呼び出し側が実施済み）。
  void onTicks(int ticks) {
    final settings = ref.read(settingsProvider);
    // C10: 方向反転設定 ON 時はティック符号を反転（ドラッグ上 = 下スクロール送信）。
    final effective = settings.invertScrollSendDirection ? -ticks : ticks;
    _pendingScrollTicks += effective;
    _ensureScrollSendTimer();
  }

  /// 最後に観測した paneMode を記録する（session poll が呼ぶ・H4②）。
  void observePaneMode(String paneMode) {
    _lastPolledPaneMode = paneMode;
  }

  /// 合流送信タイマーを生成する（100ms 周期・未生成のときのみ・D6）。
  void _ensureScrollSendTimer() {
    if (_scrollSendTimer != null) return;
    _scrollSendTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => flush(),
    );
  }

  /// 合流送信タイマーを cancel する（M4）。保留ティックは破棄しない。
  void _cancelScrollSendTimer() {
    _scrollSendTimer?.cancel();
    _scrollSendTimer = null;
  }

  /// 保留ティックと合流タイマーを破棄する（M4・モード切替/再接続/切断時）。
  void discard() {
    _cancelScrollSendTimer();
    _pendingScrollTicks = 0;
  }

  // inventory: TERM-SCROLL-010
  /// 合流送信のフラッシュ（100ms ごと・D6）。
  ///
  /// 最大 8 ティックを 1 コマンドに連結して [TerminalPaneSendPort] で送信する。
  Future<void> flush() async {
    if (host.isDisposed) return;
    if (_pendingScrollTicks == 0 || _scrollSendFlushInFlight) return;

    // H4②: copy-mode 検出（await readPane 後にしか立たない）と flush の競合防止。
    if (_copyModeDetected() || _lastPolledPaneMode.isNotEmpty) {
      discard();
      return;
    }

    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    // 切断時は破棄（キューしない・R6）。writer/paneId が取れない場合も同様。
    if (!send.isConnected || writer == null || paneId == null) {
      discard();
      return;
    }

    final up = _pendingScrollTicks > 0;
    final ticks = _pendingScrollTicks.abs().clamp(1, 8);
    // 超過分（> 8）は次回フラッシュへ保持する。
    _pendingScrollTicks = up
        ? (_pendingScrollTicks - ticks)
        : (_pendingScrollTicks + ticks);
    if (_pendingScrollTicks == 0) _cancelScrollSendTimer();

    _scrollSendFlushInFlight = true;
    try {
      await writer.sendScroll(
        paneId,
        kind: resolveKind(),
        up: up,
        ticks: ticks,
      );
      send.boostPolling(); // D6: フラッシュ時のみ
    } on HerdrCommandException catch (e) {
      // C12: 最小監視（A8 リングバッファ・SDK 送信なし）
      send.recordHerdrSwitchEvent('scrollSend flush error (${e.runtimeType})');
    } catch (e) {
      // TmuxCommandException 等の失敗も最小監視へ記録（C12）
      send.recordHerdrSwitchEvent('scrollSend flush error (${e.runtimeType})');
    } finally {
      _scrollSendFlushInFlight = false;
    }
  }

  // inventory: TERM-SCROLL-011
  /// 送信方式（[ScrollSendKind]）の決定（D11・C9）。
  ScrollSendKind resolveKind() {
    final override = _overrideScrollSendKindForTesting;
    if (override != null) return override;
    final setting = ref.read(settingsProvider).scrollSendInput;
    if (setting == 'wheel' && caps.canWheelSend) {
      return ScrollSendKind.wheel;
    }
    return ScrollSendKind.key;
  }

  /// テストフック: 送信方式の判定を強制する（C9）。null で通常判定へ戻す。
  void setKindOverrideForTesting(ScrollSendKind? kind) {
    _overrideScrollSendKindForTesting = kind;
  }

  /// P5: 合流タイマーを cancel する（dispose）。
  void dispose() {
    _cancelScrollSendTimer();
  }
}
