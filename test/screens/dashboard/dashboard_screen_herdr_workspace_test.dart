import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/screens/dashboard/dashboard_screen.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

// 表示統一の回帰テスト: herdr / tmux とも trailing が「>」（chevron_right）
// で、workspace 操作メニュー（⋮ / 'Workspace actions'）と READ ONLY バッジが
// 表示されないこと。

class _MixedActiveSessionsNotifier extends ActiveSessionsNotifier {
  @override
  ActiveSessionsState build() {
    return ActiveSessionsState(
      sessions: [
        ActiveSession(
          connectionId: 'connection-herdr',
          connectionName: 'Herdr Server',
          host: 'localhost',
          sessionName: 'lab-ws1',
          sessionId: 'w1',
          windowCount: 1,
          connectedAt: DateTime(2026, 1, 1),
          backend: MultiplexerBackendKind.herdr,
        ),
        ActiveSession(
          connectionId: 'connection-tmux',
          connectionName: 'Tmux Server',
          host: '192.168.0.10',
          sessionName: 'main',
          sessionId: 'main',
          windowCount: 2,
          connectedAt: DateTime(2026, 1, 2),
          backend: MultiplexerBackendKind.tmux,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues(const {});
    addTearDown(() => SecureStorageService.setTestValues(null));
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSessionsProvider.overrideWith(
            () => _MixedActiveSessionsNotifier(),
          ),
        ],
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'herdr/tmux session cards both show chevron_right with no workspace '
    'actions and no READ ONLY badge',
    (tester) async {
      await pumpDashboard(tester);

      // herdr / tmux の両カードが表示される。
      expect(find.text('Herdr Server: lab-ws1'), findsOneWidget);
      expect(find.text('Tmux Server: main'), findsOneWidget);

      // 両カードとも trailing が「>」（chevron_right）で表示統一されている。
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

      // workspace 操作メニューは撤廃されている。
      expect(find.byTooltip('Workspace actions'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // herdr の READ ONLY バッジは出ない。
      expect(find.text('READ ONLY'), findsNothing);
    },
  );
}
