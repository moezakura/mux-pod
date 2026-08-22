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

  testWidgets('背景色付き行に背景レイヤーが描画される', (tester) async {
    await tester.pumpWidget(buildSubject('\x1b[42mgreen text\x1b[0m'));
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
              text: '\x1b[42mgreen\x1b[0m',
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
}
