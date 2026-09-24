import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_view_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// リンク起動コーディネータ `TerminalViewShell.openExternalLink`
/// （Issue #61 / 🤝#3・Phase 4 #12）の widget テスト。
///
/// scheme ガード → 設定分岐（OFF 既定 = 確認モーダル / ON = 直接起動）→
/// 外部起動の単一ファネルを検証する。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （MethodChannel モック・実機確認で補う）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  /// url_launcher プラットフォームチャンネルをモックし呼び出しを記録する
  /// （markdown_preview_link_guard_test.dart と同一手法）。
  List<MethodCall> mockUrlLauncher(WidgetTester tester, bool canLaunch) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return canLaunch;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    return calls;
  }

  /// settingsProvider を load 完了まで待機しつつ、コーディネータ起動
  /// ボタン付きのハーネスを pump する（settings_provider_test.dart パターン）。
  Future<ProviderContainer> pumpHarness(
    WidgetTester tester,
    String triggerUrl,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => TerminalViewShell.openExternalLink(
                  context,
                  ref,
                  triggerUrl,
                ),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );
    // read で build() をトリガーし、fire-and-forget の _loadSettings を
    // pumpAndSettle で確実に完了させる（settings_provider_test.dart 同一）。
    container.read(settingsProvider);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('設定 OFF（既定）: 確認モーダル経由で「開く」→ 外部起動', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final calls = mockUrlLauncher(tester, true);
    await pumpHarness(tester, 'https://example.com/page');

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // 既定（openLinksDirectly = false）は確認モーダルを表示する
    expect(find.text('Open Link?'), findsOneWidget);
    expect(calls.where((c) => c.method == 'canLaunch'), isEmpty);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(calls.where((c) => c.method == 'canLaunch'), hasLength(1));
    final launches = calls.where((c) => c.method == 'launch').toList();
    expect(launches, hasLength(1));
    expect((launches.single.arguments as Map)['url'], 'https://example.com/page');
  });

  testWidgets('設定 OFF: モーダル「キャンセル」→ 外部起動しない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final calls = mockUrlLauncher(tester, true);
    await pumpHarness(tester, 'https://example.com/page');

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls.where((c) => c.method == 'launch'), isEmpty);
  });

  testWidgets('設定 ON（openLinksDirectly）: モーダル無しで直接外部起動', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_open_links_directly': true,
    });
    final calls = mockUrlLauncher(tester, true);
    await pumpHarness(tester, 'https://example.com/page');

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // モーダルを表示せず直接起動する
    expect(find.text('Open Link?'), findsNothing);
    final launches = calls.where((c) => c.method == 'launch').toList();
    expect(launches, hasLength(1));
    expect((launches.single.arguments as Map)['url'], 'https://example.com/page');
  });

  testWidgets('非 https/http URL（javascript:）は無視され無反応', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_open_links_directly': true,
    });
    final calls = mockUrlLauncher(tester, true);
    await pumpHarness(tester, 'javascript:alert(1)');

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // scheme ガードにより canLaunch も launch も呼ばない・モーダルも出ない
    expect(find.text('Open Link?'), findsNothing);
    expect(calls, isEmpty);
  });
}
