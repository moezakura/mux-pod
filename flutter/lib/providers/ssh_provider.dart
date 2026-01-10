import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh/ssh_auth.dart';
import '../services/ssh/ssh_client.dart';
import '../services/storage/connection_repository.dart';
import 'connection_provider.dart';

/// SSHクライアント プロバイダー
final sshClientProvider = Provider<SshClient>((ref) {
  final client = SshClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// SSH認証サービス プロバイダー
final sshAuthServiceProvider = Provider<SshAuthService>((ref) {
  return SshAuthService(
    sshClient: ref.watch(sshClientProvider),
    connectionRepository: ref.watch(connectionRepositoryProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
});

/// 接続状態ストリーム プロバイダー
final connectionStateProvider =
    StreamProvider<ConnectionStateEvent>((ref) {
  final client = ref.watch(sshClientProvider);
  return client.connectionState;
});

/// SSH接続コントローラー プロバイダー（接続IDごと）
final sshConnectionControllerProvider = AsyncNotifierProvider.family
    .autoDispose<SshConnectionController, SshShellSession?, String>(
  SshConnectionController.new,
);

/// SSH接続コントローラー
class SshConnectionController
    extends AutoDisposeFamilyAsyncNotifier<SshShellSession?, String> {
  @override
  Future<SshShellSession?> build(String arg) async {
    ref.onDispose(() async {
      // クリーンアップ
      final session = state.valueOrNull;
      if (session != null) {
        await session.close();
      }
    });
    return null; // 初期状態は未接続
  }

  SshClient get _sshClient => ref.read(sshClientProvider);
  SshAuthService get _authService => ref.read(sshAuthServiceProvider);
  ConnectionRepository get _connectionRepo =>
      ref.read(connectionRepositoryProvider);

  String get connectionId => arg;

  /// 接続
  Future<void> connect() async {
    state = const AsyncValue.loading();

    try {
      final connection = await _connectionRepo.get(connectionId);
      if (connection == null) {
        throw Exception('Connection not found: $connectionId');
      }

      await _authService.connect(connection);

      // 最終接続日時を更新
      await _connectionRepo.updateLastConnected(connectionId);

      state = const AsyncValue.data(null); // 接続成功だがシェルはまだ
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// シェルセッション開始
  Future<SshShellSession> startShell({
    int width = 80,
    int height = 24,
    String term = 'xterm-256color',
  }) async {
    if (!_sshClient.isConnected(connectionId)) {
      await connect();
    }

    final session = await _sshClient.startShell(
      connectionId: connectionId,
      width: width,
      height: height,
      term: term,
    );

    state = AsyncValue.data(session);
    return session;
  }

  /// コマンド実行
  Future<SshExecResult> exec(String command) async {
    if (!_sshClient.isConnected(connectionId)) {
      await connect();
    }

    return await _sshClient.exec(
      connectionId: connectionId,
      command: command,
    );
  }

  /// 切断
  Future<void> disconnect() async {
    final session = state.valueOrNull;
    if (session != null) {
      await session.close();
    }

    await _sshClient.disconnect(connectionId);
    state = const AsyncValue.data(null);
  }

  /// 接続状態取得
  ConnectionStatus get status => _sshClient.getStatus(connectionId);

  /// 接続済みか
  bool get isConnected => _sshClient.isConnected(connectionId);
}
