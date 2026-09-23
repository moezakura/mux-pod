import 'package:flutter/material.dart';

/// Markdown プレビュー画面の Raw/Rendered 各ビュー用スクロール安定キー。
///
/// 画面本体（`markdown_preview/markdown_preview_screen.dart`）と表示層
/// （`markdown_preview/markdown_preview_body.dart`）の双方から参照される
/// 中立値。screens の他ファイルへは依存しない（相互循環参照の防止）。
/// `MarkdownPreviewScreen.rawScrollKey` / `.renderedScrollKey`（テストの
/// クラス静的参照）はこの const 値への委譲 getter として定義される。
abstract final class MarkdownScrollKeys {
  static const Key rawScrollKey = Key('mdScrollRaw');
  static const Key renderedScrollKey = Key('mdScrollRendered');
}
