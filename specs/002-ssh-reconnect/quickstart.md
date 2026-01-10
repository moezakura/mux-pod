# Quickstart: SSH再接続機能

**Feature**: 002-ssh-reconnect
**Date**: 2026-01-10

## 概要

SSH接続が切断された際に、ユーザーが迅速に状況を把握し、スムーズに再接続できる機能を実装する。

## 主要コンポーネント

### 1. ReconnectService (`src/services/ssh/reconnect.ts`)

再接続ロジックを管理するサービス。

```typescript
import { createReconnectService } from '@/services/ssh/reconnect';

const reconnectService = createReconnectService();

// 切断検出時に呼び出し
reconnectService.handleDisconnection(connection, state);

// 手動で再接続を開始
await reconnectService.startReconnect(connection, { password: '...' });

// 再接続をキャンセル
reconnectService.cancelReconnect(connectionId);
```

### 2. ReconnectDialog (`src/components/connection/ReconnectDialog.tsx`)

再接続確認ダイアログ。

```tsx
import { ReconnectDialog } from '@/components/connection';

<ReconnectDialog
  visible={showDialog}
  connection={connection}
  connectionState={state}
  onReconnect={(password) => handleReconnect(password)}
  onCancel={() => navigateToConnections()}
  onDismiss={() => setShowDialog(false)}
/>
```

### 3. ConnectionStatusIndicator (`src/components/connection/ConnectionStatusIndicator.tsx`)

接続状態を視覚的に表示するインジケーター。

```tsx
import { ConnectionStatusIndicator } from '@/components/connection';

<ConnectionStatusIndicator
  state={connectionState}
  size="md"
  onPress={() => showStatusDetails()}
  animated
/>
```

## 状態管理

### connectionStore の拡張

```typescript
// 再接続設定の更新
useConnectionStore.getState().updateReconnectSettings(id, {
  autoReconnect: true,
  maxReconnectAttempts: 3,
  reconnectInterval: 5000,
});

// 切断状態に設定
useConnectionStore.getState().setDisconnected(id, 'network_error');

// 再接続中状態に設定
useConnectionStore.getState().setReconnecting(id, 1, 3);
```

## 実装手順

### Step 1: 型定義の拡張

`src/types/connection.ts` に再接続関連の型を追加:

```typescript
// Connection に追加
autoReconnect: boolean;
maxReconnectAttempts: number;
reconnectInterval: number;

// ConnectionState に追加
disconnectedAt?: number;
disconnectReason?: DisconnectReason;
reconnectAttempt?: ReconnectAttempt;

// 新規型
type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting' | 'error';
type DisconnectReason = 'network_error' | 'server_closed' | 'auth_failed' | 'timeout' | 'user_disconnect' | 'unknown';

interface ReconnectAttempt {
  startedAt: number;
  attemptNumber: number;
  maxAttempts: number;
  nextAttemptAt?: number;
  history: AttemptResult[];
}
```

### Step 2: ReconnectService の実装

1. `src/services/ssh/reconnect.ts` を作成
2. `IReconnectService` インターフェースを実装
3. SSHクライアントの`onClose`イベントと連携
4. 再試行ロジックを実装（タイマー管理）

### Step 3: connectionStore の拡張

1. 再接続関連アクションを追加
2. セレクターを追加
3. 永続化設定を更新（再接続設定をAsyncStorageに保存）

### Step 4: UI コンポーネントの実装

1. `ConnectionStatusIndicator.tsx` を作成
2. `ReconnectDialog.tsx` を作成
3. `TerminalHeader.tsx` にインジケーターを統合
4. ターミナル画面でダイアログを表示するロジックを追加

### Step 5: テストの作成

1. ReconnectService のユニットテスト
2. connectionStore の再接続アクションテスト
3. コンポーネントのスナップショットテスト

## ファイル構成

```
src/
├── components/
│   └── connection/
│       ├── ConnectionStatusIndicator.tsx  # 新規
│       ├── ReconnectDialog.tsx            # 新規
│       └── index.ts                        # 更新
├── services/
│   └── ssh/
│       ├── reconnect.ts                   # 新規
│       └── index.ts                        # 更新
├── stores/
│   └── connectionStore.ts                 # 更新
└── types/
    └── connection.ts                      # 更新
```

## テスト実行

```bash
# ユニットテスト
pnpm test src/services/ssh/reconnect.test.ts
pnpm test src/stores/connectionStore.test.ts

# 型チェック
pnpm typecheck

# Lint
pnpm lint
```

## 注意事項

- 認証情報はセキュアストレージから取得（平文保存禁止）
- バックグラウンド処理はフォアグラウンド優先
- 最大試行回数到達後は手動確認に切り替え
