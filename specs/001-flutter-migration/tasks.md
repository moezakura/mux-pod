# Tasks: Flutter Migration

**Input**: Design documents from `/specs/001-flutter-migration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: TDD approach enabled (Constitution Principle III)

**Organization**: Tasks grouped by user story to enable independent implementation and testing

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

All paths relative to `flutter/` project directory:
- **Models**: `lib/models/`
- **Services**: `lib/services/`
- **Providers**: `lib/providers/`
- **Screens**: `lib/screens/`
- **Widgets**: `lib/widgets/`
- **Tests**: `test/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Flutter project initialization and basic structure

- [x] T001 Create Flutter project in `flutter/` directory with `flutter create --org com.muxpod --project-name muxpod flutter`
- [x] T002 Configure `flutter/pubspec.yaml` with all dependencies (dartssh2, xterm, flutter_riverpod, flutter_secure_storage, shared_preferences, freezed, go_router)
- [x] T003 [P] Configure `flutter/analysis_options.yaml` with strict mode and lint rules
- [x] T004 [P] Create directory structure per plan.md (lib/models, lib/services, lib/providers, lib/screens, lib/widgets, lib/theme, lib/router)
- [x] T005 [P] Add font assets (JetBrainsMono, HackGen) to `flutter/assets/fonts/`
- [x] T006 Run `flutter pub get` and `dart run build_runner build` to verify setup

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Core App Structure

- [x] T007 Create `flutter/lib/main.dart` with ProviderScope and app initialization
- [x] T008 Create `flutter/lib/app.dart` with MaterialApp and GoRouter configuration
- [x] T009 Create `flutter/lib/router/app_router.dart` with all route definitions

### Shared Models (Freezed)

- [x] T010 [P] Create AuthMethod model in `flutter/lib/models/auth_method.dart`
- [x] T011 [P] Create base enums (KeyType, FontFamily, ColorTheme, NotificationAction, NotificationFrequency) in `flutter/lib/models/enums.dart`
- [x] T012 Run code generation: `dart run build_runner build --delete-conflicting-outputs`

### Theme System

- [x] T013 [P] Create terminal color themes in `flutter/lib/theme/terminal_colors.dart`
- [x] T014 [P] Create app theme in `flutter/lib/theme/app_theme.dart`

### Storage Infrastructure

- [x] T015 Create SecureStorageService in `flutter/lib/services/keychain/secure_storage.dart`
- [x] T016 Create StorageService (SharedPreferences wrapper) in `flutter/lib/services/storage/storage_service.dart`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1+2 - SSH接続・ターミナル操作 + 接続管理 (Priority: P1) 🎯 MVP

**Goal**: ユーザーがSSH接続設定を追加し、サーバーに接続してtmuxペイン内でコマンドを実行できる

**Independent Test**: 接続設定を追加し、サーバーに接続、tmuxペイン内でlsコマンドを実行して結果が表示される

**Note**: US1とUS2は密接に関連しており（接続なしにターミナル操作なし）、MVPとして一緒に実装

### Tests for US1+US2 (TDD)

- [ ] T017 [P] [US1] Unit test for SSHClient in `flutter/test/unit/services/ssh_client_test.dart` (後回し - SSHモック複雑)
- [ ] T018 [P] [US1] Unit test for TmuxCommands in `flutter/test/unit/services/tmux_commands_test.dart` (後回し)
- [ ] T019 [P] [US2] Unit test for ConnectionProvider in `flutter/test/unit/providers/connection_provider_test.dart` (後回し)
- [ ] T020 [P] [US2] Widget test for ConnectionsScreen in `flutter/test/widget/screens/connections_screen_test.dart` (後回し)
- [ ] T021 [P] [US1] Widget test for TerminalScreen in `flutter/test/widget/screens/terminal_screen_test.dart` (後回し)

### Models for US1+US2

- [x] T022 [P] [US2] Create Connection model in `flutter/lib/models/connection.dart`
- [x] T023 [P] [US1] Create TmuxSession model in `flutter/lib/models/tmux.dart`
- [x] T024 [P] [US1] Create TmuxWindow model in `flutter/lib/models/tmux.dart`
- [x] T025 [P] [US1] Create TmuxPane model in `flutter/lib/models/tmux.dart`
- [x] T026 Run code generation: `dart run build_runner build`

### Services for US1+US2

- [x] T027 [US2] Implement ConnectionRepository in `flutter/lib/services/storage/connection_repository.dart`
- [x] T028 [US1] Implement SSHClient (dartssh2 wrapper) in `flutter/lib/services/ssh/ssh_client.dart`
- [x] T029 [US1] Implement SSHAuthService in `flutter/lib/services/ssh/ssh_auth.dart`
- [x] T030 [US1] Implement TmuxCommands in `flutter/lib/services/tmux/tmux_commands.dart`
- [x] T031 [US1] Implement TmuxParser in `flutter/lib/services/tmux/tmux_parser.dart`
- [x] T032 [US1] Implement TerminalController in `flutter/lib/services/terminal/terminal_controller.dart`

### Providers for US1+US2

- [x] T033 [P] [US2] Create ConnectionProvider in `flutter/lib/providers/connection_provider.dart`
- [x] T034 [P] [US1] Create SSHProvider in `flutter/lib/providers/ssh_provider.dart`
- [x] T035 [P] [US1] Create TmuxProvider in `flutter/lib/providers/tmux_provider.dart`
- [x] T036 [P] [US1] Create TerminalProvider in `flutter/lib/providers/terminal_provider.dart`

### Widgets for US1+US2

- [ ] T037 [P] [US1] Create TerminalView widget in `flutter/lib/widgets/terminal_view.dart`
- [ ] T038 [P] [US1] Create SpecialKeysBar widget in `flutter/lib/widgets/special_keys_bar.dart`
- [ ] T039 [P] [US1] Create SessionTree widget in `flutter/lib/widgets/session_tree.dart`

### Screens for US1+US2

- [ ] T040 [US2] Create ConnectionsScreen in `flutter/lib/screens/connections/connections_screen.dart`
- [ ] T041 [US2] Create ConnectionCard widget in `flutter/lib/screens/connections/widgets/connection_card.dart`
- [ ] T042 [US2] Create ConnectionFormScreen in `flutter/lib/screens/connections/connection_form_screen.dart`
- [ ] T043 [US1] Create TerminalScreen in `flutter/lib/screens/terminal/terminal_screen.dart`
- [ ] T044 [US1] Create TerminalToolbar widget in `flutter/lib/screens/terminal/widgets/terminal_toolbar.dart`

### Integration

- [ ] T045 [US1] Integrate xterm.dart with SSHClient in TerminalScreen
- [ ] T046 [US1] Implement PTY resize sync on terminal size change
- [ ] T047 [US1] Implement error handling and reconnection UI
- [ ] T048 [US2] Implement connection edit and delete functionality

**Checkpoint**: MVP complete - Users can add connections, connect via SSH, and interact with tmux panes

---

## Phase 4: User Story 3 - SSH鍵管理 (Priority: P2)

**Goal**: ユーザーがSSH鍵を生成/インポートし、鍵認証でサーバーに接続できる

**Independent Test**: 鍵を生成し、その鍵を使用してサーバーに接続できる

### Tests for US3 (TDD)

- [ ] T049 [P] [US3] Unit test for KeyService in `flutter/test/unit/services/key_service_test.dart`
- [ ] T050 [P] [US3] Widget test for KeysScreen in `flutter/test/widget/screens/keys_screen_test.dart`

### Models for US3

- [ ] T051 [US3] Create SSHKey model in `flutter/lib/models/ssh_key.dart`
- [ ] T052 Run code generation: `dart run build_runner build`

### Services for US3

- [ ] T053 [US3] Implement KeyRepository in `flutter/lib/services/keychain/key_repository.dart`
- [ ] T054 [US3] Implement KeyGenerationService in `flutter/lib/services/keychain/key_generation.dart`
- [ ] T055 [US3] Implement KeyImportService in `flutter/lib/services/keychain/key_import.dart`

### Providers for US3

- [ ] T056 [US3] Create KeyProvider in `flutter/lib/providers/key_provider.dart`

### Screens for US3

- [ ] T057 [US3] Create KeysScreen in `flutter/lib/screens/keys/keys_screen.dart`
- [ ] T058 [US3] Create KeyCard widget in `flutter/lib/screens/keys/widgets/key_card.dart`
- [ ] T059 [US3] Create KeyGenerateScreen in `flutter/lib/screens/keys/key_generate_screen.dart`
- [ ] T060 [US3] Create KeyImportScreen in `flutter/lib/screens/keys/key_import_screen.dart`

### Integration

- [ ] T061 [US3] Integrate key selection in ConnectionFormScreen
- [ ] T062 [US3] Implement key-based authentication in SSHAuthService

**Checkpoint**: Users can generate SSH keys, import existing keys, and use them for authentication

---

## Phase 5: User Story 4 - tmuxナビゲーション (Priority: P2)

**Goal**: ユーザーがtmuxセッション/ウィンドウ/ペインを階層的にナビゲーションできる

**Independent Test**: 複数セッションがある状態で、セッション/ウィンドウ/ペイン間を移動できる

### Tests for US4 (TDD)

- [ ] T063 [P] [US4] Unit test for TmuxNavigationService in `flutter/test/unit/services/tmux_navigation_test.dart`
- [ ] T064 [P] [US4] Widget test for SessionTree in `flutter/test/widget/widgets/session_tree_test.dart`

### Services for US4

- [ ] T065 [US4] Implement TmuxNavigationService in `flutter/lib/services/tmux/tmux_navigation.dart`

### Providers for US4

- [ ] T066 [US4] Enhance TmuxProvider with navigation state in `flutter/lib/providers/tmux_provider.dart`

### Screens for US4

- [ ] T067 [US4] Create SessionListDrawer in `flutter/lib/screens/terminal/widgets/session_list_drawer.dart`
- [ ] T068 [US4] Create WindowTabBar in `flutter/lib/screens/terminal/widgets/window_tab_bar.dart`
- [ ] T069 [US4] Create PaneSelector in `flutter/lib/screens/terminal/widgets/pane_selector.dart`

### Integration

- [ ] T070 [US4] Implement swipe gestures for pane/window switching
- [ ] T071 [US4] Implement session creation from app

**Checkpoint**: Users can navigate between tmux sessions, windows, and panes with gestures and UI

---

## Phase 6: User Story 5 - 通知ルール (Priority: P3)

**Goal**: ユーザーがターミナル出力パターンにマッチする通知ルールを設定し、通知を受け取れる

**Independent Test**: 「error」というテキストルールを設定し、ターミナルにerrorが表示されたら通知が発生する

### Tests for US5 (TDD)

- [ ] T072 [P] [US5] Unit test for NotificationEngine in `flutter/test/unit/services/notification_engine_test.dart`
- [ ] T073 [P] [US5] Unit test for PatternMatcher in `flutter/test/unit/services/pattern_matcher_test.dart`

### Models for US5

- [ ] T074 [US5] Create NotificationRule model in `flutter/lib/models/notification_rule.dart`
- [ ] T075 [US5] Create NotificationCondition model in `flutter/lib/models/notification_rule.dart`
- [ ] T076 Run code generation: `dart run build_runner build`

### Services for US5

- [ ] T077 [US5] Implement PatternMatcher in `flutter/lib/services/notification/pattern_matcher.dart`
- [ ] T078 [US5] Implement NotificationEngine in `flutter/lib/services/notification/notification_engine.dart`
- [ ] T079 [US5] Implement NotificationRepository in `flutter/lib/services/notification/notification_repository.dart`

### Providers for US5

- [ ] T080 [US5] Create NotificationProvider in `flutter/lib/providers/notification_provider.dart`

### Screens for US5

- [ ] T081 [US5] Create NotificationRulesScreen in `flutter/lib/screens/notifications/notification_rules_screen.dart`
- [ ] T082 [US5] Create RuleCard widget in `flutter/lib/screens/notifications/widgets/rule_card.dart`
- [ ] T083 [US5] Create RuleFormDialog in `flutter/lib/screens/notifications/widgets/rule_form_dialog.dart`

### Integration

- [ ] T084 [US5] Integrate NotificationEngine with TerminalController to monitor output
- [ ] T085 [US5] Implement in-app notification UI (snackbar/overlay)

**Checkpoint**: Users can create notification rules and receive alerts when patterns match

---

## Phase 7: User Story 6 - 表示設定 (Priority: P3)

**Goal**: ユーザーがターミナルのフォント、サイズ、カラーテーマをカスタマイズできる

**Independent Test**: フォントサイズを変更し、ターミナル表示に反映される

### Tests for US6 (TDD)

- [ ] T086 [P] [US6] Unit test for SettingsProvider in `flutter/test/unit/providers/settings_provider_test.dart`
- [ ] T087 [P] [US6] Widget test for SettingsScreen in `flutter/test/widget/screens/settings_screen_test.dart`

### Models for US6

- [ ] T088 [US6] Create AppSettings model in `flutter/lib/models/app_settings.dart`
- [ ] T089 [US6] Create DisplaySettings, TerminalSettings, SshSettings, SecuritySettings in `flutter/lib/models/app_settings.dart`
- [ ] T090 [US6] Create TerminalColors model in `flutter/lib/models/terminal_colors.dart`
- [ ] T091 Run code generation: `dart run build_runner build`

### Services for US6

- [ ] T092 [US6] Implement SettingsRepository in `flutter/lib/services/storage/settings_repository.dart`

### Providers for US6

- [ ] T093 [US6] Create SettingsProvider in `flutter/lib/providers/settings_provider.dart`

### Screens for US6

- [ ] T094 [US6] Create SettingsScreen in `flutter/lib/screens/settings/settings_screen.dart`
- [ ] T095 [US6] Create DisplaySettingsSection in `flutter/lib/screens/settings/widgets/display_settings_section.dart`
- [ ] T096 [US6] Create TerminalSettingsSection in `flutter/lib/screens/settings/widgets/terminal_settings_section.dart`
- [ ] T097 [US6] Create SecuritySettingsSection in `flutter/lib/screens/settings/widgets/security_settings_section.dart`

### Integration

- [ ] T098 [US6] Apply settings to TerminalView (font, size, colors)
- [ ] T099 [US6] Implement biometric unlock option

**Checkpoint**: Users can customize terminal appearance and app settings persist across sessions

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T100 [P] Add error boundary and crash handling in `flutter/lib/app.dart`
- [ ] T101 [P] Implement loading states and skeleton screens across all screens
- [ ] T102 [P] Add app icon and splash screen in `flutter/android/`
- [ ] T103 Performance optimization: optimize terminal rendering for high-throughput output
- [ ] T104 Run `dart analyze` and fix all warnings
- [ ] T105 Run `flutter test` and ensure all tests pass
- [ ] T106 Validate against quickstart.md scenarios
- [ ] T107 Build release APK: `flutter build apk --release`

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
     ↓
Phase 2 (Foundational) ← BLOCKS all user stories
     ↓
┌────┴────┬────────┬────────┬────────┐
↓         ↓        ↓        ↓        ↓
Phase 3   Phase 4  Phase 5  Phase 6  Phase 7
(US1+US2) (US3)    (US4)    (US5)    (US6)
 MVP!      ↓        ↓        ↓        ↓
           └────────┴────────┴────────┘
                      ↓
               Phase 8 (Polish)
```

### User Story Dependencies

| Story | Depends On | Can Run In Parallel With |
|-------|-----------|--------------------------|
| US1+US2 (MVP) | Foundational | - |
| US3 (SSH鍵) | Foundational | US1+US2, US4, US5, US6 |
| US4 (tmuxナビ) | Foundational | US3, US5, US6 |
| US5 (通知) | Foundational | US3, US4, US6 |
| US6 (設定) | Foundational | US3, US4, US5 |

### Within Each User Story

1. Tests MUST be written and FAIL before implementation (TDD)
2. Models before Services
3. Services before Providers
4. Providers before Screens
5. Integration tasks last

---

## Parallel Opportunities

### Phase 1 (Setup)

```bash
# Parallel tasks:
T003, T004, T005  # Can all run in parallel
```

### Phase 2 (Foundational)

```bash
# Parallel tasks:
T010, T011        # Shared models
T013, T014        # Theme files
```

### Phase 3 (US1+US2 MVP)

```bash
# Tests in parallel:
T017, T018, T019, T020, T021

# Models in parallel:
T022, T023, T024, T025

# Providers in parallel:
T033, T034, T035, T036

# Widgets in parallel:
T037, T038, T039
```

### Phase 4-7 (US3-US6)

Each user story can be worked on independently by different developers after Phase 2 completes.

---

## Implementation Strategy

### MVP First (Phase 1-3)

1. Complete Phase 1: Setup (6 tasks)
2. Complete Phase 2: Foundational (10 tasks)
3. Complete Phase 3: US1+US2 MVP (32 tasks)
4. **STOP and VALIDATE**: Full end-to-end test
5. Deploy/demo MVP APK

**MVP Scope**: 48 tasks total for working SSH terminal with connection management

### Incremental Delivery

| Milestone | Phases | Cumulative Tasks | Deliverable |
|-----------|--------|------------------|-------------|
| MVP | 1-3 | 48 | SSH接続+ターミナル操作 |
| +SSH鍵 | 4 | 62 | 鍵認証サポート |
| +tmuxナビ | 5 | 71 | 高度なナビゲーション |
| +通知 | 6 | 85 | パターンマッチ通知 |
| +設定 | 7 | 99 | カスタマイズ |
| Complete | 8 | 107 | 本番リリース |

---

## Summary

| Category | Count |
|----------|-------|
| **Total Tasks** | 107 |
| Phase 1 (Setup) | 6 |
| Phase 2 (Foundational) | 10 |
| Phase 3 (US1+US2 MVP) | 32 |
| Phase 4 (US3 SSH鍵) | 14 |
| Phase 5 (US4 tmuxナビ) | 9 |
| Phase 6 (US5 通知) | 14 |
| Phase 7 (US6 設定) | 14 |
| Phase 8 (Polish) | 8 |
| **Parallel Opportunities** | 42 tasks marked [P] |

---

## Notes

- [P] tasks = different files, no dependencies
- [US#] label maps task to specific user story
- Each user story is independently completable and testable after Phase 2
- TDD enabled: Write tests first, ensure they fail, then implement
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
