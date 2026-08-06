/// tmuxのバージョン情報を保持し、機能の対応状況を判定するクラス
// inventory: TMUX-VER-001
class TmuxVersionInfo {
  final int major;
  final int minor;

  const TmuxVersionInfo(this.major, this.minor);

  /// "tmux 3.4" や "tmux 2.9a" 形式の文字列をパースする
  /// パース失敗時はnullを返す
  // inventory: TMUX-VER-002
  static TmuxVersionInfo? parse(String versionOutput) {
    final match = RegExp(r'tmux\s+(\d+)\.(\d+)').firstMatch(versionOutput);
    if (match == null) return null;
    return TmuxVersionInfo(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  /// resize-window -x -y は tmux 2.9+ で追加
  // inventory: TMUX-VER-003
  bool get supportsResizeWindow => major > 2 || (major == 2 && minor >= 9);

  /// resize-pane -x -y は tmux 1.7+ で追加（実質全バージョン対応）
  // inventory: TMUX-VER-004
  bool get supportsResizePaneToSize => major > 1 || (major == 1 && minor >= 7);

  @override
  String toString() => 'tmux $major.$minor';

  @override
  bool operator ==(Object other) =>
      other is TmuxVersionInfo && major == other.major && minor == other.minor;

  @override
  int get hashCode => Object.hash(major, minor);
}
