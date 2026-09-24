import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/markdown_preview_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';

import '../../../helpers/fake_sftp_client.dart';
import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/fake_ssh_notifier.dart';

// P5: MarkdownPreviewScreen テストの pump ヘルパーと fake（main() なし）。

/// 1x1 透明 PNG（Image.memory のデコード検証用・構造検証のための実バイト）。
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// open の呼び出しパスを記録する FakeSftpClient（SFTP 読込の範囲検証用）。
class RecordingSftpClient extends FakeSftpClient {
  final List<String> openedPaths = [];

  RecordingSftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openedPaths.add(path);
    return super.open(path, mode: mode);
  }
}

/// open 失敗→成功を切替できる FakeSftpClient（再試行テスト用）。

class FlakySftpClient extends FakeSftpClient {
  bool failOpen = true;

  FlakySftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    if (failOpen) throw Exception('sftp io failure');
    return super.open(path, mode: mode);
  }
}

/// 画面側 load 呼び出しを検証するためのスタブ Notifier（H-3 用）。
class FakeMarkdownPreviewNotifier extends MarkdownPreviewNotifier {
  FakeMarkdownPreviewNotifier(this._initial);

  final MarkdownPreviewState _initial;
  int loadCalls = 0;

  @override
  MarkdownPreviewState build() => _initial;

  @override
  Future<void> load({
    required String connectionId,
    required FileEntry entry,
  }) async {
    loadCalls++;
  }
}

FileEntry mdEntry({int? size, String path = '/home/user/docs/readme.md'}) {
  return FileEntry(
    name: path.split('/').last,
    fullPath: path,
    isDirectory: false,
    size: size,
  );
}

Uint8List bytes(String text) => utf8.encode(text);

/// 実 Provider 経由で画面を起動する（SFTP fixture は [sftpClient]）。
Future<FakeSshClient> pumpScreen(
  WidgetTester tester, {
  FakeSftpClient? sftpClient,
  FileEntry? entry,
  FakeSshClient? sshClient,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final client =
      sshClient ??
      (FakeSshClient()..sftpClient = sftpClient ?? FakeSftpClient());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MarkdownPreviewScreen(
          connectionId: 'conn1',
          entry: entry ?? mdEntry(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

/// スタブ Notifier（markdownPreviewProvider override）で画面を起動する。
Future<void> pumpScreenWithState(
  WidgetTester tester,
  MarkdownPreviewState state,
) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sshProvider.overrideWith(
          () => FakeSshNotifier(client: FakeSshClient()),
        ),
        markdownPreviewProvider.overrideWith(
          () => FakeMarkdownPreviewNotifier(state),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MarkdownPreviewScreen(connectionId: 'conn1', entry: mdEntry()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
