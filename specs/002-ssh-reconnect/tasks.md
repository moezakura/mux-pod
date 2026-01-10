# Tasks: SSH再接続機能

**Input**: Design documents from `/specs/002-ssh-reconnect/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included (Constitution requires TDD approach)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: 型定義とStore拡張の準備

- [x] T001 [P] 再接続関連の型を追加 in `src/types/connection.ts`
  - `ConnectionStatus` に `'reconnecting'` を追加
  - `DisconnectReason` 型を新規作成
  - `ReconnectAttempt`, `AttemptResult` インターフェースを追加
  - `Connection` に再接続設定フィールド追加（autoReconnect, maxReconnectAttempts, reconnectInterval）
  - `ConnectionState` に切断情報フィールド追加（disconnectedAt, disconnectReason, reconnectAttempt）
  - `DEFAULT_RECONNECT_SETTINGS` 定数を追加

- [x] T002 [P] connectionStoreに再接続アクションを追加 in `src/stores/connectionStore.ts`
  - `updateReconnectSettings` アクション追加
  - `setDisconnected` アクション追加
  - `setReconnecting` アクション追加
  - `recordReconnectAttempt` アクション追加
  - `clearReconnectState` アクション追加
  - 永続化設定を更新（再接続設定を含める）

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 全ユーザーストーリーで共有する再接続サービスの基盤

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 ReconnectServiceのテストを作成 in `__tests__/services/ssh/reconnect.test.ts`
  - handleDisconnection: 自動再接続有効時にtrueを返す
  - handleDisconnection: 自動再接続無効時にfalseを返す
  - startReconnect: 接続成功時にsuccess=trueを返す
  - startReconnect: 接続失敗時にリトライする
  - startReconnect: 最大試行回数後にgiveUpイベントを発火
  - cancelReconnect: 再接続中にキャンセル可能

- [x] T004 ReconnectServiceを実装 in `src/services/ssh/reconnect.ts`
  - `IReconnectService` インターフェースを実装
  - `handleDisconnection` メソッド実装
  - `startReconnect` メソッド実装（リトライロジック含む）
  - `cancelReconnect` メソッド実装
  - イベントハンドラ管理
  - タイマー管理（試行間隔）

- [x] T005 SSHサービスのexportを更新 in `src/services/ssh/index.ts`
  - ReconnectService関連のexportを追加

**Checkpoint**: 再接続サービスの基盤が完成 - ユーザーストーリー実装可能

---

## Phase 3: User Story 1 - 接続状態の常時確認 (Priority: P1) 🎯 MVP

**Goal**: ターミナル画面で接続状態を常に視覚的に確認でき、状態変化時に即座に更新される

**Independent Test**: 接続状態インジケーターが表示され、SSHクライアントのonCloseイベント発火時に「切断」状態に変化することを確認

### Tests for User Story 1

- [x] T006 [P] [US1] ConnectionStatusIndicatorのテストを作成 in `__tests__/components/connection/ConnectionStatusIndicator.test.tsx`
  - connected状態で緑色ドットを表示
  - disconnected状態で赤色ドットを表示
  - reconnecting状態で回転アニメーションを表示
  - onPressで詳細情報を表示

### Implementation for User Story 1

- [x] T007 [P] [US1] ConnectionStatusIndicatorを実装 in `src/components/connection/ConnectionStatusIndicator.tsx`
  - status に応じた色・アイコン表示
  - アニメーション（パルス、回転）
  - タップ時の詳細表示
  - サイズバリエーション（sm/md/lg）

- [x] T008 [US1] SSHクライアントのonClose連携を実装 in `src/services/ssh/client.ts`
  - onCloseイベント時にconnectionStoreのsetDisconnectedを呼び出す
  - 切断理由の判定ロジック

- [x] T009 [US1] コンポーネントのexportを更新 in `src/components/connection/index.ts`
  - ConnectionStatusIndicatorをexport

- [x] T010 [US1] TerminalHeaderにインジケーターを統合 in `src/components/terminal/TerminalHeader.tsx`
  - ConnectionStatusIndicatorを配置
  - connectionStoreからstateを取得

**Checkpoint**: 接続状態の視覚的表示が機能する（US1完了）

---

## Phase 4: User Story 2 - 切断時の再接続確認 (Priority: P2)

**Goal**: SSH接続が切断された際に再接続確認ダイアログが表示され、ユーザーが再接続またはキャンセルを選択できる

**Independent Test**: 接続切断時にダイアログが表示され、「再接続」選択で接続が復旧することを確認

### Tests for User Story 2

- [ ] T011 [P] [US2] ReconnectDialogのテストを作成 in `__tests__/components/connection/ReconnectDialog.test.tsx`
  - visible=trueでダイアログが表示される
  - 「再接続」ボタンでonReconnectが呼ばれる
  - 「キャンセル」ボタンでonCancelが呼ばれる
  - 接続中にスピナーが表示される
  - エラー時にメッセージと再試行ボタンが表示される

### Implementation for User Story 2

- [ ] T012 [P] [US2] ReconnectDialogを実装 in `src/components/connection/ReconnectDialog.tsx`
  - Modal コンポーネントでオーバーレイ表示
  - confirm/connecting/password/error/success 状態管理
  - 再接続・キャンセルボタン
  - 進捗状態（スピナー）表示
  - エラーメッセージ表示
  - パスワード入力フォーム（認証情報がない場合）

- [ ] T013 [US2] ReconnectDialogのexportを追加 in `src/components/connection/index.ts`
  - ReconnectDialogをexport

- [ ] T014 [US2] useReconnectDialogフックを作成 in `src/hooks/useReconnectDialog.ts`
  - ダイアログ表示状態管理
  - ReconnectServiceとの連携
  - 再接続処理の実行
  - 認証情報取得

- [ ] T015 [US2] ターミナル画面でダイアログを使用 in `app/terminal/[id].tsx`
  - 切断検出時にダイアログ表示
  - 再接続成功時にダイアログ閉じる
  - キャンセル時に接続一覧へ遷移

- [ ] T016 [US2] hooksのexportを更新 in `src/hooks/index.ts`
  - useReconnectDialogをexport

**Checkpoint**: 手動再接続フローが機能する（US1 + US2完了）

---

## Phase 5: User Story 3 - 自動再接続設定 (Priority: P3)

**Goal**: 接続ごとに自動再接続のON/OFFを設定でき、有効時は確認ダイアログなしで自動的に再接続が試行される

**Independent Test**: 自動再接続を有効化し、接続切断時にダイアログなしで再接続が開始されることを確認

### Tests for User Story 3

- [ ] T017 [P] [US3] 自動再接続ロジックのテストを作成 in `__tests__/services/ssh/reconnect.test.ts`
  - autoReconnect=true時にダイアログなしで再接続開始
  - 3回失敗後に手動ダイアログに切り替え
  - キャンセル操作で自動再接続を中止

### Implementation for User Story 3

- [ ] T018 [P] [US3] ConnectionFormに自動再接続設定を追加 in `src/components/connection/ConnectionForm.tsx`
  - 自動再接続トグルスイッチ
  - 最大試行回数設定（任意）
  - 試行間隔設定（任意）

- [ ] T019 [US3] ReconnectServiceに自動再接続ロジックを統合 in `src/services/ssh/reconnect.ts`
  - handleDisconnection内で自動再接続判定
  - 最大試行回数到達時の手動ダイアログ切り替え
  - インジケーターへの試行回数表示連携

- [ ] T020 [US3] ターミナル画面で自動再接続を処理 in `app/terminal/[id].tsx`
  - autoReconnect=true時はダイアログ非表示
  - 自動再接続失敗後にダイアログ表示
  - インジケータータップでキャンセル可能

- [ ] T021 [US3] ConnectionStatusIndicatorに試行回数表示を追加 in `src/components/connection/ConnectionStatusIndicator.tsx`
  - reconnecting状態で「再接続中 (2/3)」形式で表示
  - タップでキャンセル確認

**Checkpoint**: 自動再接続フローが機能する（全ユーザーストーリー完了）

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 品質向上とエッジケース対応

- [ ] T022 [P] 型チェックを実行 `pnpm typecheck`
- [ ] T023 [P] Lintを実行 `pnpm lint`
- [ ] T024 [P] 全テストを実行 `pnpm test`
- [ ] T025 エッジケース対応: パスワード未保存時の再接続フロー確認
- [ ] T026 エッジケース対応: バックグラウンド移行時の処理確認
- [ ] T027 quickstart.mdの手順に従って動作確認

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational) ← BLOCKS all user stories
    ↓
┌───────────────────────────────────────┐
│  Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3)  │
│  (順次実行、各ストーリーは独立テスト可能)        │
└───────────────────────────────────────┘
    ↓
Phase 6 (Polish)
```

### User Story Dependencies

| Story | 依存 | 独立テスト可能 |
|-------|------|---------------|
| US1 (P1) | Phase 2完了 | ✅ インジケーター単体で動作確認可能 |
| US2 (P2) | US1（インジケーター） | ✅ ダイアログ単体で動作確認可能 |
| US3 (P3) | US2（ダイアログ） | ✅ 自動再接続単体で動作確認可能 |

### Parallel Opportunities

**Phase 1内（並列可能）**:
- T001: 型定義
- T002: Store拡張

**Phase 3内（並列可能）**:
- T006: テスト作成
- T007: コンポーネント実装

**Phase 4内（並列可能）**:
- T011: テスト作成
- T012: コンポーネント実装

**Phase 5内（並列可能）**:
- T017: テスト作成
- T018: フォーム拡張

**Phase 6内（並列可能）**:
- T022, T023, T024: 各種チェック

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup完了
2. Phase 2: Foundational完了
3. Phase 3: User Story 1完了
4. **STOP and VALIDATE**: インジケーター動作確認
5. デモ可能

### Incremental Delivery

1. Setup + Foundational → 基盤完成
2. US1追加 → インジケーター動作 → **MVP!**
3. US2追加 → 手動再接続動作 → リリース候補
4. US3追加 → 自動再接続動作 → フル機能
5. Polish → 品質保証 → 最終リリース

---

## Summary

| フェーズ | タスク数 | 並列可能 |
|---------|---------|---------|
| Phase 1: Setup | 2 | 2 |
| Phase 2: Foundational | 3 | 0 |
| Phase 3: US1 | 5 | 2 |
| Phase 4: US2 | 6 | 2 |
| Phase 5: US3 | 5 | 2 |
| Phase 6: Polish | 6 | 3 |
| **合計** | **27** | **11** |

**MVP Scope**: Phase 1-3（US1完了まで、10タスク）
