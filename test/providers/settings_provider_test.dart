// settings_provider の永続化・状態管理を検証するテスト。
//
// - scrollSendInput / invertScrollSendDirection（Scroll Send 設定）の
//   永続化・copyWith 検証（scroll-emulation 由来）。
// - SettingsNotifier.setLanguage() が SharedPreferences の 'settings_language'
//   キーへ保存し、新しいコンテナ（アプリ再起動相当）の再読込（reload() /
//   build() 内の _loadSettings）で復元されることを確認する。
//
// 注意: SettingsNotifier.build()/_loadSettings() は
// SystemChrome.setPreferredOrientations を呼ぶため、テストでは
// SystemChannels.platform を no-op にモックする。
// （_applyRefreshRate は Platform.isAndroid ガードによりテストホストでは
// 実行されない。）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _languageKey = 'settings_language';

/// SettingsNotifier.build() は fire-and-forget で _loadSettings() を開始するため、
/// 素の ProviderContainer テストでは dispose 前に非同期完了が保証されない。
/// testWidgets + pumpAndSettle で確実に完了させてから検証する。
// inventory: TEST-SETTINGS-PROVIDER-001
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // _loadSettings() 内の SystemChrome.setPreferredOrientations を no-op 化
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    // l10n 言語キャッシュが他テストへ波及しないようリセットする。
    setCachedLanguage(null);
  });

  group('AppSettings scrollSendInput / invertScrollSendDirection', () {
    Future<ProviderContainer> pumpContainer(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      // read で build() をトリガーしてから、fire-and-forget の _loadSettings を
      // pumpAndSettle で確実に完了させる（read は同期でデフォルトを返すため、
      // この直後の read は更新後の state を返す）
      container.read(settingsProvider);
      await tester.pumpAndSettle();
      return container;
    }

    // inventory: TEST-SETTINGS-PROVIDER-002
    testWidgets('defaults are wheel and false', (tester) async {
      final container = await pumpContainer(tester);

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'wheel');
      expect(settings.invertScrollSendDirection, isFalse);
    });

    // inventory: TEST-SETTINGS-PROVIDER-003
    testWidgets('loads persisted values from prefs', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_scroll_send_input': 'key',
        'settings_invert_scroll_send_direction': true,
      });
      final container = await pumpContainer(tester);

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'key');
      expect(settings.invertScrollSendDirection, isTrue);
    });

    // inventory: TEST-SETTINGS-PROVIDER-004
    testWidgets('setScrollSendInput updates state and persists', (
      tester,
    ) async {
      final container = await pumpContainer(tester);

      await container.read(settingsProvider.notifier).setScrollSendInput('key');
      await tester.pump();

      final settings = container.read(settingsProvider);
      expect(settings.scrollSendInput, 'key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_scroll_send_input'), 'key');
    });

    // inventory: TEST-SETTINGS-PROVIDER-005
    testWidgets('setInvertScrollSendDirection updates state and persists', (
      tester,
    ) async {
      final container = await pumpContainer(tester);

      await container
          .read(settingsProvider.notifier)
          .setInvertScrollSendDirection(true);
      await tester.pump();

      final settings = container.read(settingsProvider);
      expect(settings.invertScrollSendDirection, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_invert_scroll_send_direction'), isTrue);
    });

    // inventory: TEST-SETTINGS-PROVIDER-006
    test('copyWith preserves other settings', () {
      const base = AppSettings();
      final updated = base.copyWith(
        scrollSendInput: 'key',
        invertScrollSendDirection: true,
        autoFitZoomOnScrollSend: true,
      );
      expect(updated.scrollSendInput, 'key');
      expect(updated.invertScrollSendDirection, isTrue);
      expect(updated.autoFitZoomOnScrollSend, isTrue);
      expect(updated.invertPaneNavigation, isFalse);
      expect(updated.darkMode, isTrue);
    });

    // inventory: TEST-SETTINGS-PROVIDER-008
    testWidgets('autoFitZoomOnScrollSend defaults to false', (tester) async {
      final container = await pumpContainer(tester);
      expect(container.read(settingsProvider).autoFitZoomOnScrollSend, isFalse);
    });

    // inventory: TEST-SETTINGS-PROVIDER-009
    testWidgets('setAutoFitZoomOnScrollSend updates state and persists', (
      tester,
    ) async {
      final container = await pumpContainer(tester);

      await container
          .read(settingsProvider.notifier)
          .setAutoFitZoomOnScrollSend(true);
      await tester.pump();

      expect(container.read(settingsProvider).autoFitZoomOnScrollSend, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_auto_fit_zoom_on_scroll_send'), isTrue);
    });
  });

  group('wheelSendVerifiedProvider', () {
    // inventory: TEST-SETTINGS-PROVIDER-007
    test('defaults to true (verified via Phase 0 B1/B2)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(wheelSendVerifiedProvider), isTrue);
    });
  });

  group('SettingsNotifier language 永続化', () {
    test('未保存時はデフォルト "system" になる', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).language, 'system');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_languageKey), isFalse);
    });

    test('setLanguage で state が更新され SharedPreferences に保存される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build() 内の fire-and-forget _loadSettings 完了を待ってから変更する
      // （pending のまま state を変えると riverpod がエラーを投げる）
      await container.read(settingsProvider.notifier).reload();
      await container.read(settingsProvider.notifier).setLanguage('ja');

      expect(container.read(settingsProvider).language, 'ja');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_languageKey), 'ja');
    });

    test('保存した言語は新規コンテナ（再起動相当）の再読込で復元される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).reload();
      await container.read(settingsProvider.notifier).setLanguage('ja');

      // アプリ再起動を模擬: 新しい ProviderContainer で読み直す
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(settingsProvider.notifier).reload();

      expect(restarted.read(settingsProvider).language, 'ja');
    });

    test('"en" と "system" もラウンドトリップで復元される', () async {
      for (final language in ['en', 'system']) {
        SharedPreferences.setMockInitialValues({});

        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(settingsProvider.notifier).reload();
        await container.read(settingsProvider.notifier).setLanguage(language);
        expect(container.read(settingsProvider).language, language);

        final restarted = ProviderContainer();
        addTearDown(restarted.dispose);
        await restarted.read(settingsProvider.notifier).reload();

        expect(
          restarted.read(settingsProvider).language,
          language,
          reason: 'language="$language" が再読込後も保持されること',
        );
      }
    });

    test('reload() は SharedPreferences の保存値を再適用する', () async {
      // 事前に保存済みの値がある状態（アプリ再起動直後相当）
      SharedPreferences.setMockInitialValues({_languageKey: 'en'});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).language, 'en');

      // 保存値を書き換えて reload() → 反映される
      await container.read(settingsProvider.notifier).setLanguage('system');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, 'ja');
      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).language, 'ja');
    });
  });

  group('SettingsNotifier cjkMode 永続化', () {
    test('未保存時はデフォルト false になる', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).cjkMode, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('settings_cjk_mode'), isFalse);
    });

    test('setCjkMode で state が更新され SharedPreferences に保存される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).reload();
      await container.read(settingsProvider.notifier).setCjkMode(true);

      expect(container.read(settingsProvider).cjkMode, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_cjk_mode'), isTrue);
    });

    test('保存した cjkMode は新規コンテナ（再起動相当）の再読込で復元される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).reload();
      await container.read(settingsProvider.notifier).setCjkMode(true);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(settingsProvider.notifier).reload();

      expect(restarted.read(settingsProvider).cjkMode, isTrue);
    });

    test('copyWith は cjkMode を指定しない場合他の設定のみ変更する', () {
      const base = AppSettings(cjkMode: true);
      final updated = base.copyWith(keepScreenOn: false);
      expect(updated.cjkMode, isTrue);
      expect(updated.keepScreenOn, isFalse);

      final toggled = base.copyWith(cjkMode: false);
      expect(toggled.cjkMode, isFalse);
    });
  });

  group('SettingsNotifier keepKeyboardOnEnter 永続化', () {
    test('未保存時はデフォルト false になる', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).keepKeyboardOnEnter, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('settings_keep_keyboard_on_enter'), isFalse);
    });

    test(
      'setKeepKeyboardOnEnter で state が更新され SharedPreferences に保存される',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container.read(settingsProvider.notifier).reload();
        await container
            .read(settingsProvider.notifier)
            .setKeepKeyboardOnEnter(true);

        expect(container.read(settingsProvider).keepKeyboardOnEnter, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('settings_keep_keyboard_on_enter'), isTrue);
      },
    );

    test('保存した keepKeyboardOnEnter は新規コンテナ（再起動相当）の再読込で復元される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).reload();
      await container
          .read(settingsProvider.notifier)
          .setKeepKeyboardOnEnter(true);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(settingsProvider.notifier).reload();

      expect(restarted.read(settingsProvider).keepKeyboardOnEnter, isTrue);
    });

    test('copyWith は keepKeyboardOnEnter を指定しない場合他の設定のみ変更する', () {
      const base = AppSettings(keepKeyboardOnEnter: true);
      final updated = base.copyWith(keepScreenOn: false);
      expect(updated.keepKeyboardOnEnter, isTrue);
      expect(updated.keepScreenOn, isFalse);

      final toggled = base.copyWith(keepKeyboardOnEnter: false);
      expect(toggled.keepKeyboardOnEnter, isFalse);
    });
  });

  group('SettingsNotifier downloadDirectory（既定ダウンロード先・Issue #40）', () {
    test('未保存時はデフォルト空文字になる', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).reload();

      expect(container.read(settingsProvider).downloadDirectory, '');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('settings_download_directory'), isFalse);
    });

    test(
      'setDownloadDirectory で state が更新され SharedPreferences に保存される',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container.read(settingsProvider.notifier).reload();
        await container
            .read(settingsProvider.notifier)
            .setDownloadDirectory('/storage/emulated/0/Download');

        expect(
          container.read(settingsProvider).downloadDirectory,
          '/storage/emulated/0/Download',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('settings_download_directory'),
          '/storage/emulated/0/Download',
        );
      },
    );

    test('保存した downloadDirectory は新規コンテナ（再起動相当）の再読込で復元される', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).reload();
      await container
          .read(settingsProvider.notifier)
          .setDownloadDirectory('downloads/');

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(settingsProvider.notifier).reload();

      expect(restarted.read(settingsProvider).downloadDirectory, 'downloads/');
    });

    test('copyWith は downloadDirectory を指定しない場合他の設定のみ変更する', () {
      const base = AppSettings(downloadDirectory: 'downloads/');
      final updated = base.copyWith(keepScreenOn: false);
      expect(updated.downloadDirectory, 'downloads/');
      expect(updated.keepScreenOn, isFalse);

      final cleared = base.copyWith(downloadDirectory: '');
      expect(cleared.downloadDirectory, '');
    });
  });
}
