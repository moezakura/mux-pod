import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../providers/ssh_provider.dart';
import '../../providers/tmux_provider.dart';
// inventory: TERM-BREAD-000
import '../../theme/design_colors.dart';
import 'terminal_overlays.dart';
import 'widgets/ansi_terminal_model.dart';

/// pane ID（"w1:p1" / "w1:t1:p1"）から属する tab ID を best-effort で導出する。
///
/// 3 セグメント形式なら "w1:t1"、2 セグメント形式なら null（不明）。スナップ
/// ショット解決（HerdrPane.tabId）を伴わない経路（直接指定・セレクタ）の
/// フォールバックに使う（L-1）。解決済みの実値がある場合はそちらを優先する。
String? herdrTabIdFromPaneId(String paneId) {
  final segments = paneId.split(':');
  if (segments.length >= 3) return segments.take(2).join(':');
  return null;
}

/// pane ID（例: "w1:p1"）のブレッドクラム表示名を返す（'Pane N'）。
///
/// 末尾セグメントから番号を抽出する（"w1:p1" → "Pane 1"）。抽出できない場合
/// は "Pane 0" を返す。A10 の currentPath 優先ルールはセレクタ側で適用し、
/// ブレッドクラムは番号ベースで統一する。
String herdrPaneSegmentLabel(String paneId, AppLocalizations l10n) {
  final last = paneId.split(':').last;
  final digits = last.replaceAll(RegExp(r'\D'), '');
  final index = int.tryParse(digits) ?? 0;
  return l10n.termPaneLabel(index);
}

/// ブレッドクラム描画用の共通データ（A9）。
///
/// tmux 経路（[buildTmuxBreadcrumb]）と herdr 経路（[buildHerdrBreadcrumb]）の
/// どちらもこのデータへ変換し、[TerminalBreadcrumbHeader] はこのデータだけを
/// 受け取って描画する（backend 分岐はデータ生成側に閉じる）。
class BreadcrumbData {
  /// セッション名（tmux）または workspace ラベル（herdr）。
  final String session;

  /// ウィンドウ名。null なら非表示（未接続時等）。
  final String? window;

  /// ペイン表示文字列（例: "Pane 0"）。null なら非表示。
  final String? pane;

  /// セッション/workspace セグメントのタップ（セレクタ表示）。
  final VoidCallback? onSessionTap;

  /// ウィンドウセグメントのタップ（セレクタ表示）。
  final VoidCallback? onWindowTap;

  /// ペインセグメントのタップ（セレクタ表示）。
  final VoidCallback? onPaneTap;

  const BreadcrumbData({
    required this.session,
    this.window,
    this.pane,
    this.onSessionTap,
    this.onWindowTap,
    this.onPaneTap,
  });
}

/// tmux 経路: [TmuxState] をブレッドクラム描画用データへ変換する（A9）。
///
/// [isDisconnected]（特殊キー送信不可・未接続）の場合は簡易表示（session のみ）
/// に切り替え、セレクタ tap を無効化する。
BreadcrumbData buildTmuxBreadcrumb({
  required TmuxState tmuxState,
  required bool isDisconnected,
  required String fallbackSessionName,
  required AppLocalizations l10n,
  required VoidCallback? onSessionTap,
  required VoidCallback? onWindowTap,
  required VoidCallback? onPaneTap,
}) {
  final activePane = tmuxState.activePane;
  return BreadcrumbData(
    session: isDisconnected
        ? (fallbackSessionName.isNotEmpty
              ? fallbackSessionName
              : (tmuxState.activeSessionName ?? ''))
        : (tmuxState.activeSessionName ?? ''),
    window: isDisconnected ? null : (tmuxState.activeWindow?.name ?? ''),
    pane: isDisconnected || activePane == null
        ? null
        : l10n.termPaneLabel(activePane.index),
    onSessionTap: isDisconnected ? null : onSessionTap,
    onWindowTap: isDisconnected ? null : onWindowTap,
    onPaneTap: isDisconnected ? null : onPaneTap,
  );
}

/// herdr の pane / tab 表示状態をブレッドクラム描画用データへ変換する（A9）。
///
/// - session/workspace セグメント → workspace セレクタ
/// - window/tab セグメント → tab セレクタ
/// - pane セグメント → pane セレクタ
BreadcrumbData buildHerdrBreadcrumb({
  required String? workspaceLabel,
  required String? tabId,
  required String? tabLabel,
  required String? paneId,
  required String fallbackSessionName,
  required AppLocalizations l10n,
  required VoidCallback onSessionTap,
  required VoidCallback onWindowTap,
  required VoidCallback onPaneTap,
}) {
  return BreadcrumbData(
    session: workspaceLabel ?? fallbackSessionName,
    // M-4: tab セグメントは数字抽出ではなく、snapshot 解決済みの実ラベルを表示。
    window: tabId != null ? (tabLabel ?? tabId) : null,
    pane: paneId != null ? herdrPaneSegmentLabel(paneId, l10n) : null,
    onSessionTap: onSessionTap,
    onWindowTap: onWindowTap,
    onPaneTap: onPaneTap,
  );
}

/// ブレッドクラムの 1 セグメント（アイコン + ラベル + ドロップダウン矢印）。
class BreadcrumbItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isActive;
  final bool isSelected;
  final VoidCallback? onTap;

  const BreadcrumbItem({
    super.key,
    required this.label,
    this.icon,
    this.isActive = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}

/// ブレッドクラムの区切り文字（'/'）。
class BreadcrumbSeparator extends StatelessWidget {
  const BreadcrumbSeparator({super.key});

  @override
  Widget build(BuildContext context) {
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
}

/// 上部のパンくずナビゲーションヘッダー（A9）。
///
/// [data] は backend 経路ごとに生成済みの共通データ（[buildTmuxBreadcrumb] /
/// [buildHerdrBreadcrumb]）。描画ロジックはこのウィジェットに一元化する。
/// モード表示・ズーム倍率・継続表示（latency / reconnect）・ファイルブラウザ
/// ボタン・設定ボタンも含む。
class TerminalBreadcrumbHeader extends StatelessWidget {
  final BreadcrumbData data;

  /// 現在のターミナルモード（normal 以外でモードインジケータ表示）。
  final TerminalMode mode;

  /// モードインジケータのタップ（normal 復帰）。
  final VoidCallback onExitToNormalMode;

  /// ズーム中かどうか（ズーム倍率表示の有無）。
  final bool isZoomed;

  /// 現在のズーム倍率（% 表示の元）。
  final double effectiveZoom;

  /// レイテンシ表示（ポーリング更新で変化）。
  final ValueListenable<int> latencyNotifier;

  /// 接続状態（再接続インジケータ描画用）。
  final SshState sshState;

  /// キューイング文字数（再接続インジケータ内表示）。
  final int queuedCount;

  /// 今すぐ再接続（エラー/再接続インジケータ）。
  final VoidCallback onRetryNow;

  /// 特殊キー送信可能（未接続時はファイルブラウザボタンを隠す）。
  final bool canSendSpecialKey;

  /// ファイルブラウザボタンのタップ。
  final VoidCallback? onFileBrowser;

  /// 設定（ターミナルメニュー）ボタンのタップ。
  final VoidCallback onMenuOpen;

  const TerminalBreadcrumbHeader({
    super.key,
    required this.data,
    required this.mode,
    required this.onExitToNormalMode,
    required this.isZoomed,
    required this.effectiveZoom,
    required this.latencyNotifier,
    required this.sshState,
    required this.queuedCount,
    required this.onRetryNow,
    required this.canSendSpecialKey,
    this.onFileBrowser,
    required this.onMenuOpen,
  });

  @override
  Widget build(BuildContext context) {
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
                    // セッション名（未接続時はタップ不可）
                    // inventory: TERM-DIALOG-004
                    BreadcrumbItem(
                      label: data.session,
                      icon: Icons.folder,
                      isActive: true,
                      onTap: data.onSessionTap,
                    ),
                    // ウィンドウ（tab）セグメント。herdr（T11）では現在
                    // ターゲット（workspace/tab/pane）を表示する。
                    if (data.window != null) ...[
                      // inventory: TERM-DIALOG-005
                      const BreadcrumbSeparator(),
                      BreadcrumbItem(
                        label: data.window!,
                        icon: Icons.tab,
                        isSelected: true,
                        onTap: data.onWindowTap,
                      ),
                    ],
                    // ペインセグメント（window と独立。herdr では pane ID が
                    // 2 セグメント形式でも表示する）
                    if (data.pane != null) ...[
                      const BreadcrumbSeparator(),
                      BreadcrumbItem(
                        label: data.pane!,
                        icon: Icons.terminal,
                        isActive: false,
                        onTap: data.onPaneTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ブレッドクラムと右側インジケータ群の間に必ず余白を確保する。
            // これがないとスクロールチップ等がブレッドクラムに密着し、重なって見える。
            const SizedBox(width: 8),
            // モード indicator（H2）: scrollSend 中も表示し、アイコンでモードを区別。
            if (mode != TerminalMode.normal)
              GestureDetector(
                onTap: onExitToNormalMode,
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
                        mode == TerminalMode.scrollSend
                            ? Icons.swipe_up
                            : Icons.unfold_more,
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
            if (isZoomed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(effectiveZoom * 100).round()}%',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: DesignColors.warning,
                  ),
                ),
              ),
            // Latency / Reconnect indicator（ValueListenableBuilderでポーリング更新をスコープ）
            ValueListenableBuilder<int>(
              valueListenable: latencyNotifier,
              builder: (context, latency, _) => ConnectionIndicator(
                sshState: sshState,
                queuedCount: queuedCount,
                latency: latency,
                onRetryNow: onRetryNow,
              ),
            ),
            // File browser button（normal 以外・未接続（特殊キー送信不可）は
            // 場所を空けるため非表示。H2: scrollSend 中も非表示 = `== normal` のみ表示）
            if (mode == TerminalMode.normal && canSendSpecialKey)
              IconButton(
                // inventory: TERM-FILE-001
                onPressed: onFileBrowser,
                icon: Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                tooltip: context.l10n.termFileBrowser,
              ),
            // Settings button
            IconButton(
              // inventory: TERM-DIALOG-002
              onPressed: onMenuOpen,
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
}
