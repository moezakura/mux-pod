import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/markdown_preview_provider.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/design_colors.dart';
import '../widgets/sftp_markdown_image.dart';
import 'markdown_code_block.dart';
import 'markdown_scroll_keys.dart';

/// Markdown プレビュー画面の状態→ビュー構築（プレゼンテーション層）。
///
/// 状態・コントローラ・トグル比率連動・再読込は親の
/// [MarkdownPreviewScreen]（State）が所有し、本 widget は props
/// （state / controllers / showRendered / mdBaseDirectory / onReload）を
/// 受けて表示のみを行う。スクロール安定キーは中立
/// [MarkdownScrollKeys] を参照する（画面本体を import しない・相互循環防止）。
class MarkdownPreviewBody extends StatelessWidget {
  const MarkdownPreviewBody({
    super.key,
    required this.state,
    required this.rawController,
    required this.renderedController,
    required this.showRendered,
    required this.mdBaseDirectory,
    required this.onReload,
  });

  /// Markdown の状態（provider 由来・読み取り専用）。
  final MarkdownPreviewState state;

  /// raw / rendered の各ビュー用スクロールコントローラ（親所有）。
  final ScrollController rawController;
  final ScrollController renderedController;

  /// 表示中ビュー（true = Rendered）。
  final bool showRendered;

  /// 相対画像の SFTP 解決基準ディレクトリ（親所有）。
  final String mdBaseDirectory;

  /// 再読込コールバック（エラー時の再試行ボタン）。
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

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
                onPressed: onReload,
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
          child: showRendered
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
      key: MarkdownScrollKeys.renderedScrollKey,
      controller: renderedController,
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: state.content,
        // C-2: syntaxHighlighter は言語を渡せないため不使用。
        // code 要素の class 属性（language-xxx）から言語を抽出してハイライト。
        builders: {'code': MarkdownCodeElementBuilder(isDark: isDark)},
        imageBuilder: (uri, title, alt) =>
            _buildImage(context, uri, title, alt),
        onTapLink: markdownOnTapLink,
      ),
    );
  }

  /// Raw ビュー（生テキスト・per-view scroll controller 付き）。
  Widget _buildRawView(MarkdownPreviewState state, bool isDark) {
    return SingleChildScrollView(
      key: MarkdownScrollKeys.rawScrollKey,
      controller: rawController,
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
      mdBaseDirectory: mdBaseDirectory,
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
}

/// リンクタップ時の scheme ガード（計画 §L2-4・L-2）。
///
/// https/http のみ [launchUrl]（OS 外部ブラウザ・about_section.dart パターン）。
/// `#anchor`（scheme 無し）・`mailto:`・`data:`・`javascript:`・`file:` 等は
/// 何もしない（タップ無視）。スキーム検証は [Uri.tryParse] で明示する。
void markdownOnTapLink(String text, String? href, String title) {
  if (href == null) return;
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return;
  markdownLaunchExternal(uri);
}

Future<void> markdownLaunchExternal(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
