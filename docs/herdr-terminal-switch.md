# Herdr ターミナル画面 表示対象切替 設計メモ

inventory: HERDR-TERM-SWITCH

## 目的

Herdr backend 接続時に、ターミナル画面の表示対象（Workspace / Tab / Pane）を read-only で切り替える。

外部契約（接続設定 JSON・CLI コマンド・tmux 経路・永続化・公開機能）は変更しない。

## 背景

- Herdr は read-only 公開のみ（G6 合意#2/#3/#6）。mutation コマンド（focus / create / kill / resize）は発行しない。
- 既存 tmux はセッション/ウィンドウ/ペインの切替を mutation 込みで実装しているが、Herdr は ID 指定の表示対象切替のみ。
- 条件分岐が複雑になるため、抽象レイヤーを導入して「分岐の意味を明確化」する（A9）。

## アーキテクチャ

```
UI（3段セレクタ / パンくず / バナー）
  → 適用層（_switchHerdrTarget + _HerdrDisplayData + _TargetSource）
    → 決定層（HerdrTargetResolver + HerdrSnapshotCache + 例外分類）
      → HerdrAdapter / HerdrPaneContentReader（既存 read-only 再利用）
        → raw SSH transport
```

依存方向は一方向。tmux Provider / tmux CLI / 永続化への依存は追加しない（A7）。

## 主要コンポーネント

### _TargetSource（画面 private 抽象）
- `String? get currentPaneId` のみ。switchTarget / fetchTree は抽象に含めない（A9）。
- `_TmuxTargetSource`: 毎呼出し `tmuxProvider.currentTarget` へ遅延委譲（null 伝播維持）。
- `_HerdrTargetSource`: 固定 pane ID を返す。切替時は `_switchHerdrTarget` が差し替える。
- L952/L1084 の `??` 分裂（`_pollTargetPaneId ?? tmuxProvider.currentTarget`）を一本化。

### HerdrSnapshotCache（lib/services/herdr/herdr_snapshot_cache.dart・純Dart）
- `HerdrAdapter Function() _adapterProvider`・`_snapshot`・`_snapshotAdapter`・`_epoch`。
- `get({bool force = false})` が唯一の read chokepoint。TTL 5s + single-flight + forceFresh。
- `identical(_adapterProvider(), _snapshotAdapter)` で adapter 差し替え（再接続）を検出し自動再取得＋エポック++。
- エポック内在化により、画面側の世代カウンタヘルパーは作らない（A3改）。

### HerdrTargetResolver（lib/services/herdr/herdr_target_resolver.dart・純関数）
- `HerdrSnapshot` + 要求（workspaceId/tabId/paneId）→ target paneId。
- 既存 `_resolveHerdrPaneId` の優先順を移設。throw なし。

### 例外分類（lib/services/herdr/herdr_errors.dart）
- `isServerDownException`: 3条件（①`HerdrServerNotRunningException` ②errorCode/message判定 ③SSH接続断の確定的判定）。
- `isHerdrTargetNotFound`: `HerdrTargetNotFoundException` または errorCode が `pane/tab/workspace_not_found`。
- `HerdrCommandException.errorCode` を stdout+stderr 両対応で抽出。

## エスカレーション規則（A2）

`_pollPaneContent` の catch は4-way分岐:
1. readPane 成功 → エポック照合後、表示に適用。
2. target-not-found → `HerdrSnapshotCache.get(force: true)` 再解決 → 復旧で表示継続 / 終端で通知（再接続しない）。
3. server-down → ポーリング停止 + SnackBar 通知 + TTL キャッシュ失効。
4. その他 → 既存 `_attemptReconnect`。

## エポック照合（A3改）

readPane 完了・`_applyUpdate`・`_loadHistoryForScroll` の async 完了時に、
cache epoch と `_TargetSource.currentPaneId` の同一性を照合し、不一致なら破棄。
バンプは cache 内在のみ（adapter 差し替え / force）。

## read-only 保証

- mutation ガード6箇所と L569 早期 return は意図的に維持（A9）。
- 3段セレクタは mutation ボタンなし。
- pane indicator は `_isReadOnly` で非表示（M2 修正）。

## 監視（A8）

リングバッファ（直近64イベント）+ debugPrint（`[HerdrSwitch]` プレフィックス）。SDK 送信なし。
snapshot / pane 内容をログに含めない。

## テスト

- 単体: `herdr_errors_test.dart` / `herdr_snapshot_cache_test.dart` / `herdr_target_resolver_test.dart`
- ウィジェット: `terminal_screen_herdr_test.dart` / `terminal_screen_herdr_epoch_test.dart`
- 計測: `tool/herdr-baseline/baseline-report.md`

## 既知のフォローアップ（M1 修正後の留意）

- `isServerDownException` 条件3はメッセージベースの確定的接続断判定（`timed out` 等の一過性エラーは除外）。
  `Failed to execute command: SocketException...` のようにラップされた接続断は `_attemptReconnect` 経路で自然復旧する。
