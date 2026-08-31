# herdr-caret-helper

Herdr のキャレット位置スナップショット取得用 wire helper（実験機能）。
`docs/herdr-caret-snapshot-implementation-plan.md` の Phase 2 成果物。

## 目的

MuxPod のプロセスからは SSH 先の Unix socket へ直接接続できないため、
SSH 先で 1 回だけ実行される小さな補助バイナリとして同梱する。
Herdr 本体・動作中の Herdr プロセスには一切変更を加えない。
`herdr-client.sock` の read-only 観測契約
（Hello → Welcome → ObserveTerminal → 最初の FrameData）だけを利用する。

## 対応版

| protocol | Herdr バージョン | 備考 |
|---|---|---|
| 17 | v0.7.5 | `ClientLaunchMode::TerminalAttach` は variant tag 1 |
| 20 | v0.8.2 | `AppDirectGraphics` 挿入により `TerminalAttach` は tag 2 |

上記以外の protocol は非対応（`usage_error` で非ゼロ終了）。通常の Herdr
接続可否判定（`HerdrAdapter.preflight`）とは独立に、この helper の
対応判定だけが実験機能の有効性を決める。

## 使い方

```sh
herdr-caret-helper --socket <client-socket-path> --pane <paneId> \
  --protocol <17|20> --cols <n> --rows <n> --timeout-ms <n>
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

client socket path は `herdr status --json` の `server.socket`
（API socket、例 `~/.config/herdr/herdr.sock`）から
`<file_stem>-client.sock` 置換（例 `~/.config/herdr/herdr-client.sock`）で
導出する（Herdr の `derive_client_socket_from_api_socket` と同一規則）。

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
- **frames 上限 16MiB**: 超過は `oversized_frame` として拒否。
