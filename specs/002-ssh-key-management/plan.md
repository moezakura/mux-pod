# Implementation Plan: SSH鍵管理機能

**Branch**: `002-ssh-key-management` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-ssh-key-management/spec.md`

## Summary

SSH鍵の生成・インポート・管理機能と既知ホスト管理を実装する。ED25519鍵の生成、PEM/OpenSSH形式の秘密鍵インポート、expo-secure-storeによるセキュアストレージ保存、生体認証連携、既知ホストによるMITM攻撃防止を提供する。

## Technical Context

**Language/Version**: TypeScript 5.6+
**Primary Dependencies**: Expo ~52.0.0, React Native 0.76.0, react-native-ssh-sftp, expo-secure-store, expo-document-picker (追加), expo-local-authentication (追加)
**Storage**: expo-secure-store (秘密鍵), AsyncStorage (メタデータ)
**Testing**: Jest + jest-expo + @testing-library/react-native
**Target Platform**: Android 8.0+ (ハードウェアKeystore対応)
**Project Type**: Mobile (Expo Router)
**Performance Goals**: 鍵生成 < 30秒, 認証 < 5秒
**Constraints**: 秘密鍵はSecureStore外保存禁止, 生体認証対応必須
**Scale/Scope**: 最大50鍵、100既知ホスト程度を想定

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | strict: true, 全エンティティに型定義 |
| II. KISS & YAGNI | ✅ PASS | 必要最小限の機能のみ実装 |
| III. Test-First | ✅ PASS | サービス層にユニットテスト必須 |
| IV. Security-First | ✅ PASS | SecureStore使用、生体認証、ログ除外 |
| V. SOLID | ✅ PASS | SRP: KeyManager / KnownHostManager 分離 |
| VI. DRY | ✅ PASS | 既存auth.tsのパターンを踏襲 |
| Prohibited Naming | ✅ PASS | utils/helpers 使用なし |

**Post-Design Re-check**: ✅ すべてのゲート通過

## Project Structure

### Documentation (this feature)

```text
specs/002-ssh-key-management/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── types.ts
│   ├── key-manager.ts
│   └── known-host-manager.ts
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
src/
├── types/
│   ├── connection.ts        # 既存 (keyId参照あり)
│   └── sshKey.ts            # 新規: SSHKey, KnownHost
├── services/
│   └── ssh/
│       ├── auth.ts          # 既存 (パスワード管理)
│       ├── client.ts        # 既存 (SSH接続)
│       ├── keyManager.ts    # 新規: 鍵生成・インポート・管理
│       ├── knownHostManager.ts # 新規: 既知ホスト管理
│       └── index.ts         # 更新: エクスポート追加
├── stores/
│   ├── connectionStore.ts   # 既存
│   └── keyStore.ts          # 新規: SSH鍵状態管理
├── components/
│   └── connection/
│       ├── ConnectionForm.tsx   # 更新: 認証方法選択追加
│       ├── KeySelector.tsx      # 新規: 鍵選択コンポーネント
│       ├── AuthMethodSelector.tsx # 新規: password/key切替
│       └── HostKeyDialog.tsx    # 新規: ホスト鍵確認
└── hooks/
    └── useSSH.ts            # 更新: 鍵認証対応

app/
└── keys/
    ├── index.tsx            # 新規: 鍵一覧画面
    ├── [id].tsx             # 新規: 鍵詳細画面
    └── import.tsx           # 新規: 鍵インポート画面

__tests__/
└── services/
    └── ssh/
        ├── keyManager.test.ts      # 新規
        └── knownHostManager.test.ts # 新規
```

**Structure Decision**: 既存のExpo Router + src/構造を維持。SSH関連サービスを`src/services/ssh/`に集約し、鍵管理画面を`app/keys/`に追加。

## Complexity Tracking

> 憲法違反なし - このセクションは空

## Dependencies to Add

```bash
pnpm add expo-document-picker expo-local-authentication
```

## Related Documents

- [research.md](./research.md) - 技術調査結果
- [data-model.md](./data-model.md) - エンティティ定義
- [quickstart.md](./quickstart.md) - 実装ガイド
- [contracts/](./contracts/) - サービスインターフェース
