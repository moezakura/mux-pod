# herdr-caret-helper

Herdr 接続時の実験的機能（キャレット位置表示・OSC 8 ハイパーリンク表示）
が使う wire helper。`docs/herdr-caret-snapshot-implementation-plan.md` は
キャレット位置機能の実装記録。

## 目的

MuxPod のプロセスからは SSH 先の Unix socket へ直接接続できないため、
SSH 先で 1 回だけ実行される小さな補助バイナリとして同梱する。
Herdr 本体・動作中の Herdr プロセスには一切変更を加えない。

この helper は3つのサブコマンドを持つ:

- サブコマンド省略（既定動作。キャレット位置取得）: `herdr-client.sock` の
  read-only 観測契約（Hello → Welcome → ObserveTerminal → 最初の
  FrameData）だけを利用する。
- `hyperlinks`（通常表示のハイパーリンク取得）: 同じ read-only 観測契約
  を、キャレット位置取得とは別の描画データ形式（後述）で利用する。
- `scrollback-links`（スクロールバックのハイパーリンク取得）: 対象ペイン
  のスクロール位置を一時的に動かしてから元に戻す（read-only ではない）。

## 対応版

対応する protocol はサブコマンドごとに個別に管理する（一覧の定義元は
下記）。

| protocol | Herdr バージョン | キャレット位置 | ハイパーリンク | 備考 |
|---|---|---|---|---|
| 17 | v0.7.5 | 対応 | 対応 | `ClientLaunchMode::TerminalAttach` は variant tag 1 |
| 20 | v0.8.2 | 対応 | 対応 | `AppDirectGraphics` 挿入により `TerminalAttach` は tag 2 |
| 22 | v0.9.1 | 対応 | 対応 | 最小限の wire サブセット（`Hello`/`Resize`/`ObserveTerminal`、`Welcome`/`Terminal`）のみ実装 |

「ハイパーリンク」列は `hyperlinks`・`scrollback-links` の両サブコマンド
に共通の対応状況（両者は同じ描画データ取得の仕組みを使う）。

上記の表で非対応となっている protocol は `usage_error` で非ゼロ終了する。
通常の Herdr 接続可否判定（`HerdrAdapter.preflight`）とは独立に、この
helper の対応判定だけが各実験機能の有効性を決める。

対応範囲の定義元は `tools/herdr-protocols.json`（サブコマンドごとに
独立した一覧を持つ）。変更後は `dart tool/generate_herdr_protocols.dart`
で Dart と Rust の定数を再生成する。CI は `--check` で生成物の更新漏れ
を検出する。対応版を追加するときは Rust の対応する wire codec と runner、
結合テストも追加し、以下の手順で配布バイナリと manifest を更新する。

## 使い方

client socket path は `herdr status --json` の `server.socket`
（API socket、例 `~/.config/herdr/herdr.sock`）から
`<file_stem>-client.sock` 置換（例 `~/.config/herdr/herdr-client.sock`）で
導出する（Herdr の `derive_client_socket_from_api_socket` と同一規則）。
以下の全サブコマンドで共通。

### キャレット位置取得（サブコマンド省略時の既定動作）

```sh
herdr-caret-helper --socket <client-socket-path> --pane <paneId> \
  --protocol <17|20|22> --cols <n> --rows <n> --timeout-ms <n>
```

- 成功時: stdout に単一 JSON 行を出力して exit 0。
  - カーソル表示中:
    `{"cursor":{"x":75,"y":6,"visible":true,"shape":0},"frameWidth":80,"frameHeight":24,"protocolVersion":17,"paneId":"wE:p46"}`
  - カーソル非表示（TUI アプリ等）の正当な観測:
    `{"cursor":null,"frameWidth":80,"frameHeight":24,"protocolVersion":17,"paneId":"wE:p44"}`
- 失敗時: stderr に `{"error":"<kind>"}`（kind のみ。socket path・payload・
  画面内容は含めない）を出力して非ゼロ終了。
  kind: `connect_failed` / `io_error` / `timeout` / `welcome_rejected` /
  `protocol_error` / `decode_error` / `usage_error`

### ハイパーリンク取得（通常表示、`hyperlinks` サブコマンド）

```sh
herdr-caret-helper hyperlinks --socket <client-socket-path> \
  --pane <paneId> --protocol <17|20|22> --cols <n> --rows <n> \
  [--api-socket <herdr-json-api-socket>] \
  --timeout-ms <n> --max-output-bytes <n>
```

`--api-socket`（Herdr の JSON API ソケット、`herdr status --json` の
`server.socket` そのもの）は省略できる。指定した場合、対象ペインの実際
の画面サイズ（`pane.process_info` の `shell_pid` から対象シェルの制御
端末を特定して読み取る）が得られれば、その実サイズで観測する。省略した
場合、または実サイズが読み取れなかった場合は、`--cols`/`--rows` に渡し
た値のまま観測する（この場合もエラーにはならず、stderr の出力は変わら
ない）。MuxPod は `--cols` に 80 列の下限を適用して渡す（pane の幅が
80 列未満でも、観測失敗で画面右端のリンクが消えるのを避けるため）。
MuxPod は `hyperlinks` を呼ぶ際、常に `--api-socket` を渡す（省略する
呼び出し方はしない）ため、実運用では対象ペインの実サイズが読み取れる
限り常にそちらが使われ、この 80 列の下限は実サイズが読み取れなかった
場合のフォールバックとしてのみ働く。キャレット位置取得（サブコマンド
省略時）も同じ 80 列の下限を適用して `--cols` を渡すが、`--api-socket`
には対応しない（常に渡された `--cols`/`--rows` をそのまま使う）。

- 成功時: stdout に単一 JSON 行を出力して exit 0。例:
  ```json
  {"paneId":"w1:p2","protocolVersion":22,"frameWidth":120,"frameHeight":40,
   "truncated":false,
   "links":[{"url":"https://example.com/","ranges":[[3,10,24],[4,0,5]]}],
   "rowHashes":[[3,"9f1c..."],[4,"03ab..."]]}
  ```
  - `links[].ranges` は `[行, 開始列, 終了列]`（0 始まり、列は表示セル
    単位で両端を含む）。行をまたぐリンクは行ごとの範囲に分けて表す。
    同じ URL への複数範囲は 1 エントリにまとめる。
  - `rowHashes` は空でない行すべてのフィンガープリントで、MuxPod 側が
    本文の行と対応づける際に使う。
  - 出力量が `--max-output-bytes`（既定 60000）を超える場合は画面下の
    行から優先して詰め、収まらなかった行のリンクは省略して
    `truncated: true` を付ける。
- 失敗時: stderr に `{"error":"<kind>"}` を出力して非ゼロ終了。kind は
  キャレット位置取得と同じ分類に `render_rejected`（想定外の描画内容
  で判定を拒否した場合）を加えたもの。
- URL は制御文字を除去してから返す。除去後に空になった、または
  2048 バイトを超える URL は無効なリンクとして扱う。
- OSC 8 の URL の途中に制御文字（C0）が含まれるリンクは、そのリンク
  だけを除外する（JSON には除外したことを出さない）。ほかのリンク・
  行・キャレット位置は通常どおり返す（BEL で終わるリンクも同様）。
  URL の途中に ST ではない ESC が現れた場合（終端が欠けた OSC 8 など、
  後続のエスケープシーケンスを URL として飲み込んでしまう場合）、URL の
  終端（ST または BEL）が無いまま画面データが終わった場合、それ以外の
  想定外の描画内容は、従来どおり `render_rejected` になる（画面単位）。

### ハイパーリンク取得（スクロールバック、`scrollback-links` サブコマンド）

```sh
herdr-caret-helper scrollback-links --api-socket <herdr-json-api-socket> \
  --socket <client-socket-path> --pane <paneId> --protocol <17|20|22> \
  --cols <n> --window <offsetFromBottom> [--window <n> ...（最大3個）] \
  --timeout-ms <n> --restore-budget-ms <n> --max-output-bytes <n> \
  --lock-dir <dir>
```

`--api-socket` は Herdr の JSON API ソケット（`herdr status --json` の
`server.socket` そのもの）。`--window` は取得したい範囲を、画面の最下行
からの行数（オフセット）で指定する（複数指定可）。`--rows` に相当する
フラグは無い。`--cols` は必須の引数だが、下記のとおり実際の列数・行数は
原則として対象ペインから読み取った実サイズを使うため、`--cols` の値が
そのまま使われるとは限らない（詳細は下記）。キャレット位置取得の
`--cols` のような下限の引き上げは行わない。

このサブコマンドは対象ペインのスクロール位置を一時的に動かしてから
必ず元に戻す。取得中は PC 側で同じ Herdr を見ている利用者にも、画面が
短時間スクロールして見える。

protocol 17/20 では、この動作の内部でペインへ直接接続する処理（Herdr
の隠しコマンド `herdr terminal attach`・`herdr terminal session control`
が使うのと同じ接続方式）を使う。同じペインにこれらのコマンドで直接接続
しているクライアントが既にあれば、その接続は切断され、自動では再接続
されない。Herdr 本体の通常の操作画面はこの接続方式に参加しないため、
影響を受けない（実機で確認済み）。

protocol 17/20 では、接続前に対象ペインの直前の `pane.get` を確認し、
`offset_from_bottom == 0` かつ `max_offset_from_bottom > 0`（画面が最下部
にあり、かつ遡れるスクロールバックが存在する）場合にのみ、以降の処理
（実際の列数の読み取り・接続・スクロール）を行う。この条件を満たさない
場合は、列数の読み取りも接続もスクロールも行わない。この場合も exit 0
で、`windows` が空配列の成功出力を返す（`restore` の分類は、遡れる
スクロールバックが無かっただけの場合は `exact`/`failed`、画面が最下部
になかった場合は `approximate` になる。後述の「既知の制約」参照）。

条件を満たした場合は、接続・観測の前に対象ペインの実際の列数・行数を
一度だけ読み取る（`pane.process_info` の `shell_pid` から対象シェルの
制御端末を特定し、その実際の画面サイズを読み取る）。読み取れたサイズは、
接続（Hello/Resize）と、各 window の描画内容の観測の両方に使う。列数を
実際の値に合わせるのは、接続時に渡す列数が対象ペインの実際の列数と
異なると、この接続が対象ペインの実寸法を実際に書き換え、対象プログラム
へ画面サイズ変更の通知（SIGWINCH）が届くことを実機で確認したための対応
で、`--cols` の値ではなく、常にこの実際のサイズで接続・観測する。実際の
サイズが読み取れない場合は、接続自体を行わず `winsize_unavailable` で
失敗する（この場合もスクロールは行われない）。この対応を導入する前の
検証で観測された、最初の画面サイズ変更通知の原因は特定されていない。
ピクセル単位の寸法（フォントの実ピクセルサイズ）の不一致については
未検証。

protocol 22 はスクロール位置の移動・復元に Herdr の API（`pane.scroll`）
を使い、上記の直接接続は行わないため、この実サイズの読み取りは各
window の描画内容の観測（スクロール自体ではない）にのみ関わる。この
観測では実サイズの読み取りを fail-open で行い、読み取れた場合はその
値（列数・行数とも）を、読み取れなかった場合は `--cols` に渡した値と
対象ペインの `pane.get` から得た `scroll.viewport_rows` の組を使う。

通常表示のハイパーリンク取得（hyperlinks）・キャレット位置取得の観測
は、寸法の指定にかかわらず対象ペインの画面サイズを変更しない（実機で
確認済み、こちらは影響を受けない）。

`--lock-dir` は必須の引数で、MuxPod からは
`${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/locks/`（パーミッ
ション 0700）を渡す。同じペインへの並行実行は、このディレクトリ配下の
ペインごとのロックファイルで直列化される。ロックは OS がプロセス終了時
に解放するため、異常終了しても残らない。

- 成功時: stdout に単一 JSON 行を出力して exit 0。例:
  ```json
  {"paneId":"w1:p2","protocolVersion":22,"restore":"exact",
   "windows":[{"requestedOffset":120,"actualOffset":120,
     "frameWidth":120,"frameHeight":40,"truncated":false,
     "links":[{"url":"https://example.com/","ranges":[[3,10,24]]}],
     "rowHashes":[[0,"9f1c..."],[1,"03ab..."]]}]}
  ```
  - `restore` は元の位置に戻せたかどうかの分類:
    - `exact`: 元がスクロールバックの最下部だったため、最下部へ正確に
      戻せた
    - `approximate`: 元は最下部以外で、取得中に流れた出力の行数を
      考慮して近い位置へ戻した（出力量や Herdr 側の丸めにより厳密には
      一致しない場合がある）
    - `skipped_reset`: 取得中に利用者の操作等で既に最下部へ戻っていた
      ため、位置を動かさなかった
    - `failed`: 復元の呼び出し自体が失敗・時間切れになった。この場合、
      動かしたスクロール位置がそのまま残る（PC 側で手動でスクロール
      し直せば元に戻る）
  - `links`・`rowHashes`・出力量の詰め方は `hyperlinks` と同じ。
  - `truncated: true` は、出力量の制限で省略した窓に加えて、描画内容を
    拒否した窓（`render_rejected` 相当、または全画面描画でなかった窓）
    にも付く。拒否した窓は `links`・`rowHashes` が空で、窓の数と順序は
    保たれる。この窓の `frameWidth`/`frameHeight` は、画面データを
    読めた場合はそのフレームの寸法、全画面描画でなくフレームを使えな
    かった場合は観測に使った寸法（17/20 と、22 で実際の列数・行数を
    読み取れた場合は読み取った実寸、22 で読み取れなかった場合は
    `--cols` と対象ペインの viewport 行数）になる。残りの窓の取得と位置の復元は通常どおり続く。
    観測した窓がすべて拒否された場合は、復元を行ったうえで全体を
    `render_rejected` で失敗させる。接続失敗・時間切れなど描画の拒否
    以外の失敗は、従来どおり全体の失敗になる。
  - MuxPod 側は `truncated: true` の窓を「取得済み」にしない。次に
    スクロールが止まったとき（既存の開始間隔の制限に従う）に、その窓が
    再取得の対象になる。出力量の上限で入りきらなかった窓も同じ扱いで、
    同じ内容のまま再取得が繰り返される場合がある。
- 失敗時: `hyperlinks` の失敗分類に加えて、`busy`（同じペインへの取得
  が別プロセスと重複した）・`unsupported_scroll`（スクロール操作に対応
  しない protocol）・`attach_rejected`（スクロールバック取得用の接続が
  拒否・切断された）・`winsize_unavailable`（protocol 17/20 で対象ペイン
  の実際の列数が読み取れなかった）を返す。`winsize_unavailable` の場合は
  接続そのものを行っていないため、位置の復元も行わない。それ以外の失敗
  は、取得自体に失敗しても位置の復元は必ず試みる。

helper 1 回の実行時間（コマンド全体）の目安は以下のとおり。計測は
`podman exec`（コンテナに対するローカル実行で、SSH 経由ではない）を
使って 1 回の呼び出しを 20 回連続実行し、壁時計で計測した。

| protocol | 回数 | 最小 | 中央値 | 最大 |
|---|---|---|---|---|
| 17 | 20 | 291ms | 292.0ms | 293ms |
| 20 | 20 | 291ms | 292.0ms | 295ms |
| 22 | 20 | 368ms | 547.5ms | 574ms |

いずれもコンテナへの `exec` 起動にかかる時間を含む値であり、悲観的な上限値
（helper 単体の処理時間だけを取り出した計測ではない）。また 17/20 と 22 は
別々のコンテナ・別々の pane 履歴サイズで計測しており、条件が揃っていない
ため、3 protocol 間の厳密な比較としては扱わず、それぞれの目安値として
参照すること。

上記は helper というコマンド全体の実行時間であり、「PC 側の表示が実際に
スクロールしている時間」（位置の移動開始から復元完了まで）はこれとは別の
指標として個別に計測している（コンテナ内から高頻度にペインの位置を確認し、
位置が変わってから元に戻るまでの時間を測るため、コマンド起動のオーバー
ヘッドは含まれない）。`--window` を 1 個・3 個（この helper が受け付ける
最大数）指定した場合の結果は次のとおりで、いずれも 300ms 以内に収まって
いる。

| protocol | 窓数 | 最小 | 中央値 | 最大 |
|---|---|---|---|---|
| 17 | 1 | 16ms | 17ms | 19ms |
| 20 | 1 | 16ms | 18.5ms | 35ms |
| 22 | 1 | 21ms | 22ms | 24ms |
| 17 | 3 | 26ms | 50.5ms | 69ms |
| 20 | 3 | 51ms | 52ms | 145ms |
| 22 | 3 | 54ms | 56ms | 58ms |

3 窓は 1 窓のおよそ 2.5〜3 倍で、3 窓分の移動・復元を直列に行っていると
考えれば妥当な増加。protocol 20・3 窓の最大値 145ms は 20 回中 1 回だけの
値で、計測に使った位置確認の呼び出し自体が一時的に遅延した可能性があり
（他の 19 回は 51〜70ms の範囲に収まっている）、実際の復元完了時刻はこの
最大値より早かった可能性がある。

## リモート配置（MuxPod からの利用）

配置先は content-addressed cache:

```
${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/<sha256>/herdr-caret-helper
```

- 一時名で SFTP upload → `sha256sum`/サイズ再検証 → rename → `chmod 0700`
- 既存ファイルの hash が一致すれば再 upload しない

削除方法（ユーザーが明示的に行う）:

```sh
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret"
```

このディレクトリには配置した helper 本体だけでなく、`scrollback-links` が
使うロックファイル（`herdr-caret/locks/` 配下）も含まれるため、上記コマンド
1 つで両方とも削除される。

MuxPod 側のキャッシュ削除 UI は本機能の初期スコープ外。

## ビルドと manifest

配布バイナリ: `assets/herdr-caret-helper/<platform>/herdr-caret-helper`
manifest: `assets/herdr-caret-helper/manifest.json`（size・sha256 記録）

CI（`.github/workflows/ci.yml` の `herdr-caret-helper` job）が
`cargo test`、musl 静的ビルド、manifest とコミット済み asset の
size/sha256 一致を検証する。

ローカル再ビルド手順（toolchain は `tools/herdr-caret-helper/rust-toolchain.toml` で固定）:

```sh
cd tools/herdr-caret-helper
rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl

# x86_64（glibc 非依存の静的バイナリ）
cargo build --release --target x86_64-unknown-linux-musl

# aarch64（zig リンクによるクロスビルド）
cargo install cargo-zigbuild --version 0.22.3 --locked
cargo zigbuild --release --target aarch64-unknown-linux-musl
```

ビルド成果物を assets へ反映したら manifest の size/sha256 を更新する:

```sh
cd <repo-root>
for id in linux-x86_64 linux-aarch64; do
  f="assets/herdr-caret-helper/$id/herdr-caret-helper"
  echo "$id size=$(stat -c%s "$f") sha256=$(sha256sum "$f" | cut -d' ' -f1)"
done
# manifest.json の該当フィールドを書き換える（python で検証も可能）
python3 - <<'EOF'
import hashlib, json, pathlib
m = json.loads(pathlib.Path('assets/herdr-caret-helper/manifest.json').read_text())
for p in m['platforms']:
    d = pathlib.Path(p['asset']).read_bytes()
    assert len(d) == p['size'], p['id']
    assert hashlib.sha256(d).hexdigest() == p['sha256'], p['id']
print('manifest OK')
EOF
```

注意: Rust の静的バイナリでも埋め込みパス等により環境が異なるとバイト
同一にはならないことがある。manifest の sha256 は「コミット済み配布
バイナリ」との一致を意味し、CI 再ビルドのバイト再現性は保証しない。

## 結合試験手順

### ローカル実環境（herdr v0.7.5 / protocol 17）

```sh
# herdr サーバが稼働中であること
herdr status  # socket: ~/.config/herdr/herdr.sock

# pane ID を確認（実値は wN:pN 形式）
herdr api snapshot | python3 -c "import json,sys; print([p['pane_id'] for p in json.load(sys.stdin)['panes']][:5])"

./tools/herdr-caret-helper/target/release/herdr-caret-helper \
  --socket ~/.config/herdr/herdr-client.sock \
  --pane <paneId> --protocol 17 --cols 80 --rows 24 --timeout-ms 3000
```

### 分離 headless 環境（任意のバージョン）

実運用サーバに影響を与えずに検証する場合:

```sh
mkdir -p /tmp/herdr-<ver>-test && cd /tmp/herdr-<ver>-test
cat > config.toml <<'EOF'
[server]
headless_cols = 120
headless_rows = 40
EOF
HERDR_SOCKET_PATH=$PWD/herdr.sock HERDR_CONFIG_PATH=$PWD/config.toml ./herdr server &
sleep 2
./herdr api snapshot   # pane ID 確認（v0.8.2 は応答が {id,result} ラッパー）
./<helper> --socket $PWD/herdr-client.sock --pane <paneId> \
  --protocol <17|20> --cols 80 --rows 24 --timeout-ms 3000
```

v0.8.2 のバイナリは GitHub Releases
（`https://github.com/herdrdev/herdr/releases/download/v0.8.2/herdr-linux-x86_64`）から取得できる。

### リモートホスト経由（SSH 先での動作確認）

テストホスト例: `192.168.10.132`（Linux x86_64 / herdr v0.7.5 稼働）

```sh
ssh 192.168.10.132 'mkdir -p ~/.cache/mux-pod/herdr-caret/manual-test'
scp assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper \
    192.168.10.132:~/.cache/mux-pod/herdr-caret/manual-test/
ssh 192.168.10.132 '~/.cache/mux-pod/herdr-caret/manual-test/herdr-caret-helper \
  --socket ~/.config/herdr/herdr-client.sock --pane <paneId> \
  --protocol 17 --cols 80 --rows 24 --timeout-ms 3000'
```

### Podman を使う場合

SSH 先相当の隔離環境として、Podman コンテナ内に herdr サーバと helper を
置いて同じ手順で検証できる（Unix socket・PTY は通常の Linux 環境と同様に
動作する）。host 側の実herdr とは `HERDR_SOCKET_PATH` で分離すること。

## herdr 新版への追従（fixture 再取得と再判定）

`hyperlinks`・`scrollback-links` は herdr の描画方式とリンク判定
（`visible_hyperlinks`）という内部実装に依存する（「既知制約」の、リンク判定と描画方式への依存の項を参照）。
そのため、新しい herdr 版は下記の再判定に合格してから対応版に加える。
不合格、または未実施の版は allow-list に加えず、fail-closed（機能が
静かに無効になる）のままにする。

### 再判定の契機

- 新しい herdr リリース。
- 本家の未マージブランチ `origin/akbash/1098-wrapped-pane-links`
  （"fix: preserve wrapped pane links"）が herdr 本体にマージされたとき。
  このブランチは `src/server/render_stream.rs` の
  `plain_url_hyperlinks_for_pane` で、OSC 8 の無いプレーン URL も
  `visible_hyperlinks` の結果に合流させる。マージ後は、プレーン URL が
  リンクとして出る挙動変化として記録し、既知制約を更新する。

追跡手順（herdr のソースを clone した場所で行う。MuxPod のリポジトリ
では行わない）:

```sh
git fetch origin
git log --oneline <現在の対応版のタグ>..origin/akbash/1098-wrapped-pane-links
git diff <現在の対応版のタグ>...origin/akbash/1098-wrapped-pane-links -- \
  src/server/render_stream.rs src/app/actions.rs src/server/render_ansi.rs
```

ブランチが `main` へ取り込まれたか（`git branch -r --contains` で確認）を
リリースごとに見る。取り込まれていれば上記の再判定を行う。

### 再判定の手順

1. **分離環境で新版を起動する**。podman コンテナなど、利用者の herdr と
   `~/.config/herdr` に触れない環境で、`HERDR_SOCKET_PATH` を指定した
   `herdr server` を起動する（「結合試験手順」の「分離 headless 環境」
   参照）。サーバーを複数動かす場合、同じ `HOME` の `~/.config/herdr/`
   にある `session.json` とサーバーログは共有される（`HERDR_CONFIG_PATH`
   でこれらが分離できるかは未確認）。
2. **probe と helper を用意する**（配布しない調査用バイナリ）。

   ```sh
   cd tools/herdr-caret-helper
   cargo build --release --example probe --target x86_64-unknown-linux-musl
   ```

   新しい herdr が**未登録の protocol 番号**（allow-list に無い番号）の
   場合、配布済みの helper と probe はそのままでは判定に使えない。
   helper は未登録の protocol を接続前に `usage_error` で拒否する
   （`tools/herdr-caret-helper/src/main.rs` の caret（`unsupported protocol`、
   180-181 行付近）と `hyperlinks`（222-223 行付近）、`src/scrollback.rs`
   の `scrollback-links`（141-142 行付近））。probe も `src/ansi_runner.rs` の
   `observe_terminal_ansi`（61-65 行付近）が未登録の番号を拒否する。
   その場合は、判定のために次を**作業用ブランチで**行う。

   1. `tools/herdr-protocols.json` に新しい番号を加え、
      `dart tool/generate_herdr_protocols.dart` で再生成する。
   2. 新しい番号の wire codec と runner を `herdr-caret-helper` に実装する
      （既存の 17/20/22 の実装を参考にする）。
   3. 上記を取り込んだ helper と probe を、配布しない開発用にビルドして
      次の手順 3 に渡す。
   4. 合格するまでは、これらをコミットしない（手順 5 を参照）。

   helper が未登録の番号を拒否した場合、スクリプトは該当ケースを NG とし、
   全体を FAIL にする（黙って通さない）。

3. **fixture 再取得スクリプトを実行する**。

   ```sh
   tool/herdr-hyperlink-fixture/capture_fixtures.sh \
     --container <name> --protocol <17|20|22> --herdr-bin <コンテナ内の herdr> \
     --env-dir <herdr.sock のあるディレクトリ> \
     --probe <probe のパス> --helper <検証する helper のパス> \
     --out-dir <出力先（tests/fixtures 配下は拒否される）>
   ```

   既知の OSC 8 出力（ASCII・CJK・半角カナ濁点・行またぎ・隣接する別
   URL・alt スクリーン内・スクロールバックへ押し出した行）を pane に
   出し（`scrollback-up` は 17/20 以外）、各ケースの生フレーム（`<case>.bin`）、取得条件（`<case>.meta.md`）、
   helper の出力、判定結果（`summary.tsv`）を `--out-dir` に書く。
   スクリプトはサーバーを起動・停止せず、ケースごとに新しい workspace
   を作って閉じない。`--protocol` は任意の番号を受け付けるが、サーバーが
   名乗る protocol（`herdr status --json` の `server.protocol`）と
   一致しなければ exit 2 で止まる（既存番号を新版へ渡して誤った PASS を
   記録しないため）。値は `environment.txt` と各 `.meta.md` に記録する。
4. **合格基準**（すべて満たす。緩めない）:
   - トラッカーの拒否が 0 件（`hyperlinks`・`scrollback-links`・caret
     が全ケースで exit 0。`render_rejected` が出ない）。
   - 既知リンク範囲・caret 位置（`tool/herdr-hyperlink-fixture/expected.tsv`）
     との完全一致（欠落も余分も 0）。
   - 往復後の位置が復元規則どおりに戻る。スクリプトが検証するのは
     次の 2 つ。元が最下部なら `offset_from_bottom` が 0 に戻り
     `restore` が `exact`。元が最下部以外（5 行上）なら元の 5 に戻り
     `restore` が `approximate`（この 2 つ目は 17/20 以外。17/20 は最下部
     以外からは往復しない）。往復中に出力が流れるケースと
     `skipped_reset` は検証しない。
   - SIGWINCH の計数が機能していること（各ケースの最後に emitter へ
     WINCH を 1 回送り、計数がちょうど 1 増える。`winch_control`）。
   - 観測での SIGWINCH が 0 回。`scrollback-links` の後の SIGWINCH は、
     17/20 では attach によるものを記録のみとし、それ以外の protocol
     （新しい番号を含む）は 0 回を必須とする。
5. **合格した場合のみ**:
   1. （caret も `tools/herdr-protocols.json` の `caretSupportedProtocols`
      に追加する版は、上記の caret の合格も満たすこと。）
   2. `--out-dir` の出力をレビューし、採用するフレームと `.meta.md` を
      `tools/herdr-caret-helper/tests/fixtures/` へ手でコピーする
      （スクリプトは `tests/fixtures` へ直接書かない）。
   3. 手順 2 で用意した作業用ブランチの変更（`tools/herdr-protocols.json`
      と再生成物、新しい番号の wire codec・runner）を、テストを加えて
      コミットする。既に登録済みの番号を再判定しただけの場合は、
      allow-list の変更は不要。
   4. 「ビルドと manifest」の手順で配布バイナリと manifest を更新する。
6. **不合格の場合**: allow-list に追加せず、作業用ブランチの変更はコミットしない。結果と差分を記録する。

herdr を起動する取得は CI では行わない（CI は、コミット済みの fixture
に対する `cargo test` の回帰だけを実行する）。新しい fixture を
`tests/fixtures/` へコピーしただけでは、既存のテストは新しいファイルを
読まない。回帰に含めるには、`tests/hyperlinks_aggregation.rs` などに
対応するテストを追加する。

検証用に SSH 先へ置いた helper とロックファイルの削除手順は、
「リモート配置（MuxPod からの利用）」の節（`rm -rf` の 1 コマンド）に
記載されたものと同じ。ここでは繰り返さない。

### 実行して確認できた範囲

`capture_fixtures.sh` を、以下の組で 1 回ずつ実行した（コンテナ内の
herdr は podman コンテナで稼働中のもの）。

| protocol | herdr | 結果 |
|---|---|---|
| 22 | v0.9.1 | 8 ケース（`scrollback-up` を含む）すべて合格。caret も全ケースで期待位置と一致。`scrollback` は `exact`（往復後 offset 0）、`scrollback-up`（5 行上から）は `approximate` で offset 5 に戻る。SIGWINCH 0 |
| 20 | v0.8.2 | 7 ケースすべて合格。caret も全ケースで一致。`scrollback` は `exact`、SIGWINCH 0 |
| 17 | v0.7.5 | 実行できなかった（下記） |

17 の経路（`--protocol 17`）はスクリプトに実装済みだが、実行での確認は
22 と 20 だけである。v0.7.5（分離環境で起動したサーバー）では、
2026-10-19 の時点で `herdr workspace create` が `ghostty error -2` で
失敗し、ケースごとの pane を作れなかったため実行できなかった。原因は
分かっていない。17 の fixture 回帰は、既存の `tests/fixtures/v17_*`
（`v17_full_redraw` と `v17_wrapped_link`）に対する `cargo test` が
カバーする範囲に限られる。CJK・半角カナ濁点・隣接する別 URL・alt スクリーン・
スクロールバックの各ケースは 17 では未確認である。

## 既知制約

- **snapshot 方式のみ**: 必要時に新規接続して 1 フレーム取得する。同一
  socket での連続追従（push 監視）は再現実験で保証できないため対象外
  （別 Issue）。
- **`cursor: null` は正当な観測**: TUI アプリ等でカーソル非表示の
  ターミナルは `cursor: null` を返す。これは失敗ではなく「非表示
  カーソル」の状態であり、MuxPod 側はカーソルを描画せず従来表示を
  維持する。
- **ObserveTerminal 後に Resize を送る**: TerminalObserve 接続は
  サーバのレンダリングサイクルに乗らないと最初のフレームが来ない
  場合があるため、render kick として同一サイズの Resize を送る
  （observe クライアントではクライアント側記録サイズが更新される
  だけで、観測対象ターミナル自体は resize されない）。
- **不明 pane は timeout 扱い**: サーバは target 解決失敗をエラー
  メッセージで返さないため、フレームが来ず timeout になる。
  失敗分類としては `timeout`（即フォールバックで無害）。
- **frames 上限 16MiB**: 超過は `decode_error` として拒否。
- **`--cols`/`--rows` に 0 は指定できない**: キャレット位置取得・
  `hyperlinks` の `--cols`/`--rows`、`scrollback-links` の `--cols`
  （`--rows` は無い）はいずれも 0 を指定すると `usage_error` で拒否
  される。
- **スクロールバック取得は表示を一時的に動かす**: `scrollback-links`
  は対象ペインのスクロール位置を一時的に動かしてから元に戻す。取得の
  たびに、PC 側で同じ Herdr を見ている利用者にも画面が短時間スクロール
  して見える。
- **古いバージョンでは特定のクライアントが切断されることがある**:
  protocol 17/20（Herdr v0.7.5/v0.8.2）でのスクロールバック取得は、
  Herdr の隠しコマンド `herdr terminal attach`・`herdr terminal session
  control` が使うのと同じ接続方式で対象ペインへ直接接続する。同じペイン
  にこれらのコマンドで直接接続しているクライアントが既にあれば、その
  接続は切断され、自動では再接続されない。Herdr 本体の通常の操作画面は
  この接続方式に参加しないため、影響を受けない（実機で確認済み）。
- **スクロール位置の移動・復元は入力バイトを送らない**: protocol 17/20
  のスクロール位置の移動・復元は、Herdr へ `AttachScroll`（入力バイトを
  空にした `PageKey`）を送るだけで、helper 自身が入力バイトを直接送る
  ことはなく、この方式では Herdr 側が対象プログラムへ入力バイトを注入
  することもない（実機で確認済み。以前使っていた別方式（`Wheel`）では
  マウスレポートモード中にエスケープ列が注入されることを実機で確認して
  いたが、現在の `PageKey` 方式はこれとは別物で注入が無い）。移動は、
  上記「使い方」の条件（`offset_from_bottom == 0` かつ
  `max_offset_from_bottom > 0`）を満たした場合にのみ行う。ある window
  への移動を送った後、移動前の位置から変わっていなければ（要求どおりの
  位置まで届いたかどうかは問わない。protocol 22 を除く）、その window
  の取得は行わず、以降に残っている window もすべて取得せずに打ち切る
  （エラーにはならない。それまでに取得できていた window はそのまま
  返す。移動した場合は、要求どおりの位置に届いていなくても、実際に
  着地した位置の内容で取得する）。復元は、いずれかの window で実際に
  位置が動いていた場合にのみ最下部へ戻す方向で送る（1つも動いていなけ
  れば復元コマンド自体を送らない。ただしこれは 17/20 が成功して終わる
  場合の話で、途中でエラーになった場合や protocol 22 では、移動を送った
  かどうかだけで復元の要否を決める）。取得中に新しい出力が増えても、
  復元は最下部で止まるはずである（Herdr 側のソースコード上はそのように
  クランプされることを確認済みだが、実際に出力が流れている最中に復元を
  行う場面そのものの実機確認はまだ行っていない）。`PageKey` 方式での
  移動・復元が実際のシェル（bash 5.2.15、`exec bash -i` で起動）上でも
  通常どおり機能することは実機で確認済み（zsh 等の他シェルは未確認）。
- **マウスレポートモードや alternate screen・DECCKM では移動がブロック
  される**: 対象プログラムが次のいずれかの状態のとき、上記の移動は要求
  どおりに動かない（位置が変わらない）:
  - マウスレポートモードが有効（v0.7.5・v0.8.2 とも、bracketed paste の
    有無に関わらない）
  - alternate screen 中（v0.7.5・v0.8.2 とも）
  - DECCKM（アプリケーションカーソルキーモード）が有効（v0.7.5 は常に、
    v0.8.2 は bracketed paste が無効の場合）
  
  v0.8.2 で DECCKM と bracketed paste がともに有効な場合のみ、ブロック
  されず通常どおり移動できる。alternate screen 中は、遡れるスクロール
  バック自体が無い（`max_offset_from_bottom == 0`）ことが多く、その場合
  は上記の条件によりそもそも移動を試みない。
- **判定から復元完了までの間の操作との競合**: 直前の `pane.get` で
  `offset_from_bottom == 0` を確認してから、移動・取得・復元が完了する
  までの間に利用者がそのペインを操作（実際のスクロール操作等）すると、
  その位置は復元によって上書きされる。また、判定直後にブロックされる
  状態に入った場合も同様に位置が失われることがある。判定から復元までを
  1回の操作にまとめる手段がプロトコルに無いため、この制約は避けられ
  ない（往復にかかる時間を短くし、呼び出しの間隔を空けることでしか軽減
  できない）。
- **取得をスキップしたかどうかを示す出力はない**: 上記のいずれかの理由
  で取得をスキップした場合でも、出力の形式は変わらない。その回の
  window にハイパーリンクが無いだけで、スキップされたことを示すフィー
  ルドは出力に含まれない。
- **復元後に位置がずれて残ることがある（protocol 22）**: protocol 22 は
  元の表示位置が最下部でなくても取得を行う。取得中に対象ペインへ新しい
  出力が流れると、復元後の位置がずれて残ることがある（元が最下部だった
  場合は正確に戻す）。この場合、出力の `restore` は `approximate` になる。
- **元が最下部でなかったために取得しなかった場合も `restore` は
  `approximate` になる（protocol 17/20）**: protocol 17/20 は、上記
  「使い方」の条件により、元の表示位置が最下部でなかった場合は接続も
  スクロールも一切行わない（`windows` は空配列）。この場合でもペイン
  には触れていないが、出力の `restore` は protocol 22 の実際のずれと
  区別する分類を持たないため、同じく `approximate` になる。遡れる
  スクロールバックが無かっただけ（元は最下部）の場合は、代わりに元の
  位置を読み直して `exact` か `failed` になる。
- **取得中の入力で最下部へ戻ることがある**: 取得中に利用者がそのペイン
  へ入力すると、表示が最下部へ戻ることがある。この場合、その回の取得
  ではハイパーリンクが得られない。
- **取得処理が復元前に終了すると位置が残る**: helper プロセスが復元
  処理の完了前に強制終了されると、動かしたスクロール位置がそのまま
  残ることがある。MuxPod は SSH 接続で PTY を割り当てず helper を
  1 コマンドとして実行する。この方式で実際に検証したところ（OpenSSH
  10.0p2、既定設定）、往復の途中で SSH 接続が切れても、helper は復元
  処理を終えてから終了しており、位置が残ったケースは無かった（切断は
  helper の最後の出力書き込みの失敗として現れるだけで、その時点では
  復元は既に完了している）。PTY を割り当てて実行した場合や、helper が
  強制終了（例: SIGKILL・SIGHUP）された場合には、復元前にプロセスが
  終了し、位置が残ることがある。この検証は OpenSSH でのみ行っており、
  他の SSH サーバ実装での動作は未確認。位置が残った場合は、PC 側で
  対象ペインを手動で最下部までスクロールすれば元に戻る。
- **大量の出力があると一致しないことがある**: スクロールバックを表示
  している間に対象ペインへ大量の出力があると、表示中の行と取得した
  内容の行がずれて一致せず、ハイパーリンクが得られないことがある。
  表示をいったん抜けて入り直すと解消する。
- **古い protocol は対象外**: protocol 14/16/19（Herdr v0.7.0〜v0.7.4、
  v0.8.0）は MuxPod の対応最低バージョンより古いため、この機能の対象外。
- **描画方式が変わると自動的に無効になる**: ハイパーリンクの判定は
  Herdr 内部の描画処理に依存しており、protocol 番号だけでは保証されない。
  想定と異なる出力を検出した場合は、ハイパーリンクを出さずに通常表示へ
  フォールバックする（意図した挙動）。
- **PC 側で幅が変わるとリンクが出ないことがある**: ハイパーリンクの
  位置合わせは、取得時に指定した幅（cols）で対象ペインの行を指紋化して
  比較する。取得の直後に PC 側でペイン幅が変わると、比較対象の行が
  一致しなくなり、その回の取得ではハイパーリンクが得られない。表示を
  いったん抜けて入り直すと解消する。
