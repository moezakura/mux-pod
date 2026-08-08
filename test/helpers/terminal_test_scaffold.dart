import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/providers/notification_panes_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/widgets/image_transfer_confirm_dialog.dart';

import '../fixtures/tmux/tmux_parser_fixtures.dart';
import 'fake_settings_notifier.dart';
import 'fake_ssh_client.dart';
import 'fake_ssh_notifier.dart';
import 'fake_tmux_notifier.dart';

class _FakeConnectionsNotifier extends ConnectionsNotifier {
  _FakeConnectionsNotifier({this.connection});

  final Connection? connection;

  @override
  ConnectionsState build() => const ConnectionsState();

  @override
  Connection? getById(String id) {
    if (connection?.id == id) return connection;
    if (id == 'test-conn') {
      return Connection(
        id: id,
        name: 'Test',
        host: 'testhost',
        port: 22,
        username: 'user',
        createdAt: DateTime(2025, 1, 1),
      );
    }
    return null;
  }

  @override
  Future<void> updateLastConnected(String id) async {}
}

class _FakeActiveSessionsNotifier extends ActiveSessionsNotifier {
  @override
  ActiveSessionsState build() => const ActiveSessionsState();

  @override
  void updateWindowCount(
    String connectionId,
    String sessionName,
    int windowCount, {
    String? sessionId,
  }) {}
}

class _FakeTerminalDisplayNotifier extends TerminalDisplayNotifier {
  @override
  TerminalDisplayState build() => const TerminalDisplayState(
    paneWidth: 80,
    paneHeight: 24,
    screenWidth: 400.0,
    screenHeight: 800.0,
    calculatedFontSize: 14.0,
  );
}

class FakeImageTransferNotifier extends ImageTransferNotifier {
  String? uploadResult;

  @override
  ImageTransferState build() => const ImageTransferState();

  void emit(ImageTransferState next) => state = next;

  @override
  Future<String?> confirmAndUpload({
    required ImageTransferOptions options,
  }) async {
    final result = uploadResult;
    if (result != null) {
      state = ImageTransferState(
        phase: ImageTransferPhase.completed,
        lastUploadedPath: result,
        uploadProgress: 1,
      );
    }
    return result;
  }
}

class _FakeAlertPanesNotifier extends AlertPanesNotifier {
  @override
  AlertPanesState build() => const AlertPanesState();
}

/// TerminalScreen 用のテストフィクスチャ。
///
/// ProviderScope で各 provider を fake で上書きし、ネットワークや
/// SharedPreferences / SecureStorage への依存を排除する。
class TerminalTestScaffold {
  static Future<FakeSshClient> pumpTerminalScreen(
    WidgetTester tester, {
    String connectionId = 'test-conn',
    String? sessionName,
    String? sessionId,
    int? lastWindowIndex,
    String? lastPaneId,
    String? deepLinkWindowName,
    int? deepLinkPaneIndex,
    AppSettings settings = const AppSettings(keepScreenOn: false),
    Map<String, String> execOutputs = const {},
    Map<String, int> execExitCodes = const {},
    Map<String, List<String>> execOutputQueues = const {},
    FakeImageTransferNotifier? imageTransferNotifier,
    Connection? connection,
    Map<String, String>? secureStorageValues,
    // herdr（read-only）向け
    bool readOnly = false,
    String? initialPaneId,
    PaneContentReader? paneContentReader,
    // ライブポーリングが動く間は pumpAndSettle が終わらないため
    // herdr 系テストでは false にして手動 pump する
    bool settle = true,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);

    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues(secureStorageValues ?? const {});
    addTearDown(() => SecureStorageService.setTestValues(null));

    final client = FakeSshClient();
    client.execOutputs = {
      'tmux -V': 'tmux 3.4',
      'list-panes -a': kFullTreeOutput,
      'capture-pane': 'hello\n1,2,80,24\n',
      'display-message -p': '1 2 80 24',
      ...execOutputs,
    };
    client.execExitCodes = execExitCodes;
    client.execOutputQueues.addAll({
      for (final entry in execOutputQueues.entries)
        entry.key: List<String>.of(entry.value),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(settings: settings),
          ),
          connectionsProvider.overrideWith(
            () => _FakeConnectionsNotifier(connection: connection),
          ),
          sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
          tmuxProvider.overrideWith(
            () => FakeTmuxNotifier(initialState: const TmuxState()),
          ),
          activeSessionsProvider.overrideWith(
            () => _FakeActiveSessionsNotifier(),
          ),
          terminalDisplayProvider.overrideWith(
            () => _FakeTerminalDisplayNotifier(),
          ),
          imageTransferProvider.overrideWith(
            () => imageTransferNotifier ?? FakeImageTransferNotifier(),
          ),
          alertPanesProvider.overrideWith(() => _FakeAlertPanesNotifier()),
        ],
        child: MaterialApp(
          home: TerminalScreen(
            connectionId: connectionId,
            sessionName: sessionName,
            sessionId: sessionId,
            lastWindowIndex: lastWindowIndex,
            lastPaneId: lastPaneId,
            deepLinkWindowName: deepLinkWindowName,
            deepLinkPaneIndex: deepLinkPaneIndex,
            readOnly: readOnly,
            initialPaneId: initialPaneId,
            paneContentReader: paneContentReader,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // 接続 + 初回ポーリング分だけ進める
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
    }
    return client;
  }
}
