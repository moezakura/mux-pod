#!/usr/bin/env bash
# herdr 0.7.5 send-text 伝送スイープ（リモートホストで実行）
# Usage: bash remote_transmission_sweep.sh <PANE_ID>
# 前提: 指定 pane でシェルが稼働していること。cat -v を自動起動する。
# 出力: 各シーケンスの NAME と od -c による伝送エビデンス
set -u
HDR=${HDR:-~/.local/bin/herdr}
PANE=${1:-w5:p2}

# pane を cat -v（icanon off）で再初期化
"$HDR" pane send-keys "$PANE" C-c >/dev/null 2>&1
sleep 0.3
"$HDR" pane send-text "$PANE" $'stty -icanon min 1 time 0; cat -v\n' >/dev/null 2>&1
sleep 0.5

# 送信テスト: NAME|バイト列（printf %b で解釈）
tests=(
  "HOME_ESC|\x1b[H"
  "END_ESC|\x1b[F"
  "PGUP_ESC|\x1b[5~"
  "PGDN_ESC|\x1b[6~"
  "DELETE_ESC|\x1b[3~"
  "INSERT_ESC|\x1b[2~"
  "F1_ESC|\x1bOP"
  "F2_ESC|\x1bOQ"
  "F3_ESC|\x1bOR"
  "F4_ESC|\x1bOS"
  "F5_ESC|\x1b[15~"
  "F6_ESC|\x1b[17~"
  "F7_ESC|\x1b[18~"
  "F8_ESC|\x1b[19~"
  "F9_ESC|\x1b[20~"
  "F10_ESC|\x1b[21~"
  "F11_ESC|\x1b[23~"
  "F12_ESC|\x1b[24~"
  "S_UP_ESC|\x1b[1;2A"
  "S_DOWN_ESC|\x1b[1;2B"
  "S_RIGHT_ESC|\x1b[1;2C"
  "S_LEFT_ESC|\x1b[1;2D"
  "S_HOME_ESC|\x1b[1;2H"
  "S_END_ESC|\x1b[1;2F"
  "C_LEFT_ESC|\x1b[1;5C"
  "C_RIGHT_ESC|\x1b[1;5D"
  "C_UP_ESC|\x1b[1;5A"
  "C_DOWN_ESC|\x1b[1;5B"
  "C_HOME_ESC|\x1b[1;5H"
  "C_END_ESC|\x1b[1;5F"
  "M_LEFT_ESC|\x1b[1;3C"
  "M_RIGHT_ESC|\x1b[1;3D"
  "M_UP_ESC|\x1b[1;3A"
  "M_DOWN_ESC|\x1b[1;3B"
  "CTRL_D|\x04"
  "CTRL_X|\x18"
  "CTRL_C|\x03"
  "CTRL_A|\x01"
  "CTRL_E|\x05"
  "CTRL_L|\x0c"
  "CTRL_U|\x15"
  "ESC_ALONE|\x1b"
  "TAB|\x09"
  "ENTER|\x0d"
  "BACKSPACE|\x7f"
  "DEL_BS_ALT|\x08"
)

printf '=== transmission sweep: pane=%s ===\n' "$PANE"
for t in "${tests[@]}"; do
  name=${t%%|*}
  bytes=$(printf '%b' "${t#*|}")
  "$HDR" pane send-text "$PANE" "$bytes" >/dev/null 2>&1
  sleep 0.4
  printf '\n--- %s (sent %q) ---\n' "$name" "$bytes"
  "$HDR" pane read "$PANE" --source recent --raw | od -c | tail -4
done
