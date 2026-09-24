import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';

import 'helpers/ansi_link_tap_harness.dart';

/// OSC 8 リンクのモード別タップ・アリーナ widget テスト
/// （Issue #61・Phase 5 #16a・🤝#2/#3）。
///
/// 検証対象フロー: タップ → recognizer/probe → onLinkTap → shell コーディネータ
/// → 確認モーダル/外部起動（url_launcher MethodChannel モックで検証）。
/// blink on/off 両相（H2）・同一 URL 2 か所共有（M4）・行跨ぎ後続行タップ（🤝#2）
/// を含む。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （MethodChannel モック・実機確認で補う）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const linkText =
      '\x1b]8;;https://example.com/page\x07visit example\x1b]8;;\x07 plain tail';

  group('通常モード（recognizer 直結）', () {
    testWidgets('リンクタップ → 確認モーダル → 開く → 外部起動', (tester) async {
      final harness = await pumpAnsiLinkTerminal(tester, text: linkText);

      await tapLinkText(tester, 'visit example');
      await tester.pumpAndSettle();

      // アリーナ: リンク recognizer が勝利し、外側 GestureDetector の onTap は
      // 発火しない（テキスト位置解決を持たないのは既存設計どおり）。
      expect(harness.terminalTaps, 0);
      // 既定（openLinksDirectly = false）は確認モーダルを表示する
      expect(find.text('Open Link?'), findsOneWidget);
      expect(harness.canLaunches, isEmpty);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(harness.canLaunches, hasLength(1));
      final launches = harness.launches.toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/page',
      );
    });

    testWidgets('リンク外テキストのタップは従来どおり（onTap 発火・起動しない）', (tester) async {
      final harness = await pumpAnsiLinkTerminal(tester, text: linkText);

      await tapLinkText(tester, 'plain tail');
      await tester.pump();

      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
      expect(harness.terminalTaps, 1);
    });

    testWidgets('ホールド+スワイプがリンク行でも発火する（アリーナ競合回帰）', (tester) async {
      final harness = await pumpAnsiLinkTerminal(tester, text: linkText);

      final position = linkSpanGlobalPosition(tester, 'visit example');
      final gesture = await tester.startGesture(position);
      // long press 認識（500ms deadline）を確実に消化する
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      await gesture.up();
      // ホールド解除・スワイプ確定のタイマーを消化する（Timer pending 防止）
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // ホールド+スワイプ（Left）が検出され、リンク recognizer は発火しない
      expect(harness.arrowSwipes, contains('Left'));
      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
    });
  });

  group('scrollSend モード', () {
    testWidgets('リンクタップ → 確認モーダル（キャンセルで起動しない）', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: linkText,
        mode: TerminalMode.scrollSend,
      );

      await tapLinkText(tester, 'visit example');
      await tester.pumpAndSettle();

      // scrollSend は外側 onTap を配置しない既存設計。リンク上タップは
      // TextSpan recognizer が arena で勝ってモーダルを開く。
      expect(harness.terminalTaps, 0);
      expect(find.text('Open Link?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.launches, isEmpty);
    });

    testWidgets('リンク上ドラッグ → 送信ティック（タップ不発火・両立実証）', (tester) async {
      // コンテンツ不足（下端アライン padding 状態）では hit しない位置が
      // 出るため、ビューポートを満たす複数行の先頭にリンク行を置く。
      final text =
          '\x1b]8;;https://example.com/page\x07visit example\x1b]8;;\x07\n'
          '${List.generate(40, (i) => "filler-$i").join("\n")}';
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: text,
        mode: TerminalMode.scrollSend,
      );

      // 1 ティック = 行高 × 1.5 = (14 × 1.2) × 1.5 = 25.2px
      const tickPx = 14.0 * 1.2 * 1.5;
      final position = linkSpanGlobalPosition(tester, 'visit example');
      final gesture = await tester.startGesture(position);
      await gesture.moveBy(Offset(0, -tickPx));
      await tester.pump();
      await gesture.moveBy(Offset(0, -tickPx));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // ドラッグ開始は recognizer が棄却してドラッグが勝つ（B5 実測の既存設計）。
      // recognizer 参加下では 1 move 目が DragStart に吸収されるため、
      // 2 move 目の 1 ティックが送信される。
      expect(harness.ticks, [1]);
      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
    });
  });

  group('選択モード（Listener プローブ・🤝#3）', () {
    testWidgets('リンクタップ（プローブ経路）→ 確認モーダル → 開く → 外部起動', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: linkText,
        mode: TerminalMode.select,
      );

      await tapLinkText(tester, 'visit example');
      await tester.pumpAndSettle();

      // SelectionArea に吸われたタップをプローブが検出し、行登録の解決経由で
      // コーディネータへ渡す（recognizer は選択モードで生成しない）
      expect(find.text('Open Link?'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        (harness.launches.single.arguments as Map)['url'],
        'https://example.com/page',
      );
    });

    testWidgets('長押し（選択開始）はプローブ非発火＝従来どおりの選択操作', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: linkText,
        mode: TerminalMode.select,
      );

      await tester.longPress(find.textContaining('visit example'));
      await tester.pumpAndSettle();

      // プローブは kLongPressTimeout 未満の down→up のみタップと判定する
      expect(find.text('Open Link?'), findsNothing);
      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
    });

    testWidgets('ドラッグ選択はプローブ非発火', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: linkText,
        mode: TerminalMode.select,
      );

      final position = linkSpanGlobalPosition(tester, 'visit example');
      final gesture = await tester.startGesture(position);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(find.text('Open Link?'), findsNothing);
      expect(harness.tappedUrls, isEmpty);
      expect(harness.launches, isEmpty);
    });

    testWidgets('水平スクロール下（横オフセット > 0）のプローブタップでも正しく url 解決する', (tester) async {
      // ハーネスは terminalWidth = 1120px > ビューポート 400px で
      // needsHorizontalScroll 有効（SizedBox 固定幅 + 水平 SingleChildScrollView）。
      // filler の後にリンクを置き、左へスクロールして行左端がビューポート外
      // （横スクロールオフセット > 0）の状態でプローブタップする —
      // paragraph.globalToLocal が水平オフセット下でも正しく解決することを
      // 回帰で守る（Risk Mitigation の固定要求）。
      const hscrollUrl = 'https://example.com/hscroll';
      final text =
          '${'x' * 24}\x1b]8;;$hscrollUrl\x07scrolled link\x1b]8;;\x07';
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: text,
        mode: TerminalMode.select,
      );

      final rp = renderParagraphOfRow(
        tester,
        find.textContaining('scrolled link'),
      );
      // スクロール前は横オフセット 0（行左端 = ビューポート左端）
      expect(rp.localToGlobal(Offset.zero).dx, moreOrLessEquals(0));

      // 横に 80px スクロール → 行左端がビューポート外へ
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();

      expect(
        rp.localToGlobal(Offset.zero).dx,
        lessThan(0),
        reason: '行左端がビューポート外 = 横スクロールオフセット > 0',
      );

      // 横オフセット下でもプローブ（paragraph.globalToLocal → getPositionForOffset
      // → セグメント解決）が正しい url を返し、確認モーダル→外部起動に至る
      await tapLinkText(tester, 'scrolled link');
      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect((harness.launches.single.arguments as Map)['url'], hscrollUrl);
    });
  });

  group('blink 両相のタップ（H2・マージゲート）', () {
    testWidgets('キャレット行リンクは点滅 on 相・off 相の両方で発火する', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text:
            'row0\n\x1b]8;;https://example.com/blink\x07link here\x1b]8;;\x07\nrow2',
        cursorX: 0,
        cursorY: 1, // 行1（リンク行）をキャレット行にする
      );

      // on 相（WithCaret 経路）で発火
      await ensureCaretPhase(tester, on: true);
      await tapLinkText(tester, 'link here');
      await tester.pumpAndSettle();
      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.launches, isEmpty);

      // off 相（早期 return → lineToTextSpan 委譲経路）でも発火
      await ensureCaretPhase(tester, on: false);
      await tapLinkText(tester, 'link here');
      await tester.pumpAndSettle();
      expect(find.text('Open Link?'), findsOneWidget);
    });
  });

  group('同一 URL の recognizer 共有（M4）', () {
    testWidgets('同一 URL 2 か所は同一 recognizer インスタンスで両位置発火する', (tester) async {
      const dupUrl = 'https://example.com/dup';
      final text =
          '\x1b]8;;$dupUrl\x07first link\x1b]8;;\x07 mid \x1b]8;;$dupUrl\x07second link\x1b]8;;\x07';
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: text,
        openDirectly: true, // モーダルを挟まず 2 連続タップを検証する
      );

      final rp = renderParagraphOfRow(
        tester,
        find.textContaining('first link'),
      );
      final recognizers = flattenTextSpans(rp.text)
          .map((entry) => entry.$1.recognizer)
          .whereType<TapGestureRecognizer>()
          .toList();
      expect(recognizers, hasLength(2));
      // URL をキーに同一インスタンスを共有する（M4 契約）
      expect(identical(recognizers[0], recognizers[1]), isTrue);

      // 両位置のタップで両方発火する
      await tapLinkText(tester, 'first link');
      await tester.pumpAndSettle();
      await tapLinkText(tester, 'second link');
      await tester.pumpAndSettle();

      final launches = harness.launches.toList();
      expect(launches, hasLength(2));
      expect(
        launches.every((call) => (call.arguments as Map)['url'] == dupUrl),
        isTrue,
      );
    });
  });

  group('行跨ぎリンク（🤝#2・行間 URL carry）', () {
    testWidgets('後続行のリンク区間タップで起動する', (tester) async {
      const carryUrl = 'https://example.com/carry';
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text:
            '\x1b]8;;$carryUrl\x07first-line\nsecond-line-target\x1b]8;;\x07\nthird-line',
      );

      // 開始行（未閉鎖）の carry により後続行も装飾付きリンク区間になる。
      // 後続行のタップで起動する（🤝#2）。
      await tapLinkText(tester, 'second-line-target');
      await tester.pumpAndSettle();

      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect((harness.launches.single.arguments as Map)['url'], carryUrl);
    });
  });
}
