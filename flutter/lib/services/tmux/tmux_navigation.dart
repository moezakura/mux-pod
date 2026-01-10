import '../ssh/ssh_client.dart';
import 'tmux_commands.dart';

/// tmuxナビゲーションサービス
///
/// セッション/ウィンドウ/ペイン間のナビゲーションを提供する。
class TmuxNavigationService {
  TmuxNavigationService({
    required TmuxCommands commands,
    required SshClient sshClient,
  })  : _commands = commands,
        _sshClient = sshClient;

  final TmuxCommands _commands;
  final SshClient _sshClient;

  // === セッションナビゲーション ===

  /// 次のセッションに移動
  Future<String?> nextSession({
    required String connectionId,
    required String currentSessionName,
  }) async {
    final sessions = await _commands.listSessions(connectionId);
    if (sessions.isEmpty) return null;

    final currentIndex = sessions.indexWhere((s) => s.name == currentSessionName);
    if (currentIndex == -1) return sessions.first.name;

    final nextIndex = (currentIndex + 1) % sessions.length;
    return sessions[nextIndex].name;
  }

  /// 前のセッションに移動
  Future<String?> previousSession({
    required String connectionId,
    required String currentSessionName,
  }) async {
    final sessions = await _commands.listSessions(connectionId);
    if (sessions.isEmpty) return null;

    final currentIndex = sessions.indexWhere((s) => s.name == currentSessionName);
    if (currentIndex == -1) return sessions.first.name;

    final prevIndex = (currentIndex - 1 + sessions.length) % sessions.length;
    return sessions[prevIndex].name;
  }

  /// セッション作成
  Future<void> createSession({
    required String connectionId,
    required String name,
    bool attach = false,
  }) async {
    await _commands.newSession(
      connectionId: connectionId,
      name: name,
      detached: !attach,
    );
  }

  /// セッション削除
  Future<void> deleteSession({
    required String connectionId,
    required String name,
  }) async {
    await _commands.killSession(
      connectionId: connectionId,
      name: name,
    );
  }

  /// セッション名変更
  Future<void> renameSession({
    required String connectionId,
    required String oldName,
    required String newName,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux rename-session -t "$oldName" "$newName"',
    );

    if (!result.success) {
      throw Exception('Failed to rename session: ${result.stderr}');
    }
  }

  // === ウィンドウナビゲーション ===

  /// 次のウィンドウに移動
  Future<int?> nextWindow({
    required String connectionId,
    required String sessionName,
    required int currentWindowIndex,
  }) async {
    final windows = await _commands.listWindows(
      connectionId: connectionId,
      sessionName: sessionName,
    );
    if (windows.isEmpty) return null;

    final currentIdx = windows.indexWhere((w) => w.index == currentWindowIndex);
    if (currentIdx == -1) return windows.first.index;

    final nextIdx = (currentIdx + 1) % windows.length;
    final nextWindow = windows[nextIdx];

    await _commands.selectWindow(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: nextWindow.index,
    );

    return nextWindow.index;
  }

  /// 前のウィンドウに移動
  Future<int?> previousWindow({
    required String connectionId,
    required String sessionName,
    required int currentWindowIndex,
  }) async {
    final windows = await _commands.listWindows(
      connectionId: connectionId,
      sessionName: sessionName,
    );
    if (windows.isEmpty) return null;

    final currentIdx = windows.indexWhere((w) => w.index == currentWindowIndex);
    if (currentIdx == -1) return windows.first.index;

    final prevIdx = (currentIdx - 1 + windows.length) % windows.length;
    final prevWindow = windows[prevIdx];

    await _commands.selectWindow(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: prevWindow.index,
    );

    return prevWindow.index;
  }

  /// ウィンドウ作成
  Future<int> createWindow({
    required String connectionId,
    required String sessionName,
    String? name,
  }) async {
    final nameFlag = name != null ? ' -n "$name"' : '';
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux new-window -t "$sessionName"$nameFlag -P -F "#{window_index}"',
    );

    if (!result.success) {
      throw Exception('Failed to create window: ${result.stderr}');
    }

    return int.parse(result.stdout.trim());
  }

  /// ウィンドウ削除
  Future<void> deleteWindow({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux kill-window -t "$sessionName:$windowIndex"',
    );

    if (!result.success) {
      throw Exception('Failed to delete window: ${result.stderr}');
    }
  }

  /// ウィンドウ名変更
  Future<void> renameWindow({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required String newName,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux rename-window -t "$sessionName:$windowIndex" "$newName"',
    );

    if (!result.success) {
      throw Exception('Failed to rename window: ${result.stderr}');
    }
  }

  // === ペインナビゲーション ===

  /// 次のペインに移動
  Future<int?> nextPane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int currentPaneIndex,
  }) async {
    final panes = await _commands.listPanes(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowIndex,
    );
    if (panes.isEmpty) return null;

    final currentIdx = panes.indexWhere((p) => p.index == currentPaneIndex);
    if (currentIdx == -1) return panes.first.index;

    final nextIdx = (currentIdx + 1) % panes.length;
    final nextPane = panes[nextIdx];

    await _commands.selectPane(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowIndex,
      paneIndex: nextPane.index,
    );

    return nextPane.index;
  }

  /// 前のペインに移動
  Future<int?> previousPane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int currentPaneIndex,
  }) async {
    final panes = await _commands.listPanes(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowIndex,
    );
    if (panes.isEmpty) return null;

    final currentIdx = panes.indexWhere((p) => p.index == currentPaneIndex);
    if (currentIdx == -1) return panes.first.index;

    final prevIdx = (currentIdx - 1 + panes.length) % panes.length;
    final prevPane = panes[prevIdx];

    await _commands.selectPane(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowIndex,
      paneIndex: prevPane.index,
    );

    return prevPane.index;
  }

  /// 方向指定でペイン移動
  Future<int?> movePaneDirection({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required PaneDirection direction,
  }) async {
    final dirFlag = switch (direction) {
      PaneDirection.up => '-U',
      PaneDirection.down => '-D',
      PaneDirection.left => '-L',
      PaneDirection.right => '-R',
    };

    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux select-pane -t "$sessionName:$windowIndex" $dirFlag',
    );

    if (!result.success) {
      // 移動先がない場合はエラーにならないこともある
      return null;
    }

    // 現在のアクティブペインを取得
    final panes = await _commands.listPanes(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowIndex,
    );

    try {
      return panes.firstWhere((p) => p.active).index;
    } catch (_) {
      return null;
    }
  }

  /// ペイン分割（水平）
  Future<int> splitPaneHorizontal({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command:
          'tmux split-window -h -t "$sessionName:$windowIndex.$paneIndex" -P -F "#{pane_index}"',
    );

    if (!result.success) {
      throw Exception('Failed to split pane: ${result.stderr}');
    }

    return int.parse(result.stdout.trim());
  }

  /// ペイン分割（垂直）
  Future<int> splitPaneVertical({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command:
          'tmux split-window -v -t "$sessionName:$windowIndex.$paneIndex" -P -F "#{pane_index}"',
    );

    if (!result.success) {
      throw Exception('Failed to split pane: ${result.stderr}');
    }

    return int.parse(result.stdout.trim());
  }

  /// ペイン削除
  Future<void> deletePane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux kill-pane -t "$sessionName:$windowIndex.$paneIndex"',
    );

    if (!result.success) {
      throw Exception('Failed to delete pane: ${result.stderr}');
    }
  }

  /// ペインズーム（最大化/元に戻す）
  Future<void> togglePaneZoom({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux resize-pane -t "$sessionName:$windowIndex.$paneIndex" -Z',
    );

    if (!result.success) {
      throw Exception('Failed to toggle zoom: ${result.stderr}');
    }
  }

  // === ユーティリティ ===

  /// 現在のアクティブなターゲットを取得
  Future<TmuxTarget?> getCurrentTarget(String connectionId) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command:
          'tmux display-message -p "#{session_name}\t#{window_index}\t#{pane_index}"',
    );

    if (!result.success) {
      return null;
    }

    final parts = result.stdout.trim().split('\t');
    if (parts.length != 3) return null;

    return TmuxTarget(
      sessionName: parts[0],
      windowIndex: int.parse(parts[1]),
      paneIndex: int.parse(parts[2]),
    );
  }

  /// 特定のターゲットに移動
  Future<void> goToTarget({
    required String connectionId,
    required TmuxTarget target,
  }) async {
    await _commands.selectPane(
      connectionId: connectionId,
      sessionName: target.sessionName,
      windowIndex: target.windowIndex,
      paneIndex: target.paneIndex,
    );
  }
}

/// ペイン移動方向
enum PaneDirection {
  up,
  down,
  left,
  right,
}

/// tmuxターゲット（セッション:ウィンドウ.ペイン）
class TmuxTarget {
  final String sessionName;
  final int windowIndex;
  final int paneIndex;

  const TmuxTarget({
    required this.sessionName,
    required this.windowIndex,
    required this.paneIndex,
  });

  String get targetString => '$sessionName:$windowIndex.$paneIndex';

  @override
  String toString() => targetString;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmuxTarget &&
          runtimeType == other.runtimeType &&
          sessionName == other.sessionName &&
          windowIndex == other.windowIndex &&
          paneIndex == other.paneIndex;

  @override
  int get hashCode =>
      sessionName.hashCode ^ windowIndex.hashCode ^ paneIndex.hashCode;
}
