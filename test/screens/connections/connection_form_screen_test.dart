import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/connections/connection_form_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_client.dart';

const kHerdrStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

class _FakeConnectionsNotifier extends ConnectionsNotifier {
  final List<Connection> _initial;
  final List<Connection> added = [];
  final List<Connection> updated = [];

  _FakeConnectionsNotifier({List<Connection>? initial}) : _initial = initial ?? [];

  @override
  ConnectionsState build() => ConnectionsState(connections: _initial);

  @override
  Connection? getById(String id) {
    try {
      return _initial.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> add(Connection connection) async {
    added.add(connection);
    state = state.copyWith(connections: [...state.connections, connection]);
  }

  @override
  Future<void> update(Connection connection) async {
    updated.add(connection);
    state = state.copyWith(
      connections: state.connections.map((c) {
        return c.id == connection.id ? connection : c;
      }).toList(),
    );
  }
}

class _TestSshClient extends FakeSshClient {
  SshConnectOptions? lastOptions;
  bool disposed = false;

  _TestSshClient() {
    execOutputs = {'tmux -V': 'tmux 3.4'};
    state = SshConnectionState.connected;
  }

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    bool lightweight = false,
  }) async {
    lastOptions = options;
    state = SshConnectionState.connected;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class _FormHarness {
  final _FakeConnectionsNotifier connections;
  final _TestSshClient? client;

  _FormHarness(this.connections, {this.client});
}

Future<_FormHarness> _pumpForm(
  WidgetTester tester, {
  String? connectionId,
  List<Connection>? initialConnections,
  _TestSshClient? client,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final connections = _FakeConnectionsNotifier(initial: initialConnections);
  final fakeClient = client ?? _TestSshClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionsProvider.overrideWith(() => connections),
        connectionFormSshClientFactoryProvider.overrideWith((ref) => () => fakeClient),
      ],
      child: MaterialApp(
        home: ConnectionFormScreen(connectionId: connectionId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _FormHarness(connections, client: fakeClient);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues({});
  });

  group('ConnectionFormScreen', () {
    testWidgets('creates a new connection and saves it', (tester) async {
      final harness = await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Production');
      await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.1');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(find.byType(TextFormField).at(4), '/opt/homebrew/bin/tmux');
      await tester.enterText(find.byType(TextFormField).at(6), 'secret');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      final saved = harness.connections.added.first;
      expect(saved.name, 'Production');
      expect(saved.multiplexer.backend, BackendType.tmux);
      expect(saved.multiplexer.executablePath, '/opt/homebrew/bin/tmux');
    });

    testWidgets('edits an existing connection with a custom path', (tester) async {
      final existing = Connection(
        id: 'c1',
        name: 'Old Server',
        host: 'old.host',
        port: 22,
        username: 'user',
        multiplexer: const MultiplexerConfig.tmux('/old/tmux'),
        createdAt: DateTime(2025, 1, 1),
      );
      final harness = await _pumpForm(
        tester,
        connectionId: 'c1',
        initialConnections: [existing],
      );

      final multiplexerField = find.byType(TextFormField).at(4);
      expect(tester.widget<TextFormField>(multiplexerField).controller?.text, '/old/tmux');

      await tester.enterText(multiplexerField, '/new/tmux');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.updated, hasLength(1));
      final saved = harness.connections.updated.first;
      expect(saved.id, 'c1');
      expect(saved.multiplexer.backend, BackendType.tmux);
      expect(saved.multiplexer.executablePath, '/new/tmux');
    });

    testWidgets('shows backend toggle with Tmux and Herdr options',
        (tester) async {
      await _pumpForm(tester);

      expect(find.text('Tmux'), findsOneWidget);
      expect(find.text('Herdr'), findsOneWidget);
    });

    testWidgets('selecting Herdr saves a herdr connection',
        (tester) async {
      final harness = await _pumpForm(tester);

      await tester.tap(find.text('Herdr'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Herdr Host');
      await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.2');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(
          find.byType(TextFormField).at(4), '/usr/local/bin/herdr');
      await tester.enterText(find.byType(TextFormField).at(6), 'secret');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      final saved = harness.connections.added.first;
      expect(saved.multiplexer.backend, BackendType.herdr);
      expect(saved.multiplexer.executablePath, '/usr/local/bin/herdr');
    });

    testWidgets('herdr connection test runs preflight via herdr status --json',
        (tester) async {
      final client = _TestSshClient();
      client.execOutputs['herdr status --json'] = kHerdrStatusOk;
      final harness = await _pumpForm(tester, client: client);

      // 名前入力前にトグルを選択（名前欄とトグルで 'Herdr' が重複しないように）
      await tester.tap(find.text('Herdr'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Herdr Host');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(
          find.byType(TextFormField).at(4), '/usr/local/bin/herdr');
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      expect(
        find.text('Connection successful! Herdr is available.'),
        findsOneWidget,
      );
      expect(harness.client!.lastOptions!.multiplexer!.backend, BackendType.herdr);
      expect(
        harness.client!.execCommands
            .any((c) => c.contains('herdr status --json')),
        isTrue,
      );
    });

    testWidgets('herdr connection test reports protocol mismatch',
        (tester) async {
      final client = _TestSshClient();
      // running な server が protocol 16 を報告する mismatch シナリオ。
      client.execOutputs['herdr status --json'] =
          '{"client":{"protocol":17},"server":{"status":"running","running":true,"protocol":16}}';
      await _pumpForm(tester, client: client);

      await tester.tap(find.text('Herdr'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Herdr Host');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(
          find.byType(TextFormField).at(4), '/usr/local/bin/herdr');
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      expect(find.textContaining('protocol 16 is not supported'), findsOneWidget);
    });

    testWidgets('rejects relative multiplexer path and accepts empty', (tester) async {
      final harness = await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      final multiplexerField = find.byType(TextFormField).at(4);
      await tester.enterText(multiplexerField, 'relative/path');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Absolute path required (e.g., /usr/bin/tmux)'), findsOneWidget);
      expect(harness.connections.added, isEmpty);

      await tester.enterText(multiplexerField, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      expect(harness.connections.added.first.multiplexer.backend, BackendType.tmux);
      expect(harness.connections.added.first.multiplexer.executablePath, isNull);
    });

    testWidgets('connection test flow shows SnackBar success', (tester) async {
      final harness = await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(find.byType(TextFormField).at(4), '/usr/local/bin/tmux');
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      expect(find.text('Connection successful! tmux is available.'), findsOneWidget);
      expect(harness.client, isNotNull);
      final options = harness.client!.lastOptions;
      expect(options, isNotNull);
      final nonNullOptions = options!;
      final multiplexer = nonNullOptions.multiplexer!;
      expect(multiplexer.backend, BackendType.tmux);
      expect(multiplexer.executablePath, '/usr/local/bin/tmux');
      expect(harness.client!.disposed, isTrue);
    });

    testWidgets(
        'connection test with unreadable key shows re-import error',
        (tester) async {
      // 鍵メタデータはあるが秘密鍵が読めない（破損鍵）状態を用意
      SharedPreferences.setMockInitialValues({
        'ssh_keys_meta': jsonEncode([
          {
            'id': 'k1',
            'name': 'broken-key',
            'type': 'ed25519',
            'createdAt': '2026-01-01T00:00:00.000',
          },
        ]),
      });
      // 秘密鍵なし → getPrivateKey が null（破損鍵）
      SecureStorageService.setTestValues({});

      await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.pump();

      // 認証方式を Private Key に切り替え
      await tester.tap(find.text('Private Key'));      await tester.pumpAndSettle();

      // 鍵を選択（破損鍵）
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('broken-key').last);
      await tester.pumpAndSettle();

      // 接続テスト
      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      // 統一エラーが表示される（生の Keystore エラーではなく再インポート案内）
      expect(
        find.textContaining('Private key is not readable'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed to unwrap key'), findsNothing);
    });

    testWidgets('shows damaged key warning when broken key is selected',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'ssh_keys_meta': jsonEncode([
          {
            'id': 'k1',
            'name': 'broken-key',
            'type': 'ed25519',
            'createdAt': '2026-01-01T00:00:00.000',
          },
        ]),
      });
      // 秘密鍵なし → 破損キーとして検出される
      SecureStorageService.setTestValues({});

      await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.pump();

      // 認証方式を Private Key に切り替え
      await tester.tap(find.text('Private Key'));
      await tester.pumpAndSettle();

      // 破損キーを選択
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('broken-key').last);
      await tester.pumpAndSettle();

      // 破損キー選択中の警告が表示される
      expect(find.textContaining('破損しています'), findsOneWidget);
    });
  });
}
