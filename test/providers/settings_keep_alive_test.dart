// SSH キープアライブ全体設定（S7）の検証テスト。
//
// - AppSettings.keepAliveTimeoutSeconds の既定値（null = 自動）と
//   copyWith（設定 / clearKeepAliveTimeout によるクリア）。
// - SettingsPersistence の settings_keep_alive_timeout キーによる
//   永続化（未保存 = null 自動・保存→復元の往復・不正値は null フォールバック）。
// - SettingsNotifier.setKeepAliveTimeoutSeconds による状態更新と
//   SharedPreferences への保存 / キー削除。
// - ConnectionSection の SSH グループと keep_alive_timeout_picker の
//   選択が SharedPreferences に永続・復元されること（plan §L4 テスト 12）。
//
// 既存 settings テスト（settings_provider_test.dart / settings_persistence_test.dart）
// のパターンに倣う。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_persistence.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/sections/connection_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // SettingsNotifier.build() 内の SystemChrome.setPreferredOrientations を
    // no-op 化（既存 settings テストと同一の配慮）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('AppSettings.keepAliveTimeoutSeconds（状態モデル）', () {
    test('既定値は null（自動）である', () {
      expect(const AppSettings().keepAliveTimeoutSeconds, isNull);
    });

    test('copyWith で値を設定できる', () {
      final updated = const AppSettings().copyWith(keepAliveTimeoutSeconds: 30);
      expect(updated.keepAliveTimeoutSeconds, 30);
    });

    test('clearKeepAliveTimeout で null（自動）へ戻せる', () {
      final updated = const AppSettings()
          .copyWith(keepAliveTimeoutSeconds: 30)
          .copyWith(clearKeepAliveTimeout: true);
      expect(updated.keepAliveTimeoutSeconds, isNull);
    });

    test('copyWith の null は既存値を維持する（?? パターン）', () {
      final updated = const AppSettings()
          .copyWith(keepAliveTimeoutSeconds: 30)
          .copyWith();
      expect(updated.keepAliveTimeoutSeconds, 30);
    });

    test('keepAliveTimeoutPresets は picker の選択肢（5/10/15/20/30/60 秒）', () {
      expect(keepAliveTimeoutPresets, [5, 10, 15, 20, 30, 60]);
    });

    group('keepAliveTimeoutFromPersisted（不正値 null フォールバック）', () {
      test('プリセット内の値はそのまま復元する', () {
        for (final preset in keepAliveTimeoutPresets) {
          expect(AppSettings.keepAliveTimeoutFromPersisted(preset), preset);
        }
      });

      test('プリセット外の int は null へフォールバックする', () {
        expect(AppSettings.keepAliveTimeoutFromPersisted(4), isNull);
        expect(AppSettings.keepAliveTimeoutFromPersisted(61), isNull);
        expect(AppSettings.keepAliveTimeoutFromPersisted(999), isNull);
      });

      test('型不一致・null は null へフォールバックする', () {
        expect(AppSettings.keepAliveTimeoutFromPersisted('30'), isNull);
        expect(AppSettings.keepAliveTimeoutFromPersisted(30.0), isNull);
        expect(AppSettings.keepAliveTimeoutFromPersisted(null), isNull);
      });
    });
  });

  group('SettingsPersistence keepAliveTimeout（永続化）', () {
    test('キー文字列は settings_keep_alive_timeout である', () {
      expect(
        SettingsPersistence.keepAliveTimeoutKey,
        'settings_keep_alive_timeout',
      );
    });

    test('未保存時の復元は null（自動）である', () async {
      final loaded = await SettingsPersistence().load();
      expect(loaded.keepAliveTimeoutSeconds, isNull);
    });

    test('保存→復元の往復ができる', () async {
      final persistence = SettingsPersistence();
      await persistence.save(SettingsPersistence.keepAliveTimeoutKey, 30);
      final loaded = await persistence.load();
      expect(loaded.keepAliveTimeoutSeconds, 30);
    });

    test('プリセット外の保存値は null（自動）へフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        SettingsPersistence.keepAliveTimeoutKey: 999,
      });
      final loaded = await SettingsPersistence().load();
      expect(loaded.keepAliveTimeoutSeconds, isNull);
    });

    test('型不一致の保存値は null（自動）へフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        SettingsPersistence.keepAliveTimeoutKey: 'invalid',
      });
      final loaded = await SettingsPersistence().load();
      expect(loaded.keepAliveTimeoutSeconds, isNull);
    });

    test('save(null) はキーを削除する', () async {
      final persistence = SettingsPersistence();
      await persistence.save(SettingsPersistence.keepAliveTimeoutKey, 20);
      await persistence.save(SettingsPersistence.keepAliveTimeoutKey, null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(SettingsPersistence.keepAliveTimeoutKey), isNull);
      final loaded = await persistence.load();
      expect(loaded.keepAliveTimeoutSeconds, isNull);
    });
  });

  group('SettingsNotifier.setKeepAliveTimeoutSeconds', () {
    Future<ProviderContainer> pumpContainer(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      // read で build() をトリガーし、fire-and-forget の _loadSettings を
      // pumpAndSettle で確実に完了させる。
      container.read(settingsProvider);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('設定値が状態と SharedPreferences に反映される', (tester) async {
      final container = await pumpContainer(tester);

      await container
          .read(settingsProvider.notifier)
          .setKeepAliveTimeoutSeconds(20);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).keepAliveTimeoutSeconds, 20);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SettingsPersistence.keepAliveTimeoutKey), 20);
    });

    testWidgets('null で自動へ戻すと状態が null・キーが削除される', (tester) async {
      final container = await pumpContainer(tester);

      await container
          .read(settingsProvider.notifier)
          .setKeepAliveTimeoutSeconds(20);
      await container
          .read(settingsProvider.notifier)
          .setKeepAliveTimeoutSeconds(null);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).keepAliveTimeoutSeconds, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(SettingsPersistence.keepAliveTimeoutKey), isNull);
    });

    testWidgets('永続化した値は新しいコンテナ（アプリ再起動相当）で復元される', (tester) async {
      final container = await pumpContainer(tester);
      await container
          .read(settingsProvider.notifier)
          .setKeepAliveTimeoutSeconds(15);
      await tester.pumpAndSettle();
      container.dispose();

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      restarted.read(settingsProvider);
      await tester.pumpAndSettle();

      expect(restarted.read(settingsProvider).keepAliveTimeoutSeconds, 15);
    });
  });

  group('ConnectionSection SSH グループと picker（テスト 12）', () {
    Future<ProviderContainer> pumpSection(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(
              body: SingleChildScrollView(child: ConnectionSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('既定（未設定）では「自動」が表示される', (tester) async {
      await pumpSection(tester);

      expect(find.text('SSH keepalive probe timeout'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('picker で 10 秒を選択すると状態と SharedPreferences に永続される', (
      tester,
    ) async {
      final container = await pumpSection(tester);

      final tile = find.text('SSH keepalive probe timeout');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // 自動 + プリセット 6 値の選択肢が並ぶ。
      expect(find.byType(RadioListTile<int>), findsNWidgets(7));

      await tester.tap(find.text('10 s'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).keepAliveTimeoutSeconds, 10);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SettingsPersistence.keepAliveTimeoutKey), 10);
      // ダイアログが閉じ、サブタイトルが選択値へ更新される。
      expect(find.text('10 s'), findsOneWidget);
    });

    testWidgets('設定済みの値から「自動」へ戻すとキーが削除される', (tester) async {
      final container = await pumpSection(tester);
      await container
          .read(settingsProvider.notifier)
          .setKeepAliveTimeoutSeconds(20);
      await tester.pumpAndSettle();

      final tile = find.text('SSH keepalive probe timeout');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).keepAliveTimeoutSeconds, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(SettingsPersistence.keepAliveTimeoutKey), isNull);
      expect(find.text('Auto'), findsOneWidget);
    });
  });
}
