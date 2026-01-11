import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

import '../keychain/secure_storage.dart';

// Re-export BiometricType from local_auth for convenience
export 'package:local_auth/local_auth.dart' show BiometricType;

/// SSH認証方式
enum SshAuthMethod {
  /// パスワード認証
  password,

  /// 公開鍵認証
  publicKey,
}

/// 生体認証の結果
enum BiometricAuthResult {
  /// 成功
  success,

  /// キャンセル
  cancelled,

  /// 利用不可
  notAvailable,

  /// 未設定
  notEnrolled,

  /// ロックアウト（試行回数超過）
  lockedOut,

  /// 永続的ロックアウト
  permanentlyLockedOut,

  /// エラー
  error,
}

/// SSH認証資格情報
class SshCredential {
  /// 認証方式
  final SshAuthMethod method;

  /// パスワード（パスワード認証時）
  final String? password;

  /// 秘密鍵（公開鍵認証時）
  final String? privateKey;

  /// パスフレーズ（秘密鍵が暗号化されている場合）
  final String? passphrase;

  const SshCredential({
    required this.method,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  /// パスワード認証用
  const SshCredential.password(this.password)
      : method = SshAuthMethod.password,
        privateKey = null,
        passphrase = null;

  /// 公開鍵認証用
  const SshCredential.publicKey({
    required this.privateKey,
    this.passphrase,
  })  : method = SshAuthMethod.publicKey,
        password = null;

  /// 有効な資格情報かどうか
  bool get isValid {
    switch (method) {
      case SshAuthMethod.password:
        return password != null && password!.isNotEmpty;
      case SshAuthMethod.publicKey:
        return privateKey != null && privateKey!.isNotEmpty;
    }
  }
}

/// SSH認証サービス
///
/// 認証資格情報の管理と生体認証を提供する。
class SshAuthService {
  final SecureStorageService _storage;
  final LocalAuthentication _localAuth;

  /// 生体認証が必要かどうか（アプリ設定に依存）
  bool requireBiometricAuth = false;

  SshAuthService({
    SecureStorageService? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? SecureStorageService(),
        _localAuth = localAuth ?? LocalAuthentication();

  // ===== 資格情報の取得 =====

  /// 接続の認証資格情報を取得
  ///
  /// [connectionId] 接続ID
  /// [authMethod] 認証方式
  /// [keyId] 使用するSSH鍵のID（公開鍵認証時）
  Future<SshCredential?> getCredential({
    required String connectionId,
    required SshAuthMethod authMethod,
    String? keyId,
  }) async {
    // 生体認証が必要な場合
    if (requireBiometricAuth) {
      final bioResult = await authenticateWithBiometrics(
        reason: '認証情報にアクセスするために生体認証が必要です',
      );
      if (bioResult != BiometricAuthResult.success) {
        return null;
      }
    }

    switch (authMethod) {
      case SshAuthMethod.password:
        final password = await getPassword(connectionId);
        if (password == null) return null;
        return SshCredential.password(password);

      case SshAuthMethod.publicKey:
        if (keyId == null) return null;
        final privateKey = await getPrivateKey(keyId);
        if (privateKey == null) return null;
        final passphrase = await getPassphrase(keyId);
        return SshCredential.publicKey(
          privateKey: privateKey,
          passphrase: passphrase,
        );
    }
  }

  // ===== パスワード管理 =====

  /// パスワード認証の資格情報を取得
  Future<String?> getPassword(String connectionId) async {
    return _storage.getPassword(connectionId);
  }

  /// パスワードを保存
  Future<void> savePassword(String connectionId, String password) async {
    await _storage.savePassword(connectionId, password);
  }

  /// パスワードを削除
  Future<void> deletePassword(String connectionId) async {
    await _storage.deletePassword(connectionId);
  }

  /// パスワードが保存されているか確認
  Future<bool> hasPassword(String connectionId) async {
    final password = await getPassword(connectionId);
    return password != null && password.isNotEmpty;
  }

  // ===== SSH鍵管理 =====

  /// 秘密鍵を取得
  Future<String?> getPrivateKey(String keyId) async {
    return _storage.getPrivateKey(keyId);
  }

  /// 秘密鍵を保存
  Future<void> savePrivateKey(String keyId, String privateKey) async {
    await _storage.savePrivateKey(keyId, privateKey);
  }

  /// 秘密鍵を削除
  Future<void> deletePrivateKey(String keyId) async {
    await _storage.deletePrivateKey(keyId);
  }

  /// パスフレーズを取得
  Future<String?> getPassphrase(String keyId) async {
    return _storage.getPassphrase(keyId);
  }

  /// パスフレーズを保存
  Future<void> savePassphrase(String keyId, String passphrase) async {
    await _storage.savePassphrase(keyId, passphrase);
  }

  /// パスフレーズを削除
  Future<void> deletePassphrase(String keyId) async {
    await _storage.deletePassphrase(keyId);
  }

  /// 秘密鍵が保存されているか確認
  Future<bool> hasPrivateKey(String keyId) async {
    final key = await getPrivateKey(keyId);
    return key != null && key.isNotEmpty;
  }

  // ===== 生体認証 =====

  /// 生体認証が利用可能か確認
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// デバイスが生体認証をサポートしているか確認
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// 利用可能な生体認証の種類を取得
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// 生体認証を実行
  ///
  /// [reason] 認証理由（ユーザーに表示）
  Future<BiometricAuthResult> authenticateWithBiometrics({
    String reason = '認証してください',
  }) async {
    try {
      // 生体認証が利用可能か確認
      final canCheck = await canCheckBiometrics();
      final isSupported = await isDeviceSupported();

      if (!canCheck || !isSupported) {
        return BiometricAuthResult.notAvailable;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
      );

      return authenticated ? BiometricAuthResult.success : BiometricAuthResult.cancelled;
    } on PlatformException catch (e) {
      return _handleAuthError(e);
    }
  }

  /// 認証（生体認証またはデバイスPIN/パターン）
  ///
  /// 生体認証が利用できない場合、デバイスの認証（PIN/パターン等）にフォールバック
  Future<BiometricAuthResult> authenticate({
    String reason = '認証してください',
  }) async {
    try {
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        return BiometricAuthResult.notAvailable;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
      );

      return authenticated ? BiometricAuthResult.success : BiometricAuthResult.cancelled;
    } on PlatformException catch (e) {
      return _handleAuthError(e);
    }
  }

  /// 認証エラーをハンドル
  BiometricAuthResult _handleAuthError(PlatformException e) {
    // local_auth のエラーコードに基づいて結果を返す
    final code = e.code;
    if (code == 'NotEnrolled' || code == 'notEnrolled') {
      return BiometricAuthResult.notEnrolled;
    } else if (code == 'LockedOut' || code == 'lockedOut') {
      return BiometricAuthResult.lockedOut;
    } else if (code == 'PermanentlyLockedOut' || code == 'permanentlyLockedOut') {
      return BiometricAuthResult.permanentlyLockedOut;
    } else if (code == 'NotAvailable' || code == 'notAvailable') {
      return BiometricAuthResult.notAvailable;
    }
    return BiometricAuthResult.error;
  }

  /// 認証をキャンセル
  Future<bool> stopAuthentication() async {
    return _localAuth.stopAuthentication();
  }

  // ===== 接続資格情報の一括操作 =====

  /// 接続のすべての資格情報を削除
  Future<void> deleteConnectionCredentials(String connectionId) async {
    await deletePassword(connectionId);
  }

  /// SSH鍵のすべての資格情報を削除
  Future<void> deleteKeyCredentials(String keyId) async {
    await Future.wait([
      deletePrivateKey(keyId),
      deletePassphrase(keyId),
    ]);
  }

  /// すべての資格情報を削除
  Future<void> deleteAllCredentials() async {
    await _storage.deleteAll();
  }
}

/// ファクトリ関数
SshAuthService createSshAuthService({
  SecureStorageService? storage,
}) {
  return SshAuthService(storage: storage);
}
