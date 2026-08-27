import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/image_transfer_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connection_state.dart';
import 'package:flutter_muxpod/widgets/image_transfer_confirm_dialog.dart';

import '../helpers/fake_settings_notifier.dart';
import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_notifier.dart';

/// [ImageTransferNotifier] を確認状態（phase=confirming）に直接遷移させるテスト用サブクラス。
///
/// 実 SFTP 経路（SftpService.upload → FakeSftpClient）を通すため、
/// terminal_test_scaffold の FakeImageTransferNotifier（実 SFTP をバイパス）は使わない。
class _TestImageTransferNotifier extends ImageTransferNotifier {
  void setConfirming({
    required Uint8List bytes,
    required String name,
    required String remotePath,
  }) {
    state = ImageTransferState(
      phase: ImageTransferPhase.confirming,
      pickedImageBytes: bytes,
      pickedImageName: name,
      pendingRemotePath: remotePath,
    );
  }
}

/// [FakeSftpClient] を拡張し、open() で生成した [FakeSftpFile] を記録するテスト用クライアント。
///
/// 成功パスの「ファイルハンドル close は正常（closeCalls==1）」を検証するため、
/// 最後に open した [FakeSftpFile] を公開する。
class _RecordingSftpClient extends FakeSftpClient {
  FakeSftpFile? lastOpened;

  _RecordingSftpClient({super.contentsByPath, super.homeDirectory});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    final file = await super.open(path, mode: mode) as FakeSftpFile;
    lastOpened = file;
    return file;
  }
}

/// open() を throw して upload を失敗させるテスト用クライアント。
class _ThrowingSftpClient extends FakeSftpClient {
  _ThrowingSftpClient({super.contentsByPath, super.homeDirectory});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    throw SftpStatusError(SftpStatusCode.failure, 'boom');
  }
}

ImageTransferOptions _originalOptions({
  String remotePath = '/tmp/muxpod/img.png',
}) {
  return ImageTransferOptions(
    remotePath: remotePath,
    outputFormat: 'original',
    jpegQuality: 85,
    resizePreset: ImageResizePreset.original,
    customMaxWidth: 0,
    customMaxHeight: 0,
    pathFormat: 'default',
    autoEnter: false,
    bracketedPaste: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({required FakeSshClient sshClient}) {
    return ProviderContainer(
      overrides: [
        // FakeSshClient を注入し、既存 file_browser_provider_test と同じ配線にする。
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
        settingsProvider.overrideWith(FakeSettingsNotifier.new),
        imageTransferProvider.overrideWith(_TestImageTransferNotifier.new),
      ],
    );
  }

  group('image_transfer_provider', () {
    test('upload 成功: クライアント closeCalls==0・ファイル closeCalls==1', () async {
      final sshClient = FakeSshClient();
      // アップロード先ディレクトリが stat 成功 / open で内容を返すように設定。
      final sftp = _RecordingSftpClient(
        homeDirectory: '/tmp/muxpod',
        contentsByPath: {'/tmp/muxpod/img.png': Uint8List(0)},
      );
      sshClient.sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      final notifier =
          container.read(imageTransferProvider.notifier)
              as _TestImageTransferNotifier;
      notifier.setConfirming(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        name: 'img.png',
        remotePath: '/tmp/muxpod/img.png',
      );

      final result = await notifier.confirmAndUpload(
        options: _originalOptions(),
      );

      expect(result, '/tmp/muxpod/img.png');
      expect(notifier.state.phase, ImageTransferPhase.completed);
      // クライアント close 禁止契約: sftp.close() は呼ばれない。
      expect(sftp.closeCalls, 0);
      // ファイルハンドル close は正常（SftpService.upload の finally で 1 回）。
      expect(sftp.lastOpened, isNotNull);
      expect(sftp.lastOpened!.closeCalls, 1);
    });

    test('連続 upload でもクライアント closeCalls==0 維持', () async {
      final sshClient = FakeSshClient();
      final sftp = _RecordingSftpClient(
        homeDirectory: '/tmp/muxpod',
        contentsByPath: {'/tmp/muxpod/a.png': Uint8List(0)},
      );
      sshClient.sftpClient = sftp;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      final notifier =
          container.read(imageTransferProvider.notifier)
              as _TestImageTransferNotifier;

      for (var i = 0; i < 2; i++) {
        notifier.setConfirming(
          bytes: Uint8List.fromList([i + 1]),
          name: 'a.png',
          remotePath: '/tmp/muxpod/a.png',
        );
        await notifier.confirmAndUpload(options: _originalOptions());
        // completed に遷移し reset で次が可能
        expect(notifier.state.phase, ImageTransferPhase.completed);
        notifier.reset();
      }

      expect(sftp.closeCalls, 0);
    });

    test('upload 失敗: 部分削除（removeCalls 記録）・クライアント closeCalls==0', () async {
      final sshClient = FakeSshClient();
      final failingClient = _ThrowingSftpClient(
        homeDirectory: '/tmp/muxpod',
        contentsByPath: {'/tmp/muxpod/img.png': Uint8List(0)},
      );
      sshClient.sftpClient = failingClient;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      final notifier =
          container.read(imageTransferProvider.notifier)
              as _TestImageTransferNotifier;
      notifier.setConfirming(
        bytes: Uint8List.fromList([9, 9]),
        name: 'img.png',
        remotePath: '/tmp/muxpod/img.png',
      );

      final result = await notifier.confirmAndUpload(
        options: _originalOptions(),
      );

      expect(result, isNull);
      expect(notifier.state.phase, ImageTransferPhase.error);
      expect(failingClient.closeCalls, 0);
      // SftpService.upload の catch が部分削除として remove を呼ぶ。
      expect(failingClient.removeCalls, contains('/tmp/muxpod/img.png'));
    });

    test('SSH 未接続: error 遷移・closeCalls==0', () async {
      final sshClient = FakeSshClient();
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      // 未接続状態にする。
      sshClient.setConnected(SshConnectionState.disconnected);

      final notifier =
          container.read(imageTransferProvider.notifier)
              as _TestImageTransferNotifier;
      notifier.setConfirming(
        bytes: Uint8List.fromList([1]),
        name: 'img.png',
        remotePath: '/tmp/muxpod/img.png',
      );

      final result = await notifier.confirmAndUpload(
        options: _originalOptions(),
      );

      expect(result, isNull);
      expect(notifier.state.phase, ImageTransferPhase.error);
      expect(sshClient.sftpClient.closeCalls, 0);
    });
  });
}
