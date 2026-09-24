// session-runtime 領域が受ける外部依存の束（root State が生成・注入）。
//
// 責務: 接続〜切断〜再接続・poll・表示データ・autoResize・転送の各 controller が
// 必要とする「framework / provider / 他領域 API」を 1 箇所に集約する。
// - ref: 各 provider への一方向アクセス
// - host: root State のライフサイクル（mounted/_isDisposed/setState）と
//   widget パラメータ（props）への窓口
// - pendingStore: C9 の pending 表示対象の保管（root State 実装）
// - herdr / input / viewport: 他領域（herdr / view-input）の公開 API への窓口。
//
// 依存方向: 本ファイルは session-runtime から他領域への一方向コールバック注入のみ。
// 他領域の具象クラスを import しない（並行実装時の未完成依存を避ける）。
// 各コールバックの実装は root State が生成時に結線する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/tmux/tmux_facade.dart';

/// root State のライフサイクル・widget パラメータへの窓口。
abstract interface class SessionHost {
  bool get isMounted;
  bool get isDisposed;
  void markNeedsBuild();
  BuildContext get context;

  // ---- #125 切断UX: root 所有の表示状態へのブリッジ ----

  /// 通信エラーパネルを表示する（切断検知・再接続失敗）。
  void showCommErrorPanel({
    required String title,
    required String body,
    required String detail,
    required Future<void> Function() onRetry,
  });

  /// 通信エラーパネルを閉じる（× 押下・接続復帰時）。
  void closeCommErrorPanel();

  /// 真の接続回復時のリセット（抑止フラグ解除 + パネルを閉じる）。
  void onConnectionRestored();

  /// 再接続待機中カウントダウンの同期。
  void syncReconnectCountdown({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  });

  // widget パラメータ（props）
  String get connectionId;
  String? get sessionName;
  String? get sessionId;
  int? get lastWindowIndex;
  String? get lastPaneId;
  String? get deepLinkWindowName;
  int? get deepLinkPaneIndex;
  Object? get injectedPaneContentReader;
  Object? get herdrCacheClock;
  Object? get herdrCaretReader;
  Object? get bottomFollowEpsilon;
}

/// C9: pending 表示対象（`_pendingTargetIdentity` / `_pendingCaret`）の保管。
///
/// 値の生成・照合（エポック）は herdr API が行う。本領域（session poll）は
/// この store へ書き込み、`_applyUpdate` で読み取る。
abstract interface class PendingViewStore {
  Object? get pendingTargetIdentity;
  set pendingTargetIdentity(Object? value);
  dynamic get pendingCaret;
  set pendingCaret(dynamic value);
}

/// G5/G6: 転送フローのリソース保持・破棄窓口。
abstract interface class TransferHost {
  bool get isMounted;
  bool get isDisposed;
  BuildContext get context;
}

/// herdr 領域が提供する API の窓口（poll・再接続・mutation から使用）。
///
/// 実装は herdr controller（各メソッドを結線）または root State が注入する。
abstract interface class SessionHerdrPort {
  Object? captureTargetIdentity();
  bool isCurrentTargetIdentity(Object? identity);
  Future<bool> reResolveAfterReconnect();
  Future<void> refreshPaneIndicatorFromCache();
  Future<void> handlePollError(Object error);
  void recordSwitchEvent(String event);
  Future<void> handleHerdrMutationError(Object error, {String? operationLabel});
  Future<void> syncAfterHerdrMutation({String? eventLabel});
  Object? get snapshotCache;
  dynamic get displayNotifier;
  dynamic get paneIndicatorNotifier;

  /// reader/writer / cache の再生成（session_readers から呼ぶ）。
  void rebuildReaders();

  /// テスト注入 content reader 経路でも herdr スナップショット cache を生成する
  /// （HEAD 相当: injected reader でもエポック照合・再解決を有効化する）。
  void rebuildInjectedReaderCache(Object client);

  /// herdr セッション確立（session_connection から呼ぶ）。
  Future<void> setupSession(Object client);
}

/// view-input 領域が提供する API の窓口（poll・再接続・表示適用から使用）。
///
/// 実装は root State が view-input の coordinator / port を結線する。
abstract interface class SessionInputPort {
  void resetTerminalMode();
  Future<void> flushInputQueue();
  void captureSelectUpdate({
    required String content,
    dynamic caret,
    Object? targetIdentity,
  });
  dynamic takeBufferedUpdate();
  void handleTmuxCopyModeDetected();
  void handleTmuxCopyModeEnded();
  void scrollToCaret();
  void followToBottom();
  void selectPaneReset();
  bool get shouldFollowBottom;

  /// 手動選択モード中か（select バッファ適用の条件）。
  bool get isSelectManualActive;

  /// 最終観測 paneMode を記録（flush 時空確認・H4②）。
  void observePaneMode(String paneMode);

  /// scrollSend/select の source が none か（copy-mode 自動遷移の条件・HEAD 同等）。
  bool get isScrollModeSourceNone;

  /// normal モードか（follow-to-bottom の条件・HEAD 同等）。
  bool get isNormalMode;

  /// ユーザーのスクロールドラッグ中か（follow-to-bottom の条件・HEAD 同等）。
  bool get isUserScrollDragging;

  /// copy-mode 検出中（scrollSend 中 source==none 維持）か。
  bool get isCopyModeActive;

  /// scrollSend モード中か（poll 間隔上限 500ms の条件）。
  bool get isScrollSendActive;
}

/// AnsiTextView の GlobalKey 経由の viewport 操作窓口（C1）。
abstract interface class SessionViewportPort {
  void resetZoom();
}

/// session-runtime が受ける外部依存の束（root State が生成）。
class SessionEnv {
  SessionEnv({
    required this.ref,
    required this.host,
    required this.pendingStore,
    required this.transferHost,
    required this.herdr,
    required this.input,
    required this.viewport,
    required this.tmux,
    this.downloadSnackBarDisplay,
  });

  final WidgetRef ref;
  final SessionHost host;
  final PendingViewStore pendingStore;
  final TransferHost transferHost;
  final SessionHerdrPort herdr;
  final SessionInputPort input;
  final SessionViewportPort viewport;
  final TmuxFacade tmux;

  /// G6: ダウンロード SnackBar 表示仕様（ui の純関数・session→ui 一方向）。
  /// 純関数が null（表示なし）を返す場合はそのまま null を伝搬する（NG-1）。
  final DownloadDisplaySpec? Function(
    dynamic l10n,
    dynamic next,
    dynamic prevPhase,
  )?
  downloadSnackBarDisplay;

  /// `context.l10n` の簡略化（l10n extension を使わない側からも表示用に使う）。
  // ignore: unused_element
  dynamic get _unused => null;

  // ---- root が結線するライフサイクルフック ----

  /// root がセット: 最初の接続開始（`_connectAndSetup` 起動）。
  void Function()? onInitialConnect;

  /// root がセット: 再接続成功（`onReconnectSuccess`）。
  void Function()? onReconnectSuccess;

  /// root がセット: リスナー設定後の後続処理（転送リスナー登録等）。
  void Function()? afterListenersSetup;

  /// root がセット: フォアグラウンド復帰時（tree refresh 等）。
  void Function()? onResumePolling;
}

/// ダウンロード SnackBar の表示仕様（ui の純関数の戻り値）。
class DownloadDisplaySpec {
  const DownloadDisplaySpec({
    required this.message,
    required this.backgroundColor,
  });

  final String message;
  final dynamic backgroundColor;
}
