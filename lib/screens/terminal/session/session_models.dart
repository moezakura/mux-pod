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

  /// herdr 通常表示のリンク情報。null なら AnsiTextView はリンク
  /// 重ね合わせを行わない（パーサ由来の OSC 8 のみ）。pane 切替・設定 OFF
  /// では明示的に null へ戻す（旧 pane のリンクを表示しない・caret と同じ
  /// 契約）。
  final PaneHyperlinks? hyperlinks;

  const TerminalViewData({
    this.content = '',
    this.paneWidth = 80,
    this.paneHeight = 24,
    this.caret,
    this.hyperlinks,
  });

  /// copyWith で nullable フィールド（[caret] / [hyperlinks]）を明示的に
  /// null へ戻せるようにするためのセンチネル（未指定 = 現状維持。
  /// null 指定 = クリア）。
  static const Object _unset = Object();

  TerminalViewData copyWith({
    String? content,
    int? paneWidth,
    int? paneHeight,
    Object? caret = _unset,
    Object? hyperlinks = _unset,
  }) => TerminalViewData(
    content: content ?? this.content,
    paneWidth: paneWidth ?? this.paneWidth,
    paneHeight: paneHeight ?? this.paneHeight,
    caret: identical(caret, _unset) ? this.caret : caret as PaneCaret?,
    hyperlinks: identical(hyperlinks, _unset)
        ? this.hyperlinks
        : hyperlinks as PaneHyperlinks?,
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

/// リンク結果の等価比較（軽量・フィールド比較）。
///
/// 同一インスタンスなら値を比較せず true（poll の高速パス）。[PaneHyperlinks]
/// は `==`/`hashCode` を override しないため、[caretEquals] と同じ形の free
/// function として提供する。
bool paneHyperlinksEquals(PaneHyperlinks? a, PaneHyperlinks? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.frameWidth != b.frameWidth ||
      a.frameHeight != b.frameHeight ||
      a.truncated != b.truncated ||
      a.links.length != b.links.length ||
      a.rowFingerprints.length != b.rowFingerprints.length) {
    return false;
  }
  for (var i = 0; i < a.links.length; i++) {
    final linkA = a.links[i];
    final linkB = b.links[i];
    if (linkA.url != linkB.url || linkA.ranges.length != linkB.ranges.length) {
      return false;
    }
    for (var j = 0; j < linkA.ranges.length; j++) {
      final rangeA = linkA.ranges[j];
      final rangeB = linkB.ranges[j];
      if (rangeA.row != rangeB.row ||
          rangeA.startCol != rangeB.startCol ||
          rangeA.endCol != rangeB.endCol) {
        return false;
      }
    }
  }
  for (final entry in a.rowFingerprints.entries) {
    if (b.rowFingerprints[entry.key] != entry.value) return false;
  }
  return true;
}
