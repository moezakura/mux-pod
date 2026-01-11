# Data Model: SSH鍵管理機能

**Feature**: 003-ssh-key-management
**Date**: 2026-01-11

## Entities

### SshKeyMeta（既存・拡張）

SSH鍵のメタデータ。`shared_preferences`に保存。

```dart
class SshKeyMeta {
  final String id;           // UUID
  final String name;         // ユーザー指定の名前
  final String type;         // 'ed25519' | 'rsa-2048' | 'rsa-3072' | 'rsa-4096'
  final String? publicKey;   // 公開鍵（authorized_keys形式）
  final String? fingerprint; // SHA256フィンガープリント
  final bool hasPassphrase;  // パスフレーズの有無
  final DateTime createdAt;  // 作成日時
  final String? comment;     // コメント（オプション）
  final KeySource source;    // 鍵の由来（generated | imported）
}
```

**Validation Rules**:
- `id`: 空でない、UUID形式
- `name`: 空でない、255文字以下
- `type`: `['ed25519', 'rsa-2048', 'rsa-3072', 'rsa-4096']`のいずれか
- `publicKey`: null許容、設定時はSSH公開鍵形式
- `fingerprint`: null許容、設定時は`SHA256:`プレフィックス付き
- `createdAt`: 有効なDateTime

**State Transitions**:
```
[生成開始] → [生成中] → [生成完了/保存済み]
                    ↘ [生成失敗]

[インポート開始] → [パース中] → [保存済み]
                          ↘ [パース失敗]

[保存済み] → [削除済み]
```

---

### KeySource（新規）

鍵の由来を示すEnum。

```dart
enum KeySource {
  generated,  // アプリ内で生成
  imported,   // ファイル/ペーストでインポート
}
```

---

### KeysState（既存）

鍵一覧の状態管理。

```dart
class KeysState {
  final List<SshKeyMeta> keys;  // 鍵リスト（作成日時降順）
  final bool isLoading;          // ロード中フラグ
  final String? error;           // エラーメッセージ
}
```

---

## Storage Schema

### shared_preferences

```json
{
  "ssh_keys_meta": [
    {
      "id": "uuid-string",
      "name": "My Key",
      "type": "ed25519",
      "publicKey": "ssh-ed25519 AAAA... comment",
      "fingerprint": "SHA256:abc123...",
      "hasPassphrase": false,
      "createdAt": "2026-01-11T12:00:00.000Z",
      "comment": null,
      "source": "generated"
    }
  ]
}
```

### flutter_secure_storage

| Key Pattern | Value | Description |
|-------------|-------|-------------|
| `privatekey_{keyId}` | PEM string | 秘密鍵（OpenSSH形式） |
| `passphrase_{keyId}` | string | パスフレーズ（暗号化保存） |

---

## Relationships

```
┌─────────────────┐
│   SshKeyMeta    │
│   (metadata)    │
│                 │
│ id ─────────────┼──┐
│ name            │  │
│ type            │  │
│ publicKey       │  │  References by key
│ fingerprint     │  │
│ hasPassphrase ──┼──┼───────────────────┐
│ createdAt       │  │                   │
│ source          │  │                   │
└─────────────────┘  │                   │
                     │                   │
           ┌─────────▼─────────┐  ┌──────▼───────┐
           │ SecureStorage     │  │ SecureStorage│
           │ privatekey_{id}   │  │ passphrase_{id}
           │ (PEM content)     │  │ (if encrypted)
           └───────────────────┘  └──────────────┘
```

---

## API Contracts

### SshKeyService

```dart
abstract class SshKeyService {
  /// Ed25519鍵ペアを生成
  Future<SshKeyPair> generateEd25519({String? comment});

  /// RSA鍵ペアを生成
  Future<SshKeyPair> generateRsa({
    required int bits, // 2048 | 3072 | 4096
    String? comment,
  });

  /// PEM文字列から鍵をパース
  Future<SshKeyPair> parseFromPem(
    String pemContent, {
    String? passphrase,
  });

  /// 鍵がパスフレーズで暗号化されているか確認
  bool isEncrypted(String pemContent);

  /// 公開鍵のフィンガープリントを計算
  String calculateFingerprint(Uint8List publicKeyBlob);

  /// 秘密鍵をPEM形式に変換
  String toPem(SshKeyPair keyPair);

  /// 公開鍵をauthorized_keys形式に変換
  String toAuthorizedKeys(SshKeyPair keyPair, String comment);
}

/// 鍵ペアのデータクラス
class SshKeyPair {
  final String type;           // 'ed25519' | 'rsa-2048' | etc.
  final Uint8List privateKey;  // 秘密鍵バイト列
  final Uint8List publicKey;   // 公開鍵バイト列
  final String fingerprint;    // SHA256フィンガープリント
}
```

### KeysNotifier（既存メソッド）

```dart
class KeysNotifier extends Notifier<KeysState> {
  Future<void> add(SshKeyMeta key);
  Future<void> remove(String id);
  Future<void> update(SshKeyMeta key);
  SshKeyMeta? getById(String id);
  Future<void> reload();
}
```

### SecureStorageService（既存メソッド）

```dart
class SecureStorageService {
  Future<void> savePrivateKey(String keyId, String privateKey);
  Future<String?> getPrivateKey(String keyId);
  Future<void> deletePrivateKey(String keyId);
  Future<void> savePassphrase(String keyId, String passphrase);
  Future<String?> getPassphrase(String keyId);
  Future<void> deletePassphrase(String keyId);
}
```
