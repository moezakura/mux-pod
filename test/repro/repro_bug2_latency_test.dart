// Repro: バグ2 描画遅延が異常に遅い（同一LAN内で100〜4000ms）
//
// 静的解析による原因（設計上の再現）:
// - herdr の全コマンドは BackendAdapter.execWithExitCode 経由で実行される
//   （ssh_client.dart:925-985）
// - execWithExitCode は毎回 `_client!.execute(command)` で SSH チャネルを開き
//   （L943）、finally で `session?.close()` して閉じる（L970-971）
// - さらに `_withExecLock`（L935）で全コマンドが直列化される（L616-628）
// - 一方 tmux は execPersistent（持続的シェル再利用・L891-917）を使うため、
//   チャネル開閉が不要で 1 RTT で済む
// - ライブポーリングも逐次実行（terminal_screen.dart:1436-1437: 前回完了後に
//   次をスケジュール）のため、1 ポーリング = 1 チャネル開閉 + 直列待ち
//
// このテストは「execWithExitCode が毎回チャネルを開閉する」「並行要求が
// 直列化される」という設計を再現する。実レイテンシ（100-4000ms）は
// ネットワーク RTT × チャネル開閉オーバーヘッドに依存するため、
// 実機での測定が必要（手順書参照）。
@Tags(['repro'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/ssh/persistent_shell.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

class _FakeSocket implements SSHSocket {
  final _stream = StreamController<Uint8List>();
  final _sink = StreamController<List<int>>();
  bool closed = false;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> get done => _stream.done;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _stream.close();
    await _sink.close();
  }

  @override
  void destroy() => unawaited(close());

  @override
  Future<void> flush() async {}
}

/// execWithExitCode が listen した時点で stdout/stderr を閉じる fake セッション。
///
/// 実際の dartssh2 ではチャネルクローズで stdout/stderr 両方が done になる。
/// onListen でデータ送出 + close することで、listen 前に close() しても
/// データが配信される（single-subscription StreamController の仕様回避）。
class _FakeInteractiveSession implements SSHSession {
  late final StreamController<Uint8List> _stdout;
  late final StreamController<Uint8List> _stderr;
  final writes = <Uint8List>[];
  bool closed = false;

  _FakeInteractiveSession({List<int> output = const []}) {
    _stdout = StreamController<Uint8List>(
      onListen: () {
        if (output.isNotEmpty) {
          _stdout.add(Uint8List.fromList(output));
        }
        unawaited(_stdout.close());
      },
    );
    _stderr = StreamController<Uint8List>(
      onListen: () {
        unawaited(_stderr.close());
      },
    );
  }

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  int? get exitCode => 0;

  @override
  SSHSessionExitSignal? get exitSignal => null;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void close() {
    closed = true;
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// execute（= チャネル開設）回数と close（= チャネル閉鎖）回数を記録する fake。
class _CountingRawSshClient implements SSHClient {
  final Completer<void> authentication = Completer<void>();
  final List<String> executedCommands = [];
  final List<_FakeInteractiveSession> openedSessions = [];
  bool closed = false;

  /// execute 内で1回あたりに待つ時間（直列化の検証用）。
  Duration executeDelay = Duration.zero;

  /// 現在実行中の execute 数（同時実行検出用）。
  int concurrentExecutes = 0;
  int maxConcurrentExecutes = 0;

  @override
  Future<void> get authenticated => authentication.future;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    executedCommands.add(command);
    concurrentExecutes++;
    if (concurrentExecutes > maxConcurrentExecutes) {
      maxConcurrentExecutes = concurrentExecutes;
    }
    if (executeDelay > Duration.zero) {
      await Future<void>.delayed(executeDelay);
    }
    final session = _FakeInteractiveSession(output: 'ok'.codeUnits);
    openedSessions.add(session);
    concurrentExecutes--;
    return session;
  }

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    final session = _FakeInteractiveSession();
    openedSessions.add(session);
    return session;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopPersistentShell extends PersistentShell {
  _NoopPersistentShell(super.client);

  @override
  bool get isStarted => true;

  @override
  Future<void> start() async {}

  @override
  Future<String> exec(String command, {Duration? timeout}) async => 'ok';

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Repro BUG-2: execWithExitCode は毎回チャネル開閉 + 直列化', () {
    late _CountingRawSshClient rawClient;
    late SshClient client;

    setUp(() async {
      rawClient = _CountingRawSshClient();
      client = SshClient(
        connectionFactory: (_, _, _, _, onAuthenticated, _) async {
          onAuthenticated();
          rawClient.authentication.complete();
          return (socket: _FakeSocket(), client: rawClient);
        },
        persistentShellFactory: (raw) async => _NoopPersistentShell(raw),
      );
      await client.connect(
        host: 'host',
        port: 22,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        lightweight: true, // keep-alive / persistent shell をスキップ
      );
    });

    tearDown(() => client.disconnect());

    test('execute(ephemeralOnly) を2回呼ぶと execute（チャネル開設）が2回発生し、'
        '各セッションが close される（= 毎回チャネル開閉）', () async {
      await client.execute(
        const CommandRequest(
          command: 'herdr status --json',
          transport: CommandTransportPreference.ephemeralOnly,
          output: CommandOutputRequirement.outputOnly,
        ),
      );
      await client.execute(
        const CommandRequest(
          command: 'herdr api snapshot',
          transport: CommandTransportPreference.ephemeralOnly,
          output: CommandOutputRequirement.outputOnly,
        ),
      );

      expect(rawClient.executedCommands, [
        'herdr status --json',
        'herdr api snapshot',
      ]);
      // 毎回 execute() = SSH チャネルを開いている（tmux の persistent は
      // チャネルを再利用するため execute を呼ばない）。
      expect(rawClient.executedCommands.length, 2);
      // 各セッションが close されている（= チャネルを毎回閉じている）。
      expect(
        rawClient.openedSessions.every((s) => s.closed),
        isTrue,
        reason:
            'バグ: ephemeralOnly が毎回チャネルを開いて閉じるため、'
            'チャネル開閉の RTT オーバーヘッドが毎ポーリング発生する',
      );
    });

    test('execute(ephemeralOnly) は直列化される（並行要求でも execute の同時実行は1つ）', () async {
      // 各 execute に 50ms かかる状態で3連続呼び出し
      rawClient.executeDelay = const Duration(milliseconds: 50);

      final futures = [
        client.execute(
          const CommandRequest(
            command: 'cmd-1',
            transport: CommandTransportPreference.ephemeralOnly,
            output: CommandOutputRequirement.outputOnly,
          ),
        ),
        client.execute(
          const CommandRequest(
            command: 'cmd-2',
            transport: CommandTransportPreference.ephemeralOnly,
            output: CommandOutputRequirement.outputOnly,
          ),
        ),
        client.execute(
          const CommandRequest(
            command: 'cmd-3',
            transport: CommandTransportPreference.ephemeralOnly,
            output: CommandOutputRequirement.outputOnly,
          ),
        ),
      ];
      await Future.wait(futures);

      expect(rawClient.executedCommands, ['cmd-1', 'cmd-2', 'cmd-3']);
      expect(
        rawClient.maxConcurrentExecutes,
        1,
        reason:
            'バグ: _withExecLock により全コマンドが直列化されるため、'
            '同時に3つのコマンドを発行しても逐次実行になり、'
            '合計レイテンシ = 3 × (チャネル開閉 + RTT + 実行時間) になる',
      );
    });

    test('lightweight 接続（herdr 相当）では persistent もチャネルを開く'
        '（持続的シェルが無いため ephemeral にフォールバック）', () async {
      // herdr は connectWithoutShell（lightweight: true）で接続されるため、
      // persistentShell が存在せず、persistentPreferred も ephemeral に
      // フォールバックする（チャネル開設）。
      await client.execute(
        const CommandRequest(
          command: 'herdr pane read w1:p1 --source recent',
          transport: CommandTransportPreference.persistentPreferred,
          output: CommandOutputRequirement.outputOnly,
        ),
      );

      expect(
        rawClient.executedCommands,
        isNotEmpty,
        reason:
            'バグ: lightweight 接続では持続的シェルが無いため、'
            'persistentPreferred でさえ毎回チャネル開閉が発生する。'
            'tmux はフル接続（persistentShell あり）でチャネルを再利用する',
      );
      expect(
        rawClient.executedCommands,
        contains('herdr pane read w1:p1 --source recent'),
      );
    });
  });
}
