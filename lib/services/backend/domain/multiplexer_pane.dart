/// 共通マルチプレクサのペイン（tmux pane / herdr pane 相当）。
///
/// 表示に使うフィールドのみを保持する不変クラス。
/// 既存の tmux/herdr モデルは変更せず、変換は各 backend の
/// `*_to_domain.dart` 側で行う。
class MultiplexerPane {
  /// インデックス（tmux: pane.index / herdr: pane_id から数値抽出、不能ならリスト順）。
  final int index;

  /// ペイン ID（tmux: "%0" / herdr: "w1:p1"）。
  final String id;

  /// フォーカス中かどうか。
  final bool active;

  /// プロセスのカレントディレクトリ。
  final String? currentPath;

  /// 表示領域の左端（絶対座標。不明なら 0）。
  final int left;

  /// 表示領域の上端（絶対座標。不明なら 0）。
  final int top;

  /// 表示領域の文字幅（不明なら 0）。
  final int width;

  /// 表示領域の文字高さ（不明なら 0）。
  final int height;

  const MultiplexerPane({
    required this.index,
    required this.id,
    this.active = false,
    this.currentPath,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
  });

  MultiplexerPane copyWith({
    int? index,
    String? id,
    bool? active,
    String? currentPath,
    int? left,
    int? top,
    int? width,
    int? height,
  }) {
    return MultiplexerPane(
      index: index ?? this.index,
      id: id ?? this.id,
      active: active ?? this.active,
      currentPath: currentPath ?? this.currentPath,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  String toString() =>
      'MultiplexerPane($index: $id, active: $active, currentPath: $currentPath, '
      'rect: ($left,$top ${width}x$height))';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexerPane &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
