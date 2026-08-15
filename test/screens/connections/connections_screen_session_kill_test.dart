import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/connections/connections_screen.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../fixtures/tmux/tmux_parser_fixtures.dart';
import '../../helpers/fake_ssh_client.dart';

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

  testWidgets(
    'TERM-CRUD session kill confirms, executes kill-session, and reloads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final connection = Connection(
        id: 'connection-1',
        name: 'Test Server',
        host: 'localhost',
        username: 'tester',
        createdAt: DateTime(2026),
      );
      final client = FakeSshClient();
      client.execOutputQueues['list-sessions'] = [
        kSessionOutput,
        'other\x1f1735689700\x1f0\x1f1\x1f\$1\x1e',
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionsProvider.overrideWith(
              () => _StaticConnectionsNotifier(connection),
            ),
            activeSessionsProvider.overrideWith(
              () => _EmptyActiveSessionsNotifier(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConnectionsScreen(
              sshClientFactory: (_) async {
                client.setConnected(SshConnectionState.connected);
                return client;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Server'));
      await tester.pumpAndSettle();
      expect(find.text('mysession'), findsOneWidget);

      await tester.tap(find.byTooltip('Kill session').first);
      await tester.pumpAndSettle();
      expect(find.text('Kill Session'), findsOneWidget);
      expect(
        client.execCommands.any((command) => command.contains('kill-session')),
        isFalse,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Kill'));
      await tester.pumpAndSettle();

      final kill = client.execCommands.indexWhere(
        (command) =>
            command.contains('kill-session') &&
            command.contains('-t mysession'),
      );
      final reload = client.execCommands.indexWhere(
        (command) => command.contains('list-sessions'),
        kill + 1,
      );
      expect(kill, greaterThanOrEqualTo(0));
      expect(reload, greaterThan(kill));
      expect(find.text('Session mysession killed'), findsOneWidget);
      expect(find.text('mysession'), findsNothing);
      expect(find.text('other'), findsOneWidget);
    },
  );
}
