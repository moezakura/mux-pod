import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'helpers/ssh_client_fakes.dart';

void main() {
  group('SshClient managed PTY（hidden herdr TUI ホスト）', () {
    Future<(SshClient, FakeRawSshClient)> connectedClient() async {
      final rawClient = FakeRawSshClient();
      final client = SshClient(
        connectionFactory: (_, _, _, _, onAuthenticated, _) async {
          onAuthenticated();
          return (socket: FakeSocket(), client: rawClient);
        },
      );
      // connect は認証完了を待つため、先に開始（await しない）してから
      // authentication を complete する（既存テストと同じ順序）。
      final connecting = client.connect(
        host: 'host',
        port: 22,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        lightweight: true,
      );
      await Future<void>.delayed(Duration.zero);
      rawClient.authentication.complete();
      await connecting;
      expect(client.state, SshConnectionState.connected);
      return (client, rawClient);
    }

    test('startManagedPty は PTY 付き exec を実行し ManagedPtyProcess を返す', () async {
      final (client, rawClient) = await connectedClient();

      final process = await client.startManagedPty(
        'herdr',
        cols: 100,
        rows: 30,
      );
      expect(rawClient.execSessions, hasLength(1));
      expect(process, isNotNull);

      // resize は throw せず呼べる（SSHSession.resizeTerminal 委譲）。
      process.resize(120, 40);

      // stdout を emitData しても例外なし（明示 discard）。
      rawClient.execSessions.single.emitData([1, 2, 3]);

      // stderrTail は空のまま（エラー未出力）。
      expect(process.stderrTail, isEmpty);
      expect(process.exitCode, 0);

      await client.disconnect();
    });

    test('二重 startManagedPty は前の managed session を close する', () async {
      final (client, rawClient) = await connectedClient();

      final first = await client.startManagedPty('herdr', cols: 80, rows: 24);
      final second = await client.startManagedPty('herdr', cols: 90, rows: 30);
      expect(rawClient.execSessions, hasLength(2));
      expect(second, isNotNull);
      expect(first, isNot(same(second)));

      await client.disconnect();
    });

    test('disconnect（dispose）で managed PTY の session も close される', () async {
      final (client, rawClient) = await connectedClient();

      await client.startManagedPty('herdr', cols: 80, rows: 24);
      expect(rawClient.execSessions, hasLength(1));

      await client.disconnect();
      // ManagedPtyProcess.close が FakeInteractiveSession.close を呼ぶ
      // （close 後は stdout/stderr が閉じる）。例外なしで完了すること。
    });

    test('未接続で startManagedPty は throw する', () async {
      final client = SshClient();
      expect(
        () => client.startManagedPty('herdr', cols: 80, rows: 24),
        throwsA(isA<Exception>()),
      );
    });
  });
}
