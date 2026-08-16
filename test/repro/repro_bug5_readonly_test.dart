// Repro: バグ5 TestConnection のときに「Readonly」と表示される（修正済み）
//
// バグ内容:
// - connection_form_screen.dart: herdr 接続テスト成功時の SnackBar が
//   'Connection successful! Herdr is available (read-only).' と表示していた
// - 0da0db9 で read-only 時代の文言として追加され、2c8f02b で mutation 解禁に
//   なった際に更新漏れしていた
//
// 修正: l10n 移行（connTestSuccessHerdr）で tmux と揃えて
// 'Connection successful! Herdr is available.' になった。
// 本テストは修正後の正しい挙動をアサートするリグレッションガードとして維持する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/connections/connection_form_screen.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../helpers/fake_ssh_client.dart';

const _kHerdrStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

class _FakeConnectionsNotifier extends ConnectionsNotifier {
  @override
  ConnectionsState build() => const ConnectionsState();
}

class _TestSshClient extends FakeSshClient {
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
    AppLocalizations? l10n,
  }) async {
    state = SshConnectionState.connected;
  }
}

Future<_TestSshClient> _pumpForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final connections = _FakeConnectionsNotifier();
  final fakeClient = _TestSshClient();
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
        home: ConnectionFormScreen(connectionId: null),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fakeClient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setTestValues({});
  });

  group('Repro BUG-5: TestConnection 成功時に "(read-only)" が表示されない（修正確認）', () {
    testWidgets('herdr 接続テスト成功の SnackBar に "(read-only)" が含まれない', (
      tester,
    ) async {
      final client = await _pumpForm(tester);
      client.execOutputs['herdr status --json'] = _kHerdrStatusOk;

      // 名前入力前にトグルを選択
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

      // 修正後: tmux と揃えて l10n.connTestSuccessHerdr の文言が表示される
      expect(
        find.text('Connection successful! Herdr is available.'),
        findsOneWidget,
        reason: 'l10n.connTestSuccessHerdr の文言が表示されること',
      );
      expect(find.textContaining('read-only'), findsNothing);
    });

    testWidgets('tmux 接続テスト成功の SnackBar には "(read-only)" が含まれない（比較対照）', (
      tester,
    ) async {
      await _pumpForm(tester);

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
      expect(find.textContaining('read-only'), findsNothing);
    });
  });
}
