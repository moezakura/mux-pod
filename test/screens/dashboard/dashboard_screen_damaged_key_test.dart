import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/dashboard/dashboard_screen.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

class _StaticConnectionsNotifier extends ConnectionsNotifier {
  _StaticConnectionsNotifier(this.connection);

  final Connection connection;

  @override
  ConnectionsState build() => ConnectionsState(connections: [connection]);
}

class _StaticActiveSessionsNotifier extends ActiveSessionsNotifier {
  _StaticActiveSessionsNotifier(this.session);

  final ActiveSession session;

  @override
  ActiveSessionsState build() => ActiveSessionsState(sessions: [session]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues(const {});
    addTearDown(() => SecureStorageService.setTestValues(null));
  });

  testWidgets('shows damaged key badge for session using a broken key',
      (tester) async {
    // 鍵メタデータはあるが秘密鍵が読めない（破損鍵）状態を用意
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'broken-key-id',
          'name': 'broken-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    // 秘密鍵なし → 破損鍵として検出される
    SecureStorageService.setTestValues(const {});

    final connection = Connection(
      id: 'conn-1',
      name: 'Server with broken key',
      host: '192.168.1.1',
      username: 'user',
      authMethod: 'key',
      keyId: 'broken-key-id',
      multiplexer: MultiplexerConfig.tmux(),
      createdAt: DateTime(2026, 1, 1),
    );

    final session = ActiveSession(
      connectionId: 'conn-1',
      connectionName: 'Server with broken key',
      host: '192.168.1.1',
      sessionName: '0',
      windowCount: 1,
      connectedAt: DateTime(2026, 1, 1),
      isAttached: true,
      backend: MultiplexerBackendKind.tmux,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StaticConnectionsNotifier(connection),
          ),
          activeSessionsProvider.overrideWith(
            () => _StaticActiveSessionsNotifier(session),
          ),
        ],
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 破損キー使用中のバッジと警告アイコンが表示される
    expect(find.text('破損した鍵を使用中'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsWidgets);
  });
}
