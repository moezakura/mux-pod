import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

/// 実行時 prop 伝播（設計書 v2-1）の回帰テスト。
///
/// didUpdateWidget で callbacks / cjkMode / keepKeyboardOnEnter を無条件に
/// エンジンへ伝播する配線の検証。既存40テストは初期値のみを検証するため、
/// 実行中トグル（terminal_screen の select-watch 相当）をここで担保する。
void main() {
  Widget harness({
    required bool directInput,
    required bool keepKeyboardOnEnter,
    required bool cjkMode,
    void Function(String)? onKeyPressed,
    void Function(String)? onSpecialKeyPressed,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 720,
            child: SpecialKeysBar(
              onKeyPressed: onKeyPressed ?? (_) {},
              onSpecialKeyPressed: onSpecialKeyPressed ?? (_) {},
              onInputTap: () {},
              onDirectInputToggle: () {},
              directInputEnabled: directInput,
              cjkMode: cjkMode,
              keepKeyboardOnEnter: keepKeyboardOnEnter,
              hapticFeedback: false,
              rows: [
                const <String>[],
                CustomKeyRows.standardRow1,
                CustomKeyRows.standardRow2,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder directInputField() => find.byType(TextField);

  String visibleText(WidgetTester tester) {
    final field = tester.widget<TextField>(directInputField());
    return field.controller!.text.replaceAll('\u200B', '');
  }

  testWidgets(
    'keepKeyboardOnEnter live toggle: false→true keeps focus after submit',
    (tester) async {
      // 初期値 false: 送信後はフレームワーク既定どおり unfocus
      await tester.pumpWidget(
        harness(directInput: true, keepKeyboardOnEnter: false, cjkMode: false),
      );
      await tester.pump();
      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isFalse,
      );

      // 実行中に true へトグル（didUpdateWidget の無条件伝播）→ 再 pump
      await tester.pumpWidget(
        harness(directInput: true, keepKeyboardOnEnter: true, cjkMode: false),
      );
      await tester.pump();
      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'keepKeyboardOnEnter live toggle: true→false unfocuses after submit',
    (tester) async {
      await tester.pumpWidget(
        harness(directInput: true, keepKeyboardOnEnter: true, cjkMode: false),
      );
      await tester.pump();
      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isTrue,
      );

      // 実行中に false へトグル → 送信後は unfocus へ戻る
      await tester.pumpWidget(
        harness(directInput: true, keepKeyboardOnEnter: false, cjkMode: false),
      );
      await tester.pump();
      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isFalse,
      );
    },
  );

  testWidgets('cjkMode live toggle: delta mode switches to full-send mode', (
    tester,
  ) async {
    final keys = <String>[];
    // 通常モード（delta送信）: テキストは欄に残る
    await tester.pumpWidget(
      harness(
        directInput: true,
        keepKeyboardOnEnter: false,
        cjkMode: false,
        onKeyPressed: keys.add,
      ),
    );
    await tester.pump();
    await tester.enterText(directInputField(), 'ls');
    await tester.pump();
    expect(keys, ['ls']);
    expect(visibleText(tester), 'ls');

    // 実行中に CJK モードへ切替（無条件伝播）→ 全文送信+クリアへ切替
    await tester.pumpWidget(
      harness(
        directInput: true,
        keepKeyboardOnEnter: false,
        cjkMode: true,
        onKeyPressed: keys.add,
      ),
    );
    await tester.pump();
    // 切替時に欄は sentinel へリセットされる
    expect(visibleText(tester), isEmpty);

    await tester.enterText(directInputField(), 'abc');
    await tester.pump();
    expect(keys, ['ls', 'abc']);
    expect(visibleText(tester), isEmpty);
  });
}
