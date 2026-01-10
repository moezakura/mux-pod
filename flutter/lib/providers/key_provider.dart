import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/enums.dart';
import '../models/ssh_key.dart';
import '../services/keychain/key_generation.dart';
import '../services/keychain/key_import.dart';
import '../services/keychain/key_repository.dart';
import 'connection_provider.dart';

/// KeyRepository プロバイダー
final keyRepositoryProvider = Provider<KeyRepository>((ref) {
  return KeyRepository(
    storageService: ref.watch(storageServiceProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
});

/// KeyGenerationService プロバイダー
final keyGenerationServiceProvider = Provider<KeyGenerationService>((ref) {
  return KeyGenerationService();
});

/// KeyImportService プロバイダー
final keyImportServiceProvider = Provider<KeyImportService>((ref) {
  return KeyImportService();
});

/// SSH鍵一覧プロバイダー
final keysProvider = AsyncNotifierProvider<KeysNotifier, List<SSHKey>>(
  KeysNotifier.new,
);

/// SSH鍵Notifier
class KeysNotifier extends AsyncNotifier<List<SSHKey>> {
  @override
  Future<List<SSHKey>> build() async {
    return await _repository.getAll();
  }

  KeyRepository get _repository => ref.read(keyRepositoryProvider);
  KeyGenerationService get _generator => ref.read(keyGenerationServiceProvider);
  KeyImportService get _importer => ref.read(keyImportServiceProvider);

  /// 鍵生成
  Future<SSHKey> generate({
    required String name,
    required KeyType type,
    int? bits,
    String? passphrase,
    String comment = '',
  }) async {
    state = const AsyncValue.loading();

    try {
      // 鍵生成
      final result = switch (type) {
        KeyType.rsa => await _generator.generateRSA(
            bits: bits ?? 4096,
            passphrase: passphrase,
            comment: comment,
          ),
        KeyType.ed25519 => await _generator.generateEd25519(
            passphrase: passphrase,
            comment: comment,
          ),
        KeyType.ecdsa => await _generator.generateECDSA(
            passphrase: passphrase,
            comment: comment,
          ),
      };

      // SSHKey モデル作成
      final sshKey = SSHKey(
        id: const Uuid().v4(),
        name: name,
        type: type,
        bits: result.bits,
        fingerprint: result.fingerprint,
        publicKey: result.publicKeyOpenSSH,
        encrypted: passphrase != null && passphrase.isNotEmpty,
        createdAt: DateTime.now(),
      );

      // 保存
      await _repository.save(sshKey);
      await _repository.savePrivateKey(
        keyId: sshKey.id,
        privateKeyPem: result.privateKeyPem,
        passphrase: passphrase,
      );

      ref.invalidateSelf();
      return sshKey;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// 鍵インポート
  Future<SSHKey> import({
    required String name,
    required String privateKeyPem,
    String? passphrase,
  }) async {
    state = const AsyncValue.loading();

    try {
      // 秘密鍵をパース
      final result = await _importer.parsePrivateKey(
        privateKeyPem,
        passphrase: passphrase,
      );

      // SSHKey モデル作成
      final sshKey = SSHKey(
        id: const Uuid().v4(),
        name: name,
        type: result.type,
        bits: result.bits,
        fingerprint: result.fingerprint,
        publicKey: result.publicKeyOpenSSH,
        encrypted: result.isEncrypted,
        createdAt: DateTime.now(),
      );

      // 保存
      await _repository.save(sshKey);
      await _repository.savePrivateKey(
        keyId: sshKey.id,
        privateKeyPem: privateKeyPem,
        passphrase: passphrase,
      );

      ref.invalidateSelf();
      return sshKey;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// 鍵削除
  Future<void> delete(String id) async {
    await _repository.delete(id);
    ref.invalidateSelf();
  }

  /// デフォルト鍵設定
  Future<void> setDefault(String id) async {
    await _repository.setDefault(id);
    ref.invalidateSelf();
  }

  /// 鍵名変更
  Future<void> rename(String id, String newName) async {
    final key = await _repository.get(id);
    if (key != null) {
      await _repository.save(key.copyWith(name: newName));
      ref.invalidateSelf();
    }
  }

  /// 秘密鍵取得
  Future<String?> getPrivateKey(String keyId) async {
    return await _repository.getPrivateKey(keyId);
  }

  /// パスフレーズ取得
  Future<String?> getPassphrase(String keyId) async {
    return await _repository.getPassphrase(keyId);
  }

  /// 最終使用日時更新
  Future<void> updateLastUsed(String keyId) async {
    await _repository.updateLastUsed(keyId);
    ref.invalidateSelf();
  }
}

/// 単一鍵プロバイダー
final keyProvider = FutureProvider.family<SSHKey?, String>((ref, id) async {
  final repository = ref.watch(keyRepositoryProvider);
  return await repository.get(id);
});

/// デフォルト鍵プロバイダー
final defaultKeyProvider = FutureProvider<SSHKey?>((ref) async {
  final repository = ref.watch(keyRepositoryProvider);
  return await repository.getDefault();
});
