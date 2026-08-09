# T0 計測スパイク: herdr 0.7.5 mutation 系コマンド実機 baseline レポート

- 計測日時: 2026-08-08T15:14Z（UTC）
- 実機: `mox@192.168.10.132`（Debian 13 / kernel 6.12.57, hostname `angelic`）
- 対象バイナリ: `~/.local/bin/herdr` **0.7.5**（`herdr --version`）
- リポジトリ: `feat/support-hardr` @ `0ece3e8`
- 計測方法: SSH から herdr CLI を直接実行し、応答 JSON / `pane read --source recent --raw` の `od -c` 出力を収集。エスケープ・制御文字の伝送検証は `stty -icanon -ixon -ixoff; cat -v` を実行したテスト pane へのエコーでバイトレベル確認。
- 検証環境: `make analyze` / `make test` は計測時点で Green（詳細は自己検証結果参照）。
- 生データ: `tool/herdr-mutation-baseline/results/t0-spike-20260809T000747Z/`

> 注意: 本スパイクの計測中に作成したテスト workspace（`t0-spike` / w5）は
> 後片付け済み。ホストは元の 4 workspace 状態（w1 フォーカス）に復元済み。

---

## ① 全キーの送信経路分類表（send-keys 受容性の実測）

`herdr pane send-keys <PANE> <KEY>` を 150 キー超について実行し、`rc=0`（受理）か
`{"error":{"code":"invalid_key","message":"unsupported key <KEY>"}}` + `rc=1`（拒否）を判定。

### 1-a. 受理キー（send-keys 直接送信が可能。計 21 種）

| 分類 | 受理キー |
|---|---|
| ファンクション | F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 |
| 基本 | Enter Tab Space Backspace BS Escape |
| カーソル | Up Down Left Right |
| 制御 | C-c（小文字 `c-c` も受理。`C-x`/`C-a` 等は**拒否**） |

受理時の送信バイト（`cat -v` エコーで確認）: `F5`→`ESC[15~`、`Up`→`ESC[A`、
`Down`→`ESC[B`、`Left`→`ESC[D`、`Right`→`ESC[C`、`Escape`→`ESC` 単独、
`Enter`→`\r`、`Backspace`/`BS`→`0x7f`（DEL）。

### 1-b. 拒否キー（send-keys 不可 → **send-text エスケープ / 制御文字経路**）

| 分類 | 拒否キー | 代替送信経路 |
|---|---|---|
| 編集/移動 | Home End PageUp PageDown Delete Insert（代替スペル `PgUp PgDn Prior Next Del Ins` `home pageup` も全て拒否） | `send-text` エスケープ: `ESC[H` `ESC[F` `ESC[5~` `ESC[6~` `ESC[3~` `ESC[2~` |
| C-* 制御 | C-a C-b C-d C-e C-f C-g C-h C-i C-j C-k C-l C-m C-n C-o C-p C-q C-r C-s C-t C-u C-v C-w C-x C-y C-z（**C-c のみ受理**） | `send-text` 制御文字: 0x01〜0x1a を直接送信（`C-d`=`0x04`、`C-x`=`0x18` 等） |
| C-* 修飾 | C-Space C-Tab C-Enter C-Backspace C-Delete C-Home C-End C-Left C-Right C-Up C-Down C-PageUp C-PageDown C-Insert C-@ C-[ C-\ C-] C-^ C-_ C-? | `send-text` エスケープ: `ESC[1;5A`（C-Up）等 |
| S-* | S-Up S-Down S-Left S-Right S-Home S-End S-PageUp S-PageDown S-Delete S-Insert S-Tab S-Space S-Enter S-Backspace S-F1〜S-F12 | `send-text` エスケープ: `ESC[1;2A`（S-Up）等 |
| M-* | M-a〜M-z（26種） M-Up M-Down M-Left M-Right M-Home M-End M-PageUp M-PageDown M-Delete M-Insert M-Tab M-Space M-Enter M-Backspace M-F1〜M-F12 | `send-text` エスケープ: `ESC[1;3C`（M-Right）等、または ESC+文字 |

**結論**: herdr 0.7.5 の send-keys は「F キー・基本キー・矢印・C-c」の最小語彙のみ。
tmux が持つ Home/End/PageUp/PageDown/Insert/Delete・S-/M- 修飾キーは全て
`invalid_key` で拒否されるため、**拒否キーは `send-text` でエスケープシーケンスを
送る経路が必須**。MuxPod アダプタのキー変換表はこの 2 経路に分岐する必要がある。

### 1-c. エラー形式

```json
{"error":{"code":"invalid_key","message":"unsupported key Home"},"id":"cli:request"}
```
- 拒否時の CLI exit code は **1**（JSON-RPC 形式のエラーを stdout に出力）。
- 受理時は stdout 無し・exit code 0。
- 注: 受理キーの中に誤って送ると shell 操作が実行される（例: Enter は空行実行、
  C-c は SIGINT）。計測は全て空プロンプト/テスト pane で実施。

---

## ② エスケープシーケンスの伝送確認（send-text 経路）

`herdr pane send-text <PANE> "<バイト列>"` を `stty -icanon -ixon -ixoff; cat -v` 実行中の
pane に送り、`pane read --source recent --raw` の `od -c` でバイトレベル確認。
**全シーケンスがアプリ（cat）に完全到達**。エコーは tty echo と cat -v 出力の 2 重で
同一バイト列が現れる（例: `\x1b[H` → `^ [ [ H` が 2 回）。

| 論理キー | 送信バイト | cat -v エコー | 到達 |
|---|---|---|---|
| Home | `\x1b[H` | `^[[H` | ✓ |
| End | `\x1b[F` | `^[[F` | ✓ |
| PageUp | `\x1b[5~` | `^[[5~` | ✓ |
| PageDown | `\x1b[6~` | `^[[6~` | ✓ |
| Delete | `\x1b[3~` | `^[[3~` | ✓ |
| Insert | `\x1b[2~` | `^[[2~` | ✓ |
| F1〜F4 | `\x1bOP` `\x1bOQ` `\x1bOR` `\x1bOS` | `^[OP` 等 | ✓ |
| F5〜F12 | `\x1b[15~` `\x1b[17~` `\x1b[18~` `\x1b[19~` `\x1b[20~` `\x1b[21~` `\x1b[23~` `\x1b[24~` | `^[[15~` 等 | ✓ |
| S-Up/Down/Right/Left | `\x1b[1;2A/B/C/D` | `^[[1;2A` 等 | ✓ |
| S-Home / S-End | `\x1b[1;2H` / `\x1b[1;2F` | `^[[1;2H` 等 | ✓ |
| C-Left/Right/Up/Down | `\x1b[1;5C/D/A/B` | `^[[1;5C` 等 | ✓ |
| C-Home / C-End | `\x1b[1;5H` / `\x1b[1;5F` | `^[[1;5H` 等 | ✓ |
| M-Left/Right/Up/Down | `\x1b[1;3C/D/A/B` | `^[[1;3C` 等 | ✓ |

- `send-text` はバイナリ素通し（bracketed paste 等の変換なし）。
- 注意: エスケープを含むシーケンスの一部（`\x1b[5~` の `5~` 部）が pane 横幅で
  wrap して見えることがあるが、`od -c` 上は同一バイト列の連続として到達を確認。

---

## ③ 制御文字の伝送確認（send-text 経路）

`stty -icanon -ixon -ixoff; cat -v` の pane に `send-text` で制御文字を送信し、
`^X` 形式のエコーを確認（`od -c`）。

| 制御文字 | バイト | cat -v エコー | 到達 |
|---|---|---|---|
| C-a / C-b / C-e / C-f / C-g / C-h | 0x01 0x02 0x05 0x06 0x07 0x08 | `^A` `^B` `^E` `^F` `^G` `^H` | ✓ |
| **C-d** | **0x04** | `^D` | ✓ |
| **C-x** | **0x18** | `^X` | ✓ |
| C-k / C-l / C-n / C-o / C-p / C-q / C-r / C-s / C-t / C-u / C-v / C-w / C-y | 0x0b 0x0c 0x0e 0x0f 0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17 0x19 | `^K` 〜 `^Y` | ✓（-ixon で flow control 無効化後に確認） |
| C-c | 0x03 | —（pty が SIGINT に変換、アプリ kill） | 伝送自体は成功（シグナル化） |
| C-z | 0x1a | —（pty が SIGTSTP に変換） | 同上 |

- **C-d/C-x は send-text で制御文字として素通し**（icanon の場合は C-d が EOF として
  消費されるため、検証は `stty -icanon` が必要）。
- 注意: `-icanon` にしても `isig` は有効のため、C-c(0x03) と C-z(0x1a) は
  pty でシグナル変換され、バイトとしてアプリに届かない。これらは send-keys で
  C-c が受理されているため（①）、C-c は send-keys 経由、C-z はエスケープ/抑制が妥当。
- IXON フロー制御（デフォルト ON）では C-s(0x13) が出力を停止するため、
  制御文字を連続送信する場合は `-ixon` にするか、C-q で再開する必要がある。

---

## ④ resize ステップ換算

`pane resize --direction <dir> --amount <FLOAT>` の実測（詳細データ:
`results/t0-spike-20260809T000747Z/resize_conversion_notes.md`）。

### 4-a. 基本換算（コンテナ幅 78 セル、単一 horizontal split 起点 0.5）

| `--amount` | 応答 ratio | 対象 pane 幅 | セル増分 |
|---|---|---|---|
| 0.05 | 0.55 | 43 | +4 |
| 0.05（2回目） | 0.6 | 47 | +4 |
| 0.05（3回目） | 0.65 | 51 | +4 |
| 0.1 | 0.75 | 59 | +8 |
| 0.2 | 0.9（クランプ） | 70 | +11（上限で頭打ち） |
| 0.5 | 0.9（changed=false） | 70 | +0 |

**セル換算式**: 対象 pane 幅 = `round(ratio × コンテナ幅)`。
→ **ratio 0.05 = 約4セル、0.1 = 約8セル、0.2 = 約16セル**（78セルコンテナ時）。

### 4-b. セマンティクス（重要）

1. **amount は現在 ratio への加算**（絶対指定ではない）: 0.5→0.55→0.6→0.75→0.9。
2. **結果は [0.1, 0.9] にクランプ**。到達後は `changed=false` + `reason:"unchanged"`。
3. **1回の呼び出しで適用される delta は最大 0.5**（amount=0.7 でも +0.5 として適用）。
4. **負値は絶対値扱い**（`-0.4` = `+0.4`）。縮小方向の符号は存在しない。
   縮小は反対方向（対側 pane を成長）で行う。
5. `direction` は「対象 pane をその方向に成長」。右 pane に `--direction left` を
   指定すると左 pane の share が減る（= 右 pane が成長）。
6. 応答 JSON の ratio は浮動小数（`0.65000004` 等）で返る。

### 4-c. resize 応答例（layout 込み）

```json
{"id":"cli:pane:resize","result":{"resize":{"changed":true,"focused_pane_id":"w5:p1",
  "layout":{...}, "pane_id":"w5:p1"},"type":"pane_resize"}}
```
- 変化が無い場合: `"reason":"unchanged"` が付与され `changed:false`。

---

## ⑤ focus / edges の実応答

### 5-a. `pane edges --pane <id>`（隣接方向の有無 + layout 込み）

```json
{"id":"cli:pane:edges","result":{"edges":{"down":true,"layout":{...},"left":true,
  "pane_id":"w5:p1","right":false,"up":true},"type":"pane_edges"}}
```
- 3 pane 横並びの左端 pane で `right:false`（右隣無し）、`left/up/down:true`。
- 構造化ナビゲーション（方向 → 隣接有無）が可能。

### 5-b. `pane focus --direction <dir> --pane <id>`

成功（右隣へ移動）:
```json
{"id":"cli:pane:focus","result":{"focus":{"changed":true,"focused_pane_id":"w5:p3",
  "layout":{...},"source_pane_id":"w5:p1"},"type":"pane_focus_direction"}}
```

隣接なし（soft 失敗）:
```json
{"id":"cli:pane:focus","result":{"focus":{"changed":false,"focused_pane_id":"w5:p3",
  "layout":{...},"reason":"no_neighbor","source_pane_id":"w5:p1"},"type":"pane_focus_direction"}}
```
- 隣接が無い場合は **エラーではなく** `reason:"no_neighbor"` + `changed:false` の
  soft 失敗。CLI exit code は 0。
- `changed:false` でも `focused_pane_id` は現フォーカスを返す。

---

## ⑥ mutation 応答 layout JSON の実構造

layout JSON は `api snapshot` の `layouts[]` と、resize/zoom/focus/edges の各応答内
`layout` に共通で現れる。split 応答のみ layout を含まない（下記）。

```json
{
  "area":       {"height":59,"width":78,"x":26,"y":1},
  "focused_pane_id": "w5:p1",
  "panes": [
    {"focused":true,  "pane_id":"w5:p1", "rect":{"height":59,"width":39,"x":26,"y":1}},
    {"focused":false, "pane_id":"w5:p4", "rect":{"height":59,"width":39,"x":65,"y":1}}
  ],
  "splits": [
    {"direction":"right","id":"split_0_root","ratio":0.5,
     "rect":{"height":59,"width":78,"x":26,"y":1}},
    {"direction":"down","id":"split_1_0","ratio":0.6,
     "rect":{"height":59,"width":39,"x":26,"y":1}}
  ],
  "tab_id":"w5:t1", "workspace_id":"w5", "zoomed":false
}
```

| フィールド | 意味 |
|---|---|
| `area` | タブ全体の表示領域（絶対座標 x/y + サイズ） |
| `panes[]` | pane 一覧。各 pane は `focused` / `pane_id` / `rect`（絶対座標） |
| `splits[]` | split ツリー。`direction`(right/down)・`id`(`split_0_root`=ルート)・`ratio`・`rect` |
| `zoomed` | zoom 状態（bool）。zoom on で `true` になるが pane rect 自体は不変（後述） |
| `focused_pane_id` | 当該タブのフォーカス pane |

### 6-a. コマンド別応答型（`result.type`）

| コマンド | `result.type` | layout を含むか | 備考 |
|---|---|---|---|
| `pane split` | `pane_info` | **含まない**（新 pane の `pane` オブジェクトのみ） | layout 取得は別途 snapshot が必要 |
| `pane resize` | `pane_resize` | 含む（`resize.layout`） | `changed` / `pane_id` / `reason`(任意) |
| `pane zoom` | `pane_zoom` | 含む（`zoom.layout`） | `zoom_changed` / `focus_changed` / `zoomed` |
| `pane focus` | `pane_focus_direction` | 含む（`focus.layout`） | `source_pane_id` / `reason`(任意) |
| `pane edges` | `pane_edges` | 含む（`edges.layout`） | `up/down/left/right` の bool |
| `workspace create` | `workspace_created` | — | `workspace` / `tab` / `root_pane` |

### 6-b. zoom の実挙動（注意点）

- `pane zoom --pane <id> --on` 応答: `zoomed:true`、`zoom_changed:true`。
- しかし **layout JSON の `panes[].rect` は zoom 前後で変化しない**（実測で確認）。
  zoom 状態は `layouts[].zoomed` フラグでのみ表現され、snapshot の
  `panes[]` / `splits[]` は**非 zoom 時のレイアウトのまま**。
- → MuxPod で zoom を扱う場合、pane 表示サイズを rect から算出する実装は
  `zoomed` フラグを別途考慮する必要がある（表示はタブ全面、rect は非 zoom 値）。

### 6-c. snapshot 全体構造（`api snapshot`）

- `layouts[]`: タブ毎の layout（上記）。`focused_pane_id`（タブ内）。
- `panes[]`: 全 pane の詳細（`cwd` / `terminal_id` / `terminal_title` / `revision` /
  `scroll{max_offset_from_bottom,offset_from_bottom,viewport_rows}` / `agent_status` 等）。
- `tabs[]` / `workspaces[]` / `agents[]` / `focused_workspace_id` / `focused_tab_id` /
  `focused_pane_id` / `protocol`(17) / `version`("0.7.5")。

---

## 実測コマンド一覧（再現手順）

```bash
# send-keys 受容性（全キーは scripts/remote_sendkeys_sweep.sh に収録）
herdr pane send-keys <PANE> F5            # rc=0（受理）
herdr pane send-keys <PANE> Home          # rc=1 invalid_key（拒否）

# 拒否キーのエスケープ経路（伝送確認: cat -v + pane read）
herdr pane send-text <PANE> $'\x1b[H'     # Home
herdr pane send-text <PANE> $'\x1b[5~'    # PageUp
herdr pane send-text <PANE> $'\x04'       # C-d（制御文字）
herdr pane read <PANE> --source recent --raw

# resize / focus / edges / zoom
herdr pane resize --pane <PANE> --direction right --amount 0.1
herdr pane focus  --direction right --pane <PANE>
herdr pane edges  --pane <PANE>
herdr pane zoom   --pane <PANE> --on
herdr api snapshot
```

## 残課題

1. **`pane read --source recent --lines N --raw` が空を返す**（`--lines` と `--raw` の
   併用で 0 バイト）。単独では正常。`--lines` のセマンティクス要確認。
2. resize の「1回あたり delta 最大 0.5」は実測による推論。ソース/ドキュメントでの
   裏取りは未実施（バイナリ解析ではキー語彙テーブルは見つからず、実測が正本）。
3. `pane split` 応答は layout を含まないため、split 後に即時レイアウト反映を行う
   実装は追加の `api snapshot` が 1 回必要になる（既存 read-only パスとの整合）。
4. C-z（0x1a）は send-text では SIGTSTP になる。MuxPod のキー経路で C-z を
   エスケープ（`\x1b[27;5~` 等）にするか、送信抑止するかの決定が必要。
5. 本実測はシェル（bash）と `cat -v` を対象。vim 等の full-screen アプリでの
   エスケープ解釈（例: `\x1b[H` でカーソルホーム）は未確認。
