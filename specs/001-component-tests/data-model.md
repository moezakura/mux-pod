# Data Model: Component Tests

**Date**: 2026-01-10
**Branch**: `001-component-tests`

## Overview

コンポーネントテストで使用するテストフィクスチャ（モックデータ）の構造を定義する。

---

## Test Fixtures

### ConnectionCard Fixtures

#### mockConnection
```typescript
interface Connection {
  id: string;                    // UUID
  name: string;                  // 表示名
  host: string;                  // ホスト名
  port: number;                  // ポート番号
  username: string;              // ユーザー名
  authMethod: 'password' | 'key'; // 認証方式
  timeout: number;               // タイムアウト秒
  keepAliveInterval: number;     // Keepalive間隔
  createdAt: number;             // 作成日時
  updatedAt: number;             // 更新日時
}
```

#### mockConnectionState
```typescript
interface ConnectionState {
  connectionId: string;
  status: 'disconnected' | 'connecting' | 'connected' | 'error';
  error?: string;
  latency?: number;
  connectedAt?: number;
}
```

---

### TerminalView Fixtures

#### mockAnsiLine
```typescript
interface AnsiLine {
  spans: AnsiSpan[];
}

interface AnsiSpan {
  text: string;
  fg?: number;          // 前景色 (0-255)
  bg?: number;          // 背景色 (0-255)
  bold?: boolean;
  dim?: boolean;
  italic?: boolean;
  underline?: boolean;
  strikethrough?: boolean;
  inverse?: boolean;
  hidden?: boolean;
}
```

#### mockTerminalTheme
```typescript
interface TerminalTheme {
  background: string;
  foreground: string;
  cursor: string;
  selection: string;
  palette: readonly string[]; // 16色
}
```

---

### SessionTabs Fixtures

#### mockTmuxSession
```typescript
interface TmuxSession {
  name: string;
  created: number;
  attached: boolean;
  windowCount: number;
  windows: TmuxWindow[];
}

interface TmuxWindow {
  index: number;
  name: string;
  active: boolean;
  paneCount: number;
  panes: TmuxPane[];
}
```

---

### SpecialKeys Fixtures

#### mockCallbacks
```typescript
interface SpecialKeysCallbacks {
  onSendKeys: jest.Mock;
  onSendSpecialKey: jest.Mock;
  onSendCtrl: jest.Mock;
}
```

---

## Fixture Factories

テスト用のファクトリ関数パターン（必要に応じて実装）:

```typescript
// 基本的なConnectionを生成
function createMockConnection(overrides?: Partial<Connection>): Connection

// 接続済み状態を生成
function createConnectedState(connectionId: string): ConnectionState

// エラー状態を生成
function createErrorState(connectionId: string, error: string): ConnectionState

// ANSIスタイル付きテキストを生成
function createStyledSpan(text: string, style: Partial<AnsiSpan>): AnsiSpan
```

---

## State Transitions

### ConnectionCard State Flow
```
Initial → onPress → Expanded (if sessions exist)
Expanded → onPress → Collapsed
Expanded → onSelectSession → Callback invoked
```

### SpecialKeys Mode Flow
```
Normal → CTRL press → CTRL Mode
CTRL Mode → Literal key press → Normal (callback with Ctrl+key)
CTRL Mode → CTRL press → Normal
Normal → ALT press → ALT Mode
ALT Mode → ALT press → Normal
```

---

## Notes

- 実際の型定義は`src/types/`に存在、テストではこれらをインポートして使用
- モックデータは各テストファイル内でインラインで定義（初期段階）
- 重複が発生した場合は`__tests__/fixtures/`に抽出を検討
