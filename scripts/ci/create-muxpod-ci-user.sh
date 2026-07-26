#!/bin/bash
#
# MuxPod CI 専用アカウント作成スクリプト
#
#   対象ホスト : 192.168.10.2 (moxs-Mac-mini.local / macOS 15.6 / arm64)
#   作成ユーザ : muxpod-ci （標準ユーザ = 管理者権限なし）
#   実行方法   : sudo bash create-muxpod-ci-user.sh
#
# このスクリプトが行うこと:
#   1. 標準ユーザ muxpod-ci を作成（UID は空きを自動採番）
#   2. SSH サービス ACL (com.apple.access_ssh) に muxpod-ci を追加
#      ※ この Mac は SSH を admin グループのみに制限しているため、
#         これを行わないと標準ユーザは SSH ログインできない
#   3. ~/.ssh/authorized_keys に作業用の公開鍵を配置
#   4. 設定内容を検証して結果を表示
#
# このスクリプトが行わないこと（sudo 不要なので後で SSH 経由で実施）:
#   - Flutter / CocoaPods / fastlane / GitHub Actions runner のインストール
#
set -euo pipefail

USERNAME="muxpod-ci"
FULLNAME="MuxPod CI"
HOMEDIR="/Users/${USERNAME}"
USERSHELL="/bin/zsh"
AUTHORIZED_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlbh2rEGIDVygR+y+/umdcv3y4ZXEK3zbL1aD8wZhHq mox@asu-win"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: root で実行してください:  sudo bash $0" >&2
  exit 1
fi

if dscl . -read "/Users/${USERNAME}" >/dev/null 2>&1; then
  echo "ERROR: ユーザ ${USERNAME} は既に存在します。中断します。" >&2
  echo "       作り直す場合は先に削除してください:" >&2
  echo "       sudo sysadminctl -deleteUser ${USERNAME}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. パスワード入力
#    sysadminctl はパスワード必須。CI 用途では対話ログインしないが、
#    アカウント作成には必要なので入力してもらう。
# ---------------------------------------------------------------------------
echo "== ${USERNAME} のログインパスワードを設定します =="
read -r -s -p "パスワード: " CI_PASSWORD; echo
read -r -s -p "パスワード（確認）: " CI_PASSWORD_CONFIRM; echo
if [[ "${CI_PASSWORD}" != "${CI_PASSWORD_CONFIRM}" ]]; then
  echo "ERROR: パスワードが一致しません。" >&2
  exit 1
fi
if [[ -z "${CI_PASSWORD}" ]]; then
  echo "ERROR: 空のパスワードは設定できません。" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. 標準ユーザ作成
#    -admin を付けないことで標準ユーザになる
# ---------------------------------------------------------------------------
echo "== ユーザ ${USERNAME} を作成中 =="
sysadminctl -addUser "${USERNAME}" \
  -fullName "${FULLNAME}" \
  -password "${CI_PASSWORD}" \
  -home "${HOMEDIR}" \
  -shell "${USERSHELL}"

# sysadminctl は失敗しても終了コード 0 を返すことがあるため実在を確認する
if ! dscl . -read "/Users/${USERNAME}" NFSHomeDirectory >/dev/null 2>&1; then
  echo "ERROR: ユーザ作成に失敗しました。" >&2
  exit 1
fi

# ホームディレクトリは初回ログイン時に作られることがあるので明示的に作る
if [[ ! -d "${HOMEDIR}" ]]; then
  echo "== ホームディレクトリを作成中 =="
  createhomedir -c -u "${USERNAME}" >/dev/null
fi

# ---------------------------------------------------------------------------
# 3. SSH サービス ACL に追加
#    この Mac の com.apple.access_ssh は admin グループのみを許可している。
#    muxpod-ci は標準ユーザなので、個別に許可を与える必要がある。
# ---------------------------------------------------------------------------
echo "== SSH アクセス許可 (com.apple.access_ssh) を付与中 =="
dseditgroup -o edit -a "${USERNAME}" -t user com.apple.access_ssh

# ---------------------------------------------------------------------------
# 4. authorized_keys 配置
# ---------------------------------------------------------------------------
echo "== SSH 公開鍵を配置中 =="
install -d -m 700 -o "${USERNAME}" -g staff "${HOMEDIR}/.ssh"
printf '%s\n' "${AUTHORIZED_KEY}" > "${HOMEDIR}/.ssh/authorized_keys"
chown "${USERNAME}":staff "${HOMEDIR}/.ssh/authorized_keys"
chmod 600 "${HOMEDIR}/.ssh/authorized_keys"

# ---------------------------------------------------------------------------
# 5. 検証
# ---------------------------------------------------------------------------
echo
echo "===== 検証結果 ====="
echo "-- ユーザ属性 --"
dscl . -read "/Users/${USERNAME}" UniqueID NFSHomeDirectory UserShell RealName

echo "-- 管理者グループに含まれていないこと（含まれていなければ OK）--"
if dseditgroup -o checkmember -m "${USERNAME}" admin | grep -q "^yes"; then
  echo "警告: ${USERNAME} が admin グループに含まれています（想定外）"
else
  echo "OK: ${USERNAME} は標準ユーザです"
fi

echo "-- SSH アクセス ACL --"
if dseditgroup -o checkmember -m "${USERNAME}" com.apple.access_ssh | grep -q "^yes"; then
  echo "OK: SSH ログインが許可されています"
else
  echo "警告: SSH ACL への追加に失敗しています"
fi

echo "-- ホームディレクトリ --"
ls -ld "${HOMEDIR}" "${HOMEDIR}/.ssh" "${HOMEDIR}/.ssh/authorized_keys"

echo
echo "===== 完了 ====="
echo "次のコマンドで疎通確認できます（作業マシンから）:"
echo "  ssh ${USERNAME}@192.168.10.2 'whoami; sw_vers -productVersion'"
