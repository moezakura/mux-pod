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

    testWidgets('does not contain Herdr or herdr text', (tester) async {
      await _pumpForm(tester);

      bool mentionsHerdr(Widget widget) {
        String? text;
        if (widget is Text) {
          text = widget.data;
        } else if (widget is RichText) {
          final span = widget.text;
          if (span is TextSpan) text = span.text;
        }
        return text?.toLowerCase().contains('herdr') ?? false;
      }

      expect(find.byWidgetPredicate(mentionsHerdr), findsNothing);
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
  });
}
