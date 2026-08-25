import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/settings/settings_screen.dart';

/// 設定画面をテスト用 surface で起動する。
///
/// [size] は論理サイズ（devicePixelRatio 1.0）。既定 390x844（スマホ一覧）。
/// タブレット（1280x800）・境界（599 / 600）テストは [size] を明示指定する。
/// [locale] / [platform] は対応テストで指定する。
/// プロバイダ override が必要なテスト（wheelSendVerifiedProvider 等）は
/// Riverpod 3.x が `Override` 型を公開 export しないため、本ヘルパー経由
/// ではなく ProviderScope を直接構築する（既存流儀・TEST-SETTINGS-UI-004 参照）。
Future<void> buildSettingsApp(
  WidgetTester tester, {
  TargetPlatform? platform,
  Locale? locale,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // CJK ModeトグルのiOS限定表示を検証するためプラットフォームを上書きできる
        theme: platform == null ? null : ThemeData(platform: platform),
        locale: locale,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// カテゴリ一覧から [title] のカテゴリをタップして詳細へ遷移する。
Future<void> openCategory(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// カテゴリ詳細のスクロール領域（`Key('settingsScrollArea')`）。
///
/// 検索フィールド（TextField/EditableText）が内部 Scrollable を持つため、
/// `find.byType(Scrollable).first` では対象が不定になる（DR-13）。
/// ListView のキーは P1-C3 で導入済み。
final Finder settingsScrollArea = find.byKey(const Key('settingsScrollArea'));

/// カテゴリ詳細内の Scrollable（キー付き ListView の内部）。
final Finder settingsScrollable = find.descendant(
  of: settingsScrollArea,
  matching: find.byType(Scrollable),
);

/// カテゴリ詳細内で [finder] までスクロールする。
///
/// 探索前にスクロール位置を先頭へ戻すことで、直前の `ensureVisible` による
/// 位置ずれ（探索対象が画面上方へ通り過ぎてレイジービルドから外れる）に
/// 依存しない検証にする。最後に `Scrollable.ensureVisible(alignment: 0.5)`
/// で画面内へ完全に収めてから返す（レイジーリストはビルドされただけで
/// 画面外のことがあるため）。
Future<void> scrollUntilFound(WidgetTester tester, Finder finder) async {
  final position = tester.state<ScrollableState>(settingsScrollable).position;
  if (position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(finder, 200, scrollable: settingsScrollable);
  await Scrollable.ensureVisible(
    finder.evaluate().single,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
}
