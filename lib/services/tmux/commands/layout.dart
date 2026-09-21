// inventory: TMUX-LAYOUT-000
/// tmux レイアウト・分割方向の定義
library;

// inventory: TMUX-ENUM-001
/// ペイン分割方向
enum SplitDirection {
  /// 右に分割（左右に並べる） - tmux split-window -h
  horizontal,

  /// 下に分割（上下に並べる） - tmux split-window -v
  vertical,
}

// inventory: TMUX-ENUM-002
/// tmuxレイアウト
enum TmuxLayout {
  /// 均等に水平分割
  evenHorizontal,

  /// 均等に垂直分割
  evenVertical,

  /// メインペインを上に配置
  mainHorizontal,

  /// メインペインを左に配置
  mainVertical,

  /// タイル状に配置
  tiled,
}

extension TmuxLayoutExtension on TmuxLayout {
  // inventory: TMUX-EXT-001
  String get name {
    switch (this) {
      case TmuxLayout.evenHorizontal:
        return 'even-horizontal';
      case TmuxLayout.evenVertical:
        return 'even-vertical';
      case TmuxLayout.mainHorizontal:
        return 'main-horizontal';
      case TmuxLayout.mainVertical:
        return 'main-vertical';
      case TmuxLayout.tiled:
        return 'tiled';
    }
  }
}
