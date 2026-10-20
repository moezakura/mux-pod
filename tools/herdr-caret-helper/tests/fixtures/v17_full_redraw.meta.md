# v17_full_redraw.bin

実測 fixture（`probe observe --save-raw` で採取した生バイト列そのもの）。

- 採取元: `muxpod-legacy-herdr` の `herdr075`（herdr v0.7.5 / protocol 17）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-demo.sh` 実行直後）
- observe: `cols=80 rows=24`
- `frame.seq=1`, `frame.full=true`
- URL は合成のもの（`example.com`）のみ
- 含まれる既知リンク（出現順）:
  1. `https://example.com/osc8-https`（ST終端）
  2. `http://example.com/osc8-http`（BEL終端）
- v0.7.5 は `ESC[2J ESC[H` を先頭に必ず出し、skip 以外の
  全セルの直前に CUP を出す（本fixtureはこの版差の実例そのもの。byte_len が
  v20/v22 より一桁大きいのはこの全セルCUPのため）
- **重要な注意（このpaneの既知の異常）**: このpaneの `stty size` は通常時
  `2 4`（極端に小さい、既存の PC 側 UI クライアント `herdr075/pcui.typescript`
  が `script` 経由で起動されており、そのPTYサイズが異常に小さいことが原因。
  調査で判明した既知の異常）。このfixture
  採取のためだけに一時的に `cols=80 rows=24` へ attach でリサイズし、採取後は
  `cols=4 rows=2` へ resize して元の状態に復元した（採取前後で `stty size`
  を確認済み: 復元後 `2 4`）。将来この fixture を再取得する際、パスに
  `pane` の実寸が変わっている可能性があるため、採取前に必ず `stty size` を
  確認すること
- 採取コマンド: `probe observe --socket /home/probe/herdr075/herdr-client.sock --pane w1:p1 --protocol 17 --cols 80 --rows 24 --save-raw <path>`（一時リサイズ後）
