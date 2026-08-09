import 'multiplexer_window.dart';

/// 共通マルチプレクサのセッション（tmux session / herdr workspace 相当）。
///
/// 表示に使うフィールドのみを保持する不変クラス。
class MultiplexerSession {
  /// セッション名（tmux: session.name / herdr: workspace.label（空なら id））。
  final String name;

  /// セッション ID（tmux: "$0" / herdr: "w1"）。
  final String? id;

  /// 配下のウィンドウ数。
  final int windowCount;

  /// アタッチ中かどうか（herdr では workspace のフォーカス状態）。
  final bool attached;

  /// 配下のウィンドウ。
  final List<MultiplexerWindow> windows;

  const MultiplexerSession({
    required this.name,
    this.id,
    this.windowCount = 0,
    this.attached = false,
    this.windows = const [],
  });

  MultiplexerSession copyWith({
    String? name,
    String? id,
    int? windowCount,
    bool? attached,
    List<MultiplexerWindow>? windows,
  }) {
    return MultiplexerSession(
      name: name ?? this.name,
      id: id ?? this.id,
      windowCount: windowCount ?? this.windowCount,
      attached: attached ?? this.attached,
      windows: windows ?? this.windows,
    );
  }

  @override
  String toString() =>
      'MultiplexerSession($name, windows: $windowCount, attached: $attached)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexerSession &&
          runtimeType == other.runtimeType &&
          _identityKey == other._identityKey;

  @override
  int get hashCode => _identityKey.hashCode;

  /// 同一性キー: id があれば `id__name`、無ければ `name`（旧データ互換）。
  String get _identityKey =>
      id != null && id!.isNotEmpty ? '${id}__$name' : name;
}
