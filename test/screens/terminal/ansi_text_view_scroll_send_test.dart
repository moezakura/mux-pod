import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/tmux/pane_navigator.dart';

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

// inventory: TERM-SCROLL-009
/// AnsiTextView 単体での scrollSend 表示分岐テスト（C5・D5/M2/M5）。
///
/// 1 ティック = `_lineHeight × 1.5` = (fontSize 10 × 1.2) × 1.5 = **18.0px**
/// （行高係数は `FontCalculator.lineHeightRatio = 1.2` ・main #79 で統一）。
/// ドラッグ距離は 18.0px 単位で指定する（fontSize 10 に固定することで
/// 浮動小数点誤差なく整数倍のティックが正確に計算される）。
const double _kTickPx = 18.0;

/// スクロール可能な 200 行のテキスト（リストのオフセット検証用）。
String get _scrollableText => List.generate(200, (i) => 'line$i').join('\n');

Widget _buildSubject({
  required TerminalMode mode,
  required List<int> ticks,
  void Function(double scale)? onZoomChanged,
  void Function(SwipeDirection direction)? onTwoFingerSwipe,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(
          settings: const AppSettings(adjustMode: 'none', fontSize: 10.0),
        ),
      ),
      terminalDisplayProvider.overrideWith(
        () => _FixedTerminalDisplayNotifier(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AnsiTextView(
          text: _scrollableText,
          paneWidth: 80,
          paneHeight: 24,
          mode: mode,
          onScrollSendTicks: (t) => ticks.add(t),
          onZoomChanged: onZoomChanged,
          onTwoFingerSwipe: onTwoFingerSwipe,
        ),
      ),
    ),
  );
}

Finder _verticalScrollable() => find.descendant(
  of: find.byType(AnsiTextView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnsiTextView scrollSend display branch (C5・D5)', () {
    testWidgets(
      'TERM-SCROLL-010 drag up emits positive ticks (1 tick = lineHeight * 1.5)',
      (tester) async {
        final ticks = <int>[];
        await tester.pumpWidget(
          _buildSubject(mode: TerminalMode.scrollSend, ticks: ticks),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -_kTickPx));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -_kTickPx));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        // 上ドラッグ = 上スクロール送信（ticks > 0）
        expect(ticks, [1, 1]);
      },
    );

    testWidgets('TERM-SCROLL-011 drag down emits negative ticks', (
      tester,
    ) async {
      final ticks = <int>[];
      await tester.pumpWidget(
        _buildSubject(mode: TerminalMode.scrollSend, ticks: ticks),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, _kTickPx * 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 下ドラッグ = 下スクロール送信（ticks < 0）。1 回の Update で 2 ティック。
      expect(ticks, [-2]);
    });

    testWidgets(
      'TERM-SCROLL-012 ±25% hysteresis dead-zone suppresses small reversals',
      (tester) async {
        final ticks = <int>[];
        await tester.pumpWidget(
          _buildSubject(mode: TerminalMode.scrollSend, ticks: ticks),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(200, 400));
        // 3 ティック上（63px）→ [3]。以後 fraction は 0。
        await gesture.moveBy(const Offset(0, -_kTickPx * 3));
        await tester.pump();
        expect(ticks, [3]);
        // 0.6 ティック上（12.6px）→ fraction 0.6（発火なし）。
        await gesture.moveBy(const Offset(0, -_kTickPx * 0.6));
        await tester.pump();
        expect(ticks, [3]);
        // 0.2 ティック下（4.2px）→ 方向反転だが ±25% デッドゾーン未満 → 無視。
        await gesture.moveBy(const Offset(0, _kTickPx * 0.2));
        await tester.pump();
        expect(ticks, [3]);
        // 0.3 ティック下（6.3px）→ 反転確定（≥0.25）で端数リセット → fraction -0.3。
        await gesture.moveBy(const Offset(0, _kTickPx * 0.3));
        await tester.pump();
        expect(ticks, [3]);
        // 0.8 ティック下（16.8px）→ fraction -1.1 → -1 発火。
        await gesture.moveBy(const Offset(0, _kTickPx * 0.8));
        await tester.pump();
        expect(ticks, [3, -1]);
        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'TERM-SCROLL-013 scrollSend: SelectionArea absent and offset frozen',
      (tester) async {
        // scrollSend: テキスト選択なし（SelectionArea 非配置）。
        final ticks = <int>[];
        await tester.pumpWidget(
          _buildSubject(mode: TerminalMode.scrollSend, ticks: ticks),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SelectionArea), findsNothing);

        // ListView のオフセットは NeverScrollableScrollPhysics で不動。
        final scrollable = _verticalScrollable();
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(1000);
        await tester.pump();
        final before = position.pixels;

        final gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -_kTickPx * 3));
        await tester.pump();
        await gesture.moveBy(const Offset(0, _kTickPx * 2));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(
          position.pixels,
          before,
          reason: 'scrollSend 中はローカルスクロールが無効（オフセット不動）',
        );
        expect(ticks, isNotEmpty, reason: 'ドラッグはスクロールではなくティック送信へ変換される');
      },
    );

    testWidgets('select mode keeps SelectionArea (4 経路分離・D12)', (tester) async {
      await tester.pumpWidget(
        _buildSubject(mode: TerminalMode.select, ticks: <int>[]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('TERM-SCROLL-014 two-finger pan does not trigger pane swipe in '
        'scrollSend (M5)', (tester) async {
      final ticks = <int>[];
      SwipeDirection? swiped;
      await tester.pumpWidget(
        _buildSubject(
          mode: TerminalMode.scrollSend,
          ticks: ticks,
          onTwoFingerSwipe: (d) => swiped = d,
        ),
      );
      await tester.pumpAndSettle();

      final g1 = await tester.startGesture(const Offset(150, 400), pointer: 1);
      final g2 = await tester.startGesture(const Offset(250, 400), pointer: 2);
      await tester.pump();
      await g1.moveBy(const Offset(0, -120));
      await g2.moveBy(const Offset(0, -120));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();

      // 2 本指スワイプ（ペイン切替）は scrollSend 中は無効（M5）。
      expect(swiped, isNull);
      // 1 本指ドラッグとしても誤発火しない（scale recognizer が勝利）。
      expect(ticks, isEmpty);
    });

    testWidgets(
      'TERM-SCROLL-015 pinch zoom is inert in scrollSend (Phase 3 #6・B5 '
      '実測で競合確認)',
      (tester) async {
        final ticks = <int>[];
        final zoomScales = <double>[];
        await tester.pumpWidget(
          _buildSubject(
            mode: TerminalMode.scrollSend,
            ticks: ticks,
            onZoomChanged: (s) => zoomScales.add(s),
          ),
        );
        await tester.pumpAndSettle();

        final g1 = await tester.startGesture(
          const Offset(150, 400),
          pointer: 1,
        );
        final g2 = await tester.startGesture(
          const Offset(250, 400),
          pointer: 2,
        );
        await tester.pump();
        // 指を広げる（ピンチアウト = ズームイン）。
        await g1.moveBy(const Offset(-40, 0));
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
        await g1.up();
        await g2.up();
        await tester.pump();

        // scrollSend 中は zoom 認識子を無効化（Phase 3 #6 分岐・B5 実測:
        // スケール認識子が arena に参加すると 1 本指ドラッグの Update が
        // 欠落し送信ティックが不足するため。ズームはモードを抜けてから行う）。
        expect(
          zoomScales,
          isEmpty,
          reason: 'scrollSend 中はピンチズームが無効（Phase 3 #6）',
        );
        // ピンチ操作がティック送信として誤解釈されないこと。
        expect(ticks, isEmpty);
      },
    );

    testWidgets('normal mode drag does not emit ticks (scrollSend 分岐のみ)', (
      tester,
    ) async {
      final ticks = <int>[];
      await tester.pumpWidget(
        _buildSubject(mode: TerminalMode.normal, ticks: ticks),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, -_kTickPx * 3));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(ticks, isEmpty, reason: 'normal モードは既存のリストスクロール（ティック送信なし）');
    });
  });
}
