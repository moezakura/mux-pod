import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_sftp_client.dart';
import '../../helpers/fake_ssh_client.dart';
import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/fake_tmux_notifier.dart';

/// テスト用の [PlatformFile] 実装。
base class FakePlatformFile extends PlatformFile {
  @override
  final String name;

  @override
  final Uri uri;

  final Uint8List content;

  FakePlatformFile(this.name, {List<int>? content})
    : content = Uint8List.fromList(content ?? const []),
      uri = Uri.file('/local/$name');

  @override
  XFile get xFile => XFile.fromData(content, name: name);

  @override
  Future<int> length() async => content.length;

  @override
  Future<Uint8List> readAsBytes() async => content;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(content);
}

/// 読み込みストリームを外部制御する [PlatformFile]。
base class ControlledPlatformFile extends FakePlatformFile {
  final StreamController<Uint8List> controller = StreamController();

  ControlledPlatformFile(super.name);

  @override
  Stream<Uint8List> readAsByteStream() => controller.stream;
}

/// pickFiles が固定リストを返す fake プラットフォーム。
class FakeFilePickerPlatform extends FilePickerPlatform {
  List<PlatformFile> filesToReturn = [];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = true,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    Object? androidSafOptions,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return filesToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFilePickerPlatform picker;
  late FakeSshClient ssh;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    picker = FakeFilePickerPlatform();
    FilePickerPlatform.instance = picker;
    ssh = FakeSshClient();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sshProvider.overrideWith(() => FakeSshNotifier(client: ssh)),
          tmuxProvider.overrideWith(
            () => FakeTmuxNotifier(initialState: const TmuxState()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FileBrowserScreen(connectionId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('アップロードボタンが表示される', (tester) async {
    await pumpScreen(tester);
    expect(find.byTooltip('アップロード'), findsOneWidget);
  });

  testWidgets('衝突なし: 選択→転送→成功SnackBarにリモートパスが出る', (tester) async {
    await pumpScreen(tester);
    picker.filesToReturn = [
      FakePlatformFile('a.txt', content: [1, 2, 3]),
    ];

    await tester.tap(find.byTooltip('アップロード'));
    await tester.pumpAndSettle();

    // 初期ディレクトリはホーム（FakeSshClient の SFTP fake のホーム）
    expect(find.text('/home/user/a.txt にアップロードしました'), findsOneWidget);
    expect(ssh.sftpClient.openedFiles, hasLength(1));
    expect(ssh.sftpClient.openedFiles.single.content, [1, 2, 3]);
    expect(ssh.sftpClient.removeCalls, isEmpty);
  });

  testWidgets('衝突あり: 上書き確認ダイアログ→上書きで元名転送', (tester) async {
    ssh.sftpClient = FakeSftpClient(entriesByPath: {'/home/user/a.txt': []});
    await pumpScreen(tester);
    picker.filesToReturn = [
      FakePlatformFile('a.txt', content: [9]),
    ];

    await tester.tap(find.byTooltip('アップロード'));
    await tester.pumpAndSettle();

    // 基盤の上書き確認ダイアログ（single モード）
    expect(find.text('ファイルが既に存在します'), findsOneWidget);
    expect(find.text('上書き'), findsOneWidget);
    expect(find.text('リネーム'), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);

    await tester.tap(find.text('上書き'));
    await tester.pumpAndSettle();

    expect(find.text('/home/user/a.txt にアップロードしました'), findsOneWidget);
    expect(ssh.sftpClient.openedFiles, hasLength(1));
  });

  testWidgets('衝突あり: リネームでユニーク名転送', (tester) async {
    ssh.sftpClient = FakeSftpClient(entriesByPath: {'/home/user/a.txt': []});
    await pumpScreen(tester);
    picker.filesToReturn = [
      FakePlatformFile('a.txt', content: [9]),
    ];

    await tester.tap(find.byTooltip('アップロード'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('リネーム'));
    await tester.pumpAndSettle();

    // ユニーク名（a_YYYYMMDD_HHMMSS_xxxx.txt）で転送される
    final snackBarText = tester
        .widget<SnackBar>(find.byType(SnackBar))
        .content
        .toString();
    expect(
      RegExp(
        r'a_\d{8}_\d{6}_[a-f0-9]{4}\.txt にアップロードしました',
      ).hasMatch(snackBarText),
      isTrue,
      reason: 'SnackBar: $snackBarText',
    );
    expect(ssh.sftpClient.openedFiles, hasLength(1));
  });

  testWidgets('衝突あり: キャンセルで中止し転送しない', (tester) async {
    ssh.sftpClient = FakeSftpClient(entriesByPath: {'/home/user/a.txt': []});
    await pumpScreen(tester);
    picker.filesToReturn = [
      FakePlatformFile('a.txt', content: [9]),
    ];

    await tester.tap(find.byTooltip('アップロード'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('アップロードをキャンセルしました'), findsOneWidget);
    expect(ssh.sftpClient.openedFiles, isEmpty);
  });

  testWidgets('転送中: 進捗パネルとキャンセルボタンが表示される', (tester) async {
    await pumpScreen(tester);
    final controlled = ControlledPlatformFile('big.bin');
    picker.filesToReturn = [controlled];

    await tester.tap(find.byTooltip('アップロード'));
    // 進捗パネルの CircularProgressIndicator は無限アニメーションのため
    // pumpAndSettle ではなく pump で進める。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 転送を保留した状態でパネル・キャンセル導線が表示される
    expect(find.text('すべてキャンセル'), findsOneWidget);
    expect(find.text('big.bin'), findsOneWidget);

    // 保留していたストリームを完結させると通常転送として終了する
    // （キャンセル伝播の非同期フロー自体は provider テストで検証済み）
    controlled.controller.add(Uint8List.fromList(List.filled(10, 1)));
    await controlled.controller.close();
    await tester.pumpAndSettle();

    expect(ssh.sftpClient.openedFiles.single.content, hasLength(10));
    expect(find.text('/home/user/big.bin にアップロードしました'), findsOneWidget);
    // 完了後はパネルが消える
    expect(find.text('すべてキャンセル'), findsNothing);
  });
}
