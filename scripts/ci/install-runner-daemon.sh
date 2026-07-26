#!/bin/bash
#
# GitHub Actions self-hosted runner を LaunchDaemon として常駐させる
#
#   対象ホスト : 192.168.10.2 (moxs-Mac-mini.local)
#   実行ユーザ : muxpod-ci （LaunchDaemon の UserName で指定）
#   実行方法   : sudo bash install-runner-daemon.sh
#
# LaunchAgent ではなく LaunchDaemon にする理由:
#   LaunchAgent は GUI ログインセッションを必要とするため、ヘッドレス運用や
#   再起動後の自動復帰ができない。LaunchDaemon + UserName + SessionCreate なら
#   ログイン不要で常駐でき、SessionCreate によりセキュリティセッションが
#   作られるので codesign / keychain 操作も動作する。
#
set -euo pipefail

CI_USER="muxpod-ci"
CI_HOME="/Users/${CI_USER}"
RUNNER_ROOT="${CI_HOME}/actions-runner"
SVC_NAME="com.muxpod.actions-runner"
PLIST="/Library/LaunchDaemons/${SVC_NAME}.plist"
LOG_DIR="${CI_HOME}/Library/Logs/${SVC_NAME}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: root で実行してください:  sudo bash $0" >&2
  exit 1
fi

# --- 前提確認 -------------------------------------------------------------
if ! dscl . -read "/Users/${CI_USER}" >/dev/null 2>&1; then
  echo "ERROR: ユーザ ${CI_USER} が存在しません。先に create-muxpod-ci-user.sh を実行してください。" >&2
  exit 1
fi
for f in "${RUNNER_ROOT}/bin/runsvc.sh" "${RUNNER_ROOT}/.runner" "${RUNNER_ROOT}/.credentials"; do
  if [[ ! -e "$f" ]]; then
    echo "ERROR: ${f} がありません。runner の設定が完了していません。" >&2
    exit 1
  fi
done

# --- 既存サービスの停止 ---------------------------------------------------
if launchctl print "system/${SVC_NAME}" >/dev/null 2>&1; then
  echo "== 既存の ${SVC_NAME} を停止中 =="
  launchctl bootout "system/${SVC_NAME}" || true
fi

# --- ログディレクトリ -----------------------------------------------------
install -d -o "${CI_USER}" -g staff -m 755 "${LOG_DIR}"

# --- plist 生成 -----------------------------------------------------------
# PATH は runsvc.sh が ${RUNNER_ROOT}/.path から読み込むが、
# .path が無い場合の保険としてここでも設定しておく。
# LANG は fastlane / CocoaPods が UTF-8 ロケールを要求するため必須。
echo "== ${PLIST} を作成中 =="
cat > "${PLIST}" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${SVC_NAME}</string>

    <key>ProgramArguments</key>
    <array>
      <string>${RUNNER_ROOT}/bin/runsvc.sh</string>
    </array>

    <key>UserName</key>
    <string>${CI_USER}</string>

    <key>WorkingDirectory</key>
    <string>${RUNNER_ROOT}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <!-- セキュリティセッションを作らせる。keychain / codesign に必要 -->
    <key>SessionCreate</key>
    <true/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>ACTIONS_RUNNER_SVC</key>
      <string>1</string>
      <key>HOME</key>
      <string>${CI_HOME}</string>
      <key>USER</key>
      <string>${CI_USER}</string>
      <key>LANG</key>
      <string>en_US.UTF-8</string>
      <key>LC_ALL</key>
      <string>en_US.UTF-8</string>
      <key>PATH</key>
      <string>${CI_HOME}/.local/share/mise/shims:${CI_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
  </dict>
</plist>
PLIST_EOF

chown root:wheel "${PLIST}"
chmod 644 "${PLIST}"
plutil -lint "${PLIST}"

# --- 起動 -----------------------------------------------------------------
echo "== サービスを起動中 =="
launchctl bootstrap system "${PLIST}"
launchctl enable "system/${SVC_NAME}"
launchctl kickstart -p "system/${SVC_NAME}" || true

# --- 検証 -----------------------------------------------------------------
echo
echo "===== 検証結果 ====="
sleep 5
launchctl print "system/${SVC_NAME}" 2>/dev/null | grep -E "^\s+(state|pid|last exit code) " || \
  echo "警告: サービス情報を取得できませんでした"

echo
echo "-- 直近のログ --"
tail -n 20 "${LOG_DIR}/stdout.log" 2>/dev/null || echo "(stdout.log はまだありません)"
tail -n 20 "${LOG_DIR}/stderr.log" 2>/dev/null || echo "(stderr.log はまだありません)"

echo
echo "===== 完了 ====="
echo "GitHub 上で runner が Idle になっていれば成功です:"
echo "  https://github.com/moezakura/mux-pod/settings/actions/runners"
echo
echo "操作コマンド:"
echo "  停止 : sudo launchctl bootout system/${SVC_NAME}"
echo "  起動 : sudo launchctl bootstrap system ${PLIST}"
echo "  ログ : tail -f ${LOG_DIR}/stdout.log"
