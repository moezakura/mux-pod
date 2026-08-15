import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/connections/connection_form_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_client.dart';

class _TestSshClient extends FakeSshClient {
  SshConnectOptions? lastOptions;

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
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues({});
  });

  testWidgets('migration E2E: old tmuxPath -> load -> edit -> save -> reload', (
    tester,
  ) async {
    // 1. 旧 tmuxPath 形式の接続を保存
    final oldJson = jsonEncode([
      {
        'id': 'c1',
        'name': 'Legacy',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'tmuxPath': '/legacy/tmux',
      },
    ]);
    final secure = SecureStorageService();
    await secure.writeValue('connections', oldJson);

    // 2. ProviderContainer で起動読み込み（マイグレーション実行）
    final container = ProviderContainer(
      overrides: [
        connectionFormSshClientFactoryProvider.overrideWith(
          (ref) =>
              () => _TestSshClient(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionsProvider.notifier).reload();

    final firstState = container.read(connectionsProvider);
    expect(firstState.connections, hasLength(1));
    expect(firstState.connections.first.multiplexer.backend, BackendType.tmux);
    expect(
      firstState.connections.first.multiplexer.executablePath,
      '/legacy/tmux',
    );

    // 3. 接続編集画面を開く
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionFormScreen(connectionId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 既存の multiplexer パスが読み込まれている
    final multiplexerField = find.byType(TextFormField).at(4);
    expect(
      tester.widget<TextFormField>(multiplexerField).controller?.text,
      '/legacy/tmux',
    );

    // 4. パスを変更して保存
    await tester.enterText(multiplexerField, '/new/tmux');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 5. 再起動をシミュレートして再度読み込み
    final restartContainer = ProviderContainer();
    addTearDown(restartContainer.dispose);
    await restartContainer.read(connectionsProvider.notifier).reload();

    final reloaded = restartContainer.read(connectionsProvider);
    expect(reloaded.connections, hasLength(1));
    expect(reloaded.connections.first.multiplexer.backend, BackendType.tmux);
    expect(reloaded.connections.first.multiplexer.executablePath, '/new/tmux');
  });
}
