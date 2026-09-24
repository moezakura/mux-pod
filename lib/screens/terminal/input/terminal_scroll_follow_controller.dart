import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ansi_terminal_model.dart' show TerminalMode;
import 'terminal_input_ports.dart'
    show
        TerminalInputHost,
        TerminalNavigationPort,
        TerminalScrollbackPort,
        TerminalTargetIdentityValidator;
import 'terminal_viewport_port.dart' show TerminalViewportPort;

/// Scroll 追従・深い履歴ロードの単一所有者（TERM-SCROLL-001〜004・
/// TERM-LIFE-020・C1）。
///
/// 最下部ピン留め 4 フラグと・深い履歴ロード中フラグを所有する。
/// `_scrollToCaret`（C1・100ms 遅延 + mounted/disposed ガード）もここが持つ。
/// 表示内容の読み書きは [TerminalScrollbackPort]、viewport 操作は
/// [TerminalViewportPort]、表示対象照合は [TerminalTargetIdentityValidator]
/// を通す。
class TerminalScrollFollowController {
  TerminalScrollFollowController({
    required this.scrollback,
    required this.viewport,
    required this.nav,
    required this.host,
    required this.validator,
    required TerminalMode Function() mode,
  }) : _mode = mode;

  final TerminalScrollbackPort scrollback;
  final TerminalViewportPort viewport;
  final TerminalNavigationPort nav;
  final TerminalInputHost host;
  final TerminalTargetIdentityValidator validator;
  final TerminalMode Function() _mode;

  /// 上端オーバースクロール時の select 遷移（coordinator が設定。HEAD の
  /// `_loadDeepHistoryOnScroll` の setState 相当: mode.applySelectForHistory +
  /// markNeedsBuild。深い履歴ロード前に同期適用する必要がある）。
  void Function()? onEnterSelectForHistory;

  /// 最下部との距離がこの値以下なら「最下部表示中」とみなす（float 誤差対策）。
  static const double _bottomFollowEpsilon = 1.0;

  /// 最下部表示中（ピン留め）。true の間はコンテンツ更新に追従する。
  bool _isPinnedToBottom = true;

  /// FAB 長押しによる最下部ロック。
  bool _isBottomLock = false;

  /// ユーザーがドラッグ中かどうか（追従を一時停止する・ドラッグ完了で解除）。
  bool _isUserScrollDragging = false;

  /// FAB タップ等のプログラマティックスクロール中かどうか。
  bool _isProgrammaticScroll = false;

  /// 深い履歴（全スクロールバック）の自動ロード中フラグ。
  bool _isLoadingDeepHistory = false;

  /// 所有する ScrollController（root の `_terminalScrollController` を受け、listener 登録する）。
  ScrollController? _attachedController;

  // ----（が読む）----
  bool get isPinnedToBottom => _isPinnedToBottom;
  bool get isBottomLock => _isBottomLock;
  bool get isUserScrollDragging => _isUserScrollDragging;

  /// コンテンツ更新に追従すべきか（ピン留め or ロック）。
  bool get shouldFollowBottom => _isPinnedToBottom || _isBottomLock;

  // ----（root が attach/detach する）----
  void attach(ScrollController controller) {
    _attachedController = controller;
    controller.addListener(onScroll);
  }

  void detach() {
    _attachedController?.removeListener(onScroll);
    _attachedController = null;
  }

  // ---- FAB 操作 / ドラッグ / スクロール ----

  /// ロックの ON/OFF（ui の FAB 長押し）。ロック中は FAB 常時表示 + 追従。
  void toggleBottomLock(bool value) {
    if (_isBottomLock == value) return;
    _isBottomLock = value;
    host.markNeedsBuild();
  }

  /// モード遷移時の follow フラグ 3 種のリセット（HEAD の各遷移 setState と同一）。
  void resetFollowFlags() {
    _isBottomLock = false;
    _isUserScrollDragging = false;
    _isProgrammaticScroll = false;
  }

  /// スクロール時にスクロールボタンを表示（HEAD `_onTerminalScroll` と同一）。
  void onScroll() {
    final controller = _attachedController;
    // プログラマティックスクロール中は中間通知でピン留め判定を false 化しない。
    if (controller != null && controller.hasClients && !_isProgrammaticScroll) {
      _isPinnedToBottom =
          controller.position.extentAfter <= _bottomFollowEpsilon;
    }
    if (_isPinnedToBottom) return;
    host.showScrollToBottomButton();
  }

  /// スクロール通知の入口（`NotificationListener<ScrollNotification>`）。
  bool onScrollNotification(ScrollNotification n) {
    // 横スクロール（AnsiTextView 内 horizontal ScrollView）は対象外。
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      handleUserScrollDrag(n.dragDetails != null);
    } else if (n is ScrollUpdateNotification) {
      handleUserScrollDrag(n.dragDetails != null);
    } else if (n is ScrollEndNotification) {
      _isUserScrollDragging = false;
    } else if (n is OverscrollNotification) {
      // inventory: TERM-SCROLL-002
      return onTerminalOverscroll(n);
    }
    return false;
  }

  /// ユーザードラッグ開始/更新通知の共通処理。
  void handleUserScrollDrag(bool isUserDrag) {
    if (!isUserDrag) return;
    _isUserScrollDragging = true;
    if (_isBottomLock) {
      _isBottomLock = false;
      host.markNeedsBuild();
    }
  }

  /// FAB 操作由来の最下部スクロール（タップ・長押し共用）。
  void scrollToBottomFollowing() {
    _isPinnedToBottom = true;
    _isProgrammaticScroll = true;
    unawaited(
      viewport.scrollToBottom().then((_) {
        _isProgrammaticScroll = false;
        _isPinnedToBottom = true;
      }),
    );
  }

  /// 上端でのオーバースクロール → 深い履歴ロード（select 専用・D12）。
  bool onTerminalOverscroll(OverscrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.overscroll < 0 &&
        _mode() == TerminalMode.normal &&
        !_isLoadingDeepHistory) {
      // inventory: TERM-SCROLL-003
      // ignore: unawaited_futures
      loadDeepHistoryOnScroll();
    }
    return false;
  }

  /// スクロール上端到達時に深い履歴を自動ロードする（遷移先 = select・D12）。
  Future<void> loadDeepHistoryOnScroll() async {
    if (_isLoadingDeepHistory) return;
    _isLoadingDeepHistory = true;
    if (_mode() != TerminalMode.select) {
      // HEAD の `_loadDeepHistoryOnScroll` の setState と同一の代入集合。
      onEnterSelectForHistory?.call();
      resetFollowFlagsFromHistoryEntry();
    }
    try {
      await loadHistoryForScroll(preservePosition: true);
    } finally {
      _isLoadingDeepHistory = false;
    }
  }

  /// select 突入（履歴ロード用）時の follow フラグ 3 種のリセット。
  void resetFollowFlagsFromHistoryEntry() {
    _isBottomLock = false;
    _isUserScrollDragging = false;
    _isProgrammaticScroll = false;
  }

  // inventory: TERM-LIFE-020
  /// select モード開始時の履歴取得（HEAD `_loadHistoryForScroll` と同一）。
  Future<void> loadHistoryForScroll({bool preservePosition = false}) async {
    // A3改: 深い履歴 read 開始前に表示対象同一性を記録（完了時に照合）。
    final identity = scrollback.captureTargetIdentity();
    final content = await scrollback.readScrollbackContent();
    if (!host.isMounted || host.isDisposed) return;
    // A3改: await 完了後に表示対象を照合。不一致なら破棄。
    if (!validator.isCurrent(identity)) return;
    // select 専用（4 経路分離・D12）: await 後のモードガード。
    if (_mode() != TerminalMode.select) return;
    if (content == null) return;

    if (preservePosition) {
      // スクロール上端からの自動ロード: プリペンドされた行数ぶん位置を補正し、
      // 直前に最上部だった行を同じ位置に留める（真ん中へ飛ばないように）。
      final oldContent = scrollback.displayedContent;
      final oldLines = oldContent.isEmpty
          ? 0
          : '\n'.allMatches(oldContent).length + 1;
      final newLines = content.isEmpty
          ? 0
          : '\n'.allMatches(content).length + 1;
      final prepended = newLines - oldLines;
      scrollback.setDisplayedContent(content);
      if (prepended > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (host.isMounted && !host.isDisposed) {
            viewport.jumpToLineFromTop(prepended);
          }
        });
      }
    } else {
      scrollback.setDisplayedContent(content);
      // ライブ位置（末尾）に合わせ、そこから上へ履歴を遡れるようにする。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.isMounted && !host.isDisposed) {
          viewport.scrollToBottom();
        }
      });
    }
  }

  // inventory: TERM-SCROLL-004
  /// キャレット位置にスクロール（C1・100ms 遅延 + mounted/_isDisposed ガード維持）。
  void scrollToCaret() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!host.isMounted || host.isDisposed) return;
      // Phase 4: herdr は有効な caret snapshot（位置既知 x/y non-null）を
      // 保持している場合のみ scrollToCaret を使う。それ以外は末尾アライン。
      // tmux は実カーソル位置があるため従来どおり中央寄せを維持。
      if (nav.isHerdr) {
        final caret = scrollback.displayedCaret;
        if (caret != null && caret.visible && caret.hasPosition) {
          viewport.scrollToCaret();
        } else {
          viewport.scrollToBottom();
        }
      } else {
        viewport.scrollToCaret();
      }
    });
  }

  /// テストフック: 履歴ロード（root が転送・TERM-LIFE-020 検証用）。
  Future<void> loadHistoryForScrollForTesting({bool preservePosition = false}) {
    return loadHistoryForScroll(preservePosition: preservePosition);
  }
}
