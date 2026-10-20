import 'package:flutter/material.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/ansi_link_tap_harness.dart';

/// herdr OSC 8 ハイパーリンク（スクロールモード）の widget テスト。
///
/// [overlayScrollbackHyperlinks] / [HerdrScrollbackHyperlinkMemo] 自体の
/// 単体テストは herdr_scrollback_hyperlink_overlay_test.dart で検証済み
/// （スナップショット照合ガード・メモ化の契約）。ここでは次の 3 点を、
/// `AnsiTextView` へ `scrollbackLinkCache`/`currentScrollbackSnapshotIdentity`
/// を直接渡す widget テストで検証する:
/// - タップで確認ダイアログに cache 由来の URL が出る
/// - スクロールモードを抜けた後（mode != select）は重ねない
/// - スナップショットを差し替えたら（cache が追いつく前）重ねない
///
/// 選択モードのリンクタップはプローブ経路（#15・`AnsiLinkProbeRegistry`）
/// で解決される（`ansi_link_tap_modes_test.dart` の「選択モード」群と
/// 同じ経路。パーサ由来かどうかを区別しない）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bodyText = 'click here for more';

  ScrollbackLinkCache cacheWithLink({
    required Object identity,
    required int generation,
    String url = 'https://example.com/scrollback',
  }) {
    final cache = ScrollbackLinkCache();
    cache.resetIfNeeded(identity: identity, generation: generation);
    cache.applyWindowResult(
      generation: generation,
      offsetFromBottom: 0,
      linksByBodyLine: {
        0: [HerdrHyperlinkRange(startCol: 6, endCol: 9, url: url)],
      },
    );
    return cache;
  }

  testWidgets('スクロールモード: cache のリンクをタップ→確認モーダルに URL→開く→外部起動'
      '（別々に作られた同じ値の identity でも重なる）', (tester) async {
    // 本番の HerdrController.captureIdentity()（herdr_controller.dart）は
    // 呼び出しのたびに新しい record インスタンスを作る（内容が同じでも
    // identical は false）。cache 構築時と
    // currentScrollbackSnapshotIdentity で別々に作った同じ値の identity
    // でも重ね合わせが働くことを確認する。
    final sharedCacheRef = Object();
    ({Object cache, int epoch}) captureIdentity() =>
        (cache: sharedCacheRef, epoch: 1);

    final cacheIdentity = captureIdentity();
    final currentIdentity = captureIdentity();
    expect(identical(cacheIdentity, currentIdentity), isFalse);
    expect(cacheIdentity == currentIdentity, isTrue);

    final cache = cacheWithLink(identity: cacheIdentity, generation: 1);

    final harness = await pumpAnsiLinkTerminal(
      tester,
      text: bodyText,
      mode: TerminalMode.select,
      scrollbackLinkCache: cache,
      currentScrollbackSnapshotIdentity: (
        identity: currentIdentity,
        generation: 1,
      ),
    );

    await tapLinkText(tester, 'here');
    await tester.pumpAndSettle();

    expect(find.text('Open Link?'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(harness.launches, hasLength(1));
    expect(
      (harness.launches.single.arguments as Map)['url'],
      'https://example.com/scrollback',
    );
  });

  testWidgets('スクロールモードを抜けた後（mode=normal）は scrollbackLinkCache を重ねない', (
    tester,
  ) async {
    final idA = Object();
    // スクロールモード中に取得済みのキャッシュが、モードを抜けた後も
    // （破棄が完了する前に）まだ残っている状況を模す。
    final cache = cacheWithLink(identity: idA, generation: 1);

    final harness = await pumpAnsiLinkTerminal(
      tester,
      text: bodyText,
      mode: TerminalMode.normal,
      scrollbackLinkCache: cache,
      currentScrollbackSnapshotIdentity: (identity: idA, generation: 1),
    );

    // 通常モードはリンク外テキストのタップで外側 onTap が発火する
    // （ansi_link_tap_modes_test.dart と同じ既存挙動）。
    await tester.tap(find.textContaining(bodyText));
    await tester.pumpAndSettle();

    expect(find.text('Open Link?'), findsNothing);
    expect(harness.launches, isEmpty);
    expect(harness.tappedUrls, isEmpty);
    expect(harness.terminalTaps, 1);
  });

  testWidgets('スナップショットを差し替えたら（cache が追いつく前）重ねない', (tester) async {
    final idA = Object();
    final idB = Object();
    final cache = cacheWithLink(identity: idA, generation: 1);
    final harness = AnsiLinkTapHarness();
    mockUrlLauncher(tester, harness);

    Widget subject(({Object? identity, int generation})? currentIdentity) =>
        buildAnsiLinkSubject(
          harness,
          text: bodyText,
          mode: TerminalMode.select,
          scrollbackLinkCache: cache,
          currentScrollbackSnapshotIdentity: currentIdentity,
        );

    await tester.pumpWidget(subject((identity: idA, generation: 1)));
    await tester.pumpAndSettle();

    // 差し替え前は重ねられている（タップでモーダルが出る）ことを確認。
    await tapLinkText(tester, 'here');
    await tester.pumpAndSettle();
    expect(find.text('Open Link?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // スナップショットが差し替わった（新しい identity/generation へ
    // 進んだ）が、cache はまだ古い世代の結果しか持っていない
    // （HerdrScrollbackLinkReader が追いつく前）。
    await tester.pumpWidget(subject((identity: idB, generation: 2)));
    await tester.pumpAndSettle();

    // もう重ねられていないので、同じ位置をタップしてもモーダルは出ない。
    await tester.tap(find.textContaining(bodyText));
    await tester.pumpAndSettle();
    expect(find.text('Open Link?'), findsNothing);
    expect(harness.launches, isEmpty);
  });
}
