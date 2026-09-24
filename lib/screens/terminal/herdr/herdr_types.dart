import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/backend/domain/multiplexer_pane.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_frame_reader.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/herdr/herdr_resize_bridge.dart';
import '../../../services/herdr/herdr_snapshot_cache.dart';
import '../../../services/ssh/ssh_client.dart';
import '../../../services/tmux/commands/layout.dart';
import '../target_source.dart';

// inventory: TERM-ENUM-002
/// mutation 後同期のターゲット解決ポリシー。
///
/// アプリ契約: Herdr の mutation は原則として現在表示中の pane を維持する
/// （[preserveCurrent]・sticky）。ただし、バックエンドのフォーカス移動を伴う
/// 操作（`--focus` 付き tab create 等）が成功した場合は、その操作に限り
/// バックエンドの focused pane へ表示を移動する（[followBackendFocus]）。
enum HerdrSyncTargetPolicy {
  /// 現在表示中の pane を最優先で維持する（既定。split/rename/zoom/close 等）。
  preserveCurrent,

  /// 現在 workspace のフォーカス tab → フォーカス pane を優先して解決する。
  /// focused 情報が欠落している場合は null を返し、呼び出し側が
  /// [preserveCurrent]（sticky）へフォールバックする（`--focus` 付き create 用）。
  followBackendFocus,
}

// inventory: TERM-SRC-002
/// herdr: 固定 pane ID を返す [TargetSource]。
///
/// 接続時に解決した pane ID を保持する。切替時は適用層
/// （[HerdrController.switchTarget]）が [setPaneId] で差し替える。
class HerdrTargetSource implements TargetSource {
  String _paneId;

  HerdrTargetSource(this._paneId);

  /// 表示対象の pane ID を差し替える（切替コミット時に呼ばれる）。
  void setPaneId(String paneId) {
    _paneId = paneId;
  }

  @override
  String? get currentPaneId => _paneId;
}

// inventory: TERM-EPOCH-000
/// herdr の表示対象同一性（A3改・エポック照合）。
///
/// 世代カウンタは持たない。`HerdrSnapshotCache.epoch`（バンプは cache 内在:
/// adapter 差し替え / force 再取得）と [HerdrTargetSource.currentPaneId]
/// （切替コミット [HerdrController.switchTarget]）の 2 つを同一性キーとして、
/// 非同期 read の開始時と完了・適用時で照合する。不一致は await 中に
/// 切替・再解決・再接続が発生したことを意味し、結果を破棄すべき。
typedef HerdrTargetIdentity = ({
  HerdrSnapshotCache cache,
  int epoch,
  String? paneId,
});

// inventory: TERM-DISP-000
/// herdr の表示状態（A9）。
///
/// workspace/tab/pane の位置情報のみを保持する不変データ。コンテンツ
/// （`TerminalViewData` / view notifier）とは別系統で、画面ローカルの
/// `HerdrDisplayData` 用 notifier が保持する。ブレッドクラムの入力になる。
class HerdrDisplayData {
  /// workspace の表示ラベル（要求時の `TerminalScreen.sessionName` 相当）。
  final String? workspaceLabel;

  /// workspace ID（例: "w1"）。解決タスクが確定した時点で設定される。
  final String? workspaceId;

  /// 表示対象 pane が属する tab ID（例: "w1:t1"）。
  ///
  /// スナップショット解決済みの実値（`HerdrPane.tabId` / `MultiplexerWindow.id`
  /// 相当）を保持する（L-1）。直接指定やセレクタ経由などスナップショット解決を
  /// 伴わない経路では、pane ID から best-effort で導出する（T11）。
  final String? tabId;

  /// tab の表示名（`MultiplexerWindow.name` 相当 = `tab.label ?? tab.id`・M-4）。
  ///
  /// 解決を伴わない経路（直接指定・テストフック）では null になり、
  /// 表示時は [tabId] へフォールバックする。
  final String? tabLabel;

  /// 表示対象 pane ID（例: "w1:p1"）。
  final String? paneId;

  const HerdrDisplayData({
    this.workspaceLabel,
    this.workspaceId,
    this.tabId,
    this.tabLabel,
    this.paneId,
  });
}

/// pane indicator（右上ミニマップ）の描画データ。
class HerdrPaneIndicatorData {
  /// 描画する pane 一覧（共通 domain 型）。
  final List<MultiplexerPane> panes;

  /// アクティブ（表示中）pane ID。
  final String? activePaneId;

  const HerdrPaneIndicatorData({required this.panes, this.activePaneId});
}

/// スナップショット解決の結果（表示対象 pane + 属する workspace/tab の実値）。
class HerdrResolvedTarget {
  const HerdrResolvedTarget({
    required this.paneId,
    this.workspaceId,
    this.tabId,
    this.tabLabel,
  });

  /// 表示対象 pane ID（例: "w1:p1"）。
  final String paneId;

  /// pane が属する workspace ID（例: "w1"）。snapshot の実値。
  final String? workspaceId;

  /// pane が属する tab ID（例: "w1:t1"）。snapshot の実値。
  final String? tabId;

  /// pane が属する tab の表示名（`MultiplexerWindow.name` 相当・M-4）。
  final String? tabLabel;
}

/// pane ID（"w1:p1" / "w1:t1:p1"）から属する tab ID を best-effort で導出する。
///
/// 3 セグメント形式なら "w1:t1"、2 セグメント形式なら null（不明）。
String? herdrTabIdFromPaneId(String paneId) {
  final segments = paneId.split(':');
  if (segments.length >= 3) return segments.take(2).join(':');
  return null;
}

/// pane ID（例: "w1:p1"）のブレッドクラム表示名を返す（'Pane N'）。
///
/// 末尾セグメントから番号を抽出する（"w1:p1" → "Pane 1"）。抽出できない場合
/// は "Pane 0" を返す。
String herdrPaneSegmentLabel(String paneId, AppLocalizations l10n) {
  final last = paneId.split(':').last;
  final digits = last.replaceAll(RegExp(r'\D'), '');
  final index = int.tryParse(digits) ?? 0;
  return l10n.termPaneLabel(index);
}

/// A10: herdr pane の表示名（3 段セレクタ用）。
///
/// 現在ディレクトリ（currentPath = cwd ?? foregroundCwd）を優先し、無ければ
/// 'Pane N'（index）をフォールバックする。
String herdrPaneLabel(MultiplexerPane pane, AppLocalizations l10n) {
  final cwd = pane.currentPath;
  if (cwd != null && cwd.isNotEmpty) return cwd;
  return l10n.termPaneLabel(pane.index);
}

/// herdr フローの外部依存（root が実装する）。session を import しない。
///
/// herdr サブフロー（setup / sync / selectors / resize / crud）が
/// `HerdrController` から受け取る最小手続きの集合。
abstract interface class HerdrHost {
  WidgetRef get ref;

  BuildContext get context;

  bool get isMounted;

  bool get isDisposed;

  MultiplexerBackendKind get backendKind;

  bool can(PaneCapabilities required);

  PaneWriter? get paneWriter;

  String? get paneId;

  HerdrSnapshotCache? get snapshotCache;

  HerdrDisplayData? get display;

  void setTargetPaneId(String paneId);

  void recordSwitchEvent(String event);

  HerdrTargetIdentity? captureIdentity();

  /// 診断用: 注入 paneContentReader があるか。
  bool get hasInjectedPaneContentReader;

  bool isCurrentIdentity(HerdrTargetIdentity? identity);

  ValueNotifier<HerdrDisplayData?> get displayNotifier;

  ValueNotifier<HerdrPaneIndicatorData?> get indicatorNotifier;

  /// セレクタ表示の委譲先（ui の MultiplexerSheet 実装）。
  HerdrSheetHost? get sheetHost;

  /// ラベル入力ダイアログ（ui の HerdrLabelInputDialog）への委譲。
  Future<String?> Function(HerdrLabelDialogArgs) get showLabelInputDialog;

  /// 接続設定（widget props）。
  String? get sessionId;

  String? get workspaceLabel;

  String? get initialPaneId;

  String? get lastPaneId;

  // ---- 実行系（root/session が注入） ----
  void clearTmuxProvider();

  void recreateReaders();

  void resetTerminalMode();

  /// view クリア + 初回スクロールフラグ false（切替・setup の副作用集約）。
  void resetView();

  void boostPolling();

  void startPolling();

  void suspendPolling();

  void resumePolling();

  void attemptReconnect();

  /// herdr reader/cache/bridge の再生成（session `_recreatePaneReader` の herdr 分岐）。
  PaneFrameReader? rebuildAfterClient(SshClient client);

  HerdrResizeBridge? get resizeBridge;

  bool get isResizing;

  void setResizing(bool value);

  void cancelPollTimer();

  // ---- herdr 内部の公開 API（controller が実装・フローからの再入） ----
  Future<List<MultiplexerSession>?> fetchHerdrSessions({
    required bool force,
    required String eventLabel,
    required bool isTerminal,
  });

  void switchTarget(
    String paneId, {
    String? workspaceLabel,
    String? workspaceId,
    String? tabId,
    String? tabLabel,
  });

  Future<bool> syncAfterMutation({
    String eventLabel,
    HerdrSyncTargetPolicy policy,
  });

  void setIndicatorData(List<MultiplexerSession>? sessions);

  Future<void> handleMutationError(Object e, {required String operationLabel});
}

/// セレクタシート表示の委譲契約（ui 側が実装・`_showMultiplexerSheet` 相当）。
abstract interface class HerdrSheetHost {
  Future<void> show({
    required String title,
    required IconData icon,
    bool topExpected,
    required ConcurrentSelectorLoader load,
  });
}

/// シートの非同期コンテンツ生成（ui の asyncContent 相当）。
typedef ConcurrentSelectorLoader = Future<HerdrSheetContent> Function();

/// セレクタシートの中身（ui が描画する data）。
class HerdrSheetContent {
  const HerdrSheetContent({
    this.headerActions = const [],
    this.top,
    this.tiles = const [],
  });

  final List<HerdrSheetHeaderAction> headerActions;

  /// 分割プレビュー（ui の PaneLayoutVisualizer が描画）。
  final HerdrSheetTopData? top;

  final List<HerdrSheetTile> tiles;
}

/// 分割プレビューの入力データ（ui が [PaneLayoutVisualizer] で描画）。
class HerdrSheetTopData {
  const HerdrSheetTopData({
    required this.window,
    this.activePaneId,
    required this.onSelectPane,
    this.onSplitPane,
  });

  final MultiplexerWindow window;
  final String? activePaneId;
  final ValueChanged<String> onSelectPane;
  final void Function(String paneId, SplitDirection direction)? onSplitPane;
}

class HerdrSheetHeaderAction {
  const HerdrSheetHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

class HerdrSheetTile {
  const HerdrSheetTile({
    required this.key,
    this.session,
    this.window,
    this.pane,
    this.title,
    this.subtitle,
    required this.isActive,
    required this.onTap,
    this.onRename,
    this.onClose,
    this.onResize,
    this.onLongPress,
  });

  final Key key;

  /// workspace タイル（このとき [title] は未使用）。
  final MultiplexerSession? session;

  /// tab タイル（このとき [title] は未使用・実ラベルは window.name が担う）。
  final MultiplexerWindow? window;

  /// pane タイル（[title] = pane 表示名（cwd 優先・A10））。
  final MultiplexerPane? pane;

  final String? title;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onClose;
  final VoidCallback? onResize;
  final VoidCallback? onLongPress;
}

/// ラベル入力ダイアログ（ui の HerdrLabelInputDialog）の引数。
class HerdrLabelDialogArgs {
  const HerdrLabelDialogArgs({
    required this.title,
    required this.labelText,
    required this.hintText,
    required this.confirmLabel,
    this.initialValue,
    this.allowEmpty = false,
  });

  final String title;
  final String labelText;
  final String hintText;
  final String confirmLabel;
  final String? initialValue;
  final bool allowEmpty;
}

/// セレクタから発火するダイアログ/操作（resize・crud フローがコールバック注入）。
///
/// controller が生成する bundle。セレクタ自体のロジック（選択・切替）は
/// committer が行い、ダイアログ起動のみここへ委譲する（cycle 回避）。
abstract interface class HerdrDialogActions {
  void showResizePaneChooser(
    List<MultiplexerSession> sessions,
    MultiplexerWindow window,
  );

  void showResizeTerminal();

  void showCreateTabDialog(MultiplexerSession workspace);

  void showRenameTabDialog(MultiplexerSession workspace, MultiplexerWindow tab);

  void confirmCloseTab({
    required MultiplexerSession workspace,
    required MultiplexerWindow tab,
    required bool isLastTab,
  });

  void confirmKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastTab,
  });

  void splitPane(String paneId, SplitDirection direction);
}
