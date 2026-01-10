# Data Model: SSH鍵管理機能

**Feature**: 002-ssh-key-management
**Date**: 2026-01-10

## Entities

### SSHKey

SSH鍵ペアのメタデータ。秘密鍵本体は SecureStore に別途保存。

```typescript
interface SSHKey {
  /** UUID v4 */
  id: string;

  /** ユーザー定義の表示名 (e.g., "Work Laptop", "Personal") */
  name: string;

  /** 鍵タイプ */
  keyType: 'ed25519' | 'rsa-2048' | 'rsa-4096' | 'ecdsa';

  /** 公開鍵 (OpenSSH authorized_keys 形式) */
  publicKey: string;

  /** SHA256 フィンガープリント (e.g., "SHA256:abcd1234...") */
  fingerprint: string;

  /** 生体認証を要求するか */
  requireBiometrics: boolean;

  /** 作成日時 (Unix timestamp ms) */
  createdAt: number;

  /** インポートされた鍵かどうか */
  imported: boolean;
}
```

**Storage**:
- メタデータ: `AsyncStorage` key `muxpod-ssh-keys` (JSON array)
- 秘密鍵: `SecureStore` key `muxpod-ssh-key-{id}`

**Validation Rules**:
- `name`: 1-50文字、空白のみ不可
- `publicKey`: OpenSSH形式のバリデーション
- `fingerprint`: `SHA256:` プレフィックス必須

---

### KnownHost

既知のサーバーホスト鍵。MITM攻撃防止のために使用。

```typescript
interface KnownHost {
  /** ホスト識別子 (host:port) */
  identifier: string;

  /** ホスト名 */
  host: string;

  /** ポート番号 */
  port: number;

  /** ホスト鍵タイプ */
  keyType: 'ssh-ed25519' | 'ssh-rsa' | 'ecdsa-sha2-nistp256' | 'ecdsa-sha2-nistp384';

  /** 公開鍵 (Base64) */
  publicKey: string;

  /** SHA256 フィンガープリント */
  fingerprint: string;

  /** 初回追加日時 (Unix timestamp ms) */
  addedAt: number;

  /** 最終検証成功日時 (Unix timestamp ms) */
  lastVerifiedAt: number;
}
```

**Storage**: `AsyncStorage` key `muxpod-known-hosts` (JSON array)

**Validation Rules**:
- `identifier`: `{host}:{port}` 形式
- `port`: 1-65535
- `fingerprint`: `SHA256:` プレフィックス必須

---

### Connection (既存エンティティの拡張)

```typescript
interface Connection {
  // ... 既存フィールド ...

  /** 認証方式 (既存) */
  authMethod: 'password' | 'key';

  /** SSH鍵ID (key認証時、既存だがオプショナルから必須に変更) */
  keyId?: string;
}
```

**Relationship**:
- `Connection.keyId` → `SSHKey.id` (多対一)

---

## State Transitions

### SSHKey Lifecycle

```
[Created] ─── 生成 ───→ [Active] ←─── インポート ───┐
                           │                         │
                           │ 削除                    │
                           ▼                         │
                        [Deleted]              [File Selected]
```

### KnownHost Verification

```
[New Connection]
      │
      ▼
[Check Known Hosts]
      │
      ├─── 見つからない ───→ [Show Fingerprint Dialog]
      │                              │
      │                    ├─ Accept ─→ [Save & Connect]
      │                    └─ Reject ─→ [Abort]
      │
      ├─── 一致 ───→ [Connect]
      │
      └─── 不一致 ───→ [Show Warning Dialog]
                              │
                    ├─ Accept ─→ [Update & Connect]
                    └─ Reject ─→ [Abort]
```

---

## Storage Keys

| Key | Type | Content |
|-----|------|---------|
| `muxpod-ssh-keys` | AsyncStorage | `SSHKey[]` メタデータ配列 |
| `muxpod-ssh-key-{id}` | SecureStore | 秘密鍵 (PEM形式) |
| `muxpod-known-hosts` | AsyncStorage | `KnownHost[]` 配列 |
| `muxpod-ssh-password-{id}` | SecureStore | パスワード (既存) |

---

## Indexes / Queries

### SSHKey
- **By ID**: `getKeyById(id: string): SSHKey | undefined`
- **All**: `getAllKeys(): SSHKey[]`
- **By Name**: `getKeyByName(name: string): SSHKey | undefined` (重複チェック用)

### KnownHost
- **By Identifier**: `getHostByIdentifier(identifier: string): KnownHost | undefined`
- **All**: `getAllHosts(): KnownHost[]`

---

## Constraints

1. **SSHKey.name** はユニークでなければならない
2. **SSHKey** 削除時、関連する **Connection** の `keyId` は `undefined` にリセット
3. **KnownHost.identifier** はユニークでなければならない
4. 秘密鍵は **SecureStore** 外に保存してはならない
