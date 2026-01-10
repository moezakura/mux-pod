# Implementation Plan: Flutter Migration

**Branch**: `001-flutter-migration` | **Date**: 2026-01-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-flutter-migration/spec.md`

## Summary

MuxPodをReact Native (Expo)からFlutterへ完全移行する。react-native-ssh-sftpのメンテナンス放棄問題を解決し、Pure Dart実装のdartssh2 + xterm.dartを採用することで、ネイティブ依存を排除しビルド安定性を向上させる。

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.24+
**Primary Dependencies**: dartssh2 2.13+, xterm 4.0+, flutter_riverpod, flutter_secure_storage, shared_preferences
**Storage**: SharedPreferences (接続設定), flutter_secure_storage (秘密鍵/パスワード暗号化)
**Testing**: flutter_test, mockito, integration_test
**Target Platform**: Android (API 21+) ※iOS/デスクトップは将来フェーズ
**Project Type**: mobile
**Performance Goals**: SSH接続5秒以内、入力レイテンシ200ms以下、1000行/秒でUIフリーズなし
**Constraints**: ネイティブパッチなしでビルド成功、ANSIカラー256色対応、CJK文字正常表示
**Scale/Scope**: 6画面 (接続一覧、ターミナル、鍵管理、通知ルール、設定、接続編集)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Phase 0 Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | Dart は静的型付け言語、`analysis_options.yaml` で strict mode 設定可能 |
| II. KISS & YAGNI | ✅ PASS | 既存RN実装の機能のみ移植、新機能追加なし |
| III. Test-First (TDD) | ✅ PASS | flutter_test + mockito でTDD可能 |
| IV. Security-First | ✅ PASS | flutter_secure_storage で暗号化保存、biometrics対応 |
| V. SOLID | ✅ PASS | Riverpod による DI、サービス層分離で対応 |
| VI. DRY | ✅ PASS | 共通ロジックはサービス層に集約 |
| Prohibited Naming | ✅ PASS | utils/, helpers/ 不使用、ドメイン名で命名 |

### Quality Gates Mapping (TypeScript → Dart)

| RN/TS Gate | Flutter/Dart Equivalent |
|------------|------------------------|
| `pnpm typecheck` | `dart analyze` |
| `pnpm lint` | `dart analyze` (lint rules in analysis_options.yaml) |
| 新機能テスト | `flutter test` |

### Post-Phase 1 Check (Design Validation)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | Freezedでイミュータブルモデル、strict mode設定 |
| II. KISS & YAGNI | ✅ PASS | 既存RN機能のみ移植、過度な抽象化なし |
| III. Test-First (TDD) | ✅ PASS | contracts/でインターフェース定義、mockitoでモック可能 |
| IV. Security-First | ✅ PASS | flutter_secure_storageで秘密鍵暗号化、biometrics対応設計 |
| V. SOLID | ✅ PASS | サービス層分離、Riverpod DI、インターフェース定義 |
| VI. DRY | ✅ PASS | Freezed codegen、共通Widget分離 |
| Prohibited Naming | ✅ PASS | services/ssh/, services/tmux/等ドメイン名で命名 |

**Conclusion**: All Constitution gates passed. Ready for Phase 2 (tasks generation).

## Project Structure

### Documentation (this feature)

```text
specs/001-flutter-migration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
flutter/                     # 新規Flutter プロジェクト
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── router/              # GoRouter ルーティング
│   │   └── app_router.dart
│   ├── models/              # データモデル (Freezed)
│   │   ├── connection.dart
│   │   ├── ssh_key.dart
│   │   ├── tmux.dart
│   │   ├── notification_rule.dart
│   │   └── app_settings.dart
│   ├── providers/           # Riverpod プロバイダー
│   │   ├── connection_provider.dart
│   │   ├── ssh_provider.dart
│   │   ├── tmux_provider.dart
│   │   ├── terminal_provider.dart
│   │   ├── key_provider.dart
│   │   ├── notification_provider.dart
│   │   └── settings_provider.dart
│   ├── services/            # ビジネスロジック
│   │   ├── ssh/
│   │   │   ├── ssh_client.dart
│   │   │   └── ssh_auth.dart
│   │   ├── tmux/
│   │   │   ├── tmux_commands.dart
│   │   │   └── tmux_parser.dart
│   │   ├── terminal/
│   │   │   └── terminal_controller.dart
│   │   ├── keychain/
│   │   │   └── secure_storage.dart
│   │   └── notification/
│   │       ├── notification_engine.dart
│   │       └── pattern_matcher.dart
│   ├── screens/             # 画面 Widget
│   │   ├── connections/
│   │   │   ├── connections_screen.dart
│   │   │   ├── connection_form_screen.dart
│   │   │   └── widgets/
│   │   ├── terminal/
│   │   │   ├── terminal_screen.dart
│   │   │   └── widgets/
│   │   ├── keys/
│   │   │   ├── keys_screen.dart
│   │   │   ├── key_generate_screen.dart
│   │   │   ├── key_import_screen.dart
│   │   │   └── widgets/
│   │   ├── notifications/
│   │   │   └── notification_rules_screen.dart
│   │   └── settings/
│   │       └── settings_screen.dart
│   ├── widgets/             # 共通 Widget
│   │   ├── terminal_view.dart
│   │   ├── special_keys_bar.dart
│   │   └── session_tree.dart
│   └── theme/               # テーマ定義
│       ├── app_theme.dart
│       └── terminal_colors.dart
├── test/
│   ├── unit/
│   │   ├── services/
│   │   └── providers/
│   ├── widget/
│   │   └── screens/
│   └── integration/
├── integration_test/
├── android/
├── pubspec.yaml
└── analysis_options.yaml
```

**Structure Decision**: モバイルアプリ構成。lib/ 配下にドメイン駆動の構造を採用。既存RNの src/ 構造を Flutter 規約に適合させ、providers/ (Riverpod) で状態管理、services/ でビジネスロジック、screens/ でUI を分離。

## Complexity Tracking

> **No Constitution violations identified. This section can be removed or left empty.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none) | - | - |
