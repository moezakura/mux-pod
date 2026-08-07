import 'multiplexer_pane.dart';

/// 共通マルチプレクサのウィンドウ（tmux window / herdr tab 相当）。
///
/// 表示に使うフィールドのみを保持する不変クラス。
class MultiplexerWindow {
  /// インデックス（tmux: window.index / herdr: tab.number）。
  final int index;

  /// ウィンドウ ID（tmux: "@0" / herdr: "w1:t1"）。
  final String? id;

  /// 表示名（tmux: window.name / herdr: tab.label（null なら id））。
  final String name;

  /// フォーカス中かどうか。
  final bool active;

  /// 配下のペイン数。
  final int paneCount;

  /// 配下のペイン。
  final List<MultiplexerPane> panes;

  const MultiplexerWindow({
    required this.index,
    this.id,
    required this.name,
    this.active = false,
    this.paneCount = 0,
    this.panes = const [],
  });

  MultiplexerWindow copyWith({
    int? index,
    String? id,
    String? name,
    bool? active,
    int? paneCount,
    List<MultiplexerPane>? panes,
  }) {
    return MultiplexerWindow(
      index: index ?? this.index,
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      paneCount: paneCount ?? this.paneCount,
      panes: panes ?? this.panes,
    );
  }

  @override
  String toString() =>
      'MultiplexerWindow($index: $name, panes: $paneCount, active: $active)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexerWindow &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          id == other.id;

  @override
  int get hashCode => Object.hash(index, id);
}
