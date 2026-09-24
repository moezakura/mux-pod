import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/custom_keys/custom_key_button.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

// P5: SpecialKeysBar テストの pump ヘルパー（main() なし・テスト対象外）。
// 旧 test/widgets/special_keys_bar_test.dart L11-142 からの行コピー。
// group4/5 のローカル重複（directInputField / visibleText）もここに一本化。

/// Narrow-phone harness (#63): assert the toolbar does not overflow at a real
/// phone width and that page-navigation keys are present.
Widget buildWidget({
  required bool directInputEnabled,
  VoidCallback? onImagePickRequested,
  List<String> row0Tokens = const <String>[],
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 320,
          child: SpecialKeysBar(
            onKeyPressed: (_) {},
            onSpecialKeyPressed: (_) {},
            onInputTap: () {},
            directInputEnabled: directInputEnabled,
            onDirectInputToggle: () {},
            onImagePickRequested: onImagePickRequested,
            rows: [
              row0Tokens,
              CustomKeyRows.standardRow1,
              CustomKeyRows.standardRow2,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Wide surface: assert the structural contract (a horizontal scroll view
/// wraps the direct-input arrow row) rather than pixel overflow. A narrow
/// width would trip an unrelated font-fallback overflow in the modifier row
/// under the test's default (non-monospace) font, which does not occur
/// on-device.
Widget harness({
  required bool directInput,
  double width = 720,
  List<String> row0Tokens = const <String>[],
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          child: SpecialKeysBar(
            onKeyPressed: (_) {},
            onSpecialKeyPressed: (_) {},
            onInputTap: () {},
            onImagePickRequested: () {},
            onDirectInputToggle: () {},
            directInputEnabled: directInput,
            hapticFeedback: false,
            rows: [
              row0Tokens,
              CustomKeyRows.standardRow1,
              CustomKeyRows.standardRow2,
            ],
          ),
        ),
      ),
    ),
  );
}

Finder horizontalScroller() => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

CustomKeyButton ck(String id, String label) => CustomKeyButton(
  id: id,
  label: label,
  steps: const [CustomKeyStep(type: CustomKeyStepType.text, value: 'x')],
);

String ckToken(String id) => 'ck:${id.substring(3)}';

Widget customHarness({
  bool directInput = false,
  bool cjkMode = false,
  bool keepKeyboardOnEnter = false,
  double width = 720,
  List<CustomKeyButton> customButtons = const [],
  List<String> row0Tokens = const <String>[],
  List<String>? row1Tokens,
  List<String>? row2Tokens,
  List<List<String>>? rows,
  void Function(CustomKeyButton)? onCustomButtonEdit,
  VoidCallback? onManageButtons,
  void Function(String)? onKeyPressed,
  void Function(String)? onSpecialKeyPressed,
  VoidCallback? onImagePickRequested,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          child: SpecialKeysBar(
            onKeyPressed: onKeyPressed ?? (_) {},
            onSpecialKeyPressed: onSpecialKeyPressed ?? (_) {},
            onInputTap: () {},
            onImagePickRequested: onImagePickRequested,
            onDirectInputToggle: () {},
            directInputEnabled: directInput,
            cjkMode: cjkMode,
            keepKeyboardOnEnter: keepKeyboardOnEnter,
            hapticFeedback: false,
            customButtons: customButtons,
            rows:
                rows ??
                [
                  row0Tokens,
                  row1Tokens ?? CustomKeyRows.standardRow1,
                  row2Tokens ?? CustomKeyRows.standardRow2,
                ],
            onCustomButtonEdit: onCustomButtonEdit,
            onManageButtons: onManageButtons,
          ),
        ),
      ),
    ),
  );
}

/// 直接入力フィールドの Finder（旧 group4/5 のローカル重複から一本化）。
Finder directInputField() => find.byType(TextField);

/// 入力欄からゼロ幅 sentinel（\u200B）を除いた可視テキストを返す。
String visibleText(WidgetTester tester) {
  final field = tester.widget<TextField>(directInputField());
  return field.controller!.text.replaceAll('\u200B', '');
}
