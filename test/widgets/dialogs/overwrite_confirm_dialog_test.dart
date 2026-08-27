import 'package:flutter/material.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/sftp/overwrite_choice.dart';
import 'package:flutter_muxpod/widgets/dialogs/overwrite_confirm_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 上書き確認ダイアログの共通ウィジェットテスト。
///
/// 検証対象（実装計画 §L2-1-c DoD / T1）:
/// - batch モード: 上書き / リネーム / スキップ 表示 + applyToAll チェック
/// - single モード: 上書き / リネーム / キャンセル 表示
/// - 結果値（choice / applyToAll）の検証
/// - barrier dismiss = null（操作中断）
///
/// ボタン文言は l10n getter（AppLocalizations.fileSkipAction 等）から
/// 取得して検索する（l10n 文言の変更に追従するため・文言直書きにしない）。
void main() {
  // ダイアログを表示し、その l10n を返す
  Future<AppLocalizations> pumpDialog(
    WidgetTester tester, {
    OverwriteDialogMode mode = OverwriteDialogMode.single,
    bool showApplyToAll = false,
    String fileName = 'report.pdf',
    void Function(OverwriteConfirmResult? result)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showOverwriteConfirmDialog(
                  context,
                  fileName: fileName,
                  mode: mode,
                  showApplyToAll: showApplyToAll,
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(AlertDialog));
    return AppLocalizations.of(ctx);
  }

  group('batch モード（#40 用）', () {
    testWidgets('上書き/リネーム/スキップの3ボタンとapplyToAll表示', (tester) async {
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.batch, showApplyToAll: true);

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.widgetWithText(TextButton, l10n.fileSkipAction), findsOneWidget);
      expect(find.widgetWithText(TextButton, l10n.fileRenameAction), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.fileOverwriteAction), findsOneWidget);
    });

    testWidgets('skip選択で choice=skip が返る', (tester) async {
      OverwriteConfirmResult? result;
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.batch,
          showApplyToAll: true,
          onResult: (r) => result = r);

      await tester.tap(find.widgetWithText(TextButton, l10n.fileSkipAction));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, OverwriteChoice.skip);
      expect(result!.applyToAll, isFalse);
    });

    testWidgets('skip選択＋applyToAllチェックで choice=skip・applyToAll=true', (tester) async {
      OverwriteConfirmResult? result;
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.batch,
          showApplyToAll: true,
          onResult: (r) => result = r);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.fileSkipAction));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, OverwriteChoice.skip);
      expect(result!.applyToAll, isTrue);
    });

    testWidgets('rename選択で choice=rename', (tester) async {
      OverwriteConfirmResult? result;
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.batch,
          onResult: (r) => result = r);

      await tester.tap(find.widgetWithText(TextButton, l10n.fileRenameAction));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, OverwriteChoice.rename);
    });
  });

  group('single モード（#41 用）', () {
    testWidgets('上書き/リネーム/キャンセル表示・applyToAll非表示', (tester) async {
      final l10n = await pumpDialog(tester, mode: OverwriteDialogMode.single);

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.widgetWithText(TextButton, l10n.commonCancel), findsOneWidget);
      expect(find.widgetWithText(TextButton, l10n.fileRenameAction), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.fileOverwriteAction), findsOneWidget);
    });

    testWidgets('cancel選択で choice=cancel', (tester) async {
      OverwriteConfirmResult? result;
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.single, onResult: (r) => result = r);

      await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, OverwriteChoice.cancel);
    });

    testWidgets('rename選択で choice=rename', (tester) async {
      OverwriteConfirmResult? result;
      final l10n = await pumpDialog(tester,
          mode: OverwriteDialogMode.single, onResult: (r) => result = r);

      await tester.tap(find.widgetWithText(TextButton, l10n.fileRenameAction));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, OverwriteChoice.rename);
    });

    testWidgets('barrier dismiss で null（操作中断）', (tester) async {
      OverwriteConfirmResult? result;
      await pumpDialog(tester,
          mode: OverwriteDialogMode.single, onResult: (r) => result = r);

      // barrier（ダイアログ外・画面左上）をタップして dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
