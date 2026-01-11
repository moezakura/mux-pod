# Implementation Plan: Settings and Notifications

**Branch**: `001-settings-notifications` | **Date**: 2026-01-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-settings-notifications/spec.md`

## Summary

設定画面のTODOコメント解決と通知ルール管理機能の完全実装。既存の`settingsProvider`と`notificationProvider`を活用し、フォントサイズ/ファミリー選択ダイアログ、動作設定の永続化、テーマ選択、通知ルールのCRUD操作を実装する。

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.24+
**Primary Dependencies**: flutter_riverpod, shared_preferences, flutter_local_notifications, url_launcher
**Storage**: SharedPreferences（設定）、SharedPreferences（通知ルール - JSON形式）
**Testing**: flutter_test, mockito
**Target Platform**: Android（iOS対応予定）
**Project Type**: Mobile
**Performance Goals**: 設定変更は1秒以内に保存、50件のルールで2秒以内にリスト表示
**Constraints**: オフライン対応不要（ローカルストレージのみ）
**Scale/Scope**: 単一ユーザー、ルール数上限なし

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | PASS | Dartの型システムで厳密に型定義済み |
| II. KISS & YAGNI | PASS | 既存プロバイダーを活用、新規抽象化なし |
| III. Test-First (TDD) | PASS | 各機能にテストを作成 |
| IV. Security-First | PASS | 設定データに機密情報なし（SSH鍵は別管理） |
| V. SOLID | PASS | SRP: 設定と通知は別プロバイダーで分離済み |
| VI. DRY | PASS | 既存のAppSettingsとNotificationRuleを再利用 |
| Prohibited Naming | PASS | utils/helpers不使用、screens/services構造 |

**Gate Result**: PASS - すべての原則を遵守

## Project Structure

### Documentation (this feature)

```text
specs/001-settings-notifications/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A for mobile-only)
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
lib/
├── main.dart
├── providers/
│   ├── settings_provider.dart    # 既存 - 活用
│   └── notification_provider.dart # 既存 - 活用
├── screens/
│   ├── settings/
│   │   └── settings_screen.dart  # 修正対象
│   └── notifications/
│       └── notification_rules_screen.dart # 修正対象
├── services/
│   └── notification/
│       └── notification_engine.dart # 既存 - 活用
├── theme/
│   └── app_theme.dart            # テーマ管理
└── widgets/
    └── dialogs/                  # 新規ダイアログウィジェット

test/
├── providers/
│   ├── settings_provider_test.dart
│   └── notification_provider_test.dart
├── screens/
│   ├── settings_screen_test.dart
│   └── notification_rules_screen_test.dart
└── widgets/
    └── dialogs_test.dart
```

**Structure Decision**: Mobile単一プロジェクト構造。既存のFlutter標準構造を維持。

## Complexity Tracking

> 違反なし - 追加の複雑性正当化は不要
