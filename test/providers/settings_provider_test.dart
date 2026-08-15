// settings_provider の language 設定の永続化を検証するテスト。
//
// SettingsNotifier.setLanguage() が SharedPreferences の 'settings_language'
// キーへ保存し、新しいコンテナ（アプリ再起動相当）の再読込（reload() /
// build() 内の _loadSettings）で復元されることを確認する。
//
// 注意: SettingsNotifier.build()/_loadSettings() は
// SystemChrome.setPreferredOrientations を呼ぶため、テストでは
// SystemChannels.platform を no-op にモックする。
// （_applyRefreshRate は Platform.isAndroid ガードによりテストホストでは
// 実行されない。）
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _languageKey = 'settings_language';

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
}
