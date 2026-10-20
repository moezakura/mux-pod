/// [AnsiTextViewState.bodyLineTexts] / [TerminalViewportPort.bodyLineTexts]
/// （herdr OSC 8 ハイパーリンク・スクロールモードのリンク読取が使う
/// `bodyLinesFor` の実体）の widget テスト。
///
/// 「行の表示文字列」（書かれたセルの文字を連結し、全角文字の後半
/// セルは含まない）と同じ定義で、`herdr_hyperlink_reconciler.dart`
/// の `bodyLines[i].segments.map((s) => s.text).join()` と同じ式を使う。
/// [TerminalViewportPort] は `GlobalKey<AnsiTextViewState>` を介した中立
/// seam のため、`terminal_scroll_follow_controller_test.dart` と同じ構成で
/// 実 `AnsiTextView` を pump して検証する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/input/terminal_viewport_port.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart'
    show HerdrHyperlinkRange;
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';

import '../../../helpers/fake_settings_notifier.dart';
import '../helpers/ansi_link_tap_harness.dart' show tapLinkText;

class _FixedTerminalDisplayNotifier extends TerminalDisplayNotifier {
  @override
  TerminalDisplayState build() => const TerminalDisplayState(
    paneWidth: 80,
    paneHeight: 24,
    screenWidth: 400.0,
    screenHeight: 400.0,
    calculatedFontSize: 14.0,
  );
}

/// [text] で `AnsiTextView` を pump し、実 `GlobalKey<AnsiTextViewState>` を
/// 返す（`bodyLineTexts()` は build 済みの状態でのみ意味を持つ）。
///
/// [scrollbackLinkCache]/[currentScrollbackSnapshotIdentity]/[onLinkTap] は
/// オーバーレイが実際にリンクを有効化することを確認するテスト用（省略時は
/// 通常表示・リンク無し）。
Future<GlobalKey<AnsiTextViewState>> _pumpAnsiTextView(
  WidgetTester tester, {
  required String text,
  TerminalMode mode = TerminalMode.normal,
  ScrollbackLinkCache? scrollbackLinkCache,
  ({Object? identity, int generation})? currentScrollbackSnapshotIdentity,
  void Function(String url)? onLinkTap,
}) async {
  final key = GlobalKey<AnsiTextViewState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        terminalDisplayProvider.overrideWith(
          () => _FixedTerminalDisplayNotifier(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: Consumer(
              builder: (context, ref, _) => AnsiTextView(
                key: key,
                text: text,
                paneWidth: 80,
                paneHeight: 24,
                mode: mode,
                scrollbackLinkCache: scrollbackLinkCache,
                currentScrollbackSnapshotIdentity:
                    currentScrollbackSnapshotIdentity,
                onLinkTap: onLinkTap,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('全角文字の行はそのまま連結される（後半セルの空文字が入らない）', (tester) async {
    final key = await _pumpAnsiTextView(tester, text: 'あいう\n漢字テスト');

    final lines = key.currentState!.bodyLineTexts();

    expect(lines, hasLength(2));
    expect(lines[0], 'あいう');
    expect(lines[1], '漢字テスト');
  });

  testWidgets('ANSI エスケープ（色）を含む行はプレーンテキストになる', (tester) async {
    final key = await _pumpAnsiTextView(
      tester,
      text: '\x1B[31mred\x1B[0m text',
    );

    final lines = key.currentState!.bodyLineTexts();

    expect(lines, hasLength(1));
    expect(lines[0], 'red text');
    expect(lines[0], isNot(contains('\x1B')));
  });

  testWidgets('返す行数は表示本文の行数と一致する（overlay を適用する前の行）', (tester) async {
    final key = await _pumpAnsiTextView(tester, text: 'alpha\nbravo\ncharlie');

    final lines = key.currentState!.bodyLineTexts();

    expect(lines, ['alpha', 'bravo', 'charlie']);
    expect(lines, hasLength('alpha\nbravo\ncharlie'.split('\n').length));
  });

  testWidgets('オーバーレイが実際にリンクを有効化する入力でも、bodyLineTexts は'
      'URL等の装飾を含まないプレーンテキストのまま（'
      'overlay は本文のテキスト自体を変えないため、本文テキストの比較だけでは'
      'overlay適用前/後を見分けられない。ここでは tap を使い、overlay が'
      '実際に有効化された状態でも bodyLineTexts の値が変わらないことを示す）', (tester) async {
    final identity = Object();
    final cache = ScrollbackLinkCache()
      ..resetIfNeeded(identity: identity, generation: 1)
      ..applyWindowResult(
        generation: 1,
        offsetFromBottom: 0,
        linksByBodyLine: {
          0: const [
            HerdrHyperlinkRange(
              startCol: 6,
              endCol: 9,
              url: 'https://example.com/',
            ),
          ],
        },
      );
    final tappedUrls = <String>[];

    final key = await _pumpAnsiTextView(
      tester,
      text: 'click here now',
      mode: TerminalMode.select,
      scrollbackLinkCache: cache,
      currentScrollbackSnapshotIdentity: (identity: identity, generation: 1),
      onLinkTap: tappedUrls.add,
    );

    // オーバーレイが実際にリンクを有効化していること（表示が変わった証拠。
    // これが無いと、そもそもオーバーレイ経路が動いていない空振りテストに
    // なる）。
    await tapLinkText(tester, 'here');
    expect(tappedUrls, ['https://example.com/']);

    // bodyLineTexts は URL・装飾を含まないプレーンテキストのまま（
    // overlay は segment を分割するだけで本文のテキスト自体
    // は変えないため、この一致だけでは overlay 適用前/後を判別できない。
    // 上の tap 検証と合わせて「overlay が有効化された状態でも
    // bodyLineTexts の値は変わらない」ことを示す）。
    final lines = key.currentState!.bodyLineTexts();
    expect(lines, ['click here now']);
  });

  testWidgets(
    'TerminalViewportPort.bodyLineTexts は AnsiTextViewState.bodyLineTexts へ委譲する',
    (tester) async {
      final key = await _pumpAnsiTextView(tester, text: 'alpha\nbravo');
      final port = TerminalViewportPort(key);

      expect(port.bodyLineTexts(), ['alpha', 'bravo']);
    },
  );

  test('TerminalViewportPort.bodyLineTexts は AnsiTextView 組み立て前は null'
      '（visibleLineRange と同じ null 許容規約）', () {
    final key = GlobalKey<AnsiTextViewState>();
    final port = TerminalViewportPort(key);

    expect(port.bodyLineTexts(), isNull);
  });
}
