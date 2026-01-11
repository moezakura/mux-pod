# Implementation Plan: SSH鍵管理機能

**Branch**: `003-ssh-key-management` | **Date**: 2026-01-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-ssh-key-management/spec.md`

## Summary

SSH鍵管理機能を実装する。Ed25519およびRSA鍵の生成、ファイルピッカーを使用した秘密鍵のインポート、鍵一覧の表示・削除機能を提供する。既存の`SecureStorageService`と`KeysNotifier`を活用し、画面間遷移とTODOコメントの解決を行う。

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.24+
**Primary Dependencies**:
- `dartssh2` (SSH接続・鍵パース)
- `cryptography` (Ed25519鍵生成)
- `pointycastle` (RSA鍵生成)
- `file_picker` (ファイル選択 - 新規追加)
- `flutter_riverpod` (状態管理)

**Storage**:
- `flutter_secure_storage` (秘密鍵・パスフレーズ)
- `shared_preferences` (鍵メタデータ)

**Testing**: `flutter_test`
**Target Platform**: Android 6.0+ (API 23+)
**Project Type**: Mobile (Flutter)
**Performance Goals**:
- Ed25519鍵生成: 30秒以内
- RSA-4096鍵生成: 60秒以内
- 鍵一覧表示: 2秒以内

**Constraints**:
- 秘密鍵は暗号化ストレージにのみ保存
- パスフレーズ付き鍵のサポート必須

**Scale/Scope**: 単一ユーザー、~100鍵程度の管理を想定

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | Dart strict mode、型ガード使用 |
| II. KISS & YAGNI | ✅ PASS | 既存コード活用、必要最小限の実装 |
| III. Test-First | ✅ PASS | 鍵生成・パースロジックのテスト作成 |
| IV. Security-First | ✅ PASS | flutter_secure_storage使用、ログに鍵情報なし |
| V. SOLID | ✅ PASS | SshKeyService分離、Provider活用 |
| VI. DRY | ✅ PASS | SecureStorageService再利用 |
| Prohibited Naming | ✅ PASS | utils/helpers使用なし |

## Project Structure

### Documentation (this feature)

```text
specs/003-ssh-key-management/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
lib/
├── providers/
│   └── key_provider.dart        # 既存: SshKeyMeta, KeysNotifier
├── screens/keys/
│   ├── keys_screen.dart         # 修正: 画面遷移追加
│   ├── key_generate_screen.dart # 修正: 鍵生成ロジック追加
│   ├── key_import_screen.dart   # 修正: ファイルピッカー・インポート追加
│   └── widgets/
│       └── key_tile.dart        # 既存: 鍵表示Widget
└── services/
    └── keychain/
        ├── secure_storage.dart  # 既存: セキュアストレージ
        └── ssh_key_service.dart # 新規: 鍵生成・パースロジック

test/
├── services/
│   └── keychain/
│       └── ssh_key_service_test.dart # 新規: 鍵生成テスト
└── screens/keys/
    └── key_screens_test.dart    # 新規: 画面テスト
```

**Structure Decision**: 既存のFlutterプロジェクト構造を維持。`lib/services/keychain/`に新規`ssh_key_service.dart`を追加し、鍵生成・パースロジックを集約。

## Complexity Tracking

> **No Constitution violations. Table intentionally empty.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| - | - | - |
