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

  const MultiplexerPane({
    required this.index,
    required this.id,
    this.active = false,
    this.currentPath,
  });

  MultiplexerPane copyWith({
    int? index,
    String? id,
    bool? active,
    String? currentPath,
  }) {
    return MultiplexerPane(
      index: index ?? this.index,
      id: id ?? this.id,
      active: active ?? this.active,
      currentPath: currentPath ?? this.currentPath,
    );
  }

  @override
  String toString() =>
      'MultiplexerPane($index: $id, active: $active, currentPath: $currentPath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexerPane && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
