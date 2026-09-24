// P4: root State（`_TerminalScreenState`）が合成アダプタへ提供する最小アクセスの
// 中立インターフェース。
//
// root → adapter → ports → 本ファイル の一方向依存にするため、
// `terminal_root_bindings.dart` から切り出した（循環 import の解消）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend/domain/pane_content_reader.dart';
import '../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../widgets/scroll_to_bottom_button.dart'
    show ScrollToBottomButtonState;
import 'widgets/ansi_text_view.dart' show AnsiTextViewState;

/// root State（`_TerminalScreenState`）が adapter へ提供する最小アクセス。
///
/// framework / widget props / GlobalKey のみ。ポート実装・env 生成は adapter 側。
abstract interface class TerminalScreenAccess {
  WidgetRef get ref;
  bool get isMounted;
  bool get isDisposed;
  BuildContext get context;
  void markNeedsBuild();

  // widget props
  String get connectionId;
  String? get sessionName;
  String? get sessionId;
  int? get lastWindowIndex;
  String? get lastPaneId;
  String? get deepLinkWindowName;
  int? get deepLinkPaneIndex;
  String? get initialPaneId;
  PaneContentReader? get injectedPaneContentReader;
  DateTime Function()? get herdrCacheClock;
  HerdrCaretSnapshotReader? get herdrCaretReader;

  // GlobalKey（root 所有・シェルと AnsiTextView が使用）
  GlobalKey<AnsiTextViewState> get ansiTextViewKey;
  GlobalKey<ScrollToBottomButtonState> get scrollToBottomKey;
}
