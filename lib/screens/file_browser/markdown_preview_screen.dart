/// Markdown プレビュー画面の公開面を供給する thin re-export シム。
///
/// 責務分割（P3 責務ベース再設計）のため、実装本体は配下へ移設済み:
/// - `markdown_preview/markdown_preview_screen.dart`: 画面 + 単一状態所有者
/// - `markdown_preview/markdown_preview_body.dart`: 状態→ビューの表示層
/// - `markdown_preview/markdown_code_block.dart`: フェンスドコード表示
/// - `markdown_preview/markdown_scroll_keys.dart`: スクロール安定キー（中立）
library;

export 'markdown_preview/markdown_code_block.dart' show MarkdownCodeBlock;
export 'markdown_preview/markdown_preview_screen.dart'
    show MarkdownPreviewScreen;
