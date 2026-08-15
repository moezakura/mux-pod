// Repro: ホスト鍵フィンガープリント形式変更で SSH 接続が失敗する
//
// dartssh2 2.18.0 で BREAKING: SSHHostkeyVerifyHandler に渡される
// fingerprint が「MD5 生バイト」から「OpenSSH 形式 `SHA256:<base64>` 文字列の
// UTF-8 バイト」に変更された（dartssh2 CHANGELOG 2.18.0）。
//
// アプリ側 _onVerifyHostKey（lib/services/ssh/ssh_client.dart）は MD5 生バイト
// 前提で hex 連結していたため、dartssh2 2.22.5 では旧形式保存値（MD5 hex）と
// 決して一致せず、ホスト鍵検証失敗 → 接続不可となっていた（ユーザー報告:
// SSH接続ができなくなった・認証が通らない）。
//
// 修正方針（ユーザー承認済み）: 旧形式保存値は「接続実績のあるサーバー」として
// 受理し、**ユーザー認証成功後にのみ**正規の SHA256 形式へ更新する。
//
// このテストはローカル sshd（127.0.0.1:22）に対する実接続で検証する。
// 前提:
//   - ローカル sshd が ed25519 ホスト鍵で稼働している
//   - /tmp/bugfix-repro-key の公開鍵が authorized_keys に登録されている
//   - /tmp/bugfix-repro-key-wrong は authorized_keys に未登録（認証失敗用）
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// ローカル sshd の ed25519 ホスト鍵 blob（KEX で渡される host key そのもの）。
Uint8List _localHostKeyBlob() {
  final pubLine = File(
    '/etc/ssh/ssh_host_ed25519_key.pub',
  ).readAsLinesSync().first;
  return base64.decode(pubLine.split(' ')[1]);
}

/// 旧 dartssh2（<= 2.17）が onVerifyHostKey に渡していた MD5 生バイトを
/// アプリの hex 連結形式にしたもの = 旧バージョンで保存された値。
String _legacyFingerprint() {
  return md5
      .convert(_localHostKeyBlob())
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':');
}

/// ローカル sshd の正規（SHA256）フィンガープリント。
String _sha256Fingerprint() {
  final digest = sha256.convert(_localHostKeyBlob()).bytes;
  final encoded = base64Encode(digest).replaceAll('=', '');
  return 'SHA256:$encoded';
}

void main() {
  setUp(() => SecureStorageService.setTestValues({}));
  tearDown(() => SecureStorageService.setTestValues(null));

  test(
    'REPRO: 対照実験 - 保存済みフィンガープリントなし（新規）なら接続できる',
    () async {
      final privateKey = File('/tmp/bugfix-repro-key').readAsStringSync();
      final client = SshClient();
      await client.connect(
        host: '127.0.0.1',
        port: 22,
        username: Platform.environment['USER'] ?? 'mox',
        options: SshConnectOptions(privateKey: privateKey),
        lightweight: true,
      );
      expect(client.isConnected, isTrue);
      await client.disconnect();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'REPRO: 旧形式（MD5 hex）保存済みでも接続でき、認証成功後に SHA256 へ更新される',
    () async {
      // 旧バージョンで接続済みのユーザーの保存済みフィンガープリントを再現
      SecureStorageService.setTestValues({
        'hostkey_127.0.0.1_22_ssh-ed25519': _legacyFingerprint(),
      });

      final privateKey = File('/tmp/bugfix-repro-key').readAsStringSync();
      final client = SshClient();
      await client.connect(
        host: '127.0.0.1',
        port: 22,
        username: Platform.environment['USER'] ?? 'mox',
        options: SshConnectOptions(privateKey: privateKey),
        lightweight: true,
      );
      // 修正後: ホスト鍵検証が通って接続できる
      expect(client.isConnected, isTrue);
      // 認証成功後に正規の SHA256 形式へ更新されている
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          '127.0.0.1',
          22,
          'ssh-ed25519',
        ),
        _sha256Fingerprint(),
      );
      await client.disconnect();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'REPRO: 旧形式保存済みでも認証失敗時は SHA256 へ更新されない',
    () async {
      SecureStorageService.setTestValues({
        'hostkey_127.0.0.1_22_ssh-ed25519': _legacyFingerprint(),
      });

      // authorized_keys に未登録の鍵で認証を失敗させる
      final wrongKey = File('/tmp/bugfix-repro-key-wrong').readAsStringSync();
      final client = SshClient();
      await expectLater(
        client.connect(
          host: '127.0.0.1',
          port: 22,
          username: Platform.environment['USER'] ?? 'mox',
          options: SshConnectOptions(privateKey: wrongKey),
          lightweight: true,
        ),
        throwsA(isA<SshAuthenticationError>()),
      );
      // 認証失敗時は保存値が更新されない（旧形式のまま）
      expect(
        await SecureStorageService().getHostKeyFingerprint(
          '127.0.0.1',
          22,
          'ssh-ed25519',
        ),
        _legacyFingerprint(),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
