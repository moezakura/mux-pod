/// OSC 8 リンクタップの widget テスト共通ハーネス（Issue #61・Phase 5 #16a/#16b）。
///
/// タップ → recognizer/probe → onLinkTap → shell コーディネータ →
/// モーダル/外部起動のフローを [pumpAnsiLinkTerminal] で一括結線し、
/// url_launcher MethodChannel モックで起動を観測する
/// （markdown_preview_link_guard_test.dart 手法）。
///
/// OS 側制約（AndroidManifest queries・ブラウザ有無）は検証対象外
/// （MethodChannel モックで再現されない・実機確認で補う）。
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_view_shell.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

import '../../../helpers/fake_settings_notifier.dart';

const MethodChannel urlLauncherChannel = MethodChannel(
  'plugins.flutter.io/url_launcher',
);

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

/// ハーネスの観測点（spy）。
class AnsiLinkTapHarness {
  /// url_launcher MethodChannel 呼び出し（canLaunch / launch）。
  final List<MethodCall> launcherCalls = <MethodCall>[];

  /// AnsiTextView.onLinkTap の受信 URL。
  final List<String> tappedUrls = <String>[];

  /// scrollSend ドラッグの送信ティック。
  final List<int> ticks = <int>[];

  /// ホールド+スワイプの方向。
  final List<String> arrowSwipes = <String>[];

  /// ターミナル領域タップ（外側 GestureDetector・normal モードのみ）。
  int terminalTaps = 0;

  Iterable<MethodCall> get launches =>
      launcherCalls.where((call) => call.method == 'launch');

  Iterable<MethodCall> get canLaunches =>
      launcherCalls.where((call) => call.method == 'canLaunch');
}

/// リンクタップテスト用のターミナル表示を構築する。
///
/// onLinkTap には実コーディネータ
/// （`TerminalViewShell.openExternalLink`）を結線するため、tap → モーダル →
/// 外部起動までを実経路で検証できる。キャンセル時の再 pump にも使う。
Widget buildAnsiLinkSubject(
  AnsiLinkTapHarness harness, {
  required String text,
  TerminalMode mode = TerminalMode.normal,
  bool openDirectly = false,
  int cursorX = 0,
  int cursorY = 0,
  double fontSize = 14.0,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(
          settings: AppSettings(
            keepScreenOn: false,
            adjustMode: 'manual',
            fontSize: fontSize,
            openLinksDirectly: openDirectly,
          ),
        ),
      ),
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
              text: text,
              paneWidth: 80,
              paneHeight: 24,
              mode: mode,
              cursorX: cursorX,
              cursorY: cursorY,
              onLinkTap: (url) {
                harness.tappedUrls.add(url);
                unawaited(
                  TerminalViewShell.openExternalLink(context, ref, url),
                );
              },
              onTap: () => harness.terminalTaps++,
              onScrollSendTicks: harness.ticks.add,
              onArrowSwipe: harness.arrowSwipes.add,
            ),
          ),
        ),
      ),
    ),
  );
}

/// url_launcher チャンネルをモックし、[harness] へ呼び出しを記録する。
void mockUrlLauncher(
  WidgetTester tester,
  AnsiLinkTapHarness harness, {
  bool canLaunch = true,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    urlLauncherChannel,
    (call) async {
      harness.launcherCalls.add(call);
      return canLaunch;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
      null,
    ),
  );
}

/// ターミナルを pump してハーネスを返す。
Future<AnsiLinkTapHarness> pumpAnsiLinkTerminal(
  WidgetTester tester, {
  required String text,
  TerminalMode mode = TerminalMode.normal,
  bool canLaunch = true,
  bool openDirectly = false,
  int cursorX = 0,
  int cursorY = 0,
  double fontSize = 14.0,
}) async {
  final harness = AnsiLinkTapHarness();
  mockUrlLauncher(tester, harness, canLaunch: canLaunch);
  await tester.pumpWidget(
    buildAnsiLinkSubject(
      harness,
      text: text,
      mode: mode,
      openDirectly: openDirectly,
      cursorX: cursorX,
      cursorY: cursorY,
      fontSize: fontSize,
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// ルート [InlineSpan] を平坦化する（TextSpan とその開始 layout オフセット）。
///
/// WidgetSpan（キャレット等）は text layout 上 placeholder 1 文字（\uFFFC）
/// を消費するためオフセットに +1 する（RenderParagraph の
/// `getPositionForOffset` / `getBoxesForRange` と同一の基準）。
List<(TextSpan, int)> flattenTextSpans(InlineSpan root) {
  final result = <(TextSpan, int)>[];
  var offset = 0;
  // WidgetSpan.visitChildren は自身を visitor に渡し続ける実装のため、
  // identity ベースの再訪問ガードなしに再帰走査すると無限ループになる。
  final visited = Expando<bool>();
  void visit(InlineSpan span) {
    if (visited[span] ?? false) {
      return;
    }
    visited[span] = true;
    if (span is TextSpan) {
      result.add((span, offset));
      offset += span.text?.length ?? 0;
    } else {
      offset += 1;
    }
    span.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return result;
}

/// 行テキスト（部分一致）から行の [RenderParagraph] を返す。
RenderParagraph renderParagraphOfRow(WidgetTester tester, Finder rowFinder) {
  expect(
    rowFinder,
    findsOneWidget,
    reason: '行テキストが一意であること (partial match)',
  );
  // find.textContaining は RichText 自身にマッチするため ancestor では
  // 取れない。element の renderObject（subtree の先頭 RenderObject =
  // Text.rich の RenderParagraph）から解決する。
  final renderObject = tester.element(rowFinder).renderObject;
  if (renderObject is RenderParagraph) {
    return renderObject;
  }
  RenderParagraph? found;
  void visit(RenderObject child) {
    if (found != null) {
      return;
    }
    if (child is RenderParagraph) {
      found = child;
      return;
    }
    child.visitChildren(visit);
  }

  renderObject?.visitChildren(visit);
  if (found == null) {
    fail('行の RenderParagraph が見つからない (partial match)');
  }
  return found!;
}

/// 指定文字オフセット中心の local タップ位置を返す（二分探索）。
///
/// RenderParagraph には逆変換 API が無く、生 TextPainter の再 layout は
/// WidgetSpan の placeholder dimensions 未設定 assert に落ちるため、
/// 実レイアウト済み [RenderParagraph.getPositionForOffset] を二分探索して
/// 文字境界の x を求める（ターミナル行は maxLines: 1 の単一行）。
Offset localTapPosition(RenderParagraph rp, int charOffset) {
  final midY = rp.size.height / 2;
  var lo = 0.0;
  var hi = rp.size.width;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    final position = rp.getPositionForOffset(Offset(mid, midY));
    if (position.offset < charOffset) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return Offset((lo + hi) / 2, midY);
}

/// 部分一致する span のうち最初のものの global タップ位置を返す。
Offset linkSpanGlobalPosition(WidgetTester tester, String substring) {
  final rp = renderParagraphOfRow(tester, find.textContaining(substring));
  for (final (span, start) in flattenTextSpans(rp.text)) {
    final text = span.text;
    if (text != null && text.contains(substring)) {
      final localIndex = text.indexOf(substring) + substring.length ~/ 2;
      return rp.localToGlobal(localTapPosition(rp, start + localIndex));
    }
  }
  fail('span が見つからない: $substring');
}

/// 部分一致する span をタップする（モーダル表示等の非同期処理も消化する）。
Future<void> tapLinkText(WidgetTester tester, String substring) async {
  await tester.tapAt(linkSpanGlobalPosition(tester, substring));
  await tester.pumpAndSettle();
}

/// ツリー内の全 [TapGestureRecognizer] を収集する（identity 検証用）。
List<TapGestureRecognizer> collectRecognizers(WidgetTester tester) {
  final recognizers = <TapGestureRecognizer>[];
  // WidgetSpan.visitChildren は自身を visitor に渡し続けるため、identity
  // ベースの再訪問ガードが必要（無いと無限再帰で StackOverflow する）。
  final visited = Expando<bool>();
  void collect(InlineSpan span) {
    if (visited[span] ?? false) {
      return;
    }
    visited[span] = true;
    final recognizer = span is TextSpan ? span.recognizer : null;
    if (recognizer is TapGestureRecognizer) {
      recognizers.add(recognizer);
    }
    span.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    collect(richText.text);
  }
  return recognizers;
}

/// キャレット（DesignColors.primary の細棒）の Finder。
Finder get caretBarFinder => find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == DesignColors.primary,
);

/// キャレット点滅の表示相を決定的に固定する（on / off）。
///
/// 500ms 点滅 Timer のため pumpAndSettle 直後の相は非決定的。期待に合わない
/// 場合は 1 点滅分（600ms）だけ時計を進めて揃える。
Future<void> ensureCaretPhase(WidgetTester tester, {required bool on}) async {
  if (tester.any(caretBarFinder) != on) {
    await tester.pump(const Duration(milliseconds: 600));
  }
  expect(tester.any(caretBarFinder), on);
}
