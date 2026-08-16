# SGR 素通し実証レポート（Phase 0: `tool/tmux-sgr-baseline/`）

- 計測日時: 2026-08-10T15:07:05Z（UTC）
- 対象コミット: `2449c8e`（`feat/scroll-emulation`）
- 実行環境（Open Questions #5）:
  - tmux: **3.7b**
  - herdr: **0.7.5**（サーバ到達あり）
  - OS: Linux jocho 6.18.35-1-lts x86_64 GNU/Linux
  - Flutter 3.38.6 stable / Dart 3.10.7
  - 詳細は `results/20260810T150705Z/metadata.txt` に記録
- 計測方法: `tool/tmux-sgr-baseline/capture_baseline.sh`（B1〜B4）。
  **B5（ジェスチャー競合）は widget テスト / 実機で確認（スクリプト対象外）**。

## 実測結果

| # | 内容 | 結果 | 詳細 |
|---|------|------|------|
| B1 | tmux `send-keys -l` による SGR（`ESC[<64;1;1M`）素通し | **PASS** | `results/20260810T150705Z/b1.log` |
| B2 | herdr `send-text` による SGR / プレーンテキスト素通し（(b) 文字キー送信の sendText 素通し確認を兼ねる） | **PASS** | `results/20260810T150705Z/b2.log` |
| B3 | copy-mode 中の SGR 送信挙動（R1: 先頭 ESC が cancel になるか・残りがゴミになるか） | **OBSERVED** | `results/20260810T150705Z/b3.log` |
| B4 | 連結送信（8 ティック分の SGR を 1 コマンドで送信） | **PASS** | `results/20260810T150705Z/b4.log` |

### B1（tmux `send-keys -l` SGR 素通し）— PASS

受信側 `stty raw -echo; cat`（pipe-pane でバイト列を記録）に `ESC[<64;1;1M`
を `send-keys -l` で送信し、受信バイト列に
`1b 5b 3c 36 34 3b 31 3b 31 4d`（=`ESC[<64;1;1M`）が**完全一致で含まれる**ことを
確認した。tmux は `-l`（literal）指定で SGR をキー名解釈せず素通しする。

### B2（herdr `send-text` SGR / プレーンテキスト素通し）— PASS

専用の使い捨て workspace（`sgr-baseline`）を作成し、その pane で raw 受信機
（`stty raw -echo; od -An -tx1`）を `send-text` で起動。SGR とプレーンテキスト
（`hello-sgr-baseline`）を `send-text` で送信し、`pane read` で od の hex 出力
（`1b 5b 3c 36 34 ...`）を確認した（exit 0・stdout 空・R7）。
**(b) 文字キー送信の sendText 素通しも同時に確認**（プレーンテキストが pane に
届いてエコー/hex 出力される・L0-a #6）。実在のユーザー pane には送信していない。

### B3（copy-mode 中の SGR 送信挙動・R1 の実証）— OBSERVED

copy-mode 中（`pane_in_mode=1`）に `send-keys -l` で SGR を送信した結果:
- 先頭 ESC が copy-mode を **cancel**（`pane_in_mode: 1 → 0`）
- `send-keys` 自体が **exit 1（`not in a mode`）で中断**され、残り
  `[<64;1;1M` は受信側に**届かなかった**（ゴミ注入なし）

この環境（tmux 3.7b）では R1 の「ゴミ注入」は発生しなかったが、**ESC が
copy-mode を解除してしまう副作用は確認**された。`_isCopyModeDetected` による
送信ドロップ + select 自動遷移（D2）は「copy-mode 解除という意図しない動作」の
防御としても妥当（ゴミ注入は他バージョンで起こり得るため防護は維持する）。

### B4（連結送信・8 ティック / 1 コマンド）— PASS

8 連結の SGR（`ESC[<64;1;1M` × 8）を 1 コマンドで `send-keys -l` 送信し、
受信バイト列に 8 連結分のバイト列が**完全一致で含まれる**ことを確認した。
→ 合流方式（D6・100ms / 最大 8 ティック）の妥当性を裏付ける。

## `wheelSend` フリップ判定（D11 ゲート）

| backend | B 実測 | wheelSend | 根拠 |
|---------|--------|-----------|------|
| tmux | B1: **PASS** | **true（フリップ済み）** | `send-keys -l` が SGR を完全一致で素通し |
| herdr | B2: **PASS** | **true（フリップ済み）** | `send-text` が SGR / プレーンテキストを素通し |

> フリップ対象は `lib/services/backend/domain/tmux_pane_writer.dart` /
> `lib/services/backend/domain/herdr_pane_writer.dart` の
> `const PaneCapabilities(...)` の `wheelSend:` 値（capability 定数の 1 行変更・
> ロールバックは false へ 1 行戻し）。
> ⚠ 実測は **tmux 3.7b / herdr 0.7.5** の環境に依存。他バージョンで SGR 素通しが
> 崩れる場合は本レポートの手順（`capture_baseline.sh`）で再実測し、該当 backend の
> `wheelSend` を false へ戻す（ロールバック手順・Implementation Plan §L5 Operations）。

## 備考

- B5（1 本指ドラッグと 2 本指ピンチの競合・論点3）は gesture arena の
  widget テスト（`test/screens/terminal/`）と実機で確認する（Phase 3 #1/#5）。
- 実測の再現手順は `README.md` と `results/20260810T150705Z/` のログに記録。
- 受信方式: tmux は `stty raw -echo; cat` + `pipe-pane` によるバイト列記録
  （`od` は tmux の `new-session` コマンド実行時に入力が届かない挙動のため不採用）。
  herdr は専用 workspace の pane で `od` を `send-text` 起動し `pane read` で確認。
