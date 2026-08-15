# TestFlight 自動デプロイ

`v*.*.*` タグを push すると、self-hosted runner 上で署名付き IPA をビルドし
TestFlight へアップロードする。

## 全体像

```
git tag v0.2.2 && git push origin v0.2.2
        │
        ▼
.github/workflows/testflight.yml
        │  runs-on: [self-hosted, macOS, ARM64, muxpod]
        ▼
192.168.10.2 (moxs-Mac-mini) / ユーザ muxpod-ci
        │
        ├─ fastlane match  ──> git@github.com:moezakura/muxpod-certificates
        │                      （AES 暗号化された証明書とプロファイル）
        ├─ flutter build ios --config-only
        ├─ fastlane gym    ──> MuxPod.ipa（手動署名）
        └─ fastlane pilot  ──> App Store Connect / TestFlight
```

## ビルドマシン

| 項目 | 値 |
|---|---|
| ホスト | `192.168.10.2` (moxs-Mac-mini.local) |
| OS | macOS 15.6 / Apple Silicon |
| 実行ユーザ | `muxpod-ci`（標準ユーザ。管理者権限なし） |
| Xcode | 26.1.1 |
| Flutter | 3.44.9（mise 管理） |
| Ruby | 3.3.12（mise 管理） |
| fastlane / CocoaPods | 2.237.0 / 1.17.0 |
| runner | `muxpod-mac-mini` / labels `self-hosted,macOS,ARM64,xcode,muxpod` |

ツールはすべて `muxpod-ci` のホーム配下にインストールしてあり、
CI の実行に sudo は不要。

### 注意点

- **Flutter のバージョン指定**: リポジトリの `.mise.toml` は
  `flutter = "3.44.9-stable"` を指定しているが、これは古い mise
  (asdf プラグイン方式) 向けの表記。ビルドマシンの mise 2026.7.x は
  ここから URL を組み立てる際に `-stable` を二重に付けてしまい 404 になる。

  ```
  flutter_macos_arm64_3.44.9-stable-stable.zip  ← 存在しない
  ```

  ローカル開発環境 (mise 2024.9.x) では現在の表記で動作しているため
  `.mise.toml` は変更せず、workflow の `MISE_FLUTTER_VERSION: '3.44.9'` で
  CI 側だけ上書きしている。環境変数は設定ファイルより優先される。

  将来ローカルの mise を更新した際は `.mise.toml` を `3.44.9` に直し、
  この上書きを削除してよい。
- **libyaml**: macOS には libyaml のヘッダが無いため、mise の Ruby ビルドで
  psych が入らない。`~/.local` に libyaml 0.2.5 を自前ビルドし、
  `RUBY_CONFIGURE_OPTS=--with-libyaml-dir=$HOME/.local` で解決している。
- **ロケール**: fastlane と CocoaPods は UTF-8 ロケールを要求する。
  workflow と LaunchDaemon の両方で `LANG=en_US.UTF-8` を設定している。

## runner の常駐

LaunchAgent ではなく **LaunchDaemon** で常駐させている。LaunchAgent は GUI
ログインセッションを必要とし、ヘッドレス運用や再起動後の自動復帰ができないため。
`UserName` で `muxpod-ci` として動かし、`SessionCreate` により
codesign / keychain 操作に必要なセキュリティセッションを作らせている。

```bash
# 状態確認
sudo launchctl print system/com.muxpod.actions-runner | grep -E 'state|pid'

# ログ
tail -f /Users/muxpod-ci/Library/Logs/com.muxpod.actions-runner/stdout.log

# 停止 / 起動
sudo launchctl bootout   system/com.muxpod.actions-runner
sudo launchctl bootstrap system /Library/LaunchDaemons/com.muxpod.actions-runner.plist
```

## 署名

`fastlane match` で管理する。証明書の秘密鍵とプロビジョニングプロファイルは
`MATCH_PASSWORD` で AES 暗号化した上で private リポジトリ
`moezakura/muxpod-certificates` に保存される。

ビルドマシンからこのリポジトリへは SSH deploy key（`~/.ssh/match_deploy_key`、
write 権限）でアクセスする。GitHub Secrets に PAT を置く必要はない。

CI では実行ごとに使い捨ての keychain を作り、そこへ証明書を取り込んでから
ビルドし、終了時に削除する（ログインキーチェーンは解錠されていないため）。

`ios/Runner.xcodeproj` はリポジトリ上では自動署名のままにしてある。
手動署名の設定は `update_code_signing_settings` で **Runner ターゲットの
Release 構成にだけ** 書き込む。CI の checkout は毎回作り直されるので
pbxproj への書き込みは残らない。

### なぜ xcargs ではないのか

`xcodebuild` のコマンドライン引数は全ターゲットに適用される。
`PROVISIONING_PROFILE_SPECIFIER` をそこで渡すと、プロファイルを受け付けない
Pods のフレームワークターゲットが軒並み失敗する。

```
error: Pods-Runner does not support provisioning profiles, but provisioning
profile match AppStore si.mox.mux-pod has been manually specified.
```

### CODE_SIGN_IDENTITY を 2 回書く理由

プロジェクトレベルに `"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer"`
があり、素の形だけを書いてもこの条件付き指定が残って開発用証明書を探しに行く。

```
error: No signing certificate "iOS Development" found:
No "iOS Development" signing certificate matching team ID "MUBKJR7U7A"
with a private key was found. (in target 'Runner' from project 'Runner')
```

そのため `update_code_signing_settings` を `sdk: nil` と
`sdk: "iphoneos*"` の 2 回呼んで両方の形を書き込んでいる。

証明書名は match が `sigh_<bundle-id>_appstore_certificate-name` という
環境変数に入れてくれるので、それを使う。

## GitHub Secrets

| Secret | 内容 |
|---|---|
| `ASC_ISSUER_ID` | App Store Connect API の Issuer ID |
| `ASC_KEY_ID` | API キー ID |
| `ASC_KEY_P8_BASE64` | `.p8` を base64 したもの |
| `MATCH_PASSWORD` | match の暗号化パスフレーズ |

ASC API キーのアクセス権限は **Admin** が必要。`App Manager` では match が
証明書を作成する API を呼べない。

`.p8` の base64 化は macOS では次のようにする（`-w0` は使えない）。

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set ASC_KEY_P8_BASE64 -R moezakura/mux-pod
```

## バージョンとビルド番号

タグ `vX.Y.Z` から算出する。既存の `release-ios.yml` と同じ規則。

```
build_name   = X.Y.Z
build_number = X * 10000 + Y * 100 + Z
```

例: `v0.2.1` → build_name `0.2.1` / build_number `201`。

## 手動実行

`workflow_dispatch` に対応している。`version` を省略すると
`pubspec.yaml` の値を使う。

```bash
gh workflow run testflight.yml -R moezakura/mux-pod -f version=0.2.2
```

## マシンの再構築

```bash
# 1. CI 専用アカウントの作成（Mac mini で root として実行）
sudo bash scripts/ci/create-muxpod-ci-user.sh

# 2. ツールチェーン（muxpod-ci として実行）
curl -fsSL https://mise.run | sh
export PATH=$HOME/.local/bin:$PATH
mise use -g flutter@3.44.9

#    Ruby は libyaml を先に用意してからでないと psych が入らない
curl -fsSL -o yaml.tar.gz https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
tar xzf yaml.tar.gz && cd yaml-0.2.5
./configure --prefix=$HOME/.local && make -j8 && make install && cd ..
RUBY_CONFIGURE_OPTS="--with-libyaml-dir=$HOME/.local" mise use -g ruby@3.3

export PATH=$HOME/.local/share/mise/shims:$PATH
gem install --no-document fastlane cocoapods

# 3. runner の取得と登録
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -fsSL -o runner.tar.gz \
  https://github.com/actions/runner/releases/download/v2.336.0/actions-runner-osx-arm64-2.336.0.tar.gz
tar xzf runner.tar.gz && rm runner.tar.gz
./config.sh --url https://github.com/moezakura/mux-pod \
  --token "$(gh api -X POST repos/moezakura/mux-pod/actions/runners/registration-token --jq .token)" \
  --name muxpod-mac-mini --labels self-hosted,macOS,ARM64,xcode,muxpod \
  --work _work --unattended --replace

#    runsvc.sh が読む PATH を設定しておく
printf '%s\n' "$HOME/.local/share/mise/shims:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  > ~/actions-runner/.path

# 4. match 用 deploy key
ssh-keygen -t ed25519 -N "" -C "muxpod-ci@mac-mini match" -f ~/.ssh/match_deploy_key
#    表示された公開鍵を muxpod-certificates の Deploy keys に write 権限で登録し、
#    ~/.ssh/config で github.com にこの鍵を使わせる

# 5. LaunchDaemon として常駐（Mac mini で root として実行）
sudo bash scripts/ci/install-runner-daemon.sh
```
