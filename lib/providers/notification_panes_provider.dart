
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/keychain/secure_storage.dart';
import '../services/ssh/ssh_client.dart';
import '../services/tmux/tmux_facade.dart';
import '../services/tmux/tmux_models.dart';

import 'connection_provider.dart';

// inventory: NOTIF-001
/// tmuxウィンドウフラグに基づく通知ペイン情報
class AlertPane {
  // inventory: NOTIF-002
  // inventory: LEGACY-0104
  final String connectionId;
  // inventory: NOTIF-003
  // inventory: LEGACY-0105
  final String connectionName;
  // inventory: NOTIF-004
  // inventory: LEGACY-0106
  final String host;
  // inventory: NOTIF-005
  // inventory: LEGACY-0107
  final String sessionName;
  // inventory: NOTIF-006
  // inventory: LEGACY-0108
  final int windowIndex;
  // inventory: NOTIF-007
  // inventory: LEGACY-0109
  final String windowName;
  // inventory: NOTIF-008
  // inventory: LEGACY-0110
  final Set<TmuxWindowFlag> flags;
  // inventory: NOTIF-009
  // inventory: LEGACY-0111
  final String paneId;
  // inventory: NOTIF-010
  // inventory: LEGACY-0112
  final int paneIndex;
  // inventory: NOTIF-011
  // inventory: LEGACY-0113
  final String? currentCommand;

  const AlertPane({
    required this.connectionId,
    required this.connectionName,
    required this.host,
    required this.sessionName,
    required this.windowIndex,
    required this.windowName,
    required this.flags,
    required this.paneId,
    required this.paneIndex,
    this.currentCommand,
  });

  // inventory: NOTIF-012
  // inventory: LEGACY-0114
  String get key => '$connectionId:$sessionName:$windowIndex:$paneId';

  // inventory: NOTIF-013
  // inventory: LEGACY-0115
  /// ウィンドウ単位のキー（同一ウィンドウの全ペインで共通）
  String get windowKey => '$connectionId:$sessionName:$windowIndex';

  // inventory: NOTIF-014
  /// 最も優先度の高いフラグを取得 (bell > activity > silence)
  TmuxWindowFlag? get primaryFlag {
    if (flags.contains(TmuxWindowFlag.bell)) return TmuxWindowFlag.bell;
    if (flags.contains(TmuxWindowFlag.activity)) return TmuxWindowFlag.activity;
    if (flags.contains(TmuxWindowFlag.silence)) return TmuxWindowFlag.silence;
    return null;
  }
}

// inventory: NOTIF-015
/// 通知ペイン一覧の状態
class AlertPanesState {
  // inventory: NOTIF-016
  // inventory: LEGACY-0116
  final List<AlertPane> alertPanes;
  // inventory: NOTIF-017
  // inventory: LEGACY-0117
  final bool isLoading;
  // inventory: NOTIF-018
  // inventory: LEGACY-0118
  final String? error;

  const AlertPanesState({
    this.alertPanes = const [],
    this.isLoading = false,
    this.error,
  });

  // inventory: NOTIF-019
  // inventory: LEGACY-0119
  AlertPanesState copyWith({
    List<AlertPane>? alertPanes,
    bool? isLoading,
    String? error,
  }) {
    return AlertPanesState(
      alertPanes: alertPanes ?? this.alertPanes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// inventory: NOTIF-020
/// 通知ペイン一覧を管理するNotifier
class AlertPanesNotifier extends Notifier<AlertPanesState> {
  // inventory: NOTIF-021
  static const _alertFlags = {
    TmuxWindowFlag.activity,
    TmuxWindowFlag.bell,
    TmuxWindowFlag.silence,
  };

  @override
  // inventory: NOTIF-022
  // inventory: LEGACY-0120
  AlertPanesState build() {
    return const AlertPanesState();
  }

  // inventory: NOTIF-023
  // inventory: LEGACY-0121
  /// アラートをローカルリストから除去
  void dismiss(String key) {
    final updated = state.alertPanes.where((a) => a.key != key).toList();
    state = state.copyWith(alertPanes: updated);
  }

  // inventory: NOTIF-024
  // inventory: LEGACY-0122
  /// tmux側のウィンドウフラグをクリア（select-windowで当該ウィンドウを選択→元に戻す）
  Future<void> clearWindowFlag(AlertPane alert) async {
    final connectionsState = ref.read(connectionsProvider);
    final connection = connectionsState.connections
        .where((c) => c.id == alert.connectionId)
        .firstOrNull;
    if (connection == null) return;

    final storage = SecureStorageService();
    // inventory: LEGACY-0123
    SshConnectOptions options;
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await storage.getPrivateKey(connection.keyId!);
      final passphrase = await storage.getPassphrase(connection.keyId!);
      options = SshConnectOptions(privateKey: privateKey, passphrase: passphrase, tmuxPath: connection.tmuxPath);
    } else {
      final password = await storage.getPassword(connection.id);
      options = SshConnectOptions(password: password, tmuxPath: connection.tmuxPath);
    }

    final sshClient = SshClient();
    try {
      await sshClient.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        options: options,
      );

      // 当該ウィンドウを選択してフラグをクリアし、元のウィンドウに戻す
      await tmuxFacade.selectWindow(
        sshClient.tmuxExecutor,
        alert.sessionName,
        alert.windowIndex,
      );
    } catch (e) {
      debugPrint('Failed to clear window flag: $e');
    } finally {
      await sshClient.disconnect();
    }
  }

  // inventory: NOTIF-025
  // inventory: LEGACY-0124
  /// 全接続からアラートペインを取得
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    final connectionsState = ref.read(connectionsProvider);
    final connections = connectionsState.connections;
    final storage = SecureStorageService();
    final allAlertPanes = <AlertPane>[];

    for (final connection in connections) {
      SshConnectOptions options;
      if (connection.authMethod == 'key' && connection.keyId != null) {
        final privateKey = await storage.getPrivateKey(connection.keyId!);
        final passphrase = await storage.getPassphrase(connection.keyId!);
        options = SshConnectOptions(privateKey: privateKey, passphrase: passphrase, tmuxPath: connection.tmuxPath);
      } else {
        final password = await storage.getPassword(connection.id);
        options = SshConnectOptions(password: password, tmuxPath: connection.tmuxPath);
      }

      final sshClient = SshClient();
      try {
        await sshClient.connect(
          host: connection.host,
          port: connection.port,
          username: connection.username,
          options: options,
        );

        final sessions = await tmuxFacade.listAllPanes(sshClient.tmuxExecutor);

        for (final session in sessions) {
          for (final window in session.windows) {
            final windowAlertFlags = window.flags.intersection(_alertFlags);
            if (windowAlertFlags.isNotEmpty) {
              for (final pane in window.panes) {
                allAlertPanes.add(AlertPane(
                  connectionId: connection.id,
                  connectionName: connection.name,
                  host: connection.host,
                  sessionName: session.name,
                  windowIndex: window.index,
                  windowName: window.name,
                  flags: windowAlertFlags,
                  paneId: pane.id,
                  paneIndex: pane.index,
                  currentCommand: pane.currentCommand,
                ));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to fetch alert panes for ${connection.name}: $e');
      } finally {
        await sshClient.disconnect();
      }
    }

    state = AlertPanesState(alertPanes: allAlertPanes);
  }
}

// inventory: NOTIF-026
/// 通知ペインプロバイダー
final alertPanesProvider =
    NotifierProvider<AlertPanesNotifier, AlertPanesState>(() {
  return AlertPanesNotifier();
});
