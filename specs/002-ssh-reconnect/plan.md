# Implementation Plan: SSH再接続機能

**Branch**: `002-ssh-reconnect` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-ssh-reconnect/spec.md`

## Summary

SSH接続が切断された際にユーザーが迅速に状況を把握し、スムーズに再接続できる機能を実装する。主要機能は：

1. **接続状態インジケーター**: ターミナルヘッダーに常時表示、状態変化を即座に反映
2. **再接続確認ダイアログ**: 切断時に表示、再接続/キャンセルの選択肢を提供
3. **自動再接続**: 接続ごとにON/OFF可能、最大3回まで自動試行
4. **ReconnectService**: 再接続ロジックを分離、テスト容易性を確保

## Technical Context

**Language/Version**: TypeScript 5.6+
**Primary Dependencies**: Expo ~52.0.0, React Native 0.76.0, Zustand 5.0+, react-native-ssh-sftp
**Storage**: AsyncStorage (接続設定), expo-secure-store (パスワード暗号化)
**Testing**: Jest (ユニットテスト)
**Target Platform**: Android (モバイル)
**Project Type**: Mobile (Expo Router)
**Performance Goals**: 切断検出3秒以内、状態表示1秒以内
**Constraints**: モバイルバッテリー消費考慮、バックグラウンド処理制限
**Scale/Scope**: 単一アクティブ接続の再接続（複数同時再接続はスコープ外）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | 全ての新規型を`src/types/connection.ts`に定義 |
| II. KISS & YAGNI | ✅ PASS | シンプルな再試行ロジック、指数バックオフは除外 |
| III. Test-First | ✅ PASS | ReconnectServiceとStore拡張のテストを先行作成 |
| IV. Security-First | ✅ PASS | 認証情報はexpo-secure-storeから取得 |
| V. SOLID | ✅ PASS | ReconnectServiceを分離（SRP）、インターフェース定義（DIP） |
| VI. DRY | ✅ PASS | 既存のConnectionCardパターンを再利用 |
| Prohibited Naming | ✅ PASS | utils/helpers使用なし、具体的なサービス名使用 |

### Post-Design Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | data-model.mdで全型定義完了 |
| II. KISS & YAGNI | ✅ PASS | 最小限のコンポーネント構成 |
| III. Test-First | ✅ PASS | テスト戦略をresearch.mdに記載 |
| IV. Security-First | ✅ PASS | 認証フローをresearch.mdで確認 |
| V. SOLID | ✅ PASS | contracts/で全インターフェース定義 |
| VI. DRY | ✅ PASS | 既存パターンの再利用を確認 |

## Project Structure

### Documentation (this feature)

```text
specs/002-ssh-reconnect/
├── spec.md              # 機能仕様書
├── plan.md              # このファイル
├── research.md          # Phase 0: 技術調査結果
├── data-model.md        # Phase 1: データモデル定義
├── quickstart.md        # Phase 1: 実装クイックスタート
├── contracts/           # Phase 1: インターフェース定義
│   ├── reconnect-service.ts
│   ├── reconnect-dialog.tsx
│   ├── connection-status-indicator.tsx
│   └── connection-store-actions.ts
├── checklists/
│   └── requirements.md  # 仕様品質チェックリスト
└── tasks.md             # Phase 2: タスク一覧（/speckit.tasksで生成）
```

### Source Code (repository root)

```text
src/
├── components/
│   └── connection/
│       ├── ConnectionCard.tsx             # 既存
│       ├── ConnectionStatusIndicator.tsx  # 新規作成
│       ├── ReconnectDialog.tsx            # 新規作成
│       └── index.ts                       # 更新
├── services/
│   └── ssh/
│       ├── client.ts                      # 既存（onClose連携）
│       ├── reconnect.ts                   # 新規作成
│       └── index.ts                       # 更新
├── stores/
│   └── connectionStore.ts                 # 更新（再接続アクション追加）
└── types/
    └── connection.ts                      # 更新（型拡張）
```

**Structure Decision**: 既存のモバイルアプリ構造（Expo Router + src/）を維持し、ssh/services内に再接続サービスを追加。UIコンポーネントはconnection/に配置。

## Complexity Tracking

> **No violations - table not required**

Constitution Checkで全項目PASSのため、複雑性の正当化は不要。

## Phase 0 Output

- ✅ [research.md](./research.md) - 7つの技術決定を文書化

## Phase 1 Output

- ✅ [data-model.md](./data-model.md) - 3エンティティ定義（Connection拡張、ConnectionState拡張、ReconnectAttempt新規）
- ✅ [quickstart.md](./quickstart.md) - 実装手順と使用例
- ✅ [contracts/](./contracts/) - 4つのインターフェース定義
  - reconnect-service.ts - ReconnectServiceインターフェース
  - reconnect-dialog.tsx - ReconnectDialogコンポーネントProps
  - connection-status-indicator.tsx - ConnectionStatusIndicatorコンポーネントProps
  - connection-store-actions.ts - connectionStore拡張アクション

## Next Steps

1. `/speckit.tasks` を実行してタスク一覧を生成
2. 生成されたタスクに従って実装を開始
3. 各タスク完了時にテストを実行
