import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../providers/markdown_preview_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_colors.dart';
import '../../theme/markdown_highlighter.dart';
import 'widgets/sftp_markdown_image.dart';

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
  static const Key rawScrollKey = Key('mdScrollRaw');
  static const Key renderedScrollKey = Key('mdScrollRendered');

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
          Expanded(child: _buildBody(context, state, isDark, l10n)),
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

  Widget _buildBody(
    BuildContext context,
    MarkdownPreviewState state,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      // 取得失敗（mdLoadFailed は Provider 層でラップ済み）・SSH 切断
      // （mdSshLost）は再試行で復旧できる（再接続後に再読み込み）。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: DesignColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? DesignColors.textPrimary
                      : DesignColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.mdRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isTooLarge) {
      // 20MB 超は拒否＋警告（合意#1）。静的メッセージのみ・SFTP 非アクセス。
      // size は実サイズ MB（切り上げ・LOW-1 対応）。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: DesignColors.warning,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.mdFileTooLargeTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? DesignColors.textPrimary
                      : DesignColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.mdFileTooLargeMessage(state.size ?? 0),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isBinary) {
      // バイナリ判定: Markdown として読み込まず専用メッセージ（合意#1）。
      // isBinary && isTruncated の複合時もバイナリ表示を優先（レビュー #3
      // LOW-2: content を表示しないため切詰めバナーは無意味）。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 48,
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.mdBinaryFile,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.content.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mdEmpty,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
              ),
            ),
          ],
        ),
      );
    }

    // 本文表示（能動ビューのみ構築・切詰めバナーは本文があるときだけ）
    return Column(
      children: [
        if (state.isTruncated) _buildTruncatedBanner(context, isDark, l10n),
        Expanded(
          child: _showRendered
              ? _buildRenderedView(context, state, isDark)
              : _buildRawView(state, isDark),
        ),
      ],
    );
  }

  /// 切詰め保険発動時のバナー（size 不明時のみ・合意#1・M-4）。
  Widget _buildTruncatedBanner(
    BuildContext context,
    bool isDark,
    AppLocalizations l10n,
  ) {
    return Container(
      width: double.infinity,
      color: DesignColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: DesignColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.mdTruncatedMessage,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? DesignColors.textSecondary
                    : DesignColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rendered ビュー（MarkdownBody・per-view scroll controller 付き）。
  Widget _buildRenderedView(
    BuildContext context,
    MarkdownPreviewState state,
    bool isDark,
  ) {
    return SingleChildScrollView(
      key: MarkdownPreviewScreen.renderedScrollKey,
      controller: _renderedController,
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: state.content,
        // C-2: syntaxHighlighter は言語を渡せないため不使用。
        // code 要素の class 属性（language-xxx）から言語を抽出してハイライト。
        builders: {'code': _MarkdownCodeElementBuilder(isDark: isDark)},
        imageBuilder: (uri, title, alt) =>
            _buildImage(context, uri, title, alt),
        onTapLink: _onTapLink,
      ),
    );
  }

  /// Raw ビュー（生テキスト・per-view scroll controller 付き）。
  Widget _buildRawView(MarkdownPreviewState state, bool isDark) {
    return SingleChildScrollView(
      key: MarkdownPreviewScreen.rawScrollKey,
      controller: _rawController,
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        state.content,
        style: AppTheme.monoTextStyle.copyWith(
          fontSize: 13,
          color: isDark
              ? DesignColors.textPrimary
              : DesignColors.textPrimaryLight,
        ),
      ),
    );
  }

  /// 画像リクエストの安全解決（#10/#11・imageBuilder）。
  ///
  /// 判定は [SftpMarkdownImage.resolveImage] に委譲:
  /// - 相対パス → [SftpMarkdownImage]（SFTP 解決・5MB 上限・validatePath
  ///   不通過は placeholder）
  /// - https/http（localhost / private IP 以外のみ）→ Image.network
  /// - data URI・その他スキーム・拒否 → placeholder＋alt（合意#7）
  Widget _buildImage(
    BuildContext context,
    Uri uri,
    String? title,
    String? alt,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolution = SftpMarkdownImage.resolveImage(
      uri: uri,
      mdBaseDirectory: _mdBaseDirectory,
    );
    switch (resolution.kind) {
      case MarkdownImageResolvedKind.sftp:
        return SftpMarkdownImage(
          path: resolution.sftpPath!,
          alt: (alt != null && alt.isNotEmpty) ? alt : title,
        );
      case MarkdownImageResolvedKind.network:
        return Image.network(
          resolution.networkUri!.toString(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const SizedBox(width: 120, height: 60),
          errorBuilder: (context, error, stackTrace) =>
              SftpMarkdownImage.placeholder(
                alt: alt,
                title: title,
                isDark: isDark,
                // ブロック時（broken_image）と区別する
                icon: Icons.image_not_supported,
              ),
        );
      case MarkdownImageResolvedKind.denied:
        return SftpMarkdownImage.placeholder(
          alt: alt,
          title: title,
          isDark: isDark,
        );
    }
  }

  /// リンクタップ時の scheme ガード（計画 §L2-4・L-2）。
  ///
  /// https/http のみ [launchUrl]（OS 外部ブラウザ・about_section.dart パターン）。
  /// `#anchor`（scheme 無し）・`mailto:`・`data:`・`javascript:`・`file:` 等は
  /// 何もしない（タップ無視）。スキーム検証は [Uri.tryParse] で明示する。
  static void _onTapLink(String text, String? href, String title) {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return;
    _launchExternal(uri);
  }

  static Future<void> _launchExternal(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Markdown の `code` 要素に対するカスタムビルダ（C-2）。
///
/// `md.Element.attributes['class']`（`language-xxx`）から言語を抽出し、
/// **言語指定のあるフェンスドコードブロックのみ**ハイライト表示する。
/// class 属性が無い要素（インラインコード・言語なしフェンスドブロック）は
/// null を返して既定描画へフォールバックする（D-2・markdown 7.3.1 は言語
/// 指定時のみ class を付与する・実測確認済み）。
class _MarkdownCodeElementBuilder extends MarkdownElementBuilder {
  _MarkdownCodeElementBuilder({required this.isDark});

  final bool isDark;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final language = MarkdownHighlighter.languageFromClassAttribute(
      element.attributes['class'],
    );
    if (language == null) return null; // 既定描画へフォールバック
    return MarkdownCodeBlock(
      code: element.textContent,
      language: language,
      isDark: isDark,
    );
  }
}

/// フェンスドコードブロックのハイライト表示（言語指定時）。
///
/// [MarkdownHighlighter] で TextSpan を生成し、横スクロール付きで表示する。
/// 長さ上限（kMaxHighlightChars）超過はハイライトせずプレーン表示（M-3）。
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.isDark,
  });

  final String code;
  final String language;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTheme.monoTextStyle.copyWith(
      fontSize: 13,
      color: isDark ? DesignColors.textPrimary : DesignColors.textPrimaryLight,
    );
    final span = MarkdownHighlighter(
      isDark: isDark,
    ).highlight(code, language, baseStyle: baseStyle);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(span),
      ),
    );
  }
}
