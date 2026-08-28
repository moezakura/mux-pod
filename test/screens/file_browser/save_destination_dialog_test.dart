import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/widgets/save_destination_dialog.dart';

import '../../helpers/fake_settings_notifier.dart';

/// 保存先フォルダ選択ダイアログ（T9）の Widget テスト。
///
/// 検証対象（実装計画 §L2-2・Phase 4 #9）:
/// - Downloads 直下（既定）/ Documents 直下 / 新規サブフォルダの 3 選択肢表示
/// - AppSettings.downloadDirectory 設定時は設定パスが表示され初期選択
/// - キャンセル → null（保存先キャンセル → 転送開始しない）
/// - 確定 → 選択カテゴリのディレクトリパスが返る
/// - サブフォルダ作成失敗 → ダイアログ内エラー表示で導線を閉じない（再選択可）
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void mockPathProvider(String appDocsPath) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocsPath;
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });
}

/// ダイアログを表示し、その戻り値の Future を返す（操作後に await して検証する）。
Future<Future<String?>> pumpDialog(
  WidgetTester tester,
  ProviderContainer container, {
  required String appDocs,
}) async {
  mockPathProvider(appDocs);
  late Future<String?> future;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () {
                  future = showSaveDestinationDialog(context, ref);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return future;
}

Future<ProviderContainer> makeContainer({
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(settings: settings),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String appDocs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dl_dialog_');
    appDocs = '${tmp.path}/docs';
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // 削除失敗は検証対象外。
    }
  });

  group('showSaveDestinationDialog', () {
    testWidgets('3 選択肢を表示し事前選択は Downloads 直下（設定空）', (tester) async {
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: appDocs);

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      // 既定選択（Downloads 直下）にチェックが付いている
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ListTile &&
              w.selected &&
              w.title.toString().contains('Downloads'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('downloadDirectory 設定時は設定パスが表示され初期選択', (tester) async {
      final container = await makeContainer(
        settings: const AppSettings(downloadDirectory: '/mnt/custom/dl'),
      );
      await pumpDialog(tester, container, appDocs: appDocs);

      expect(find.text('/mnt/custom/dl'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ListTile &&
              w.selected &&
              w.title.toString().contains('/mnt/custom/dl'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('キャンセルで null が返る', (tester) async {
      final container = await makeContainer();
      final future = await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await future, isNull);
    });

    testWidgets('Downloads 直下を確定すると保存先が返りディレクトリも作成される', (tester) async {
      final container = await makeContainer();
      final future = await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await future, '$appDocs/downloads');
      expect(Directory('$appDocs/downloads').existsSync(), isTrue);
    });

    testWidgets('Documents 直下を選択して確定すると保存先が返りディレクトリも作成される', (tester) async {
      final container = await makeContainer();
      final future = await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('Documents'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await future, appDocs);
      expect(Directory(appDocs).existsSync(), isTrue);
    });

    testWidgets('新規サブフォルダ名で確定すると保存先が作成されパスが返る', (tester) async {
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('New folder'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'sub dir');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // ダイアログが閉じ、実際に保存先ディレクトリが作成されている。
      expect(find.text('New folder'), findsNothing);
      expect(Directory('$appDocs/downloads/sub dir').existsSync(), isTrue);
    });

    testWidgets('サブフォルダ作成失敗はエラー表示でダイアログを閉じない', (tester) async {
      // /proc 配下は書き込み不可 → Directory.create が失敗する（Linux テスト環境）。
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: '/proc');

      await tester.tap(find.text('New folder'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ng');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // エラー文言が表示され、ダイアログは維持される（再選択可）
      expect(find.text('Failed to create folder'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
    });

    testWidgets('サブフォルダ名が空の場合はエラーで確定しない', (tester) async {
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('New folder'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to create folder'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
    });

    testWidgets('サブフォルダ名が「..」の場合はエラーで確定しない（親ディレクトリ解決の防止・LOW#2）', (tester) async {
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('New folder'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '..');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // エラー表示でダイアログ維持（再選択可）・親ディレクトリへ解決されない（LOW#2）。
      expect(find.text('Failed to create folder'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      expect(Directory('$appDocs/downloads').existsSync(), isFalse);
      expect(Directory(appDocs).existsSync(), isFalse);
    });

    testWidgets('サブフォルダ名が「.」または空白のみの場合はエラーで確定しない（LOW#2）', (tester) async {
      final container = await makeContainer();
      await pumpDialog(tester, container, appDocs: appDocs);

      await tester.tap(find.text('New folder'));
      await tester.pump();

      // 「.」: 親ディレクトリ解決候補。
      await tester.enterText(find.byType(TextField), '.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to create folder'), findsOneWidget);

      // 空白のみ: trim 後に空 → エラー（既存挙動）。
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to create folder'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      expect(Directory('$appDocs/downloads').existsSync(), isFalse);
    });
  });
}