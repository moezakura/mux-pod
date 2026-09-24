// inventory: TERM-SRC-000
/// 現在の表示対象 pane ID の取得抽象（A9）。
///
/// tmux は毎呼出し現在ターゲットへ遅延委譲（null 伝播維持）、herdr は固定
/// pane ID を返す。これにより従来の `??` 分裂
/// （`_pollTargetPaneId ?? tmuxProvider.currentTarget`）を一本化する。
///
/// 抽象に含めるのは `currentPaneId` のみ。`switchTarget` / `fetchTree` は
/// 含めない（tmux に「アプリローカル表示切替」概念がなく、抽象に入れると
/// 嘘の意味論 or no-op になるため。切替は画面メソッドに残す）。
abstract interface class TargetSource {
  /// 現在の表示対象 pane ID（tmux で未確定の場合は null）。
  String? get currentPaneId;
}

// inventory: TERM-SRC-001
/// tmux: 毎呼出し現在ターゲットへ遅延委譲する `TmuxNotifier.currentTarget`。
///
/// 遅延委譲により、tmux の split/kill で index がずれても対象が変わらない
/// 既存挙動を保持する（null 伝播も維持）。
class TmuxTargetSource implements TargetSource {
  final String? Function() _readCurrentTarget;

  TmuxTargetSource(this._readCurrentTarget);

  @override
  String? get currentPaneId => _readCurrentTarget();
}
