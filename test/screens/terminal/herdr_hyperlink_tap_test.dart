import 'package:flutter/material.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/ansi_link_tap_harness.dart';

/// herdr OSC 8 ハイパーリンク（通常表示）の widget テスト。
///
/// パーサ由来（`\x1b]8;;`）ではなく [PaneHyperlinks] 経由で重ね合わされた
/// リンクが、既存の単一経路（recognizer → onLinkTap → shell コーディネータ →
/// 確認モーダル → url_launcher）をそのまま通ることを検証する。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （MethodChannel モックで再現されない・実機確認で補う）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bodyText = 'click here for more';

  PaneHyperlinks buildHyperlinks({
    required String url,
    int startCol = 6,
    int endCol = 9,
  }) => PaneHyperlinks(
    frameWidth: 80,
    frameHeight: 1,
    links: [
      PaneHyperlink(
        url: url,
        ranges: [
          PaneHyperlinkRange(row: 0, startCol: startCol, endCol: endCol),
        ],
      ),
    ],
    rowFingerprints: {0: HerdrRowFingerprint.rowFingerprint(bodyText)!},
  );

  group('通常モード（herdrHyperlinks 経由）', () {
    testWidgets('リンクタップ → 確認モーダルに herdr 由来 URL → 開く → 外部起動', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: bodyText,
        herdrHyperlinks: buildHyperlinks(url: 'https://example.com/herdr'),
      );

      await tapLinkText(tester, 'here');
      await tester.pumpAndSettle();

      expect(harness.terminalTaps, 0);
      expect(find.text('Open Link?'), findsOneWidget);
      expect(harness.canLaunches, isEmpty);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(harness.canLaunches, hasLength(1));
      final launches = harness.launches.toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/herdr',
      );
    });

    testWidgets('リンクだけ変わった herdrHyperlinks で再構築すると新しい URL が使われる', (
      tester,
    ) async {
      final harness = AnsiLinkTapHarness();
      mockUrlLauncher(tester, harness);

      Widget subject(String url) => buildAnsiLinkSubject(
        harness,
        text: bodyText,
        herdrHyperlinks: buildHyperlinks(url: url),
      );

      await tester.pumpWidget(subject('https://example.com/first'));
      await tester.pumpAndSettle();

      // 本文（テキスト）は不変のまま herdrHyperlinks の URL だけが変わる poll
      // を模す（リンクだけ変わった poll）。
      await tester.pumpWidget(subject('https://example.com/second'));
      await tester.pumpAndSettle();

      await tapLinkText(tester, 'here');
      await tester.pumpAndSettle();

      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final launches = harness.launches.toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/second',
      );
    });
  });

  group('選択モード（select・スクロールモード）', () {
    testWidgets('herdrHyperlinks が非 null でも通常表示の重ね合わせは行わない', (tester) async {
      final harness = await pumpAnsiLinkTerminal(
        tester,
        text: bodyText,
        mode: TerminalMode.select,
        herdrHyperlinks: buildHyperlinks(url: 'https://example.com/herdr'),
      );

      // select モードはテキスト選択（SelectionArea）に切り替わるため、通常
      // モードの recognizer タップ経路自体を通らない。ここでは「herdr の
      // リンクが重ね合わされて確認モーダルが出ない」ことを、モーダル非表示
      // で確認する（select モードは外側 onTap も配置しない既存設計）。
      await tester.tap(find.textContaining('click here for more'));
      await tester.pumpAndSettle();

      expect(find.text('Open Link?'), findsNothing);
      expect(harness.launches, isEmpty);
      expect(harness.tappedUrls, isEmpty);
    });
  });

  group('既存の OSC 8（パーサ由来）との共存', () {
    testWidgets('herdrHyperlinks が null なら従来の OSC 8 リンクのみ表示される（既存挙動）', (
      tester,
    ) async {
      const linkText =
          '\x1b]8;;https://example.com/parser\x07visit example\x1b]8;;\x07';
      final harness = await pumpAnsiLinkTerminal(tester, text: linkText);

      await tapLinkText(tester, 'visit example');
      await tester.pumpAndSettle();

      expect(find.text('Open Link?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final launches = harness.launches.toList();
      expect(launches, hasLength(1));
      expect(
        (launches.single.arguments as Map)['url'],
        'https://example.com/parser',
      );
    });
  });
}
