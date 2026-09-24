// P4/#125: 切断UX（通信エラーパネル・再接続詳細パネル）の状態所有者。
//
// root State（terminal_screen.dart）から切り出した協調オブジェクト。
// 状態の更新は [markNeedsBuild] 経由で親の setState を呼び、MediaQuery は
// [contextOf] から取得する（root を 500 行未満に保つための分割）。
import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/reconnect_countdown.dart';

class TerminalReconnectPanel {
  TerminalReconnectPanel({
    required this.markNeedsBuild,
    required this.contextOf,
    required this.isDisposed,
  });

  /// 親 State の `setState(() {})` 相当。
  final void Function() markNeedsBuild;

  /// MediaQuery 参照用（再接続パネルの矢印位置計算）。
  final BuildContext Function() contextOf;

  /// 親 State が dispose 済みか。
  final bool Function() isDisposed;

  /// 切断/再接続失敗の通知抑制フラグ。初回の切断検知で 1 回だけ表示し、
  /// 真の再接続成功（isConnected）まで再表示しない。
  bool _disconnectToastShown = false;

  /// 自動再接続待機中のカウントダウン（残り秒・null = 非表示）。
  final countdown = ReconnectCountdown();

  /// 再接続中パネル（カウントダウン表示タップで開く詳細パネル）。
  bool panelVisible = false;
  final indicatorKey = GlobalKey();
  double arrowRight = 100;
  final headerLink = LayerLink();
  Timer? _hideTimer;

  /// 通信エラーパネル（切断検知・初期接続エラーで画面下部に表示）。
  String? title;
  String? body;
  String? detail;
  bool expanded = false;
  Future<void> Function()? onRetry;

  /// 通信エラーパネルを表示する（切断検知・再接続失敗）。
  void show({
    required String title,
    required String body,
    required String detail,
    required Future<void> Function() onRetry,
  }) {
    if (isDisposed()) return;

    // 初回表示以降、真の再接続成功（isConnected 遷移）まで再表示しない。
    if (_disconnectToastShown) {
      // 表示中は最新の失敗を反映する。閉じたパネルは再表示しない。
      if (this.body != null) {
        markNeedsBuild();
        this.title = title;
        this.body = body;
        this.detail = detail;
        this.onRetry = onRetry;
      }
      return;
    }
    _disconnectToastShown = true;

    markNeedsBuild();
    this.title = title;
    this.body = body;
    this.detail = detail;
    expanded = false;
    this.onRetry = onRetry;
  }

  /// 通信エラーパネルを閉じる（× 押下・接続復帰時）。
  void close() {
    if (isDisposed()) return;
    markNeedsBuild();
    body = null;
    detail = null;
    expanded = false;
  }

  /// 真の接続回復時のリセット（抑止フラグ解除 + パネルを閉じる）。
  void onConnectionRestored() {
    _disconnectToastShown = false;
    close();
  }

  /// 再接続待機中カウントダウンの同期（非再接続時はパネルを閉じる）。
  void sync({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  }) {
    if (!isReconnecting) {
      _hideTimer?.cancel();
      if (panelVisible) {
        markNeedsBuild();
        panelVisible = false;
      }
    }
    countdown.sync(
      isReconnecting: isReconnecting,
      isWaitingForNetwork: isWaitingForNetwork,
      nextRetryAt: nextRetryAt,
    );
  }

  /// 再接続詳細パネルの開閉トグル。開いたまま 10 秒で自動的に閉じる。
  void togglePanel() {
    final box = indicatorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final center = box.localToGlobal(Offset(box.size.width / 2, 0));
      arrowRight = (MediaQuery.sizeOf(contextOf()).width - 16 - center.dx - 7)
          .clamp(12, 238)
          .toDouble();
    }
    markNeedsBuild();
    panelVisible = !panelVisible;
    _hideTimer?.cancel();
    if (panelVisible) {
      _hideTimer = Timer(const Duration(seconds: 10), () {
        if (!isDisposed() && panelVisible) {
          markNeedsBuild();
          panelVisible = false;
        }
      });
    }
  }

  void toggleExpanded() {
    markNeedsBuild();
    expanded = !expanded;
  }

  void retry() {
    onRetry?.call();
  }

  void dispose() {
    _hideTimer?.cancel();
    countdown.dispose();
  }
}
