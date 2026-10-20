# v22_wrapped_link.bin

行をまたいで実際に折り返す OSC 8 リンクの実測 fixture（`probe observe
--save-raw` で採取した生バイト列そのもの。エスケープ加工なし）。

既存の `v22_full_redraw.bin` に含まれる `osc8-wrapped-long-url` リンクは、
調査により行末でちょうど終わっており実際には折り返していないことが
判明したため、本 fixture を別途追加した。

- 採取元: `muxpod-osc8-herdr`（herdr v0.9.1 / protocol 22）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-wrap-demo.sh` 実行直後）
- observe: `cols=73 rows=29`（採取直前に `stty size` で実寸確認済み: `29 73`。
  リサイズ操作は行っていない）
- `frame.seq=1`, `frame.full=true`（新規 observe 接続の最初のフレーム）
- 出力元スクリプト: `/home/probe/osc8-wrap-demo.sh`（コンテナ内にのみ存在、
  リポジトリには未追加。内容は ASCII 111 文字のリンクと、全角文字を含む
  CJK 65 文字のリンクをそれぞれ 1 行出力するだけの `printf`）
- 含まれる既知リンクと実測範囲（行・開始列・終了列。1-origin、両端含む）:
  1. `https://example.com/osc8-wrap-ascii`（ASCII、111文字、ST終端）
     - row2: col3-col73（71文字）
     - row3: col1-col40（40文字）
     - 2行にまたがる。OSC 8 の open は row2 col3 の 1 回のみで、row3 への
       CUP ジャンプをまたいでも再送出されない（close は row3 col40 の 1 回）
  2. `https://example.com/osc8-wrap-cjk`（全角文字を含む、CJK 56文字+ASCII
     接頭辞9文字、ST終端）
     - row4: col3-col73（`wrap-cjk-` 9文字 + 全角31文字 = 71セル。全角文字は
       2セル幅のため、row4 末尾ちょうど col73 で切れ目良く終わり、パディング
       セルは不要だった）
     - row5: col1-col50（全角25文字 = 50セル）
     - 2行にまたがる。open/close ともリンク1と同様に1回ずつ
- 採取コマンド（再実行して確認済み）:
  `probe observe --socket /home/probe/.config/herdr/herdr-client.sock --pane w1:p1 --protocol 22 --cols 73 --rows 29 --save-raw <path>`
- sha256: `59ce36470d5ac9b5ec59673be2b65757add4034a11e2586e7679cd405e2cfe96`
