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
| Flutter | 3.38.6（mise 管理） |
| Ruby | 3.3.12（mise 管理） |
| fastlane / CocoaPods | 2.237.0 / 1.17.0 |
| runner | `muxpod-mac-mini` / labels `self-hosted,macOS,ARM64,xcode,muxpod` |

ツールはすべて `muxpod-ci` のホーム配下にインストールしてあり、
CI の実行に sudo は不要。

### 注意点

- **Flutter のバージョン指定**: リポジトリの `.mise.toml` は
  `flutter = "3.38.6-stable"` だが、macOS ではこの表記だと mise が
  `-stable` を二重に付与して 404 になる。ビルドマシンには
  `flutter@3.38.6` として導入してある。
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

`ios/Runner.xcodeproj` は自動署名のままにしてあり、手動署名の設定は
ビルド時に `xcargs` で上書きしている。

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
mise use -g flutter@3.38.6

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
