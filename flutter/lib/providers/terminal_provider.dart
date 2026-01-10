import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal/terminal_controller.dart' show SshTerminalController;
import 'ssh_provider.dart';

/// ターミナルコントローラー プロバイダー（接続IDごと）
final terminalControllerProvider =
    Provider.family.autoDispose<SshTerminalController, String>((ref, connectionId) {
  final sshClient = ref.watch(sshClientProvider);

  final controller = SshTerminalController(
    connectionId: connectionId,
    sshClient: sshClient,
  );

  ref.onDispose(() {
    controller.dispose();
  });

  return controller;
});

/// ターミナル状態プロバイダー（接続IDごと）
final terminalStateProvider = StateNotifierProvider.family
    .autoDispose<TerminalStateNotifier, TerminalState, String>(
  (ref, connectionId) => TerminalStateNotifier(connectionId),
);

/// ターミナル状態
class TerminalState {
  final bool isConnected;
  final bool isLoading;
  final String? error;
  final int width;
  final int height;
  final bool showSpecialKeys;

  const TerminalState({
    this.isConnected = false,
    this.isLoading = false,
    this.error,
    this.width = 80,
    this.height = 24,
    this.showSpecialKeys = true,
  });

  TerminalState copyWith({
    bool? isConnected,
    bool? isLoading,
    String? error,
    int? width,
    int? height,
    bool? showSpecialKeys,
  }) {
    return TerminalState(
      isConnected: isConnected ?? this.isConnected,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      width: width ?? this.width,
      height: height ?? this.height,
      showSpecialKeys: showSpecialKeys ?? this.showSpecialKeys,
    );
  }
}

/// ターミナル状態Notifier
class TerminalStateNotifier extends StateNotifier<TerminalState> {
  TerminalStateNotifier(this.connectionId) : super(const TerminalState());

  final String connectionId;

  /// ローディング開始
  void setLoading() {
    state = state.copyWith(isLoading: true, error: null);
  }

  /// 接続成功
  void setConnected() {
    state = state.copyWith(isConnected: true, isLoading: false, error: null);
  }

  /// 切断
  void setDisconnected() {
    state = state.copyWith(isConnected: false, isLoading: false);
  }

  /// エラー
  void setError(String error) {
    state = state.copyWith(isLoading: false, error: error);
  }

  /// エラークリア
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// サイズ変更
  void setSize(int width, int height) {
    state = state.copyWith(width: width, height: height);
  }

  /// 特殊キー表示切り替え
  void toggleSpecialKeys() {
    state = state.copyWith(showSpecialKeys: !state.showSpecialKeys);
  }
}
