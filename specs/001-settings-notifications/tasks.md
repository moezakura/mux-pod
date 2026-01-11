# Tasks: Settings and Notifications Implementation

**Input**: Design documents from `/specs/001-settings-notifications/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Included per TDD principle in constitution (Test-First)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Mobile (Flutter)**: `lib/` for source, `test/` for tests
- Paths relative to repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and dependency setup

- [x] T001 Add url_launcher dependency via `flutter pub add url_launcher`
- [x] T002 [P] Create dialogs widget directory at `lib/widgets/dialogs/`
- [x] T003 [P] Verify existing providers work via `flutter analyze`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Convert MyApp to ConsumerWidget in `lib/main.dart` for dynamic theme support
- [x] T005 Add AndroidManifest.xml queries for url_launcher in `android/app/src/main/AndroidManifest.xml`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Terminal Font Configuration (Priority: P1)

**Goal**: ユーザーがフォントサイズとフォントファミリーを変更・保存できる

**Independent Test**: 設定画面でフォントサイズを変更し、アプリを再起動後も設定が保持される

### Tests for User Story 1

- [x] T006 [P] [US1] Create widget test for FontSizeDialog in `test/widgets/font_size_dialog_test.dart`
- [x] T007 [P] [US1] Create widget test for FontFamilyDialog in `test/widgets/font_family_dialog_test.dart`

### Implementation for User Story 1

- [x] T008 [P] [US1] Create FontSizeDialog widget in `lib/widgets/dialogs/font_size_dialog.dart`
- [x] T009 [P] [US1] Create FontFamilyDialog widget in `lib/widgets/dialogs/font_family_dialog.dart`
- [x] T010 [US1] Implement Font Size onTap handler in `lib/screens/settings/settings_screen.dart` (line 24)
- [x] T011 [US1] Implement Font Family onTap handler in `lib/screens/settings/settings_screen.dart` (line 32)
- [x] T012 [US1] Update Font Size subtitle to show current value from settingsProvider in `lib/screens/settings/settings_screen.dart`
- [x] T013 [US1] Update Font Family subtitle to show current value from settingsProvider in `lib/screens/settings/settings_screen.dart`

**Checkpoint**: User Story 1 fully functional - font settings persist across app restarts

---

## Phase 4: User Story 2 - Notification Rule Management (Priority: P1)

**Goal**: ユーザーが通知ルールを作成・編集・削除・保存できる

**Independent Test**: 新しい通知ルールを作成してアプリを再起動後、ルールが保持される

### Tests for User Story 2

- [x] T014 [P] [US2] Create widget test for NotificationRulesScreen in `test/screens/notification_rules_screen_test.dart`

### Implementation for User Story 2

- [x] T015 [US2] Add notificationProvider watch to build rule list in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T016 [US2] Replace empty Center widget with ListView.builder for rules in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T017 [US2] Create rule list item widget with Dismissible for swipe-to-delete in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T018 [US2] Add rule enable/disable toggle Switch to list item in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T019 [US2] Implement _save method to call notificationProvider.addRule/updateRule in `lib/screens/notifications/notification_rules_screen.dart` (line 139)
- [x] T020 [US2] Add ConsumerStatefulWidget to _RuleFormDialog for ref access in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T021 [US2] Implement rule tap to edit (pass existing rule to dialog) in `lib/screens/notifications/notification_rules_screen.dart`
- [x] T022 [US2] Add delete confirmation dialog before Dismissible completes in `lib/screens/notifications/notification_rules_screen.dart`

**Checkpoint**: User Story 2 fully functional - notification rules CRUD with persistence

---

## Phase 5: User Story 3 - Behavior Settings Persistence (Priority: P2)

**Goal**: ユーザーがHaptic FeedbackとKeep Screen On設定を変更・保存できる

**Independent Test**: Haptic Feedbackをオフにしてアプリを再起動後、オフのまま

### Tests for User Story 3

- [x] T023 [P] [US3] Create widget test for behavior settings toggles in `test/screens/settings_screen_test.dart`

### Implementation for User Story 3

- [x] T024 [US3] Wire Haptic Feedback SwitchListTile value to settingsProvider.enableVibration in `lib/screens/settings/settings_screen.dart` (line 40-44)
- [x] T025 [US3] Wire Keep Screen On SwitchListTile value to settingsProvider (add new field if needed) in `lib/screens/settings/settings_screen.dart` (line 49-53)
- [x] T026 [US3] Add keepScreenOn field to AppSettings if not present in `lib/providers/settings_provider.dart`

**Checkpoint**: User Story 3 fully functional - behavior settings persist

---

## Phase 6: User Story 4 - Theme Selection (Priority: P2)

**Goal**: ユーザーがアプリテーマ（Dark/Light）を変更できる

**Independent Test**: テーマをライトに変更し、アプリ全体の表示が即座に切り替わる

### Tests for User Story 4

- [x] T027 [P] [US4] Create widget test for ThemeDialog in `test/widgets/theme_dialog_test.dart`

### Implementation for User Story 4

- [x] T028 [US4] Create ThemeDialog widget in `lib/widgets/dialogs/theme_dialog.dart`
- [x] T029 [US4] Implement Theme onTap handler in `lib/screens/settings/settings_screen.dart` (line 77)
- [x] T030 [US4] Update Theme subtitle to show current value from settingsProvider in `lib/screens/settings/settings_screen.dart`
- [x] T031 [US4] Ensure MyApp rebuilds with new themeMode when darkMode changes in `lib/main.dart`

**Checkpoint**: User Story 4 fully functional - theme changes immediately and persists

---

## Phase 7: User Story 5 - External Links (Priority: P3)

**Goal**: ユーザーがSource Codeリンクをタップして外部ブラウザでGitHubを開ける

**Independent Test**: Source Codeをタップして外部ブラウザでGitHubが開く

### Tests for User Story 5

- [x] T032 [P] [US5] Create widget test for external link tap in `test/screens/settings_screen_test.dart`

### Implementation for User Story 5

- [x] T033 [US5] Import url_launcher in `lib/screens/settings/settings_screen.dart`
- [x] T034 [US5] Implement Source Code onTap handler with launchUrl in `lib/screens/settings/settings_screen.dart` (line 93)

**Checkpoint**: User Story 5 fully functional - external link opens in browser

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T035 [P] Run flutter analyze and fix any warnings
- [x] T036 [P] Run flutter test and ensure all tests pass
- [ ] T037 [P] Run quickstart.md verification checklist manually
- [x] T038 Code review for constitution compliance (KISS, DRY, SOLID)
- [ ] T039 Verify all settings persist across app restart (integration test)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 are both P1, can run in parallel
  - US3 and US4 are both P2, can run in parallel after P1
  - US5 is P3, can run after P2
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 3 (P2)**: Can start after Foundational - No dependencies on other stories
- **User Story 4 (P2)**: Depends on T004 (main.dart ConsumerWidget) from Foundational
- **User Story 5 (P3)**: Depends on T001 (url_launcher) and T005 (AndroidManifest) from Setup/Foundational

### Within Each User Story

- Tests MUST be written and FAIL before implementation (TDD)
- Dialog widgets before screen integration
- Screen modifications after dialogs complete
- Commit after each task or logical group

### Parallel Opportunities

- T002, T003 can run in parallel (Setup)
- T006, T007 can run in parallel (US1 tests)
- T008, T009 can run in parallel (US1 dialogs)
- T014, T023, T027, T032 can all run in parallel (tests across stories)
- US1 and US2 can be worked on in parallel (both P1)
- US3 and US4 can be worked on in parallel (both P2)

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create widget test for FontSizeDialog in test/widgets/font_size_dialog_test.dart"
Task: "Create widget test for FontFamilyDialog in test/widgets/font_family_dialog_test.dart"

# Launch all dialog widgets for User Story 1 together:
Task: "Create FontSizeDialog widget in lib/widgets/dialogs/font_size_dialog.dart"
Task: "Create FontFamilyDialog widget in lib/widgets/dialogs/font_family_dialog.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Font Configuration)
4. Complete Phase 4: User Story 2 (Notification Rules)
5. **STOP and VALIDATE**: Test US1 + US2 independently
6. Deploy/demo if ready - core settings and notifications work

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Font settings work
3. Add User Story 2 → Test independently → Notification rules work (MVP!)
4. Add User Story 3 → Test independently → Behavior settings work
5. Add User Story 4 → Test independently → Theme switching works
6. Add User Story 5 → Test independently → External links work
7. Each story adds value without breaking previous stories

### Suggested MVP Scope

**US1 + US2 = MVP**: Font configuration and notification rule management are the core features. Behavior settings (US3), theme (US4), and external links (US5) are nice-to-have polish.

---

## Summary

| Metric | Count |
|--------|-------|
| Total Tasks | 39 |
| Setup Tasks | 3 |
| Foundational Tasks | 2 |
| US1 Tasks | 8 |
| US2 Tasks | 9 |
| US3 Tasks | 4 |
| US4 Tasks | 5 |
| US5 Tasks | 3 |
| Polish Tasks | 5 |
| Parallel Opportunities | 14 tasks marked [P] |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (TDD)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
