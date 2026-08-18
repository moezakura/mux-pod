import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper that wraps the dialog content in a testable widget tree.
Widget _buildWidget({
  String initialValue = '',
  required void Function(String) onValueChanged,
  required Future<void> Function(String) onSend,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: buildInputDialogContentForTesting(
        initialValue: initialValue,
        onValueChanged: onValueChanged,
        onSend: onSend,
      ),
    ),
  );
}

/// 既存テストの構成（pumpWidget → pump → キー合成 → pump）を踏襲する。
/// 修飾キー合成は down → key → up の順（押下順序が HardwareKeyboard 状態の前提）。
void main() {
  group('InputDialogContent – Enter key behaviour', () {
    testWidgets(
      'plain Enter inserts exactly one newline and does not send (T1\')',
      (tester) async {
        int sendCount = 0;
        String? lastValue;
        await tester.pumpWidget(
          _buildWidget(
            initialValue: 'hello',
            onValueChanged: (v) => lastValue = v,
            onSend: (v) async => sendCount++,
          ),
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(sendCount, 0);
        expect(lastValue, 'hello\n');
      },
    );

    testWidgets('Ctrl+Enter sends once without inserting a newline (T2\')', (
      tester,
    ) async {
      int sendCount = 0;
      String? sentValue;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (_) {},
          onSend: (v) async {
            sentValue = v;
            sendCount++;
          },
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(sendCount, 1);
      expect(sentValue, 'hello');
      expect(sentValue, isNot(contains('\n')));
    });

    testWidgets('Enter while composing is ignored, Ctrl+Enter is consumed (T3)', (
      tester,
    ) async {
      int sendCount = 0;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: '',
          onValueChanged: (_) {},
          onSend: (v) async => sendCount++,
        ),
      );
      await tester.pump();

      // Simulate IME composition: set composing range to a non-collapsed range.
      final TextField textField = tester.widget<TextField>(
        find.byType(TextField),
      );
      final TextEditingController controller = textField.controller!;
      controller.value = const TextEditingValue(
        text: 'あ',
        composing: TextRange(start: 0, end: 1),
      );
      await tester.pump();

      // composing 中 plain Enter → IME に譲る（無視・変換維持）
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sendCount, 0);
      expect(controller.text, 'あ');

      // composing 中 Ctrl+Enter → handled 消費（送信も改行もしない）
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(sendCount, 0);
      expect(controller.text, 'あ');
    });

    testWidgets('Cmd+Enter (meta) sends once (T4)', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (_) {},
          onSend: (v) async => sendCount++,
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Execute button sends once (T5)', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (_) {},
          onSend: (v) async => sendCount++,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Execute'));
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Shift+Enter inserts newline (backward compatibility, T6)', (
      tester,
    ) async {
      int sendCount = 0;
      String? lastValue;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (v) => lastValue = v,
          onSend: (v) async => sendCount++,
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sendCount, 0);
      expect(lastValue, contains('\n'));
    });

    testWidgets('numpadEnter inserts newline and Ctrl+numpadEnter sends (T7)', (
      tester,
    ) async {
      int sendCount = 0;
      String? lastValue;
      String? sentValue;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (v) => lastValue = v,
          onSend: (v) async {
            sentValue = v;
            sendCount++;
          },
        ),
      );
      await tester.pump();

      // numpadEnter → 改行挿入・送信しない
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      expect(sendCount, 0);
      expect(lastValue, contains('\n'));

      // Ctrl+numpadEnter → 送信
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(sendCount, 1);
      expect(sentValue, 'hello\n');
    });

    testWidgets('Ctrl+Enter while sending does not send again (T8)', (
      tester,
    ) async {
      final completer = Completer<void>();
      int sendCount = 0;
      await tester.pumpWidget(
        _buildWidget(
          initialValue: 'hello',
          onValueChanged: (_) {},
          onSend: (v) async {
            sendCount++;
            return completer.future;
          },
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // 送信中（onSend 未完了）に再度 Ctrl+Enter → 二重送信防止
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(sendCount, 1);

      completer.complete();
      await tester.pump();
    });

    testWidgets(
      'Enter repeat inserts newline continuously; Ctrl+Enter repeat does not resend (T9)',
      (tester) async {
        int sendCount = 0;
        String? lastValue;
        await tester.pumpWidget(
          _buildWidget(
            initialValue: 'hello',
            onValueChanged: (v) => lastValue = v,
            onSend: (v) async => sendCount++,
          ),
        );
        await tester.pump();

        // Enter 長押し（KeyDown + KeyRepeat×2）→ 連続改行・送信しない
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(sendCount, 0);
        expect(lastValue, 'hello\n\n\n');

        // Ctrl+Enter のリピート（KeyRepeat）→ 再送信なし・改行もなし
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(sendCount, 0);
        expect(lastValue, 'hello\n\n\n');
      },
    );
  });
}
