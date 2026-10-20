# herdr hyperlink fixture 再取得

herdr の OSC 8 ハイパーリンクの描画方式が版によって変わっていないかを、
分離環境（podman コンテナ内の herdr）で再判定するためのスクリプト。手順の
全体（契機・合格基準・合格時の手順）は
[`docs/herdr-caret-helper.md`](../../docs/herdr-caret-helper.md) の
「herdr 新版への追従」を参照。

| ファイル | 内容 |
|---|---|
| `capture_fixtures.sh` | ホスト側のオーケストレータ。ケースごとに workspace を作り、生フレームの採取、`hyperlinks`・`scrollback-links` の実行、判定までを行う |
| `scripts/emit_links.sh` | コンテナ内の pane で既知の OSC 8 リンクを 1 ケース分出して待機する |
| `scripts/fx_json.py` | JSON の取り出しと、`expected.tsv` との完全一致比較（標準ライブラリのみ） |
| `expected.tsv` | ケースごとの期待リンク範囲（行・開始列・終了列は 0 始まり、両端を含む表示セル単位） |

ケース: `ascii`、`cjk`、`kana`（半角カナ濁点）、`wrap`（行またぎ）、
`adjacent`（隣接する別 URL）、`alt`（alt スクリーン内）、`scrollback`
（スクロールバックへ押し出した行）、`scrollback-up`（17/20 以外。最下部から 5 行上げた状態からの往復）。
各ケースで `hyperlinks`・caret・（scrollback 系は）`scrollback-links` を実行し、`expected.tsv` と完全一致で比べる。
SIGWINCH の計数は、各ケースの最後に WINCH を 1 回送り、計数が 1 増えることで動作を確認している
（herdr による resize の再現ではない）。

## 使い方

```sh
cd tools/herdr-caret-helper
cargo build --release --example probe --target x86_64-unknown-linux-musl
cd ../..
tool/herdr-hyperlink-fixture/capture_fixtures.sh \
  --container muxpod-osc8-herdr --protocol 22 --herdr-bin herdr \
  --env-dir /home/probe/.config/herdr \
  --probe tools/herdr-caret-helper/target/x86_64-unknown-linux-musl/release/examples/probe \
  --helper assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper \
  --out-dir /tmp/herdr-fixture-out
```

- 実行中のサーバーに対して動く。サーバーの起動・停止はしない。
- `--protocol` は任意の番号を受け付けるが、`herdr status --json` の `server.protocol` と一致しなければ exit 2 で止まる。
  未登録の番号は、その番号を allow-list と codec・runner に加えた開発用の helper と probe を渡さないと FAIL になる
  （手順は docs の「herdr 新版への追従」）。
- `--out-dir` に `tests/fixtures` 配下は指定できない（コミット済み fixture を
  上書きしない）。出力をレビューして、手でコピーする。
- 作った workspace（label `fx-<case>-p<protocol>`）と、待機中の
  `emit_links.sh` は閉じない。不要になったら利用者が閉じる。
- ホストの herdr と `~/.config/herdr` には触れない。
- 終了コード: 0 = 全ケース合格、1 = 不合格あり、2 = 使い方の誤り・環境の問題。

## 出力

`<out-dir>/p<protocol>/` に、ケースごとの `<case>.bin`（生フレーム）、
`<case>.meta.md`（採取条件・sha256・判定）、helper の出力（`*.json`・`*.err`・
`*.compare.txt`）と、全体の `summary.tsv` を書く。

## 実行で確認できた範囲

| protocol | herdr | 結果 |
|---|---|---|
| 22 | v0.9.1 | 8 ケース（`scrollback-up` を含む）すべて合格。caret も全ケースで期待位置と一致。`scrollback` は `exact`、`scrollback-up`（5 行上から）は `approximate` で offset 5 に戻る |
| 20 | v0.8.2 | 7 ケースすべて合格。caret も全ケースで一致。`scrollback` は `exact` |
| 17 | v0.7.5 | 実行できなかった |

17 の経路（`--protocol 17`）は実装済みだが、実行での確認は 22 と 20 だけ。
v0.7.5（分離環境で起動したサーバー）では 2026-10-19 の時点で
`herdr workspace create` が `ghostty error -2` で失敗し、実行できなかった。
原因は分かっていない。17 の fixture 回帰は、既存の
`tools/herdr-caret-helper/tests/fixtures/v17_*`（`v17_full_redraw` と `v17_wrapped_link`）に対する
`cargo test` がカバーする範囲に限られる。CJK・半角カナ濁点・隣接する別 URL・alt スクリーン・
スクロールバックの各ケースは 17 では未確認。

## 期待値の変更履歴

`expected.tsv` の `kana` は、初回の採取（22）で 0〜2 列と置いたが、FAIL したため 0〜5 列へ
訂正した。根拠は生フレーム（`kana.bin`）の CUP 位置で、ｶﾞ は 1 つあたり 2 セルを占める
（CUP が `1;1` → `1;3` → `1;5`、リンクの閉じが `1;7`）。helper の出力に合わせて直したのではない。
初回の出力はリポジトリには含めていない。
