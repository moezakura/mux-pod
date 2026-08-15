import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/connections/connections_screen.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/fake_tmux_notifier.dart';

class _StaticConnectionsNotifier extends ConnectionsNotifier {
  _StaticConnectionsNotifier(this.connection);

  final Connection connection;

  @override
  ConnectionsState build() => ConnectionsState(connections: [connection]);
}

class _EmptyActiveSessionsNotifier extends ActiveSessionsNotifier {
  @override
  ActiveSessionsState build() => const ActiveSessionsState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues(const {});
    addTearDown(() => SecureStorageService.setTestValues(null));
  });

  testWidgets('shows damaged key badge for connection using a broken key', (
    tester,
  ) async {
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

    final client = FakeSshClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StaticConnectionsNotifier(connection),
          ),
          activeSessionsProvider.overrideWith(
            () => _EmptyActiveSessionsNotifier(),
          ),
          sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              settings: const AppSettings(keepScreenOn: false),
            ),
          ),
          tmuxProvider.overrideWith(
            () => FakeTmuxNotifier(initialState: const TmuxState()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionsScreen(sshClientFactory: (_) async => client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 破損キー使用中のバッジと警告アイコンが表示される
    expect(find.text('破損した鍵を使用中'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsWidgets);
  });

  testWidgets('does not show damaged key badge for healthy key connection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_meta': jsonEncode([
        {
          'id': 'healthy-key-id',
          'name': 'healthy-key',
          'type': 'ed25519',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });
    SecureStorageService.setTestValues({'privatekey_healthy-key-id': 'K'});

    final connection = Connection(
      id: 'conn-1',
      name: 'Server with healthy key',
      host: '192.168.1.1',
      username: 'user',
      authMethod: 'key',
      keyId: 'healthy-key-id',
      multiplexer: MultiplexerConfig.tmux(),
      createdAt: DateTime(2026, 1, 1),
    );

    final client = FakeSshClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsProvider.overrideWith(
            () => _StaticConnectionsNotifier(connection),
          ),
          activeSessionsProvider.overrideWith(
            () => _EmptyActiveSessionsNotifier(),
          ),
          sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              settings: const AppSettings(keepScreenOn: false),
            ),
          ),
          tmuxProvider.overrideWith(
            () => FakeTmuxNotifier(initialState: const TmuxState()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionsScreen(sshClientFactory: (_) async => client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('破損した鍵を使用中'), findsNothing);
  });
}
