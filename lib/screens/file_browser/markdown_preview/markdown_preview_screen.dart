import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/markdown_preview_provider.dart';
import '../../../services/sftp/file_entry.dart';
import '../../../theme/design_colors.dart';

import 'markdown_preview_body.dart';
import 'markdown_scroll_keys.dart';

/// Markdown プレビュー画面（SFTP 取得した .md/.markdown の表示）。
///
/// Raw / Rendered トグル（画面ローカル state）・各ビューでスクロール位置保持
/// （per-view ×2・合意#5）・トグル時に現在ビューのスクロール比率
/// （offset / maxScrollExtent）を他ビューへ比率連動で適用。
///
/// 初回表示の流れ（H-3）: initState の postFrameCallback で画面側から
/// [MarkdownPreviewNotifier.load] を開始する（push 前に load しない。
/// AutoDispose 競合回避）。状態は [markdownPreviewProvider] の watch で
/// 表示（ローディング / エラー+再試行 / 20MB 超過 / バイナリ / 空 / 本文）。
///
/// 状態所有（controllers / showRendered / トグル比率連動 / reload）と
/// 表示構築（[MarkdownPreviewBody]）を分離した単一状態所有者。
class MarkdownPreviewScreen extends ConsumerStatefulWidget {
  const MarkdownPreviewScreen({
    super.key,
    required this.connectionId,
    required this.entry,
  });

  final String connectionId;

  /// プレビュー対象の .md / .markdown エントリ。
  final FileEntry entry;

  /// トグル・スクロール操作用の安定キー（テストから参照可）。
  /// 実体は中立 [MarkdownScrollKeys] の static const（ヘッド同等の const 宣言を維持）。
  static const Key rawScrollKey = MarkdownScrollKeys.rawScrollKey;
  static const Key renderedScrollKey = MarkdownScrollKeys.renderedScrollKey;

  @override
  ConsumerState<MarkdownPreviewScreen> createState() =>
      _MarkdownPreviewScreenState();
}

class _MarkdownPreviewScreenState extends ConsumerState<MarkdownPreviewScreen> {
  /// raw / rendered の各ビュー用スクロールコントローラ（per-view ×2・合意#5）。
  final ScrollController _rawController = ScrollController();
  final ScrollController _renderedController = ScrollController();

  /// 表示中ビュー（true = Rendered 基本・D-4）。
  bool _showRendered = true;

  /// .md ファイルのリモートディレクトリ（相対画像の SFTP 解決基準・合意#7）。
  late final String _mdBaseDirectory = p.posix.dirname(widget.entry.fullPath);

  @override
  void initState() {
    super.initState();
    // H-3: 初回 ref.watch 確立直後に load() を開始する（画面側駆動）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
    });
  }

  @override
  void dispose() {
    _rawController.dispose();
    _renderedController.dispose();
    super.dispose();
  }

  void _reload() {
    ref
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: widget.connectionId, entry: widget.entry);
  }

  /// トグル時に現在ビューのスクロール比率を他ビューへ適用する（合意#5）。
  ///
  /// ①現在ビューの `offset / maxScrollExtent` を比率としてキャプチャ
  /// （`maxScrollExtent <= 0` は比率 0）②トグル切替後、
  /// `addPostFrameCallback` で he ビューへ `jumpTo(比率 × 新 maxScrollExtent)`
  /// を適用する。raw / rendered の行構成差は比率対応で吸収される。
  void _onToggleView(bool showRendered) {
    if (showRendered == _showRendered) return;
    final active = _showRendered ? _renderedController : _rawController;
    final target = _showRendered ? _rawController : _renderedController;
    final ratio = (active.hasClients && active.position.maxScrollExtent > 0)
        ? active.offset / active.position.maxScrollExtent
        : 0.0;

    setState(() => _showRendered = showRendered);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (target.hasClients && target.position.maxScrollExtent > 0) {
        target.jumpTo(ratio * target.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(markdownPreviewProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mdPreviewTitle)),
      body: Column(
        children: [
          _buildToggleBar(context, l10n, isDark),
          Expanded(
            child: MarkdownPreviewBody(
              state: state,
              rawController: _rawController,
              renderedController: _renderedController,
              showRendered: _showRendered,
              mdBaseDirectory: _mdBaseDirectory,
              onReload: _reload,
            ),
          ),
        ],
      ),
    );
  }

  // --- 各部位の構築 ---

  /// ファイル名 + Raw/Rendered トグルのバー。
  Widget _buildToggleBar(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.mdRaw)),
              ButtonSegment(value: true, label: Text(l10n.mdRendered)),
            ],
            selected: {_showRendered},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (selection) => _onToggleView(selection.first),
          ),
        ],
      ),
    );
  }
}
