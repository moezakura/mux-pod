# v17_wrapped_link.bin

行をまたいで実際に折り返す OSC 8 リンクの実測 fixture（`probe observe
--save-raw` で採取した生バイト列そのもの）。`v22_wrapped_link.bin` と同じ
背景・同じ出力スクリプトによる、protocol 17 版。

- 採取元: `muxpod-legacy-herdr` の **`herdr075b`**（herdr v0.7.5 / protocol
  17）。**`herdr075` ではない**
- **`herdr075` を使わなかった理由**: `herdr075` の `w1:p1` は既知の
  異常（`pcui`（PC側UIクライアント）が `script` 経由で起動しておりPTY
  サイズを握っている）が今回も再現し、
  `probe attach-hold --cols 80 --rows 24` によるリサイズ試行（1秒・8秒の
  両方）を行っても `pane.get` の `viewport_rows` が `2` のまま変化せず、
  `stty size` も `2 4`（縮退値）のままだった。`observe` 単体では
  `width=80 height=24` を返すことがあっても、取得された画面内容が
  古い（直前の無関係な作業の残骸）ままで信頼できなかった。この pane を
  無理に使うのは避け、同じ理由により作成済みのクリーンな第二
  インスタンス `herdr075b` を使用した（新規リサイズ操作は一切行っていない）
- pane: `w1:p1`（`clear; bash /home/probe/osc8-wrap-demo.sh` 実行直後）
- observe: `cols=53 rows=23`（`herdr075b` のデフォルトpaneサイズをそのまま
  使用。採取直前に `stty size` で実寸確認済み: `23 53`）
- **注意（列幅の事実確認）**: 当初 `--cols 54` で観測していたが、`stty
  size` を確認したところ実際のPTY幅は `53` 列であった（`54` は誤り）。
  本 fixture は `--cols 53` で採り直したもの。実際のシェルの折り返し判断は
  PTYの真の幅（53）に基づいて行われており、以下の折り返し位置はすべて
  53列基準で一致している
- `frame.seq=1`, `frame.full=true`
- v0.7.5 は既存 `v17_full_redraw.meta.md` に記載のとおり skip 以外の全セル
  直前に CUP を出す全セル再送出方式のため、byte_len が v20/v22 より一桁
  大きい（本fixtureも同様: 21751 bytes）
- **構造上の版差（tracker実装にとって重要）**: v20/v22 は複数行に
  またがる OSC 8 リンクでも open タグを1回しか送らない（row間のCUP
  ジャンプをまたいで有効なまま）のに対し、v17 は **物理行が変わるたびに
  同じ URL で OSC 8 open を再送出し、その行の末尾で一旦 close する**
  （1つの意味的リンクが、行数と同じ回数の open/close ペアに分割されて
  送出される）。本fixtureで実際に確認した構造は以下のとおり
- 含まれる既知リンクと実測範囲（行・開始列・終了列。1-origin、両端含む。
  複数のopen/closeペアにまたがるが、URLが同一かつテキストが連続している
  ことを文字単位で確認済みのため、意味的には1つの折り返しリンクである）:
  1. `https://example.com/osc8-wrap-ascii`（ASCII、111文字、ST終端）
     - row2: col3-col53（open@row2col3, close@row2col53、51文字）
     - row3: col1-col53（open@row3col1, close@row3col53、53文字）
     - row4: col1-col7（open@row4col1, close@row4col7、7文字）
     - 3行にまたがる（51+53+7=111文字、原文と一致）
  2. `https://example.com/osc8-wrap-cjk`（全角文字を含む、CJK 56文字+ASCII
     接頭辞9文字、ST終端）
     - row5: col3-col53（open@row5col3, close@row5col53、30文字。
       `wrap-cjk-` 9文字 + 全角21文字）
     - row6: col1-col53（open@row6col1, close@row6col53、27文字 = 全角26文字
       + **パディング用の半角スペース1文字**。行末 col53 に全角文字が
       収まらず、スペース1文字で埋めてから折り返している。このスペースは
       OSC8 の有効区間（open〜close）の内側で送出されている）
     - row7: col1-col18（open@row7col1, close@row7col18、9文字 = 全角9文字）
     - 3行にまたがる。全角文字の本文だけを数えると 21（row5）+26（row6）
       +9（row7）=56 文字で原文の全角56文字と一致する。OSC8区間内の
       総セル数は row6 のパディングスペース1を加えた 30+27+9=66 セル
- 採取コマンド（再実行して確認済み）:
  `probe observe --socket /home/probe/herdr075b/herdr-client.sock --pane w1:p1 --protocol 17 --cols 53 --rows 23 --save-raw <path>`
- sha256: `140530dd54c4ca2ca440feb2349d5fdfabcc47fde856a533bdb268f28cfac5d5`
