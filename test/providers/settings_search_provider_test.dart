// 設定検索 Provider（settings_search_provider.dart）の単体テスト。
//
// 純 Dart + ProviderContainer（ウィジェットなし）。settingsSearchIndexProvider は
// settingsProvider.language のみ watch するため、SharedPreferences をモックして
// ProviderContainer で直接検証する。
//
// 検証対象（計画 §L3 P2-C6）:
// - 大小文字 contains / title・description・カテゴリ名・値ラベル
// - 言語横断（ja index で 'font'・en index で「フォント」・'system' でも en/ja 両ヒット）
// - ランキング（現在ロケール優先・カテゴリ順・order）
// - 言語切替で再構築（language のみ watch・クエリ/トグルでは再構築されない）
// - クエリ保持（非 autoDispose）
// - 空クエリ空リスト / ゲート項目（Overlay Position）ヒット
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/settings/search/settings_search_provider.dart';
import 'package:flutter_muxpod/screens/settings/settings_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // settingsProvider.build()/_loadSettings() の SystemChrome 呼び出しを no-op 化
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    container = ProviderContainer();
    // build() をトリガー（デフォルト language = 'system'）。
    // _loadSettings は fire-and-forget のため、非同期完了を待ってから検証する
    // （TEST-SETTINGS-PROVIDER-001 と同じ不安定要因 R-1 の回避）。
    container.read(settingsProvider);
    await pumpEventQueue();
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    // l10n 言語キャッシュが他テストへ波及しないようリセットする。
    setCachedLanguage(null);
  });

  Future<void> setLanguage(String language) async {
    await container.read(settingsProvider.notifier).setLanguage(language);
  }

  Future<void> setQuery(String query) async {
    container.read(settingsSearchProvider.notifier).setQuery(query);
  }

  /// フィルタ結果のヒット project を文字列化する（title=item.id）。
  List<String> hitIds() =>
      container.read(filteredSettingsProvider).map((h) => h.item.id).toList();

  group('settingsSearchProvider 基本', () {
    test('空クエリは空リストを返す', () {
      expect(container.read(settingsSearchProvider), '');
      expect(container.read(filteredSettingsProvider), isEmpty);
    });

    test('空白のみのクエリも空リスト（一覧表示を維持）', () async {
      await setQuery('   ');
      expect(container.read(filteredSettingsProvider), isEmpty);
    });

    test('setQuery / clear でクエリが保持される（非 autoDispose）', () async {
      await setQuery('font');
      expect(container.read(settingsSearchProvider), 'font');
      container.read(settingsSearchProvider.notifier).clear();
      expect(container.read(settingsSearchProvider), '');
      expect(container.read(filteredSettingsProvider), isEmpty);
    });
  });

  group('settingsSearchIndexProvider（language のみ watch・M-5）', () {
    test('言語切替で再構築される', () async {
      var rebuilds = 0;
      container.listen(
        settingsSearchIndexProvider,
        (_, _) => rebuilds++,
        fireImmediately: true,
      );
      expect(rebuilds, 1); // 初期値通知
      await setLanguage('ja');
      await pumpEventQueue();
      expect(rebuilds, 2);
      await setLanguage('en');
      await pumpEventQueue();
      expect(rebuilds, 3);
    });

    test('トグル変更（darkMode 等）では再構築されない', () async {
      var rebuilds = 0;
      container.listen(
        settingsSearchIndexProvider,
        (_, _) => rebuilds++,
        fireImmediately: true,
      );
      expect(rebuilds, 1); // 初期値通知のみ
      await container.read(settingsProvider.notifier).setDarkMode(false);
      await pumpEventQueue();
      await container.read(settingsProvider.notifier).setShowKeyOverlay(false);
      await pumpEventQueue();
      expect(rebuilds, 1);
    });

    test('インデックスは言語値を cross しても常に en/ja 両ロケールを並置する（M-2）', () async {
      // 'system'（端末ロケール=テスト en）でも両ロケール解決
      final systemIndex = container.read(settingsSearchIndexProvider);
      expect(
        systemIndex.items.length,
        36,
      ); // Display10+Behavior13+Connection10+About3
      expect(systemIndex.current, isNotNull);
      expect(systemIndex.other, isNotNull);

      await setLanguage('ja');
      final jaIndex = container.read(settingsSearchIndexProvider);
      expect(jaIndex.items.length, 36);
      expect(jaIndex.other, isNotNull); // en 側も並置

      await setLanguage('en');
      final enIndex = container.read(settingsSearchIndexProvider);
      expect(enIndex.items.length, 36);
      expect(enIndex.other, isNotNull); // ja 側も並置
    });
  });

  group('文言マッチ（大小文字・title/desc/カテゴリ/値ラベル）', () {
    test('大小文字 contains: "FONT" で font 系がヒット', () async {
      await setQuery('FONT');
      final ids = hitIds();
      expect(ids, contains('fontSize'));
      expect(ids, contains('fontFamily'));
      expect(ids, contains('minFontSize'));
    });

    test('title マッチ: "no results に近い" 以外の通常タイトル', () async {
      await setQuery('adjust');
      expect(hitIds(), contains('adjustMode'));
    });

    test('カテゴリ名マッチ: "Behavior" で Behavior カテゴリ全項目がヒット', () async {
      await setQuery('behavior');
      final ids = hitIds();
      expect(ids.length, 13); // Behavior は3グループ+フラット1の13項目
      expect(ids, contains('customButtons'));
      expect(ids, contains('invertPaneNavigation'));
    });

    test('値ラベル: "auto fit" で adjustMode がヒット', () async {
      await setQuery('auto fit');
      expect(hitIds(), contains('adjustMode'));
    });

    test('値ラベル: "120" で maxRefreshRate がヒット', () async {
      await setQuery('120');
      expect(hitIds(), contains('maxRefreshRate'));
    });

    test('値ラベル: "jpeg" で imageOutputFormat がヒット', () async {
      await setQuery('jpeg');
      expect(hitIds(), contains('imageOutputFormat'));
    });

    test(
      '値ラベル: "above keyboard" で overlayPosition がヒット（ゲート項目・DR-10）',
      () async {
        await setQuery('above keyboard');
        expect(hitIds(), contains('overlayPosition'));
      },
    );

    test('ゲート項目（Overlay Position）は showKeyOverlay=false でもヒット対象', () async {
      await container.read(settingsProvider.notifier).setShowKeyOverlay(false);
      await setQuery('overlay');
      expect(hitIds(), contains('overlayPosition'));
      expect(hitIds(), contains('keyOverlay'));
    });
  });

  group('言語横断（en/ja 両ラベル照合・🤝A2）', () {
    test('ja 表示中に "font" がヒット（en ラベル照合）', () async {
      await setLanguage('ja');
      await setQuery('font');
      expect(hitIds(), contains('fontSize'));
    });

    test('en 表示中に「フォント」がヒット（ja ラベル照合）', () async {
      await setLanguage('en');
      await setQuery('フォント');
      expect(hitIds(), contains('fontSize'));
      expect(hitIds(), contains('fontFamily'));
    });

    test('"ssh" で clearHostKeys がヒット（ja 表示中でも）', () async {
      await setLanguage('ja');
      await setQuery('ssh');
      expect(hitIds(), contains('clearHostKeys'));
    });

    test("'system'（端末ロケール=テスト en）でも en/ja 両方言語でヒット（M-2）", () async {
      // 初期値 'system' のまま
      await setQuery('font');
      expect(hitIds(), contains('fontSize')); // en
      await setQuery('フォント');
      expect(hitIds(), contains('fontSize')); // ja
    });
  });

  group('ランキング（現在ロケール優先・カテゴリ順・order）', () {
    test('en 表示: 現在ロケールヒットが先頭（フォント→ja のみヒットは後）', () async {
      await setLanguage('en');
      await setQuery('th');
      final hits = container.read(filteredSettingsProvider);
      // 'theme' は en タイトルで current ヒットするため、ja のみの item より前
      final themeIdx = hits.indexWhere((h) => h.item.id == 'theme');
      if (themeIdx >= 0) {
        expect(
          hits.take(themeIdx + 1).every((h) => h.matchedInCurrentLocale),
          isTrue,
        );
      }
    });

    test('同一クエリでマッチが空でないときカテゴリ順 → order 順で並ぶ', () async {
      await setQuery('font');
      final hits = container.read(filteredSettingsProvider);
      final ordering = hits.map((h) => h.item.category.index).toList();
      // 非降順（カテゴリ順・同カテゴリ内は order 昇順）
      for (var i = 1; i < ordering.length; i++) {
        expect(
          ordering[i] >= ordering[i - 1],
          isTrue,
          reason: 'カテゴリ順に並ぶべき（${hits[i - 1].item.id} → ${hits[i].item.id}）',
        );
      }
      // 同カテゴリ内 order 昇順
      for (final group in hits.groupBy((h) => h.item.category)) {
        final orders = group.map((h) => h.item.orderInCategory).toList();
        expect(orders, List.of(orders)..sort(), reason: 'カテゴリ内 order 昇順');
      }
    });
  });

  group('検索対象の完全性（全36項目）', () {
    test('36項目すべてが descriptor に存在しカテゴリと order が一意', () {
      final index = container.read(settingsSearchIndexProvider);
      final ids = index.items.map((e) => e.id).toList();
      expect(ids.toSet().length, 36);
      // カテゴリ内 order が一意（0..n-1 の重複なし）
      for (final category in SettingsCategory.values) {
        final perCategory =
            index.items.where((e) => e.category == category).toList()
              ..sort((a, b) => a.orderInCategory.compareTo(b.orderInCategory));
        final orders = perCategory.map((e) => e.orderInCategory).toList();
        expect(orders, List.generate(orders.length, (i) => i));
      }
      expect(
        index.items.where((e) => e.category == SettingsCategory.display).length,
        10,
      );
      expect(
        index.items
            .where((e) => e.category == SettingsCategory.behavior)
            .length,
        13,
      );
      expect(
        index.items
            .where((e) => e.category == SettingsCategory.connection)
            .length,
        10,
      );
      expect(
        index.items.where((e) => e.category == SettingsCategory.about).length,
        3,
      );
    });
  });
}

extension _GroupBy<T> on Iterable<T> {
  Iterable<List<T>> groupBy(SettingsCategory Function(T) keyOf) sync* {
    final groups = <SettingsCategory, List<T>>{};
    for (final e in this) {
      groups.putIfAbsent(keyOf(e), () => []).add(e);
    }
    yield* groups.values;
  }
}
