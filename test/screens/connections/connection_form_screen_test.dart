import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/connections/connection_form_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/connection/proxy_config.dart';
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

  _FakeConnectionsNotifier({List<Connection>? initial})
    : _initial = initial ?? [];

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
    AppLocalizations? l10n,
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
        connectionFormSshClientFactoryProvider.overrideWith(
          (ref) =>
              () => fakeClient,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
      await tester.enterText(
        find.byType(TextFormField).at(4),
        '/opt/homebrew/bin/tmux',
      );
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

    testWidgets('edits an existing connection with a custom path', (
      tester,
    ) async {
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
      expect(
        tester.widget<TextFormField>(multiplexerField).controller?.text,
        '/old/tmux',
      );

      await tester.enterText(multiplexerField, '/new/tmux');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.updated, hasLength(1));
      final saved = harness.connections.updated.first;
      expect(saved.id, 'c1');
      expect(saved.multiplexer.backend, BackendType.tmux);
      expect(saved.multiplexer.executablePath, '/new/tmux');
    });

    testWidgets('shows backend toggle with Tmux and Herdr options', (
      tester,
    ) async {
      await _pumpForm(tester);

      expect(find.text('Tmux'), findsOneWidget);
      expect(find.text('Herdr'), findsOneWidget);
    });

    testWidgets('selecting Herdr saves a herdr connection', (tester) async {
      final harness = await _pumpForm(tester);

      await tester.tap(find.text('Herdr'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Herdr Host');
      await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.2');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(
        find.byType(TextFormField).at(4),
        '/usr/local/bin/herdr',
      );
      await tester.enterText(find.byType(TextFormField).at(6), 'secret');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      final saved = harness.connections.added.first;
      expect(saved.multiplexer.backend, BackendType.herdr);
      expect(saved.multiplexer.executablePath, '/usr/local/bin/herdr');
    });

    testWidgets(
      'herdr connection test runs preflight via herdr status --json',
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
          find.byType(TextFormField).at(4),
          '/usr/local/bin/herdr',
        );
        await tester.enterText(find.byType(TextFormField).at(6), 'password');
        await tester.pump();

        await tester.tap(find.text('TEST CONNECTION'));
        await tester.pumpAndSettle();

        expect(
          find.text('Connection successful! Herdr is available.'),
          findsOneWidget,
        );
        expect(
          harness.client!.lastOptions!.multiplexer!.backend,
          BackendType.herdr,
        );
        expect(
          harness.client!.execCommands.any(
            (c) => c.contains('herdr status --json'),
          ),
          isTrue,
        );
      },
    );

    testWidgets('herdr connection test reports protocol mismatch', (
      tester,
    ) async {
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
        find.byType(TextFormField).at(4),
        '/usr/local/bin/herdr',
      );
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'protocol 16 is not supported (minimum supported: 17)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('rejects relative multiplexer path and accepts empty', (
      tester,
    ) async {
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

      expect(
        find.text('Absolute path required (e.g., /usr/bin/tmux)'),
        findsOneWidget,
      );
      expect(harness.connections.added, isEmpty);

      await tester.enterText(multiplexerField, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      expect(
        harness.connections.added.first.multiplexer.backend,
        BackendType.tmux,
      );
      expect(
        harness.connections.added.first.multiplexer.executablePath,
        isNull,
      );
    });

    testWidgets('connection test flow shows SnackBar success', (tester) async {
      final harness = await _pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'host');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(
        find.byType(TextFormField).at(4),
        '/usr/local/bin/tmux',
      );
      await tester.enterText(find.byType(TextFormField).at(6), 'password');
      await tester.pump();

      await tester.tap(find.text('TEST CONNECTION'));
      await tester.pumpAndSettle();

      expect(
        find.text('Connection successful! tmux is available.'),
        findsOneWidget,
      );
      expect(harness.client, isNotNull);
      final options = harness.client!.lastOptions;
      expect(options, isNotNull);
      final nonNullOptions = options!;
      final multiplexer = nonNullOptions.multiplexer!;
      expect(multiplexer.backend, BackendType.tmux);
      expect(multiplexer.executablePath, '/usr/local/bin/tmux');
      expect(harness.client!.disposed, isTrue);
    });

    testWidgets('connection test with unreadable key shows re-import error', (
      tester,
    ) async {
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
      await tester.tap(find.text('Private Key'));
      await tester.pumpAndSettle();

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

    testWidgets('shows damaged key warning when broken key is selected', (
      tester,
    ) async {
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
      expect(
        find.textContaining('The selected key is damaged'),
        findsOneWidget,
      );
    });
  });

  group('ConnectionFormScreen proxy & keepalive', () {
    Future<_FormHarness> fillBasicTarget(WidgetTester tester) async {
      final harness = await _pumpForm(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Jumped');
      await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.1');
      await tester.enterText(find.byType(TextFormField).at(3), 'user');
      await tester.enterText(find.byType(TextFormField).at(6), 'secret');
      await tester.pump();
      return harness;
    }

    Future<void> enableProxy(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('proxy_enable_switch')));
      await tester.pumpAndSettle();
    }

    Future<void> fillHop(
      WidgetTester tester,
      int index, {
      String host = 'jump1.example.com',
      String port = '2200',
      String username = 'jumpuser',
      String password = 'jumppw',
    }) async {
      await tester.enterText(
        find.byKey(Key('proxy_hop_host_$index')),
        host,
      );
      await tester.enterText(
        find.byKey(Key('proxy_hop_port_$index')),
        port,
      );
      await tester.enterText(
        find.byKey(Key('proxy_hop_username_$index')),
        username,
      );
      if (password.isNotEmpty) {
        await tester.enterText(
          find.byKey(Key('proxy_hop_password_$index')),
          password,
        );
      }
      await tester.pump();
    }

    testWidgets(
      'MR-3: tests connection with unsaved jump password via form values',
      (tester) async {
        final client = _TestSshClient();
        await _pumpForm(tester, client: client);

        await tester.enterText(find.byType(TextFormField).at(0), 'Jumped');
        await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.1');
        await tester.enterText(find.byType(TextFormField).at(3), 'user');
        await tester.enterText(find.byType(TextFormField).at(6), 'secret');
        await tester.pump();

        await enableProxy(tester);
        await fillHop(tester, 0);
        await tester.pump();

        await tester.tap(find.text('TEST CONNECTION'));
        await tester.pumpAndSettle();

        // 未保存の jump password でもテストが通る（MR-3）。
        expect(
          find.text('Connection successful! tmux is available.'),
          findsOneWidget,
        );
        final proxy = client.lastOptions!.proxy;
        expect(proxy, isNotNull);
        expect(proxy!.hops, hasLength(1));
        expect(proxy.hops[0].host, 'jump1.example.com');
        expect(proxy.hops[0].port, 2200);
        expect(proxy.hops[0].username, 'jumpuser');
        expect(proxy.hops[0].password, 'jumppw');
        // M3: 転送先は target 座標で解決済み。
        expect(proxy.forwardHost, '192.168.1.1');
        expect(proxy.forwardPort, 22);
      },
    );

    testWidgets('restores multi-hop proxy settings when editing', (
      tester,
    ) async {
      final existing = Connection(
        id: 'c1',
        name: 'Jumped',
        host: '192.168.1.1',
        username: 'user',
        proxy: const ProxyConfig(
          hops: [
            ProxyHop(host: 'jump1.example.com', port: 2200, username: 'u1'),
            ProxyHop(
              host: 'jump2.example.com',
              username: 'u2',
              authMethod: 'key',
              keyId: 'k1',
            ),
          ],
          forwardHost: '10.0.0.5',
          forwardPort: 2222,
        ),
        keepAliveTimeoutSeconds: 60,
        createdAt: DateTime(2025, 1, 1),
      );
      await _pumpForm(
        tester,
        connectionId: 'c1',
        initialConnections: [existing],
      );

      // スイッチが on で hop 2 行が復元される。
      final switchWidget = tester.widget<Switch>(
        find.byKey(const Key('proxy_enable_switch')),
      );
      expect(switchWidget.value, isTrue);
      expect(find.byKey(const Key('proxy_hop_host_0')), findsOneWidget);
      expect(find.byKey(const Key('proxy_hop_host_1')), findsOneWidget);

      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('proxy_hop_host_0')),
        ).controller!.text,
        'jump1.example.com',
      );
      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('proxy_hop_port_0')),
        ).controller!.text,
        '2200',
      );
      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('proxy_hop_host_1')),
        ).controller!.text,
        'jump2.example.com',
      );
      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('proxy_forward_host')),
        ).controller!.text,
        '10.0.0.5',
      );
      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('proxy_forward_port')),
        ).controller!.text,
        '2222',
      );
      // keepalive の逆流。
      expect(
        tester.widget<TextFormField>(
          find.byKey(const Key('keepalive_timeout_field')),
        ).controller!.text,
        '60',
      );
    });

    testWidgets('saves multi-hop proxy with credentials (M6 normalization)', (
      tester,
    ) async {
      final harness = await fillBasicTarget(tester);

      await enableProxy(tester);
      await fillHop(tester, 0);
      await tester.tap(find.byKey(const Key('proxy_add_hop')));
      await tester.pumpAndSettle();
      await fillHop(
        tester,
        1,
        host: 'jump2.example.com',
        port: '2222',
        username: 'u2',
        password: 'pw2',
      );
      // M6: 転送先ホスト空欄のまま転送先ポートのみ入力 쳌 転送先は未指定扱い。
      await tester.enterText(
        find.byKey(const Key('proxy_forward_port')),
        '9090',
      );
      await tester.enterText(
        find.byKey(const Key('keepalive_timeout_field')),
        '60',
      );
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.added, hasLength(1));
      final saved = harness.connections.added.first;
      final proxy = saved.proxy;
      expect(proxy, isNotNull);
      expect(proxy!.hops, hasLength(2));
      expect(proxy.hops[0].host, 'jump1.example.com');
      expect(proxy.hops[1].host, 'jump2.example.com');
      expect(proxy.hops[1].port, 2222);
      // M6: 転送先ホスト未指定なら forwardPort のみ入力は無視。
      expect(proxy.forwardHost, isNull);
      expect(proxy.forwardPort, isNull);
      // keepalive。
      expect(saved.keepAliveTimeoutSeconds, 60);
      // 認証情報は secure storage のみ（JSON 混入禁止）。
      expect(
        await SecureStorageService().getProxyPassword(saved.id, 0),
        'jumppw',
      );
      expect(
        await SecureStorageService().getProxyPassword(saved.id, 1),
        'pw2',
      );
      expect(jsonEncode(saved.toJson()), isNot(contains('jumppw')));
    });

    testWidgets('MR-4: disabling proxy removes all hop keys on save', (
      tester,
    ) async {
      SecureStorageService.setTestValues({
        'proxy_password_c1_0': 'old0',
        'proxy_password_c1_1': 'old1',
      });
      final existing = Connection(
        id: 'c1',
        name: 'Jumped',
        host: '192.168.1.1',
        username: 'user',
        proxy: const ProxyConfig(
          hops: [
            ProxyHop(host: 'jump1.example.com', username: 'u1'),
            ProxyHop(host: 'jump2.example.com', username: 'u2'),
          ],
        ),
        createdAt: DateTime(2025, 1, 1),
      );
      final harness = await _pumpForm(
        tester,
        connectionId: 'c1',
        initialConnections: [existing],
      );

      await tester.tap(find.byKey(const Key('proxy_enable_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(harness.connections.updated, hasLength(1));
      expect(harness.connections.updated.first.proxy, isNull);
      final storage = SecureStorageService();
      expect(await storage.getProxyPassword('c1', 0), isNull);
      expect(await storage.getProxyPassword('c1', 1), isNull);
    });

    testWidgets(
      '🤝2: shrinking hops 3 to 1 removes orphan indices 1 and 2',
      (tester) async {
        SecureStorageService.setTestValues({
          'proxy_password_c1_0': 'old0',
          'proxy_password_c1_1': 'old1',
          'proxy_password_c1_2': 'old2',
        });
        ProxyHop hop(String host) =>
            ProxyHop(host: host, username: 'u');
        final existing = Connection(
          id: 'c1',
          name: 'Jumped',
          host: '192.168.1.1',
          username: 'user',
          proxy: ProxyConfig(
            hops: [hop('jump1.example.com'), hop('jump2.example.com'), hop('jump3.example.com')],
          ),
          createdAt: DateTime(2025, 1, 1),
        );
        final harness = await _pumpForm(
          tester,
          connectionId: 'c1',
          initialConnections: [existing],
        );

        // hop 3（index 2）を削除 → hop 2（index 1）を削除。
        await tester.tap(find.byKey(const Key('proxy_hop_remove_2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('proxy_hop_remove_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(harness.connections.updated, hasLength(1));
        expect(
          harness.connections.updated.first.proxy!.hops,
          hasLength(1),
        );
        final storage = SecureStorageService();
        // index 0 は維持（空欄 = 既存値維持）。
        expect(await storage.getProxyPassword('c1', 0), 'old0');
        // orphan（index 1, 2）は削除される。
        expect(await storage.getProxyPassword('c1', 1), isNull);
        expect(await storage.getProxyPassword('c1', 2), isNull);
      },
    );

    testWidgets('limits hop rows to 5 and supports removal', (tester) async {
      await _pumpForm(tester);
      await enableProxy(tester);

      expect(find.byKey(const Key('proxy_hop_host_0')), findsOneWidget);

      // フォームが長くなるため、追加前にボタンを可視化する。
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(find.byKey(const Key('proxy_add_hop')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('proxy_add_hop')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('proxy_hop_host_4')), findsOneWidget);

      // 上限 5: 追加ボタンは無効化される。
      final addButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('proxy_add_hop')),
      );
      expect(addButton.onPressed, isNull);
      expect(find.byKey(const Key('proxy_hop_host_5')), findsNothing);

      // 削除で減る（最小 1 は維持）・残り行は index が詰め直される。
      await tester.ensureVisible(find.byKey(const Key('proxy_hop_remove_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('proxy_hop_remove_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('proxy_hop_host_0')), findsOneWidget);
      expect(find.byKey(const Key('proxy_hop_host_4')), findsNothing);
    });

    testWidgets('blocks saving when a duplicate host:port exists', (
      tester,
    ) async {
      final harness = await fillBasicTarget(tester);

      await enableProxy(tester);
      await fillHop(tester, 0);
      await tester.tap(find.byKey(const Key('proxy_add_hop')));
      await tester.pumpAndSettle();
      await fillHop(
        tester,
        1,
        port: '2200',
        username: 'other',
        password: 'pw2',
      );
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // 両方の重複行でエラーが表示される。
      expect(
        find.textContaining(
          'jump1.example.com:2200 is already in the chain',
        ),
        findsNWidgets(2),
      );
      expect(harness.connections.added, isEmpty);
    });

    testWidgets('keepalive: empty input saves unset (auto)', (tester) async {
      final harness = await fillBasicTarget(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(harness.connections.added, hasLength(1));
      expect(harness.connections.added.first.keepAliveTimeoutSeconds, isNull);
    });

    testWidgets('keepalive: out-of-range input blocks saving', (tester) async {
      final harness = await fillBasicTarget(tester);

      await tester.enterText(
        find.byKey(const Key('keepalive_timeout_field')),
        '400',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between 5 and 300'), findsOneWidget);
      expect(harness.connections.added, isEmpty);
    });

    testWidgets('keepalive: in-range boundary value is saved', (tester) async {
      final harness = await fillBasicTarget(tester);

      await tester.enterText(
        find.byKey(const Key('keepalive_timeout_field')),
        '300',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(harness.connections.added, hasLength(1));
      expect(harness.connections.added.first.keepAliveTimeoutSeconds, 300);
    });
  });
}
