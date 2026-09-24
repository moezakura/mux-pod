import '../../../services/backend/domain/pane_frame_reader.dart' show PaneCaret;

// inventory: TERM-ENUM-001
/// スクロールモードのソース
enum ScrollModeSource {
  /// 通常モード（スクロールモードではない）
  none,

  /// ユーザーが UI から手動で有効化
  manual,

  /// tmux copy-mode を自動検出
  tmux,
}

/// 選択モード中にバッファリングされた更新（C7）。
///
/// [content] と同一フレームから合成された [caret]・表示対象同一性
/// [targetIdentity]（`Object?` の不透明トークン。herdr の表示対象判定のみが
/// 中身を知る）がセットで保持される。適用時に [TerminalTargetIdentityValidator]
/// が照合し、不一致なら破棄される。
class TerminalBufferedUpdate {
  const TerminalBufferedUpdate({
    required this.content,
    this.caret,
    this.targetIdentity,
  });

  /// バッファリングされたペイン内容。
  final String content;

  /// 同一フレームから合成された caret（表示への反映に使う）。
  final PaneCaret? caret;

  /// バッファ時点の表示対象同一性（適用時の破棄判定に使う）。
  final Object? targetIdentity;
}
