# Herdr 全 mutation 解禁 設計メモ

inventory: HERDR-MUTATION

## 目的

Herdr backend の **read-only 制約を撤廃**し、tmux と同等の全操作
（send-text / send-keys / focus / split / close / zoom / resize / rename /
paste / copy-mode(履歴) / 画像転送 / workspace・tab CRUD）を可能にする
設計を記録する。表示対象切替（read 側）の設計は
`docs/herdr-terminal-switch.md` を参照。

対応する合意: G6 合意#3 改訂（公開機能契約の変更）・ユーザー決定 Q-01〜Q-07・
Challenger C1-C3 / H4-H7 / Scoper S1/S2/S4。

## 重心宣言（G6 合意#3 の改訂）

**外部データ / IF 契約は不変**:

| 契約 | 扱い |
|---|---|
| Connection 永続 JSON（`multiplexer { backend, executablePath }`） | 不変 |
| CLI 文字列（既存 herdr CLI・tmux CLI） | 不変（新規に使うのは既存 herdr コマンドの呼び出しのみ） |
| tmux 経路（`TmuxContract` / `TmuxFacade` / `PaneNavigator`） | 不変（`TmuxPaneWriter` がラップするが中身は触らない） |
| 永続化・DB（SharedPreferences / Connection JSON / ActiveSession） | 不変 |
| `TerminalScreen.readOnly` パラメータ | 存続（呼び出し側明示の opt-in・H6）。herdr による自動付与は廃止 |

**公開機能契約は変更**: herdr 接続時に **Tmux と同等の全操作を解禁**する
（旧「herdr は read-only のみ」を改訂）。

## アーキテクチャ（write 側抽象）

```
UI（TerminalScreen / Dashboard / Connections）
  → _can(capability) で操作の有効/無効を判定
    → PaneWriter（write 抽象: TmuxPaneWriter / HerdrPaneWriter）
      → TmuxContract / HerdrAdapter（_execMutation）
        → raw SSH transport
```

- **`PaneWriter`**（`lib/services/backend/domain/pane_writer.dart`）:
  backend 非依存の write 抽象。`capabilities` getter・`mapSpecialKey`・
  sendText / sendKey / selectPane / focusPaneDirection / splitPane / closePane /
  renamePane / zoomPane / resizePane / createTab / closeTab / renameTab /
  focusTab / createWorkspace / closeWorkspace / renameWorkspace /
  focusWorkspace / pasteText / imageTransfer を持つ。
  非対応操作は `UnsupportedPaneOperationException`。
  soft 失敗（`no_neighbor` / `changed:false`）は `PaneOperationNoopException`
  （情報通知・S4）。
- **`TmuxPaneWriter`**（`tmux_pane_writer.dart`）: 既存 `TmuxContract` をラップ
  （後方互換・コマンド文字列は不変）。capability は全 true。
- **`HerdrPaneWriter`**（`herdr_pane_writer.dart`）: `HerdrAdapter` の mutation
  メソッドをラップ。`PaneKeyMap` でキー送信経路を変換。capability は
  `absoluteResize: false`・`copyMode: false` 以外は全 true（Q-04 / H7）。
- UI から tmux 直結コード（`tmuxFacade` 直叩き）を排除し、backend 分岐を
  構造的に強制する（R3）。

## PaneCapabilities（capability 判定 `_can`）

`PaneCapabilities`（enum 相当の final class・`pane_writer.dart`）:
`sendText` / `sendKeys` / `focus` / `split` / `close` / `rename` / `zoom` /
`resize` / `paste` / `copyMode` / `imageTransfer` / `workspaceCrud` /
`tabCrud` / `absoluteResize`。

- UI は `_can(required)`（`terminal_screen.dart`）で操作を有効/無効化する。
  `_isReadOnly`（boolean）は操作単位の解禁/遮断を表現できないため廃止
  （H4 等価性テスト: フリップ前の read-only 相当が capability false で
  遮断されることを保証）。
- herdr の設計上の制約:
  - `absoluteResize: false`（herdr は絶対 cols/rows 不可・相対分数のみ・Q-04）
  - `copyMode: false`（herdr に copy-mode は無い・H7。`pane read` 履歴ベースで代替）

## PaneKeyMap（全キー送信経路・Q-07）

`lib/services/herdr/herdr_keymap.dart`。tmux キー名 → herdr 送信経路の O(1)
変換表。**「送信できないキー」は存在しない**（全キーで送信経路が返る）。

| 経路 | 対象 | 実装 |
|---|---|---|
| ① `send-keys` 受理キー | F1-F12 / Enter / Tab / Space / Backspace / BS / Escape / 矢印 / C-c（T0 実測 1-a: 21 種） | `HerdrKeyRoute.sendKeys(keyName)` |
| ② `send-text` + エスケープシーケンス | `send-keys` 拒否キー（Home / End / PgUp / PgDn / Delete / Insert・S-/M-/C- 修飾キー） | `HerdrKeyRoute.sendTextEscape(bytes)`（`\x1b[H` / `\x1b[1;5A` 等） |
| ③ `send-text` + 制御文字 | C-a / C-d / C-x 等の C-* 制御文字（C-c 以外） | `HerdrKeyRoute.sendTextControl(byte)`（0x01〜0x1a） |

根拠: herdr 0.7.5 の `send-keys` は最小語彙のみ（T0 実測）だが、`send-text` は
バイナリ素通し（G4 実測）のためエスケープシーケンス / 制御文字がそのまま
アプリ（vim / less / シェル）に届く。実測レポート:
`tool/herdr-mutation-baseline/mutation-baseline-report.md`。
万一 `invalid_key` が返った場合のみ防御的に SnackBar 通知（R9）。

## mutation 実行基盤

- **`HerdrCommands`**（`herdr_commands.dart`）: mutation コマンド文字列の生成
  （send-text / send-keys / focus / edges / resize / zoom / rename / close /
  split / tab CRUD / workspace CRUD）。
- **`HerdrAdapter._execMutation`**（`herdr_adapter.dart`）: rc + stderr のみ検証。
  **stdout 空でも rc=0 を成功とみなす**（R7: send-text は成功時 stdout 空）。
  応答に layout JSON が含まれる場合は `HerdrSnapshotParser` でパースし
  `HerdrMutationResult` に保持。
- **`HerdrMutationResult`**: `{changed, reason, layout}`。
  `changed:false`（resize の `reason:"unchanged"` / focus の
  `reason:"no_neighbor"`）は**失敗ではなく soft 失敗**（情報通知・S4）。
  stdout が空の成功（send-text / send-keys / close / split / rename）は
  `changed: true`。
- **`HerdrLayout`**（`herdr_models.dart`）: mutation 応答の layout
  （area / panes[rect] / splits[ratio,rect] / zoomed / focusedPaneId）。
  `MultiplexerPane` に `left/top/width/height`（デフォルト 0）で写像。

## mutation 後ツリー同期の単一化（H5 / S4 / T18）

全 mutation（split / close / zoom / resize / rename / create / focus /
workspace・tab CRUD）の成功後は **同一経路**
`_syncAfterHerdrMutation`（`terminal_screen.dart`）:

1. `HerdrSnapshotCache.get(force: true)`（エポック++。adapter 差し替えは既存
   `identical` 検出に委譲・A3改。split/create 等の layout なし応答も force
   再取得で反映）
2. `_resolveHerdrTargetFromSessions`（`HerdrTargetResolver` と等価な決定順・
   現在表示中の pane を `preferredPaneId` で最優先）でターゲット再解決
3. ターゲット変化時のみ `_switchHerdrTarget(paneId, workspaceId, tabId,
   tabLabel)` で表示を単一コミット（snapshot 実値を伝播）
4. `_boostPolling` で即時反映

破壊的操作（close / workspace close）でターゲット消滅 → 再解決で別 pane に移る
（連鎖 close は確認済みの上で遷移）。再解決不能（全 workspace 消滅）は
`_notifyHerdrTargetLost` で終端通知（再接続しない・R1）。server-down は
`_fetchHerdrSessions` の既存ルーティング（ポーリング停止 + 通知 + キャッシュ失効）
に倒れる。

ポーリング（`pane read`）は既存のまま継続。snapshot と表示の整合は
`HerdrSnapshotCache` の TTL 5s + force + エポック照合（A3改）で担保。

## mutation 失敗の分類別通知（S4 / T19）

`_handleHerdrMutationError`（`terminal_screen.dart`）に集約:

| 分類 | 判定 | 通知 | 後続処理 |
|---|---|---|---|
| target-not-found | `isHerdrTargetNotFound`（`pane_not_found` 等） | SnackBar「対象が消えました。再同期しました」 | `get(force:true)` → 再解決（`_syncAfterHerdrMutation`） |
| 非対応キー（防御的） | `isHerdrInvalidKey`（`invalid_key`） | SnackBar「このキーは herdr で送信できませんでした」 | なし（Q-07 の全キー送信経路のフォールバック・R9） |
| 方向なし / no-op | `PaneOperationNoopException`（`no_neighbor` / `unchanged`） | 情報 SnackBar（文言出し分け） | なし |
| server-down | `isServerDownException` | 既存（ポーリング停止 + 通知 + キャッシュ失効） | `_handleHerdrServerDown` |
| その他通信エラー | — | 既存エラー SnackBar | `SshConnectionError` は `_attemptReconnect`・それ以外は通知 |

## UI 解禁の要点

- **C-c 解禁 + 破壊的 close の一本化（Q-03）**: C-c は `send-keys <id> C-c` で
  送信（初回確認ダイアログ「Ctrl-C は pane のシェルを終了させる場合があります。
  破壊的な close は Pane メニューの Close を使います」+ 以後は警告バッジ維持・
  SharedPreferences `herdr_ctrl_c_confirmation_seen`）。破壊的 close は必ず
  `pane close` 経由（R1/R2）。最後の pane / tab は既存 `_confirmAndKillPane` で
  連鎖終了確認。
- **resize（Q-04）**: `HerdrResizePaneDialog`（方向 ←→↑↓ + ステップ
  0.05/0.1/0.2 等）。現在サイズは layout の rect から表示。
  `herdr pane resize --direction <dir> --amount <step>` を発行。
- **paste / 画像転送 / copy-mode（Q-06 / H7）**:
  - paste: `send-text` 複数行（`pasteText`）
  - 画像転送: SFTP アップロード（`image_transfer_provider.dart`・backend 非依存）
    + `send-text` でパス送信（`imageTransfer`）
  - copy-mode: herdr には無いため `pane read` 履歴表示ベースで代替
- **dashboard / connections（Q-05）**: `readOnly: isHerdr` 撤廃、READ ONLY バッジ・
  New/Kill 非表示の撤廃。herdr workspace の New / Kill
  （`workspace create` / `workspace close`）を有効化。

## stale tmuxProvider 対策（R3）

- herdr セッション確立（`_setupHerdrSession`）時に
  `ref.read(tmuxProvider.notifier).clear()`（`TmuxState()` リセット）し、
  接続残骸（`currentTarget` 等）を破棄する。
- `_TargetSource`（`_HerdrTargetSource` 固定 pane ID）・`PaneWriter`
  （backend 分岐）と併せて、mutation は必ず herdr の pane_id を使用する
  実装規約とする。

## 監視（A8）

既存の最小監視（debugPrint + リングバッファ・SDK 送信なし）を踏襲。
mutation の結果（成功 / 分類）もイベントへ追記する。**内容（送信テキスト・
画像パス）はログに含めない**（プライバシー維持）。

## テスト

- 単体: `herdr_commands_test.dart`（コマンド文字列）/ `herdr_adapter_test.dart`
  （`_execMutation`・`invalid_key` / `no_neighbor` 分類・layout パース）/
  `herdr_keymap_test.dart`（全キー送信経路）/ `pane_writer_test.dart` /
  `tmux_pane_writer_test.dart` / `herdr_pane_writer_test.dart`（capability・
  委譲・`PaneOperationNoopException`）/ `herdr_errors_test.dart`
- ウィジェット: `terminal_screen_can_test.dart`（`_can` 等価性・H4）/
  `terminal_screen_herdr_mutation_ui_test.dart`（UI 解禁）/ 
  `terminal_screen_herdr_mutation_sync_test.dart`（mutation 後同期単一経路）/
  `terminal_screen_herdr_cc_close_test.dart`（C-c 初回確認・連鎖 close 確認）/
  `connections_screen_herdr_test.dart` / dashboard 系テスト
- 計測: `tool/herdr-mutation-baseline/mutation-baseline-report.md`（T0 実測）

## Open Questions / 将来 milestone

| # | 質問 | 現時点の見解 |
|---|---|---|
| OQ1 | セレクタで任意 pane を直接アクティブ化（`pane focus --pane <ID>` 単体が無い） | 方向 focus + edges 反復を先行、layout 幾何の最短ステップ計算を必要時のみ追加 |
| OQ6 | 将来の socket API 直結移行（mutation 即時応答・event subscription） | CLI 先行を維持。移行時は `PaneWriter` interface が受け皿 |
