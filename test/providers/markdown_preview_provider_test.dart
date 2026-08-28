import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/markdown_preview_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connection_state.dart';

import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_notifier.dart';

/// open 呼び出しを数える FakeSftpClient（遷移前サイズ拒否の「SFTP 非アクセス」検証用）。
class _CountingSftpClient extends FakeSftpClient {
  int openCalls = 0;

  _CountingSftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openCalls++;
    return super.open(path, mode: mode);
  }
}

/// 初回の open のみ遅延させる FakeSftpClient（_readVersion stale 検証用）。
class _OnceDelayedSftpClient extends FakeSftpClient {
  final Completer<void> openGate = Completer<void>();
  int openCalls = 0;

  _OnceDelayedSftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    openCalls++;
    if (openCalls == 1) {
      await openGate.future;
    }
    return super.open(path, mode: mode);
  }
}

/// open で例外を投げる FakeSftpClient（IO エラー検証用）。
class _ThrowingSftpClient extends FakeSftpClient {
  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    throw Exception('sftp io failure');
  }
}

/// 内容は軽量のまま stat だけが上限超えを報告する FakeSftpClient
/// （stat 超過 → PreviewTooLargeException 検証用）。
class _StatOversizedSftpClient extends FakeSftpClient {
  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    return FakeSftpFile(
      this,
      contentsByPath[path] ?? Uint8List(0),
      size: maxPreviewBytes + 1,
    );
  }
}

/// stat() が size 不明（null）を返す FakeSftpFile（切詰め保険の発動条件）。
class _UnknownSizeFile extends FakeSftpFile {
  _UnknownSizeFile(super.client, super.content);

  @override
  Future<SftpFileAttrs> stat() async {
    return SftpFileAttrs(
      mode: SftpFileMode.value(0x81A4),
      size: null,
      modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
    );
  }
}

/// 常に size 不明の FakeSftpFile を返す FakeSftpClient（isTruncated 検証用）。
class _UnknownSizeSftpClient extends FakeSftpClient {
  _UnknownSizeSftpClient({super.contentsByPath});

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    return _UnknownSizeFile(this, contentsByPath[path] ?? Uint8List(0));
  }
}

FileEntry _mdEntry({int? size, String path = '/home/user/readme.md'}) {
  return FileEntry(
    name: path.split('/').last,
    fullPath: path,
    isDirectory: false,
    size: size,
  );
}

Uint8List _bytes(String text) => utf8.encode(text);

String _mdText() => '# Title\n\nHello **markdown**.\n\n- item1\n- item2\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({required FakeSshClient sshClient}) {
    final container = ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      ],
    );
    // isAutoDispose: true のプロバイダは購読が 0 になると破棄されるため、
    // テスト中は listen で保持する（riverpod の標準パターン）。
    container.listen(markdownPreviewProvider, (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  test('initial state uses defaults', () async {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final state = container.read(markdownPreviewProvider);
    expect(state.path, '');
    expect(state.content, '');
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.isTooLarge, isFalse);
    expect(state.isBinary, isFalse);
    expect(state.isTruncated, isFalse);
    expect(state.size, isNull);
  });

  test('load loads and decodes markdown text', () async {
    final sftpClient = FakeSftpClient(
      contentsByPath: {'/home/user/readme.md': _bytes(_mdText())},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry());

    final state = container.read(markdownPreviewProvider);
    expect(state.path, '/home/user/readme.md');
    expect(state.content, _mdText());
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.isBinary, isFalse);
    expect(state.isTooLarge, isFalse);
  });

  test(
    'load decodes japanese utf8 text without false binary detection',
    () async {
      const jpText = '# 日本語の見出し\n\nこれはテストです。\n- 箇条書き\n';
      final sftpClient = FakeSftpClient(
        contentsByPath: {'/home/user/readme.md': _bytes(jpText)},
      );
      final sshClient = FakeSshClient()..sftpClient = sftpClient;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      await container
          .read(markdownPreviewProvider.notifier)
          .load(connectionId: 'conn1', entry: _mdEntry());

      final state = container.read(markdownPreviewProvider);
      expect(state.isBinary, isFalse);
      expect(state.content, jpText);
    },
  );

  test('load detects binary content and does not decode', () async {
    // 先頭ブロック（8KB）内に NUL を含む疑似 .md
    final binary = Uint8List.fromList([
      ...utf8.encode('# fake md\n'),
      0x00,
      0x01,
      0x02,
      0x03,
    ]);
    final sftpClient = FakeSftpClient(
      contentsByPath: {'/home/user/readme.md': binary},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry());

    final state = container.read(markdownPreviewProvider);
    expect(state.isBinary, isTrue);
    expect(state.content, isEmpty); // decode されない
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
  });

  test(
    'load rejects entry.size over maxPreviewBytes without sftp access',
    () async {
      final sftpClient = _CountingSftpClient(
        contentsByPath: {'/home/user/readme.md': _bytes(_mdText())},
      );
      final sshClient = FakeSshClient()..sftpClient = sftpClient;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      const oversize = maxPreviewBytes + 1; // 21MB 相当
      await container
          .read(markdownPreviewProvider.notifier)
          .load(
            connectionId: 'conn1',
            entry: _mdEntry(size: oversize),
          );

      final state = container.read(markdownPreviewProvider);
      expect(state.isTooLarge, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.content, isEmpty);
      expect(state.size, (oversize / (1024 * 1024)).ceil()); // 21
      expect(sftpClient.openCalls, 0); // SFTP に一切触れない（H-3）
    },
  );

  test('load sets isTooLarge when stat().size exceeds limit', () async {
    // entry.size は不明（null）だが、open 後の stat が 20MB 超を報告する
    final sftpClient = _StatOversizedSftpClient();
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry()); // size 不明

    final state = container.read(markdownPreviewProvider);
    expect(state.isTooLarge, isTrue);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.size, ((maxPreviewBytes + 1) / (1024 * 1024)).ceil()); // 21
  });

  test('load reports isTruncated for unknown-size oversized file', () async {
    // 20MB+1 バイト（'a' 埋め）。stat は size 不明 → 切詰め保険が発動する
    final bigContent = Uint8List(maxPreviewBytes + 1)
      ..fillRange(0, maxPreviewBytes + 1, 0x61);
    final sftpClient = _UnknownSizeSftpClient(
      contentsByPath: {'/home/user/readme.md': bigContent},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry()); // size 不明

    final state = container.read(markdownPreviewProvider);
    expect(state.isTruncated, isTrue);
    expect(state.isTooLarge, isFalse);
    expect(state.isBinary, isFalse);
    expect(state.content.length, maxPreviewBytes + 1);
  });

  test('load catches sftp io error and sets mdLoadFailed', () async {
    final sftpClient = _ThrowingSftpClient();
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry());

    final state = container.read(markdownPreviewProvider);
    expect(state.error, isNotNull);
    expect(state.error, contains('sftp io failure')); // mdLoadFailed ラップ
    expect(state.isLoading, isFalse);
    expect(state.isTooLarge, isFalse);
  });

  test('_readVersion discards stale results on consecutive loads', () async {
    final sftpClient = _OnceDelayedSftpClient(
      contentsByPath: {'/home/user/readme.md': _bytes('# slow\n')},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    final notifier = container.read(markdownPreviewProvider.notifier);

    // 1 回目: open が遅延 → 後に stale となる
    final firstLoad = notifier.load(connectionId: 'conn1', entry: _mdEntry());
    // 2 回目: 直ちに完了（勝ち残る）
    sftpClient.contentsByPath['/home/user/readme.md'] = _bytes('# fast\n');
    await notifier.load(connectionId: 'conn1', entry: _mdEntry());

    // 1 回目を解放（stale・破棄されるはず）
    sftpClient.openGate.complete();
    await firstLoad;

    final state = container.read(markdownPreviewProvider);
    expect(state.content, '# fast\n');
    expect(state.content, isNot(contains('slow')));
    expect(state.isLoading, isFalse);
  });

  test('connection loss sets mdSshLost error', () async {
    final sftpClient = FakeSftpClient(
      contentsByPath: {'/home/user/readme.md': _bytes(_mdText())},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry());

    sshClient.setConnected(SshConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(markdownPreviewProvider);
    expect(state.error, 'SSH connection lost'); // mdSshLost・テスト環境は en
    expect(state.isLoading, isFalse);
  });

  test('dispose cancels connection subscription', () async {
    final sftpClient = FakeSftpClient(
      contentsByPath: {'/home/user/readme.md': _bytes(_mdText())},
    );
    final sshClient = FakeSshClient()..sftpClient = sftpClient;
    // 手動 dispose のため makeContainer は使わず直接構築する
    final container = ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
      ],
    );
    container.listen(markdownPreviewProvider, (_, _) {});

    await container
        .read(markdownPreviewProvider.notifier)
        .load(connectionId: 'conn1', entry: _mdEntry());

    container.dispose();

    // 購読が解除されていれば、dispose 後の setConnected でも例外は出ない
    // （解除漏れがあれば listener が破棄済み state を書き換えようとして throw する）
    sshClient.setConnected(SshConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
  });
}
