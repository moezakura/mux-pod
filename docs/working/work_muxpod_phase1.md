# タスク: MuxPod Phase 1 MVP

## 概要

MuxPod Phase 1 MVPの実装。SSH接続基盤、接続管理UI、tmux基本操作、ターミナル表示、キー入力機能を実装する。

## 担当エージェント

- 実装1: %100 (claude) - プロジェクト初期化 + SSH/tmux基盤
- 実装2: %101 (claude) - UI/画面実装
- レビュー: %102 (claude) - コードレビュー

## Phase 1 タスク分解

### 1. プロジェクト初期化（実装1担当）
- [ ] Expo プロジェクト作成 (`npx create-expo-app`)
- [ ] TypeScript 設定
- [ ] ディレクトリ構成作成
- [ ] 依存パッケージインストール

### 2. SSH接続基盤（実装1担当）
- [ ] src/services/ssh/client.ts - SSHクライアント
- [ ] src/services/ssh/auth.ts - 認証処理
- [ ] src/types/connection.ts - 接続型定義

### 3. tmux操作（実装1担当）
- [ ] src/services/tmux/commands.ts - tmuxコマンド
- [ ] src/services/tmux/parser.ts - 出力パーサー
- [ ] src/types/tmux.ts - tmux型定義

### 4. 状態管理（実装2担当）
- [ ] src/stores/connectionStore.ts
- [ ] src/stores/sessionStore.ts
- [ ] src/stores/terminalStore.ts
- [ ] src/stores/settingsStore.ts

### 5. 接続管理UI（実装2担当）
- [ ] app/index.tsx - 接続一覧画面
- [ ] app/connection/add.tsx - 接続追加
- [ ] src/components/connection/ConnectionList.tsx
- [ ] src/components/connection/ConnectionCard.tsx

### 6. ターミナル表示（実装2担当）
- [ ] app/(main)/terminal/[connectionId].tsx
- [ ] src/components/terminal/TerminalView.tsx
- [ ] src/components/terminal/TerminalInput.tsx
- [ ] src/components/terminal/SpecialKeys.tsx
- [ ] src/services/ansi/parser.ts - ANSIパーサー

### 7. セッションナビゲーション（実装2担当）
- [ ] src/components/connection/SessionTree.tsx
- [ ] src/components/navigation/SessionTabs.tsx
- [ ] src/components/navigation/WindowTabs.tsx
- [ ] src/components/navigation/PaneSelector.tsx

### 8. hooks（両担当）
- [ ] src/hooks/useSSH.ts
- [ ] src/hooks/useTmux.ts
- [ ] src/hooks/useTerminal.ts

## 進捗ログ

| 時刻 | 内容 |
|------|------|
| 20:07 | タスク計画作成 |

## 依存関係

```
プロジェクト初期化
    → SSH基盤 + 状態管理（並列可）
    → tmux操作 + 接続管理UI（並列可）
    → ターミナル表示 + セッションナビ（並列可）
    → hooks
    → 統合テスト
```
