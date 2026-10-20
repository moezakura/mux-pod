# v22_full_redraw.bin

実測 fixture（`tools/herdr-caret-helper/examples/probe.rs
observe --save-raw` で採取した生バイト列そのもの。エスケープ加工なし）。

- 採取元: `muxpod-osc8-herdr`（herdr v0.9.1 / protocol 22）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-demo.sh` 実行直後）
- observe: `cols=80 rows=40`、TerminalHello → ObserveTerminal → Resize
- `frame.seq=1`, `frame.full=true`（新規接続の最初のフレーム）
- URL は合成のもの（`example.com`・`file:///etc/hostname`）のみ。実環境の画面内容は含まない
- 含まれる既知リンク（`osc8-demo.sh` の出力、出現順）:
  1. `https://example.com/osc8-https`（ST終端）
  2. `http://example.com/osc8-http`（BEL終端）
  3. `file:///etc/hostname`（http以外のスキーム）
  4. `https://example.com/osc8-red`（SGR併用）
  5. `https://example.com/osc8-wrapped-long-url`（長いURL、折り返し想定）
- カーソル状態（末尾に `CUP → ?25h/?25l`）: このfixtureは `?25h`（表示）
  状態。`?25l`（非表示）・DECSCUSR付きの別バリエーションも同じ方法で観測済みだが、raw binは保存していない
- 採取コマンド: `probe observe --socket /home/probe/.config/herdr/herdr-client.sock --pane w1:p1 --protocol 22 --cols 80 --rows 40 --save-raw <path>`
