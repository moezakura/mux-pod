// inventory: TERM-SCREEN-002
// ポーリングで頻繁に更新されるターミナル表示データを管理する不変モデル。
// ValueNotifierで管理し、親ウィジェットのsetState()を回避する。
import '../../../services/backend/domain/pane_frame_reader.dart';

/// ポーリングで頻繁に更新されるターミナル表示データ。
// inventory: LEGACY-0059
class TerminalViewData {
  // inventory: LEGACY-0060
  final String content;
  // inventory: LEGACY-0061
  final int paneWidth;
  // inventory: LEGACY-0062
  final int paneHeight;

  /// herdr カーソル情報（Phase 4）。null なら AnsiTextView は従来の
  /// cursorX/cursorY（tmux 等）を使う。pane 切替・設定 OFF では明示的に
  /// null へ戻す（旧 pane の caret を表示しない）。
  final PaneCaret? caret;

  const TerminalViewData({
    this.content = '',
    this.paneWidth = 80,
    this.paneHeight = 24,
    this.caret,
  });

  /// copyWith で nullable フィールド（[caret]）を明示的に null へ戻せるように
  /// するためのセンチネル（未指定 = 現状維持。null 指定 = クリア）。
  static const Object _unset = Object();

  TerminalViewData copyWith({
    String? content,
    int? paneWidth,
    int? paneHeight,
    Object? caret = _unset,
  }) => TerminalViewData(
    content: content ?? this.content,
    paneWidth: paneWidth ?? this.paneWidth,
    paneHeight: paneHeight ?? this.paneHeight,
    caret: identical(caret, _unset) ? this.caret : caret as PaneCaret?,
  );
}

/// カーソル値の等価比較（軽量・フィールド比較）。
///
/// 同一インスタンスなら値を比較せず true（poll の高速パス）。
bool caretEquals(PaneCaret? a, PaneCaret? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.x == b.x &&
      a.y == b.y &&
      a.visible == b.visible &&
      a.shape == b.shape &&
      a.frameWidth == b.frameWidth &&
      a.frameHeight == b.frameHeight;
}
