# Quickstart: SSH鍵管理機能

**Feature**: 002-ssh-key-management

## 依存パッケージの追加

```bash
pnpm add expo-document-picker expo-local-authentication
```

## ファイル構成

```
src/
├── types/
│   └── sshKey.ts              # SSHKey, KnownHost 型定義
├── services/
│   └── ssh/
│       ├── keyManager.ts      # SSH鍵の生成・インポート・管理
│       ├── knownHostManager.ts # 既知ホスト管理
│       └── index.ts           # エクスポート追加
├── stores/
│   └── keyStore.ts            # SSH鍵の状態管理 (Zustand)
├── components/
│   └── connection/
│       ├── KeySelector.tsx    # 鍵選択UI
│       ├── AuthMethodSelector.tsx # 認証方法選択
│       └── HostKeyDialog.tsx  # ホスト鍵確認ダイアログ
└── app/
    └── keys/
        ├── index.tsx          # 鍵一覧画面
        ├── [id].tsx           # 鍵詳細画面
        └── import.tsx         # 鍵インポート画面
```

## 実装順序

### Phase 1: コア機能 (P1)

1. **型定義** (`src/types/sshKey.ts`)
   - `SSHKey`, `KnownHost`, 定数

2. **鍵管理サービス** (`src/services/ssh/keyManager.ts`)
   - `generateKey()` - ED25519鍵生成
   - `importKey()` - 鍵インポート
   - `getAllKeys()` / `getKeyById()` - 取得
   - `deleteKey()` - 削除

3. **鍵ストア** (`src/stores/keyStore.ts`)
   - Zustand store でリアクティブな状態管理

4. **接続フォーム拡張** (`src/components/connection/ConnectionForm.tsx`)
   - 認証方法選択UI追加
   - 鍵選択ドロップダウン

### Phase 2: 管理UI (P2)

5. **鍵一覧画面** (`app/keys/index.tsx`)
   - 鍵リスト表示
   - 生成・インポートボタン

6. **鍵詳細画面** (`app/keys/[id].tsx`)
   - 公開鍵表示・コピー
   - 削除機能

7. **鍵選択コンポーネント** (`src/components/connection/KeySelector.tsx`)
   - ボトムシート形式の鍵選択

### Phase 3: セキュリティ (P3)

8. **既知ホスト管理** (`src/services/ssh/knownHostManager.ts`)
   - ホスト鍵検証
   - 信頼済みホスト保存

9. **ホスト鍵ダイアログ** (`src/components/connection/HostKeyDialog.tsx`)
   - 初回接続時の確認
   - 鍵変更警告

## 使用例

### 鍵生成

```typescript
import { keyManager } from '@/services/ssh/keyManager';

const result = await keyManager.generateKey({
  name: 'My Server Key',
  keyType: 'ed25519',
  requireBiometrics: true,
});

console.log(result.publicKey);
// ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... muxpod-key
```

### 鍵インポート

```typescript
import { keyManager } from '@/services/ssh/keyManager';

const key = await keyManager.importKey({
  name: 'Existing Key',
  privateKey: `-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----`,
  passphrase: 'optional-passphrase',
});
```

### ホスト鍵検証

```typescript
import { knownHostManager } from '@/services/ssh/knownHostManager';

const result = await knownHostManager.verifyHostKey({
  host: 'example.com',
  port: 22,
  keyType: 'ssh-ed25519',
  publicKey: 'AAAAC3NzaC1lZDI1NTE5...',
  fingerprint: 'SHA256:abcd1234...',
});

if (result.status === 'unknown') {
  // 初回接続: ユーザーに確認を求める
} else if (result.status === 'changed') {
  // 警告: ホスト鍵が変更された
}
```

## テスト

```bash
# ユニットテスト
pnpm test src/services/ssh/keyManager.test.ts

# 型チェック
pnpm typecheck
```
