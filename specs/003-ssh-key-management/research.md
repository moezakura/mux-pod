# Research: SSH鍵管理機能

**Feature**: 003-ssh-key-management
**Date**: 2026-01-11

## Research Tasks

### 1. SSH鍵生成ライブラリの選定

**Question**: Dart/FlutterでEd25519/RSA鍵ペアを生成するには？

**Decision**: `cryptography`パッケージ（Ed25519）と `pointycastle`パッケージ（RSA）を使用

**Rationale**:
- `dartssh2`は鍵のパース/ロードのみサポートし、生成機能はない
- `cryptography`はEd25519をネイティブサポート、クロスプラットフォーム対応
- `pointycastle`はRSA鍵生成の実績あり、Pure Dartで依存関係なし

**Alternatives Considered**:

| パッケージ | 評価 | 却下理由 |
|-----------|------|----------|
| `ed25519_dart` | △ | Ed25519のみ、メンテナンス不活発 |
| `basic_utils` | △ | RSAのみ、API複雑 |
| `cryptography` | ✅ | Ed25519対応、アクティブメンテナンス |
| `pointycastle` | ✅ | RSA対応、広く使用されている |

**Implementation Notes**:
```dart
// Ed25519 using cryptography package
import 'package:cryptography/cryptography.dart';

final ed25519 = Ed25519();
final keyPair = await ed25519.newKeyPair();
final privateKey = await keyPair.extractPrivateKeyBytes();
final publicKey = await keyPair.extractPublicKey();

// RSA using pointycastle
import 'package:pointycastle/export.dart';

final keyGen = RSAKeyGenerator()
  ..init(ParametersWithRandom(
    RSAKeyGeneratorParameters(BigInt.parse('65537'), 4096, 64),
    secureRandom,
  ));
final pair = keyGen.generateKeyPair();
```

---

### 2. ファイルピッカーの選定

**Question**: AndroidでSSH秘密鍵ファイルを選択するには？

**Decision**: `file_picker`パッケージを使用

**Rationale**:
- pub.devで最も人気（5000+ likes）
- Android/iOS/Web/Desktop対応
- シンプルなAPI、拡張子フィルタリング対応
- アクティブにメンテナンスされている

**Alternatives Considered**:

| パッケージ | 評価 | 却下理由 |
|-----------|------|----------|
| `native_file_picker` | △ | 新しい、実績少ない |
| `filesystem_picker` | △ | ディレクトリ選択向け |
| `file_picker` | ✅ | 実績豊富、APIシンプル |

**Implementation Notes**:
```dart
import 'package:file_picker/file_picker.dart';

// 秘密鍵ファイル選択
FilePickerResult? result = await FilePicker.platform.pickFiles(
  type: FileType.any,  // SSH鍵は拡張子なしの場合あり
  allowMultiple: false,
);

if (result != null && result.files.single.path != null) {
  final file = File(result.files.single.path!);
  final content = await file.readAsString();
  // PEM形式かどうか検証
}
```

---

### 3. 秘密鍵のPEM形式パース

**Question**: インポートされた秘密鍵をどうパースするか？

**Decision**: `dartssh2`の`SSHKeyPair.fromPem()`を活用

**Rationale**:
- 既存依存関係で対応可能
- OpenSSH形式・PEM形式両方サポート
- パスフレーズ付き鍵の復号もサポート

**Implementation Notes**:
```dart
import 'package:dartssh2/dartssh2.dart';

// 暗号化チェック
final isEncrypted = SSHKeyPair.isEncryptedPem(pemContent);

// パース
final keyPair = SSHKeyPair.fromPem(
  pemContent,
  passphrase: isEncrypted ? userPassphrase : null,
);

// 鍵タイプ取得
final keyType = keyPair.type; // 'ssh-ed25519', 'ssh-rsa', etc.
```

---

### 4. PEM形式での鍵エクスポート

**Question**: 生成した鍵をPEM形式で保存するには？

**Decision**: OpenSSH形式のPEMを手動で構築

**Rationale**:
- `cryptography`や`pointycastle`はPEM出力を直接サポートしない
- OpenSSH形式が標準的で、他ツールとの互換性が高い

**Implementation Notes**:
```dart
// Ed25519の場合
String toPem(Uint8List privateKey, Uint8List publicKey) {
  // OpenSSH形式のPEM構造を構築
  // - "-----BEGIN OPENSSH PRIVATE KEY-----"
  // - Base64エンコードされたバイナリデータ
  // - "-----END OPENSSH PRIVATE KEY-----"
}

// 公開鍵はauthorized_keys形式
String toAuthorizedKeys(String type, Uint8List publicKey, String comment) {
  return '$type ${base64Encode(publicKey)} $comment';
}
```

---

### 5. フィンガープリント計算

**Question**: 鍵のフィンガープリントをどう計算するか？

**Decision**: SHA-256ハッシュを使用（OpenSSH標準）

**Rationale**:
- OpenSSH 6.8以降のデフォルト
- MD5より安全性が高い

**Implementation Notes**:
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

String calculateFingerprint(Uint8List publicKeyBlob) {
  final hash = sha256.convert(publicKeyBlob);
  return 'SHA256:${base64Encode(hash.bytes).replaceAll('=', '')}';
}
```

---

## Dependencies to Add

```yaml
# pubspec.yaml に追加
dependencies:
  file_picker: ^8.0.3
  cryptography: ^2.7.0
  pointycastle: ^3.9.1
```

## Security Considerations

1. **秘密鍵の扱い**:
   - メモリ上での保持を最小限に
   - ログ出力に鍵データを含めない
   - 使用後は変数をクリア

2. **パスフレーズの扱い**:
   - flutter_secure_storageに暗号化保存
   - UIでの表示はマスク処理

3. **一時ファイル**:
   - ファイルピッカー経由のファイルは読み取り後即座にパス参照を破棄
