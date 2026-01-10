import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tmux.dart';
import '../services/tmux/tmux_commands.dart';
import '../services/tmux/tmux_navigation.dart';
import 'ssh_provider.dart';

/// TmuxCommands プロバイダー
final tmuxCommandsProvider = Provider<TmuxCommands>((ref) {
  return TmuxCommands(
    sshClient: ref.watch(sshClientProvider),
  );
});

/// TmuxNavigationService プロバイダー
final tmuxNavigationProvider = Provider<TmuxNavigationService>((ref) {
  return TmuxNavigationService(
    commands: ref.watch(tmuxCommandsProvider),
    sshClient: ref.watch(sshClientProvider),
  );
});

/// セッション一覧プロバイダー（接続IDごと）
final tmuxSessionsProvider =
    FutureProvider.family<List<TmuxSession>, String>((ref, connectionId) async {
  final commands = ref.watch(tmuxCommandsProvider);
  final sshClient = ref.watch(sshClientProvider);

  if (!sshClient.isConnected(connectionId)) {
    return [];
  }

  final sessions = await commands.listSessions(connectionId);

  // セッションごとにウィンドウ一覧を取得
  final fullSessions = <TmuxSession>[];
  for (final session in sessions) {
    final windows = await _loadWindowsWithPanes(
      commands: commands,
      connectionId: connectionId,
      sessionName: session.name,
    );

    fullSessions.add(TmuxSession(
      name: session.name,
      created: session.created,
      attached: session.attached,
      windowCount: session.windowCount,
      windows: windows,
    ));
  }

  return fullSessions;
});

/// ウィンドウとペインを読み込む
Future<List<TmuxWindow>> _loadWindowsWithPanes({
  required TmuxCommands commands,
  required String connectionId,
  required String sessionName,
}) async {
  final windowInfos = await commands.listWindows(
    connectionId: connectionId,
    sessionName: sessionName,
  );

  final windows = <TmuxWindow>[];
  for (final windowInfo in windowInfos) {
    final paneInfos = await commands.listPanes(
      connectionId: connectionId,
      sessionName: sessionName,
      windowIndex: windowInfo.index,
    );

    final panes = paneInfos
        .map((p) => TmuxPane(
              index: p.index,
              id: p.id,
              active: p.active,
              currentCommand: p.currentCommand,
              title: p.title,
              width: p.width,
              height: p.height,
              cursorX: p.cursorX,
              cursorY: p.cursorY,
            ))
        .toList();

    windows.add(TmuxWindow(
      index: windowInfo.index,
      name: windowInfo.name,
      active: windowInfo.active,
      paneCount: windowInfo.paneCount,
      panes: panes,
    ));
  }

  return windows;
}

/// tmux操作コントローラー プロバイダー（接続IDごと）
final tmuxControllerProvider = AsyncNotifierProvider.family
    .autoDispose<TmuxController, TmuxNavigationState?, String>(
  TmuxController.new,
);

/// tmuxナビゲーション状態
class TmuxNavigationState {
  final String sessionName;
  final int windowIndex;
  final int paneIndex;

  const TmuxNavigationState({
    required this.sessionName,
    required this.windowIndex,
    required this.paneIndex,
  });

  TmuxNavigationState copyWith({
    String? sessionName,
    int? windowIndex,
    int? paneIndex,
  }) {
    return TmuxNavigationState(
      sessionName: sessionName ?? this.sessionName,
      windowIndex: windowIndex ?? this.windowIndex,
      paneIndex: paneIndex ?? this.paneIndex,
    );
  }
}

/// tmux操作コントローラー
class TmuxController
    extends AutoDisposeFamilyAsyncNotifier<TmuxNavigationState?, String> {
  @override
  Future<TmuxNavigationState?> build(String arg) async {
    return null;
  }

  TmuxCommands get _commands => ref.read(tmuxCommandsProvider);
  TmuxNavigationService get _navigation => ref.read(tmuxNavigationProvider);
  String get connectionId => arg;

  /// セッション選択
  Future<void> selectSession(String sessionName) async {
    state = AsyncValue.data(TmuxNavigationState(
      sessionName: sessionName,
      windowIndex: 0,
      paneIndex: 0,
    ));
  }

  /// 次のセッションに移動
  Future<void> nextSession() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final nextName = await _navigation.nextSession(
      connectionId: connectionId,
      currentSessionName: current.sessionName,
    );

    if (nextName != null) {
      state = AsyncValue.data(TmuxNavigationState(
        sessionName: nextName,
        windowIndex: 0,
        paneIndex: 0,
      ));
    }
  }

  /// 前のセッションに移動
  Future<void> previousSession() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final prevName = await _navigation.previousSession(
      connectionId: connectionId,
      currentSessionName: current.sessionName,
    );

    if (prevName != null) {
      state = AsyncValue.data(TmuxNavigationState(
        sessionName: prevName,
        windowIndex: 0,
        paneIndex: 0,
      ));
    }
  }

  /// ウィンドウ選択
  Future<void> selectWindow(int windowIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;

    await _commands.selectWindow(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: windowIndex,
    );

    state = AsyncValue.data(current.copyWith(
      windowIndex: windowIndex,
      paneIndex: 0,
    ));
  }

  /// 次のウィンドウに移動
  Future<void> nextWindow() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final nextIdx = await _navigation.nextWindow(
      connectionId: connectionId,
      sessionName: current.sessionName,
      currentWindowIndex: current.windowIndex,
    );

    if (nextIdx != null) {
      state = AsyncValue.data(current.copyWith(
        windowIndex: nextIdx,
        paneIndex: 0,
      ));
    }
  }

  /// 前のウィンドウに移動
  Future<void> previousWindow() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final prevIdx = await _navigation.previousWindow(
      connectionId: connectionId,
      sessionName: current.sessionName,
      currentWindowIndex: current.windowIndex,
    );

    if (prevIdx != null) {
      state = AsyncValue.data(current.copyWith(
        windowIndex: prevIdx,
        paneIndex: 0,
      ));
    }
  }

  /// ペイン選択
  Future<void> selectPane(int paneIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;

    await _commands.selectPane(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: paneIndex,
    );

    state = AsyncValue.data(current.copyWith(paneIndex: paneIndex));
  }

  /// 次のペインに移動
  Future<void> nextPane() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final nextIdx = await _navigation.nextPane(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      currentPaneIndex: current.paneIndex,
    );

    if (nextIdx != null) {
      state = AsyncValue.data(current.copyWith(paneIndex: nextIdx));
    }
  }

  /// 前のペインに移動
  Future<void> previousPane() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final prevIdx = await _navigation.previousPane(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      currentPaneIndex: current.paneIndex,
    );

    if (prevIdx != null) {
      state = AsyncValue.data(current.copyWith(paneIndex: prevIdx));
    }
  }

  /// 方向指定でペイン移動
  Future<void> movePaneDirection(PaneDirection direction) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final newIdx = await _navigation.movePaneDirection(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      direction: direction,
    );

    if (newIdx != null) {
      state = AsyncValue.data(current.copyWith(paneIndex: newIdx));
    }
  }

  /// セッション作成
  Future<void> createSession(String name) async {
    await _navigation.createSession(
      connectionId: connectionId,
      name: name,
    );
    // 新しいセッションに移動
    state = AsyncValue.data(TmuxNavigationState(
      sessionName: name,
      windowIndex: 0,
      paneIndex: 0,
    ));
    // セッション一覧を更新
    ref.invalidate(tmuxSessionsProvider(connectionId));
  }

  /// ウィンドウ作成
  Future<void> createWindow({String? name}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final newIdx = await _navigation.createWindow(
      connectionId: connectionId,
      sessionName: current.sessionName,
      name: name,
    );

    state = AsyncValue.data(current.copyWith(
      windowIndex: newIdx,
      paneIndex: 0,
    ));
    ref.invalidate(tmuxSessionsProvider(connectionId));
  }

  /// ペイン分割（水平）
  Future<void> splitPaneHorizontal() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final newIdx = await _navigation.splitPaneHorizontal(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: current.paneIndex,
    );

    state = AsyncValue.data(current.copyWith(paneIndex: newIdx));
    ref.invalidate(tmuxSessionsProvider(connectionId));
  }

  /// ペイン分割（垂直）
  Future<void> splitPaneVertical() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final newIdx = await _navigation.splitPaneVertical(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: current.paneIndex,
    );

    state = AsyncValue.data(current.copyWith(paneIndex: newIdx));
    ref.invalidate(tmuxSessionsProvider(connectionId));
  }

  /// ペインズーム切り替え
  Future<void> togglePaneZoom() async {
    final current = state.valueOrNull;
    if (current == null) return;

    await _navigation.togglePaneZoom(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: current.paneIndex,
    );
  }

  /// キー送信
  Future<void> sendKeys(String keys, {bool literal = false}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    await _commands.sendKeys(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: current.paneIndex,
      keys: keys,
      literal: literal,
    );
  }

  /// ペイン内容取得
  Future<List<String>> capturePane({int? startLine, int? endLine}) async {
    final current = state.valueOrNull;
    if (current == null) return [];

    return await _commands.capturePane(
      connectionId: connectionId,
      sessionName: current.sessionName,
      windowIndex: current.windowIndex,
      paneIndex: current.paneIndex,
      startLine: startLine,
      endLine: endLine,
    );
  }

  /// セッション一覧を再読み込み
  void refresh() {
    ref.invalidate(tmuxSessionsProvider(connectionId));
  }
}
