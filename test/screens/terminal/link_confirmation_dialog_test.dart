import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/link_confirmation_dialog.dart';

/// confirmExternalLink（OSC 8 リンク確認モーダル・Issue #61 / 🤝#3）の
/// widget テスト。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （実機確認で補う）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetUrl = 'https://example.com/very/long/path?q=1#frag';

  /// モーダルを pump するハーネス。[result] はコールバック完了後に書き換わる。
  Future<({Future<void> Function() trigger, bool Function() result})>
  pumpHarness(WidgetTester tester) async {
    var result = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmExternalLink(context, Uri.parse(targetUrl));
            },
            child: const Text('trigger'),
          ),
        ),
      ),
    );
    return (
      trigger: () => tester.tap(find.text('trigger')),
      result: () => result,
    );
  }

  testWidgets('URL 全文を SelectableText で表示する', (tester) async {
    final harness = await pumpHarness(tester);
    await harness.trigger();
    await tester.pumpAndSettle();

    expect(find.text('Open Link?'), findsOneWidget);
    // URL 全文表示（開く前の確認・コピー対象・フィッシング緩和）
    expect(find.text(targetUrl), findsOneWidget);
  });

  testWidgets('「開く」で true を返す', (tester) async {
    final harness = await pumpHarness(tester);
    await harness.trigger();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(harness.result(), isTrue);
  });

  testWidgets('「キャンセル」で false を返す', (tester) async {
    final harness = await pumpHarness(tester);
    await harness.trigger();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.result(), isFalse);
  });

  testWidgets('スキャン外タップによる dismiss も false 扱い', (tester) async {
    final harness = await pumpHarness(tester);
    await harness.trigger();
    await tester.pumpAndSettle();

    // ダイアログ外（画面左上端）をタップ → barrier dismiss
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(harness.result(), isFalse);
  });
}
