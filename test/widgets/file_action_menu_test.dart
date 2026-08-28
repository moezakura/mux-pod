import 'package:flutter/material.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/screens/file_browser/widgets/file_action_menu.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// FileActionMenu の「ダウンロード」表示の Widget テスト。
///
/// 検証対象（実装計画 §L2-2 / Phase 3 #6・Pattern Map Concern 26）:
/// - ファイル: ダウンロード表示される
/// - ディレクトリ: ダウンロード非表示
/// - シンボリックリンク: ダウンロード非表示（一覧からの除外/選択不可と同等）
void main() {
  Future<void> pumpMenu(WidgetTester tester, FileEntry entry) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => FileActionMenu.show(context, entry),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('FileActionMenu download', () {
    testWidgets('ファイルで「ダウンロード」を表示する', (tester) async {
      const entry = FileEntry(
        name: 'report.pdf',
        fullPath: '/home/user/report.pdf',
        isDirectory: false,
        size: 1024,
      );
      await pumpMenu(tester, entry);

      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('ディレクトリでは「ダウンロード」を表示しない', (tester) async {
      const entry = FileEntry(
        name: 'docs',
        fullPath: '/home/user/docs',
        isDirectory: true,
      );
      await pumpMenu(tester, entry);

      expect(find.text('Download'), findsNothing);
    });

    testWidgets('シンボリックリンクでは「ダウンロード」を表示しない', (tester) async {
      const entry = FileEntry(
        name: 'link.txt',
        fullPath: '/home/user/link.txt',
        isDirectory: false,
        isSymlink: true,
      );
      await pumpMenu(tester, entry);

      expect(find.text('Download'), findsNothing);
    });
  });
}
