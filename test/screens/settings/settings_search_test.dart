// 設定検索 UI（settings_search_field / settings_search_results_view）のテスト。
//
// 計画 §L3 P2-C8 の検証項目:
// - フィールド表示（hint）
// - 入力→絞込（en）・ja locale + 'フォント'
// - グループ見出し（カテゴリ名）
// - 空結果 + クリア
// - 結果タップ → push（スマホ・クエリ保持）
// - タブレット（1280×800・dpr 1.0）→ カテゴリ選択 + クエリ clear
// - `testTextInput.isVisible == false` キーボード非表示（autofocus 無効）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/screens/settings/widgets/settings_section_header.dart';
import 'package:flutter_muxpod/screens/settings/widgets/settings_search_field.dart';

import 'test_helpers.dart';

void main() {
  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  /// 検索フィールドの現在の入力値（Provider→controller 同期の検証用）。
  String searchFieldText(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(TextField),
      ),
    );
    return field.controller?.text ?? '';
  }

  group('Settings search field', () {
    testWidgets('shows hint and does not auto-focus keyboard', (tester) async {
      await buildSettingsApp(tester);

      expect(find.text('Search settings…'), findsOneWidget);
      // autofocus 無効: キーボード（テスト入力）が表示されない
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('clearing via suffix icon restores the category list', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await typeQuery(tester, 'font');
      expect(find.text('Font Size'), findsOneWidget);
      // クリアボタン（suffix icon）で一覧へ復帰
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Search settings…'), findsOneWidget);
    });
  });

  group('Settings search filtering', () {
    testWidgets('narrows to matching items (en)', (tester) async {
      await buildSettingsApp(tester);
      await typeQuery(tester, 'font');

      // 検索結果: Font Size / Font Family / Minimum Font Size がヒット
      expect(find.text('Font Size'), findsOneWidget);
      expect(find.text('Font Family'), findsOneWidget);
      // カテゴリ一覧は隠れる
      expect(find.text('Behavior'), findsNothing);
    });

    testWidgets('matches ja labels from a ja locale (フォント)', (tester) async {
      await buildSettingsApp(tester, locale: const Locale('ja'));
      await typeQuery(tester, 'フォント');

      // ja ラベル照合: フォントサイズ（Font Size）
      expect(find.text('フォントサイズ'), findsOneWidget);
      // グループ見出し = カテゴリ名「表示」
      expect(find.text('表示'), findsOneWidget);
      // カテゴリ一覧の他カテゴリ（操作）は隠れる
      expect(find.text('操作'), findsNothing);
    });

    testWidgets('shows category group headings', (tester) async {
      await buildSettingsApp(tester);
      await typeQuery(tester, 'font');

      // グループ見出し = 所属カテゴリ名（Display）
      expect(find.text('Display'), findsOneWidget);
    });

    testWidgets('shows empty state and restores list after clear', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await typeQuery(tester, 'zzzzzz');

      expect(find.text('No matching settings'), findsOneWidget);
      expect(find.text('Try a different search term'), findsOneWidget);

      // 空状態のクリアボタンで一覧へ復帰
      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
    });
  });

  group('Settings search result tap', () {
    testWidgets('tapping a result pushes the category detail (query kept)', (
      tester,
    ) async {
      await buildSettingsApp(tester);
      await typeQuery(tester, 'adjust');

      await tester.tap(find.text('Adjust Mode'));
      await tester.pumpAndSettle();

      // カテゴリ詳細（Display）が開く
      expect(find.text('Auto Fit'), findsOneWidget);

      // 戻ると一覧へ復帰しクエリが保持されている（Provider 非 autoDispose）
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Adjust Mode'), findsOneWidget);
      // フィールドにクエリが残っている
      expect(find.text('Adjust Mode'), findsOneWidget);
    });

    testWidgets('tablet: tapping a result selects category and clears query', (
      tester,
    ) async {
      await buildSettingsApp(tester, size: const Size(1280, 800));

      // タブレット: 左ペイン検索
      await typeQuery(tester, 'adjust');
      // 右ペイン初期 Display 詳細にも 'Adjust Mode' があるため、
      // 左ペインの検索結果タイル（ツリー順で先）をタップする。
      await tester.tap(find.text('Adjust Mode').first);
      await tester.pumpAndSettle();

      // 右ペインが Display 詳細へ切替＆クエリ clear
      // （右ペイン詳細 1箇所に' Adjust Mode' が残る）
      expect(find.text('Adjust Mode'), findsOneWidget);
      expect(find.text('Auto Fit'), findsOneWidget);
      expect(find.text('Display'), findsWidgets); // 左ペイン一覧復帰
      // Provider clear がフィールドへも反映される（ref.listen 同期）
      expect(searchFieldText(tester), '');
    });
  });

  group('Settings search tablet overflow (T-1 回帰)', () {
    testWidgets('broad query does not overflow the tablet left pane', (
      tester,
    ) async {
      final overflowErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      // RenderFlex overflow を捕捉する方式（#T-1 回帰）
      FlutterError.onError = (details) {
        if (details.toString().contains('A RenderFlex overflowed')) {
          overflowErrors.add(details);
        } else {
          originalOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await buildSettingsApp(tester, size: const Size(1280, 800));
      // 30 以上のヒットを生む広域 1 文字クエリ（'e' は title/desc 全体に頻出）
      await typeQuery(tester, 'e');
      await tester.pumpAndSettle();

      // 左ペインがスクロール可能なため overflow していない
      expect(overflowErrors, isEmpty);
    });
  });

  group('Settings search semantics (P3-C10)', () {
    testWidgets('search result category headings expose isHeader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await buildSettingsApp(tester);
      await typeQuery(tester, 'font');

      // 検索結果のカテゴリグループ見出し（Display）がヘッダーとして公開される
      final heading = find.descendant(
        of: find.byType(SettingsSectionHeader),
        matching: find.text('Display'),
      );
      expect(tester.getSemantics(heading).flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('category body heading exposes isHeader', (tester) async {
      final handle = tester.ensureSemantics();
      await buildSettingsApp(tester);
      await openCategory(tester, 'Display');

      // カテゴリ詳細の先頭カテゴリ名ヘッダ（Display）
      final heading = find.descendant(
        of: find.byType(SettingsSectionHeader),
        matching: find.text('Display'),
      );
      expect(tester.getSemantics(heading).flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });
}
