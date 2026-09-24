import 'package:flutter/widgets.dart';

import '../widgets/ansi_text_view.dart' show AnsiTextViewState;

/// `GlobalKey<AnsiTextViewState>` を唯一の窓口として viewport 操作を公開する
/// 中立 seam。
///
/// HEAD の `_ansiTextViewKey.currentState?.…` 直接呼出（9 箇所）をここへ
/// 集約する。呼び出しはすべて `?.` の null 許容を維持する（`AnsiTextView` が
/// 組み立てられる前・破棄後は無害 no-op）。
class TerminalViewportPort {
  TerminalViewportPort(this.widgetKey);

  /// `AnsiTextView(key: …)` に渡す GlobalKey（root build が使用）。
  final GlobalKey<AnsiTextViewState> widgetKey;

  AnsiTextViewState? get _view => widgetKey.currentState;

  /// 末尾へスクロール（AnsiTextView `scrollToBottom` への即時委譲）。
  Future<void> scrollToBottom() async {
    await _view?.scrollToBottom();
  }

  /// 上端からの行数補正（`jumpToLineFromTop` への即時委譲）。
  void jumpToLineFromTop(int lineIndex) => _view?.jumpToLineFromTop(lineIndex);

  /// 最下部への追従ジャンプ（`followToBottom` への即時委譲・session 側が利用）。
  void followToBottom() => _view?.followToBottom();

  /// キャレット位置へスクロール（**即時・Raw**。C1 の guarded 版は
  /// `TerminalScrollFollowController.scrollToCaret` が提供する別物）。
  void scrollToCaret() => _view?.scrollToCaret();

  /// ズームをリセット（ui のメニュー `resetZoom` が利用）。
  void resetZoom() => _view?.resetZoom();
}
