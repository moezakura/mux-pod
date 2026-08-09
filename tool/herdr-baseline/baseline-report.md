# T0 計測スパイク: 現行 herdr パス baseline レポート

- 計測日時: 2026-08-08（実装タスク T0〜T4b 着手前）
- 対象コミット: `d20d751`（`feat/support-hardr`）
- 計測方法: 現行コードの静的パス解析（行番号付き）＋ 一時計測テスト
  （`test/tmp_baseline_measure_test.dart`、計測後削除済み）による実測。
  実測は `FakeSshClient`（`test/helpers/fake_ssh_client.dart`）の
  `execCommands` ログと `FakeSshNotifier.reconnectCalls` を数えたもの。
- 検証環境: `make analyze` / `make test` が baseline 時点で全 Green
  （analyze: No issues found / test: 774 tests passed）。

## ① 接続時の snapshot 取得回数と成否

| パス | 実測 | 静的解析 |
|---|---|---|
| sessionName 一致解決 | **1回**（成功） | `_setupHerdrSession` → `_resolveHerdrPaneId`（terminal_screen.dart L796-836）が `adapter.snapshot()` を 1 回のみ実行 |
| initialPaneId/lastPaneId 直接指定 | **0回** | `_setupHerdrSession` L775-777 で `directId != null` なら snapshot を読まず直接 pane ID を採用 |

実測 JSON:
```json
{
  "t0_1_snapshot_count_at_connect": 1,
  "t0_1_snapshot_success": true,
  "t0_1_pane_read_count_in_window": 6,
  "t0_1_list_panes_count_at_connect": 0,
  "t0_1_tmux_setup_count_at_connect": 0,
  "t0_1b_snapshot_count_with_direct_pane_id": 0
}
```

- 600ms 窓（`settle:false` 相当のポンプ）で pane read が 6 回実行
  = ポーリング間隔 100ms の既定値と一致。
- 接続時に tmux セットアップ（`tmux -V` / `set-option`）は 0 回
  （herdr 早期 return L569-576 でスキップ）。

## ② readPane 失敗時の catch 経路（全例外→`_attemptReconnect` の実測）

- `_pollPaneContent`（L931-1065）の `try/catch` は**例外種別を区別せず**
  全例外を捕捉し、`!currentState.isReconnecting` なら `_attemptReconnect()`
  （L1054-1061）を呼ぶ。型別分岐は存在しない。
- 実測: `SshConnectionError('boom')` を readPane に注入 → 次の失敗ポーリングで
  `reconnectCalls` が 0 → 1 に増加（＝`_attemptReconnect` 発火を確認）。

```json
{
  "t0_2_reconnect_calls_after_10_polls": 2,
  "t0_2_pane_read_errors_observed": 8,
  "t0_2_ssh_state_is_reconnecting": false,
  "t0_2_ssh_state_connection": "disconnected"
}
```

- 注: 観測される reconnect 回数が readPane エラー回数より少なくなるのは、
  (a) 適応型ポーリングのバックオフ（`AdaptivePollingInterval`:
  無変化 3 回で 50ms から線形に増加し 15 回で 2000ms 上限）により
  エラーポーリング自体が間引きされる、
  (b) fake の `reconnect()` が state を `disconnected` にするため、
  次ポーリングは SSH 断側の早return分岐へ入る、ため。
  実環境の `SshNotifier.reconnect` は `isReconnecting=true` + 指数バックオフ
  （1s×1.5^n）を設定するため、readPane が失敗し続ける間は再接続が
  **バックオフ付きで繰り返される再接続ループ**になる（R1 の根拠）。

## ③ herdr 接続中に `_startTreeRefresh` / `listAllPanes` が発火する事実

- 初期接続パスでは発火しない（`_connectAndSetup` L569-576 の herdr 早期 return
  が `_startTreeRefresh()`（L727）より前にあるため）→ 実測 0 回。
- しかし **再接続成功時 `_onReconnectSuccess`（L493-514）が無条件で
  `_startTreeRefresh()`（L506）を呼ぶ**。また **`_resumePolling`（L398-406）も
  無条件で `_startTreeRefresh()`（L404）を呼ぶ**。両者とも backend 分岐が無い。
- 実測: ライフサイクル `paused → resumed` を経由すると tree refresh timer
  （10 秒周期）が起動し、`list-panes -a` が 1 回実行された。

```json
{
  "t0_3_list_panes_before_lifecycle": 0,
  "t0_3_list_panes_after_resume_10s": 1,
  "t0_3_tree_refresh_fires_during_herdr": true
}
```

- これは herdr 中に tmux CLI が発火するバグ（計画 L0-b-08 / A7）。
  修正は T9a で実施（本タスク T0〜T4b の範囲外）。

## ④ エラー→再接続までの回数・時間

- 経路: `_pollPaneContent` catch → `_attemptReconnect()`（L1174-1189）
  → `SshNotifier.reconnect()`（ssh_provider.dart L333-381）。
- バックオフ定数（ssh_provider.dart 実測）:
  - `_baseDelayMs = 1000`（初回 1 秒）
  - `_backoffMultiplier = 1.5`（指数バックオフ）
  - `_maxDelayMs = 60000`（上限 60 秒）
  - `_maxReconnectAttempts = 0`（**無制限リトライ**）
  - `_onConnectionStateChanged`（L308-327）でも切断検知→`reconnect()` が走る
- 実測: readPane エラー 1 バーストで `reconnect()` 呼び出し 1 回
  （`isReconnecting` ガード + ポーリング間引きにより、同一窓内の多重再入は抑制）。
- 結果: エラーが続く限りバックオフ付きで無制限に再接続を試み続ける。
  サーバ未稼働（server-down）で readPane が失敗し続ける場合も同じ経路を辿る
  ＝再接続ループの温床（A1 で述語導入が必要な理由）。

## ⑤ L952/L1084 のターゲット分裂の発生頻度

- **L952**（`_pollPaneContent`）: ポーリング毎に
  `_pollTargetPaneId ?? ref.read(tmuxProvider.notifier).currentTarget` を評価。
  頻度 = ポーリング間隔（50〜2000ms、既定 100ms）。接続直後の 600ms 窓で
  実測 6 回評価。
- **L1084**（`_loadHistoryForScroll`）: スクロールモード突入時に毎回評価
  （オーバースクロール検出 L1249-1263 からの深い履歴ロード時）。
- herdr パス: `_pollTargetPaneId` が接続時に非 null になるため右辺
  （tmux `currentTarget` 読み）は**発火しない**。ただし式が 2 箇所に重複し、
  将来 herdr の切替（固定 pane ID の差し替え）を導入すると
  「片方だけが新ターゲットを見る」分裂が起こり得る（A9 / T4b の根拠）。
- tmux パス: `_pollTargetPaneId` は常に null のため、毎回 `currentTarget` を読む。

## まとめ（T1〜T4b への示唆）

| # | 実測事実 | 反映先 |
|---|---|---|
| ① | snapshot は接続時 1 回（TTL キャッシュで抑制可能なのは接続以外の多重取得） | T4a `HerdrSnapshotCache`（TTL 5s + single-flight） |
| ② | 全例外→`_attemptReconnect`（種別分岐なし）。server-down でも再接続ループ | T2 `isServerDownException` / T7 種別分岐 |
| ③ | herdr 中に `list-panes -a` がライフサイクル/再接続経由で発火 | T9a（範囲外・申告） |
| ④ | バックオフ 1s×1.5^n 無制限 → readPane 失敗が続くと実質再接続ループ | T2 / T7 |
| ⑤ | L952/L1084 の `??` 分裂（herdr では左辺固定・tmux では右辺固定） | T4b `_TargetSource` 一本化 |

## 添付: 計測テスト生出力（要約）

```
00:03 +1: T0-1 connect snapshot count + tree refresh absence
00:03 +2: T0-1b direct pane id skips snapshot
00:03 +3: T0-2 readPane failure path: all exceptions -> _attemptReconnect
00:03 +4: T0-3 tree refresh fires during herdr after lifecycle resume
00:04 +4: All tests passed!
```

（計測用テストファイルはスパイクのため削除済み。再現手順は上記
「計測方法」と実測 JSON に記録。）
