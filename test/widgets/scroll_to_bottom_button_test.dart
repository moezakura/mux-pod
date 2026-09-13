import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/widgets/scroll_to_bottom_button.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('ScrollToBottomButton (FAB ロック機能)', () {
    testWidgets('locked=true なら show() 呼び出し前でも表示され、3 秒 pump しても消えない', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(ScrollToBottomButton(locked: true, onPressed: () {})),
      );
      // ロック中は show() なしでも表示される（SizedBox.shrink ではない）。
      expect(find.byType(AnimatedContainer), findsOneWidget);
      expect(
        _decoration(tester).color,
        isNot(Colors.transparent),
        reason: 'ロック中は常時アクティブ背景で表示されること',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byType(AnimatedContainer),
        findsOneWidget,
        reason: '3 秒経過しても表示が維持されること',
      );
      expect(
        _decoration(tester).color,
        isNot(Colors.transparent),
        reason: '3 秒経過してもアクティブ背景が維持されること',
      );
    });

    testWidgets(
      'locked=true でアイコンが vertical_align_bottom、通常時は keyboard_double_arrow_down',
      (tester) async {
        await tester.pumpWidget(
          _wrap(ScrollToBottomButton(locked: true, onPressed: () {})),
        );
        expect(find.byIcon(Icons.vertical_align_bottom), findsOneWidget);

        // 通常時: show() 前は非表示 → show() 後に keyboard_double_arrow_down。
        final key = GlobalKey<ScrollToBottomButtonState>();
        await tester.pumpWidget(
          _wrap(ScrollToBottomButton(key: key, onPressed: () {})),
        );
        expect(
          find.byType(AnimatedContainer),
          findsNothing,
          reason: 'locked=false かつ show() 前は非表示であること',
        );
        key.currentState!.show();
        await tester.pump();
        expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);
      },
    );

    testWidgets('タップで onPressed、ロングプレスで onLongPress が発火する', (tester) async {
      var tapped = 0;
      var longPressed = 0;
      final key = GlobalKey<ScrollToBottomButtonState>();
      await tester.pumpWidget(
        _wrap(
          ScrollToBottomButton(
            key: key,
            onPressed: () => tapped++,
            onLongPress: () => longPressed++,
          ),
        ),
      );
      key.currentState!.show();
      await tester.pump();

      await tester.tap(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(tapped, 1, reason: 'タップで onPressed が発火すること');
      expect(longPressed, 0);

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(longPressed, 1, reason: 'ロングプレスで onLongPress が発火すること');
      expect(tapped, 1, reason: 'ロングプレスでは onPressed は発火しないこと');
    });

    testWidgets('locked true→false 遷移後、表示中なら 3 秒後にフェードする', (tester) async {
      final key = GlobalKey<ScrollToBottomButtonState>();
      await tester.pumpWidget(
        _wrap(ScrollToBottomButton(key: key, locked: true, onPressed: () {})),
      );
      // show() で _visible を立てておく（ロック解除後の残留対策の前提）。
      key.currentState!.show();
      await tester.pump();
      expect(_decoration(tester).color, isNot(Colors.transparent));

      // ロック解除（true → false）。
      await tester.pumpWidget(
        _wrap(ScrollToBottomButton(key: key, locked: false, onPressed: () {})),
      );
      await tester.pump();
      expect(
        _decoration(tester).color,
        isNot(Colors.transparent),
        reason: 'ロック解除直後はまだ表示・アクティブであること',
      );
      expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);

      // 3 秒フェードタイマー + アニメーション消化後は非アクティブ背景に遷移する。
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _decoration(tester).color,
        Colors.transparent,
        reason: 'ロック解除後 3 秒でアクティブ背景が落ちること',
      );
    });
  });
}
