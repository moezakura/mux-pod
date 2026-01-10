# Tasks: Component Tests

**Input**: Design documents from `/specs/001-component-tests/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: This feature IS about tests - all tasks are test implementation.

**Organization**: Tasks are grouped by user story (each component = one user story).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1=ConnectionCard, US2=SpecialKeys, US3=SessionTabs, US4=TerminalView)
- Include exact file paths in descriptions

## Path Conventions

- **Test files**: `__tests__/components/`
- **Source components**: `src/components/`
- **Types**: `src/types/`

---

## Phase 1: Setup

**Purpose**: Ensure test infrastructure is ready

- [x] T001 Create test directory structure at `__tests__/components/`
- [x] T002 Add @expo/vector-icons mock to `jest.setup.js` if not present

**Checkpoint**: Test infrastructure ready

---

## Phase 2: User Story 1 - ConnectionCard Test Coverage (Priority: P1) 🎯 MVP

**Goal**: 開発者がConnectionCardの動作を検証できるテストを実装

**Independent Test**: `pnpm test ConnectionCard` でConnectionCardのみテスト実行可能

### Implementation for User Story 1

- [x] T003 [P] [US1] Create test file with mock data setup at `__tests__/components/ConnectionCard.test.tsx`
- [x] T004 [US1] Implement test: 接続情報が表示される at `__tests__/components/ConnectionCard.test.tsx`
- [x] T005 [US1] Implement test: connected状態でステータスドットが緑色 at `__tests__/components/ConnectionCard.test.tsx`
- [x] T006 [US1] Implement test: タップでセッション一覧が展開 at `__tests__/components/ConnectionCard.test.tsx`
- [x] T007 [US1] Implement test: セッション選択でコールバック呼び出し at `__tests__/components/ConnectionCard.test.tsx`
- [x] T008 [US1] Implement test: エラー状態でエラーメッセージ表示 at `__tests__/components/ConnectionCard.test.tsx`

**Checkpoint**: ConnectionCard tests pass - `pnpm test ConnectionCard`

---

## Phase 3: User Story 2 - SpecialKeys Test Coverage (Priority: P1)

**Goal**: 開発者がSpecialKeysの動作を検証できるテストを実装

**Independent Test**: `pnpm test SpecialKeys` でSpecialKeysのみテスト実行可能

### Implementation for User Story 2

- [x] T009 [P] [US2] Create test file with mock callbacks at `__tests__/components/SpecialKeys.test.tsx`
- [x] T010 [US2] Implement test: ESCボタンでonSendSpecialKey呼び出し at `__tests__/components/SpecialKeys.test.tsx`
- [x] T011 [US2] Implement test: TABボタンでonSendSpecialKey呼び出し at `__tests__/components/SpecialKeys.test.tsx`
- [x] T012 [US2] Implement test: CTRLモード切替 at `__tests__/components/SpecialKeys.test.tsx`
- [x] T013 [US2] Implement test: CTRLモードでリテラルキーがonSendCtrl呼び出し at `__tests__/components/SpecialKeys.test.tsx`
- [x] T014 [US2] Implement test: disabled状態でコールバック無効 at `__tests__/components/SpecialKeys.test.tsx`

**Checkpoint**: SpecialKeys tests pass - `pnpm test SpecialKeys`

---

## Phase 4: User Story 3 - SessionTabs Test Coverage (Priority: P2)

**Goal**: 開発者がSessionTabsの動作を検証できるテストを実装

**Independent Test**: `pnpm test SessionTabs` でSessionTabsのみテスト実行可能

### Implementation for User Story 3

- [x] T015 [P] [US3] Create test file with mock session data at `__tests__/components/SessionTabs.test.tsx`
- [x] T016 [US3] Implement test: 全セッション名がタブ表示 at `__tests__/components/SessionTabs.test.tsx`
- [x] T017 [US3] Implement test: タブタップでonSelect呼び出し at `__tests__/components/SessionTabs.test.tsx`
- [x] T018 [US3] Implement test: 選択中タブがアクティブスタイル at `__tests__/components/SessionTabs.test.tsx`
- [x] T019 [US3] Implement test: attachedバッジ表示 at `__tests__/components/SessionTabs.test.tsx`
- [x] T020 [US3] Implement test: 空セッション時のメッセージ表示 at `__tests__/components/SessionTabs.test.tsx`

**Checkpoint**: SessionTabs tests pass - `pnpm test SessionTabs`

---

## Phase 5: User Story 4 - TerminalView Test Coverage (Priority: P2)

**Goal**: 開発者がTerminalViewの動作を検証できるテストを実装

**Independent Test**: `pnpm test TerminalView` でTerminalViewのみテスト実行可能

### Implementation for User Story 4

- [x] T021 [P] [US4] Create test file with mock line/span data at `__tests__/components/TerminalView.test.tsx`
- [x] T022 [US4] Implement test: テキスト内容が表示される at `__tests__/components/TerminalView.test.tsx`
- [x] T023 [US4] Implement test: 前景色が適用される at `__tests__/components/TerminalView.test.tsx`
- [x] T024 [US4] Implement test: bold属性が適用される at `__tests__/components/TerminalView.test.tsx`
- [x] T025 [US4] Implement test: 空行の高さ at `__tests__/components/TerminalView.test.tsx`
- [x] T026 [US4] Implement test: カスタムテーマの背景色 at `__tests__/components/TerminalView.test.tsx`

**Checkpoint**: TerminalView tests pass - `pnpm test TerminalView`

---

## Phase 6: Polish & Validation

**Purpose**: 全体検証とクリーンアップ

- [x] T027 Run all tests with `pnpm test` and verify all pass
- [x] T028 Verify test coverage meets requirements (20 test cases minimum)
- [x] T029 Run `pnpm typecheck` to ensure type safety

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **User Stories (Phase 2-5)**: Depend on Setup completion
  - US1 and US2 are P1 priority - can run in parallel
  - US3 and US4 are P2 priority - can run in parallel
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (ConnectionCard)**: Can start after Setup - No dependencies on other stories
- **User Story 2 (SpecialKeys)**: Can start after Setup - No dependencies on other stories
- **User Story 3 (SessionTabs)**: Can start after Setup - No dependencies on other stories
- **User Story 4 (TerminalView)**: Can start after Setup - No dependencies on other stories

### Within Each User Story

- Create test file with mock setup first
- Implement individual test cases sequentially
- All test cases in same file - no [P] marker within story

### Parallel Opportunities

- All 4 user stories can run in parallel after Setup (T001-T002 complete)
- P1 stories (US1, US2) should be prioritized if sequential execution needed

---

## Parallel Example: All User Stories

```bash
# After Setup complete, launch all stories in parallel:
Task: "Create ConnectionCard.test.tsx" (US1)
Task: "Create SpecialKeys.test.tsx" (US2)
Task: "Create SessionTabs.test.tsx" (US3)
Task: "Create TerminalView.test.tsx" (US4)
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: ConnectionCard tests (P1)
3. Complete Phase 3: SpecialKeys tests (P1)
4. **STOP and VALIDATE**: `pnpm test` で2コンポーネントのテストがパス
5. Deploy/demo if ready

### Incremental Delivery

1. Setup → Foundation ready
2. Add US1 (ConnectionCard) → `pnpm test ConnectionCard` パス
3. Add US2 (SpecialKeys) → `pnpm test SpecialKeys` パス
4. Add US3 (SessionTabs) → `pnpm test SessionTabs` パス
5. Add US4 (TerminalView) → `pnpm test TerminalView` パス
6. Final: `pnpm test` で全テストパス

### Parallel Team Strategy

With multiple developers:

1. Complete Setup together
2. Once Setup is done:
   - Developer A: US1 (ConnectionCard) + US3 (SessionTabs)
   - Developer B: US2 (SpecialKeys) + US4 (TerminalView)
3. All tests complete and run together

---

## Notes

- 各テストファイルは独立して実行可能
- モックデータは各ファイル内にインラインで定義（DRY: 3回重複したら共通化検討）
- テストID(T001-T029)は実行順序を示す
- [P]マークは異なるファイルで並列実行可能なタスク
- [USn]マークはユーザーストーリー帰属を示す
