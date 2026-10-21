/// [TerminalScrollFollowController.onViewportSettled]（herdr OSC 8
/// ハイパーリンク・スクロールモードのリンク読取への通知）の widget テスト。
///
/// [TerminalViewportPort] は `GlobalKey<AnsiTextViewState>` を介した中立
/// seam の実装（concrete class・interface ではない）で、`AnsiTextView` の
/// 実インスタンスが無いと `visibleLineRange()` が意味を持たない。そのため
/// 純粋な unit test ではなく、実 `AnsiTextView` を pump した widget test で
/// 検証する（`test/screens/terminal/helpers/ansi_link_tap_harness.dart` と
/// 同じ構成）。
///
/// [TerminalScrollFollowController] 自体は `onScrollNotification` を直接
/// 呼べるため、実際の `NotificationListener` は経由せず、合成した
/// [ScrollEndNotification] を渡して検証する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/screens/terminal/input/terminal_input_ports.dart';
import 'package:flutter_muxpod/screens/terminal/input/terminal_scroll_follow_controller.dart';
import 'package:flutter_muxpod/screens/terminal/input/terminal_viewport_port.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/tmux/pane_navigator.dart'
    show SwipeDirection;

import '../../../helpers/fake_settings_notifier.dart';

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

class _FakeScrollbackPort implements TerminalScrollbackPort {
  _FakeScrollbackPort(this._content);

  String _content;

  /// テストが差し替える捕獲 identity（デフォルトは非 null の固定値）。
  Object? identityToCapture = Object();

  @override
  bool get canRead => true;
  @override
  String get displayedContent => _content;
  @override
  int get displayedPaneWidth => 80;
  @override
  int get displayedPaneHeight => 24;
  @override
  PaneCaret? get displayedCaret => null;
  @override
  int get scrollbackLimit => 10000;
  @override
  Object? captureTargetIdentity() => identityToCapture;
  @override
  Future<String?> readScrollbackContent() async => _content;
  @override
  void setDisplayedContent(String content) => _content = content;
}

class _FakeValidator implements TerminalTargetIdentityValidator {
  bool current = true;
  @override
  bool isCurrent(Object? identity) => current;
}

class _FakeNavigationPort implements TerminalNavigationPort {
  @override
  bool get isHerdr => false;
  @override
  Future<void> selectAdjacentPane(
    SwipeDirection direction, {
    required bool invert,
  }) async {}
  @override
  Map<SwipeDirection, bool>? navigableDirections({required bool invert}) =>
      null;
  @override
  Future<void> focusPaneDirection(SwipeDirection direction) async {}
}

class _FakeHost implements TerminalInputHost {
  bool mounted = true;
  bool disposed = false;
  @override
  bool get isMounted => mounted;
  @override
  bool get isDisposed => disposed;
  @override
  void markNeedsBuild() {}
  @override
  void showScrollToBottomButton() {}
  @override
  void notifyInputQueueFull() {}
  @override
  void notifyMultilineNeedsConnection() {}
  @override
  void notifyHerdrInvalidKey() {}
}

typedef _SettledEvent = ({
  ({Object? identity, int generation}) snapshotIdentity,
  int lineCount,
  ({int top, int bottom}) visibleRange,
});

/// [manyLines] 行のテキストで `AnsiTextView` を pump し、実
/// `GlobalKey<AnsiTextViewState>` を返す（`visibleLineRange()` が実際の
/// スクロール位置を反映するようにするため）。
Future<GlobalKey<AnsiTextViewState>> pumpScrollableAnsiTextView(
  WidgetTester tester, {
  required String text,
  GlobalKey<AnsiTextViewState>? key,
}) async {
  final resolvedKey = key ?? GlobalKey<AnsiTextViewState>();
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: Consumer(
              builder: (context, ref, _) => AnsiTextView(
                key: resolvedKey,
                text: text,
                paneWidth: 80,
                paneHeight: 24,
                mode: TerminalMode.select,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return resolvedKey;
}

/// テスト対象の `metrics.axis == Axis.vertical` を満たす合成
/// [ScrollEndNotification] を作る（`onScrollNotification` の軸ガードを
/// 通すためだけの最小構成。`pixels`/`viewportDimension` の値自体は
/// `_notifyViewportSettled` の判定には使わない。実際の可視範囲は
/// `viewport.visibleLineRange()` が実 widget のスクロール位置から算出する）。
ScrollEndNotification syntheticVerticalScrollEnd(BuildContext context) {
  return ScrollEndNotification(
    context: context,
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 500,
      viewportDimension: 400,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    ),
  );
}

void main() {
  testWidgets('select モードでスクロールを止めると onViewportSettled が1回呼ばれる', (
    tester,
  ) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    final key = await pumpScrollableAnsiTextView(tester, text: manyLines);
    final context = tester.element(find.byType(AnsiTextView));

    final events = <_SettledEvent>[];
    final controller = TerminalScrollFollowController(
      scrollback: _FakeScrollbackPort(manyLines),
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    controller.onScrollNotification(syntheticVerticalScrollEnd(context));
    await tester.pumpAndSettle();

    expect(events, hasLength(1));
    expect(events.single.lineCount, 200);
    expect(
      events.single.visibleRange.top,
      lessThanOrEqualTo(events.single.visibleRange.bottom),
    );
    expect(events.single.snapshotIdentity.identity, isNotNull);
  });

  testWidgets('normal モード中は onViewportSettled を呼ばない', (tester) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    final key = await pumpScrollableAnsiTextView(tester, text: manyLines);
    final context = tester.element(find.byType(AnsiTextView));

    final events = <_SettledEvent>[];
    final controller = TerminalScrollFollowController(
      scrollback: _FakeScrollbackPort(manyLines),
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.normal,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    controller.onScrollNotification(syntheticVerticalScrollEnd(context));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
  });

  testWidgets('detach 後は onViewportSettled を呼ばない', (tester) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    final key = await pumpScrollableAnsiTextView(tester, text: manyLines);
    final context = tester.element(find.byType(AnsiTextView));

    final events = <_SettledEvent>[];
    final controller = TerminalScrollFollowController(
      scrollback: _FakeScrollbackPort(manyLines),
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    controller.attach(ScrollController());
    controller.detach();
    controller.onScrollNotification(syntheticVerticalScrollEnd(context));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
  });

  testWidgets('select モードに入りスナップショットが確定した直後に1回呼ばれる（loadHistoryForScroll）', (
    tester,
  ) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    final key = await pumpScrollableAnsiTextView(tester, text: manyLines);

    final events = <_SettledEvent>[];
    final scrollback = _FakeScrollbackPort(manyLines);
    final controller = TerminalScrollFollowController(
      scrollback: scrollback,
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    await controller.loadHistoryForScrollForTesting();
    // 本番でフレームが予約されるのは `host.markNeedsBuild()` ではなく、
    // `loadHistoryForScroll` 内の `scrollback.setDisplayedContent` が
    // `viewNotifier.value` を更新し（`terminal_screen_ports.dart:277-279`）、
    // それを購読する `ValueListenableBuilder` 相当が再構築を要求するため
    // である。ここでは controller を widget tree の外から
    // 直接叩いており、その再構築要求が無いため代わりに明示的に予約する
    // （`AutomatedTestWidgetsFlutterBinding.pump` は `hasScheduledFrame` の
    // ときしか handleDrawFrame を実行しない）。
    WidgetsBinding.instance.scheduleFrame();
    await tester.pumpAndSettle();

    expect(events, hasLength(1));
    expect(events.single.snapshotIdentity.generation, 1);
  });

  testWidgets('スナップショットが確定するたびに generation が増える', (tester) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    final key = await pumpScrollableAnsiTextView(tester, text: manyLines);

    final events = <_SettledEvent>[];
    final scrollback = _FakeScrollbackPort(manyLines);
    final controller = TerminalScrollFollowController(
      scrollback: scrollback,
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    await controller.loadHistoryForScrollForTesting();
    WidgetsBinding.instance.scheduleFrame();
    await tester.pumpAndSettle();
    await controller.loadHistoryForScrollForTesting();
    WidgetsBinding.instance.scheduleFrame();
    await tester.pumpAndSettle();

    expect(events, hasLength(2));
    expect(events[0].snapshotIdentity.generation, 1);
    expect(events[1].snapshotIdentity.generation, 2);
  });

  testWidgets('visibleLineRange が最初 null でも次フレームで非 null なら1回だけ呼ぶ', (
    tester,
  ) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    // AnsiTextView へまだアタッチしていない key（visibleLineRange() が
    // null を返す状態を作る）。
    final key = GlobalKey<AnsiTextViewState>();

    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final events = <_SettledEvent>[];
    final controller = TerminalScrollFollowController(
      scrollback: _FakeScrollbackPort(manyLines),
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    // 1回目: key が未アタッチのため visibleLineRange() は null。
    // 次フレームでの再試行が登録される（scheduleFrame() 込み）。
    controller.onScrollNotification(
      syntheticVerticalScrollEnd(capturedContext),
    );
    expect(events, isEmpty);

    // 次フレームで同じ key に実 AnsiTextView をマウントする。
    await pumpScrollableAnsiTextView(tester, text: manyLines, key: key);

    expect(events, hasLength(1));
  });

  testWidgets('visibleLineRange が2回連続で null なら通知0回・それ以上再試行しない', (tester) async {
    final manyLines = List.generate(200, (i) => 'line $i').join('\n');
    // マウントしないままにする key。
    final key = GlobalKey<AnsiTextViewState>();

    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final events = <_SettledEvent>[];
    final controller = TerminalScrollFollowController(
      scrollback: _FakeScrollbackPort(manyLines),
      viewport: TerminalViewportPort(key),
      nav: _FakeNavigationPort(),
      host: _FakeHost(),
      validator: _FakeValidator(),
      mode: () => TerminalMode.select,
    );
    controller.onViewportSettled =
        (snapshotIdentity, lineCount, visibleRange) => events.add((
          snapshotIdentity: snapshotIdentity,
          lineCount: lineCount,
          visibleRange: visibleRange,
        ));

    controller.onScrollNotification(
      syntheticVerticalScrollEnd(capturedContext),
    );
    expect(events, isEmpty);

    // 再試行のフレームが発火しても key は未マウントのまま
    // （visibleLineRange() は2回目も null → それ以上は再試行しない）。
    await tester.pump();
    await tester.pump();
    expect(events, isEmpty);
    // events が空のままでも
    // 再試行が無限に続く実装では検知できないため、これ以上フレームが
    // 予約されていない（＝再試行が登録されていない）ことも確認する。
    expect(tester.binding.hasScheduledFrame, isFalse);

    // さらに時間が経っても新たな再試行が登録されていないことを確認する。
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);
  });
}
