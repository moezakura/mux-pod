import '../ssh/ssh_client.dart';
import 'tmux_parser.dart';

/// tmuxコマンドサービス
///
/// tmuxコマンドを実行してセッション/ウィンドウ/ペインを操作する。
class TmuxCommands {
  TmuxCommands({
    required SshClient sshClient,
  }) : _sshClient = sshClient;

  final SshClient _sshClient;
  final TmuxParser _parser = TmuxParser();

  // === セッション操作 ===

  /// セッション一覧取得
  Future<List<TmuxSessionInfo>> listSessions(String connectionId) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux list-sessions -F "#{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}"',
    );

    if (!result.success) {
      if (result.stderr.contains('no server running')) {
        return [];
      }
      throw Exception('Failed to list sessions: ${result.stderr}');
    }

    return _parser.parseSessions(result.stdout);
  }

  /// 新規セッション作成
  Future<void> newSession({
    required String connectionId,
    required String name,
    bool detached = true,
  }) async {
    final detachFlag = detached ? ' -d' : '';
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux new-session$detachFlag -s "$name"',
    );

    if (!result.success) {
      throw Exception('Failed to create session: ${result.stderr}');
    }
  }

  /// セッション削除
  Future<void> killSession({
    required String connectionId,
    required String name,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux kill-session -t "$name"',
    );

    if (!result.success) {
      throw Exception('Failed to kill session: ${result.stderr}');
    }
  }

  // === ウィンドウ操作 ===

  /// ウィンドウ一覧取得
  Future<List<TmuxWindowInfo>> listWindows({
    required String connectionId,
    required String sessionName,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux list-windows -t "$sessionName" -F "#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}"',
    );

    if (!result.success) {
      throw Exception('Failed to list windows: ${result.stderr}');
    }

    return _parser.parseWindows(result.stdout);
  }

  /// ウィンドウ選択
  Future<void> selectWindow({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux select-window -t "$sessionName:$windowIndex"',
    );

    if (!result.success) {
      throw Exception('Failed to select window: ${result.stderr}');
    }
  }

  // === ペイン操作 ===

  /// ペイン一覧取得
  Future<List<TmuxPaneInfo>> listPanes({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux list-panes -t "$sessionName:$windowIndex" -F "#{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}"',
    );

    if (!result.success) {
      throw Exception('Failed to list panes: ${result.stderr}');
    }

    return _parser.parsePanes(result.stdout);
  }

  /// ペイン選択
  Future<void> selectPane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux select-pane -t "$sessionName:$windowIndex.$paneIndex"',
    );

    if (!result.success) {
      throw Exception('Failed to select pane: ${result.stderr}');
    }
  }

  /// ペイン内容取得
  Future<List<String>> capturePane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) async {
    final escFlag = escapeSequences ? ' -e' : '';
    final startFlag = startLine != null ? ' -S $startLine' : '';
    final endFlag = endLine != null ? ' -E $endLine' : '';

    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux capture-pane -t "$sessionName:$windowIndex.$paneIndex"$escFlag$startFlag$endFlag -p',
    );

    if (!result.success) {
      throw Exception('Failed to capture pane: ${result.stderr}');
    }

    return result.stdout.split('\n');
  }

  /// キー送信
  Future<void> sendKeys({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    required String keys,
    bool literal = false,
  }) async {
    final literalFlag = literal ? ' -l' : '';
    final escapedKeys = keys.replaceAll('"', r'\"');

    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux send-keys -t "$sessionName:$windowIndex.$paneIndex"$literalFlag "$escapedKeys"',
    );

    if (!result.success) {
      throw Exception('Failed to send keys: ${result.stderr}');
    }
  }

  /// ペインリサイズ
  Future<void> resizePane({
    required String connectionId,
    required String sessionName,
    required int windowIndex,
    required int paneIndex,
    required int width,
    required int height,
  }) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux resize-pane -t "$sessionName:$windowIndex.$paneIndex" -x $width -y $height',
    );

    if (!result.success) {
      throw Exception('Failed to resize pane: ${result.stderr}');
    }
  }

  // === ユーティリティ ===

  /// tmuxインストール確認
  Future<bool> isTmuxInstalled(String connectionId) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'which tmux',
    );

    return result.success && result.stdout.isNotEmpty;
  }

  /// tmuxバージョン取得
  Future<String?> getTmuxVersion(String connectionId) async {
    final result = await _sshClient.exec(
      connectionId: connectionId,
      command: 'tmux -V',
    );

    if (!result.success) {
      return null;
    }

    return result.stdout.trim();
  }
}
