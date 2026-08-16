import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';
import 'package:flutter_muxpod/services/terminal/terminal_font_styles.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

import '../../helpers/fake_settings_notifier.dart';

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

  testWidgets('renders plain text without crashing', (tester) async {
    await tester.pumpWidget(buildSubject('hello world'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsOneWidget);
  });

  testWidgets('renders ANSI colored text', (tester) async {
    await tester.pumpWidget(buildSubject('\x1B[31mred\x1B[0m text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('red'), findsOneWidget);
  });

  testWidgets('long text wraps to multiple text widgets', (tester) async {
    final text = 'line1\nline2\nline3';
    await tester.pumpWidget(buildSubject(text));
    await tester.pumpAndSettle();
    expect(find.textContaining('line1'), findsOneWidget);
    expect(find.textContaining('line2'), findsOneWidget);
    expect(find.textContaining('line3'), findsOneWidget);
  });

  testWidgets('tapping terminal calls onTap', (tester) async {
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
              text: 'hello',
              paneWidth: 80,
              paneHeight: 24,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AnsiTextView));
    expect(tapped, isTrue);
  });

  testWidgets('line height uses FontCalculator.lineHeightRatio (1.2)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              settings: const AppSettings(
                keepScreenOn: false,
                adjustMode: 'manual',
                fontSize: 14.0,
              ),
            ),
          ),
          terminalDisplayProvider.overrideWith(
            () => _FixedTerminalDisplayNotifier(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AnsiTextView(
              text: 'a\nb\nc\nd\ne',
              paneWidth: 80,
              paneHeight: 24,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.itemExtent, closeTo(14.0 * 1.2, 0.001));
  });

  testWidgets(
    'content shorter than viewport aligns to bottom via top padding',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                settings: const AppSettings(
                  keepScreenOn: false,
                  adjustMode: 'manual',
                  fontSize: 14.0,
                ),
              ),
            ),
            terminalDisplayProvider.overrideWith(
              () => _FixedTerminalDisplayNotifier(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400.0,
                child: AnsiTextView(
                  text: 'a\nb\nc\nd\ne',
                  paneWidth: 80,
                  paneHeight: 24,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 5行 × 16.8px = 84px を 400px のビューポートで下端アラインする場合、
      // 上端パディングは 400 - 84 = 316px になる。
      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = (listView.padding as EdgeInsets).top;
      expect(padding, closeTo(400.0 - 5 * 14.0 * 1.2, 0.001));
    },
  );

  testWidgets('content fills viewport uses no top padding', (tester) async {
    final text = List.generate(40, (i) => 'line-$i').join('\n');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              settings: const AppSettings(
                keepScreenOn: false,
                adjustMode: 'manual',
                fontSize: 14.0,
              ),
            ),
          ),
          terminalDisplayProvider.overrideWith(
            () => _FixedTerminalDisplayNotifier(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400.0,
              child: AnsiTextView(text: text, paneWidth: 80, paneHeight: 24),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 40行 × 16.8px = 672px > 400px なのでパディングなし（従来動作）。
    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = (listView.padding as EdgeInsets).top;
    expect(padding, 0.0);
  });

  // ===== Issue #70: キャレットのテキストレイアウト直接挿入（合成廃止） =====

  Widget buildCaretSubject(
    String text, {
    int cursorX = 0,
    int cursorY = 0,
    int paneHeight = 3,
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          () => FakeSettingsNotifier(
            settings: const AppSettings(
              keepScreenOn: false,
              adjustMode: 'manual',
              fontSize: 14.0,
            ),
          ),
        ),
        terminalDisplayProvider.overrideWith(
          () => _FixedTerminalDisplayNotifier(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: AnsiTextView(
              text: text,
              paneWidth: 20,
              paneHeight: paneHeight,
              cursorX: cursorX,
              cursorY: cursorY,
            ),
          ),
        ),
      ),
    );
  }

  final caretFinder = find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == DesignColors.primary,
  );

  testWidgets('caret is rendered inline inside the RichText (not composited)', (tester) async {
    await tester.pumpWidget(
      buildCaretSubject('abc\ndef\nghi', cursorX: 2, cursorY: 1),
    );
    await tester.pumpAndSettle();

    expect(caretFinder, findsOneWidget);
    // 合成（Stack+Positioned）ではなく RichText の子として存在する
    expect(
      find.ancestor(of: caretFinder, matching: find.byType(RichText)),
      findsOneWidget,
    );
    expect(find.byType(Positioned), findsNothing);
  });

  testWidgets('caret sits on the cursor row and within the text extent', (tester) async {
    // 1行目の2文字目の直後にキャレット（行スパンが xx + caret + def に分割される）
    await tester.pumpWidget(
      buildCaretSubject('xxdef\nabcdefgh\nzz', cursorX: 2, cursorY: 0),
    );
    await tester.pumpAndSettle();

    final caretRect = tester.getRect(caretFinder);
    final below = tester.getRect(find.textContaining('abcdefgh'));
    const fontSize = 14.0;
    final lineHeight = FontCalculator.lineHeightRatio * fontSize;

    // 縦: キャレットの中心は1行目（下の行から1行分上）にいる＝行がズレていない
    expect(caretRect.center.dy, closeTo(below.center.dy - lineHeight, 2.0));
    // 横: アプリと同じ文字幅測定で2文字分進んだ位置（テキスト描画位置と一致）
    final charWidth = FontCalculator.measureCharWidth('JetBrains Mono', 14.0);
    expect(caretRect.left, closeTo(below.left + charWidth * 2, 1.0));
  });

  testWidgets('caret is a thin vertical bar of fontSize height', (tester) async {
    await tester.pumpWidget(
      buildCaretSubject('abc\ndef\nghi', cursorX: 2, cursorY: 1),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(caretFinder);
    expect(rect.width, 2.0);
    // FakeSettingsNotifier の既定 fontSize は14
    expect(rect.height, 14.0);
  });

  testWidgets('caret blinks off after 500ms and back on', (tester) async {
    await tester.pumpWidget(
      buildCaretSubject('abc\ndef\nghi', cursorX: 2, cursorY: 1),
    );
    await tester.pumpAndSettle();
    expect(caretFinder, findsOneWidget);

    // 時計を正確に進める（pumpAndSettle は時刻を進めるので使わない）
    await tester.pump(const Duration(milliseconds: 600));
    expect(caretFinder, findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(caretFinder, findsOneWidget);
  });

  testWidgets('caret on empty line renders at line start', (tester) async {
    await tester.pumpWidget(
      buildCaretSubject('abc\n\nghi', cursorX: 0, cursorY: 1),
    );
    await tester.pumpAndSettle();

    expect(caretFinder, findsOneWidget);
    // 空行の行頭: 高さ方向は2行目の位置
    final caretRect = tester.getRect(caretFinder);
    final firstRow = tester.getRect(find.textContaining('abc'));
    final lineHeight = FontCalculator.lineHeightRatio * 14.0;
    expect(caretRect.center.dy, closeTo(firstRow.center.dy + lineHeight, 3.0));
    // 行頭: 1行目のテキスト左端と同じ位置
    expect(caretRect.left, closeTo(firstRow.left, 2.0));
  });

  testWidgets('caret beyond line end is padded to the cursor column', (tester) async {
    // 空行で cursorX=3: 3セル分のパディングの後にキャレット
    await tester.pumpWidget(
      buildCaretSubject('abc\n\nghi', cursorX: 3, cursorY: 1),
    );
    await tester.pumpAndSettle();

    expect(caretFinder, findsOneWidget);
  });

  testWidgets('caret lands after a full-width character (column boundary)', (tester) async {
    // 「あ」は2カラム幅: cursorX=2 は「あ」の直後の文字境界
    await tester.pumpWidget(
      buildCaretSubject('あb\nxx\nzz', cursorX: 2, cursorY: 0),
    );
    await tester.pumpAndSettle();

    final caretRect = tester.getRect(caretFinder);
    final below = tester.getRect(find.textContaining('xx'));
    // 全角1文字 = 半角2文字分の幅の位置にキャレットがある
    // （実際のフォールバックフォントの描画幅に追随するのが直接挿入方式の 本質）
    final painter = TextPainter(
      text: TextSpan(
        text: 'あ',
        style: TerminalFontStyles.getTextStyle('JetBrains Mono', fontSize: 14.0),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    expect(caretRect.left, closeTo(below.left + painter.width, 1.0));
  });
}
