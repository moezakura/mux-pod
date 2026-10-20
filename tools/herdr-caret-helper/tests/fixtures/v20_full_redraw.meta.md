# v20_full_redraw.bin

実測 fixture（`probe observe --save-raw` で採取した生バイト列そのもの）。

- 採取元: `muxpod-legacy-herdr` の `herdr082`（herdr v0.8.2 / protocol 20）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-demo.sh` 実行直後）
- observe: `cols=100 rows=29`（pane の実寸と一致。`stty size` で確認済み）
- `frame.seq=1`, `frame.full=true`
- URL は合成のもの（`example.com`）のみ
- 含まれる既知リンク（出現順）:
  1. `https://example.com/osc8-https`（ST終端）
  2. `http://example.com/osc8-http`（BEL終端）
- 非ASCIIセル直後のCUP再同期は本fixtureには非ASCII文字を含まないため、
  別途 `echo ABあいCD` の観測（エスケープ表記のテキスト）で確認済み
- 採取コマンド: `probe observe --socket /home/probe/herdr082/herdr-client.sock --pane w1:p1 --protocol 20 --cols 100 --rows 29 --save-raw <path>`
