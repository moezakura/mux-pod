# Implementation Plan: Component Tests

**Branch**: `001-component-tests` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-component-tests/spec.md`

## Summary

4つの主要UIコンポーネント（ConnectionCard, TerminalView, SpecialKeys, SessionTabs）に対するReact Native Testing Libraryを使用したコンポーネントテストを追加する。既存のjest.config.jsとjest.setup.jsを活用し、__tests__/components/ディレクトリにテストファイルを配置する。

## Technical Context

**Language/Version**: TypeScript 5.6+
**Primary Dependencies**: React Native 0.76.0, Expo ~52.0.0, React Native Testing Library
**Storage**: N/A（テスト機能のため永続化不要）
**Testing**: Jest (jest-expo preset), React Native Testing Library, @testing-library/jest-native
**Target Platform**: Android (React Native)
**Project Type**: mobile
**Performance Goals**: N/A（テスト機能）
**Constraints**: 既存のjest設定を使用、@expo/vector-iconsのモックが必要
**Scale/Scope**: 4コンポーネント × 5テストケース = 20テストケース

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type Safety | ✅ PASS | テストファイルもTypeScriptで型安全に記述 |
| II. KISS & YAGNI | ✅ PASS | 必要最小限のテストのみ実装 |
| III. Test-First (TDD) | ✅ PASS | テスト追加が目的であり、TDDを推進 |
| IV. Security-First | ✅ PASS | テストではモックを使用、実認証情報は使用しない |
| V. SOLID | ✅ PASS | 各テストファイルは単一コンポーネントのみを対象 |
| VI. DRY | ✅ PASS | 共通モックやヘルパーは適切に共有 |
| Prohibited Naming | ✅ PASS | __tests__/components/は標準的なJest命名規則 |

**GATE RESULT**: ✅ ALL PASS - 違反なし

## Project Structure

### Documentation (this feature)

```text
specs/001-component-tests/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal - test fixtures)
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
__tests__/
└── components/
    ├── ConnectionCard.test.tsx
    ├── TerminalView.test.tsx
    ├── SpecialKeys.test.tsx
    └── SessionTabs.test.tsx

src/
├── components/
│   ├── connection/
│   │   └── ConnectionCard.tsx      # テスト対象
│   ├── terminal/
│   │   ├── TerminalView.tsx        # テスト対象
│   │   └── SpecialKeys.tsx         # テスト対象
│   └── navigation/
│       └── SessionTabs.tsx         # テスト対象
└── types/
    ├── connection.ts               # テストで使用するモックデータの型
    ├── tmux.ts                     # テストで使用するモックデータの型
    └── terminal.ts                 # テストで使用するモックデータの型
```

**Structure Decision**: 既存のMuxPodプロジェクト構造に従い、__tests__/components/ディレクトリにテストファイルを配置。jest.config.jsの`testMatch`パターン (`**/__tests__/**/*.test.{ts,tsx}`) に準拠。

## Complexity Tracking

> 違反なし - このセクションは空

