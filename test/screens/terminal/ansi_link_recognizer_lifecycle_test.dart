import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import 'helpers/ansi_link_tap_harness.dart';

/// OSC 8 リンクのタップ認識子ライフサイクル・scheme ガード widget テスト
/// （Issue #61・Phase 5 #16b）。
///
/// 検証対象: recognizer 生成時の scheme フィルタ（C1 正規化受理・非対応
/// scheme 不発火）・行入れ替わり時の破棄・点滅中の蓄積回帰（critic R1）。
/// recognizer の生成者/破棄者は行ウィジェット State（D5-A 契約）であり、
/// テストはその観測可能な挙動を固定する。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （MethodChannel モックで再現されない・実機確認で補う）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scheme フィルタ（recognizer 生成時・C1）', () {
    testWidgets('HTTPS: 大文字表記は正規化により受理され発火する', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: '\x1b]8;;HTTPS://example.com/up\x07tap me\x1b]8;;\x07',
      );

      // Uri.tryParse の scheme 小文字正規化により https として受理され
      // recognizer が生成される（fail-closed 大文字拒否は C1 で棄却済み）
      expect(collectRecognizers(tester), hasLength(1));

      await tapLinkText(tester, 'tap me');
      await tester.pump();

      expect(harness.tappedUrls, ['HTTPS://example.com/up']);
    });

    testWidgets('非対応 scheme は recognizer 生成なし・装飾付きタップ不可', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text:
            '\x1b]8;;javascript:alert(1)\x07javascript part\x1b]8;;\x07\n'
            '\x1b]8;;mailto:a@b.c\x07mailto part\x1b]8;;\x07\n'
            '\x1b]8;;file:/etc/passwd\x07file part\x1b]8;;\x07\n'
            '\x1b]8;;example.com/relative\x07relative part\x1b]8;;\x07',
      );

      // 非 https/http は recognizer を生成しない（装飾付き・タップ不可＝D8 仕様）
      expect(collectRecognizers(tester), isEmpty);

      // 装飾（リンク下線）は付く: OSC 8 区間であることを視覚的に示す
      final rp = renderParagraphOfRow(
        tester,
        find.textContaining('javascript part'),
      );
      final linkSpan = flattenTextSpans(
        rp.text,
      ).firstWhere((entry) => (entry.$1.text ?? '').contains('javascript'));
      expect(
        linkSpan.$1.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
      );

      // タップしても起動導線（onLinkTap）に届かない
      await tapLinkText(tester, 'javascript part');
      await tapLinkText(tester, 'mailto part');
      await tapLinkText(tester, 'file part');
      await tapLinkText(tester, 'relative part');
      await tester.pump();

      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
    });

    testWidgets('選択モードのプローブ経路でも非対応 scheme はコーディネータで無視される', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: '\x1b]8;;file:/etc/passwd\x07probe me\x1b]8;;\x07',
        mode: TerminalMode.select,
      );

      await tapLinkText(tester, 'probe me');
      await tester.pump();

      // プローブは区間 url を解決するが、scheme ガード（二重防御）で
      // モーダル・起動のいずれも行わない
      expect(find.text('Open Link?'), findsNothing);
      expect(harness.launches, isEmpty);
    });
  });

  group('recognizer ライフサイクル（D5-A 契約）', () {
    testWidgets('行入れ替わりで旧 recognizer は例外なく破棄され新行が発火する', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: '\x1b]8;;https://example.com/first\x07first link\x1b]8;;\x07',
      );
      await tapLinkText(tester, 'first link');
      // 確認モーダルが開くため、次のタップが barrier に吸われる前に閉じる
      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.tappedUrls, ['https://example.com/first']);

      // 同一ウィジェット位置で別行に差し替え（didUpdateWidget 経路・
      // ListView 仮想化の行入れ替わり相当）
      await tester.pumpWidget(
        buildAnsiLinkSubject(
          harness,
          text: '\x1b]8;;https://example.com/second\x07second link\x1b]8;;\x07',
        ),
      );
      await tester.pumpAndSettle();

      // 旧 recognizer の dispose 漏れ・dispose 済み recognizer の使用は
      // フレームワーク assert として検出される（例外なしを確認）
      expect(tester.takeException(), isNull);

      await tapLinkText(tester, 'second link');
      await tester.pump();
      expect(harness.tappedUrls, [
        'https://example.com/first',
        'https://example.com/second',
      ]);
    });

    testWidgets('点滅（500ms × 数回）後も recognizer 数は増えない（蓄積回帰）', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text:
            'row0\n\x1b]8;;https://example.com/blink\x07link here\x1b]8;;\x07\nrow2',
        cursorX: 0,
        cursorY: 1, // リンク行をキャレット行にして点滅再構築を毎 500ms 走らせる
      );

      final before = collectRecognizers(tester);
      expect(before, hasLength(1));

      // 500ms 点滅 × 4 回（on/off 両相の span 再構築を含む）
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 600));
      }

      final after = collectRecognizers(tester);
      expect(after, hasLength(before.length));
      // identical 判定で State が使い回すため蓄積しない（critic R1 回答）
      expect(identical(before.single, after.single), isTrue);
      expect(harness.launches, isEmpty);
    });

    testWidgets('モード変化（normal → select）で recognizer は破棄される', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: '\x1b]8;;https://example.com/page\x07visit example\x1b]8;;\x07',
      );
      expect(collectRecognizers(tester), hasLength(1));

      // 選択モードへ切り替え: recognizer は選択モードで生成しないため全破棄
      await tester.pumpWidget(
        buildAnsiLinkSubject(
          harness,
          text: '\x1b]8;;https://example.com/page\x07visit example\x1b]8;;\x07',
          mode: TerminalMode.select,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(collectRecognizers(tester), isEmpty);
    });
  });
}
