/// herdr caret / リンク読取の合成ファクトリ（[HerdrCaretComposer]）が必要と
/// する外部依存の抽象（[HerdrCaretHost]）と、その controller 向けのコール
/// バック実装（[HerdrCaretHostImpl]）。
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../../services/herdr/herdr_adapter.dart';
import '../../../services/herdr/herdr_models.dart';
import '../../../services/herdr/herdr_pane_frame_reader.dart';
import '../../../services/herdr/herdr_snapshot_cache.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import '../../../services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import '../../../services/herdr/hyperlink/scrollback_link_cache.dart';

/// 合成ファクトリが required とする外部依存（root が提供）。
///
/// caret / frame reader の生成に必要な herdr state（cache / adapter / reader /
/// status）と、画面側の反映先（frameReader・view caret）への接続を抽象化する。
abstract interface class HerdrCaretHost {
  WidgetRef get ref;

  bool get isMounted;

  bool get isDisposed;

  MultiplexerBackendKind get backendKind;

  HerdrAdapter? get frameAdapter;

  HerdrSnapshotCache? get snapshotCache;

  /// テスト注入用 reader（`TerminalScreen.herdrCaretReader`）。
  HerdrCaretSnapshotReader? get injectedReader;

  /// テスト注入用 hyperlink reader（`TerminalScreen.herdrHyperlinkReader`・
  /// herdr OSC 8 ハイパーリンク実験機能）。[injectedReader] と同じ
  /// 経路（本番は null）。
  HerdrHyperlinkReader? get injectedHyperlinkReader;

  HerdrCaretSnapshotReader? get caretReader;

  set caretReader(HerdrCaretSnapshotReader? value);

  HerdrStatus? get caretStatus;

  set caretStatus(HerdrStatus? value);

  /// 通常表示のハイパーリンク reader（herdr OSC 8 ハイパーリンク実験機能）。
  HerdrHyperlinkReader? get hyperlinkReader;

  set hyperlinkReader(HerdrHyperlinkReader? value);

  /// 構築した frame reader をポーリングループへ反映する（session 側）。
  void setFrameReader(HerdrPaneFrameReader reader);

  /// OFF 遷移時・切替時に view の caret をクリアする（session 側）。
  void clearViewCaret();

  /// 現在表示対象の pane ID（`HerdrController.paneId` への即時委譲）。
  String? get currentPaneId;

  /// スクロールモードのリンクキャッシュ。
  ScrollbackLinkCache? get scrollbackLinkCache;

  set scrollbackLinkCache(ScrollbackLinkCache? value);

  /// スクロールモードのリンク読取。
  HerdrScrollbackLinkReader? get scrollbackLinkReader;

  set scrollbackLinkReader(HerdrScrollbackLinkReader? value);

  /// テスト注入用 scrollback-links helper runner（`TerminalScreen.
  /// herdrScrollbackLinkHelperRunner`）。[injectedReader] と同じ経路
  /// （本番は null）。
  HerdrScrollbackLinkHelperRunner? get injectedScrollbackLinkHelperRunner;

  /// スクロールモードの現在の本文行（プレーンテキスト）。
  List<String> Function() get bodyLinesFor;

  /// バックグラウンド中でないか。
  bool Function() get isActive;

  /// スクロールモードのリンク取得結果が更新されたときの再描画通知。
  void Function() get notifyScrollbackLinksUpdated;

  /// 現在のスクロールモードのスナップショット identity。
  ({Object? identity, int generation})? Function() get currentSnapshotIdentity;

  /// 現在 select モードか（herdr OSC 8 ハイパーリンク実験機能）。
  /// [HerdrCaretComposer.setupScrollbackLinkReader] の manifest 読込中
  /// （await 中）に届いた viewport 確定は、reader が未代入のため
  /// `_host.scrollbackLinkReader?.` で捨てられる。reader 代入完了時に
  /// [HerdrCaretComposer.onScrollbackLinkReaderAssigned] から 1 回だけ
  /// 送り直す際、モードが変わっていないか（select を抜けた・エンジン
  /// 再構築で resetTerminalMode が先に走った等）を確認するために使う。
  bool Function() get isSelectModeActive;

  /// [HerdrScrollbackLinkReader] の時計（省略時 `DateTime.now`）。
  /// `env.clock`（`TerminalScreen.herdrCacheClock`。既存の
  /// [HerdrSnapshotCache] と同じテスト注入経路）をそのまま渡す。テストで
  /// 実時間（`DateTime.now()`）と `flutter test` の仮想クロック
  /// （`tester.pump` が進める Timer 用クロック）がずれることで、
  /// `HerdrScrollbackLinkReader` の開始間隔 2 秒（[HerdrScrollbackLinkReader.
  /// minInterval]）ゲートが実時間側では絶対に満たされず、2 回目以降の
  /// 往復が `pump` をどれだけ進めても発生しない事故を避ける。
  DateTime Function()? get scrollbackLinkClock;
}

/// [HerdrCaretHost] のコールバック実装（controller が組み立てる・cycle 回避）。
class HerdrCaretHostImpl implements HerdrCaretHost {
  HerdrCaretHostImpl({
    required this.ref,
    required bool Function() isMounted,
    required bool Function() isDisposed,
    required MultiplexerBackendKind Function() backendKind,
    required HerdrAdapter? Function() frameAdapter,
    required HerdrSnapshotCache? Function() snapshotCache,
    required HerdrCaretSnapshotReader? Function() injectedReader,
    required HerdrHyperlinkReader? Function() injectedHyperlinkReader,
    required HerdrCaretSnapshotReader? Function() caretReader,
    required void Function(HerdrCaretSnapshotReader? value) setCaretReader,
    required HerdrStatus? Function() caretStatus,
    required void Function(HerdrStatus? value) setCaretStatus,
    required HerdrHyperlinkReader? Function() hyperlinkReader,
    required void Function(HerdrHyperlinkReader? value) setHyperlinkReader,
    required void Function(HerdrPaneFrameReader reader) onFrameReader,
    required VoidCallback onClearViewCaret,
    required String? Function() currentPaneId,
    required ScrollbackLinkCache? Function() scrollbackLinkCache,
    required void Function(ScrollbackLinkCache? value) setScrollbackLinkCache,
    required HerdrScrollbackLinkReader? Function() scrollbackLinkReader,
    required void Function(HerdrScrollbackLinkReader? value)
    setScrollbackLinkReader,
    required HerdrScrollbackLinkHelperRunner? Function()
    injectedScrollbackLinkHelperRunner,
    required List<String> Function() bodyLinesFor,
    required bool Function() isActive,
    required bool Function() isSelectModeActive,
    required void Function() notifyScrollbackLinksUpdated,
    required ({Object? identity, int generation})? Function()
    currentSnapshotIdentity,
    this.scrollbackLinkClock,
  }) : _isMounted = isMounted,
       _isDisposed = isDisposed,
       _backendKind = backendKind,
       _frameAdapter = frameAdapter,
       _snapshotCache = snapshotCache,
       _injectedReader = injectedReader,
       _injectedHyperlinkReader = injectedHyperlinkReader,
       _caretReader = caretReader,
       _setCaretReader = setCaretReader,
       _caretStatus = caretStatus,
       _currentPaneId = currentPaneId,
       _scrollbackLinkCache = scrollbackLinkCache,
       _setScrollbackLinkCache = setScrollbackLinkCache,
       _scrollbackLinkReader = scrollbackLinkReader,
       _setScrollbackLinkReader = setScrollbackLinkReader,
       _injectedScrollbackLinkHelperRunner = injectedScrollbackLinkHelperRunner,
       _bodyLinesFor = bodyLinesFor,
       _isActive = isActive,
       _isSelectModeActive = isSelectModeActive,
       _notifyScrollbackLinksUpdated = notifyScrollbackLinksUpdated,
       _currentSnapshotIdentity = currentSnapshotIdentity,
       _setCaretStatus = setCaretStatus,
       _hyperlinkReader = hyperlinkReader,
       _setHyperlinkReader = setHyperlinkReader,
       _onFrameReader = onFrameReader,
       _onClearViewCaret = onClearViewCaret;

  @override
  final WidgetRef ref;

  @override
  final DateTime Function()? scrollbackLinkClock;

  final bool Function() _isMounted;
  final bool Function() _isDisposed;
  final MultiplexerBackendKind Function() _backendKind;
  final HerdrAdapter? Function() _frameAdapter;
  final HerdrSnapshotCache? Function() _snapshotCache;
  final HerdrCaretSnapshotReader? Function() _injectedReader;
  final HerdrHyperlinkReader? Function() _injectedHyperlinkReader;
  final HerdrCaretSnapshotReader? Function() _caretReader;
  final void Function(HerdrCaretSnapshotReader? value) _setCaretReader;
  final HerdrStatus? Function() _caretStatus;
  final void Function(HerdrStatus? value) _setCaretStatus;
  final HerdrHyperlinkReader? Function() _hyperlinkReader;
  final void Function(HerdrHyperlinkReader? value) _setHyperlinkReader;
  final void Function(HerdrPaneFrameReader reader) _onFrameReader;
  final VoidCallback _onClearViewCaret;
  final String? Function() _currentPaneId;
  final ScrollbackLinkCache? Function() _scrollbackLinkCache;
  final void Function(ScrollbackLinkCache? value) _setScrollbackLinkCache;
  final HerdrScrollbackLinkReader? Function() _scrollbackLinkReader;
  final void Function(HerdrScrollbackLinkReader? value)
  _setScrollbackLinkReader;
  final HerdrScrollbackLinkHelperRunner? Function()
  _injectedScrollbackLinkHelperRunner;
  final List<String> Function() _bodyLinesFor;
  final bool Function() _isActive;
  final bool Function() _isSelectModeActive;
  final void Function() _notifyScrollbackLinksUpdated;
  final ({Object? identity, int generation})? Function()
  _currentSnapshotIdentity;

  @override
  bool get isMounted => _isMounted();

  @override
  bool get isDisposed => _isDisposed();

  @override
  MultiplexerBackendKind get backendKind => _backendKind();

  @override
  HerdrAdapter? get frameAdapter => _frameAdapter();

  @override
  HerdrSnapshotCache? get snapshotCache => _snapshotCache();

  @override
  HerdrCaretSnapshotReader? get injectedReader => _injectedReader();

  @override
  HerdrHyperlinkReader? get injectedHyperlinkReader =>
      _injectedHyperlinkReader();

  @override
  HerdrCaretSnapshotReader? get caretReader => _caretReader();

  @override
  set caretReader(HerdrCaretSnapshotReader? value) => _setCaretReader(value);

  @override
  HerdrStatus? get caretStatus => _caretStatus();

  @override
  set caretStatus(HerdrStatus? value) => _setCaretStatus(value);

  @override
  HerdrHyperlinkReader? get hyperlinkReader => _hyperlinkReader();

  @override
  set hyperlinkReader(HerdrHyperlinkReader? value) =>
      _setHyperlinkReader(value);

  @override
  void setFrameReader(HerdrPaneFrameReader reader) => _onFrameReader(reader);

  @override
  void clearViewCaret() => _onClearViewCaret();

  @override
  String? get currentPaneId => _currentPaneId();

  @override
  ScrollbackLinkCache? get scrollbackLinkCache => _scrollbackLinkCache();

  @override
  set scrollbackLinkCache(ScrollbackLinkCache? value) =>
      _setScrollbackLinkCache(value);

  @override
  HerdrScrollbackLinkReader? get scrollbackLinkReader =>
      _scrollbackLinkReader();

  @override
  set scrollbackLinkReader(HerdrScrollbackLinkReader? value) =>
      _setScrollbackLinkReader(value);

  @override
  HerdrScrollbackLinkHelperRunner? get injectedScrollbackLinkHelperRunner =>
      _injectedScrollbackLinkHelperRunner();

  @override
  List<String> Function() get bodyLinesFor => _bodyLinesFor;

  @override
  bool Function() get isActive => _isActive;

  @override
  bool Function() get isSelectModeActive => _isSelectModeActive;

  @override
  void Function() get notifyScrollbackLinksUpdated =>
      _notifyScrollbackLinksUpdated;

  @override
  ({Object? identity, int generation})? Function()
  get currentSnapshotIdentity => _currentSnapshotIdentity;
}
