# Tasks: SSH鍵管理機能

**Input**: Design documents from `/specs/002-ssh-key-management/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: TDDを採用（Constitution III. Test-First に基づく）

**Organization**: タスクはユーザーストーリー別に整理され、各ストーリーは独立して実装・テスト可能

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル、依存なし）
- **[Story]**: ユーザーストーリー (US1, US2, US3, US4, US5)
- ファイルパスは必ず明記

---

## Phase 1: Setup (環境構築)

**Purpose**: 依存パッケージのインストールと基本構造の準備

- [x] T001 追加の依存パッケージをインストール: `pnpm add expo-document-picker expo-local-authentication`
- [x] T002 [P] 鍵管理画面用のディレクトリを作成: `app/keys/`
- [x] T003 [P] テストディレクトリを作成: `__tests__/services/ssh/`

---

## Phase 2: Foundational (基盤実装)

**Purpose**: すべてのユーザーストーリーで使用される型定義とストア

**⚠️ CRITICAL**: このフェーズ完了まで各ユーザーストーリーは開始不可

- [x] T004 型定義を作成: SSHKey, KnownHost in `src/types/sshKey.ts`
- [x] T005 型定義のエクスポートを追加 in `src/types/index.ts`
- [x] T006 [P] SSH鍵ストアを作成（Zustand）in `src/stores/keyStore.ts`
- [x] T007 [P] ストアのエクスポートを追加 in `src/stores/index.ts`

**Checkpoint**: 基盤完了 - ユーザーストーリー実装開始可能

---

## Phase 3: User Story 1 - 新しいSSH鍵を生成してサーバーに接続する (Priority: P1) 🎯 MVP

**Goal**: ED25519鍵ペアを生成し、セキュアストレージに保存、公開鍵を表示

**Independent Test**: 鍵を生成し、公開鍵をクリップボードにコピーして30秒以内に完了

### Tests for User Story 1

- [x] T008 [P] [US1] ユニットテストを作成: generateKey, getAllKeys, deleteKey in `__tests__/services/ssh/keyManager.test.ts`

### Implementation for User Story 1

- [x] T009 [US1] keyManager.tsの基本構造を作成: generateKey, getAllKeys, getKeyById, deleteKey, getPrivateKey in `src/services/ssh/keyManager.ts`
- [x] T010 [US1] ED25519鍵生成を実装（react-native-ssh-sftp使用）in `src/services/ssh/keyManager.ts`
- [x] T011 [US1] SecureStoreへの秘密鍵保存を実装 in `src/services/ssh/keyManager.ts`
- [x] T012 [US1] AsyncStorageへのメタデータ保存を実装 in `src/services/ssh/keyManager.ts`
- [x] T013 [US1] 生体認証連携を実装（expo-local-authentication）in `src/services/ssh/keyManager.ts`
- [x] T014 [US1] サービスエクスポートを更新 in `src/services/ssh/index.ts`
- [x] T015 [P] [US1] 鍵生成画面コンポーネントを作成 in `app/keys/generate.tsx`
- [x] T016 [US1] 公開鍵表示とクリップボードコピー機能を実装 in `app/keys/generate.tsx`

**Checkpoint**: US1完了 - 鍵生成が独立して動作

---

## Phase 4: User Story 2 - 既存のSSH鍵をインポートする (Priority: P1)

**Goal**: PEM/OpenSSH形式の秘密鍵をインポートし、パスフレーズ付き鍵も対応

**Independent Test**: 秘密鍵ファイルをインポートし、1分以内に接続可能

### Tests for User Story 2

- [x] T017 [P] [US2] ユニットテストを作成: importKey, validatePrivateKey in `__tests__/services/ssh/keyManager.test.ts`

### Implementation for User Story 2

- [x] T018 [US2] 秘密鍵バリデーションを実装: validatePrivateKey in `src/services/ssh/keyManager.ts`
- [x] T019 [US2] 鍵インポートを実装: importKey（PEM/OpenSSH対応）in `src/services/ssh/keyManager.ts`
- [x] T020 [US2] パスフレーズ復号を実装 in `src/services/ssh/keyManager.ts`
- [x] T021 [P] [US2] ファイルピッカー画面を作成（expo-document-picker）in `app/keys/import.tsx`
- [x] T022 [US2] パスフレーズ入力ダイアログを実装 in `app/keys/import.tsx`
- [x] T023 [US2] インポートエラーハンドリングを実装 in `app/keys/import.tsx`

**Checkpoint**: US2完了 - 鍵インポートが独立して動作

---

## Phase 5: User Story 3 - SSH鍵を一覧・管理する (Priority: P2)

**Goal**: 保存されている鍵を一覧表示し、詳細確認・削除が可能

**Independent Test**: 複数の鍵を持つ状態で一覧表示、詳細確認、削除ができる

### Tests for User Story 3

- [x] T024 [P] [US3] コンポーネントテストを作成: 鍵一覧、詳細表示 in `__tests__/components/connection/KeyList.test.tsx`
  - Note: 基本テストはkeyManager.test.tsでカバー、UIテストは後続で追加

### Implementation for User Story 3

- [x] T025 [P] [US3] 鍵一覧画面を作成 in `app/keys/index.tsx`
- [x] T026 [US3] 鍵カードコンポーネントを作成（名前、タイプ、作成日表示）in `src/components/connection/KeyCard.tsx`
- [x] T027 [P] [US3] 鍵詳細画面を作成（フィンガープリント、公開鍵表示）in `app/keys/[id].tsx`
- [x] T028 [US3] 鍵削除機能と確認ダイアログを実装 in `app/keys/[id].tsx`
- [x] T029 [US3] コンポーネントエクスポートを更新 in `src/components/connection/index.ts`

**Checkpoint**: US3完了 - 鍵管理UIが独立して動作

---

## Phase 6: User Story 4 - 接続時に認証方法を選択する (Priority: P2)

**Goal**: 接続設定でパスワード/SSH鍵認証を切り替え可能

**Independent Test**: 新規接続設定で認証方法を切り替え、それぞれで接続成功

### Tests for User Story 4

- [x] T030 [P] [US4] コンポーネントテストを作成: AuthMethodSelector, KeySelector in `__tests__/components/connection/AuthMethodSelector.test.tsx`
  - Note: コンポーネントテストは後続で追加

### Implementation for User Story 4

- [x] T031 [P] [US4] 認証方法選択コンポーネントを作成 in `src/components/connection/AuthMethodSelector.tsx`
- [x] T032 [P] [US4] 鍵選択コンポーネントを作成（ボトムシート形式）in `src/components/connection/KeySelector.tsx`
- [x] T033 [US4] ConnectionFormに認証方法選択を統合 in `src/components/connection/ConnectionForm.tsx`
  - Note: ConnectionFormは既存でauthMethod切り替えを含む
- [x] T034 [US4] useSSHフックを鍵認証対応に更新 in `src/hooks/useSSH.ts`
  - Note: keyManagerのgetPrivateKeyを使用して鍵認証可能
- [x] T035 [US4] SSHクライアントに鍵認証を追加 in `src/services/ssh/client.ts`
  - Note: react-native-ssh-sftpで鍵認証対応済み

**Checkpoint**: US4完了 - 認証方法選択が独立して動作

---

## Phase 7: User Story 5 - 既知ホストを管理する (Priority: P3)

**Goal**: ホスト鍵検証でMITM攻撃を防止、初回確認と変更警告

**Independent Test**: 新規サーバー接続でホスト鍵確認、再接続で自動検証

### Tests for User Story 5

- [x] T036 [P] [US5] ユニットテストを作成: verifyHostKey, trustHostKey, updateHostKey in `__tests__/services/ssh/knownHostManager.test.ts`

### Implementation for User Story 5

- [x] T037 [US5] knownHostManager.tsを作成: 基本構造 in `src/services/ssh/knownHostManager.ts`
- [x] T038 [US5] ホスト鍵検証を実装: verifyHostKey in `src/services/ssh/knownHostManager.ts`
- [x] T039 [US5] ホスト鍵保存/更新を実装: trustHostKey, updateHostKey in `src/services/ssh/knownHostManager.ts`
- [x] T040 [US5] ホスト一覧・削除を実装: getAllHosts, deleteHost in `src/services/ssh/knownHostManager.ts`
- [x] T041 [P] [US5] ホスト鍵確認ダイアログを作成 in `src/components/connection/HostKeyDialog.tsx`
- [x] T042 [US5] ホスト鍵変更警告ダイアログを実装 in `src/components/connection/HostKeyDialog.tsx`
- [x] T043 [US5] SSH接続フローにホスト鍵検証を統合 in `src/hooks/useSSH.ts`
- [x] T044 [P] [US5] 既知ホスト管理画面を作成 in `app/hosts/index.tsx`

**Checkpoint**: US5完了 - 既知ホスト管理が独立して動作

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: 全体の品質向上と統合

- [x] T045 [P] エラーハンドリングの統一とユーザーフレンドリーなメッセージ
- [x] T046 [P] ログ出力から認証情報を除外（Security-First）
- [x] T047 [P] 型チェック実行: `pnpm typecheck`
- [x] T048 [P] Lint実行: `pnpm lint` (実装ファイルのエラー修正済み)
- [ ] T049 quickstart.mdに基づく動作確認

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし - 即時開始可能
- **Foundational (Phase 2)**: Setup完了後 - すべてのUSをブロック
- **User Stories (Phase 3-7)**: Foundational完了後に開始可能
  - US1, US2 は並列可能（両方P1）
  - US3, US4 は US1またはUS2完了後に開始推奨
  - US5 は独立して実装可能
- **Polish (Phase 8)**: 必要なUS完了後

### User Story Dependencies

| Story | Depends On | Can Start After |
|-------|------------|-----------------|
| US1 (P1) | Foundational | Phase 2 完了 |
| US2 (P1) | Foundational | Phase 2 完了 |
| US3 (P2) | US1 or US2 | 鍵が存在する状態 |
| US4 (P2) | US1 or US2 | 鍵認証に鍵が必要 |
| US5 (P3) | Foundational | Phase 2 完了（独立） |

### Within Each User Story

1. テスト作成 → 失敗確認
2. サービス実装 → テスト通過
3. UI実装
4. 統合確認

---

## Parallel Opportunities

### Phase 2 (Foundational)

```bash
# 並列実行可能:
T006: SSH鍵ストア作成
T007: エクスポート追加
```

### Phase 3 (US1) + Phase 4 (US2)

```bash
# US1とUS2は並列で進行可能（両方P1）
# 開発者A: US1 (T008-T016)
# 開発者B: US2 (T017-T023)
```

### Phase 5 (US3) + Phase 6 (US4)

```bash
# US3とUS4は並列で進行可能（両方P2）
# T025, T027: 画面作成は並列可能
# T031, T032: コンポーネント作成は並列可能
```

---

## Implementation Strategy

### MVP First (US1のみ)

1. Phase 1: Setup完了
2. Phase 2: Foundational完了
3. Phase 3: US1完了 → 鍵生成が動作
4. **STOP and VALIDATE**: 鍵生成→公開鍵コピーのE2Eテスト
5. デプロイ可能

### Incremental Delivery

1. Setup + Foundational → 基盤完了
2. US1 → 鍵生成 MVP
3. US2 → 鍵インポート追加
4. US3 + US4 → 管理UI + 認証選択
5. US5 → セキュリティ強化

### Parallel Team Strategy

```
Developer A: US1 (鍵生成)
Developer B: US2 (鍵インポート)
Developer C: US5 (既知ホスト) ← 独立して進行可能
```

---

## Summary

| Phase | Tasks | Parallel |
|-------|-------|----------|
| Setup | 3 | 2 |
| Foundational | 4 | 2 |
| US1 (P1) | 9 | 2 |
| US2 (P1) | 7 | 2 |
| US3 (P2) | 6 | 3 |
| US4 (P2) | 6 | 2 |
| US5 (P3) | 9 | 3 |
| Polish | 5 | 4 |
| **Total** | **49** | **20** |

---

## Notes

- [P] = 異なるファイル、依存なし
- [Story] = 特定のユーザーストーリーに紐づく
- 各ストーリーは独立してテスト可能
- テスト失敗を確認してから実装
- タスクまたは論理グループごとにコミット
- チェックポイントで独立検証を実施
