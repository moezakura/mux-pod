# Research: SSH再接続機能

**Feature**: 002-ssh-reconnect
**Date**: 2026-01-10

## 1. SSH切断検出メカニズム

### Decision
react-native-ssh-sftpの`Disconnect`イベントと既存のKeepAlive機能を組み合わせて切断を検出する。

### Rationale
- 既存の`SSHClient`クラスが`onClose`イベントハンドラをサポート済み（`client.ts:39`）
- `startShell`メソッド内で`Disconnect`イベントをリッスン済み（`client.ts:186-187`）
- 追加のポーリングは不要で、イベント駆動で即座に検出可能

### Alternatives Considered
1. **定期的なpingコマンド実行**: オーバーヘッドが大きく、バッテリー消費が増加
2. **TCP接続状態の監視**: React Native環境では低レベルAPIへのアクセスが制限される
3. **KeepAliveタイムアウトのみ**: 既に`connection.keepAliveInterval`で設定可能だが、即時検出には不十分

## 2. 再接続ダイアログ実装パターン

### Decision
React NativeのModalコンポーネントを使用し、`connectionStore`の状態変化をトリガーとして表示する。

### Rationale
- 既存の`ConnectionErrorScreen.tsx`コンポーネントがエラー表示のパターンを確立
- Zustandの`connectionStates`でリアクティブに状態管理可能
- モーダルは画面遷移なしでオーバーレイ表示でき、ユーザーの作業コンテキストを維持

### Alternatives Considered
1. **Alert.alert()**: カスタマイズ性が低く、進捗状態の表示ができない
2. **フルスクリーン遷移**: 接続復帰後に元の画面に戻る処理が複雑になる
3. **トースト通知のみ**: ユーザーアクションが必要な場合に不適切

## 3. 自動再接続の実装戦略

### Decision
`ReconnectService`クラスを新設し、再試行ロジックを`connectionStore`から分離する。

### Rationale
- Single Responsibility Principle: `connectionStore`は接続状態管理に専念
- テスト容易性: 再接続ロジックを独立してユニットテスト可能
- 設定の柔軟性: 接続ごとに異なる再接続ポリシーを適用可能

### Implementation Details
```
再接続フロー:
1. 切断検出 → connectionStore.setConnectionState(id, { status: 'disconnected' })
2. ReconnectService.handleDisconnection(connectionId)
3. 自動再接続有効? → 即座に再接続試行開始
4. 自動再接続無効? → ReconnectDialogを表示
5. 再接続試行 → status: 'reconnecting' + attemptCount表示
6. 成功 → status: 'connected', ダイアログ閉じる
7. 失敗(max回数未満) → 間隔を空けて再試行
8. 失敗(max回数到達) → 手動確認ダイアログに切り替え
```

### Retry Policy
- 最大試行回数: 3回（デフォルト、接続設定で変更可能）
- 試行間隔: 5秒（固定、指数バックオフは初期実装では行わない - spec.md Assumptions参照）
- キャンセル可能: 任意のタイミングでユーザーが中断可能

## 4. 接続状態インジケーター設計

### Decision
`ConnectionStatusIndicator`コンポーネントを作成し、`TerminalHeader`に統合する。

### Rationale
- 既存の`TerminalHeader.tsx`がヘッダー表示を担当
- `ConnectionCard`の`ServerIcon`コンポーネントが状態表示パターンを確立（`ConnectionCard.tsx:38-74`）
- 再利用可能なインジケーターコンポーネントとして設計

### Visual States
| 状態 | 色 | アイコン | アニメーション |
|------|-----|---------|---------------|
| connected | 緑 (#22c55e) | ● (ドット) | なし |
| connecting | 黄 (#eab308) | ○ (リング) | パルス |
| reconnecting | 黄 (#eab308) | ↻ (矢印) | 回転 |
| disconnected | 赤 (#ef4444) | ● (ドット) | なし |
| error | 赤 (#ef4444) | ⚠ (警告) | なし |

## 5. 認証情報の再取得

### Decision
再接続時に`expo-secure-store`から認証情報を取得し、存在しない場合はパスワード入力ダイアログを表示する。

### Rationale
- 既存の`auth.ts`が認証情報の取得ロジックを提供
- セキュリティ原則（Constitution IV）に準拠: 認証情報は暗号化保存
- パスワードが保存されていないケース（ユーザーが「保存しない」を選択）に対応必要

### Flow
1. 再接続開始時に`getStoredCredentials(connectionId)`を呼び出し
2. 認証情報が存在 → そのまま接続試行
3. 認証情報が不存在 → `PasswordInputDialog`を表示
4. ユーザー入力後 → 接続試行（オプションで保存）

## 6. バックグラウンド処理

### Decision
フォアグラウンド時の再接続を優先し、バックグラウンド移行時は再接続処理を継続するが、成功/失敗時にローカル通知で結果を通知する。

### Rationale
- モバイルOSのバックグラウンド制限（iOS: 30秒、Android: 10分）
- 仕様のAssumptionsに「フォアグラウンド時の再接続を優先」と明記
- 完全なバックグラウンド対応は将来的なスコープ

### Implementation
- `AppState`イベントリスナーでフォアグラウンド/バックグラウンド状態を監視
- バックグラウンド移行時: 再接続タイマーは継続、結果をキャッシュ
- フォアグラウンド復帰時: キャッシュされた結果をUIに反映

## 7. テスト戦略

### Decision
切断検出と再接続ロジックはモックを使用してユニットテストし、E2Eテストは手動で行う。

### Test Cases
1. **切断検出**: `onClose`イベント発火時に状態が`disconnected`に変化
2. **自動再接続**: 有効時に自動で`reconnecting`状態に遷移
3. **手動再接続**: ダイアログ表示と選択肢の動作
4. **最大試行回数**: 3回失敗後に手動確認に切り替え
5. **キャンセル**: 再接続中のキャンセル操作
6. **認証情報なし**: パスワード入力ダイアログ表示

### Mocking Strategy
- `SSHClient`: `jest.mock('react-native-ssh-sftp')`
- `expo-secure-store`: `jest.mock('expo-secure-store')`
- タイマー: `jest.useFakeTimers()`
