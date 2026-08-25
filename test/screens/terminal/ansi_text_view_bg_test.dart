import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import '../../helpers/fake_settings_notifier.dart';

/// C-001: 背景色付き行の行末までの背景描画・空行の背景描画を検証する。
///
/// テスト環境（Ahem フォント）では実機フォントの「行末スペースに背景が
/// 塗られない」挙動を再現できないため、ここでは背景レイヤー（ColoredBox）
/// の構造存在を検証する。実機での見た目は REPRO 手順 + ピクセル解析で
/// 検証する（bugfix レポート参照）。
class _FixedTerminalDisplayNotifier extends TerminalDisplayNotifier {
  @override
  TerminalDisplayState build() => const TerminalDisplayState(
    paneWidth: 80,
    paneHeight: 24,
    screenWidth: 400.0,
    screenHeight: 800.0,
    calculatedFontSize: 14.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ANSI 緑背景 (42) = standardColors[2]
  const greenBackground = Color(0xFF0DBC79);
  // ANSI 赤背景 (41) = standardColors[1]
  const redBackground = Color(0xFFCD3131);
  // ANSI 青背景 (44) = standardColors[4]
  const blueBackground = Color(0xFF2472C8);
  // デフォルト背景
  const defaultBackground = Color(0xFF1E1E1E);

  Widget buildSubject(String text) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        terminalDisplayProvider.overrideWith(
          () => _FixedTerminalDisplayNotifier(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AnsiTextView(text: text, paneWidth: 80, paneHeight: 24),
        ),
      ),
    );
  }

  int countColoredBoxes(WidgetTester tester, Color color) {
    return tester
        .widgetList<ColoredBox>(
          find.byWidgetPredicate((w) => w is ColoredBox && w.color == color),
        )
        .length;
  }

  /// RichText の InlineSpan からテキストを持つ TextSpan を再帰的に収集する。
  /// （opaque 化したセグメントの backgroundColor を検証するために使用）
  List<TextSpan> collectTextSpans(InlineSpan span) {
    if (span is! TextSpan) return const [];
    return [
      if (span.text != null) span,
      ...span.children?.expand(collectTextSpans) ?? const [],
    ];
  }

  /// ウィジェットツリー内の全 RichText からテキストを持つ TextSpan を収集する。
  List<TextSpan> collectAllTextSpans(WidgetTester tester) {
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((rt) => collectTextSpans(rt.text))
        .toList();
  }

  testWidgets('背景色付き行に背景レイヤーが描画される', (tester) async {
    // W1: 末尾リセットが無い（endStyle=green）ため行レイヤーが維持される
    await tester.pumpWidget(buildSubject('\x1b[42mgreen text'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, greenBackground), greaterThanOrEqualTo(1));
  });

  testWidgets('SGRのみの空行にも背景レイヤーが描画される', (tester) async {
    await tester.pumpWidget(buildSubject('before\n\x1b[42m\nafter'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, greenBackground), greaterThanOrEqualTo(1));
  });

  testWidgets('デフォルト背景の行には追加の背景レイヤーが無い', (tester) async {
    await tester.pumpWidget(buildSubject('plain line'));
    await tester.pumpAndSettle();

    // デフォルト背景色の ColoredBox（Container 由来）のみで、
    // 行単位の追加背景レイヤーが存在しないこと
    final rowLayers = tester
        .widgetList<ColoredBox>(
          find.byWidgetPredicate(
            (w) =>
                w is ColoredBox &&
                w.color == defaultBackground &&
                w.child is SizedBox,
          ),
        )
        .length;
    expect(rowLayers, 0);
  });

  testWidgets('背景レイヤーはIgnorePointerで包まれタップを奪わない', (tester) async {
    var tapped = false;
    // W8: 末尾リセットが無い（endStyle=green）ため行レイヤーが維持される
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => FakeSettingsNotifier()),
          terminalDisplayProvider.overrideWith(
            () => _FixedTerminalDisplayNotifier(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AnsiTextView(
              text: '\x1b[42mgreen',
              paneWidth: 80,
              paneHeight: 24,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 背景 ColoredBox の親チェーンに IgnorePointer が存在すること
    final backgroundFinder = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == greenBackground,
    );
    expect(backgroundFinder, findsWidgets);
    // 背景 ColoredBox の祖先に IgnorePointer が存在すること
    final coloredBoxElement = tester.element(backgroundFinder.first);
    var hasIgnorePointerAncestor = false;
    coloredBoxElement.visitAncestorElements((ancestor) {
      if (ancestor.widget is IgnorePointer) {
        hasIgnorePointerAncestor = true;
        return false;
      }
      return true;
    });
    expect(hasIgnorePointerAncestor, isTrue);

    // タップが onTap に届くこと（背景レイヤーがヒットテストを妨げない）
    await tester.tap(find.byType(AnsiTextView));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('S4型: 末尾リセット行には背景レイヤーが無い', (tester) async {
    // W2: 単色＋末尾リセット → endStyle=default。余白は default（ユーザー承認仕様）
    await tester.pumpWidget(buildSubject('\x1b[42mgreen text\x1b[0m'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, greenBackground), 0);
  });

  testWidgets('S3型: 複数色＋末尾リセットはレイヤー無し・セル単位は span が担当', (tester) async {
    // W3: レイヤー無し、RED/GREEN は各セグメント span の backgroundColor で描画
    await tester.pumpWidget(
      buildSubject('\x1b[41mRED\x1b[42mGREEN\x1b[49m'),
    );
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, redBackground), 0);
    expect(countColoredBoxes(tester, greenBackground), 0);

    final spans = collectAllTextSpans(tester);
    final red = spans.firstWhere((s) => s.text == 'RED');
    expect(red.style!.backgroundColor, redBackground);
    final green = spans.firstWhere((s) => s.text == 'GREEN');
    expect(green.style!.backgroundColor, greenBackground);
  });

  testWidgets('S1型: 途中リセット＋先頭デフォルト区間には背景レイヤーが無い', (tester) async {
    // W4: PREFIX \x1b[44mBLUE\x1b[49m → endStyle=default → 余白は default
    await tester.pumpWidget(buildSubject('PREFIX \x1b[44mBLUE\x1b[49m'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, blueBackground), 0);
  });

  testWidgets('HYP-4型: 途中デフォルト区間は opaque で default に塗られる', (tester) async {
    // W5: plain \x1b[44m tail → endStyle=blue のレイヤー有り。"plain " span が opaque default
    await tester.pumpWidget(buildSubject('plain \x1b[44m tail'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, blueBackground), greaterThanOrEqualTo(1));

    final spans = collectAllTextSpans(tester);
    final plain = spans.firstWhere((s) => s.text == 'plain ');
    expect(plain.style!.backgroundColor, defaultBackground);
  });

  testWidgets('R10型: 末尾色SGRのみの行も途中 span は opaque で default', (tester) async {
    // W6: 'text \x1b[44m' → endStyle=blue のレイヤー有り。"text " span は opaque default
    await tester.pumpWidget(buildSubject('text \x1b[44m'));
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, blueBackground), greaterThanOrEqualTo(1));

    final spans = collectAllTextSpans(tester);
    final text = spans.firstWhere((s) => s.text == 'text ');
    expect(text.style!.backgroundColor, defaultBackground);
  });

  testWidgets('EV-LOG-006型: 実色スペース行には背景レイヤーが残る', (tester) async {
    // W7: 実スペース100個の行（PR#98 の行末色埋め機能維持の回帰防止）
    await tester.pumpWidget(
      buildSubject('\x1b[42mtext${' ' * 100}\x1b[0m'),
    );
    await tester.pumpAndSettle();

    expect(countColoredBoxes(tester, greenBackground), greaterThanOrEqualTo(1));
  });
}
