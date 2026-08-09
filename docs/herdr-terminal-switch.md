# Herdr ターミナル画面 表示対象切替 設計メモ

inventory: HERDR-TERM-SWITCH

## 目的

Herdr backend 接続時に、ターミナル画面の表示対象（Workspace / Tab / Pane）を切り替える。

本 memo は**表示対象切替（read 側の表示決定）**の設計を記録する。herdr は
**全 mutation 解禁後（G6 合意#3 改訂）**の状態を前提とし、mutation 操作
（send-text / send-keys / focus / split / close / zoom / resize / paste /
copy-mode(履歴) / 画像転送 / workspace・tab CRUD）の設計は
`docs/herdr-mutation.md` に分離した。両文書を併せて現行の herdr 実装を構成する。

外部契約（接続設定 JSON・CLI コマンド・tmux 経路・永続化・公開機能）は変更しない
（重心宣言。公開機能契約のみ G6 合意#3 改訂で変更）。

## 背景

- **方針転換（G6 合意#3 改訂・T21）**: 旧来は「Herdr は read-only 公開のみ
  （G6 合意#2/#3/#6）。mutation コマンド（focus / create / kill / resize）は
  発行しない」だった。本 milestone で**全 mutation 解禁に改訂**した
  （Q-01: リリースは 1 回 / Q-02: 全操作解禁）。表示対象切替は mutation 込みの
  操作体系の一部として実装される。
- 既存 tmux と操作感を統一するため、write 側抽象 `PaneWriter`
  （`TmuxPaneWriter` / `HerdrPaneWriter` の 2 実装）と capability 判定
  `_can(capability)` を導入した（A9 / R3）。
- 条件分岐が複雑になるため、抽象レイヤーを導入して「分岐の意味を明確化」する（A9）。

## アーキテクチャ

```
UI（3段セレクタ / パンくず / バナー / 操作ボタン）
  → 適用層（_switchHerdrTarget + _HerdrDisplayData + _TargetSource）
    → 決定層（HerdrTargetResolver + HerdrSnapshotCache + 例外分類）
      → read:  HerdrAdapter / HerdrPaneContentReader（snapshot / pane read）
        write: PaneWriter（TmuxPaneWriter / HerdrPaneWriter）
        → raw SSH transport
```

依存方向は一方向。tmux Provider / tmux CLI / 永続化への依存は追加しない（A7）。
mutation は必ず `PaneWriter` 経由で herdr の pane_id（`wN:pN` / `wN:tN:pN`）を
使用する（R3: stale tmuxProvider への誤送信の構造的対策）。

## 主要コンポーネント（read 側）

### _TargetSource（画面 private 抽象）
- `String? get currentPaneId` のみ。switchTarget / fetchTree は抽象に含めない（A9）。
- `_TmuxTargetSource`: 毎呼出し `tmuxProvider.currentTarget` へ遅延委譲（null 伝播維持）。
- `_HerdrTargetSource`: 固定 pane ID を返す。切替時は `_switchHerdrTarget` が差し替える。
- 旧 `_pollTargetPaneId ?? tmuxProvider.currentTarget` の `??` 分裂を一本化。

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
- `isHerdrInvalidKey`: errorCode が `invalid_key`（mutation 用。Q-07 の全キー送信経路により通常は発生しない・R9）。
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

## mutation 対応（旧「read-only 保証」の改訂）

旧「read-only 保証」章（mutation ガード6箇所・L569 早期 return を意図的に維持・
A9 合意）は **G6 合意#3 改訂により廃止**した。全 mutation 解禁後の状態は以下のとおり:

- **capability 判定への置換**: `_isReadOnly`（`widget.readOnly || _backendKind ==
  herdr`）を廃止し、`_can(PaneCapabilities)` へ置換（Q-02/H4）。herdr は
  `HerdrPaneWriter.capabilities` で操作単位の能力を持ち、tmux と同等の操作が可能。
  `absoluteResize` のみ設計上 false（herdr は相対分数のみ・Q-04）。UI ガードは
  すべて `!_can(...)` に集約される。
- **3 段セレクタ**: mutation ボタン（Split / Close / Rename / tab・workspace CRUD）
  が `_can` で有効化される。pane indicator の非表示（旧 M2 修正）は撤廃。
- **全キー送信経路（Q-07）**: `PaneKeyMap` により「送信できないキー」は存在しない。
  `send-keys` 受理キーはそのまま、拒否キーは `send-text` + エスケープシーケンス、
  制御文字は `send-text` + 制御文字で送信する（`send-text` はバイナリ素通し・G4 実測）。
- **破壊的 close の一本化（Q-03）**: close は必ず `pane close` 経由。C-c は tmux と
  同等に解禁するが、初回確認ダイアログ + 警告バッジでリスクを明示する（R1）。
- **resize の置換（Q-04）**: 絶対値入力 UI を「方向 + ステップ」に置換（herdr は
  絶対 cols/rows 不可のため）。

mutation 実行基盤（`_execMutation` / `HerdrMutationResult`）・mutation 後ツリー同期
の単一経路（force 再取得 → 再解決 → `_switchHerdrTarget`）・失敗の分類別通知の
詳細は `docs/herdr-mutation.md` を参照。

## 監視（A8）

リングバッファ（直近64イベント）+ debugPrint（`[HerdrSwitch]` プレフィックス）。SDK 送信なし。
snapshot / pane 内容をログに含めない。mutation の結果（成功 / 分類）もイベントへ
追記する（内容・送信テキストは含めない・プライバシー維持）。

## テスト

- 単体: `herdr_errors_test.dart` / `herdr_snapshot_cache_test.dart` /
  `herdr_target_resolver_test.dart` / `herdr_keymap_test.dart` /
  `herdr_adapter_test.dart` / `pane_writer_test.dart` / `tmux_pane_writer_test.dart` /
  `herdr_pane_writer_test.dart`
- ウィジェット: `terminal_screen_herdr_test.dart` / `terminal_screen_herdr_epoch_test.dart` /
  `terminal_screen_herdr_mutation_ui_test.dart` / `terminal_screen_herdr_mutation_sync_test.dart` /
  `terminal_screen_herdr_cc_close_test.dart` / `terminal_screen_can_test.dart` /
  `connections_screen_herdr_test.dart` / dashboard 系テスト
- 計測: `tool/herdr-baseline/baseline-report.md` / `tool/herdr-mutation-baseline/mutation-baseline-report.md`

## 既知のフォローアップ（M1 修正後の留意）

- `isServerDownException` 条件3はメッセージベースの確定的接続断判定（`timed out` 等の一過性エラーは除外）。
  `Failed to execute command: SocketException...` のようにラップされた接続断は `_attemptReconnect` 経路で自然復旧する。
- mutation の将来課題（socket API 直結・OQ6 等）は `docs/herdr-mutation.md` の Open Questions を参照。
