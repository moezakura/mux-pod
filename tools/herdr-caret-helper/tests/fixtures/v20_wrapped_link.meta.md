# v20_wrapped_link.bin

行をまたいで実際に折り返す OSC 8 リンクの実測 fixture（`probe observe
--save-raw` で採取した生バイト列そのもの）。`v22_wrapped_link.bin` と同じ
背景・同じ出力スクリプトによる、protocol 20 版。

- 採取元: `muxpod-legacy-herdr` の `herdr082`（herdr v0.8.2 / protocol 20）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-wrap-demo.sh` 実行直後）
- observe: `cols=73 rows=28`（採取直前に `stty size` で実寸確認済み: `28 73`）
- **既知のドリフト**: `v20_full_redraw.meta.md`（初回採取時点）は `cols=100
  rows=29` で記録されているが、その後実環境側で `28 73` へドリフトしたことが
  既に確認済み（復元不要）。本 fixture は現在の
  実寸（`28 73`）でそのまま採取した
- `frame.seq=1`, `frame.full=true`
- 出力元スクリプト: `/home/probe/osc8-wrap-demo.sh`（`v22_wrapped_link.meta.md`
  参照。同一スクリプト・同一開始列のため、pane幅が同じ73colsである
  `v22_wrapped_link.bin` と折り返し位置が一致する）
- 含まれる既知リンクと実測範囲（行・開始列・終了列。1-origin、両端含む）:
  1. `https://example.com/osc8-wrap-ascii`（ASCII、111文字、ST終端）
     - row2: col3-col73（71文字）
     - row3: col1-col40（40文字）
     - 2行にまたがる。open は row2 col3 の1回のみ（v22と同じ構造）
  2. `https://example.com/osc8-wrap-cjk`（全角文字を含む、CJK 56文字+ASCII
     接頭辞9文字、ST終端）
     - row4: col3-col73（71セル、パディング不要）
     - row5: col1-col50（50セル）
     - 2行にまたがる。open/closeとも1回ずつ
- **既知の異常（未解明、対応不要と判断）**: `pane.read`（`source:"recent"`）
  が `stty size` 確認目的の単純な `echo` に対しても空文字列を返すことが
  あった（herdr082プロセス自体は `/proc` 上で生存を確認済み）。本 fixture の
  採取・内容確認は `pane.read` を使わず `probe observe --save-raw` の直接
  取得とバイト列の目視確認で行い、影響を受けていない
- 採取コマンド（再実行して確認済み）:
  `probe observe --socket /home/probe/herdr082/herdr-client.sock --pane w1:p1 --protocol 20 --cols 73 --rows 28 --save-raw <path>`
- sha256: `8aecf1ed0cbfd1ef16a9b810c94852ac26621b409d73901a1676e235f865f83a`
