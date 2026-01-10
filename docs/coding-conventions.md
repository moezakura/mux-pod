# MuxPod コーディング規約

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| コンポーネント | PascalCase | `TerminalView.tsx` |
| hooks | camelCase + `use` prefix | `useTerminal.ts` |
| stores | camelCase + `Store` suffix | `connectionStore.ts` |
| services | camelCase | `client.ts` |
| 型定義 | PascalCase | `TmuxSession` |
| 定数 | SCREAMING_SNAKE_CASE | `DEFAULT_PORT` |

## 状態管理

### Zustand Store
- グローバル状態は `src/stores/` に配置
- 永続化が必要なもの: `persist` middleware + AsyncStorage
- センシティブデータ: `expo-secure-store`

```typescript
// 例: src/stores/connectionStore.ts
export const useConnectionStore = create<ConnectionStore>()(
  persist(
    (set, get) => ({ ... }),
    {
      name: 'muxpod-connections',
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({ connections: state.connections }),
    }
  )
);
```

## SSH/tmux操作

### SSHクライアント
- `src/services/ssh/client.ts` の `SSHClient` クラスを使用
- 接続管理は `connectionStore` と連携

### tmuxコマンド
- `src/services/tmux/commands.ts` の `TmuxCommands` クラスを使用
- シェルエスケープは必ず `escape()` メソッドを使用（インジェクション防止）

```typescript
// 正しい例
await tmux.sendKeys(sessionName, windowIndex, paneIndex, keys);

// 悪い例（直接コマンド構築は禁止）
await ssh.exec(`tmux send-keys -t ${sessionName} ${keys}`);
```

## ターミナル表示

- ANSIエスケープシーケンス処理: `src/services/ansi/parser.ts`
- 文字幅計算（日本語対応）: `src/services/terminal/charWidth.ts`
- ポーリング間隔: 100ms（`useTerminal` hook内）

## TypeScript

### 型定義
- 共通型は `src/types/` に配置
- コンポーネント固有のPropsは同ファイル内で定義

### 厳格モード
- `strict: true` を維持
- `any` の使用は原則禁止（やむを得ない場合は `// eslint-disable-next-line` でコメント）

## コンポーネント設計

### ファイル構成
```typescript
// 1. imports
import { ... } from 'react';
import { ... } from '@/components/ui';

// 2. types
interface Props { ... }

// 3. component
export function MyComponent({ ... }: Props) {
  // hooks
  // handlers
  // render
}
```

### Hooks
- カスタムhooksは `src/hooks/` に配置
- 1つのhookは1つの責務に集中
