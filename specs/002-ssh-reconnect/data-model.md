# Data Model: SSH再接続機能

**Feature**: 002-ssh-reconnect
**Date**: 2026-01-10

## Entity Relationships

```
┌─────────────────────┐      ┌──────────────────────┐
│     Connection      │ 1  1 │   ReconnectSettings  │
│ (既存エンティティ)   │──────│   (新規追加フィールド)│
└─────────────────────┘      └──────────────────────┘
          │ 1
          │
          │ *
┌─────────────────────┐
│   ConnectionState   │
│ (既存、拡張)         │
└─────────────────────┘
          │ 1
          │
          │ 0..1
┌─────────────────────┐
│  ReconnectAttempt   │
│ (新規、ランタイム)   │
└─────────────────────┘
```

## Entities

### Connection (既存エンティティ - 拡張)

`src/types/connection.ts` に定義済み。再接続設定フィールドを追加。

```typescript
interface Connection {
  // 既存フィールド
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  authMethod: 'password' | 'key';
  keyId?: string;
  timeout: number;
  keepAliveInterval: number;
  icon?: string;
  color?: string;
  tags?: string[];
  lastConnected?: number;
  createdAt: number;
  updatedAt: number;

  // 新規追加: 再接続設定
  autoReconnect: boolean;           // 自動再接続有効フラグ (default: true)
  maxReconnectAttempts: number;     // 最大試行回数 (default: 3)
  reconnectInterval: number;        // 試行間隔(ms) (default: 5000)
}
```

**Validation Rules**:
- `autoReconnect`: boolean, default `true`
- `maxReconnectAttempts`: 1-10の整数, default `3`
- `reconnectInterval`: 1000-30000の整数(ms), default `5000`

**State Transitions**: N/A (設定値は静的)

---

### ConnectionState (既存エンティティ - 拡張)

`src/types/connection.ts` に定義済み。状態値と詳細情報を拡張。

```typescript
interface ConnectionState {
  // 既存フィールド
  connectionId: string;
  status: ConnectionStatus;   // 拡張: 'reconnecting' 追加
  error?: string;
  latency?: number;
  connectedAt?: number;

  // 新規追加
  disconnectedAt?: number;     // 切断時刻 (Unix timestamp ms)
  disconnectReason?: DisconnectReason;  // 切断理由
  reconnectAttempt?: ReconnectAttempt;  // 現在の再接続試行情報
}

type ConnectionStatus =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'reconnecting'  // 新規追加
  | 'error';

type DisconnectReason =
  | 'network_error'      // ネットワーク障害
  | 'server_closed'      // サーバー側で切断
  | 'auth_failed'        // 認証失敗
  | 'timeout'            // タイムアウト
  | 'user_disconnect'    // ユーザー操作による切断
  | 'unknown';           // 不明
```

**Validation Rules**:
- `disconnectedAt`: `status === 'disconnected'` または `status === 'reconnecting'` 時のみ設定
- `disconnectReason`: `disconnectedAt` が設定されている場合のみ有効
- `reconnectAttempt`: `status === 'reconnecting'` 時のみ設定

**State Transitions**:
```
connected → disconnected (切断検出)
disconnected → connecting (手動再接続開始)
disconnected → reconnecting (自動再接続開始)
reconnecting → connected (再接続成功)
reconnecting → disconnected (再接続断念/キャンセル)
reconnecting → error (致命的エラー)
error → connecting (再試行)
```

---

### ReconnectAttempt (新規エンティティ - ランタイム)

再接続試行の状態を追跡。永続化されない。

```typescript
interface ReconnectAttempt {
  /** 試行開始時刻 (Unix timestamp ms) */
  startedAt: number;

  /** 現在の試行回数 (1から開始) */
  attemptNumber: number;

  /** 最大試行回数 (Connection.maxReconnectAttemptsからコピー) */
  maxAttempts: number;

  /** 次回試行予定時刻 (Unix timestamp ms, 待機中のみ) */
  nextAttemptAt?: number;

  /** 各試行の結果履歴 */
  history: AttemptResult[];
}

interface AttemptResult {
  /** 試行番号 */
  attemptNumber: number;

  /** 試行時刻 */
  attemptedAt: number;

  /** 結果 */
  result: 'success' | 'failed' | 'cancelled';

  /** 失敗理由 (result === 'failed' の場合) */
  error?: string;
}
```

**Validation Rules**:
- `attemptNumber`: 1以上、`maxAttempts`以下
- `history.length`: `attemptNumber` と一致（試行後に追加）
- `nextAttemptAt`: 現在時刻より未来

**State Transitions**:
```
null → ReconnectAttempt (再接続開始)
attemptNumber++ (次の試行へ)
ReconnectAttempt → null (成功/断念/キャンセル)
```

## Default Values

```typescript
const DEFAULT_RECONNECT_SETTINGS = {
  autoReconnect: true,
  maxReconnectAttempts: 3,
  reconnectInterval: 5000,  // 5秒
};
```

## Storage

| Entity | Storage | Persistence |
|--------|---------|-------------|
| Connection (再接続設定含む) | AsyncStorage | ✅ 永続化 |
| ConnectionState | Zustand (メモリ) | ❌ ランタイムのみ |
| ReconnectAttempt | Zustand (メモリ) | ❌ ランタイムのみ |

## Migration

既存の`Connection`エンティティへのフィールド追加は、Zustandのpersist middlewareによって自動的にマージされる。新規フィールドが存在しない場合はデフォルト値を使用。

```typescript
// connectionStore.ts での初期化時にデフォルト値を適用
const normalizeConnection = (conn: Partial<Connection>): Connection => ({
  ...DEFAULT_CONNECTION,
  ...DEFAULT_RECONNECT_SETTINGS,
  ...conn,
});
```
