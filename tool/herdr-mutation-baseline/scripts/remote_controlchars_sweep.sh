#!/usr/bin/env bash
# herdr 0.7.5 制御文字伝送スイープ（cat -v を毎回再起動）
# Usage: bash remote_controlchars_sweep.sh <PANE_ID>
set -u
HDR=${HDR:-~/.local/bin/herdr}
PANE=${1:-w5:p2}

restart_cat() {
  "$HDR" pane send-keys "$PANE" C-c >/dev/null 2>&1
  sleep 0.3
  "$HDR" pane send-text "$PANE" $'stty -icanon -ixon -ixoff min 1 time 0; cat -v\n' >/dev/null 2>&1
  sleep 0.4
}

printf '=== control-char transmission sweep: pane=%s ===\n' "$PANE"
# cat -v を初期起動
restart_cat
# NAME|0xNN
tests=(
  "CTRL_A|\x01" "CTRL_B|\x02" "CTRL_C|\x03" "CTRL_D|\x04" "CTRL_E|\x05"
  "CTRL_F|\x06" "CTRL_G|\x07" "CTRL_H|\x08" "CTRL_I|\x09" "CTRL_J|\x0a"
  "CTRL_K|\x0b" "CTRL_L|\x0c" "CTRL_N|\x0e" "CTRL_O|\x0f" "CTRL_P|\x10"
  "CTRL_Q|\x11" "CTRL_R|\x12" "CTRL_S|\x13" "CTRL_T|\x14" "CTRL_U|\x15"
  "CTRL_V|\x16" "CTRL_W|\x17" "CTRL_X|\x18" "CTRL_Y|\x19" "CTRL_Z|\x1a"
  "ESC|\x1b" "BS|\x7f" "TAB|\x09" "LF|\x0a" "CR|\x0d"
)
for t in "${tests[@]}"; do
  name=${t%%|*}
  byte=$(printf '%b' "${t#*|}")
  # cat -v が生きているか確認（pane に改行を送って read で $ があれば死んでいる）
  "$HDR" pane send-text "$PANE" "$byte" >/dev/null 2>&1
  sleep 0.4
  printf '\n--- %s (sent %q) ---\n' "$name" "$byte"
  "$HDR" pane read "$PANE" --source recent --raw | od -c | tail -3
  # C-c / シグナル系は cat が死ぬため再起動
  if [[ "$name" == "CTRL_C" ]]; then
    restart_cat
  fi
done
