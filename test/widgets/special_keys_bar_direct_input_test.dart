import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/special_keys_bar_harness.dart';

void main() {
  group('SpecialKeysBar direct input field', () {
    testWidgets('typed text stays visible and is sent exactly once', (
      tester,
    ) async {
      final keys = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, onKeyPressed: keys.add),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();

      // The field keeps the typed text visible (not cleared to the sentinel).
      expect(visibleText(tester), 'models');
      expect(keys, ['models']);
    });

    testWidgets('deleting text sends BSpace for each removed char', (
      tester,
    ) async {
      final keys = <String>[];
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(
          directInput: true,
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      expect(keys, ['models']);

      await tester.enterText(directInputField(), 'mode');
      await tester.pump();

      expect(specials.where((k) => k == 'BSpace').length, 2);
      expect(visibleText(tester), 'mode');
    });

    testWidgets('submit sends Enter and clears the field', (tester) async {
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, onSpecialKeyPressed: specials.add),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      expect(visibleText(tester), 'models');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(specials, contains('Enter'));
      expect(visibleText(tester), isEmpty);
    });

    testWidgets('keepKeyboardOnEnter keeps focus after submit', (tester) async {
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(
          directInput: true,
          keepKeyboardOnEnter: true,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      // 同期 requestFocus() で unfocus をキャンセルする（フレームワークの
      // 明示サポート経路: editable_text._restartConnectionIfNeeded）。
      // pump 1回でマイクロタスクまで消化し、settle で post-frame の
      // sentinel 再リセットも完了させる。
      await tester.pump();
      await tester.pumpAndSettle();

      expect(specials, contains('Enter'));
      expect(visibleText(tester), isEmpty);
      // 送信後もフィールドはフォーカスを失わない（キーボード維持）
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isTrue,
      );
    });

    testWidgets('default (off) unfocuses after submit (regression guard)', (
      tester,
    ) async {
      await tester.pumpWidget(customHarness(directInput: true));
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      // 設定OFF（デフォルト）: 既存挙動どおりフォーカスは外れる
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isFalse,
      );
    });

    testWidgets('field disables autocorrect and smart punctuation', (
      tester,
    ) async {
      await tester.pumpWidget(
        customHarness(directInput: true, onKeyPressed: (_) {}),
      );
      await tester.pump();

      // パススルー入力欄のため、OSによるテキスト書き換え（".."→"‥" 等）を
      // 許可しない（Issue: iOS自動補正による入力破壊）。
      final field = tester.widget<TextField>(directInputField());
      expect(field.autocorrect, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      // enableSuggestions は無効化しない: Androidエンジンが inputType へ
      // TYPE_TEXT_VARIATION_VISIBLE_PASSWORD を付加し、IME変換（日本語入力）が
      // 不可能になるため（autocorrect=false と併用しない）。
      expect(field.enableSuggestions, isTrue);
    });
  });
  group('SpecialKeysBar CJK mode (v0.7.0-pre4 behavior)', () {
    testWidgets('committed text is sent in full and the field clears', (
      tester,
    ) async {
      final keys = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, cjkMode: true, onKeyPressed: keys.add),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'こんにちは');
      await tester.pump();

      // pre4挙動: 確定テキストを全文送信し、入力欄はsentinelへクリアされる
      expect(keys, ['こんにちは']);
      expect(visibleText(tester), isEmpty);

      // 追加入力も毎回全文送信される（テキストは欄に残らない）
      await tester.enterText(directInputField(), 'abc');
      await tester.pump();
      expect(keys, ['こんにちは', 'abc']);
      expect(visibleText(tester), isEmpty);
    });

    testWidgets('iOS duplicate insertion is trimmed to composing text', (
      tester,
    ) async {
      final keys = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, cjkMode: true, onKeyPressed: keys.add),
      );
      await tester.pump();

      // IME変換中（composing範囲付き）の更新: 送信しない
      final field = tester.widget<TextField>(directInputField());
      final controller = field.controller!;
      controller.value = const TextEditingValue(
        text: '\u200Bこんにちは',
        composing: TextRange(start: 1, end: 6),
      );
      await tester.pump();
      expect(keys, isEmpty);

      // iOSの自動確定バグ: composingテキストの重複挿入として確定される
      controller.value = const TextEditingValue(
        text: '\u200Bこんにちはこんにちは',
        selection: TextSelection.collapsed(offset: 11),
      );
      await tester.pump();

      // 重複分は除去され、composingテキストのみ一度だけ送信される
      expect(keys, ['こんにちは']);
    });

    testWidgets('toggling CJK mode resets the field to sentinel', (
      tester,
    ) async {
      final keys = <String>[];
      await tester.pumpWidget(
        customHarness(directInput: true, onKeyPressed: keys.add),
      );
      await tester.pump();

      // 通常モード（delta送信）でテキストを残す
      await tester.enterText(directInputField(), 'ls');
      await tester.pump();
      expect(visibleText(tester), 'ls');

      // CJKモードへ切替: 残ったテキストはクリアされる
      await tester.pumpWidget(
        customHarness(directInput: true, cjkMode: true, onKeyPressed: keys.add),
      );
      await tester.pump();
      expect(visibleText(tester), isEmpty);
    });

    testWidgets('CJK mode + keepKeyboardOnEnter keeps focus after submit', (
      tester,
    ) async {
      final keys = <String>[];
      final specials = <String>[];
      await tester.pumpWidget(
        customHarness(
          directInput: true,
          cjkMode: true,
          keepKeyboardOnEnter: true,
          onKeyPressed: keys.add,
          onSpecialKeyPressed: specials.add,
        ),
      );
      await tester.pump();

      await tester.enterText(directInputField(), 'models');
      await tester.pump();
      // CJKモード: 入力確定で全文送信済み・欄はクリア済み
      expect(keys, ['models']);
      expect(visibleText(tester), isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pumpAndSettle();

      // 'Enter' が1回だけ送信され、フィールドはクリア・フォーカス維持
      expect(specials.where((k) => k == 'Enter').length, 1);
      expect(visibleText(tester), isEmpty);
      expect(
        tester.widget<TextField>(directInputField()).focusNode!.hasFocus,
        isTrue,
      );
    });
  });
}
