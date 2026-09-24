import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/batch_destination_picker_provider.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/file_browser_screen.dart';
import 'package:flutter_muxpod/services/download/batch_destination_picker.dart';
import 'package:flutter_muxpod/services/download/download_destination.dart';
import 'package:flutter_muxpod/services/download/save_as_exporter.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';

import '../../../helpers/fake_file_browser_notifier.dart';
import '../../../helpers/fake_settings_notifier.dart';
import '../../../helpers/fake_sftp_client.dart';
import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/fake_ssh_notifier.dart';

// P5: file browser download flow テストの harness（main() なし）。

class TestDownloadSftpClient extends FakeSftpClient {
  TestDownloadSftpClient({required super.contentsByPath});

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    final content = contentsByPath[path];
    if (content != null) {
      return SftpFileAttrs(
        mode: SftpFileMode.value(0x81A4),
        size: content.length,
        modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
      );
    }
    return super.stat(path, followLink: followLink);
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    return FakeSftpFile(this, contentsByPath[path] ?? Uint8List(0));
  }
}

FileEntry downloadEntry(String name) => FileEntry(
  name: name,
  fullPath: '/home/user/$name',
  isDirectory: false,
  size: 300,
);

class FakeBatchDestinationPicker implements BatchDestinationPicker {
  FakeBatchDestinationPicker({this.result});

  final DownloadDestination? result;
  int pickCalls = 0;

  @override
  Future<DownloadDestination?> pick() async {
    pickCalls++;
    return result;
  }
}

const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Future<void> settleTransfer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (const {
    DownloadPhase.idle,
    DownloadPhase.selecting,
    DownloadPhase.downloading,
    DownloadPhase.exporting,
  }.contains(container.read(downloadProvider).phase)) {
    if (sw.elapsed > timeout) {
      fail(
        'transfer did not settle: ${container.read(downloadProvider).phase}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  // 中間 completed の後に走る export（単一）やシートの自動クローズを確定させる。
  // export の継続は FakeAsync 外（runAsync 実ゾーン）で解決されるため複数回空回し。
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<ProviderContainer> pumpDownloadScreen(
  WidgetTester tester, {
  required FakeSshClient sshClient,
  required List<FileEntry> entries,
  required String appDocs,
  String? appTmp,
  BatchDestinationPicker? picker,
  SaveAsExporter? exporter,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocs;
        }
        if (call.method == 'getTemporaryDirectory') {
          return appTmp;
        }
        return null;
      });

  final container = ProviderContainer(
    overrides: [
      fileBrowserProvider.overrideWith(
        () => FakeFileBrowserNotifier(entries: entries),
      ),
      sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      settingsProvider.overrideWith(
        () => FakeSettingsNotifier(settings: const AppSettings()),
      ),
      if (picker != null)
        batchDestinationPickerProvider.overrideWithValue(picker),
      if (exporter != null)
        downloadProvider.overrideWith(
          () => DownloadNotifier(exporter: exporter),
        ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FileBrowserScreen(connectionId: 'test-conn'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> waitUntil(
  WidgetTester tester,
  ProviderContainer container,
  bool Function() condition,
) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail(
        'condition did not become true: ${container.read(downloadProvider).phase}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> waitForText(WidgetTester tester, String text) async {
  const timeout = Duration(seconds: 10);
  final sw = Stopwatch()..start();
  while (find.text(text).evaluate().isEmpty) {
    if (sw.elapsed > timeout) {
      fail('text "$text" did not appear');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// path_provider MethodChannel の mock 登録（旧 setUp 本文）。
void registerPathProviderChannel(String appDocs, String appTmp) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocs;
        }
        if (call.method == 'getTemporaryDirectory') {
          return appTmp;
        }
        return null;
      });
}

/// path_provider MethodChannel の mock 解除（旧 tearDown 本文）。
void unregisterPathProviderChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, null);
}
