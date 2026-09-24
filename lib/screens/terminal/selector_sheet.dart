import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/backend/domain/multiplexer_pane.dart';
import '../../services/backend/domain/multiplexer_session.dart';
import '../../services/backend/domain/multiplexer_window.dart';
import '../../l10n/l10n_ext.dart';

/// セレクタの現在位置（H-1: ハイライト導出用）。
///
/// backend 別に、表示中の session / window / pane の現在位置を保持する。
/// tmux は provider のアクティブ状態（activeSessionName / activeWindowIndex /
/// activeWindowId / activePaneId）を渡し、herdr は表示対象 pane から導出した
/// 値を渡す。フィールドは全て nullable（未確定の段は null）。
class SelectorContext {
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

  const SelectorContext({
    this.sessionName,
    this.sessionId,
    this.windowIndex,
    this.windowId,
    this.paneId,
  });
}

/// H-1: セッションのハイライト（[SelectorContext] の現在位置と照合）。
///
/// 一義的な基準は現在の session ID（[MultiplexerSession.id] ==
/// [SelectorContext.sessionId]）。現在の session ID が判明している場合は
/// ID ベース判定のみで行い、名前（表示名）一致はしない。これにより同名ラベル
/// の workspace（herdr の "tmp" w3/w4）でも、現在の workspace ID と一致する
/// ものだけがハイライトされる。
///
/// [SelectorContext.sessionId] が不明（旧データ等）の場合のみ、名前一致と
/// paneId prefix（"w1:" 等）の旧挙動へフォールバックする。
bool isCurrentSession(MultiplexerSession session, SelectorContext? current) {
  if (current == null) return false;
  // 一義的な基準: 現在の session ID と一致するか
  final currentSessionId = current.sessionId;
  final sessionId = session.id;
  if (currentSessionId != null && currentSessionId.isNotEmpty) {
    if (sessionId != null && sessionId == currentSessionId) return true;
    // paneId が現在の session に属するか（pane 由来の ID 判定）
    final paneId = current.paneId;
    if (paneId != null &&
        sessionId != null &&
        paneId.startsWith('$sessionId:')) {
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

/// H-1: ウィンドウのハイライト（[SelectorContext] の現在位置と照合）。
///
/// 一義的な基準は現在の window ID（[MultiplexerWindow.id] ==
/// [SelectorContext.windowId]）。[windowId] が判明している場合は ID 一致のみで
/// 判定し、[windowId] 不明時のみ index フォールバックする（旧挙動）。
bool isCurrentWindow(MultiplexerWindow window, SelectorContext? current) {
  if (current == null) return false;
  final currentWindowId = current.windowId;
  if (currentWindowId != null && currentWindowId.isNotEmpty) {
    return window.id == currentWindowId;
  }
  if (window.index == current.windowIndex) return true;
  return false;
}

/// H-1: ペインのハイライト（[SelectorContext] の現在位置と照合）。
bool isCurrentPane(MultiplexerPane pane, SelectorContext? current) =>
    pane.id == current?.paneId;

/// 非同期ロードされたセレクタの内容（一覧 + ヘッダー action + top）。
class SelectorContent {
  final List<Widget> children;
  final List<Widget> headerActions;

  /// 一覧の上部に表示するウィジェット（無ければ null）。
  final Widget? top;
  const SelectorContent({
    this.children = const [],
    this.headerActions = const [],
    this.top,
  });
}

/// 共通 1 段セレクタシート（選択即閉じ・元 tmux 挙動）。
///
/// 受け取った [children]（呼び出し側が構築済みのタイル）を 1 階層だけ表示する。
/// タイルの onTap は呼び出し側が「pop → コールバック」を担い、このシート自体は
/// ドリルダウン状態を持たない。3 種のシート（Select Session / Select Window /
/// Select Pane）は [title] / [icon] / [children] / [headerActions] の違いで
/// 1 クラスが表現する（M-6: タイトル統一）。
///
/// [headerActions] はヘッダー右側の mutation ボタン（tmux は能力あり（接続中）時のみ
/// 呼び出し側が構築）。[top] は一覧の上部に表示するウィジェット（tmux pane
/// シートの [PaneLayoutVisualizer]）。ハイライト（H-1）は [SelectorContext]
/// から呼び出し側がタイルへ渡す。
class MultiplexerSelectorSheet extends StatefulWidget {
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

  /// top 表示がローディング中から確定するセレクタ（herdr pane セレクタ）で
  /// maxHeight 0.7 を固定する（ローディング中の高さジャンプ防止）。
  final bool topExpected;

  /// 非同期で一覧を取得する（バグ3 根本対応: 即時 open + loading/data/error）。
  ///
  /// 戻り値は (children, headerActions, top) のセット。データロード後にヘッダーの
  /// mutation ボタン（Resize 等）と top（分割プレビュー）も確定させるため、
  /// headerActions / top も同時に返す（tooltip を維持・バグ3 根本対応）。
  final Future<SelectorContent> Function()? asyncContent;

  /// 取得失敗時の Retry コールバック（無ければ null）。
  final VoidCallback? retry;

  const MultiplexerSelectorSheet({
    super.key,
    required this.title,
    required this.icon,
    this.headerActions = const [],
    this.top,
    this.topExpected = false,
    this.asyncContent,
    this.retry,
    required this.children,
  });

  @override
  State<MultiplexerSelectorSheet> createState() =>
      MultiplexerSelectorSheetState();
}

class MultiplexerSelectorSheetState extends State<MultiplexerSelectorSheet> {
  /// ロード結果（null なら loading・エラーは [_loadError] で表現）。
  SelectorContent? _content;
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
    final hasTop =
        widget.top != null || widget.topExpected || _content?.top != null;
    final maxHeight = MediaQuery.of(context).size.height * (hasTop ? 0.7 : 0.6);
    final topWidget = _content?.top ?? widget.top;

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
            if (topWidget != null) ...[
              topWidget,
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
          if (topWidget != null) ...[
            topWidget,
            Divider(height: 1, color: colorScheme.outline),
          ],
          Flexible(
            child: ListView(shrinkWrap: true, children: widget.children),
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
          if (headerActions.isNotEmpty) ...[const Spacer(), ...headerActions],
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
          Text(
            context.l10n.termFailedToLoad,
            style: TextStyle(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          if (widget.retry != null)
            FilledButton(
              onPressed: () {
                widget.retry!();
                _load();
              },
              child: Text(context.l10n.termRetry),
            ),
        ],
      ),
    );
  }
}
