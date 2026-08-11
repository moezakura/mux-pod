import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/backend/backend_type.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
import '../../services/backend/domain/multiplexer_pane.dart';
import '../../services/backend/domain/multiplexer_session.dart';
import '../../services/backend/domain/multiplexer_window.dart';
import '../../services/backend/domain/herdr_pane_writer.dart';
import '../../services/backend/domain/pane_content_reader.dart';
import '../../services/backend/domain/pane_frame_reader.dart';
import '../../services/backend/domain/pane_history_policy.dart';
import '../../services/backend/domain/pane_read.dart';
import '../../services/backend/domain/pane_writer.dart';
import '../../services/backend/domain/tmux_pane_writer.dart';
import '../../services/herdr/herdr_adapter.dart';
import '../../services/herdr/herdr_commands.dart'
    show HerdrCommandException, HerdrTargetNotFoundException;
import '../../services/herdr/herdr_errors.dart';
import '../../services/herdr/herdr_models.dart';
import '../../services/herdr/herdr_pane_content_reader.dart';
import '../../services/herdr/herdr_pane_frame_reader.dart';
import '../../services/herdr/herdr_snapshot_cache.dart';
import '../../services/herdr/herdr_target_resolver.dart';
import '../../services/herdr/herdr_to_domain.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/network/network_monitor.dart';
import '../../services/ssh/input_queue.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/tmux/pane_navigator.dart';
import '../../services/tmux/tmux_pane_content_reader.dart';
import '../../services/terminal/font_calculator.dart';
import '../../services/terminal/adaptive_polling.dart';
import '../../services/tmux/tmux_command_builder.dart';
import '../../services/tmux/tmux_facade.dart';
import '../../services/tmux/tmux_models.dart';
import '../../services/tmux/tmux_to_domain.dart';

import '../../services/tmux/tmux_version.dart';
import '../../widgets/dialogs/resize_dialog.dart';
import '../../widgets/dialogs/rename_window_dialog.dart';
import '../../theme/design_colors.dart';
import '../../services/terminal/tmux_key_display.dart';
import '../../widgets/key_overlay_widget.dart';
import '../../widgets/scroll_to_bottom_button.dart';
import '../../widgets/special_keys_bar.dart';
import '../../widgets/image_transfer_confirm_dialog.dart';
import '../../widgets/multiplexer_tiles.dart';
import '../../providers/terminal_display_provider.dart';
import '../../providers/image_transfer_provider.dart';
import '../file_browser/file_browser_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../settings/settings_screen.dart';
import 'widgets/ansi_text_view.dart';
import 'widgets/terminal_zoom.dart';

// inventory: TERM-ENUM-001
/// スクロールモードのソース
enum ScrollModeSource {
  /// 通常モード（スクロールモードではない）
  none,

  /// ユーザーがUIから手動で有効化
  manual,

  /// tmux copy-modeを自動検出
  tmux,
}

// inventory: TERM-SCREEN-002
/// ポーリングで頻繁に更新されるターミナル表示データ
///
/// ValueNotifierで管理し、親ウィジェットのsetState()を回避する。
/// これによりBottomSheet表示中の親リビルドを防ぎ、
/// isDismissible: trueでも安定して動作する。
class _TerminalViewData {
  // inventory: LEGACY-0059
  final String content;
  // inventory: LEGACY-0060
  final int paneWidth;
  // inventory: LEGACY-0061
  final int paneHeight;

  const _TerminalViewData({
    this.content = '',
    this.paneWidth = 80,
    this.paneHeight = 24,
  });

  // inventory: LEGACY-0062
  _TerminalViewData copyWith({
    String? content,
    int? paneWidth,
    int? paneHeight,
  }) => _TerminalViewData(
    content: content ?? this.content,
    paneWidth: paneWidth ?? this.paneWidth,
    paneHeight: paneHeight ?? this.paneHeight,
  );
}

// inventory: TERM-SRC-000
/// 現在の表示対象 pane ID の取得抽象（A9）。
///
/// tmux は毎呼出し現在ターゲットへ遅延委譲（null 伝播維持）、herdr は固定
/// pane ID を返す。これにより L952/L1084 の `??` 分裂
/// （`_pollTargetPaneId ?? tmuxProvider.currentTarget`）を一本化する。
///
/// 抽象に含めるのは `currentPaneId` のみ。`switchTarget` / `fetchTree` は
/// 含めない（tmux に「アプリローカル表示切替」概念がなく、抽象に入れると
/// 嘘の意味論 or no-op になるため。切替は画面メソッドに残す）。
abstract interface class _TargetSource {
  /// 現在の表示対象 pane ID（tmux で未確定の場合は null）。
  String? get currentPaneId;
}

// inventory: TERM-SRC-001
/// tmux: 毎呼出し現在ターゲットへ遅延委譲する [TmuxNotifier.currentTarget]。
///
/// 遅延委譲により、tmux の split/kill で index がずれても対象が変わらない
/// 既存挙動を保持する（null 伝播も維持）。
class _TmuxTargetSource implements _TargetSource {
  final String? Function() _readCurrentTarget;

  _TmuxTargetSource(this._readCurrentTarget);

  @override
  String? get currentPaneId => _readCurrentTarget();
}

// inventory: TERM-SRC-002
/// herdr: 固定 pane ID を返す。
///
/// 接続時に解決した pane ID を保持する。切替時は適用層
/// （`_switchHerdrTarget`）が [setPaneId] で差し替える。
class _HerdrTargetSource implements _TargetSource {
  String _paneId;

  _HerdrTargetSource(this._paneId);

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
/// 画面側に世代カウンタは持たない。`HerdrSnapshotCache.epoch`（バンプは
/// cache 内在: adapter 差し替え / force 再取得）と [_TargetSource.currentPaneId]
/// （切替コミット [_switchHerdrTarget]）の 2 つを同一性キーとして、非同期 read
/// の開始時と完了・適用時で照合する。不一致は await 中に切替・再解決・
/// 再接続が発生したことを意味し、結果を破棄すべき。
typedef _HerdrTargetIdentity = ({
  HerdrSnapshotCache cache,
  int epoch,
  String? paneId,
});

// inventory: TERM-DISP-000
/// herdr の表示状態（A9）。
///
/// workspace/tab/pane の位置情報のみを保持する不変データ。コンテンツ
/// （[_TerminalViewData] / `_viewNotifier`）とは別系統で、画面ローカルの
/// `_herdrDisplayNotifier`（`ValueNotifier<_HerdrDisplayData?>`）が保持する。
/// ブレッドクラム（`_herdrToBreadcrumb`）の入力になる。
class _HerdrDisplayData {
  /// workspace の表示ラベル（要求時 [TerminalScreen.sessionName] 相当）。
  final String? workspaceLabel;

  /// workspace ID（例: "w1"）。解決タスクが確定した時点で設定される。
  final String? workspaceId;

  /// 表示対象 pane が属する tab ID（例: "w1:t1"）。
  ///
  /// スナップショット解決済みの実値（[HerdrPane.tabId] / `MultiplexerWindow.id`
  /// 相当）を保持する（L-1）。直接指定（initialPaneId / lastPaneId）やセレクタ
  /// 経由などスナップショット解決を伴わない経路では、pane ID
  /// （"w1:p1" / "w1:t1:p1"）から best-effort で導出する（T11）。pane ID が
  /// 2 セグメント形式（G4 実測の "w1:p1"）の場合は不明のため null。
  final String? tabId;

  /// tab の表示名（`MultiplexerWindow.name` 相当 = `tab.label ?? tab.id`・M-4）。
  ///
  /// スナップショット解決済みの実値を保持する。パンくずの tab セグメントは
  /// この値（数字抽出した [tabId] ではなく実ラベル）を表示する（T4）。
  /// 解決を伴わない経路（直接指定・テストフック）では null になり、
  /// 表示時は [tabId] へフォールバックする。
  final String? tabLabel;

  /// 表示対象 pane ID（例: "w1:p1"）。
  final String? paneId;

  const _HerdrDisplayData({
    this.workspaceLabel,
    this.workspaceId,
    this.tabId,
    this.tabLabel,
    this.paneId,
  });
}

/// スナップショット解決の結果（表示対象 pane + 属する workspace/tab の実値）。
///
/// [HerdrTargetResolver.resolve] で決定した pane ID に対し、snapshot の
/// [HerdrPane]（`workspaceId` / `tabId`）から実値を引き当てて保持する（L-1）。
/// 解決 pane が snapshot に存在する限り workspaceId / tabId は非 null になる
/// （防御的に null 許容で定義する）。
class _HerdrResolvedTarget {
  const _HerdrResolvedTarget({
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
  /// snapshot の実値（`tab.label ?? tab.id`）。null の場合は不明。
  final String? tabLabel;
}

/// pane ID（"w1:p1" / "w1:t1:p1"）から属する tab ID を best-effort で導出する。
///
/// 3 セグメント形式なら "w1:t1"、2 セグメント形式なら null（不明）。スナップ
/// ショット解決（`HerdrPane.tabId`）を伴わない経路（直接指定・セレクタ）の
/// フォールバックに使う（L-1）。解決済みの実値がある場合はそちらを優先する。
String? _herdrTabIdFromPaneId(String paneId) {
  final segments = paneId.split(':');
  if (segments.length >= 3) return segments.take(2).join(':');
  return null;
}

/// pane ID（例: "w1:p1"）のブレッドクラム表示名を返す（'Pane N'）。
///
/// 末尾セグメントから番号を抽出する（"w1:p1" → "Pane 1"）。抽出できない場合
/// は "Pane 0" を返す。A10 の currentPath 優先ルールはセレクタ側
/// （[_herdrPaneLabel]）で適用し、ブレッドクラムは番号ベースで統一する。
String _herdrPaneSegmentLabel(String paneId) {
  final last = paneId.split(':').last;
  final digits = last.replaceAll(RegExp(r'\D'), '');
  final index = int.tryParse(digits) ?? 0;
  return 'Pane $index';
}

/// A10: herdr pane の表示名（3 段セレクタ用）。
///
/// 現在ディレクトリ（currentPath = cwd ?? foregroundCwd）を優先し、無ければ
/// 'Pane N'（index）をフォールバックする。
String _herdrPaneLabel(MultiplexerPane pane) {
  final cwd = pane.currentPath;
  if (cwd != null && cwd.isNotEmpty) return cwd;
  return 'Pane ${pane.index}';
}

// inventory: TERM-BREAD-000
/// ブレッドクラム描画用の共通データ（A9）。
///
/// tmux 経路（`_tmuxToBreadcrumb`）と herdr 経路（`_herdrToBreadcrumb`）の
/// どちらもこのデータへ変換し、`_buildBreadcrumbHeader` はこのデータだけを
/// 受け取って描画する（backend 分岐はデータ生成側に閉じる）。
class _BreadcrumbData {
  /// セッション名（tmux）または workspace ラベル（herdr）。
  final String session;

  /// ウィンドウ名。null なら非表示（read-only 等）。
  final String? window;

  /// ペイン表示文字列（例: "Pane 0"）。null なら非表示。
  final String? pane;

  /// true なら read-only バッジを表示し、window/pane セグメントを省略する。
  final bool readOnlyBadge;

  /// セッション/workspace セグメントのタップ（セレクタ表示）。
  final VoidCallback? onSessionTap;

  /// ウィンドウセグメントのタップ（セレクタ表示）。
  final VoidCallback? onWindowTap;

  /// ペインセグメントのタップ（セレクタ表示）。
  final VoidCallback? onPaneTap;

  /// read-only バッジのタップ（T11: herdr のみ 3 段セレクタを開く）。
  final VoidCallback? onReadOnlyTap;

  const _BreadcrumbData({
    required this.session,
    this.window,
    this.pane,
    this.readOnlyBadge = false,
    this.onSessionTap,
    this.onWindowTap,
    this.onPaneTap,
    this.onReadOnlyTap,
  });
}

// inventory: TERM-SCREEN-001
/// ターミナル画面（HTMLデザイン仕様準拠）
class TerminalScreen extends ConsumerStatefulWidget {
  // inventory: LEGACY-0063
  final String connectionId;
  // inventory: LEGACY-0064
  final String? sessionName;

  // inventory: TERM-SCREEN-007
  /// セッション ID（tmux: "$0" / herdr: "w3"）。
  ///
  /// herdr では同名ラベル（例: "tmp" の w3/w4）の workspace を ID で区別する
  /// ために使う（id 一致 → label 一致 → フォールバックの優先順）。tmux 経路
  /// ではセッション照合・新規作成に実セッション名（[sessionName]）を使うため、
  /// この値は tmux の解決には影響しない。null 許容（旧呼び出し互換）。
  final String? sessionId;

  // inventory: LEGACY-0065
  /// 復元用: 最後に開いていたウィンドウインデックス
  final int? lastWindowIndex;

  // inventory: LEGACY-0066
  /// 復元用: 最後に開いていたペインID
  final String? lastPaneId;

  // inventory: LEGACY-0067
  /// ディープリンク用: ウィンドウ名で指定（インデックスではなく名前で検索）
  final String? deepLinkWindowName;

  // inventory: LEGACY-0068
  /// ディープリンク用: ペインインデックス
  final int? deepLinkPaneIndex;

  // inventory: TERM-SCREEN-004
  /// ペイン内容読み取りの注入用（テスト・呼び出し側）。
  ///
  /// null なら接続の backend 種別に応じて
  /// [TmuxPaneContentReader] / [HerdrPaneContentReader] を自動生成する。
  final PaneContentReader? paneContentReader;

  // inventory: TERM-SCREEN-005
  /// read-only（herdr）表示モード。
  ///
  /// true の場合、mutation（キー入力・copy-mode・特殊キー・CRUD・リサイズ）
  /// を非表示/無効化し、ペイン内容の表示とスクロールのみを提供する。
  final bool readOnly;

  // inventory: TERM-SCREEN-006
  /// 直接表示する pane ID（herdr 用）。
  ///
  /// null なら接続先の herdr スナップショットから
  /// セッション名（workspace label/id）に一致する pane を解決する。
  final String? initialPaneId;

  const TerminalScreen({
    super.key,
    required this.connectionId,
    this.sessionName,
    this.sessionId,
    this.lastWindowIndex,
    this.lastPaneId,
    this.deepLinkWindowName,
    this.deepLinkPaneIndex,
    this.paneContentReader,
    this.readOnly = false,
    this.initialPaneId,
  });

  @override
  // inventory: LEGACY-0069
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

// inventory: TERM-SCREEN-003
class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  final _secureStorage = SecureStorageService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _ansiTextViewKey = GlobalKey<AnsiTextViewState>();
  final _scrollToBottomKey = GlobalKey<ScrollToBottomButtonState>();
  final _terminalScrollController = ScrollController();

  // 接続状態（ローカルで管理）
  bool _isConnecting = false;
  String? _connectionError;
  SshState _sshState = const SshState();

  // ポーリングで頻繁に更新されるターミナル表示データ（ValueNotifierで管理）
  // 親のsetState()を回避し、ValueListenableBuilderでサブツリーのみリビルドする
  final _viewNotifier = ValueNotifier<_TerminalViewData>(
    const _TerminalViewData(),
  );

  // 表示状態（A9）: herdr の workspace/tab/pane 位置。コンテンツ（_viewNotifier）
  // とは別系統の画面ローカル Notifier。ブレッドクラムの入力になる。
  final _herdrDisplayNotifier = ValueNotifier<_HerdrDisplayData?>(null);

  // レイテンシ表示専用のNotifier（ping揺れで本文が再描画されないよう分離）
  final _latencyNotifier = ValueNotifier<int>(0);

  // キーオーバーレイ
  final KeyOverlayState _keyOverlayState = KeyOverlayState();
  Timer? _keyOverlayTimer;

  // ポーリング用タイマー
  Timer? _pollTimer;
  Timer? _treeRefreshTimer;
  bool _isPolling = false;
  bool _isDisposed = false;

  // フレームスキップ用（高頻度更新の最適化）
  static const _minFrameInterval = Duration(milliseconds: 16); // ~60fps
  DateTime _lastFrameTime = DateTime.now();
  bool _pendingUpdate = false;
  String _pendingContent = '';

  // A3改: 保留中コンテンツ（_pendingContent）の表示対象同一性。
  // `_scheduleUpdate` で設定し、`_applyUpdate` で照合に使う（不一致なら破棄）。
  _HerdrTargetIdentity? _pendingTargetIdentity;

  // 適応型ポーリング用
  int _currentPollingInterval = 100;
  static const int _minPollingInterval = 50;
  static const int _maxPollingInterval = 2000;

  // 変化頻度トラッキング（毎ポーリングで更新。アイドル時にポーリングをバックオフ）
  int _unchangedPolls = 0;
  String? _lastPolledContent;

  // 選択状態保持用（スクロールモード中の更新抑制）
  String _bufferedContent = '';
  bool _hasBufferedUpdate = false;

  // A3改: バッファされた更新（_bufferedContent）の表示対象同一性。
  // バッファ時に記録し、適用時（_applyBufferedUpdate → _applyUpdate）に照合する。
  _HerdrTargetIdentity? _bufferedTargetIdentity;

  // 深い履歴（全スクロールバック）の自動ロード用
  bool _isLoadingDeepHistory = false;

  // 初回スクロール完了フラグ
  bool _hasInitialScrolled = false;

  // ターミナルモード
  TerminalMode _terminalMode = TerminalMode.normal;

  // スクロールモードのソース（none / manual / tmux）
  ScrollModeSource _scrollModeSource = ScrollModeSource.none;

  // ズームスケール
  double _zoomScale = 1.0;

  /// 表示中の実効ズーム倍率（永続 zoomFactor × ピンチ中のプレビュー _zoomScale）。
  double get _effectiveZoom =>
      ref.read(settingsProvider).zoomFactor * _zoomScale;

  /// 実効ズームが等倍でない（インジケータ/リセットの活性判定）。
  bool get _isZoomed => (_effectiveZoom - 1.0).abs() > 0.005;

  // EnterCommand入力内容保持（ボトムシートを閉じても保持）
  String _savedCommandInput = '';

  // 入力キュー（切断中の入力を保持）
  final _inputQueue = InputQueue();

  // バックグラウンド状態
  bool _isInBackground = false;

  // directInput設定のローカルキャッシュ（ref.watch回避）
  bool _directInputEnabled = true;

  // ウィンドウ作成中フラグ（連打防止）
  bool _isCreatingWindow = false;

  // リサイズ中フラグ（排他制御）
  bool _isResizing = false;

  // AutoResizeで縮めたtmuxウィンドウ（切断時に自動サイズへ戻す）
  final Set<String> _resizedWindowTargets = <String>{};

  // バックグラウンド移行時に自動サイズへ戻したか（復帰時の再フィット用）
  bool _windowsRestoredForBackground = false;

  // 自動リサイズのdebounceタイマー（画面サイズ変更時）
  Timer? _autoResizeDebounceTimer;

  // フォアグラウンドを離れてからウィンドウ復元までの猶予タイマー
  Timer? _backgroundRestoreTimer;

  // tmuxバージョン情報（リサイズ機能判定用）
  TmuxVersionInfo? _tmuxVersion;

  // ペイン内容読み取り（backend 種別で tmux/herdr を選択）
  PaneContentReader? _paneReader;

  // ペイン表示フレーム合成（content + geometry・バグ1 根本対応）。
  // herdr は content と layout を合成する。tmux は PaneFrameReader を使わず
  // 従来の PaneContentReader（poll で geometry 込み）をそのまま使う。
  PaneFrameReader? _frameReader;

  // ペイン操作（write 側抽象）。backend 種別で生成する（T8: `TmuxPaneWriter` /
  // `HerdrPaneWriter`。Phase 0 の仮実装 `_Phase0PaneWriter` は廃止）。呼び出し
  // 側の明示（`readOnly: true`）・未接続時は null（全 capability false 扱い）。
  PaneWriter? _paneWriter;

  // ポーリング対象 pane ID の取得抽象（tmux=遅延委譲 / herdr=固定 ID）
  _TargetSource? _targetSource;

  // herdr スナップショットキャッシュ（A5: 唯一の read chokepoint）。
  // 再接続で adapter が差し替わるときは `_recreatePaneReader` で作り直す。
  HerdrSnapshotCache? _herdrSnapshotCache;

  // server-down / 終端エラーでポーリングを停止したか（再開まで _scheduleNextPoll を抑止）。
  bool _pollingSuspended = false;

  // backend 種別（`_can` 判定・操作能力の導出に使う。接続前は unknown）
  MultiplexerBackendKind _backendKind = MultiplexerBackendKind.unknown;

  /// 現在のバックエンドが持つ操作能力。
  ///
  /// `_paneWriter` が未生成（[TerminalScreen.readOnly] 明示・未接続）の場合は
  /// 全能力 false（read-only 相当）。Phase 0 では herdr は全能力 false・
  /// tmux は全 true のため、`!_can` は従来の `_isReadOnly`
  /// （`widget.readOnly || _backendKind == herdr`）と同値になる（H4 等価性）。
  PaneCapabilities get _paneCapabilities =>
      _paneWriter?.capabilities ?? const PaneCapabilities();

  /// 指定した操作能力（[required] に true が立っている能力）が現在の
  /// バックエンドで有効かどうか。
  ///
  /// 判定は純データで副作用なし（L2-1）。UI ガードはすべて `!_can(...)`
  /// に置換する（`_isReadOnly` の boolean では操作単位の解禁/遮断を表現
  /// できない・Q-02/H4）。
  bool _can(PaneCapabilities required) {
    final caps = _paneCapabilities;
    return (required.sendText == false || caps.sendText) &&
        (required.sendKeys == false || caps.sendKeys) &&
        (required.focus == false || caps.focus) &&
        (required.split == false || caps.split) &&
        (required.close == false || caps.close) &&
        (required.rename == false || caps.rename) &&
        (required.zoom == false || caps.zoom) &&
        (required.resize == false || caps.resize) &&
        (required.paste == false || caps.paste) &&
        (required.copyMode == false || caps.copyMode) &&
        (required.imageTransfer == false || caps.imageTransfer) &&
        (required.workspaceCrud == false || caps.workspaceCrud) &&
        (required.tabCrud == false || caps.tabCrud) &&
        (required.absoluteResize == false || caps.absoluteResize);
  }

  /// テキスト送信（`send-text`）が可能か。
  bool get _canSendText => _can(const PaneCapabilities(sendText: true));

  /// 特殊キー送信（`send-keys` / エスケープ / 制御文字）が可能か。
  bool get _canSendSpecialKey => _can(const PaneCapabilities(sendKeys: true));

  /// 方向フォーカス移動（2 本指スワイプ・矢印・navigableDirections）が可能か。
  bool get _canFocusDirection => _can(const PaneCapabilities(focus: true));

  /// 分割（split）が可能か。
  bool get _canSplitPane => _can(const PaneCapabilities(split: true));

  /// copy-mode（履歴選択モード）が可能か。
  bool get _canCopyMode => _can(const PaneCapabilities(copyMode: true));

  // 最小監視（A8）: herdr 表示対象切替・server-down 検出・再解決の直近イベントを
  // 記録するリングバッファ。診断用であり、SDK 送信は行わない（プライバシー・最小導線）。
  static const int _herdrSwitchEventBufferSize = 64;
  final List<String> _herdrSwitchEvents = <String>[];

  // inventory: TERM-MON-000
  /// リングバッファ（直近 64 件）へイベントを記録し debugPrint する（A8）。
  ///
  /// [event] には pane ID 等の位置情報を含めてよいが、snapshot / pane 内容など
  /// の機密情報は含めない（非機能: セキュリティ/プライバシー）。SDK 送信は
  /// 行わない（A8: 最小監視）。
  void _recordHerdrSwitchEvent(String event) {
    final entry = '[HerdrSwitch] $event';
    if (_herdrSwitchEvents.length >= _herdrSwitchEventBufferSize) {
      _herdrSwitchEvents.removeAt(0);
    }
    _herdrSwitchEvents.add(entry);
    debugPrint(entry);
  }

  // inventory: TERM-EPOCH-001
  /// 現在の herdr 表示対象同一性を記録する（A3改）。
  ///
  /// 非同期 read の開始前に呼び、完了時（[._isCurrentHerdrTarget]）と照合する。
  /// tmux パス（[HerdrSnapshotCache] 未使用）や cache 未生成の間は null を返し、
  /// 照合は常に成功させる（従来挙動維持）。
  _HerdrTargetIdentity? _captureHerdrTarget() {
    final cache = _herdrSnapshotCache;
    if (cache == null) return null;
    return (
      cache: cache,
      epoch: cache.epoch,
      paneId: _targetSource?.currentPaneId,
    );
  }

  // inventory: TERM-EPOCH-002
  /// 記録 [identity] が現在の表示対象と一致するか照合する（A3改）。
  ///
  /// 不一致は await 中に表示対象切替（[_switchHerdrTarget]）・再解決（force
  /// 再取得によるエポック++）・再接続（cache 再生成）が発生したことを意味し、
  /// 呼び出し側は結果を破棄すべき。バンプは行わない（バンプは cache 内在）。
  /// [identity] が null（tmux パス）のときは常に true。
  bool _isCurrentHerdrTarget(_HerdrTargetIdentity? identity) {
    if (identity == null) return true; // tmux パス: 照合適用外（従来挙動維持）
    final cache = _herdrSnapshotCache;
    return identical(cache, identity.cache) &&
        cache != null &&
        cache.epoch == identity.epoch &&
        _targetSource?.currentPaneId == identity.paneId;
  }

  // Riverpodリスナー
  ProviderSubscription<SshState>? _sshSubscription;
  ProviderSubscription<TmuxState>? _tmuxSubscription;
  ProviderSubscription<AppSettings>? _settingsSubscription;
  ProviderSubscription<AsyncValue<NetworkStatus>>? _networkSubscription;

  @override
  // inventory: TERM-LIFE-001
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // スクロール時にスクロールボタンを表示
    // inventory: TERM-SCROLL-001
    _terminalScrollController.addListener(_onTerminalScroll);

    // 次フレームでリスナーを設定（ref使用のため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // inventory: TERM-LIFE-008
      _setupListeners();
      _connectAndSetup();
      // inventory: TERM-LIFE-007
      _applyKeepScreenOn();
    });
  }

  @override
  // inventory: TERM-LIFE-002
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.inactive:
        // 一時的な非アクティブ（通知シェード等）: 猶予後に復元をスケジュール。
        // 早期復帰すればキャンセルされ、無駄なリサイズ往復を避ける。
        // inventory: TERM-LIFE-005
        _pausePolling();
        // inventory: TERM-LIFE-004
        _scheduleBackgroundRestore();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 明確なバックグラウンド化。最近のアプリからスワイプ終了されても、SSHが
        // 生きているこの時点で（猶予を待たず即座に）復元する。
        _pausePolling();
        _backgroundRestoreTimer?.cancel();
        if (_resizedWindowTargets.isNotEmpty) {
          _windowsRestoredForBackground = true;
        }
        // inventory: TERM-RESIZE-002
        _restoreResizedWindows();
        break;
      case AppLifecycleState.resumed:
        _backgroundRestoreTimer?.cancel();
        // inventory: TERM-LIFE-006
        _resumePolling();
        // バックグラウンドで戻していた場合は画面サイズに合わせて再リサイズ
        if (_windowsRestoredForBackground) {
          _windowsRestoredForBackground = false;
          final pane = ref.read(tmuxProvider).activePane;
          if (pane != null && ref.read(settingsProvider).isAutoResize) {
            // inventory: TERM-RESIZE-001
            _executeAutoResize(pane, force: true);
          }
        }
        break;
      case AppLifecycleState.detached:
        // フォールバック: 即時ベストエフォートで復元
        _backgroundRestoreTimer?.cancel();
        if (_resizedWindowTargets.isNotEmpty) {
          _windowsRestoredForBackground = true;
        }
        _restoreResizedWindows();
        break;
    }
  }

  /// フォアグラウンドを離れて一定時間経過したら、AutoResizeで縮めたtmuxウィンドウを
  /// 自動サイズへ戻す。短時間で復帰した場合（通知シェード等の一時的な非アクティブ）は
  /// resumedでキャンセルされ、無駄なリサイズ往復を避ける。
  void _scheduleBackgroundRestore() {
    _backgroundRestoreTimer?.cancel();
    _backgroundRestoreTimer = Timer(const Duration(milliseconds: 600), () {
      if (_isDisposed) return;
      if (_resizedWindowTargets.isNotEmpty) {
        _windowsRestoredForBackground = true;
      }
      _restoreResizedWindows();
    });
  }

  @override
  // inventory: TERM-LIFE-003
  void didChangeMetrics() {
    super.didChangeMetrics();
    final settings = ref.read(settingsProvider);
    if (!settings.isAutoResize) return;

    // debounce: 画面回転・折りたたみの連続サイズ変更を抑制
    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isDisposed) return;
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        _executeAutoResize(activePane);
      }
    });
  }

  /// バックグラウンド移行時にポーリングを停止
  void _pausePolling() {
    _isInBackground = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = null;
    WakelockPlus.disable();
  }

  /// フォアグラウンド復帰時にポーリングを再開
  void _resumePolling() {
    if (!_isInBackground || _isDisposed) return;
    _isInBackground = false;
    if (_backendKind == MultiplexerBackendKind.herdr) {
      // herdr: tmux 専用のツリー更新（_startTreeRefresh）は起動しない
      // （既存バグ修正・A7）。server-down 停止状態からの復帰はサーバー復旧を
      // 再検証してポーリングを再開する（停止のまま戻ると表示が固まり、再開
      // 手段が SnackBar の Retry のみになるため）。
      _pollingSuspended = false;
    }
    // inventory: TERM-LIFE-014
    _startPolling();
    if (_backendKind != MultiplexerBackendKind.herdr) {
      // inventory: TERM-LIFE-013
      _startTreeRefresh();
    }
    _applyKeepScreenOn();
  }

  /// Keep screen on設定を適用
  void _applyKeepScreenOn() {
    final settings = ref.read(settingsProvider);
    if (settings.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Providerのリスナーを設定
  void _setupListeners() {
    // SSH状態の変化を監視
    _sshSubscription = ref.listenManual<SshState>(sshProvider, (
      previous,
      next,
    ) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _sshState = next;
      });
    }, fireImmediately: true);

    // Tmux状態の変化を監視
    // 注意: 親のsetState()は不要。ブレッドクラムやペインインジケーターは
    // Consumer widgetでtmuxProviderを直接watchするため、
    // サブツリー内でのみリビルドされる。
    _tmuxSubscription = ref.listenManual<TmuxState>(tmuxProvider, (
      previous,
      next,
    ) {
      // Consumer widgets が直接 tmuxProvider を watch しているため、
      // 親の setState() は不要（BottomSheet安定化のため除去）
    }, fireImmediately: true);

    // 設定の変化を監視（Keep screen on / directInput用）
    _settingsSubscription = ref.listenManual<AppSettings>(settingsProvider, (
      previous,
      next,
    ) {
      if (!mounted || _isDisposed) return;
      if (previous?.keepScreenOn != next.keepScreenOn) {
        _applyKeepScreenOn();
      }
      if (previous?.directInputEnabled != next.directInputEnabled) {
        setState(() {
          _directInputEnabled = next.directInputEnabled;
        });
      }
      // AutoResize時: フォント/ズーム変更（ピンチや設定）で tmux ペインを再フィット
      if (next.isAutoResize &&
          (previous?.fontSize != next.fontSize ||
              previous?.zoomFactor != next.zoomFactor)) {
        final pane = ref.read(tmuxProvider).activePane;
        if (pane != null) _executeAutoResize(pane);
      }
    }, fireImmediately: false);

    // 初期値を明示的に設定
    _directInputEnabled = ref.read(settingsProvider).directInputEnabled;

    // ネットワーク状態の変化を監視（実際の接続状態変化時のみ更新）
    _networkSubscription = ref.listenManual<AsyncValue<NetworkStatus>>(
      networkStatusProvider,
      (previous, next) {
        if (!mounted || _isDisposed) return;
        final prevStatus = previous?.value;
        final nextStatus = next.value;
        if (prevStatus != nextStatus) {
          setState(() {});
        }
      },
      fireImmediately: true,
    );

    // 再接続成功時の処理を設定
    final sshNotifier = ref.read(sshProvider.notifier);
    // inventory: TERM-LIFE-009
    sshNotifier.onReconnectSuccess = _onReconnectSuccess;
  }

  /// 再接続成功時の処理
  Future<void> _onReconnectSuccess() async {
    if (!mounted || _isDisposed) return;

    // ポーリングフラグをリセット
    _isPolling = false;

    // 再接続で SshClient が作り直されたため、ペイン内容読み取りを再生成
    _recreatePaneReader();

    if (_backendKind == MultiplexerBackendKind.herdr) {
      // herdr: ターゲットを再解決して表示を継続する。adapter 差し替えの検出
      // （`identical`）とエポック++ は cache 内在で自動（A3改）。tmux 専用の
      // ツリー更新（_startTreeRefresh）は起動しない（既存バグ修正・A7）。
      final resolved = await _reResolveHerdrTargetAfterReconnect();
      if (resolved && !_isDisposed) {
        // 再接続成功を再試行点としてポーリングを再開する。server-down 停止中
        // でもサーバー復旧を再検証し、復旧していれば通常表示へ戻る（停止中
        // なら次回ポーリングで再停止 + SnackBar 通知）。
        _pollingSuspended = false;
        _startPolling();
      }
    } else {
      // ポーリングを再開
      _startPolling();

      // セッションツリーを再取得
      _startTreeRefresh();
    }

    // キューされた入力を送信
    // inventory: TERM-LIFE-010
    await _flushInputQueue();

    // UIを更新
    if (mounted) setState(() {});
  }

  /// キューされた入力を送信
  Future<void> _flushInputQueue() async {
    if (_inputQueue.isEmpty) return;

    final queuedInput = _inputQueue.flush();
    if (queuedInput.isNotEmpty) {
      // inventory: TERM-INPUT-002
      await _sendKeyData(queuedInput);
    }
  }

  /// SSH接続してtmuxセッションをセットアップ
  Future<void> _connectAndSetup() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      // 1. 接続情報を取得
      final connection = ref
          .read(connectionsProvider.notifier)
          .getById(widget.connectionId);
      if (connection == null) {
        throw Exception('Connection not found');
      }

      // 1.5. backend 種別を確定（herdr は read-only 分岐に使う）
      final isHerdr = connection.multiplexer.backend == BackendType.herdr;
      _backendKind = isHerdr
          ? MultiplexerBackendKind.herdr
          : MultiplexerBackendKind.tmux;

      // 2. 認証情報を取得
      final options = await _getAuthOptions(connection);
      if (!mounted || _isDisposed) {
        return;
      }

      // 3. SSH接続（シェルは起動しない - execのみ使用）
      final sshNotifier = ref.read(sshProvider.notifier);
      await sshNotifier.connectWithoutShell(connection, options);
      if (!mounted || _isDisposed) {
        return;
      }

      final client = sshNotifier.client;
      if (client == null) {
        throw Exception('SSH client is not available');
      }

      // 3.4. herdr: read-only セッションを設定して終了
      if (isHerdr) {
        await _setupHerdrSession(client);
        if (!mounted || _isDisposed) return;
        setState(() {
          _isConnecting = false;
        });
        return;
      }

      // 3.5. tmuxバージョン取得（リサイズ機能判定用）
      try {
        _tmuxVersion = await tmuxFacade.getVersion(client.tmuxExecutor);
      } catch (_) {
        _tmuxVersion = null;
      }

      // tmux のペイン内容読み取りを設定
      _recreatePaneReader();
      if (_paneReader == null) {
        throw Exception('Pane content reader is not available');
      }

      // 4. セ���ションツリー全体を取得
      // inventory: TERM-LIFE-012
      await _refreshSessionTree();
      if (!mounted || _isDisposed) {
        return;
      }

      final tmuxState = ref.read(tmuxProvider);
      final sessions = tmuxState.sessions;

      // 5. セッションを選択または新規作成
      String sessionName;
      if (widget.sessionName != null) {
        // セッション名が指定されている場合
        final existingIndex = sessions.indexWhere(
          (s) => s.name == widget.sessionName,
        );
        if (existingIndex >= 0) {
          // 既存セッションに接続
          sessionName = sessions[existingIndex].name;
        } else {
          // 新規セッション作成
          final sshClient = ref.read(sshProvider.notifier).client;
          if (sshClient != null) {
            await tmuxFacade.createSession(
              sshClient.tmuxExecutor,
              name: widget.sessionName!,
              detached: true,
            );
          }
          if (!mounted || _isDisposed) return;
          await _refreshSessionTree();
          if (!mounted || _isDisposed) return;
          sessionName = widget.sessionName!;
        }
      } else if (sessions.isNotEmpty) {
        // セッション名が指定されていない場合は最初のセッションに接続
        sessionName = sessions.first.name;
      } else {
        // セッションがない場合は自動生成名で新規作成
        final sshClient = ref.read(sshProvider.notifier).client;
        sessionName = 'muxpod-${DateTime.now().millisecondsSinceEpoch}';
        if (sshClient != null) {
          await tmuxFacade.createSession(
            sshClient.tmuxExecutor,
            name: sessionName,
            detached: true,
          );
        }
        if (!mounted || _isDisposed) return;
        await _refreshSessionTree();
        if (!mounted || _isDisposed) return;
      }

      // このセッションの履歴保持行数を設定する（グローバル -g ではなく対象
      // セッションのみ。ユーザーのtmuxサーバ全体の設定は書き換えない）。tmux仕様で
      // 既存ペインには遡らず、以後このセッションに作成されるペインに効く。
      // 値はユーザー設定 scrollbackLines に合わせる。ベストエフォート。
      try {
        final historyLimit = ref
            .read(settingsProvider)
            .scrollbackLines
            .clamp(200, 20000)
            .toInt();
        final client = sshNotifier.client;
        if (client != null) {
          await tmuxFacade.setHistoryLimit(
            client.tmuxExecutor,
            historyLimit,
            target: sessionName,
          );
        }
      } catch (_) {}

      // 6. アクティブセッション/ウィンドウ/ペインを設定
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

      // 6.1 ディープリンクまたは保存されたウィンドウ/ペイン位置を復元
      if (widget.deepLinkWindowName != null) {
        // ディープリンク: ウィンドウ名で検索
        final tmuxState = ref.read(tmuxProvider);
        final session = tmuxState.activeSession;
        if (session != null) {
          final targetName = widget.deepLinkWindowName!;
          // ウィンドウ名で検索（"index:name" 形式の名前部分にも対応）
          // inventory: LEGACY-0070
          TmuxWindow? window;
          for (final w in session.windows) {
            if (w.name == targetName || w.name.endsWith(':$targetName')) {
              window = w;
              break;
            }
          }
          if (window != null) {
            ref.read(tmuxProvider.notifier).setActiveWindow(window.index);

            // ペインインデックスが指定されている場合
            if (widget.deepLinkPaneIndex != null &&
                widget.deepLinkPaneIndex! < window.panes.length) {
              final pane = window.panes[widget.deepLinkPaneIndex!];
              ref.read(tmuxProvider.notifier).setActivePane(pane.id);
            }
          }
        }
      } else if (widget.lastWindowIndex != null) {
        // 通常の復元: インデックスで検索
        final tmuxState = ref.read(tmuxProvider);
        final session = tmuxState.activeSession;
        if (session != null) {
          // 指定されたウィンドウが存在するか確認
          final window = session.windows.firstWhere(
            (w) => w.index == widget.lastWindowIndex,
            orElse: () => session.windows.first,
          );
          ref.read(tmuxProvider.notifier).setActiveWindow(window.index);

          // ペインIDが指定されていて存在する場合は復元
          if (widget.lastPaneId != null) {
            final pane = window.panes.firstWhere(
              (p) => p.id == widget.lastPaneId,
              orElse: () => window.panes.first,
            );
            ref.read(tmuxProvider.notifier).setActivePane(pane.id);
          }
        }
      }

      // 7. TerminalDisplayProviderにペイン情報を通知（フォントサイズ計算用）
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        debugPrint(
          '[Terminal] Pane size: ${activePane.width}x${activePane.height}',
        );
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
        _viewNotifier.value = _viewNotifier.value.copyWith(
          paneWidth: activePane.width,
          paneHeight: activePane.height,
        );

        // ペインにフォーカスインを送信（Claude Code等のアプリがフォーカスを検知できるようにする）
        final client = sshNotifier.client;
        if (client != null) {
          await tmuxFacade.sendFocusIn(client.tmuxExecutor, activePane.id);
        }
      }

      // 7.5. 表示対象ソースを確定（tmux=毎呼出し currentTarget へ遅延委譲）
      // 既存の `_pollTargetPaneId ?? tmuxProvider.currentTarget`（L952/L1084）の
      // tmux 側をこのソースに一本化する（A9）。herdr 側は `_setupHerdrSession`
      // で `_HerdrTargetSource` を設定する。
      _targetSource = _TmuxTargetSource(
        () => ref.read(tmuxProvider.notifier).currentTarget,
      );

      // 8. 100msポーリング開始
      _startPolling();

      // 9. 5秒ごとにセッションツリーを更新
      _startTreeRefresh();

      if (!mounted) return;
      setState(() {
        _isConnecting = false;
      });

      // 10. 自動リサイズ: 接続直後、レイアウト確定後にtmuxウィンドウを画面幅へ合わせる
      if (ref.read(settingsProvider).isAutoResize) {
        // inventory: TERM-RESIZE-003
        _scheduleInitialAutoResize();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionError = e.toString();
      });
      // inventory: TERM-DIALOG-001
      _showErrorSnackBar(e.toString());
    }
  }

  /// backend 種別に応じてペイン内容読み取りを（再）生成する。
  ///
  /// 再接続時は [SshClient] が作り直されるため、新しいクライアントで
  /// 読み直す（古いクライアントを保持したままポーリングしない）。操作側
  /// （[_paneWriter]）も同じタイミングで再生成する。
  void _recreatePaneReader() {
    _recreatePaneWriter();
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;
    if (widget.paneContentReader != null) {
      _paneReader = widget.paneContentReader;
      _frameReader = null; // テスト注入 reader は content のみ（geometry は解決しない）
      // herdr: スナップショット読み取りは content reader とは独立に cache
      // （唯一の read chokepoint・A5 / A3改）経由にする。テスト注入 reader でも
      // cache を生成してエポック照合を有効にする（バックエンドは client 由来）。
      if (_backendKind == MultiplexerBackendKind.herdr) {
        final adapter = HerdrAdapter(sshClient);
        _herdrSnapshotCache = HerdrSnapshotCache(() => adapter);
      }
    } else if (_backendKind == MultiplexerBackendKind.herdr) {
      final adapter = HerdrAdapter(sshClient);
      _paneReader = HerdrPaneContentReader(adapter);
      // スナップショット読み取りは cache（唯一の read chokepoint・A5）経由に
      // する。adapter 差し替え（再接続・SSH client 再生成）は cache を作り直して追随。
      _herdrSnapshotCache = HerdrSnapshotCache(() => adapter);
      // content + geometry の合成（バグ1 根本対応: 表示層の backend 分岐と
      // 診断 getter の表示利用を除去）。cache.get() の TTL/single-flight/epoch
      // 契約を守る PaneLayoutResolver を使う。
      _frameReader = HerdrPaneFrameReader(
        adapter,
        HerdrPaneLayoutResolver(_herdrSnapshotCache!),
      );
    } else {
      _paneReader = TmuxPaneContentReader(sshClient.tmuxExecutor);
      _frameReader = null;
    }
  }

  /// backend 種別に応じてペイン操作（write 側抽象）を（再）生成する。
  ///
  /// 呼び出し側の明示（[TerminalScreen.readOnly]）・未接続・backend 未確定の
  /// ときは null（全 capability false 扱い = read-only）。T8 で `_Phase0PaneWriter`
  /// を廃止し、実実装（`TmuxPaneWriter` / `HerdrPaneWriter`）を生成する。
  /// herdr は Phase 2（T13）で capability がフリップされ mutation が解禁される
  /// （Q-01: 公開は 1 回のリリース・中間状態は出さない）。
  void _recreatePaneWriter() {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || widget.readOnly) {
      _paneWriter = null;
      return;
    }
    _paneWriter = switch (_backendKind) {
      // herdr: mutation 解禁（Phase 2・T13）。capability は PaneCapabilities 参照。
      MultiplexerBackendKind.herdr => HerdrPaneWriter(HerdrAdapter(sshClient)),
      // tmux: 既存 tmuxFacade をラップ（後方互換・コマンド文字列不変）。
      MultiplexerBackendKind.tmux =>
        TmuxPaneWriter(tmuxFacade, sshClient.tmuxExecutor),
      MultiplexerBackendKind.unknown => null,
    };
  }

  /// herdr の read-only セッションを設定する。
  ///
  /// 表示対象 pane を解決し、ライブポーリングを開始する。mutation 系の
  /// tmux セットアップ（バージョン確認・セッション作成・ツリー取得・
  /// フォーカス送信・自動リサイズ）は一切行わない。
  ///
  /// **stale tmuxProvider 対策（T9・R3）**: セッション確立の冒頭で
  /// `tmuxProvider.clear()` を呼び、接続残骸（activePaneId / currentTarget 等）
  /// を破棄する。これにより tmux の currentTarget が herdr 操作に混入する経路を
  /// 根絶する（mutation は必ず herdr の pane_id `wN:pN` を使用する実装規約）。
  Future<void> _setupHerdrSession(SshClient client) async {
    ref.read(tmuxProvider.notifier).clear();
    _recreatePaneReader();

    // 表示対象 pane を解決（直接指定 or スナップショットから）。
    // 直接指定（initialPaneId / lastPaneId）時はスナップショット解決を伴わず、
    // workspaceId / tabId は pane ID からの best-effort 導出にフォールバックする。
    final directId = widget.initialPaneId ?? widget.lastPaneId;
    final resolvedTarget = directId == null ? await _resolveHerdrPaneId() : null;
    final resolvedId = resolvedTarget?.paneId ?? directId;
    if (resolvedId == null) {
      // 診断: 要求条件（sessionId / label）とスナップショット状態を記録する。
      // 旧データ（sessionId: null）はラベル一致（先頭の同名 workspace）に
      // フォールバックするため、この経路は snapshot 取得失敗 or 空
      // （workspace/pane が 0 件）のときに到達する。
      _recordHerdrSwitchEvent(
        'initial resolve failed: no pane found '
        '(sessionId=${widget.sessionId ?? '<null>'}, '
        'label=${widget.sessionName ?? '<null>'}, directId=$directId)',
      );
      throw Exception('No herdr pane found for this workspace');
    }

    // 表示対象を固定 pane ID のソースとして確定（切替時は差し替え）
    _targetSource = _HerdrTargetSource(resolvedId);

    // 表示状態を通知（A9 / T11）: workspace は要求ラベル、tab はスナップショット
    // 解決済みの実値（直接指定時は pane ID から best-effort 導出）、pane は解決結果。
    _herdrDisplayNotifier.value = _HerdrDisplayData(
      workspaceLabel: widget.sessionName,
      workspaceId: resolvedTarget?.workspaceId ?? resolvedId.split(':').first,
      tabId: resolvedTarget?.tabId ?? _herdrTabIdFromPaneId(resolvedId),
      tabLabel: resolvedTarget?.tabLabel,
      paneId: resolvedId,
    );

    // ライブ表示を開始
    _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
    _hasInitialScrolled = false;
    _startPolling();
  }

  /// herdr スナップショットから表示対象の pane を解決する。
  ///
  /// スナップショット取得は [HerdrSnapshotCache]（唯一の read chokepoint・A5）
  /// 経由で行う。優先順の実体は [HerdrTargetResolver]（純粋関数）:
  /// [TerminalScreen.initialPaneId] / [TerminalScreen.lastPaneId] →
  /// [TerminalScreen.sessionName] に一致する workspace のフォーカス pane →
  /// 同 workspace の先頭 pane → 全体のフォーカス pane → 全体の先頭 pane。
  /// 戻り値は解決 pane と属する workspaceId / tabId の実値（[_HerdrResolvedTarget]）。
  Future<_HerdrResolvedTarget?> _resolveHerdrPaneId() async {
    final cache = _herdrSnapshotCache;
    if (cache == null) {
      // 診断: スナップショットキャッシュ未生成（backendKind が herdr でない /
      // SSH client 未接続 / paneContentReader 分岐で cache を作らなかった）とき。
      // 「No herdr pane found」の原因特定用。
      _recordHerdrSwitchEvent(
        'initial resolve failed: no snapshot cache '
        '(backendKind=$_backendKind, '
        'hasPaneContentReader=${widget.paneContentReader != null})',
      );
      return null;
    }
    final HerdrSnapshot snapshot;
    try {
      // 初回解決も cache 経由（A5）。初回はキャッシュが空のため実取得が 1 回走る。
      snapshot = await cache.get(force: true);
    } on HerdrCommandException catch (e) {
      // スナップショット取得失敗時は解決不能（呼び出し側でエラー表示）。
      // 診断: 例外種別・errorCode・exitCode・message（stderr 由来）を記録し、
      // server-down / stderr 混入 / パース失敗のどれが原因かを特定可能にする。
      _recordHerdrSwitchEvent(
        'initial resolve failed: snapshot fetch error '
        '(type=${e.runtimeType}, errorCode=${e.errorCode ?? '<null>'}, '
        'exitCode=${e.exitCode}, message=${e.message})',
      );
      return null;
    } on HerdrTargetNotFoundException catch (e) {
      // target 不在（pane/tab/workspace_not_found）も解決不能として扱う。
      // 診断: kind / errorCode を記録する。
      _recordHerdrSwitchEvent(
        'initial resolve failed: target not found in snapshot '
        '(type=${e.runtimeType}, kind=${e.kind}, '
        'errorCode=${e.errorCode ?? '<null>'}, '
        'exitCode=${e.exitCode}, message=${e.message})',
      );
      return null;
    } catch (e) {
      // SSH/transport 層の例外（SshConnectionError 等）は従来どおり伝播させる
      // （呼び出し側 `_connectAndSetup` の接続エラー UI に倒す）。挙動は変えず、
      // 原因特定用に種別のみ記録する。
      _recordHerdrSwitchEvent(
        'initial resolve failed: unexpected error '
        '(type=${e.runtimeType}, error=$e)',
      );
      rethrow;
    }

    return _resolveHerdrPaneIdFromSnapshot(snapshot);
  }

  /// [snapshot] から表示対象 pane を解決する（初回解決・A2 再解決で共通）。
  ///
  /// [preferredPaneId]（現在表示中の pane）を最優先し、続いて要求時の
  /// initialPaneId / lastPaneId、その後 workspace ベースの解決へフォールバックする。
  /// workspace 解決は [TerminalScreen.sessionId]（id 一致）→ [TerminalScreen.sessionName]
  /// （label 一致 → id 一致）→ 先頭 workspace の優先順。同名ラベル（herdr の
  /// "tmp" w3/w4）は sessionId で区別される。sessionId が snapshot に存在しない
  /// 場合のみ workspaceId を渡さず、ラベル一致にフォールバックする。
  /// 解決した pane の属する workspaceId / tabId は snapshot の [HerdrPane] から
  /// 実値を引き当てて [_HerdrResolvedTarget] として返す。
  _HerdrResolvedTarget? _resolveHerdrPaneIdFromSnapshot(
    HerdrSnapshot snapshot, {
    String? preferredPaneId,
  }) {
    // sessionId 優先: スナップショット内に一致する workspace がある場合のみ
    // workspaceId として resolver へ渡す（無ければラベル一致にフォールバック）。
    final requestedId = widget.sessionId;
    final workspaceId = (requestedId != null &&
            requestedId.isNotEmpty &&
            snapshot.workspaces.any((w) => w.id == requestedId))
        ? requestedId
        : null;
    final paneId = HerdrTargetResolver.resolve(
      snapshot,
      paneIds: [
        if (preferredPaneId != null) preferredPaneId,
        if (widget.initialPaneId != null) widget.initialPaneId!,
        if (widget.lastPaneId != null) widget.lastPaneId!,
      ],
      workspaceId: workspaceId,
      workspaceLabel: widget.sessionName,
    );
    if (paneId == null) {
      // 診断: resolver が pane を解決できなかった理由を記録する。
      // 「No herdr pane found」の原因特定用（workspace 0 件 / pane 0 件 /
      // label 不一致で先頭ワークスペースへもフォールバックできない場合）。
      _recordHerdrSwitchEvent(
        'resolve failed: no pane in snapshot '
        '(workspaces=${snapshot.workspaces.length}, '
        'panes=${snapshot.panes.length}, '
        'sessionId=${widget.sessionId ?? '<null>'}, '
        'label=${widget.sessionName ?? '<null>'}, '
        'requestedWorkspaceId=${workspaceId ?? '<null>'})',
      );
      return null;
    }
    final pane = snapshot.panes.where((p) => p.id == paneId).firstOrNull;
    // M-4: tab の表示名（tab.label ?? tab.id 相当）も snapshot 実値で確定する。
    final tab = pane?.tabId == null
        ? null
        : snapshot.tabs.where((t) => t.id == pane!.tabId).firstOrNull;
    return _HerdrResolvedTarget(
      paneId: paneId,
      workspaceId: pane?.workspaceId,
      tabId: pane?.tabId,
      tabLabel: tab?.label,
    );
  }

  /// セッションツリー全体を取得して更新
  Future<void> _refreshSessionTree() async {
    if (_isDisposed) {
      return;
    }
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      return;
    }

    try {
      final sessions = await tmuxFacade.listAllPanes(sshClient.tmuxExecutor);
      if (!mounted || _isDisposed) return;
      ref.read(tmuxProvider.notifier).updateSessions(sessions);
      // アクティブセッションのウィンドウ数を provider に同期
      // （ホーム画面と接続カードのウィンドウ数カウンタが作成/削除後も追従する）
      final refreshedSession = ref.read(tmuxProvider).activeSession;
      if (refreshedSession != null) {
        ref
            .read(activeSessionsProvider.notifier)
            .updateWindowCount(
              widget.connectionId,
              refreshedSession.name,
              refreshedSession.windows.length,
              sessionId: refreshedSession.id,
            );
      }
    } catch (_) {
      // ツリー更新エラーは静かに無視（次回ポーリングで再試行）
    }
  }

  /// 10秒ごとにセッションツリーを更新
  void _startTreeRefresh() {
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = Timer.periodic(
      // inventory: LEGACY-0071
      const Duration(seconds: 10),
      (_) {
        // ポーリング中はSSH競合を回避するためスキップ
        if (!_isPolling) {
          _refreshSessionTree();
        }
      },
    );
  }

  /// 適応型ポーリングでcapture-paneを実行してターミナル内容を更新
  ///
  /// コンテンツの変化頻度に応じてポーリング間隔を動的に調整:
  /// - 高頻度更新時（htop等）: 50ms
  /// - 通常時: 100ms
  /// - アイドル時: 500ms
  void _startPolling() {
    _pollTimer?.cancel();
    // inventory: TERM-LIFE-015
    _scheduleNextPoll();
  }

  /// 次のポーリングをスケジュール
  void _scheduleNextPoll() {
    if (_isDisposed || _pollingSuspended) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(
      Duration(milliseconds: _currentPollingInterval),
      () async {
        // inventory: TERM-LIFE-018
        await _pollPaneContent();
        _scheduleNextPoll();
      },
    );
  }

  // inventory: TERM-LIFE-016
  /// キー入力後にポーリングを即座にブースト（アイドル時の応答性改善）
  void _boostPolling() {
    // 既に最小間隔なら Timer 再生成は不要（高速連打時の churn を回避）
    if (_currentPollingInterval == _minPollingInterval) return;
    _currentPollingInterval = _minPollingInterval;
    _pollTimer?.cancel();
    _scheduleNextPoll();
  }

  // inventory: TERM-LIFE-017
  /// ポーリング間隔を更新
  void _updatePollingInterval() {
    final recommended = AdaptivePollingInterval.calculateInterval(
      _unchangedPolls,
    );
    // tmux copy-mode 検出中はポーリング間隔の上限を500msに制限
    final maxInterval = _scrollModeSource == ScrollModeSource.tmux
        ? 500
        : _maxPollingInterval;
    _currentPollingInterval = recommended.clamp(
      _minPollingInterval,
      maxInterval,
    );
  }

  /// ペイン内容をポーリング取得
  Future<void> _pollPaneContent() async {
    if (_isPolling || _isDisposed) return; // 前回のポーリングがまだ実行中 or disposed
    _isPolling = true;

    try {
      final sshNotifier = ref.read(sshProvider.notifier);
      final sshClient = sshNotifier.client;

      // 接続が切れている場合は自動再接続を試みる
      if (sshClient == null || !sshClient.isConnected) {
        // すでに再接続中でなければ再接続を開始
        final currentState = ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          // inventory: TERM-LIFE-021
          _attemptReconnect();
        }
        _isPolling = false;
        return;
      }

      // ペイン内容読み取りからターゲットを取得
      final paneId = _targetSource?.currentPaneId;
      final reader = _paneReader;
      final frameReader = _frameReader;
      if (paneId == null || reader == null) {
        _isPolling = false;
        return;
      }

      // A3改: read 開始前に表示対象同一性（cache epoch + pane ID）を記録。
      // 完了時（下記）に照合し、await 中に切替・再解決・再接続があれば破棄する。
      final herdrIdentity = _captureHerdrTarget();

      final startTime = DateTime.now();

      // ペイン表示フレームを取得する。herdr は content + geometry を
      // PaneFrameReader が合成し（バグ1 根本対応: 表示層の backend 分岐と
      // 診断 getter の表示利用を除去）、tmux / テスト注入 reader は従来の
      // PaneContentReader を使う。ライブポーリングは read intent（LiveTail）で
      // 要求する（バグ4 根本対応: 行数の符号・大小による暗黙の意味判定を廃止）。
      final snapshot = frameReader != null
          ? (await frameReader.read(PaneFrameRequest(
              PaneReadRequest.live(paneId: paneId),
            ))).toSnapshot()
          : await reader.readPane(PaneReadRequest.live(paneId: paneId));

      final endTime = DateTime.now();

      if (!mounted || _isDisposed) return;

      // A3改: await 完了後に表示対象を照合。不一致（await 中に切替・再解決・
      // 再接続が発生）ならこの結果を破棄し、次回ポーリングに任せる。
      if (!_isCurrentHerdrTarget(herdrIdentity)) return;

      // カーソル位置とペインサイズを更新
      // tmux は snapshot（poll）経由で geometry を得る。herdr は PaneFrameReader
      // が layout から合成済み。zoom 時は pane rect が非 zoom 値のまま
      // （herdr_models.dart）のため layout.area（タブ全面）を解決済み。
      // rect が取得できない場合は従来どおり geometry 無しのままスキップし、
      // 既定の 80x24（spec.md:75）に落ちる。
      final geometry = snapshot.geometry;
      final w = geometry?.width ?? 0;
      final h = geometry?.height ?? 0;
      if (w > 0 && h > 0) {
        if (w != _viewNotifier.value.paneWidth ||
            h != _viewNotifier.value.paneHeight) {
          _viewNotifier.value = _viewNotifier.value.copyWith(
            paneWidth: w,
            paneHeight: h,
          );
          // フォントサイズ再計算のために通知
          final currentActivePane = ref.read(tmuxProvider).activePane;
          if (currentActivePane != null) {
            ref
                .read(terminalDisplayProvider.notifier)
                .updatePane(currentActivePane.copyWith(width: w, height: h));
          }
        }

        // inventory: LEGACY-0079
        final activePaneId = ref.read(tmuxProvider).activePaneId;
        if (activePaneId != null) {
          ref
              .read(tmuxProvider.notifier)
              .updateCursorPosition(
                activePaneId,
                snapshot.cursorX,
                snapshot.cursorY,
              );
        }
      }

      final processedOutput = snapshot.content;
      final paneModeOutput = snapshot.paneMode;

      // レイテンシは専用ValueNotifierで更新（変化時のみインジケーターを再描画）。
      // コンテンツ用_viewNotifierには含めないことで、ping揺れによる
      // ターミナル本文（AnsiTextView）の無駄な再描画を排除する。
      final latency = endTime.difference(startTime).inMilliseconds;
      if (mounted && !_isDisposed) {
        _latencyNotifier.value = latency;
      }

      // 適応型ポーリング: 内容変化の頻度を毎ポーリングで記録（アイドル時にバックオフ）
      if (processedOutput == _lastPolledContent) {
        _unchangedPolls++;
      } else {
        _unchangedPolls = 0;
        _lastPolledContent = processedOutput;
      }

      // コンテンツ差分があれば更新（スロットリング適用）
      final currentView = _viewNotifier.value;
      if (processedOutput != currentView.content) {
        // 手動スクロールモード中は更新をバッファリングして選択状態を保持
        // tmux copy-mode中はcapture-paneがスクロール位置の内容を返すためリアルタイム表示
        if (_terminalMode == TerminalMode.scroll &&
            _scrollModeSource == ScrollModeSource.manual) {
          _bufferedContent = processedOutput;
          _hasBufferedUpdate = true;
          // A3改: バッファ時点の表示対象同一性を併記（適用時に照合）。
          _bufferedTargetIdentity = herdrIdentity;
        } else {
          _scheduleUpdate(processedOutput, targetIdentity: herdrIdentity);
        }
      }

      // tmux copy-mode 検出による自動モード切替
      if (mounted && !_isDisposed) {
        final paneMode = paneModeOutput.trim();
        final isTmuxCopyMode = paneMode.isNotEmpty;

        if (isTmuxCopyMode && _scrollModeSource == ScrollModeSource.none) {
          // tmux copy-mode に入った → スクロールモードに自動切替
          setState(() {
            _terminalMode = TerminalMode.scroll;
            _scrollModeSource = ScrollModeSource.tmux;
          });
        } else if (!isTmuxCopyMode &&
            _scrollModeSource == ScrollModeSource.tmux) {
          // tmux copy-mode が終了した → 自動で通常モードに復帰
          setState(() {
            _terminalMode = TerminalMode.normal;
            _scrollModeSource = ScrollModeSource.none;
          });
          // inventory: TERM-LIFE-019
          _applyBufferedUpdate();
        }
      }

      // 適応型ポーリング間隔を更新
      _updatePollingInterval();
    } catch (e) {
      // A2: herdr は例外種別で分岐（target-not-found 再解決 / server-down
      // 停止+通知 / その他再接続）。tmux パスは従来挙動を維持する（回帰防止）。
      if (_backendKind == MultiplexerBackendKind.herdr) {
        await _handleHerdrPollError(e);
      } else {
        // 通信エラーの場合は自動再接続を試みる
        if (!_isDisposed) {
          final currentState = ref.read(sshProvider);
          if (!currentState.isReconnecting) {
            _attemptReconnect();
          }
        }
      }
    } finally {
      _isPolling = false;
    }
  }

  /// herdr ポーリング例外の種別分岐（A2 / R1）。
  ///
  /// 1. target-not-found → スナップショット強制再取得 → 再解決（再接続しない）
  /// 2. server-down → ポーリング停止 + SnackBar + キャッシュ失効
  /// 3. その他 → 従来どおり自動再接続を試みる
  ///
  /// A8 監視（SDK 送信なし）: 種別と再解決の成否をリングバッファへ記録する。
  Future<void> _handleHerdrPollError(Object e) async {
    if (isHerdrTargetNotFound(e)) {
      _recordHerdrSwitchEvent('target-not-found detected (${e.runtimeType})');
      await _handleHerdrTargetNotFound();
    } else if (isServerDownException(e)) {
      _recordHerdrSwitchEvent('server-down detected (${e.runtimeType})');
      await _handleHerdrServerDown(e);
    } else {
      _recordHerdrSwitchEvent('poll error (${e.runtimeType})');
      // その他の通信エラーは従来どおり自動再接続を試みる
      if (!_isDisposed) {
        final currentState = ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          _attemptReconnect();
        }
      }
    }
  }

  /// target-not-found からの再解決とエスカレーション（A2）。
  ///
  /// [_fetchHerdrSessions(force: true)] でスナップショットを強制再取得し、
  /// 共通 domain ツリーから表示対象を再解決する（T5: 取得とエラー分類は
  /// 共有ヘルパーに集約）。
  /// - 復旧したら [_switchHerdrTarget] で表示継続（監視: re-resolve succeeded）
  /// - 再解決でも不在なら再接続せず終端（ポーリング停止 + SnackBar・
  ///   監視: re-resolve failed）
  Future<void> _handleHerdrTargetNotFound() async {
    final sessions = await _fetchHerdrSessions(
      force: true,
      eventLabel: 're-resolve failed',
      isTerminal: true,
    );
    if (sessions == null || !mounted || _isDisposed) return;

    final currentPaneId = _targetSource?.currentPaneId;
    final resolved = _resolveHerdrTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      // 終端: 再解決でも対象不在 → 再接続しない（R1）
      _recordHerdrSwitchEvent('re-resolve failed: target missing');
      _notifyHerdrTargetLost();
      return;
    }

    _recordHerdrSwitchEvent('re-resolve succeeded -> ${resolved.paneId}');
    if (resolved.paneId == currentPaneId) {
      // 同じ pane なら切替コミットは不要（表示継続）
      return;
    }
    // 再解決で確定した tabId / workspaceId / tabLabel（snapshot 実値）を表示状態へ伝播する
    _switchHerdrTarget(
      resolved.paneId,
      workspaceId: resolved.workspaceId,
      tabId: resolved.tabId,
      tabLabel: resolved.tabLabel,
    );
  }

  /// 再接続後のターゲット再解決（T9a）。
  ///
  /// 再接続で [SshClient] が作り直されたため、[_recreatePaneReader] が生成した
  /// 新しい [HerdrSnapshotCache]（新 adapter）経由でスナップショットを強制取得し
  /// （[_fetchHerdrSessions(force: true)]）、共通 domain ツリーから表示対象を
  /// 再解決する。adapter 差し替えの検出（`identical`）とエポック++ は cache
  /// 内在で自動（A3改）。await 中に古い cache を捕まえた read は
  /// [_isCurrentHerdrTarget] の同一性照合で破棄される。
  ///
  /// - 同じ pane に解決 → 表示継続（切替コミットなし）
  /// - 別 pane に解決 → [_switchHerdrTarget] で表示更新
  /// - 再解決不能（全 workspace 消滅等）→ 終端通知（再接続しない・R1）
  ///
  /// 戻り値: 表示を継続できる場合は true。server-down / 終端（再解決不能）で
  /// ポーリング停止 + 通知へ倒した場合は false。
  Future<bool> _reResolveHerdrTargetAfterReconnect() async {
    final sessions = await _fetchHerdrSessions(
      force: true,
      eventLabel: 're-resolve failed after reconnect',
      isTerminal: true,
    );
    if (sessions == null || !mounted || _isDisposed) return false;

    final currentPaneId = _targetSource?.currentPaneId;
    final resolved = _resolveHerdrTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      // 終端: 再解決でも対象不在 → 再接続しない（R1）
      _recordHerdrSwitchEvent(
        're-resolve failed after reconnect: target missing',
      );
      _notifyHerdrTargetLost();
      return false;
    }

    _recordHerdrSwitchEvent('re-resolve after reconnect -> ${resolved.paneId}');
    if (resolved.paneId == currentPaneId) {
      // 同じ pane なら切替コミットは不要（表示継続）
      return true;
    }
    // 再解決で確定した tabId / workspaceId / tabLabel（snapshot 実値）を表示状態へ伝播する
    _switchHerdrTarget(
      resolved.paneId,
      workspaceId: resolved.workspaceId,
      tabId: resolved.tabId,
      tabLabel: resolved.tabLabel,
    );
    return true;
  }

  /// herdr スナップショット取得の共有ヘルパー（T5 / M-3）。
  ///
  /// [HerdrSnapshotCache.get()]（唯一の read chokepoint・A5）→
  /// `toDomainSessions()` を集約し、共通 domain ツリー（[MultiplexerSession]）
  /// を返す。エラー分類（[_recordHerdrSwitchEvent]・SnackBar 表示・
  /// server-down ルーティング）もここで行い、呼び出し側は戻り値 null で
  /// 「取得失敗」を判定する。
  ///
  /// [eventLabel] は取得失敗時に記録する `[HerdrSwitch]` イベントの説明部分
  /// （例: 're-resolve failed' / 'selector snapshot'）。[isTerminal] が true の
  /// 呼び出し（再解決系）では server-down 以外の失敗を [_notifyHerdrTargetLost]
  /// （終端通知）に倒し、false（セレクタ系）では SnackBar 表示に倒す。
  Future<List<MultiplexerSession>?> _fetchHerdrSessions({
    bool force = false,
    required String eventLabel,
    required bool isTerminal,
  }) async {
    final cache = _herdrSnapshotCache;
    if (cache == null) {
      _recordHerdrSwitchEvent('$eventLabel: no snapshot cache');
      if (isTerminal) _notifyHerdrTargetLost();
      return null;
    }

    final HerdrSnapshot snapshot;
    try {
      snapshot = await cache.get(force: force);
    } catch (e) {
      if (!mounted || _isDisposed) return null;
      if (isServerDownException(e)) {
        _recordHerdrSwitchEvent('server-down detected (${e.runtimeType})');
        await _handleHerdrServerDown(e);
      } else if (isTerminal) {
        _recordHerdrSwitchEvent('$eventLabel: snapshot fetch error');
        _notifyHerdrTargetLost();
      } else {
        _recordHerdrSwitchEvent(
          '$eventLabel: snapshot fetch error (${e.runtimeType})',
        );
        _showHerdrErrorSnackBar('Failed to load herdr tree: $e');
      }
      return null;
    }
    return snapshot.toDomainSessions();
  }

  // inventory: TERM-MUT-SYNC-001
  /// **H5/T18 単一経路**: mutation 成功後のツリー同期。
  ///
  /// 全 mutation（split / close / zoom / resize / rename / create / focus /
  /// workspace・tab CRUD）の成功後に呼ぶ**唯一の同期経路**（呼び漏れ・不整合
  /// 防止）。操作ごとに別個の同期ロジックを書かない。
  ///
  /// 1. [HerdrSnapshotCache.get(force: true)] でスナップショットを強制再取得
  ///    （エポック++。adapter 差し替えは既存 `identical` 検出に委譲・A3改。
  ///    split/create 等の layout なし応答（T0 実測）も force 再取得で反映）
  /// 2. [_resolveHerdrTargetFromSessions]（[HerdrTargetResolver] と等価な決定順）
  ///    でターゲットを再解決（現在表示中の pane を [preferredPaneId] で最優先）
  /// 3. ターゲット変化時のみ [_switchHerdrTarget] で表示を単一コミット
  ///    （snapshot 実値の workspaceId / tabId / tabLabel を伝播）
  /// 4. [_boostPolling] で即時反映
  ///
  /// 破壊的操作（close / workspace close）でターゲットが消滅した場合は再解決で
  /// 別 pane に移る（連鎖 close は確認済みの上で遷移）。再解決不能（全 workspace
  /// 消滅）は [_notifyHerdrTargetLost] で終端通知（再接続しない・R1）。server-down
  /// は [_fetchHerdrSessions] の既存ルーティング（ポーリング停止 + 通知 +
  /// キャッシュ失効）に倒れる。
  ///
  /// ポーリング（`pane read`）は既存のまま継続する（TTL 5s + force + エポック
  /// 照合で snapshot と表示の整合を担保・A3改）。
  ///
  /// 戻り値: 表示を継続できる（同一 pane 表示継続 or 切替成功）場合は true。
  /// server-down / 終端（再解決不能）でポーリング停止 + 通知へ倒した場合は false。
  Future<bool> _syncAfterHerdrMutation({String eventLabel = 'mutation sync'}) async {
    // 1. force 再取得（エポック++。server-down は既存ルーティングへ）。
    final sessions = await _fetchHerdrSessions(
      force: true,
      eventLabel: eventLabel,
      isTerminal: true,
    );
    if (sessions == null || !mounted || _isDisposed) return false;

    // 2. ターゲット再解決（現在表示中の pane を最優先・HerdrTargetResolver 等価）。
    final currentPaneId = _targetSource?.currentPaneId;
    final resolved = _resolveHerdrTargetFromSessions(
      sessions,
      preferredPaneId: currentPaneId,
    );
    if (resolved == null) {
      // 終端: 破壊的操作で全 workspace が消滅した等 → 再接続しない（R1）。
      _recordHerdrSwitchEvent('$eventLabel: no target remains');
      _notifyHerdrTargetLost();
      return false;
    }

    // 3. ターゲット変化時のみ切替コミット（同一なら表示継続・チラつき防止）。
    if (resolved.paneId != currentPaneId) {
      _recordHerdrSwitchEvent('$eventLabel -> ${resolved.paneId}');
      _switchHerdrTarget(
        resolved.paneId,
        workspaceId: resolved.workspaceId,
        tabId: resolved.tabId,
        tabLabel: resolved.tabLabel,
      );
    }

    // 4. 即時反映（切替コミット内でも boost されるが、同一 pane 時も反映する）。
    _boostPolling();
    return true;
  }

  /// 共通 domain ツリー（[_fetchHerdrSessions] の成果物）から表示対象 pane を
  /// 再解決する（T5）。
  ///
  /// 優先順は [HerdrTargetResolver]（snapshot 版・決定層）と等価に保つ:
  /// [preferredPaneId] → initialPaneId → lastPaneId → workspace ラベル一致
  /// （label → id）→ workspace のフォーカス tab → 先頭 tab → tab 内フォーカス
  /// pane → 先頭 pane → workspace 内フォーカス pane → 先頭 pane → 全体フォーカス
  /// pane → 先頭 pane。解決した pane の属する workspace / tab の実値
  /// （session.id / window.id / window.name）を [_HerdrResolvedTarget] で返す。
  _HerdrResolvedTarget? _resolveHerdrTargetFromSessions(
    List<MultiplexerSession> sessions, {
    String? preferredPaneId,
  }) {
    // 1. 直接 pane 指定（preferredPaneId → initialPaneId → lastPaneId）
    for (final id in [
      preferredPaneId,
      widget.initialPaneId,
      widget.lastPaneId,
    ]) {
      if (id == null) continue;
      final pane = _findHerdrPane(sessions, id);
      if (pane != null) return _herdrResolvedTargetOf(sessions, pane);
    }

    // 2. workspace 決定: sessionId（id 一致）→ sessionName（label 一致 → id 一致）
    //    → 先頭。同名ラベル（herdr の "tmp" w3/w4）は sessionId で区別する。
    MultiplexerSession? workspace;
    final requestedId = widget.sessionId;
    if (requestedId != null && requestedId.isNotEmpty) {
      for (final session in sessions) {
        if (session.id == requestedId) {
          workspace = session;
          break;
        }
      }
    }
    if (workspace == null) {
      final label = widget.sessionName;
      if (label != null && label.isNotEmpty) {
        for (final session in sessions) {
          if (session.name == label || session.id == label) {
            workspace = session;
            break;
          }
        }
      }
    }
    workspace ??= sessions.firstOrNull;
    if (workspace == null) return null;

    // 3-4. tab（フォーカス → 先頭）→ tab 内 pane（フォーカス → 先頭）
    final focusedTab = workspace.windows.where((w) => w.active).firstOrNull;
    final tab = focusedTab ?? workspace.windows.firstOrNull;
    if (tab != null) {
      final focusedPane = tab.panes.where((p) => p.active).firstOrNull;
      if (focusedPane != null) return _herdrResolvedTargetOf(sessions, focusedPane);
      if (tab.panes.isNotEmpty) return _herdrResolvedTargetOf(sessions, tab.panes.first);
    }

    // 5. workspace 内フォールバック（tab 解決不能・tab 内が空のとき）
    final workspacePanes = [for (final w in workspace.windows) ...w.panes];
    final workspaceFocused = workspacePanes.where((p) => p.active).firstOrNull;
    if (workspaceFocused != null) return _herdrResolvedTargetOf(sessions, workspaceFocused);
    if (workspacePanes.isNotEmpty) return _herdrResolvedTargetOf(sessions, workspacePanes.first);

    // 6. 全体フォールバック
    final allPanes = [
      for (final s in sessions)
        for (final w in s.windows)
          ...w.panes,
    ];
    final globalFocused = allPanes.where((p) => p.active).firstOrNull;
    if (globalFocused != null) return _herdrResolvedTargetOf(sessions, globalFocused);
    if (allPanes.isNotEmpty) return _herdrResolvedTargetOf(sessions, allPanes.first);
    return null;
  }

  /// [sessions] から [paneId] に一致する [MultiplexerPane] を引き当てる。
  MultiplexerPane? _findHerdrPane(
    List<MultiplexerSession> sessions,
    String paneId,
  ) {
    for (final session in sessions) {
      for (final window in session.windows) {
        for (final pane in window.panes) {
          if (pane.id == paneId) return pane;
        }
      }
    }
    return null;
  }

  /// [pane] の属する workspace / tab の実値を [_HerdrResolvedTarget] として返す。
  ///
  /// session.id（workspace ID）/ window.id（tab ID）/ window.name
  /// （`tab.label ?? tab.id` 相当・M-4）を親ツリーから引き当てる。
  /// 引き当てできない場合は pane ID からの best-effort 導出へフォールバックする。
  _HerdrResolvedTarget _herdrResolvedTargetOf(
    List<MultiplexerSession> sessions,
    MultiplexerPane pane,
  ) {
    for (final session in sessions) {
      for (final window in session.windows) {
        if (window.panes.any((p) => p.id == pane.id)) {
          return _HerdrResolvedTarget(
            paneId: pane.id,
            workspaceId: session.id ?? pane.id.split(':').first,
            tabId: window.id ?? _herdrTabIdFromPaneId(pane.id),
            tabLabel: window.name,
          );
        }
      }
    }
    return _HerdrResolvedTarget(
      paneId: pane.id,
      workspaceId: pane.id.split(':').first,
      tabId: _herdrTabIdFromPaneId(pane.id),
    );
  }

  /// server-down からのエスカレーション（A2 / R1）。
  ///
  /// ポーリングを停止し（再接続ループ防止）、キャッシュを失効させ、SnackBar
  /// で通知する。Retry は「再接続」ではなく「再試行」（ポーリング再開）。
  Future<void> _handleHerdrServerDown(Object e) async {
    _suspendPollingAfterError();
    _herdrSnapshotCache?.invalidate();
    if (mounted && !_isDisposed) {
      _showHerdrErrorSnackBar('Herdr server is not responding: $e');
    }
  }

  /// 終端エラー（再解決でも対象不在）を通知する。再接続はしない（A2 / R1）。
  void _notifyHerdrTargetLost() {
    if (!mounted || _isDisposed) return;
    _suspendPollingAfterError();
    _showHerdrErrorSnackBar('Herdr target pane not found');
  }

  /// ポーリングを停止し、[_scheduleNextPoll] による再スケジュールを抑止する。
  void _suspendPollingAfterError() {
    _pollingSuspended = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 停止したポーリングを再開する（SnackBar の Retry アクション = 再試行）。
  void _resumePollingAfterError() {
    if (!mounted || _isDisposed) return;
    _pollingSuspended = false;
    _startPolling();
  }

  /// herdr 用のエラー SnackBar（tmux の `_showErrorSnackBar` を踏襲）。
  ///
  /// Retry は「再接続」ではなく「再試行」（再解決 / ポーリング再開）を意味する。
  void _showHerdrErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _resumePollingAfterError,
        ),
      ),
    );
  }

  /// T19/S4: herdr mutation の結果 SnackBar（tmux の `_showErrorSnackBar` を
  /// 踏襲したプレーン通知。分類別の文言は呼び出し側が組み立てる）。
  void _showHerdrMutationSnackBar(String message) {
    if (!mounted || _isDisposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// T19/S4: target-not-found の通知（SnackBar「対象が消えました。再同期しました」）。
  void _showHerdrTargetNotFoundSnackBar() {
    _showHerdrMutationSnackBar('対象が消えました。再同期しました');
  }

  /// T19/S4: 非対応キー（`invalid_key`）の防御的通知。
  ///
  /// Q-07 の全キー送信経路（[PaneKeyMap]）により通常は発生しない（R9）。
  void _showHerdrInvalidKeySnackBar() {
    _showHerdrMutationSnackBar('このキーは herdr で送信できませんでした');
  }

  /// T19/S4: 方向なし / no-op（soft 失敗）の情報通知。
  ///
  /// [PaneOperationNoopException.reason] に応じて文言を出し分ける:
  /// `no_neighbor`（隣接 pane なし）→「その方向に pane はありません」/
  /// `unchanged`（分割境界外 resize）→「分割境界のため変更なし」。
  void _showHerdrMutationNoopSnackBar(PaneOperationNoopException e) {
    final message = switch (e.reason) {
      'no_neighbor' => 'その方向に pane はありません',
      'unchanged' => '分割境界のため変更なし',
      _ => '操作は実行されましたが状態は変わりませんでした',
    };
    _showHerdrMutationSnackBar(message);
  }

  /// T19/S4: herdr mutation の失敗を分類して通知・後続処理を行う。
  ///
  /// [PaneWriter] 経由の mutation 呼び出しを try-catch でラップし、この分類に
  /// 集約する（S4 分類表）:
  ///
  /// | 分類 | 判定 | 通知 | 後続処理 |
  /// |---|---|---|---|
  /// | target-not-found | [isHerdrTargetNotFound]（`pane_not_found` 等） | 「対象が消えました。再同期しました」 | [HerdrSnapshotCache.get(force:true)] → 再解決（[_syncAfterHerdrMutation]） |
  /// | 非対応キー（防御的） | [isHerdrInvalidKey]（`invalid_key`） | 「このキーは herdr で送信できませんでした」 | なし（Q-07 の全キー送信経路のフォールバック・R9） |
  /// | 方向なし / no-op | [PaneOperationNoopException]（`no_neighbor` / `changed:false`） | 情報 SnackBar | なし |
  /// | server-down | [isServerDownException] | 既存（ポーリング停止 + 通知 + キャッシュ失効） | [_handleHerdrServerDown] |
  /// | その他通信エラー | — | 既存エラー SnackBar | 必要時は [_attemptReconnect] |
  Future<void> _handleHerdrMutationError(
    Object e, {
    required String operationLabel,
  }) async {
    if (!mounted || _isDisposed) return;
    if (isHerdrTargetNotFound(e)) {
      // 対象が消えた（他端末での close 等）→ 通知 + 単一経路で再同期。
      _recordHerdrSwitchEvent(
        'mutation $operationLabel: target-not-found (${e.runtimeType})',
      );
      _showHerdrTargetNotFoundSnackBar();
      await _syncAfterHerdrMutation(eventLabel: '$operationLabel re-sync');
    } else if (isHerdrInvalidKey(e)) {
      // 防御的（通常は発生しない・R9）。
      _recordHerdrSwitchEvent(
        'mutation $operationLabel: invalid_key (${e.runtimeType})',
      );
      _showHerdrInvalidKeySnackBar();
    } else if (e is PaneOperationNoopException) {
      // 方向なし / no-op（soft 失敗・情報通知）。
      _recordHerdrSwitchEvent(
        'mutation $operationLabel: no-op (reason: ${e.reason ?? '<null>'})',
      );
      _showHerdrMutationNoopSnackBar(e);
    } else if (isServerDownException(e)) {
      // server-down: 既存どおりポーリング停止 + 通知 + キャッシュ失効。
      _recordHerdrSwitchEvent(
        'mutation $operationLabel: server-down (${e.runtimeType})',
      );
      await _handleHerdrServerDown(e);
    } else {
      // その他通信エラー: 接続断系は既存の自動再接続、それ以外はエラー通知。
      _recordHerdrSwitchEvent(
        'mutation $operationLabel: error (${e.runtimeType})',
      );
      if (e is SshConnectionError) {
        final currentState = ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          _attemptReconnect();
        }
      } else {
        _showHerdrMutationSnackBar('$operationLabel failed: $e');
      }
    }
  }

  /// バッファリングされた更新を適用（スクロールモード終了時に呼び出し）
  void _applyBufferedUpdate() {
    if (_hasBufferedUpdate) {
      // A3改: バッファ時点の表示対象同一性を引き継ぎ、`_applyUpdate` で照合する。
      _scheduleUpdate(
        _bufferedContent,
        targetIdentity: _bufferedTargetIdentity,
      );
      _hasBufferedUpdate = false;
      _bufferedContent = '';
      _bufferedTargetIdentity = null;
    }
  }

  // inventory: TERM-LIFE-020
  /// スクロール&選択モード開始時に履歴を一度だけ取得して表示する。
  /// ライブポーリングは軽量な直近行のままなので性能は落ちない。深い履歴は
  /// ポーリングとは別のexecチャネルで取得し、ホットパスに影響しない。
  Future<void> _loadHistoryForScroll({bool preservePosition = false}) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;
    final paneId = _targetSource?.currentPaneId;
    final reader = _paneReader;
    final frameReader = _frameReader;
    if (paneId == null || reader == null) return;
    // A3改: 深い履歴 read 開始前に表示対象同一性を記録（完了時に照合）。
    final herdrIdentity = _captureHerdrTarget();
    try {
      // スクロールバック全体を一括取得（read intent = Scrollback で要求する）。
      // 行数は backend ポリシー（PaneHistoryPolicy）が解決する（バグ4 根本対応:
      // 設定解決を表示層から分離・魔法数 -100000/-120 の暗黙判定を廃止）。
      final policy = PaneHistoryPolicyResolver.forBackend(
        _backendKind,
        configuredScrollbackLines: ref.read(settingsProvider).scrollbackLines,
      );
      final request = PaneReadRequest.scrollback(
        paneId: paneId,
        maxLines: policy.scrollbackLimit,
      );
      final snapshot = frameReader != null
          ? (await frameReader.read(PaneFrameRequest(request))).toSnapshot()
          : await reader.readPane(request);
      if (!mounted || _isDisposed) return;
      // A3改: await 完了後に表示対象を照合。不一致（await 中に切替・再解決・
      // 再接続が発生）なら破棄し、ライブ表示のままにする。
      if (!_isCurrentHerdrTarget(herdrIdentity)) return;
      if (_terminalMode != TerminalMode.scroll) return;
      final content = snapshot.content;
      if (preservePosition) {
        // スクロール上端からの自動ロード: プリペンドされた行数ぶん位置を補正し、
        // 直前に最上部だった行を同じ位置に留める（真ん中へ飛ばないように）。
        // 行数は実際のコンテンツ文字列から算出（ウィジェット側キャッシュに依存しない）。
        final oldContent = _viewNotifier.value.content;
        final oldLines = oldContent.isEmpty
            ? 0
            : '\n'.allMatches(oldContent).length + 1;
        final newLines = content.isEmpty
            ? 0
            : '\n'.allMatches(content).length + 1;
        final prepended = newLines - oldLines;
        _viewNotifier.value = _viewNotifier.value.copyWith(content: content);
        if (prepended > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isDisposed) {
              _ansiTextViewKey.currentState?.jumpToLineFromTop(prepended);
            }
          });
        }
      } else {
        _viewNotifier.value = _viewNotifier.value.copyWith(content: content);
        // ライブ位置（末尾）に合わせ、そこから上へ履歴を遡れるようにする
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposed) {
            _ansiTextViewKey.currentState?.scrollToBottom();
          }
        });
      }
    } catch (_) {
      // 取得失敗時は直近行のライブ表示のまま
    }
  }

  /// フレームスキップを考慮して更新をスケジュール
  ///
  /// 高頻度更新時（htop等）に毎フレーム更新しないようスロットリングを行う。
  /// 16ms（約60fps）以内の連続更新は次フレームに延期される。
  void _scheduleUpdate(String content, {_HerdrTargetIdentity? targetIdentity}) {
    _pendingContent = content;
    // A3改: このコンテンツの表示対象同一性を併記し、`_applyUpdate` で照合する。
    _pendingTargetIdentity = targetIdentity;

    // すでに更新がスケジュール済みなら何もしない
    if (_pendingUpdate) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastFrameTime);

    if (elapsed >= _minFrameInterval) {
      // 十分な時間が経過しているので即時更新
      _applyUpdate();
    } else {
      // フレームスキップ: 次のフレームで更新
      _pendingUpdate = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _pendingUpdate = false;
        _applyUpdate();
      });
    }
  }

  /// 保留中の更新を適用
  void _applyUpdate() {
    if (!mounted || _isDisposed) return;
    // A3改: スロットリング待ちの間に表示対象が変わっていないか照合。
    // 不一致（切替・再解決・再接続）なら破棄し、次回ポーリングに任せる。
    if (!_isCurrentHerdrTarget(_pendingTargetIdentity)) return;
    _lastFrameTime = DateTime.now();
    // ValueNotifier更新（親のsetState()を回避し、ValueListenableBuilderのみリビルド）
    _viewNotifier.value = _viewNotifier.value.copyWith(
      content: _pendingContent,
    );

    // 初回コンテンツ受信時に一番下へスクロール
    if (!_hasInitialScrolled && _pendingContent.isNotEmpty) {
      _hasInitialScrolled = true;
      // inventory: TERM-SCROLL-004
      _scrollToCaret();
    }
  }

  /// 自動再接続を試みる
  Future<void> _attemptReconnect() async {
    if (_isDisposed) return;

    final sshNotifier = ref.read(sshProvider.notifier);
    final success = await sshNotifier.reconnect();

    if (!mounted || _isDisposed) return;

    if (!success) {
      // 再接続失敗時は再試行（最大回数に達するまで）
      final currentState = ref.read(sshProvider);
      if (currentState.reconnectAttempt < 5) {
        // 次のポーリングで再試行される
      }
    }
  }

  // inventory: TERM-LIFE-024
  /// 認証オプションを取得
  Future<SshConnectOptions> _getAuthOptions(Connection connection) async {
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await _secureStorage.getPrivateKey(connection.keyId!);
      final passphrase = await _secureStorage.getPassphrase(connection.keyId!);
      return SshConnectOptions(
        privateKey: privateKey,
        passphrase: passphrase,
        multiplexer: connection.multiplexer,
      );
    } else {
      final password = await _secureStorage.getPassword(connection.id);
      return SshConnectOptions(
        password: password,
        multiplexer: connection.multiplexer,
      );
    }
  }

  /// エラーSnackBar表示
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      // inventory: LEGACY-0073
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          // inventory: TERM-LIFE-011
          onPressed: _connectAndSetup,
        ),
      ),
    );
  }

  /// スクロール時にスクロールボタンを表示
  void _onTerminalScroll() {
    _scrollToBottomKey.currentState?.show();
  }

  /// 上端でのオーバースクロール（さらに上へ引っ張る操作）を検出して深い履歴を
  /// ロードする。単に上端へ達しただけでは発火せず、明示的に引っ張ったときのみ
  /// 発火する（誤爆を防ぎ、tmux のコピーモード相当の操作感にする）。
  bool _onTerminalOverscroll(OverscrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.overscroll < 0 &&
        _terminalMode == TerminalMode.normal &&
        !_isLoadingDeepHistory) {
      // inventory: TERM-SCROLL-003
      _loadDeepHistoryOnScroll();
    }
    return false;
  }

  /// スクロール上端到達時に深い履歴を自動ロードする。スクロールモードに入って
  /// ライブ更新をバッファし、履歴表示を保持する。
  Future<void> _loadDeepHistoryOnScroll() async {
    if (_isLoadingDeepHistory) return;
    _isLoadingDeepHistory = true;
    if (_terminalMode != TerminalMode.scroll) {
      setState(() {
        _terminalMode = TerminalMode.scroll;
        _scrollModeSource = ScrollModeSource.manual;
      });
    }
    try {
      await _loadHistoryForScroll(preservePosition: true);
    } finally {
      _isLoadingDeepHistory = false;
    }
  }

  @override
  // inventory: LEGACY-0072
  void deactivate() {
    // ref.readはdeactivateまでは安全（disposeでは_elementsから外れている）
    final sshNotifier = ref.read(sshProvider.notifier);
    sshNotifier.onReconnectSuccess = null;
    sshNotifier.onDisconnectDetected = null;

    // popUntil等で_disconnect()を経由せずにpopされた場合もSSHを切断
    // 切断前にリサイズしたウィンドウを自動サイズへ戻す（best-effort）
    unawaited(
      _restoreResizedWindows().then((_) {
        if (sshNotifier.checkConnection()) {
          sshNotifier.disconnect();
        }
      }),
    );
    super.deactivate();
  }

  @override
  // inventory: TERM-LIFE-022
  void dispose() {
    // まず_isDisposedをセットして非同期処理を停止
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // WakeLockを無効化
    WakelockPlus.disable();
    // Riverpodサブスクリプションをキャンセル
    _sshSubscription?.close();
    _sshSubscription = null;
    _tmuxSubscription?.close();
    _tmuxSubscription = null;
    _settingsSubscription?.close();
    _settingsSubscription = null;
    _networkSubscription?.close();
    _networkSubscription = null;
    _imageTransferSub?.close();
    _imageTransferSub = null;
    // タイマーを停止
    _pollTimer?.cancel();
    _pollTimer = null;
    _treeRefreshTimer?.cancel();
    _treeRefreshTimer = null;
    // キーオーバーレイ
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = null;
    _keyOverlayState.dispose();
    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = null;
    _backgroundRestoreTimer?.cancel();
    _backgroundRestoreTimer = null;
    // herdr: スナップショットキャッシュと A3改 表示対象同一性を解放
    _herdrSnapshotCache = null;
    _pendingTargetIdentity = null;
    _bufferedTargetIdentity = null;
    // 最小監視（A8）リングバッファを解放
    _herdrSwitchEvents.clear();
    // ValueNotifierを破棄
    _viewNotifier.dispose();
    _herdrDisplayNotifier.dispose();
    _latencyNotifier.dispose();
    // スクロールコントローラーのリスナーを削除して破棄
    _terminalScrollController.removeListener(_onTerminalScroll);
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  // inventory: TERM-LIFE-023
  Widget build(BuildContext context) {
    // ローカル状態を使用（ref.watchは使わない）
    // 注意: tmuxProviderは各Consumer内でref.watchして取得する
    // これにより親build()がポーリングで呼ばれず、BottomSheetが安定する
    final sshState = _sshState;
    // inventory: LEGACY-0081
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // ブレッドクラム: backend 種別で経路を分岐（A9）。
              // tmux は Consumer で tmuxProvider を直接 watch（親リビルド不要）。
              // herdr は表示状態（_HerdrDisplayData）を ValueListenableBuilder で監視。
              // inventory: TERM-DIALOG-003
              if (_backendKind == MultiplexerBackendKind.herdr)
                ValueListenableBuilder<_HerdrDisplayData?>(
                  valueListenable: _herdrDisplayNotifier,
                  builder: (context, display, _) => _buildBreadcrumbHeader(
                    _herdrToBreadcrumb(display),
                  ),
                )
              else
                Consumer(
                  builder: (context, ref, _) {
                    final tmuxState = ref.watch(tmuxProvider);
                    return _buildBreadcrumbHeader(_tmuxToBreadcrumb(tmuxState));
                  },
                ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _terminalMode == TerminalMode.scroll
                          ? DesignColors.warning
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // ターミナル表示: ValueListenableBuilder + Consumer
                      // ポーリング更新はValueNotifier経由でこのサブツリーのみリビルド
                      RepaintBoundary(
                        child: ValueListenableBuilder<_TerminalViewData>(
                          valueListenable: _viewNotifier,
                          builder: (context, viewData, _) {
                            return Consumer(
                              builder: (context, ref, _) {
                                final cursor = ref.watch(
                                  tmuxProvider.select(
                                    (s) => (
                                      x: s.activePane?.cursorX ?? 0,
                                      y: s.activePane?.cursorY ?? 0,
                                    ),
                                  ),
                                );
                                return NotificationListener<
                                  OverscrollNotification
                                >(
                                  // inventory: TERM-SCROLL-002
                                  onNotification: _onTerminalOverscroll,
                                  child: AnsiTextView(
                                    key: _ansiTextViewKey,
                                    text: viewData.content,
                                    paneWidth: viewData.paneWidth,
                                    paneHeight: viewData.paneHeight,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.9),
                                    // 操作能力（`_can`）に応じてキー入力・スワイプ操作を無効化
                                    // inventory: TERM-INPUT-001
                                    onKeyInput: _canSendText
                                        ? _handleKeyInput
                                        : null,
                                    onTap: () {
                                      _scrollToBottomKey.currentState?.show();
                                    },
                                    mode: _terminalMode,
                                    zoomEnabled: true,
                                    onZoomChanged: (scale) {
                                      setState(() {
                                        _zoomScale = scale;
                                      });
                                    },
                                    verticalScrollController:
                                        _terminalScrollController,
                                    cursorX: cursor.x,
                                    cursorY: cursor.y,
                                    // inventory: TERM-INPUT-005
                                    onArrowSwipe: _canSendSpecialKey
                                        ? _sendSpecialKeyWithOverlay
                                        : null,
                                    // inventory: TERM-NAV-007
                                    onTwoFingerSwipe: _canFocusDirection
                                        ? _handleTwoFingerSwipe
                                        : null,
                                    navigableDirections: _canFocusDirection
                                        ? _getNavigableDirections()
                                        : null,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      // Pane indicator: ConsumerでtmuxProviderを直接watch
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final tmuxState = ref.watch(tmuxProvider);
                            // inventory: TERM-DIALOG-006
                            return _buildPaneIndicator(tmuxState);
                          },
                        ),
                      ),
                      // スクロールボタン: ターミナルエリア右下
                      Positioned(
                        bottom: 8,
                        right: 16,
                        child: ScrollToBottomButton(
                          key: _scrollToBottomKey,
                          onPressed: () {
                            _ansiTextViewKey.currentState?.scrollToBottom();
                          },
                        ),
                      ),
                      // キーオーバーレイ
                      KeyOverlayWidget(
                        overlayState: _keyOverlayState,
                        position: _keyOverlayPosition,
                      ),
                    ],
                  ),
                ),
              ),
              // 画像アップロード進捗バー
              Consumer(
                builder: (context, ref, _) {
                  final transfer = ref.watch(imageTransferProvider);
                  final isActive =
                      transfer.phase == ImageTransferPhase.uploading ||
                      transfer.phase == ImageTransferPhase.converting;
                  if (!isActive) return const SizedBox.shrink();
                  return LinearProgressIndicator(
                    value: transfer.uploadProgress > 0
                        ? transfer.uploadProgress
                        : null,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                  );
                },
              ),
              // 特殊キー入力バー（`_canSendSpecialKey` が false のときは
              // 読み取り専用バナーを表示し mutation 導線を隠す）
              if (!_canSendSpecialKey)
                _ReadOnlyBanner(isDark: isDark)
              else
                SpecialKeysBar(
                  // inventory: TERM-INPUT-006
                  onKeyPressed: _sendKeyWithOverlay,
                  onSpecialKeyPressed: _sendSpecialKeyWithOverlay,
                  // inventory: TERM-INPUT-009
                  onInputTap: _showInputDialog,
                  directInputEnabled: _directInputEnabled,
                  onDirectInputToggle: () {
                    ref.read(settingsProvider.notifier).toggleDirectInput();
                  },
                  // inventory: TERM-FILE-002
                  onImagePickRequested: _handleImageTransfer,
                ),
            ],
          ),
          // ローディングオーバーレイ
          if (_isConnecting || sshState.isConnecting)
            Container(
              color: isDark ? Colors.black54 : Colors.white70,
              child: const Center(child: CircularProgressIndicator()),
            ),
          // エラーオーバーレイ
          if (_connectionError != null || sshState.hasError)
            // inventory: TERM-DIALOG-007
            _buildErrorOverlay(sshState.error ?? _connectionError),
        ],
      ),
    );
  }

  // --- キーオーバーレイ ラッパー ---

  KeyOverlayPosition get _keyOverlayPosition {
    final pos = ref.read(settingsProvider).keyOverlayPosition;
    return switch (pos) {
      'center' => KeyOverlayPosition.center,
      'belowHeader' => KeyOverlayPosition.belowHeader,
      _ => KeyOverlayPosition.aboveKeyboard,
    };
  }

  /// 特殊キー送信 + オーバーレイ表示
  void _sendSpecialKeyWithOverlay(String tmuxKey) {
    // inventory: TERM-INPUT-004
    _sendSpecialKey(tmuxKey);
    // inventory: TERM-INPUT-007
    _showKeyOverlay(tmuxKey);
  }

  /// リテラルキー送信 + ショートカットキーのオーバーレイ表示
  void _sendKeyWithOverlay(String key) {
    // inventory: TERM-INPUT-003
    _sendKey(key);
    if (TmuxKeyDisplay.isShortcutKey(key)) {
      _showKeyOverlay(key);
    }
  }

  /// オーバーレイ表示ロジック
  void _showKeyOverlay(String key) {
    final settings = ref.read(settingsProvider);
    if (!settings.showKeyOverlay) return;

    final category = TmuxKeyDisplay.categoryOf(key);
    if (category == null) return;

    final enabled = switch (category) {
      KeyOverlayCategory.modifier => settings.keyOverlayModifier,
      KeyOverlayCategory.special => settings.keyOverlaySpecial,
      KeyOverlayCategory.arrow => settings.keyOverlayArrow,
      KeyOverlayCategory.shortcut => settings.keyOverlayShortcut,
    };
    if (!enabled) return;

    _keyOverlayState.show(TmuxKeyDisplay.displayText(key));
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = Timer(const Duration(milliseconds: 1500), () {
      _keyOverlayState.hide();
    });
  }

  /// AnsiTextViewからのキー入力を処理
  void _handleKeyInput(KeyInputEvent event) {
    // テキスト送信不可（read-only）ではキー入力を無効化
    if (!_canSendText) return;
    // 特殊キーの場合はtmux形式で送信（オーバーレイ付き）
    if (event.isSpecialKey && event.tmuxKeyName != null) {
      _sendSpecialKeyWithOverlay(event.tmuxKeyName!);
    } else {
      // 通常の文字はリテラル送信
      _sendKeyData(event.data);
    }
  }

  /// 2本指スワイプによるペイン切り替え
  ///
  /// tmux: PaneNavigator（tmuxProvider）で隣接 pane を解決して select-pane を
  /// 発行する（従来挙動）。herdr: `PaneWriter.focusPaneDirection`
  /// （`pane focus --direction`）へ配線し（T18）、成功後は H5 単一経路
  /// （[_syncAfterHerdrMutation]）で表示を更新する。stale tmuxProvider への
  /// 誤送信はない（R3・backend 分岐）。
  void _handleTwoFingerSwipe(SwipeDirection direction) {
    // 方向フォーカス不可（read-only）では tmuxProvider を読まない（R3）。
    if (!_canFocusDirection) return;
    if (_backendKind == MultiplexerBackendKind.herdr) {
      _focusHerdrPaneDirection(direction);
      return;
    }
    final tmuxState = ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return;

    // 設定に応じてスワイプ方向を反転
    final settings = ref.read(settingsProvider);
    final actualDirection = settings.invertPaneNavigation
        ? direction.inverted
        : direction;

    final targetPane = PaneNavigator.findAdjacentPane(
      panes: window.panes,
      current: activePane,
      direction: actualDirection,
    );

    if (targetPane != null) {
      // inventory: TERM-NAV-003
      _selectPane(targetPane.id);
    }
  }

  /// herdr の 2 本指スワイプによる方向フォーカス（T18・`pane focus --direction`）。
  ///
  /// [PaneWriter.focusPaneDirection]（`HerdrPaneWriter` → `herdr pane focus
  /// --direction {dir} --pane {id}`）でフォーカスを移動し、成功後は H5/T18
  /// 単一経路（[_syncAfterHerdrMutation]）で表示対象を同期する。隣接 pane が
  /// 無い場合（`no_neighbor` / `changed:false` の soft 失敗）は情報通知
  /// （「その方向に pane はありません」・S4/T19）。
  Future<void> _focusHerdrPaneDirection(SwipeDirection direction) async {
    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    final directionName = switch (direction) {
      SwipeDirection.up => 'up',
      SwipeDirection.down => 'down',
      SwipeDirection.left => 'left',
      SwipeDirection.right => 'right',
    };

    // ポーリング停止（SSH競合回避・mutation 実行中は既存方針）
    _pollTimer?.cancel();
    try {
      await writer.focusPaneDirection(paneId, directionName);
      if (!mounted || _isDisposed) return;
      // H5/T18 単一経路: 強制再取得 → 再解決 → ターゲット変化時のみ切替コミット。
      await _syncAfterHerdrMutation(eventLabel: 'focus sync');
    } on PaneOperationNoopException catch (e) {
      // 隣接 pane なし（soft 失敗・情報通知）。
      _showHerdrMutationNoopSnackBar(e);
    } catch (e) {
      // T19/S4: 分類別通知。
      await _handleHerdrMutationError(e, operationLabel: 'focus');
    } finally {
      // ポーリング再開
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// 現在のペインからナビゲーション可能な方向を取得
  Map<SwipeDirection, bool>? _getNavigableDirections() {
    // 方向フォーカス不可（read-only）では tmuxProvider を読まない（R3）。
    // herdr では tmuxProvider が clear() されているため null を返し、
    // スワイプヒントは非表示になる（方向 focus の herdr 配線は T12/T18）。
    if (!_canFocusDirection) return null;
    final tmuxState = ref.read(tmuxProvider);
    final window = tmuxState.activeWindow;
    final activePane = tmuxState.activePane;
    if (window == null || activePane == null) return null;

    final rawDirections = PaneNavigator.getNavigableDirections(
      panes: window.panes,
      current: activePane,
    );

    // 反転設定が有効な場合、方向キーを入れ替える
    final settings = ref.read(settingsProvider);
    if (settings.invertPaneNavigation) {
      return {
        for (final dir in SwipeDirection.values)
          dir: rawDirections[dir.inverted] ?? false,
      };
    }

    return rawDirections;
  }

  /// キーデータを PaneWriter 経由で送信（tmux: send-keys -l / herdr: send-text）
  Future<void> _sendKeyData(String data) async {
    // テキスト送信不可（read-only）では送信しない
    if (!_canSendText) return;
    final sshClient = ref.read(sshProvider.notifier).client;

    // 接続が切れている場合はキューに追加
    if (sshClient == null || !sshClient.isConnected) {
      final wasOverflow = _inputQueue.isOverflow;
      _inputQueue.enqueue(data);
      if (!wasOverflow && _inputQueue.isOverflow && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Input queue is full; some keystrokes may be lost.'),
          ),
        );
      }
      if (mounted) setState(() {}); // キューイング状態を更新
      return;
    }

    // 表示対象は `_TargetSource`（tmux = currentTarget / herdr = 固定 pane ID）。
    // T8: tmuxFacade 直叩きをやめ PaneWriter へ委譲する（R3）。
    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      await writer.sendText(paneId, data);
      _boostPolling();
    } catch (_) {
      // キー送信エラーは静かに無視
    }
  }

  // inventory: TERM-NAV-001
  /// セッションを選択
  Future<void> _selectSession(String sessionName) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    // tmux_providerでアクティブセッションを更新
    ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

    // アクティブなペインを選択状態にする（select-paneコマンドを実行）
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await _selectPane(activePaneId);
    } else {
      // ターミナル内容をクリアして再取得
      _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
      _hasInitialScrolled = false;
    }
  }

  // inventory: TERM-NAV-002
  /// ウィンドウを選択
  Future<void> _selectWindow(String sessionName, int windowIndex) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    // セッションが異なる場合はセッションも切り替え
    final currentSession = ref.read(tmuxProvider).activeSessionName;
    if (currentSession != sessionName) {
      ref.read(tmuxProvider.notifier).setActiveSession(sessionName);
    }

    try {
      // tmux select-windowを実行
      await tmuxFacade.selectWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
      );
    } catch (e) {
      // SSH接続が閉じている場合は無視
      debugPrint('[Terminal] Failed to select window: $e');
      return;
    }
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブウィンドウを更新
    ref.read(tmuxProvider.notifier).setActiveWindow(windowIndex);

    // アクティブなペインを選択状態にする（select-paneコマンドを実行）
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await _selectPane(activePaneId);
    } else {
      // ターミナル内容をクリアして再取得
      _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
      _hasInitialScrolled = false;
    }
  }

  // inventory: TERM-NAV-008
  /// herdr の表示対象 pane を切り替える（切替コミットの単一入口・A4）。
  ///
  /// tmux の [_selectPane]（select-pane コマンド発行）とは別系統の read-only
  /// 表示切替で、mutation は一切発行しない。表示リセット漏れによるスクロール/
  /// モード残留を防ぐため、以下の状態変更をこのメソッドに単一化する:
  ///
  /// 1. [_HerdrTargetSource] の pane ID 差し替え（[ _HerdrTargetSource.setPaneId]）
  /// 2. [_viewNotifier] の content クリア（`copyWith(content: '')`）
  /// 3. [_hasInitialScrolled] リセット（false）
  /// 4. スクロールモード（[_terminalMode] / [_scrollModeSource] / バッファ）リセット
  /// 5. [_herdrDisplayNotifier] 更新（[_HerdrDisplayData] の workspaceLabel /
  ///    workspaceId / tabId / paneId）
  /// 6. [_boostPolling] で即時反映
  ///
  /// 呼び出し元（セレクタ T10・再解決経路等）はこのメソッド経由でのみ
  /// pane ID を差し替える。
  ///
  /// [workspaceLabel] はセレクタ（選択結果の workspace 名）が渡す。省略時は
  /// 要求時の [TerminalScreen.sessionName] を維持する（初回解決・再解決経路）。
  /// [workspaceId] / [tabId] はスナップショット解決済みの実値（再解決・再接続
  /// 経路が渡す）。省略時は pane ID から best-effort で導出する（セレクタ経路）。
  /// [tabLabel] は tab の表示名（`MultiplexerWindow.name` 相当・M-4）で、省略時
  /// は [tabId] へフォールバックする（`name = label ?? id` のドメイン規則に一致）。
  /// 同一ターゲット（paneId / tabId / workspaceId が全て一致）への切替は no-op
  /// にして、表示リセット（コンテンツクリア・スクロール位置喪失）による
  /// チラつきを防ぐ（L-3）。
  void _switchHerdrTarget(
    String paneId, {
    String? workspaceLabel,
    String? workspaceId,
    String? tabId,
    String? tabLabel,
  }) {
    if (!mounted || _isDisposed) return;
    final source = _targetSource;
    if (source is! _HerdrTargetSource) return;

    // 実効値: 未指定の引数は既存の pane ID 導出にフォールバックする
    final effectiveWorkspaceId = workspaceId ?? paneId.split(':').first;
    final effectiveTabId = tabId ?? _herdrTabIdFromPaneId(paneId);
    final effectiveTabLabel = tabLabel ?? effectiveTabId;

    // L-3: 同一ターゲット（paneId / tabId / workspaceId が全て一致）への切替は
    // no-op で、表示リセットと切替イベント・ポーリングブーストを抑止する。
    final current = _herdrDisplayNotifier.value;
    if (current != null &&
        current.paneId == paneId &&
        current.workspaceId == effectiveWorkspaceId &&
        current.tabId == effectiveTabId) {
      return;
    }

    // 1. 表示対象 pane ID を差し替え
    source.setPaneId(paneId);

    // 2-3. コンテンツクリアと初回スクロールフラグのリセット
    _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
    _hasInitialScrolled = false;

    // 4. スクロールモードとバッファのリセット（切替後の残留防止）
    setState(() {
      _terminalMode = TerminalMode.normal;
      _scrollModeSource = ScrollModeSource.none;
    });
    _bufferedContent = '';
    _hasBufferedUpdate = false;
    // A3改: バッファの表示対象同一性もクリア（切替後の stale 適用防止）。
    _bufferedTargetIdentity = null;

    // 5. 表示状態（ブレッドクラム入力）の更新（T11: workspace/tab/pane を反映）
    _herdrDisplayNotifier.value = _HerdrDisplayData(
      workspaceLabel: workspaceLabel ?? widget.sessionName,
      workspaceId: effectiveWorkspaceId,
      tabId: effectiveTabId,
      tabLabel: effectiveTabLabel,
      paneId: paneId,
    );

    // 監視（A8）: 表示対象切替を記録（SDK 送信なし）
    _recordHerdrSwitchEvent('switch target -> $paneId');

    // 6. 即時反映
    _boostPolling();
  }

  /// テストフック: [_switchHerdrTarget] を widget テストから呼び出すための
  /// `@visibleForTesting` メソッド。本番コードからは呼ばない（呼び出し元は
  /// セレクタ T10 が実装した時点で直接 [_switchHerdrTarget] を呼ぶ）。
  @visibleForTesting
  void switchHerdrTargetForTesting(String paneId) => _switchHerdrTarget(paneId);

  /// テストフック: H5/T18 単一経路（[_syncAfterHerdrMutation]）を widget テスト
  /// から直接呼び出すための `@visibleForTesting` メソッド。本番コードからは
  /// 呼ばない（各 mutation ハンドラが成功後にこの単一経路を呼ぶ）。
  @visibleForTesting
  Future<bool> syncAfterHerdrMutationForTesting({
    String eventLabel = 'test mutation sync',
  }) =>
      _syncAfterHerdrMutation(eventLabel: eventLabel);

  /// テストフック: [_splitPane]（herdr 分岐）を widget テストから呼び出すための
  /// `@visibleForTesting` メソッド。本番コードからは呼ばない（セレクタの
  /// 分割導線が `_splitPane` を呼ぶ）。
  @visibleForTesting
  Future<void> splitPaneForTesting(
    String paneId,
    SplitDirection direction,
  ) =>
      _splitPane(paneId, direction);

  /// テストフック: [_renameHerdrPane]（herdr 分岐）を widget テストから
  /// 呼び出すための `@visibleForTesting` メソッド。本番コードからは呼ばない
  /// （セレクタの Rename 導線が [_renameHerdrPane] を呼ぶ）。
  @visibleForTesting
  Future<void> renameHerdrPaneForTesting(String paneId, String label) =>
      _renameHerdrPane(paneId, label);

  /// テストフック: [_handleHerdrZoomPane]（herdr 分岐）を widget テストから
  /// 呼び出すための `@visibleForTesting` メソッド。本番コードからは呼ばない
  /// （セレクタの Zoom 導線が [_handleHerdrZoomPane] を呼ぶ）。
  @visibleForTesting
  Future<void> zoomHerdrPaneForTesting(String paneId) =>
      _handleHerdrZoomPane(paneId);

  /// テストフック: [_createHerdrTab]（herdr 分岐）を widget テストから呼び出す
  /// ための `@visibleForTesting` メソッド。本番コードからは呼ばない
  /// （tab セレクタの New Tab 導線が [_createHerdrTab] を呼ぶ）。
  @visibleForTesting
  Future<void> createHerdrTabForTesting(String workspaceId) =>
      _createHerdrTab(workspaceId);

  /// テストフック: [_renameHerdrTab]（herdr 分岐）を widget テストから呼び出す
  /// ための `@visibleForTesting` メソッド。本番コードからは呼ばない
  /// （tab セレクタの Rename 導線が [_renameHerdrTab] を呼ぶ）。
  @visibleForTesting
  Future<void> renameHerdrTabForTesting(String tabId, String label) =>
      _renameHerdrTab(tabId, label);

  /// テストフック: [_closeHerdrTab]（herdr 分岐）を widget テストから呼び出す
  /// ための `@visibleForTesting` メソッド。本番コードからは呼ばない
  /// （tab セレクタの Close 導線が [_closeHerdrTab] を呼ぶ）。
  @visibleForTesting
  Future<void> closeHerdrTabForTesting(String tabId) =>
      _closeHerdrTab(tabId: tabId);

  /// テストフック: herdr の方向フォーカス（[_focusHerdrPaneDirection]）を widget
  /// テストから呼び出すための `@visibleForTesting` メソッド。本番コードからは
  /// 呼ばない（`_handleTwoFingerSwipe` が herdr 分岐で呼ぶ）。
  @visibleForTesting
  Future<void> focusHerdrPaneDirectionForTesting(SwipeDirection direction) =>
      _focusHerdrPaneDirection(direction);

  /// テストフック: リングバッファ（直近 64 件・`[HerdrSwitch]` プレフィックス付き）
  /// の現在内容を返す。本番コードからは呼ばない（A8 監視は画面ローカル）。
  @visibleForTesting
  List<String> herdrSwitchEventsForTesting() =>
      List.unmodifiable(_herdrSwitchEvents);

  /// テストフック: 深い履歴のロード（[_loadHistoryForScroll]）を widget テスト
  /// から直接呼び出すための `@visibleForTesting` メソッド。本番コードからは
  /// 呼ばない（オーバースクロール / スクロールモード遷移が呼ぶ）。
  @visibleForTesting
  Future<void> loadHistoryForScrollForTesting() =>
      _loadHistoryForScroll();

  /// テストフック: `_can` 判定を widget テストから直接検証する（H4 等価性
  /// テスト・T4）。本番コードからは呼ばない。
  @visibleForTesting
  bool canForTesting(PaneCapabilities required) => _can(required);

  /// テストフック: 現在のバックエンド操作能力を返す（T4 の Phase 0 検証用）。
  /// 本番コードからは呼ばない。
  @visibleForTesting
  PaneCapabilities paneCapabilitiesForTesting() => _paneCapabilities;

  /// テストフック: tmux キー名の特殊キー送信（[_sendSpecialKey] 相当）を widget
  /// テストから直接検証する（T13: PaneKeyMap の全キー送信経路・防御的
  /// `invalid_key` 通知）。本番コードからは呼ばない。
  @visibleForTesting
  void sendSpecialKeyForTesting(String tmuxKey) {
    _sendSpecialKey(tmuxKey);
  }

  /// ペインを選択（T8: PaneWriter 経由。tmux の select-pane 発行 + 状態同期）
  Future<void> _selectPane(String paneId) async {
    // フォーカス不可（read-only）では送信しない（R3: herdr で tmuxProvider を
    // 読まない）。herdr は直接アクティブ化 CLI が無いため（OQ1）、セレクタの
    // pane 選択は表示切替コミット（_switchHerdrTarget）を経由する。
    if (!_can(const PaneCapabilities(focus: true))) return;
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final writer = _paneWriter;
    if (writer == null) return;

    try {
      // 表示対象（target）は _TargetSource 側で解決済み。tmux の select-pane +
      // focus-in は TmuxPaneWriter が委譲する（従来の previousPaneId による
      // focus-out は PaneWriter interface で表現できないため省略）。
      await writer.selectPane(paneId);
    } catch (e) {
      // SSH接続が閉じている場合は無視
      debugPrint('[Terminal] Failed to select pane: $e');
      return;
    }
    if (!mounted || _isDisposed) return;

    // tmux_providerでアクティブペインを更新
    ref.read(tmuxProvider.notifier).setActivePane(paneId);

    // TerminalDisplayProviderにペイン情報を通知（フォントサイズ計算用）
    final activePane = ref.read(tmuxProvider).activePane;
    final tmuxState = ref.read(tmuxProvider);
    if (activePane != null) {
      ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      _viewNotifier.value = _viewNotifier.value.copyWith(
        paneWidth: activePane.width,
        paneHeight: activePane.height,
        content: '',
      );
      // ペイン切り替え時は初回スクロールフラグをリセット
      // 次のコンテンツ受信時に最下部へスクロールされる
      _hasInitialScrolled = false;

      // 自動リサイズ: ペイン選択時に画面サイズに合わせてtmuxペインをリサイズ
      final settings = ref.read(settingsProvider);
      if (settings.isAutoResize) {
        await _executeAutoResize(activePane);
      }

      // セッション情報を保存（復元用）
      final sessionName = tmuxState.activeSessionName;
      final sessionId = tmuxState.activeSession?.id;
      final windowIndex = tmuxState.activeWindowIndex;
      if (sessionName != null && windowIndex != null) {
        ref
            .read(activeSessionsProvider.notifier)
            .updateLastPane(
              connectionId: widget.connectionId,
              sessionName: sessionName,
              sessionId: sessionId,
              windowIndex: windowIndex,
              paneId: paneId,
            );
      }
    }
  }

  /// キャレット位置にスクロール
  ///
  /// パネル/ウィンドウ切り替え後の初回表示時に呼ばれ、
  /// カーソル行が画面中央付近に来るようスクロールする
  void _scrollToCaret() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || _isDisposed) return;
      _ansiTextViewKey.currentState?.scrollToCaret();
    });
  }

  /// エラーオーバーレイ
  Widget _buildErrorOverlay(String? error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final queuedCount = _inputQueue.length;
    final isWaitingForNetwork = _sshState.isWaitingForNetwork;

    return Container(
      color: isDark ? Colors.black87 : Colors.white.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWaitingForNetwork ? Icons.signal_wifi_off : Icons.error_outline,
              color: isWaitingForNetwork
                  ? DesignColors.warning
                  : colorScheme.error,
              size: 48,
            ),
            // inventory: LEGACY-0074
            const SizedBox(height: 16),
            // inventory: LEGACY-0090
            Text(
              isWaitingForNetwork
                  ? 'Waiting for network...'
                  : (error ?? 'Connection error'),
              style: TextStyle(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),

            // キューイング状態
            if (queuedCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: DesignColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard, size: 16, color: DesignColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '$queuedCount chars queued',
                      style: TextStyle(
                        color: DesignColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        _inputQueue.clear();
                        setState(() {});
                      },
                      child: Icon(
                        Icons.clear,
                        size: 16,
                        color: DesignColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    ref.read(sshProvider.notifier).reconnectNow();
                  },
                  child: const Text('Retry Now'),
                ),
                if (_sshState.isReconnecting) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 上部のパンくずナビゲーションヘッダー（A9）。
  ///
  /// [data] は backend 経路ごとに生成済みの共通データ（`_tmuxToBreadcrumb` /
  /// `_herdrToBreadcrumb`）。描画ロジックはこの関数に一元化する。
  Widget _buildBreadcrumbHeader(_BreadcrumbData data) {
    final colorScheme = Theme.of(context).colorScheme;

    // SafeAreaを外側に配置してステータスバー分のスペースを確保
    return SafeArea(
      bottom: false,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.9),
          border: Border(
            bottom: BorderSide(color: colorScheme.outline, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Breadcrumb navigation
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // セッション名（read-only ではタップ不可）
                    // inventory: TERM-DIALOG-004
                    _buildBreadcrumbItem(
                      data.session,
                      icon: Icons.folder,
                      isActive: true,
                      onTap: data.onSessionTap,
                    ),
                    // ウィンドウ（tab）セグメント。herdr（T11）では read-only
                    // でも現在ターゲット（workspace/tab/pane）を表示する。
                    if (data.window != null) ...[
                      // inventory: TERM-DIALOG-005
                      _buildBreadcrumbSeparator(),
                      _buildBreadcrumbItem(
                        data.window!,
                        icon: Icons.tab,
                        isSelected: true,
                        onTap: data.onWindowTap,
                      ),
                    ],
                    // ペインセグメント（window と独立。herdr では pane ID が
                    // 2 セグメント形式でも表示する）
                    if (data.pane != null) ...[
                      _buildBreadcrumbSeparator(),
                      _buildBreadcrumbItem(
                        data.pane!,
                        icon: Icons.terminal,
                        isActive: false,
                        onTap: data.onPaneTap,
                      ),
                    ],
                    if (data.readOnlyBadge) ...[
                      // herdr: read-only バッジ（T4: 表示専用・非インタラクティブ。
                      // セレクタ導線は各セグメントのタップに移行した）
                      _buildBreadcrumbSeparator(),
                      _buildBreadcrumbItem(
                        'Read-only',
                        icon: Icons.lock_outline,
                        isActive: false,
                        onTap: data.onReadOnlyTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ブレッドクラムと右側インジケータ群の間に必ず余白を確保する。
            // これがないとスクロールチップ等がブレッドクラムに密着し、重なって見える。
            const SizedBox(width: 8),
            // Scroll mode indicator
            if (_terminalMode == TerminalMode.scroll)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _terminalMode = TerminalMode.normal;
                    _scrollModeSource = ScrollModeSource.none;
                  });
                  // inventory: TERM-COPY-002
                  _cancelTmuxCopyMode();
                  _applyBufferedUpdate();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: DesignColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: DesignColors.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.unfold_more,
                        size: 12,
                        color: DesignColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: DesignColors.warning),
                    ],
                  ),
                ),
              ),
            // Zoom indicator
            if (_isZoomed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(_effectiveZoom * 100).round()}%',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: DesignColors.warning,
                  ),
                ),
              ),
            // Latency / Reconnect indicator（ValueListenableBuilderでポーリング更新をスコープ）
            ValueListenableBuilder<int>(
              valueListenable: _latencyNotifier,
              builder: (context, latency, _) =>
                  _buildConnectionIndicator(latency),
            ),
            // File browser button（スクロール中・read-only は場所を空けるため非表示）
            if (_terminalMode != TerminalMode.scroll && !data.readOnlyBadge)
              IconButton(
                // inventory: TERM-FILE-001
                onPressed: _handleFileBrowser,
                icon: Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                tooltip: 'File Browser',
              ),
            // Settings button
            IconButton(
              // inventory: TERM-DIALOG-002
              onPressed: _showTerminalMenu,
              icon: Icon(
                Icons.settings,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// tmux 経路: [TmuxState] をブレッドクラム描画用データへ変換する（A9）。
  ///
  /// 特殊キー送信不可（read-only）の場合はバッジ表示に切り替え、セレクタ
  /// tap を無効化する。
  _BreadcrumbData _tmuxToBreadcrumb(TmuxState tmuxState) {
    final isReadOnly = !_canSendSpecialKey;
    final activePane = tmuxState.activePane;
    return _BreadcrumbData(
      session: isReadOnly
          ? (widget.sessionName ?? tmuxState.activeSessionName ?? '')
          : (tmuxState.activeSessionName ?? ''),
      window: isReadOnly ? null : (tmuxState.activeWindow?.name ?? ''),
      pane: isReadOnly || activePane == null
          ? null
          : 'Pane ${activePane.index}',
      readOnlyBadge: isReadOnly,
      onSessionTap: isReadOnly ? null : () => _showSessionSelector(tmuxState),
      onWindowTap: isReadOnly ? null : () => _showWindowSelector(tmuxState),
      onPaneTap: isReadOnly ? null : () => _showPaneSelector(tmuxState),
    );
  }

  /// herdr 経路: 表示状態（[display]）をブレッドクラム描画用データへ変換する（A9）。
  ///
  /// read-only は呼び出し側明示（[TerminalScreen.readOnly]）のときのみバッジを
  /// 表示する（T16/H6）。セレクタ導線は各セグメントのタップ:
  /// - session/workspace セグメント → workspace セレクタ（Select Session 相当）
  /// - window/tab セグメント → tab セレクタ（Select Window 相当）
  /// - pane セグメント → pane セレクタ（Select Pane 相当）
  _BreadcrumbData _herdrToBreadcrumb(_HerdrDisplayData? display) {
    final paneId = display?.paneId;
    final tabId = display?.tabId;
    final isExplicitReadOnly = widget.readOnly;
    return _BreadcrumbData(
      session: display?.workspaceLabel ?? widget.sessionName ?? '',
      // M-4: tab セグメントは数字抽出（旧 _herdrTabSegmentLabel）ではなく、
      // snapshot 解決済みの実ラベル（tabLabel = tab.label ?? tab.id 相当）を表示する。
      window: tabId != null ? (display?.tabLabel ?? tabId) : null,
      pane: paneId != null ? _herdrPaneSegmentLabel(paneId) : null,
      readOnlyBadge: isExplicitReadOnly,
      onSessionTap: () => _showHerdrWorkspaceSelector(),
      onWindowTap: () => _showHerdrTabSelector(),
      onPaneTap: () => _showHerdrPaneSelector(),
      // T4: Read-only バッジは表示専用（非インタラクティブ）
      onReadOnlyTap: null,
    );
  }

  /// herdr の workspace セレクタ（Select Session 相当・選択即閉じ・T10 / A6 / T4）。
  ///
  /// データソースは [_fetchHerdrSessions]（共有ヘルパー）が [HerdrSnapshotCache]
  /// （唯一の read chokepoint・A5）経由で取得した snapshot を `toDomainSessions()`
  /// で共通 domain ツリーへ変換したもの。workspace 一覧を 1 階層で表示し、選択
  /// するとその workspace の表示対象 pane を解決して [_switchHerdrTarget]
  /// （切替コミットの単一入口・T6）で切替え、シートを即閉じする。read-only（A6）
  /// のため mutation UI は持たない。
  void _showHerdrWorkspaceSelector() {
    if (!mounted || _isDisposed) return;
    if (_backendKind != MultiplexerBackendKind.herdr) return;
    // バグ3 根本対応: シートを即時 open し、asyncChildren で非同期取得して
    // loading → data/error と表示する。fetch 完了を待たないため、遅延中に
    // 再タップしてもシートは既に open されており、以後のタップは modal
    // barrier に吸収される（app の共有 boolean ガードは不要）。
    _showMultiplexerSheet(
      title: 'Select Session',
      icon: Icons.folder,
      asyncContent: () async {
        final sessions = await _fetchHerdrSessions(
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');
        final current = _herdrSelectorContext();
        return _SelectorContent(
          children: [
            for (final session in sessions)
              MultiplexerSessionTile(
                key: ValueKey('mux-sel-session-${session.name}'),
                session: session,
                isActive: _isCurrentSession(session, current),
                onTap: () {
                  Navigator.pop(context);
                  _herdrSelectWorkspace(sessions, session);
                },
              ),
          ],
        );
      },
    );
  }

  /// タブ resize 可否の共有判定（M-1: ヘッダー/タイル/ハンドラで完全共有）。
  ///
  /// herdr は相対分数 resize のみ（Q-04）のため、単一 pane タブの resize は
  /// no-op になる（意図的差分①・🤝#2）。よって「resize 能力があり、かつ
  /// pane 数 > 1」のときのみ resize 導線を表示する。pane 数は解決データ
  /// （[MultiplexerWindow.panes]）から判定する（表示用 `paneCount` は使用しない）。
  bool _canResizeTab(MultiplexerWindow tab) =>
      _can(const PaneCapabilities(resize: true)) && tab.panes.length > 1;

  /// herdr の tab セレクタ（Select Window 相当・選択即閉じ・T10 / A6 / T4）。
  ///
  /// 現在表示中の workspace（[_HerdrDisplayData] から引き当て）の tab 一覧を
  /// 1 階層で表示する。選択するとその tab のフォーカス pane へ
  /// [_switchHerdrTarget] で切替え、シートを即閉じする。
  ///
  /// Q-05（tab CRUD 解禁）以降は mutation UI を追加する（tmux の
  /// [_showWindowSelector] を参照）:
  /// - ヘッダー: New Tab（[PaneWriter.createTab] = `herdr tab create`）/
  ///   Resize Tab（現在表示タブのアクティブ pane を対象・下記 [_canResizeTab]）
  /// - タイル ⋮: Rename Tab（[PaneWriter.renameTab] = `herdr tab rename`）/
  ///   Resize Tab（[PaneWriter.resizePane] 経由・タブのアクティブ pane 対象）/
  ///   Close Tab（[PaneWriter.closeTab] = `herdr tab close`・最後の tab は
  ///   連鎖 close 確認付き・R2）
  ///
  /// タブ resize（タスク①・🤝#1・案A）: herdr はタブ単位の resize コマンドが
  /// 存在しないため（Q-04）、「タブのアクティブ pane の相対分数 resize」として
  /// 提供する。単一 pane タブの resize は no-op になるため（意図的差分①・🤝#2）、
  /// ヘッダー/タイル両導線とも [_canResizeTab] でガードする。
  void _showHerdrTabSelector() {
    if (!mounted || _isDisposed) return;
    if (_backendKind != MultiplexerBackendKind.herdr) return;
    // バグ3 根本対応: シートを即時 open し、asyncContent で非同期取得して
    // loading → data/error と表示する（再タップは modal barrier が吸収）。
    _showMultiplexerSheet(
      title: 'Select Window',
      icon: Icons.tab,
      asyncContent: () async {
        // theme 依存の値を async gap 前に取得（use_build_context_synchronously）。
        final primary = Theme.of(context).colorScheme.primary;
        final sessions = await _fetchHerdrSessions(
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');

        final workspace = _herdrFindWorkspace(
          sessions,
          _herdrDisplayNotifier.value,
        );
        if (workspace == null) throw StateError('No workspace found');

        final current = _herdrSelectorContext();
        // mutation アクションは能力単位で有効化（T4: `_can` の各 capability に分解）。
        final canTabCrud = _can(const PaneCapabilities(tabCrud: true));
        final canRename = _can(const PaneCapabilities(rename: true));
        // ヘッダー Resize Tab の対象は「現在表示中のタブ」（pane セレクタの
        // 現在表示 pane と同型・H-2）。解決不能なら導線を出さない（防御）。
        final currentWindow = _herdrFindWindow(
          workspace,
          _herdrDisplayNotifier.value,
        );
        // New Tab（Q-05）はデータロード後に workspace.id が確定するため、
        // headerActions を loader で返す（tooltip 付き IconButton）。
        final headerActions = [
          if (currentWindow != null && _canResizeTab(currentWindow))
            IconButton(
              icon: Icon(Icons.open_in_full, color: primary),
              tooltip: 'Resize Tab',
              onPressed: () => _closeSelectorThen(
                () => _handleHerdrResizeTabPane(currentWindow),
              ),
            ),
          if (canTabCrud && workspace.id != null)
            IconButton(
              icon: Icon(Icons.add, color: primary),
              tooltip: 'New Tab',
              onPressed: () =>
                  _closeSelectorThen(() => _createHerdrTab(workspace.id!)),
            ),
        ];
        return _SelectorContent(
          headerActions: headerActions,
          children: [
            for (final window in workspace.windows)
              MultiplexerWindowTile(
                key: ValueKey('mux-sel-window-${window.id ?? window.index}'),
                window: window,
                isActive: _isCurrentWindow(window, current),
                onTap: () {
                  Navigator.pop(context);
                  _herdrSelectTab(sessions, workspace, window);
                },
                onRename: canRename && window.id != null
                    ? () => _closeSelectorThen(() {
                          _showHerdrRenameTabDialog(workspace, window);
                        })
                    : null,
                onResize: _canResizeTab(window)
                    ? () => _closeSelectorThen(
                          () => _handleHerdrResizeTabPane(window),
                        )
                    : null,
                resizeLabel: 'Resize Tab',
                onClose: canTabCrud && window.id != null
                    ? () => _closeSelectorThen(() {
                          // Q-03/R2: 最後の tab / workspace の連鎖 close を確認してから
                          // `tab close` を実行する。
                          _confirmAndCloseHerdrTab(
                            workspace: workspace,
                            tab: window,
                            isLastTab: workspace.windows.length == 1,
                          );
                        })
                    : null,
              ),
          ],
        );
      },
    );
  }

  /// herdr の pane セレクタ（Select Pane 相当・選択即閉じ・T10 / A6 / T4）。
  ///
  /// 現在表示中の workspace / tab（[_HerdrDisplayData] から引き当て）の pane
  /// 一覧を 1 階層で表示する。pane 表示名は cwd 優先（A10 / [_herdrPaneLabel]）。
  /// 選択すると [_switchHerdrTarget] で切替え、シートを即閉じする。
  /// mutation 解禁後（T13/T14）はリサイズを有効化する（Q-04: 方向 + ステップ
  /// UI の [HerdrResizePaneDialog]。絶対値 UI は herdr 非対応のため tmux と
  /// 経路を分ける）。Q-02（全操作解禁）ではヘッダーに Split / Rename / Zoom を
  /// 追加する（tmux の [_showPaneSelector] を参照。ヘッダー操作の対象は
  /// 現在表示中の pane = Resize と同じ導線）:
  /// - Split: 方向選択ダイアログ（右/下）→ [_splitPane]（`herdr pane split`）
  /// - Rename: 入力ダイアログ → [_renameHerdrPane]（`herdr pane rename`）
  /// - Zoom: トグル（[_handleHerdrZoomPane] = `herdr pane zoom --toggle`。
  ///   zoom 状態は snapshot の layout `zoomed` フラグで表示・可能なら）
  void _showHerdrPaneSelector() {
    if (!mounted || _isDisposed) return;
    if (_backendKind != MultiplexerBackendKind.herdr) return;
    // バグ3 根本対応: シートを即時 open し、asyncContent で非同期取得して
    // loading → data/error と表示する（再タップは modal barrier が吸収）。
    _showMultiplexerSheet(
      title: 'Select Pane',
      icon: Icons.terminal,
      asyncContent: () async {
        // theme 依存の値を async gap 前に取得（use_build_context_synchronously）。
        final primary = Theme.of(context).colorScheme.primary;
        final sessions = await _fetchHerdrSessions(
          eventLabel: 'selector snapshot',
          isTerminal: false,
        );
        if (sessions == null) throw StateError('Failed to load herdr tree');

        final display = _herdrDisplayNotifier.value;
        final workspace = _herdrFindWorkspace(sessions, display);
        final window = _herdrFindWindow(workspace, display);
        if (workspace == null || window == null) {
          throw StateError('No workspace/tab found');
        }

        final current = _herdrSelectorContext();
        // mutation アクションは能力単位で有効化（T4: `_can` の各 capability に分解）。
        final canResize = _can(const PaneCapabilities(resize: true));
        final canClose = _can(const PaneCapabilities(close: true));
        final canSplit = _can(const PaneCapabilities(split: true));
        final canRename = _can(const PaneCapabilities(rename: true));
        final canZoom = _can(const PaneCapabilities(zoom: true));
        // ヘッダー操作の対象は現在表示中の pane（既存 Resize ボタンと同じ導線）。
        final currentPaneId = _targetSource?.currentPaneId;
        final currentPane = currentPaneId == null
            ? null
            : _findHerdrPane(sessions, currentPaneId);
        // zoom 状態は snapshot の layout `zoomed` フラグから表示（可能なら）。
        final isZoomed = _isHerdrTabZoomed(display?.tabId);
        // ヘッダー mutation（Q-02）はデータロード後に確定するため loader で返す。
        final headerActions = [
          if (canSplit && currentPane != null)
            IconButton(
              icon: Icon(Icons.call_split, color: primary),
              tooltip: 'Split Pane',
              onPressed: () => _closeSelectorThen(
                () => _showHerdrSplitDirectionChooser(currentPane),
              ),
            ),
          if (canRename && currentPane != null)
            IconButton(
              icon: Icon(Icons.drive_file_rename_outline, color: primary),
              tooltip: 'Rename Pane',
              onPressed: () => _closeSelectorThen(
                () => _showHerdrRenamePaneDialog(currentPane),
              ),
            ),
          if (canZoom && currentPane != null)
            IconButton(
              icon: Icon(
                isZoomed ? Icons.zoom_out : Icons.zoom_in,
                color: primary,
              ),
              tooltip: isZoomed ? 'Unzoom Pane' : 'Zoom Pane',
              onPressed: () => _closeSelectorThen(
                () => _handleHerdrZoomPane(currentPane.id),
              ),
            ),
          if (canResize)
            IconButton(
              icon: Icon(Icons.open_in_full, color: primary),
              tooltip: 'Resize Pane',
              onPressed: () => _closeSelectorThen(() {
                // ヘッダーの Resize は現在表示中の pane を対象にする。
                final id = _targetSource?.currentPaneId;
                if (id == null) return;
                final pane = _findHerdrPane(sessions, id);
                if (pane != null) _handleHerdrResizePane(pane);
              }),
            ),
        ];
        return _SelectorContent(
          headerActions: headerActions,
          children: [
            for (final pane in window.panes)
              MultiplexerPaneTile(
                key: ValueKey('mux-sel-pane-${pane.id}'),
                pane: pane,
                paneTitle: _herdrPaneLabel(pane),
                isActive: _isCurrentPane(pane, current),
                onTap: () {
                  Navigator.pop(context);
                  _herdrSelectPane(sessions, workspace, pane);
                },
                onLongPress: canClose
                    ? () => _closeSelectorThen(() {
                          // T17（Q-03/R2）: 最後の pane / tab 判定を snapshot から
                          // 行い、連鎖 close を確認してから `pane close` を実行する。
                          _confirmAndKillHerdrPane(
                            paneId: pane.id,
                            paneTitle: _herdrPaneLabel(pane),
                            isLastPane: window.panes.length == 1,
                            isLastTab: workspace.windows.length == 1,
                          );
                        })
                    : null,
                onResize: canResize
                    ? () =>
                        _closeSelectorThen(() => _handleHerdrResizePane(pane))
                    : null,
                onClose: canClose
                    ? () => _closeSelectorThen(() {
                          _confirmAndKillHerdrPane(
                            paneId: pane.id,
                            paneTitle: _herdrPaneLabel(pane),
                            isLastPane: window.panes.length == 1,
                            isLastTab: workspace.windows.length == 1,
                          );
                        })
                    : null,
              ),
          ],
        );
      },
    );
  }

  /// herdr の現在位置（H-1: ハイライト導出用）を [_SelectorContext] で返す。
  ///
  /// 表示状態（[_HerdrDisplayData]）の workspaceLabel / workspaceId / tabId と
  /// [_TargetSource.currentPaneId] から導出する。sessionId（workspace ID）は
  /// ハイライト判定の一義的な基準（同名ラベル "tmp" w3/w4 の区別用）。
  _SelectorContext _herdrSelectorContext() {
    final display = _herdrDisplayNotifier.value;
    return _SelectorContext(
      sessionName: display?.workspaceLabel,
      sessionId: display?.workspaceId,
      windowId: display?.tabId,
      paneId: _targetSource?.currentPaneId,
    );
  }

  /// workspace 選択（Select Session 相当）: その workspace の表示対象 pane を
  /// 解決し、[_switchHerdrTarget]（切替コミット・T6）で切替える。
  void _herdrSelectWorkspace(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
  ) {
    final target = _herdrResolveWorkspaceTarget(sessions, workspace);
    if (target == null) return;
    _switchHerdrTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
  }

  /// [workspace] の表示対象 pane を解決する（HerdrTargetResolver の決定順と
  /// 等価: フォーカス tab → tab 内フォーカス pane → tab 内先頭 → workspace 内
  /// フォーカス pane → workspace 内先頭）。
  _HerdrResolvedTarget? _herdrResolveWorkspaceTarget(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
  ) {
    final focusedTab = workspace.windows.where((w) => w.active).firstOrNull;
    final tab = focusedTab ?? workspace.windows.firstOrNull;
    if (tab != null) {
      final focusedPane = tab.panes.where((p) => p.active).firstOrNull;
      if (focusedPane != null) {
        return _herdrResolvedTargetOf(sessions, focusedPane);
      }
      if (tab.panes.isNotEmpty) {
        return _herdrResolvedTargetOf(sessions, tab.panes.first);
      }
    }
    final workspacePanes = [for (final w in workspace.windows) ...w.panes];
    final workspaceFocused = workspacePanes.where((p) => p.active).firstOrNull;
    if (workspaceFocused != null) {
      return _herdrResolvedTargetOf(sessions, workspaceFocused);
    }
    if (workspacePanes.isNotEmpty) {
      return _herdrResolvedTargetOf(sessions, workspacePanes.first);
    }
    return null;
  }

  /// tab 選択（Select Window 相当）: その tab のフォーカス pane へ切替える。
  void _herdrSelectTab(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) {
    final pane = tab.panes.where((p) => p.active).firstOrNull ??
        tab.panes.firstOrNull;
    if (pane == null) return;
    final target = _herdrResolvedTargetOf(sessions, pane);
    _switchHerdrTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
  }

  /// pane 選択（Select Pane 相当）: [_switchHerdrTarget]（切替コミット・T6）で
  /// 切替える。
  void _herdrSelectPane(
    List<MultiplexerSession> sessions,
    MultiplexerSession workspace,
    MultiplexerPane pane,
  ) {
    final target = _herdrResolvedTargetOf(sessions, pane);
    _switchHerdrTarget(
      target.paneId,
      workspaceLabel: workspace.name,
      workspaceId: target.workspaceId,
      tabId: target.tabId,
      tabLabel: target.tabLabel,
    );
  }

  /// [sessions] から現在表示中の workspace（[_HerdrDisplayData.workspaceId] /
  /// [workspaceLabel] 一致）を引き当てる（セレクタの表示対象引き当て用・T4）。
  MultiplexerSession? _herdrFindWorkspace(
    List<MultiplexerSession> sessions,
    _HerdrDisplayData? display,
  ) {
    final id = display?.workspaceId;
    final label = display?.workspaceLabel;
    for (final session in sessions) {
      if (id != null && session.id == id) return session;
      if (label != null && session.name == label) return session;
    }
    return null;
  }

  /// [session] から現在表示中の tab（[_HerdrDisplayData.tabId] 一致）を引き当てる
  /// （セレクタの表示対象引き当て用・T4）。
  MultiplexerWindow? _herdrFindWindow(
    MultiplexerSession? session,
    _HerdrDisplayData? display,
  ) {
    final tabId = display?.tabId;
    if (session == null || tabId == null) return null;
    for (final window in session.windows) {
      if (window.id == tabId) return window;
    }
    return null;
  }

  // inventory: TERM-NAV-004
  /// セッション選択シートを表示（選択即閉じ・元 tmux 挙動）。
  ///
  /// 全セッションを 1 階層で表示する。タップした session は [_selectSession] で
  /// 即時確定してシートを閉じる（T2 / H-1: ハイライトは [_SelectorContext] から
  /// 導出）。
  void _showSessionSelector(TmuxState tmuxState) {
    final sessions = tmuxState.sessions.map((s) => s.toDomain()).toList();
    final current = _selectorContextOf(tmuxState);
    _showMultiplexerSheet(
      title: 'Select Session',
      icon: Icons.folder,
      children: [
        for (final session in sessions)
          MultiplexerSessionTile(
            key: ValueKey('mux-sel-session-${session.name}'),
            session: session,
            isActive: _isCurrentSession(session, current),
            onTap: () {
              Navigator.pop(context);
              _selectSession(session.name);
            },
          ),
      ],
    );
  }

  // inventory: TERM-NAV-005
  /// ウィンドウ選択シートを表示（選択即閉じ・元 tmux 挙動）。
  ///
  /// 現在のアクティブ session の window 一覧を 1 階層で表示する。タップした
  /// window は [_selectWindow] で即時確定してシートを閉じる。mutation（New
  /// Window / Resize Window / Rename / Close）は非 read-only 時のみヘッダーと
  /// PopupMenu に表示する（H-4）。
  void _showWindowSelector(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    if (session == null) return;
    final domainSession = session.toDomain();
    final current = _selectorContextOf(tmuxState);
    // mutation アクションは能力単位で有効化（T4: `_isReadOnly` の一括 boolean
    // を `_can` の各 capability に分解）。
    final canTabCrud = _can(const PaneCapabilities(tabCrud: true));
    final canResize = _can(const PaneCapabilities(resize: true));
    final canRename = _can(const PaneCapabilities(rename: true));
    final canClose = _can(const PaneCapabilities(close: true));
    final primary = Theme.of(context).colorScheme.primary;
    _showMultiplexerSheet(
      title: 'Select Window',
      icon: Icons.tab,
      headerActions: [
        if (canResize)
          IconButton(
            icon: Icon(Icons.open_in_full, color: primary),
            tooltip: 'Resize Window',
            onPressed: () =>
                _closeSelectorThen(() => _showResizeWindowChooser(tmuxState)),
          ),
        if (canTabCrud)
          IconButton(
            icon: Icon(Icons.add, color: primary),
            tooltip: 'New Window',
            onPressed: () =>
                _closeSelectorThen(() => _showCreateWindowDialog(session)),
          ),
      ],
      children: [
        for (final window in domainSession.windows)
          MultiplexerWindowTile(
            key: ValueKey('mux-sel-window-${window.id ?? window.index}'),
            window: window,
            isActive: _isCurrentWindow(window, current),
            onTap: () {
              Navigator.pop(context);
              _selectWindow(session.name, window.index);
            },
            onRename: canRename
                ? () => _closeSelectorThen(() {
                      final tmuxWindow = _tmuxWindowOf(session, window);
                      if (tmuxWindow != null) {
                        // inventory: TERM-CRUD-009
                        _showRenameWindowDialog(session, tmuxWindow);
                      }
                    })
                : null,
            onResize: canResize
                ? () =>
                    _closeSelectorThen(() => _showResizeWindowChooser(tmuxState))
                : null,
            onClose: canClose
                ? () => _closeSelectorThen(() {
                      // inventory: TERM-CRUD-007
                      _confirmAndKillWindow(
                        sessionName: session.name,
                        windowIndex: window.index,
                        windowName: window.name,
                        isLastWindow: session.windows.length == 1,
                      );
                    })
                : null,
          ),
      ],
    );
  }

  /// tmux の現在位置（H-1: ハイライト導出用）を [_SelectorContext] で返す。
  ///
  /// provider のアクティブ状態（activeSessionName / activeSession.id /
  /// activeWindowIndex / activeWindowId / activePaneId）を渡す。sessionId は
  /// ハイライト判定の一義的な基準（$0 等）。
  _SelectorContext _selectorContextOf(TmuxState tmuxState) => _SelectorContext(
        sessionName: tmuxState.activeSessionName,
        sessionId: tmuxState.activeSession?.id,
        windowIndex: tmuxState.activeWindowIndex,
        windowId: tmuxState.activeWindow?.id,
        paneId: tmuxState.activePaneId,
      );

  /// 共通 1 段セレクタシート（[_MultiplexerSelectorSheet]）を開く汎用ヘルパー。
  ///
  /// 呼び出し側が構築した [children]（タイル。onTap は「pop → コールバック」）と
  /// [headerActions]（mutation ボタン）を単一階層のシートとして表示する。
  /// [top] は一覧の上部に表示するウィジェット（tmux pane シートのレイアウト
  /// ビジュアライザ）。シートが閉じた後は [_scrollToBottomKey] を表示する
  /// （既存 3 段セレクタと同じライフサイクル）。
  ///
  /// [asyncContent] を指定すると、**シートを即時 open して loading を表示**し、
  /// 非同期で取得完了後に一覧を表示する（バグ3 根本対応: fetch 後の open では
  /// 遅延中に再タップが barrier に当たり即閉じする問題を解消）。
  /// 戻り値の `_SelectorContent` に children と headerActions の両方を含める
  /// ことで、データロード後にヘッダーの mutation ボタンも確定できる。
  /// [retry] を指定すると、取得失敗時に Retry ボタンを表示する。
  /// [children] が指定されている場合は従来どおり同期的に表示する。
  Future<void> _showMultiplexerSheet({
    required String title,
    required IconData icon,
    Widget? top,
    List<Widget> children = const [],
    List<Widget> headerActions = const [],
    Future<_SelectorContent> Function()? asyncContent,
    VoidCallback? retry,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: _MultiplexerSelectorSheet(
            title: title,
            icon: icon,
            top: top,
            headerActions: headerActions,
            asyncContent: asyncContent,
            retry: retry,
            children: children,
          ),
        );
      },
    ).then((_) {
      if (mounted) _scrollToBottomKey.currentState?.show();
    });
  }

  /// セレクタシートを閉じてから mutation アクションを起動する。
  ///
  /// 既存セレクタの「pop → 200ms 待ち → コールバック」順を維持する（ダイアログ
  /// 表示前にシートの dismiss アニメーションを開始させる）。
  void _closeSelectorThen(VoidCallback action) {
    Navigator.pop(context);
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_isDisposed) action();
    });
  }

  // inventory: TERM-NAV-006
  /// ペイン選択シートを表示（選択即閉じ・元 tmux 挙動）。
  ///
  /// 現在のアクティブ window の pane 一覧を 1 階層で表示する。タップした pane は
  /// [_selectPane] で即時確定してシートを閉じる。ペインのグラフィカルなレイアウト
  /// （[_PaneLayoutVisualizer]）を一覧の上部に表示し、分割は [_splitPane]、
  /// リサイズは [_showResizePaneChooser] に到達する（T2）。
  void _showPaneSelector(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    final window = tmuxState.activeWindow;
    if (session == null || window == null) return;
    final domainWindow = window.toDomain();
    final current = _selectorContextOf(tmuxState);
    // mutation アクションは能力単位で有効化（T4: `_isReadOnly` の一括 boolean
    // を `_can` の各 capability に分解）。
    final canResize = _can(const PaneCapabilities(resize: true));
    final canClose = _can(const PaneCapabilities(close: true));
    final primary = Theme.of(context).colorScheme.primary;
    _showMultiplexerSheet(
      title: 'Select Pane',
      icon: Icons.terminal,
      top: _buildPaneLayoutVisualizer(tmuxState, domainWindow),
      headerActions: [
        if (canResize)
          IconButton(
            icon: Icon(Icons.open_in_full, color: primary),
            tooltip: 'Resize Pane',
            onPressed: () =>
                _closeSelectorThen(() => _showResizePaneChooser(tmuxState)),
          ),
      ],
      children: [
        for (final pane in domainWindow.panes)
          MultiplexerPaneTile(
            key: ValueKey('mux-sel-pane-${pane.id}'),
            pane: pane,
            paneTitle: _tmuxPaneLabelFor(tmuxState, pane.id),
            subtitle: _tmuxPaneSubtitleFor(tmuxState, pane),
            isActive: _isCurrentPane(pane, current),
            onTap: () {
              Navigator.pop(context);
              _selectPane(pane.id);
            },
            onLongPress: canClose
                ? () => _closeSelectorThen(() {
                      // inventory: TERM-CRUD-004
                      _confirmAndKillPane(
                        paneId: pane.id,
                        paneTitle: _tmuxPaneLabelFor(tmuxState, pane.id),
                        isLastPane: window.panes.length == 1,
                        isLastWindow: session.windows.length == 1,
                      );
                    })
                : null,
            onResize: canResize
                ? () =>
                    _closeSelectorThen(() => _showResizePaneChooser(tmuxState))
                : null,
            onClose: canClose
                ? () => _closeSelectorThen(() {
                      // inventory: TERM-CRUD-004
                      _confirmAndKillPane(
                        paneId: pane.id,
                        paneTitle: _tmuxPaneLabelFor(tmuxState, pane.id),
                        isLastPane: window.panes.length == 1,
                        isLastWindow: session.windows.length == 1,
                      );
                    })
                : null,
          ),
      ],
    );
  }

  /// tmux のペインレイアウトビジュアライザを構築する（T2 / Q3）。
  ///
  /// 共通 domain の [MultiplexerWindow] から tmux の [TmuxWindow]（幾何情報を
  /// 含む）を引き当て、[_PaneLayoutVisualizer] を返す。引き当てできない場合は
  /// null（レイアウト非表示）。分割不可（`!_canSplitPane`）では split を
  /// 無効化し選択のみ許可する（H-4）。
  Widget? _buildPaneLayoutVisualizer(
    TmuxState tmuxState,
    MultiplexerWindow window,
  ) {
    final tmuxWindow = _tmuxWindowInTree(tmuxState, window);
    if (tmuxWindow == null) return null;
    return _PaneLayoutVisualizer(
      panes: tmuxWindow.panes,
      activePaneId: tmuxState.activePaneId,
      onPaneSelected: (paneId) {
        Navigator.pop(context);
        _selectPane(paneId);
      },
      onSplitRequested: _canSplitPane
          ? (paneId, direction) {
              Navigator.pop(context);
              _splitPane(paneId, direction);
            }
          : null,
    );
  }

  /// ウィンドウ作成ダイアログを表示
  void _showCreateWindowDialog(TmuxSession session) {
    final existingNames = session.windows.map((w) => w.name).toList();
    showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _NewWindowDialog(existingWindowNames: existingNames),
    ).then((windowName) {
      if (windowName != null) {
        // inventory: TERM-CRUD-001
        _createWindow(windowName.isEmpty ? null : windowName);
      }
    });
  }

  /// 新しいウィンドウを作成
  Future<void> _createWindow(String? windowName) async {
    if (_isCreatingWindow) return;
    _isCreatingWindow = true;
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SSH connection is not available')),
          );
        }
        return;
      }
      final session = ref.read(tmuxProvider).activeSession;
      if (session == null) return;

      await tmuxFacade.createWindow(
        sshClient.tmuxExecutor,
        sessionName: session.name,
        windowName: windowName,
      );
      await _refreshSessionTree();
      if (!mounted) return;

      // active=1のウィンドウを検出して自動切替
      final updatedSession = ref.read(tmuxProvider).activeSession;
      final activeWindow = updatedSession?.windows
          .where((w) => w.active)
          .firstOrNull;
      if (activeWindow != null) {
        ref.read(tmuxProvider.notifier).setActiveWindow(activeWindow.index);
        _viewNotifier.value = _viewNotifier.value.copyWith(content: '');
        _hasInitialScrolled = false;
        final activePaneId = ref.read(tmuxProvider).activePaneId;
        if (activePaneId != null) {
          await _selectPane(activePaneId);
        }
      }
      _boostPolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create window: $e')));
      }
    } finally {
      _isCreatingWindow = false;
    }
  }

  // inventory: TERM-CRUD-003
  /// ペインを分割（T8: PaneWriter 経由）
  Future<void> _splitPane(String paneId, SplitDirection direction) async {
    // 分割不可（read-only・herdr は Phase 1 で capability false）では送信しない
    if (!_canSplitPane) return;
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    final writer = _paneWriter;
    if (writer == null) return;

    try {
      // PaneWriter の方向名（'right' / 'down'）へ変換して委譲する
      // （tmux: split-window / herdr: pane split）。
      final directionName = switch (direction) {
        SplitDirection.horizontal => 'right',
        SplitDirection.vertical => 'down',
      };
      await writer.splitPane(paneId, directionName);
      // herdr: H5/T18 単一経路（force 再取得 → 再解決 → ターゲット変化時のみ
      // 切替）でツリー同期。split 応答は layout を含まないため（T0 実測 6-a）、
      // force 再取得で snapshot から反映する。
      // tmux: 従来挙動（_refreshSessionTree・provider 更新）を維持。
      if (_backendKind == MultiplexerBackendKind.herdr) {
        await _syncAfterHerdrMutation(eventLabel: 'split pane sync');
      } else {
        await _refreshSessionTree();
      }
    } catch (e) {
      if (_backendKind == MultiplexerBackendKind.herdr) {
        // T19/S4: 分類別通知（target-not-found → 再同期 / server-down →
        // ポーリング停止 + 通知 / その他 → エラー通知）。
        await _handleHerdrMutationError(e, operationLabel: 'split');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to split pane: $e')));
      }
    }
  }

  // inventory: TERM-CRUD-005
  /// ペインを閉じる確認ダイアログを表示
  void _confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastWindow,
  }) {    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            'Close Pane?',
            style: TextStyle(
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
          ),
          content: Text(
            isLastPane && isLastWindow
                ? 'This is the last pane in the last window. Closing it will end the session and disconnect from the server.'
                : isLastPane
                ? 'This is the last pane in this window. Closing it will also close the window.'
                : 'Are you sure you want to close pane "$paneTitle"?',
            style: TextStyle(
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // 実行直前にペインがまだ存在するか再検証
                final currentWindow = ref.read(tmuxProvider).activeWindow;
                if (currentWindow == null ||
                    !currentWindow.panes.any((p) => p.id == paneId)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This pane no longer exists'),
                      ),
                    );
                  }
                  return;
                }
                // inventory: TERM-CRUD-004
                _killPane(
                  paneId: paneId,
                  isLastPane: isLastPane,
                  isLastWindow: isLastWindow,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // inventory: TERM-RESIZE-006
  /// リサイズ対象のペインをグラフィカルに選択するダイアログ
  void _showResizePaneChooser(TmuxState tmuxState) {
    final window = tmuxState.activeWindow;
    if (window == null || window.panes.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _ResizePaneChooserDialog(
          panes: window.panes,
          activePaneId: tmuxState.activePaneId,
          onResize: (selectedPane) {
            Navigator.pop(dialogContext);
            // inventory: TERM-RESIZE-004
            _handleResizePane(selectedPane);
          },
        );
      },
    );
  }

  /// リサイズ対象のウィンドウをグラフィカルに選択するダイアログ
  void _showResizeWindowChooser(TmuxState tmuxState) {
    final session = tmuxState.activeSession;
    if (session == null || session.windows.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _ResizeWindowChooserDialog(
          windows: session.windows,
          activeWindowIndex: tmuxState.activeWindowIndex,
          onResize: (selectedWindow) {
            Navigator.pop(dialogContext);
            _handleResizeWindow(selectedWindow);
          },
        );
      },
    );
  }

  /// 自動リサイズ: 画面サイズに合わせてtmuxペインをリサイズ
  Future<void> _executeAutoResize(TmuxPane pane, {bool force = false}) async {
    if (_isResizing) return;
    if (_tmuxVersion != null && !_tmuxVersion!.supportsResizeWindow) return;

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);

    final fontSize = zoomedFontSize(
      baseFontSize: settings.fontSize,
      zoomFactor: settings.zoomFactor,
      minFontSize: settings.minFontSize,
    );
    final targetCols = FontCalculator.calculateMaxCols(
      screenWidth: displayState.screenWidth,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );
    final targetRows = FontCalculator.calculateMaxRows(
      screenHeight: displayState.screenHeight,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );

    debugPrint(
      '[AutoResize] screenWidth=${displayState.screenWidth} '
      'screenHeight=${displayState.screenHeight} '
      'fontSize=$fontSize '
      'fontFamily=${settings.fontFamily} '
      'pane=${pane.id} current=${pane.width}x${pane.height} '
      'target=${targetCols}x$targetRows',
    );

    // 既存サイズと同一ならスキップ
    if (!force && pane.width == targetCols && pane.height == targetRows) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) return;
      await tmuxFacade.resizeWindow(
        sshClient.tmuxExecutor,
        pane.id,
        cols: targetCols,
        rows: targetRows,
      );
      _resizedWindowTargets.add(pane.id);
      // 接続断時にサーバ側で自動復元するtrapを設定（スワイプ終了・強制終了対策）
      await tmuxFacade.setWindowRestoreTrap(
        sshClient.tmuxExecutor,
        _resizedWindowTargets.toList(),
      );
      await _refreshSessionTree();
      final updatedPane = ref.read(tmuxProvider).activePane;
      if (updatedPane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(updatedPane);
      }
    } catch (e) {
      debugPrint('[AutoResize] Failed: $e');
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// AutoResizeで縮めたウィンドウを自動サイズへ戻す（デスクトップ等の他クライアントが
  /// 幅を取り戻せるように）。SSHがまだ生きているうちに呼ぶこと。
  Future<void> _restoreResizedWindows() async {
    if (_resizedWindowTargets.isEmpty) return;
    final targets = _resizedWindowTargets.toList();
    _resizedWindowTargets.clear();
    final client = ref.read(sshProvider.notifier).client;
    if (client == null || !client.isConnected) return;
    // fire-and-forget（チャネル開閉なし）で送信。高遅延やバックグラウンド移行の短い
    // 猶予でも詰まらず、届かず死んだ場合はサーバ側trapが復元する。
    await tmuxFacade.restoreWindows(client.tmuxExecutor, targets);
  }

  /// 接続直後の自動リサイズ。screenWidth が確定（>0）してから実行する。
  /// 初回はレイアウト未確定で screenWidth=0 のため、確定まで数フレーム待つ。
  void _scheduleInitialAutoResize([int attempt = 0]) {
    if (!mounted || _isDisposed) return;
    final screenWidth = ref.read(terminalDisplayProvider).screenWidth;
    final activePane = ref.read(tmuxProvider).activePane;
    if (activePane != null && screenWidth > 0) {
      _executeAutoResize(activePane);
    } else if (attempt < 15) {
      Future.delayed(
        const Duration(milliseconds: 120),
        () => _scheduleInitialAutoResize(attempt + 1),
      );
    }
  }

  /// ペインをリサイズ（絶対値 UI。tmux 専用経路・T8 で TmuxPaneWriter へ委譲）
  Future<void> _handleResizePane(TmuxPane pane) async {
    if (_isResizing) return;

    // 絶対値 resize（tmux）のみこの経路。herdr は `absoluteResize` が false
    // （Q-04: 相対分数のみ）のため capability ガードで到達しない。
    // PaneWriter の resizePane は相対分数のため、絶対値は TmuxPaneWriter の
    // tmux 固有メソッドへ委譲する（方向+ステップ UI は T14 で導入）。
    if (!_can(const PaneCapabilities(resize: true, absoluteResize: true))) {
      return;
    }

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);
    final tmuxState = ref.read(tmuxProvider);

    // 現在のウィンドウの全ペインを取���
    final activeWindow = tmuxState.activeWindow;
    final allPanes = activeWindow?.panes ?? [pane];

    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (context) => ResizePaneDialog(
        targetPane: pane,
        allPanesInWindow: allPanes,
        currentCols: pane.width,
        currentRows: pane.height,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
      ),
    );

    if (result == null || !mounted) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      // T8: 絶対値 resize は TmuxPaneWriter（tmuxFacade ラップ）へ委譲する。
      final writer = _paneWriter;
      if (writer is! TmuxPaneWriter) return;
      await writer.resizePaneAbsolute(
        pane.id,
        cols: result.cols,
        rows: result.rows,
      );
      await _refreshSessionTree();
      // 明示的にupdatePaneを呼んでフォント再計算
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Resize failed: $e')));
      }
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  // inventory: TERM-RESIZE-007
  /// herdr ペインを「方向 + ステップ」でリサイズする（T14・Q-04）。
  ///
  /// herdr は絶対 cols/rows 不可・相対分数のみ（m11/m16 実測）のため、tmux の
  /// 絶対値 [ResizePaneDialog] は使わず、方向（←→↑↓）+ ステップ量
  /// （0.05/0.1/0.2 等）の [HerdrResizePaneDialog] を表示する。現在サイズは
  /// layout の rect（[MultiplexerPane.width]/[height]）から表示する。
  ///
  /// 実行は [PaneWriter.resizePane]（`HerdrPaneWriter` → `herdr pane resize
  /// --direction --amount`）へ委譲する。`changed:false`（分割境界外）は
  /// [PaneOperationNoopException] として情報通知（S4）し、成功時はスナップ
  /// ショットを強制再取得してレイアウトを同期する（H5 単一経路の resize 適用）。
  Future<void> _handleHerdrResizePane(MultiplexerPane pane) async {
    if (_isResizing) return;
    // resize 可能（herdr は `absoluteResize` false のため絶対値 UI には到達しない）。
    if (!_can(const PaneCapabilities(resize: true))) return;

    final result = await showDialog<HerdrResizeResult>(
      context: context,
      builder: (context) => HerdrResizePaneDialog(
        paneId: pane.id,
        currentWidth: pane.width,
        currentHeight: pane.height,
      ),
    );
    if (result == null || !mounted) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final writer = _paneWriter;
      if (writer == null) return;
      await writer.resizePane(pane.id, result.direction, result.amount);
      // 成功: H5/T18 単一経路（force 再取得 → 再解決 → ターゲット変化時のみ
      // 切替）で layout rect と表示対象を同期する。
      await _syncAfterHerdrMutation(eventLabel: 'resize sync');
    } on PaneOperationNoopException catch (e) {
      // 分割境界外（soft 失敗・情報通知）。
      _showHerdrMutationNoopSnackBar(e);
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'resize');
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  // inventory: TERM-RESIZE-008
  /// herdr の tab resize（タスク①・🤝#1・案A）。
  ///
  /// herdr のタブ（window）は独立したサイズ属性を持たないため（H-1・Q-04）、
  /// タブの**アクティブ pane** を対象に既存の [_handleHerdrResizePane]
  /// （`herdr pane resize` 相対分数）へ委譲する。単一 pane タブの resize は
  /// no-op になるため [_canResizeTab] ガードで弾く（意図的差分①・🤝#2）。
  /// アクティブ pane が解決できない場合は沈黙 return（安全側フォールバック）。
  /// `_isResizing` / ダイアログ / 4-way エラー処理は委譲先の既存フローを流用する。
  Future<void> _handleHerdrResizeTabPane(MultiplexerWindow tab) async {
    if (!_canResizeTab(tab)) return;
    final pane = tab.panes.where((p) => p.active).firstOrNull ??
        tab.panes.firstOrNull;
    if (pane == null) return;
    await _handleHerdrResizePane(pane);
  }

  /// ウィンドウをリサイズ
  Future<void> _handleResizeWindow(TmuxWindow window) async {
    if (_isResizing) return;

    final displayState = ref.read(terminalDisplayProvider);
    final settings = ref.read(settingsProvider);

    // ウィンドウサイズはペインのwidth+leftの最大値で推定
    // inventory: LEGACY-0078
    final panes = window.panes;
    int windowCols = 80;
    int windowRows = 24;
    if (panes.isNotEmpty) {
      windowCols = panes
          .map((p) => p.left + p.width)
          .reduce((a, b) => a > b ? a : b);
      windowRows = panes
          .map((p) => p.top + p.height)
          .reduce((a, b) => a > b ? a : b);
    }

    final result = await showDialog<ResizeResult>(
      context: context,
      builder: (context) => ResizeWindowDialog(
        window: window,
        panes: panes,
        currentCols: windowCols,
        currentRows: windowRows,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
        supportsResizeWindow: _tmuxVersion?.supportsResizeWindow ?? false,
      ),
    );

    if (result == null || !mounted) return;

    _isResizing = true;
    _pollTimer?.cancel();
    try {
      final sshClient = ref.read(sshProvider.notifier).client;
      if (sshClient == null) return;
      final tmuxState = ref.read(tmuxProvider);
      final target = '${tmuxState.activeSessionName}:${window.index}';
      await tmuxFacade.resizeWindow(
        sshClient.tmuxExecutor,
        target,
        cols: result.cols,
        rows: result.rows,
      );
      await _refreshSessionTree();
      final activePane = ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Resize failed: $e')));
      }
    } finally {
      _isResizing = false;
      if (mounted && !_isDisposed) _startPolling();
    }
  }

  /// ペインを閉じる（T8: PaneWriter 経由。SSH経由で kill-pane / pane close）
  Future<void> _killPane({
    required String paneId,
    required bool isLastPane,
    required bool isLastWindow,
  }) async {
    // close 不可（read-only・herdr は Phase 1 で capability false）では送信しない
    if (!_can(const PaneCapabilities(close: true))) return;
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    final writer = _paneWriter;
    if (writer == null) return;

    // ポーリング停止（SSH競合回避）
    _pollTimer?.cancel();

    try {
      // 破壊的 close の唯一経路（Q-03）。tmux: kill-pane / herdr: pane close。
      await writer.closePane(paneId);
      await _refreshSessionTree();
      if (!mounted || _isDisposed) return;

      // セッション消滅確認（最後のウィンドウの最後のペインだった場合）
      if (isLastPane && isLastWindow) {
        var sessions = <TmuxSession>[];
        try {
          sessions = await tmuxFacade.listSessions(sshClient.tmuxExecutor);
        } catch (_) {}
        if (!mounted || _isDisposed) return;
        if (sessions.isEmpty) {
          // inventory: TERM-DIALOG-012
          await _disconnect();
          return;
        }
      }

      // 最後のペインだった場合→tmuxが自動選択した新ウィンドウに同期
      if (isLastPane) {
        final newTmuxState = ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow =
              newSession.windows.where((w) => w.active).firstOrNull ??
              newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _selectWindow(newSession.name, newActiveWindow.index);
          }
        }
      } else {
        // 同じウィンドウ内の残りペインに同期
        final newTmuxState = ref.read(tmuxProvider);
        final activeWindow = newTmuxState.activeWindow;
        if (activeWindow != null) {
          final newActivePane =
              activeWindow.panes.where((p) => p.active).firstOrNull ??
              activeWindow.panes.firstOrNull;
          if (newActivePane != null) {
            await _selectPane(newActivePane.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill pane: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close pane: $e')));
      }
    } finally {
      // ポーリング再開
      if (mounted && !_isDisposed) {
        _startPolling();
      }
    }
  }

  Widget _buildBreadcrumbItem(
    String label, {
    IconData? icon,
    bool isActive = false,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.05),
                ),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: isActive
                    ? colorScheme.primary
                    : (isSelected
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label.isEmpty ? '...' : label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: isActive || isSelected
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: isActive
                    ? colorScheme.primary
                    : (isSelected
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: isActive
                    ? colorScheme.primary.withValues(alpha: 0.7)
                    : colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbSeparator() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '/',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w300,
          color: colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// ターミナルメニューを表示
  void _showTerminalMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBgColor = isDark
        ? DesignColors.surfaceDark
        : DesignColors.surfaceLight;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedTextColor = isDark ? Colors.white38 : Colors.black38;
    final inactiveIconColor = isDark ? Colors.white60 : Colors.black45;

    showModalBottomSheet(
      context: context,
      backgroundColor: menuBgColor,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: DesignColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Terminal Options',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // モード切り替え（Normal / Scroll & Select）
              ListTile(
                leading: Icon(
                  _terminalMode == TerminalMode.scroll
                      ? Icons.unfold_more
                      : Icons.keyboard,
                  color: _terminalMode == TerminalMode.scroll
                      ? DesignColors.warning
                      : inactiveIconColor,
                ),
                title: Text(
                  _terminalMode == TerminalMode.scroll
                      ? 'Scroll & Select Mode'
                      : 'Normal Mode',
                  style: TextStyle(
                    color: _terminalMode == TerminalMode.scroll
                        ? DesignColors.warning
                        : textColor,
                    fontWeight: _terminalMode == TerminalMode.scroll
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  _terminalMode == TerminalMode.scroll
                      ? 'Tap to return to normal mode'
                      : 'Tap to enable text selection',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                trailing: Switch(
                  value: _terminalMode == TerminalMode.scroll,
                  onChanged: (value) {
                    final newMode = value
                        ? TerminalMode.scroll
                        : TerminalMode.normal;
                    setState(() {
                      _terminalMode = newMode;
                      _scrollModeSource = value
                          ? ScrollModeSource.manual
                          : ScrollModeSource.none;
                    });
                    if (newMode == TerminalMode.scroll) {
                      // T15: copy-mode は tmux のみ（herdr には無い・H7）。
                      // herdr は `pane read` 履歴ベースのスクロールのみ行う。
                      if (_canCopyMode) {
                        // inventory: TERM-COPY-001
                        _enterTmuxCopyMode();
                      }
                      _loadHistoryForScroll();
                    } else {
                      if (_canCopyMode) {
                        _cancelTmuxCopyMode();
                      }
                      _applyBufferedUpdate();
                    }
                    Navigator.pop(context);
                  },
                  activeThumbColor: DesignColors.warning,
                ),
                onTap: () {
                  final isScrolling = _terminalMode == TerminalMode.scroll;
                  final newMode = isScrolling
                      ? TerminalMode.normal
                      : TerminalMode.scroll;
                  setState(() {
                    _terminalMode = newMode;
                    _scrollModeSource = isScrolling
                        ? ScrollModeSource.none
                        : ScrollModeSource.manual;
                  });
                  if (newMode == TerminalMode.scroll) {
                    // T15: copy-mode は tmux のみ（herdr には無い・H7）。
                    // herdr は `pane read` 履歴ベースのスクロールのみ行う。
                    if (_canCopyMode) {
                      _enterTmuxCopyMode();
                    }
                    _loadHistoryForScroll();
                  } else {
                    if (_canCopyMode) {
                      _cancelTmuxCopyMode();
                    }
                    _applyBufferedUpdate();
                  }
                  Navigator.pop(context);
                },
              ),
              // ズームリセット
              ListTile(
                leading: Icon(
                  Icons.zoom_out_map,
                  color: _isZoomed ? DesignColors.warning : inactiveIconColor,
                ),
                title: Text(
                  'Reset Zoom',
                  style: TextStyle(
                    color: _isZoomed ? textColor : mutedTextColor,
                  ),
                ),
                subtitle: Text(
                  _isZoomed
                      ? 'Current: ${(_effectiveZoom * 100).round()}%'
                      : 'Pinch to zoom in/out',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                enabled: _isZoomed,
                onTap: _isZoomed
                    ? () {
                        ref.read(settingsProvider.notifier).setZoomFactor(1.0);
                        _ansiTextViewKey.currentState?.resetZoom();
                        setState(() {
                          _zoomScale = 1.0;
                        });
                        Navigator.pop(context);
                      }
                    : null,
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // 設定画面へ
              ListTile(
                leading: Icon(Icons.settings, color: inactiveIconColor),
                title: Text('Settings', style: TextStyle(color: textColor)),
                subtitle: Text(
                  'Font, theme, and other options',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // 切断ボタン
              ListTile(
                leading: Icon(
                  Icons.power_settings_new,
                  color: DesignColors.error,
                ),
                title: Text(
                  'Disconnect',
                  style: TextStyle(
                    color: DesignColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Close SSH connection',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // inventory: TERM-DIALOG-011
                  _showDisconnectConfirmation();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// ウィンドウ閉じる確認ダイアログを表示
  void _confirmAndKillWindow({
    required String sessionName,
    required int windowIndex,
    required String windowName,
    required bool isLastWindow,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            'Close Window?',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            isLastWindow
                ? 'This is the last window in the session. Closing it will end the session and disconnect from the server.'
                : 'Are you sure you want to close window "$windowName"?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final wasActive =
                    windowIndex == ref.read(tmuxProvider).activeWindowIndex;
                // inventory: TERM-CRUD-006
                _killWindow(
                  sessionName: sessionName,
                  windowIndex: windowIndex,
                  wasActiveWindow: wasActive,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// ウィンドウを閉じる
  Future<void> _killWindow({
    required String sessionName,
    required int windowIndex,
    required bool wasActiveWindow,
  }) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }

    try {
      debugPrint('[Terminal] Killing window: $sessionName:$windowIndex');
      await tmuxFacade.killWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
      );
      await _refreshSessionTree();

      if (!mounted || _isDisposed) return;

      // セッション消滅判定: list-sessionsで直接確認
      var sessions = <TmuxSession>[];
      try {
        sessions = await tmuxFacade.listSessions(sshClient.tmuxExecutor);
      } catch (_) {}
      if (sessions.isEmpty) {
        debugPrint(
          '[Terminal] Last window closed, session terminated. Disconnecting...',
        );
        await _disconnect();
        return;
      }

      // アクティブウィンドウを閉じた場合、tmuxが自動選択した新ウィンドウに同期
      if (wasActiveWindow) {
        final newTmuxState = ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow =
              newSession.windows.where((w) => w.active).firstOrNull ??
              newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _selectWindow(newSession.name, newActiveWindow.index);
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill window: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close window: $e')));
      }
    }
  }

  /// ウィンドウ名変更ダイアログを表示
  void _showRenameWindowDialog(TmuxSession session, TmuxWindow window) {
    final otherNames = session.windows
        .where((w) => w.index != window.index)
        .map((w) => w.name)
        .toList();
    showDialog<String>(
      context: context,
      builder: (dialogContext) => RenameWindowDialog(
        currentName: window.name,
        otherWindowNames: otherNames,
      ),
    ).then((newName) {
      if (newName == null) return;
      final trimmed = newName.trim();
      if (trimmed.isEmpty || trimmed == window.name) return;
      // inventory: TERM-CRUD-008
      _renameWindow(
        sessionName: session.name,
        windowIndex: window.index,
        newName: trimmed,
      );
    });
  }

  /// ウィンドウ名を変更
  Future<void> _renameWindow({
    required String sessionName,
    required int windowIndex,
    required String newName,
  }) async {
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection is not available')),
        );
      }
      return;
    }
    try {
      debugPrint(
        '[Terminal] Renaming window: $sessionName:$windowIndex -> $newName',
      );
      await tmuxFacade.renameWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
        newName,
      );
      await _refreshSessionTree();
    } catch (e) {
      debugPrint('[Terminal] Failed to rename window: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to rename window: $e')));
      }
    }
  }

  /// 切断確認ダイアログを表示
  void _showDisconnectConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            'Disconnect?',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            'Are you sure you want to disconnect from the server?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // ダイアログを閉じる
                await _disconnect();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // inventory: TERM-CRUD-011
  /// herdr のペインを閉じる確認ダイアログ（T17・Q-03/R2）。
  ///
  /// 最後の pane / 最後の tab（snapshot から判定）を閉じる場合は
  /// tab → workspace の連鎖終了を警告する。確認後は [_killHerdrPane]
  /// （`PaneWriter.closePane` = `herdr pane close` の唯一経路）を実行する。
  void _confirmAndKillHerdrPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastTab,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final String message;
        if (isLastPane && isLastTab) {
          message =
              'This is the last pane in the last tab. Closing it will also '
              'close the tab and the workspace.';
        } else if (isLastPane) {
          message =
              'This is the last pane in this tab. Closing it will also '
              'close the tab.';
        } else {
          message = 'Are you sure you want to close pane "$paneTitle"?';
        }
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            'Close Pane?',
            style: TextStyle(
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // inventory: TERM-CRUD-010
                _killHerdrPane(paneId: paneId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// herdr のペインを閉じる（T17・Q-03: 破壊的 close は `pane close` に一本化）。
  ///
  /// [PaneWriter.closePane]（`HerdrPaneWriter` → `herdr pane close`）を実行し、
  /// 成功後は H5/T18 単一経路（[PaneWriter] で強制再取得 → 再解決 → ターゲット
  /// 変化時のみ [_switchHerdrTarget]）でツリーを同期する。連鎖 close（最後の
  /// pane / 最後の tab）は [_confirmAndKillHerdrPane] で確認済みの前提。
  ///
  /// 失敗時は T19/S4 の分類別通知（target-not-found → 通知 + 再同期 /
  /// server-down → 既存ポーリング停止 + 通知 / その他 → エラー通知）へ倒れる。
  Future<void> _killHerdrPane({required String paneId}) async {
    // close 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(close: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;

    // ポーリング停止（SSH競合回避）
    _pollTimer?.cancel();

    try {
      await writer.closePane(paneId);
      if (!mounted || _isDisposed) return;

      // H5/T18 単一経路: 強制再取得 → 再解決 → ターゲット変化時のみ切替コミット。
      // 連鎖 close で全 workspace が消滅した場合は _syncAfterHerdrMutation が
      // 終端通知（再接続しない・R1）まで行う。
      await _syncAfterHerdrMutation(eventLabel: 'close pane sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'close');
    } finally {
      // ポーリング再開
      if (mounted && !_isDisposed) {
        _startPolling();
      }
    }
  }

  // inventory: TERM-CRUD-012
  /// herdr の分割方向選択ダイアログ（Q-02: split 解禁）。
  ///
  /// ヘッダーの Split ボタンから現在表示中の pane を対象に開く。右
  /// （[SplitDirection.horizontal]）/ 下（[SplitDirection.vertical]）の 2 択で
  /// [_splitPane]（`PaneWriter.splitPane` = `herdr pane split --direction
  /// right|down`）へ委譲する。成功後は [_splitPane] 内の単一経路
  /// （[_syncAfterHerdrMutation]）で同期、失敗時は分類別通知
  /// （[_handleHerdrMutationError]）へ倒れる。
  void _showHerdrSplitDirectionChooser(MultiplexerPane pane) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? DesignColors.textSecondary
        : DesignColors.textSecondaryLight;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark
            ? DesignColors.surfaceDark
            : DesignColors.surfaceLight,
        title: Text(
          'Split Pane',
          style: TextStyle(
            color: isDark
                ? DesignColors.textPrimary
                : DesignColors.textPrimaryLight,
          ),
        ),
        content: Text(
          'Split "${_herdrPaneLabel(pane)}" to the right or down?',
          style: TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? DesignColors.textSecondary
                    : DesignColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _splitPane(pane.id, SplitDirection.horizontal);
            },
            child: const Text('Split Right'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _splitPane(pane.id, SplitDirection.vertical);
            },
            child: const Text('Split Down'),
          ),
        ],
      ),
    );
  }

  // inventory: TERM-CRUD-013
  /// herdr の pane ラベル変更ダイアログ（Q-02: rename 解禁）。
  ///
  /// 入力後は [_renameHerdrPane]（`PaneWriter.renamePane` =
  /// `herdr pane rename`）を実行する。現在のラベルは domain に保持されない
  /// ため（A10: 表示名は cwd 優先）、初期値は空で新規入力する。
  void _showHerdrRenamePaneDialog(MultiplexerPane pane) {
    showDialog<String>(
      context: context,
      builder: (dialogContext) => _HerdrLabelInputDialog(
        title: 'Rename Pane',
        labelText: 'Pane Label',
        hintText: 'Enter a label for this pane',
        confirmLabel: 'Rename',
      ),
    ).then((label) {
      if (label == null || !mounted) return;
      final trimmed = label.trim();
      if (trimmed.isEmpty) return;
      // inventory: TERM-CRUD-013
      _renameHerdrPane(pane.id, trimmed);
    });
  }

  // inventory: TERM-CRUD-014
  /// herdr の pane ラベル変更（`PaneWriter.renamePane` = `herdr pane rename`）。
  ///
  /// 成功後は H5/T18 単一経路（[_syncAfterHerdrMutation]）でツリー同期、失敗時
  /// は T19/S4 の分類別通知（[_handleHerdrMutationError]）へ倒れる。
  Future<void> _renameHerdrPane(String paneId, String label) async {
    // rename 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(rename: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;
    try {
      await writer.renamePane(paneId, label);
      if (!mounted || _isDisposed) return;
      await _syncAfterHerdrMutation(eventLabel: 'rename pane sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'rename pane');
    }
  }

  // inventory: TERM-CRUD-015
  /// herdr の pane zoom トグル（Q-02: zoom 解禁）。
  ///
  /// [PaneWriter.zoomPane]（`HerdrPaneWriter` → `herdr pane zoom --toggle`）を
  /// 実行し、成功後は H5/T18 単一経路（[_syncAfterHerdrMutation]）でツリー同期、
  /// 失敗時は T19/S4 の分類別通知（[_handleHerdrMutationError]）へ倒れる。
  Future<void> _handleHerdrZoomPane(String paneId) async {
    // zoom 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(zoom: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;
    try {
      await writer.zoomPane(paneId, mode: 'toggle');
      if (!mounted || _isDisposed) return;
      await _syncAfterHerdrMutation(eventLabel: 'zoom pane sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'zoom');
    }
  }

  /// snapshot の layout `zoomed` フラグから現在 tab の zoom 状態を返す
  /// （Q-02: zoom 状態表示・可能なら）。
  ///
  /// zoom 状態は tab 単位（layout 単位）に保持される（[HerdrLayout.zoomed]。
  /// T0 実測 6-b）。[HerdrSnapshotCache.cachedSnapshot] は診断用参照のため、
  /// セレクタのボタン表示向け best-effort とし、snapshot 未取得（null）なら
  /// false（非 zoom 表示）を返す。
  bool _isHerdrTabZoomed(String? tabId) {
    final snapshot = _herdrSnapshotCache?.cachedSnapshot;
    if (snapshot == null || tabId == null) return false;
    for (final layout in snapshot.layouts) {
      if (layout.tabId == tabId) return layout.zoomed;
    }
    return false;
  }

  // inventory: TERM-CRUD-016
  /// herdr の tab ラベル変更ダイアログ（Q-05: tab CRUD 解禁）。
  ///
  /// 入力後は [_renameHerdrTab]（`PaneWriter.renameTab` =
  /// `herdr tab rename`）を実行する。
  void _showHerdrRenameTabDialog(
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) {
    final tabId = tab.id;
    if (tabId == null) return;
    showDialog<String>(
      context: context,
      builder: (dialogContext) => _HerdrLabelInputDialog(
        title: 'Rename Tab',
        labelText: 'Tab Label',
        hintText: 'Enter a label for this tab',
        initialValue: tab.name,
        confirmLabel: 'Rename',
      ),
    ).then((label) {
      if (label == null || !mounted) return;
      final trimmed = label.trim();
      if (trimmed.isEmpty || trimmed == tab.name) return;
      // inventory: TERM-CRUD-016
      _renameHerdrTab(tabId, trimmed);
    });
  }

  /// herdr の tab ラベル変更（`PaneWriter.renameTab` = `herdr tab rename`）。
  ///
  /// 成功後は H5/T18 単一経路（[_syncAfterHerdrMutation]）でツリー同期、失敗時
  /// は T19/S4 の分類別通知（[_handleHerdrMutationError]）へ倒れる。
  Future<void> _renameHerdrTab(String tabId, String label) async {
    // rename 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(rename: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;
    try {
      await writer.renameTab(tabId, label);
      if (!mounted || _isDisposed) return;
      await _syncAfterHerdrMutation(eventLabel: 'rename tab sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'rename tab');
    }
  }

  // inventory: TERM-CRUD-017
  /// herdr の tab 作成（Q-05: tab CRUD 解禁）。
  ///
  /// [PaneWriter.createTab]（`HerdrPaneWriter` → `herdr tab create --workspace`
  /// `{workspace_id}`）を実行する。tab create 応答は layout を含まないため
  /// （T18・`result.tab` のみ）、成功後は H5/T18 単一経路（[_syncAfterHerdrMutation]）
  /// の force 再取得で snapshot から反映する。失敗時は T19/S4 の分類別通知
  /// （[_handleHerdrMutationError]）へ倒れる。
  Future<void> _createHerdrTab(String workspaceId) async {
    // tab CRUD 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(tabCrud: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;
    try {
      await writer.createTab(workspaceId);
      if (!mounted || _isDisposed) return;
      await _syncAfterHerdrMutation(eventLabel: 'create tab sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'create tab');
    }
  }

  // inventory: TERM-CRUD-018
  /// herdr の tab を閉じる確認ダイアログ（Q-05: tab CRUD・連鎖 close 確認）。
  ///
  /// 最後の tab（snapshot から判定）を閉じると workspace も連鎖終了するため、
  /// 確認文言を出し分ける（pane の連鎖 close 確認 [_confirmAndKillHerdrPane] と
  /// 同様・R2）。確認後は [_closeHerdrTab]（`PaneWriter.closeTab` =
  /// `herdr tab close`）を実行する。
  void _confirmAndCloseHerdrTab({
    required MultiplexerSession workspace,
    required MultiplexerWindow tab,
    required bool isLastTab,
  }) {
    final tabId = tab.id;
    if (tabId == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = isLastTab
        ? 'This is the last tab in this workspace. Closing it will also '
            'close the workspace.'
        : 'Are you sure you want to close tab "${tab.name}"?';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark
            ? DesignColors.surfaceDark
            : DesignColors.surfaceLight,
        title: Text(
          'Close Tab?',
          style: TextStyle(
            color: isDark
                ? DesignColors.textPrimary
                : DesignColors.textPrimaryLight,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? DesignColors.textSecondary
                    : DesignColors.textSecondaryLight,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // inventory: TERM-CRUD-018
              _closeHerdrTab(tabId: tabId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DesignColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// herdr の tab を閉じる（`PaneWriter.closeTab` = `herdr tab close`）。
  ///
  /// 成功後は H5/T18 単一経路（[_syncAfterHerdrMutation]）でツリー同期、失敗時
  /// は T19/S4 の分類別通知（[_handleHerdrMutationError]）へ倒れる。連鎖 close
  /// （最後の tab → workspace 消滅）は [_confirmAndCloseHerdrTab] で確認済みの
  /// 前提。再解決不能（全 workspace 消滅）は [_syncAfterHerdrMutation] が終端
  /// 通知（再接続しない・R1）まで行う。
  Future<void> _closeHerdrTab({required String tabId}) async {
    // tab CRUD 不可（read-only 明示）では送信しない
    if (!_can(const PaneCapabilities(tabCrud: true))) return;
    final writer = _paneWriter;
    if (writer == null) return;
    try {
      await writer.closeTab(tabId);
      if (!mounted || _isDisposed) return;
      await _syncAfterHerdrMutation(eventLabel: 'close tab sync');
    } catch (e) {
      await _handleHerdrMutationError(e, operationLabel: 'close tab');
    }
  }

  /// SSH接続を切断して前の画面に戻る
  Future<void> _disconnect() async {
    // ポーリングを停止
    _pollTimer?.cancel();
    _treeRefreshTimer?.cancel();

    // stale tmuxProvider 対策（T9）: 切断時に backend 種別を問わず残骸を破棄
    // する（herdr の接続残骸・tmux のアクティブ状態が次回接続へ混入しない）。
    ref.read(tmuxProvider.notifier).clear();

    // 切断前にリサイズしたウィンドウを自動サイズへ戻す
    await _restoreResizedWindows();

    // SSH切断
    await ref.read(sshProvider.notifier).disconnect();

    // 前の画面に戻る
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // inventory: TERM-DIALOG-008
  /// 接続状態インジケーター（レイテンシまたは再接続状態を表示）
  Widget _buildConnectionIndicator(int latency) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colorScheme.outline, width: 1)),
      ),
      child: _sshState.isReconnecting
          // inventory: TERM-DIALOG-010
          ? _buildReconnectingIndicator()
          : _buildLatencyIndicator(latency),
    );
  }

  // inventory: TERM-DIALOG-009
  /// レイテンシ表示
  Widget _buildLatencyIndicator(int latency) {
    // レイテンシに応じた色を決定
    // inventory: LEGACY-0076
    Color indicatorColor;
    if (latency < 100) {
      indicatorColor = DesignColors.success; // 緑: 良好
    } else if (latency < 300) {
      indicatorColor = DesignColors.primary; // シアン: 普通
    } else if (latency < 500) {
      indicatorColor = DesignColors.warning; // オレンジ: やや遅い
    } else {
      indicatorColor = DesignColors.error; // 赤: 遅い
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bolt,
          size: 10,
          color: indicatorColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '${latency}ms',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: indicatorColor.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  /// 再接続中インジケーター
  Widget _buildReconnectingIndicator() {
    final attempt = _sshState.reconnectAttempt;
    final isWaitingForNetwork = _sshState.isWaitingForNetwork;
    final nextRetryAt = _sshState.nextRetryAt;
    final queuedCount = _inputQueue.length;

    // 次回リトライまでの秒数を計算
    // inventory: LEGACY-0077
    String? countdownText;
    if (nextRetryAt != null && !isWaitingForNetwork) {
      final remaining = nextRetryAt.difference(DateTime.now()).inSeconds;
      if (remaining > 0) {
        countdownText = '${remaining}s';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // スピナーまたは圏外アイコン
        if (isWaitingForNetwork)
          Icon(
            Icons.signal_wifi_off,
            size: 12,
            color: DesignColors.warning.withValues(alpha: 0.8),
          )
        else
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: DesignColors.warning.withValues(alpha: 0.8),
            ),
          ),
        const SizedBox(width: 6),

        // ステータステキスト
        Text(
          isWaitingForNetwork
              ? 'Offline'
              : 'Reconnecting${attempt > 1 ? ' ($attempt)' : ''}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: DesignColors.warning.withValues(alpha: 0.8),
          ),
        ),

        // カウントダウン
        if (countdownText != null) ...[
          const SizedBox(width: 4),
          Text(
            countdownText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: DesignColors.textMuted,
            ),
          ),
        ],

        // キューイング状態
        if (queuedCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: DesignColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$queuedCount chars',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.primary,
              ),
            ),
          ),
        ],

        // 今すぐ再接続ボタン
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            ref.read(sshProvider.notifier).reconnectNow();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: DesignColors.warning.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.warning,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// キーを PaneWriter 経由で送信（T8）
  ///
  /// [key] 送信するキー
  /// [literal] trueの場合はリテラル送信（sendText / tmux send-keys -l）
  Future<void> _sendKey(String key, {bool literal = true}) async {
    // テキスト送信不可（read-only）では送信しない。非リテラル（特殊キー）は
    // 特殊キー送信能力（sendKeys）で判定する。
    if (literal ? !_canSendText : !_canSendSpecialKey) return;
    final sshClient = ref.read(sshProvider.notifier).client;

    // 接続が切れている場合はキューに追加（リテラルの場合のみ）
    if (sshClient == null || !sshClient.isConnected) {
      if (literal) {
        final wasOverflow = _inputQueue.isOverflow;
        _inputQueue.enqueue(key);
        if (!wasOverflow && _inputQueue.isOverflow && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Input queue is full; some keystrokes may be lost.',
              ),
            ),
          );
        }
        if (mounted) setState(() {}); // キューイング状態を更新
      }
      return;
    }

    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      if (literal) {
        await writer.sendText(paneId, key);
      } else {
        await writer.sendKey(paneId, key);
      }
      _boostPolling();
    } on HerdrCommandException catch (e) {
      // 防御的（Q-07 の全キー送信経路により通常は発生しない・R9）:
      // `invalid_key` のみ分類通知し、それ以外は従来どおり静かに無視する。
      if (isHerdrInvalidKey(e)) {
        _showHerdrInvalidKeySnackBar();
      }
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  /// tmux copy-modeに入る
  Future<void> _enterTmuxCopyMode() async {
    // copy-mode 不可（read-only）では使わない（履歴は直接取得する）
    if (!_canCopyMode) return;
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;
    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;
    try {
      await tmuxFacade.enterCopyModeNoWait(sshClient.tmuxExecutor, target);
      _boostPolling();
    } catch (_) {}
  }

  /// tmux copy-modeを終了
  Future<void> _cancelTmuxCopyMode() async {
    // copy-mode 不可（read-only）では使わない
    if (!_canCopyMode) return;
    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;
    final target = ref.read(tmuxProvider.notifier).currentTarget;
    if (target == null) return;
    try {
      await tmuxFacade.cancelCopyModeNoWait(sshClient.tmuxExecutor, target);
      _boostPolling();
    } catch (_) {}
  }

  /// tmux特殊キーを PaneWriter 経由で送信（Ctrl+C, Escape等・T8）
  ///
  /// herdr では `HerdrPaneWriter.sendKey` が [PaneKeyMap] の全キー送信経路
  /// （Q-07: send-keys 受理 / send-text エスケープ / send-text 制御文字）を
  /// 適用するため、**「送信できないキー」は存在しない**。万一 `invalid_key` が
  /// 返った場合のみ防御的に SnackBar 通知する（T19・R9。通常は発生しない）。
  Future<void> _sendSpecialKey(String tmuxKey) async {
    // 特殊キー送信不可（read-only）では送信しない
    if (!_canSendSpecialKey) return;
    final sshClient = ref.read(sshProvider.notifier).client;

    // 特殊キーは接続が切れている場合は送信しない（キューしない）
    if (sshClient == null || !sshClient.isConnected) return;

    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      // PaneWriter 経由（tmux: send-keys / herdr: PaneKeyMap の送信経路）
      await writer.sendKey(paneId, tmuxKey);
      _boostPolling();
    } on HerdrCommandException catch (e) {
      // 防御的（Q-07 の全キー送信経路により通常は発生しない・R9）:
      // `invalid_key` のみ分類通知し、それ以外は従来どおり静かに無視する。
      if (isHerdrInvalidKey(e)) {
        _showHerdrInvalidKeySnackBar();
      }
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）
    }
  }

  ProviderSubscription? _imageTransferSub;

  // inventory: TERM-FILE-004
  /// 画像転送の状態リスナーを初期化（1回のみ）
  void _ensureImageTransferListener() {
    if (_imageTransferSub != null) return;
    _imageTransferSub = ref.listenManual(imageTransferProvider, (
      prev,
      next,
    ) async {
      if (next.phase == ImageTransferPhase.confirming &&
          next.pickedImageBytes != null &&
          next.pendingRemotePath != null &&
          (prev?.phase == ImageTransferPhase.picking)) {
        if (!mounted) return;
        final settings = ref.read(settingsProvider);
        final options = await ImageTransferConfirmDialog.show(
          context,
          remotePath: next.pendingRemotePath!,
          imageBytes: next.pickedImageBytes!,
          imageName: next.pickedImageName,
          settings: settings,
        );

        if (options != null) {
          final uploadedPath = await ref
              .read(imageTransferProvider.notifier)
              .confirmAndUpload(options: options);

          if (uploadedPath != null && mounted) {
            // inventory: TERM-FILE-003
            await _injectImagePath(uploadedPath, options);
          }
        } else {
          ref.read(imageTransferProvider.notifier).cancel();
        }
      }

      if (next.phase == ImageTransferPhase.error && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Image transfer failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      if (next.phase == ImageTransferPhase.completed &&
          next.lastUploadedPath != null &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded: ${next.lastUploadedPath}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  /// ファイルブラウザを開く
  void _handleFileBrowser() {
    final activePaneId = ref.read(tmuxProvider).activePaneId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileBrowserScreen(
          connectionId: widget.connectionId,
          paneId: activePaneId,
        ),
      ),
    );
  }

  /// 画像転送フローを開始
  void _handleImageTransfer() {
    _ensureImageTransferListener();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(imageTransferProvider.notifier)
                    .pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(imageTransferProvider.notifier)
                    .pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// アップロード済み画像のパスをターミナルに注入（T8: PaneWriter 経由）
  Future<void> _injectImagePath(
    String remotePath,
    ImageTransferOptions options,
  ) async {
    // 画像転送不可（read-only・herdr は Phase 2 まで capability false）では
    // 送信しない。
    if (!_can(const PaneCapabilities(imageTransfer: true))) return;

    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    // パスフォーマット適用（optionsから取得）
    final formattedPath = options.pathFormat.replaceAll('{path}', remotePath);

    if (writer is TmuxPaneWriter) {
      // tmux: 既存の bracketed paste 経路（後方互換・コマンド文字列不変）
      await writer.sendBracketedPaste(
        paneId: paneId,
        path: formattedPath,
        bracketedPaste: options.bracketedPaste,
        autoEnter: options.autoEnter,
      );
    } else {
      // herdr: send-text でパス送信（Q-06・Phase 2 で有効化）
      await writer.pasteText(paneId, formattedPath);
    }

    _boostPolling();
  }

  void _showInputDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _InputDialogContent(
        initialValue: _savedCommandInput,
        onValueChanged: (value) {
          // 入力内容をリアルタイムで保存
          _savedCommandInput = value;
        },
        onSend: (value) async {
          // inventory: TERM-INPUT-008
          await _sendMultilineText(value);
          // 送信成功したら入力内容をクリア
          _savedCommandInput = '';
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    ).then((_) {
      _scrollToBottomKey.currentState?.show();
    });
  }

  /// Sends multi-line text to the active pane via PaneWriter (T8).
  ///
  /// tmux: `load-buffer` + `paste-buffer`（bracketed paste・原子送信）。
  /// herdr: `send-text`（Q-06・Phase 2 で有効化）。
  Future<void> _sendMultilineText(String text) async {
    if (text.isEmpty) return;

    // paste 不可（read-only・herdr は Phase 1 で capability false）では送信しない
    if (!_can(const PaneCapabilities(paste: true))) return;

    final writer = _paneWriter;
    final paneId = _targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    // Pass text as-is: bracketed paste preserves whatever newlines are
    // present. The caller decides whether a trailing Enter is desired.
    final payload = text;

    final sshClient = ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      // Multi-line paste via send-keys would re-introduce the race condition
      // fixed by PR #51. Reject the operation and ask the user to retry
      // once connected rather than silently queuing via the legacy path.
      if (text.contains('\n') && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Multi-line send requires a live connection; please retry.',
            ),
          ),
        );
      } else {
        _inputQueue.enqueue(text);
        if (mounted) setState(() {});
      }
      return;
    }

    try {
      await writer.pasteText(paneId, payload);
      _boostPolling();
    } catch (e) {
      debugPrint('[Terminal] paste-buffer send failed: $e');
      // TODO: surface a SnackBar after repeated failures.
    }
  }

  /// 右上のペインインジケーター
  ///
  /// ペインの実際のサイズ比率に基づいてレイアウトを表示
  ///
  /// 分割不可（`!_canSplitPane`・read-only）では表示しない。タップで
  /// [_showPaneSelector] → [_selectPane] / [_splitPane] / [_killPane]
  /// （mutation 発行）に到達するため、herdr 接続中に stale な tmuxProvider
  /// 状態があっても mutation が発行されないよう本メソッド先頭でガードする
  /// （M2）。
  Widget _buildPaneIndicator(TmuxState tmuxState) {
    if (!_canSplitPane) return const SizedBox.shrink();

    final window = tmuxState.activeWindow;
    final panes = window?.panes ?? [];
    final activePaneId = tmuxState.activePaneId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // 1ペイン（または0）ではミニマップは情報量ゼロ。右上に重なって内容
    // （プロンプトやスクロール位置表示など）を隠すだけなので表示しない。
    if (panes.length <= 1) {
      return const SizedBox.shrink();
    }

    // インジケーター全体のサイズ
    const double indicatorSize = 48.0;

    return GestureDetector(
      onTap: () => _showPaneSelector(tmuxState),
      child: Opacity(
        opacity: 0.5,
        child: Container(
          width: indicatorSize,
          height: indicatorSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: Size(indicatorSize - 4, indicatorSize - 4),
            painter: _PaneLayoutPainter(
              panes: panes,
              activePaneId: activePaneId,
              activeColor: colorScheme.primary,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// ペインレイアウトを描画するCustomPainter
///
/// tmuxから取得したpane_left/pane_topを使用して
/// 実際のレイアウトを正確に再現する
class _PaneLayoutPainter extends CustomPainter {
  final List<TmuxPane> panes;
  final String? activePaneId;
  // inventory: LEGACY-0080
  final Color activeColor;
  final bool isDark;

  _PaneLayoutPainter({
    required this.panes,
    this.activePaneId,
    required this.activeColor,
    required this.isDark,
  });

  @override
  // inventory: LEGACY-0082
  void paint(Canvas canvas, Size size) {
    if (panes.isEmpty) return;

    // ウィンドウ全体のサイズを計算（全ペインを含む範囲）
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    if (maxRight == 0 || maxBottom == 0) return;

    // スケール係数を計算
    final scaleX = size.width / maxRight;
    final scaleY = size.height / maxBottom;
    final gap = 1.0;

    // ペインごとに描画
    for (final pane in panes) {
      final isActive = pane.id == activePaneId;

      // 実際の位置とサイズからRectを計算
      final left = pane.left * scaleX;
      final top = pane.top * scaleY;
      final width = pane.width * scaleX - gap;
      final height = pane.height * scaleY - gap;

      final rect = Rect.fromLTWH(left, top, width, height);

      // 背景
      final bgPaint = Paint()
        ..color = isActive
            ? activeColor.withValues(alpha: 0.3)
            : (isDark ? Colors.black45 : Colors.grey.shade300);
      canvas.drawRect(rect, bgPaint);

      // 枠線
      final borderPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark ? Colors.white30 : Colors.grey.shade500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.5 : 1.0;
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  // inventory: LEGACY-0083
  bool shouldRepaint(covariant _PaneLayoutPainter oldDelegate) {
    return panes != oldDelegate.panes ||
        activePaneId != oldDelegate.activePaneId ||
        activeColor != oldDelegate.activeColor ||
        isDark != oldDelegate.isDark;
  }
}

/// ペインレイアウトをインタラクティブに表示するウィジェット
///
/// 各ペインをタップで選択可能。ペイン番号も表示。
class _PaneLayoutVisualizer extends StatefulWidget {
  final List<TmuxPane> panes;
  final String? activePaneId;
  // inventory: LEGACY-0084
  final void Function(String paneId) onPaneSelected;
  final void Function(String paneId, SplitDirection direction)?
  onSplitRequested;

  const _PaneLayoutVisualizer({
    required this.panes,
    this.activePaneId,
    required this.onPaneSelected,
    this.onSplitRequested,
  });

  @override
  State<_PaneLayoutVisualizer> createState() => _PaneLayoutVisualizerState();
}

class _PaneLayoutVisualizerState extends State<_PaneLayoutVisualizer> {
  /// 分割モードが有効なペインID（nullなら通常表示）
  String? _splitModeActivePaneId;

  @override
  Widget build(BuildContext context) {
    if (widget.panes.isEmpty) return const SizedBox.shrink();

    // ウィンドウ全体のサイズを計算（全ペインを含む範囲）
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in widget.panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    if (maxRight == 0 || maxBottom == 0) return const SizedBox.shrink();

    // アスペクト比を計算
    final aspectRatio = maxRight / maxBottom;

    return Container(
      padding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: aspectRatio.clamp(0.5, 3.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth;
            final containerHeight = constraints.maxHeight;

            // スケール係数を計算
            final scaleX = containerWidth / maxRight;
            final scaleY = containerHeight / maxBottom;
            const gap = 2.0;

            return Stack(
              children: widget.panes.map((pane) {
                final isActive = pane.id == widget.activePaneId;
                final isSplitMode = _splitModeActivePaneId == pane.id;

                // 実際の位置とサイズからRectを計算
                final left = pane.left * scaleX;
                final top = pane.top * scaleY;
                final width = pane.width * scaleX - gap;
                final height = pane.height * scaleY - gap;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: GestureDetector(
                    key: ValueKey('terminal-pane-layout-${pane.id}'),
                    onTap: () => _handlePaneTap(pane, isActive, width, height),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isActive
                            ? DesignColors.primary.withValues(alpha: 0.3)
                            : Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? DesignColors.primary
                              : Colors.white.withValues(alpha: 0.3),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: _buildPaneContent(
                          pane: pane,
                          isActive: isActive,
                          isSplitMode: isSplitMode,
                          width: width,
                          height: height,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  /// インライン分割アイコンが収まる最小サイズ
  static const _minInlineWidth = 80.0;
  static const _minInlineHeight = 60.0;

  void _handlePaneTap(
    TmuxPane pane,
    bool isActive,
    double width,
    double height,
  ) {
    if (isActive && widget.onSplitRequested != null) {
      if (width < _minInlineWidth || height < _minInlineHeight) {
        // 小さいペイン → モーダルダイアログで分割方向を選択
        _showSplitDialog(pane);
      } else {
        // 大きいペイン → インラインで分割モード切り替え
        setState(() {
          _splitModeActivePaneId = _splitModeActivePaneId == pane.id
              ? null
              : pane.id;
        });
      }
    } else {
      // 非アクティブペインをタップ → ペイン選択
      widget.onPaneSelected(pane.id);
    }
  }

  void _showSplitDialog(TmuxPane pane) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            'Split Pane ${pane.index}',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CustomPaint(
                  size: const Size(24, 24),
                  painter: _SplitRightIconPainter(color: colorScheme.primary),
                ),
                title: const Text('Split Right'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  widget.onSplitRequested!(pane.id, SplitDirection.horizontal);
                },
              ),
              ListTile(
                leading: CustomPaint(
                  size: const Size(24, 24),
                  painter: _SplitDownIconPainter(color: colorScheme.primary),
                ),
                title: const Text('Split Down'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  widget.onSplitRequested!(pane.id, SplitDirection.vertical);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaneContent({
    required TmuxPane pane,
    required bool isActive,
    required bool isSplitMode,
    required double width,
    required double height,
  }) {
    if (isActive && isSplitMode) {
      // 分割モード: アイコンボタン表示
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${pane.index}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: width > 60 ? 18 : 14,
              fontWeight: FontWeight.w700,
              color: DesignColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSplitButton(
                key: ValueKey('terminal-split-right-${pane.id}'),
                painter: _SplitRightIconPainter(color: DesignColors.primary),
                onTap: () => widget.onSplitRequested!(
                  pane.id,
                  SplitDirection.horizontal,
                ),
              ),
              const SizedBox(width: 8),
              _buildSplitButton(
                key: ValueKey('terminal-split-down-${pane.id}'),
                painter: _SplitDownIconPainter(color: DesignColors.primary),
                onTap: () =>
                    widget.onSplitRequested!(pane.id, SplitDirection.vertical),
              ),
            ],
          ),
        ],
      );
    }

    // 通常表示
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${pane.index}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: width > 60 ? 18 : 14,
            fontWeight: FontWeight.w700,
            color: isActive
                ? DesignColors.primary
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
        if (isActive &&
            widget.onSplitRequested != null &&
            width > 60 &&
            height > 40) ...[
          const SizedBox(height: 2),
          Text(
            'Tap to split',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              color: DesignColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ] else if (width > 80 && height > 50) ...[
          const SizedBox(height: 2),
          Text(
            '${pane.width}x${pane.height}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSplitButton({
    Key? key,
    required CustomPainter painter,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: DesignColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: DesignColors.primary.withValues(alpha: 0.4),
            ),
          ),
          child: CustomPaint(size: const Size(20, 20), painter: painter),
        ),
      ),
    );
  }
}

/// 右分割アイコン: 左に既存ペイン、右に新ペイン（+マーク付き）
class _SplitRightIconPainter extends CustomPainter {
  // inventory: LEGACY-0085
  final Color color;

  _SplitRightIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = w * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        // inventory: LEGACY-0086
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央縦線）
    // inventory: LEGACY-0087
    canvas.drawLine(Offset(mid, pad), Offset(mid, h - pad), paint);

    // 右側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = mid + (w - pad - mid) / 2;
    final cy = h / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(
      Offset(cx - plusSize, cy),
      Offset(cx + plusSize, cy),
      plusPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - plusSize),
      Offset(cx, cy + plusSize),
      plusPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitRightIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 下分割アイコン: 上に既存ペイン、下に新ペイン（+マーク付き）
class _SplitDownIconPainter extends CustomPainter {
  final Color color;

  _SplitDownIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final pad = w * 0.1;
    final mid = h * 0.5;

    // 外枠
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2),
        const Radius.circular(2),
      ),
      paint,
    );

    // 分割線（中央横線）
    canvas.drawLine(Offset(pad, mid), Offset(w - pad, mid), paint);

    // 下側に+マーク
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final cx = w / 2;
    final cy = mid + (h - pad - mid) / 2;
    final plusSize = w * 0.12;
    canvas.drawLine(
      Offset(cx - plusSize, cy),
      Offset(cx + plusSize, cy),
      plusPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - plusSize),
      Offset(cx, cy + plusSize),
      plusPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitDownIconPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 入力ダイアログのコンテンツ（複数行対応、Shift+Enterで改行）
class _InputDialogContent extends StatefulWidget {
  // inventory: LEGACY-0088
  final String initialValue;
  final void Function(String value) onValueChanged;
  final Future<void> Function(String value) onSend;

  const _InputDialogContent({
    this.initialValue = '',
    required this.onValueChanged,
    required this.onSend,
  });

  @override
  State<_InputDialogContent> createState() => _InputDialogContentState();
}

class _InputDialogContentState extends State<_InputDialogContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    // キーイベントをハンドルするためにonKeyEventを設定
    _focusNode.onKeyEvent = _handleKeyEvent;
    // テキスト変更時に親へ通知
    _controller.addListener(_onTextChanged);
    // 自動フォーカス（カーソルを末尾に）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // カーソルを末尾に移動
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onTextChanged() {
    widget.onValueChanged(_controller.text);
  }

  /// Returns true when an IME composition range is open.
  bool get _isImeActive {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.onKeyEvent = null;
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// キーイベントをハンドル（Shift+Enterで改行、Enterで送信）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_isImeActive) {
        return KeyEventResult.ignored;
      }
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      if (isShiftPressed) {
        // Shift+Enter: 改行を挿入
        _insertNewline();
        return KeyEventResult.handled;
      } else {
        // Enterのみ: 送信
        _handleSend();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 現在のカーソル位置に改行を挿入
  void _insertNewline() {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\n');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  Future<void> _handleSend() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSend(_controller.text);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Enter Command',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.keyBackground
                      : DesignColors.keyBackgroundLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Shift+Enter: 改行',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: isDark
                        ? DesignColors.textMuted
                        : DesignColors.textMutedLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 200, // 最大高さを制限してスクロール可能に
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              maxLines: null, // 無制限にして内部スクロール
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline, // ペースト時の複数行対応
              style: GoogleFonts.jetBrainsMono(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Type your command... (Enter to send)',
                hintStyle: GoogleFonts.jetBrainsMono(
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
                filled: true,
                fillColor: isDark
                    ? DesignColors.inputDark
                    : DesignColors.inputLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _handleSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          'Execute',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// ウィンドウ名入力ダイアログ
class _NewWindowDialog extends StatefulWidget {
  // inventory: LEGACY-0089
  final List<String> existingWindowNames;

  const _NewWindowDialog({required this.existingWindowNames});

  @override
  State<_NewWindowDialog> createState() => _NewWindowDialogState();
}

class _NewWindowDialogState extends State<_NewWindowDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateWindowName(String? value) {
    if (value == null || value.isEmpty) {
      return null; // 空入力はtmuxデフォルト名で許容
    }
    if (value.length > 50) {
      return 'Window name must be 50 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - and _ allowed';
    }
    if (widget.existingWindowNames.contains(value)) {
      return 'Window "$value" already exists';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        'New Window',
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: 'Window Name',
            hintText: 'Leave empty for default',
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
            filled: true,
            fillColor: isDark
                ? DesignColors.inputDark
                : DesignColors.inputLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateWindowName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

/// herdr の pane / tab ラベル入力ダイアログ（Q-02/Q-05: rename 解禁）。
///
/// tmux の [RenameWindowDialog] と違い、herdr のラベルは自由文字列
/// （`[a-zA-Z0-9_-]` 制約・重複チェックを持たない）ため、汎用のテキスト入力
/// ダイアログとして pane（`herdr pane rename`）と tab（`herdr tab rename`）の
/// 両方で共用する。空入力（trim 後）は無効。
class _HerdrLabelInputDialog extends StatefulWidget {
  /// ダイアログタイトル（'Rename Pane' / 'Rename Tab'）。
  final String title;

  /// 入力欄のラベル（'Pane Label' / 'Tab Label'）。
  final String labelText;

  /// 入力欄のヒント（任意）。
  final String? hintText;

  /// 初期値（tab は現在ラベル。pane は domain にラベルが無いため空）。
  final String initialValue;

  /// 確定ボタンの文言（'Rename'）。
  final String confirmLabel;

  const _HerdrLabelInputDialog({
    required this.title,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
    required this.confirmLabel,
  });

  @override
  State<_HerdrLabelInputDialog> createState() => _HerdrLabelInputDialogState();
}

class _HerdrLabelInputDialogState extends State<_HerdrLabelInputDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateLabel(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Label cannot be empty';
    }
    if (value.length > 100) {
      return 'Label must be 100 characters or less';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.title,
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
            filled: true,
            fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateLabel,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

// ====================================================================
// _ResizePaneChooserDialog
// ====================================================================

/// リサイズ対象ペインをグラフィカルに選択するダイアログ
class _ResizePaneChooserDialog extends StatefulWidget {
  final List<TmuxPane> panes;
  final String? activePaneId;
  final void Function(TmuxPane selectedPane) onResize;

  const _ResizePaneChooserDialog({
    required this.panes,
    this.activePaneId,
    required this.onResize,
  });

  @override
  State<_ResizePaneChooserDialog> createState() =>
      _ResizePaneChooserDialogState();
}

class _ResizePaneChooserDialogState extends State<_ResizePaneChooserDialog> {
  late String? _selectedPaneId;

  @override
  void initState() {
    super.initState();
    // デフォルト: 現在アクティブなペインが選択状態
    _selectedPaneId = widget.activePaneId;
  }

  TmuxPane? get _selectedPane {
    if (_selectedPaneId == null) return null;
    try {
      return widget.panes.firstWhere((p) => p.id == _selectedPaneId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPane;

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Resize Pane',
        style: TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ペインレイアウトのグリッドプレビュー
              _buildSelectablePaneGrid(),
              const SizedBox(height: 12),
              // 選択中のペイン情報
              if (selected != null)
                Text(
                  'Selected: Pane ${selected.index} (${selected.width}x${selected.height})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                )
              else
                const Text(
                  'Tap a pane to select',
                  style: TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected != null ? () => widget.onResize(selected) : null,
          style: FilledButton.styleFrom(backgroundColor: DesignColors.primary),
          child: const Text('Resize'),
        ),
      ],
    );
  }

  Widget _buildSelectablePaneGrid() {
    if (widget.panes.isEmpty) return const SizedBox.shrink();

    // ウィンドウ全体のサイズを計算
    int maxRight = 0;
    int maxBottom = 0;
    for (final pane in widget.panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxRight == 0) maxRight = 1;
    if (maxBottom == 0) maxBottom = 1;

    return Container(
      height: 150,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: DesignColors.canvasDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DesignColors.borderDark),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const pad = 4.0;
          final areaW = constraints.maxWidth - pad * 2;
          final areaH = constraints.maxHeight - pad * 2;
          final scaleX = areaW / maxRight;
          final scaleY = areaH / maxBottom;

          return Padding(
            padding: const EdgeInsets.all(pad),
            child: Stack(
              children: [
                SizedBox(width: areaW, height: areaH),
                ...widget.panes.map((pane) {
                  final isSelected = pane.id == _selectedPaneId;
                  final left = pane.left * scaleX;
                  final top = pane.top * scaleY;
                  final width = (pane.width * scaleX).clamp(20.0, areaW - left);
                  final height = (pane.height * scaleY).clamp(
                    14.0,
                    areaH - top,
                  );

                  return Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: GestureDetector(
                      key: ValueKey('terminal-resize-pane-${pane.id}'),
                      onTap: () => setState(() => _selectedPaneId = pane.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? DesignColors.primary.withValues(alpha: 0.25)
                              : DesignColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? DesignColors.primary
                                : DesignColors.borderDark,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '${pane.index}\n${pane.width}x${pane.height}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? DesignColors.primary
                                    : DesignColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ====================================================================
// _ResizeWindowChooserDialog
// ====================================================================

/// リサイズ対象ウィンドウをグラフィカルに選択するダイアログ
class _ResizeWindowChooserDialog extends StatefulWidget {
  // inventory: LEGACY-0091
  final List<TmuxWindow> windows;
  // inventory: LEGACY-0092
  final int? activeWindowIndex;
  final void Function(TmuxWindow selectedWindow) onResize;

  const _ResizeWindowChooserDialog({
    required this.windows,
    this.activeWindowIndex,
    required this.onResize,
  });

  @override
  State<_ResizeWindowChooserDialog> createState() =>
      _ResizeWindowChooserDialogState();
}

class _ResizeWindowChooserDialogState
    extends State<_ResizeWindowChooserDialog> {
  late int? _selectedWindowIndex;

  @override
  void initState() {
    super.initState();
    // デフォルト: 現在アクティブなウィンドウが選択状態
    _selectedWindowIndex = widget.activeWindowIndex;
  }

  TmuxWindow? get _selectedWindow {
    if (_selectedWindowIndex == null) return null;
    try {
      return widget.windows.firstWhere((w) => w.index == _selectedWindowIndex);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedWindow;

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Resize Window',
        style: TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ウィンドウカード一覧
              ...widget.windows.map((window) {
                final isSelected = window.index == _selectedWindowIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildWindowCard(window, isSelected),
                );
              }),
              const SizedBox(height: 4),
              // 選択中のウィンドウ情報
              if (selected != null) ...[
                Text(
                  'Selected: ${selected.name} (${_windowSizeString(selected)})',
                  style: const TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
              ] else
                const Text(
                  'Tap a window to select',
                  style: TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected != null ? () => widget.onResize(selected) : null,
          style: FilledButton.styleFrom(backgroundColor: DesignColors.primary),
          child: const Text('Resize'),
        ),
      ],
    );
  }

  String _windowSizeString(TmuxWindow window) {
    final panes = window.panes;
    if (panes.isEmpty) return '?x?';
    final cols = panes
        .map((p) => p.left + p.width)
        .reduce((a, b) => a > b ? a : b);
    final rows = panes
        .map((p) => p.top + p.height)
        .reduce((a, b) => a > b ? a : b);
    return '${cols}x$rows';
  }

  Widget _buildWindowCard(TmuxWindow window, bool isSelected) {
    final panes = window.panes;
    return GestureDetector(
      key: ValueKey('terminal-resize-window-${window.index}'),
      onTap: () => setState(() => _selectedWindowIndex = window.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: DesignColors.canvasDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? DesignColors.primary : DesignColors.borderDark,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ウィンドウヘッダー
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignColors.primary.withValues(alpha: 0.15)
                    : DesignColors.surfaceDark,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Text(
                '${window.name}  ${_windowSizeString(window)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? DesignColors.primary
                      : DesignColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // ペインレイアウトプレビュー
            if (panes.isNotEmpty)
              SizedBox(height: 60, child: _buildPaneLayoutPreview(panes)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaneLayoutPreview(List<TmuxPane> panes) {
    int maxRight = 0;
    int maxBottom = 0;
    for (final p in panes) {
      final right = p.left + p.width;
      final bottom = p.top + p.height;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    if (maxRight == 0) maxRight = 1;
    if (maxBottom == 0) maxBottom = 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth - 8;
        final areaH = constraints.maxHeight - 8;

        return Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              SizedBox(width: areaW, height: areaH),
              ...panes.map((pane) {
                final left = (pane.left / maxRight) * areaW;
                final top = (pane.top / maxBottom) * areaH;
                final width = (pane.width / maxRight) * areaW;
                final height = (pane.height / maxBottom) * areaH;

                return Positioned(
                  left: left,
                  top: top,
                  width: width.clamp(16.0, areaW),
                  height: height.clamp(10.0, areaH),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: DesignColors.borderDark,
                        width: 1,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// Factory that exposes [_InputDialogContent] for widget tests.
///
/// Production code must never call this function.
@visibleForTesting
// inventory: TERM-SCREEN-004
Widget buildInputDialogContentForTesting({
  String initialValue = '',
  required void Function(String value) onValueChanged,
  required Future<void> Function(String value) onSend,
}) {
  return _InputDialogContent(
    initialValue: initialValue,
    onValueChanged: onValueChanged,
    onSend: onSend,
  );
}

/// [TmuxState] のツリーから pane ID に一致する [TmuxPane] を引き当てる（T2）。
TmuxPane? _findTmuxPaneIn(TmuxState tmuxState, String paneId) {
  for (final session in tmuxState.sessions) {
    for (final window in session.windows) {
      for (final pane in window.panes) {
        if (pane.id == paneId) return pane;
      }
    }
  }
  return null;
}

/// tmux の pane 表示名（title → currentCommand → 'Pane N' の既存ルール・Q1）。
///
/// 既存 3 セレクタ（L3604-3608 相当）のタイトル優先ルールを共通シート向けに
/// 移設したもの。ツリーから引き当てできない pane ID は 'Pane 0' を返す
/// （防御的フォールバック。実際にはシートの pane は同一ツリー由来のため不発）。
String _tmuxPaneLabelFor(TmuxState tmuxState, String paneId) {
  final pane = _findTmuxPaneIn(tmuxState, paneId);
  if (pane == null) return 'Pane 0';
  final title = pane.title;
  if (title != null && title.isNotEmpty) return title;
  final command = pane.currentCommand;
  if (command != null && command.isNotEmpty) return command;
  return 'Pane ${pane.index}';
}

/// tmux の pane サブタイトル（'WxH'・M-2）。引き当て不可なら null。
String? _tmuxPaneSubtitleFor(TmuxState tmuxState, MultiplexerPane pane) {
  return _findTmuxPaneIn(tmuxState, pane.id)?.sizeString;
}

/// 共通 domain の [MultiplexerWindow] に一致する [TmuxWindow] をツリー全体から
/// 引き当てる（ID 優先、次に index + name）。
TmuxWindow? _tmuxWindowInTree(TmuxState tmuxState, MultiplexerWindow window) {
  for (final session in tmuxState.sessions) {
    for (final tmuxWindow in session.windows) {
      if (window.id != null && tmuxWindow.id == window.id) return tmuxWindow;
      if (tmuxWindow.index == window.index &&
          tmuxWindow.name == window.name) {
        return tmuxWindow;
      }
    }
  }
  return null;
}

/// [session] 内で [window] に一致する [TmuxWindow] を引き当てる。
TmuxWindow? _tmuxWindowOf(TmuxSession session, MultiplexerWindow window) {
  for (final tmuxWindow in session.windows) {
    if (window.id != null && tmuxWindow.id == window.id) return tmuxWindow;
    if (tmuxWindow.index == window.index) return tmuxWindow;
  }
  return null;
}

/// セレクタの現在位置（H-1: ハイライト導出用）。
///
/// backend 別に、表示中の session / window / pane の現在位置を保持する。
/// tmux は provider のアクティブ状態（activeSessionName / activeWindowIndex /
/// activeWindowId / activePaneId）を渡し、herdr は表示対象 pane から導出した
/// 値を渡す。フィールドは全て nullable（未確定の段は null）。
class _SelectorContext {
  /// 現在の session 名。
  final String? sessionName;

  /// 現在の session / workspace ID（tmux: "$0" / herdr: "w1"）。
  ///
  /// ハイライト判定（H-1）の一義的な基準。同名ラベル（herdr の "tmp" w3/w4）
  /// の曖昧さはこの ID で解消する。不明（旧データ等）の場合のみ名前一致へ
  /// フォールバックする。
  final String? sessionId;

  /// 現在の window インデックス。
  final int? windowIndex;

  /// 現在の window ID（tmux: "@0" / herdr: "w1:t1"）。
  final String? windowId;

  /// 現在の pane ID（tmux: "%0" / herdr: "w1:p1"）。
  final String? paneId;

  const _SelectorContext({
    this.sessionName,
    this.sessionId,
    this.windowIndex,
    this.windowId,
    this.paneId,
  });
}

/// H-1: セッションのハイライト（[_SelectorContext] の現在位置と照合）。
///
/// 一義的な基準は現在の session ID（[MultiplexerSession.id] ==
/// [_SelectorContext.sessionId]）。現在の session ID が判明している場合は
/// ID ベース判定のみで行い、名前（表示名）一致はしない。これにより同名ラベル
/// の workspace（herdr の "tmp" w3/w4）でも、現在の workspace ID と一致する
/// ものだけがハイライトされる。
///
/// [_SelectorContext.sessionId] が不明（旧データ等）の場合のみ、名前一致と
/// paneId prefix（"w1:" 等）の旧挙動へフォールバックする。
bool _isCurrentSession(MultiplexerSession session, _SelectorContext? current) {
  if (current == null) return false;
  // 一義的な基準: 現在の session ID と一致するか
  final currentSessionId = current.sessionId;
  final sessionId = session.id;
  if (currentSessionId != null && currentSessionId.isNotEmpty) {
    if (sessionId != null && sessionId == currentSessionId) return true;
    // paneId が現在の session に属するか（pane 由来の ID 判定）
    final paneId = current.paneId;
    if (paneId != null && sessionId != null && paneId.startsWith('$sessionId:')) {
      return true;
    }
    return false;
  }
  // フォールバック: sessionId が不明な場合は名前一致（旧挙動）
  if (session.name == current.sessionName) return true;
  final paneId = current.paneId;
  return sessionId != null &&
      paneId != null &&
      paneId.startsWith('$sessionId:');
}

/// H-1: ウィンドウのハイライト（[_SelectorContext] の現在位置と照合）。
///
/// 一義的な基準は現在の window ID（[MultiplexerWindow.id] ==
/// [_SelectorContext.windowId]）。[windowId] が判明している場合は ID 一致のみで
/// 判定し、[windowId] 不明時のみ index フォールバックする（旧挙動）。
bool _isCurrentWindow(MultiplexerWindow window, _SelectorContext? current) {
  if (current == null) return false;
  final currentWindowId = current.windowId;
  if (currentWindowId != null && currentWindowId.isNotEmpty) {
    return window.id == currentWindowId;
  }
  if (window.index == current.windowIndex) return true;
  return false;
}

/// H-1: ペインのハイライト（[_SelectorContext] の現在位置と照合）。
bool _isCurrentPane(MultiplexerPane pane, _SelectorContext? current) =>
    pane.id == current?.paneId;

/// 共通 1 段セレクタシート（選択即閉じ・元 tmux 挙動）。
///
/// 受け取った [children]（呼び出し側が構築済みのタイル）を 1 階層だけ表示する。
/// タイルの onTap は呼び出し側が「pop → コールバック」を担い、このシート自体は
/// ドリルダウン状態を持たない。3 種のシート（Select Session / Select Window /
/// Select Pane）は [title] / [icon] / [children] / [headerActions] の違いで
/// 1 クラスが表現する（M-6: タイトル統一）。
///
/// [headerActions] はヘッダー右側の mutation ボタン（tmux の非 read-only 時のみ
/// 呼び出し側が構築）。[top] は一覧の上部に表示するウィジェット（tmux pane
/// シートの [_PaneLayoutVisualizer]）。ハイライト（H-1）は [_SelectorContext]
/// から呼び出し側がタイルへ渡す。
class _MultiplexerSelectorSheet extends StatefulWidget {
  /// シートのタイトル（'Select Session' / 'Select Window' / 'Select Pane'）。
  final String title;

  /// シートのヘッダーアイコン。
  final IconData icon;

  /// 一覧に表示するタイル（呼び出し側が構築）。
  final List<Widget> children;

  /// ヘッダー右側の mutation ボタン（無ければ空）。
  final List<Widget> headerActions;

  /// 一覧の上部に表示するウィジェット（無ければ null）。
  final Widget? top;

  /// 非同期で一覧を取得する（バグ3 根本対応: 即時 open + loading/data/error）。
  ///
  /// 戻り値は (children, headerActions) のペア。データロード後にヘッダーの
  /// mutation ボタン（New Tab / Split / Rename / Zoom / Resize）も確定させる
  /// ため、headerActions も同時に返す（tooltip を維持・バグ3 根本対応）。
  final Future<_SelectorContent> Function()? asyncContent;

  /// 取得失敗時の Retry コールバック（無ければ null）。
  final VoidCallback? retry;

  const _MultiplexerSelectorSheet({
    required this.title,
    required this.icon,
    this.headerActions = const [],
    this.top,
    this.asyncContent,
    this.retry,
    required this.children,
  });

  @override
  State<_MultiplexerSelectorSheet> createState() =>
      _MultiplexerSelectorSheetState();
}

/// 非同期ロードされたセレクタの内容（一覧 + ヘッダー action）。
class _SelectorContent {
  final List<Widget> children;
  final List<Widget> headerActions;
  const _SelectorContent({
    this.children = const [],
    this.headerActions = const [],
  });
}

class _MultiplexerSelectorSheetState extends State<_MultiplexerSelectorSheet> {
  /// ロード結果（null なら loading・エラーは [_loadError] で表現）。
  _SelectorContent? _content;
  Object? _loadError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.asyncContent != null) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _loading = true;
      _loadError = null;
      _content = null;
    });
    widget.asyncContent!().then(
      (content) {
        if (!mounted) return;
        setState(() {
          _content = content;
          _loading = false;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _loadError = e;
          _loading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasTop = widget.top != null;
    final maxHeight =
        MediaQuery.of(context).size.height * (hasTop ? 0.7 : 0.6);

    final loader = widget.asyncContent;
    if (loader != null) {
      final headerActions = _content?.headerActions ?? widget.headerActions;
      final body = _loading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
              ? _buildError(context, colorScheme)
              : ListView(
                  shrinkWrap: true,
                  children: _content?.children ?? const <Widget>[],
                );
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, colorScheme, headerActions),
            Divider(height: 1, color: colorScheme.outline),
            if (widget.top != null) ...[
              widget.top!,
              Divider(height: 1, color: colorScheme.outline),
            ],
            Flexible(child: body),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    // 従来の同期 children 表示。
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, colorScheme, widget.headerActions),
          Divider(height: 1, color: colorScheme.outline),
          if (widget.top != null) ...[
            widget.top!,
            Divider(height: 1, color: colorScheme.outline),
          ],
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: widget.children,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    List<Widget> headerActions,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(widget.icon, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          if (headerActions.isNotEmpty) ...[
            const Spacer(),
            ...headerActions,
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(height: 8),
          Text('Failed to load', style: TextStyle(color: colorScheme.onSurface)),
          const SizedBox(height: 8),
          if (widget.retry != null)
            FilledButton(
              onPressed: () {
                widget.retry!();
                _load();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// READ ONLY バナー（herdr 表示用）。
///
/// 特殊キーバー（SpecialKeysBar）の代わりに表示し、読み取り専用であることを
/// 示す。キー入力が無効なため、デザイン上の注意書きのみを担う。
class _ReadOnlyBanner extends StatelessWidget {
  final bool isDark;

  const _ReadOnlyBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark
          ? DesignColors.connectingCardDark.withValues(alpha: 0.4)
          : DesignColors.connectingCardLight,
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: isDark
                ? DesignColors.connectedCardTextDark
                : DesignColors.connectedCardTextLight,
          ),
          const SizedBox(width: 8),
          Text(
            'READ ONLY — viewing only',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? DesignColors.connectedCardTextDark
                  : DesignColors.connectedCardTextLight,
            ),
          ),
          const Spacer(),
          Text(
            'Herdr',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
