#!/usr/bin/env bash
# herdr 0.7.5 send-keys 受容性スイープ（リモートホストで実行）
# Usage: bash remote_sendkeys_sweep.sh <PANE_ID>
# 出力: TSV（KEY<TAB>RC<TAB>ERROR_JSON）
set -u
HDR=${HDR:-~/.local/bin/herdr}
PANE=${1:-w5:p1}

# 計測対象キー語彙（tmux 系キー名 + 代替スペルの候補）
keys=(
  # --- F キー ---
  F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12
  # --- 特殊キー（標準名 + 代替スペル） ---
  Enter Tab Space Backspace Escape
  Home End PageUp PageDown Delete Insert
  Up Down Left Right
  PgUp PgDn Prior Next Del Ins BS
  # --- C-* ---
  C-a C-b C-c C-d C-e C-f C-g C-h C-i C-j C-k C-l C-m C-n C-o C-p C-q C-r C-s C-t C-u C-v C-w C-x C-y C-z
  C-Space C-Tab C-Enter C-Backspace C-Delete C-Home C-End C-Left C-Right C-Up C-Down C-PageUp C-PageDown C-Insert
  C-@ C-[ C-\ C-] C-^ C-_ C-?
  # --- S-* ---
  S-Up S-Down S-Left S-Right S-Home S-End S-PageUp S-PageDown S-Delete S-Insert S-Tab S-Space S-Enter S-Backspace
  S-F1 S-F2 S-F3 S-F4 S-F5 S-F6 S-F7 S-F8 S-F9 S-F10 S-F11 S-F12
  # --- M-* ---
  M-a M-b M-c M-d M-e M-f M-g M-h M-i M-j M-k M-l M-m M-n M-o M-p M-q M-r M-s M-t M-u M-v M-w M-x M-y M-z
  M-Up M-Down M-Left M-Right M-Home M-End M-PageUp M-PageDown M-Delete M-Insert M-Tab M-Space M-Enter M-Backspace
  M-F1 M-F2 M-F3 M-F4 M-F5 M-F6 M-F7 M-F8 M-F9 M-F10 M-F11 M-F12
)

printf 'KEY\tRC\tERROR\n'
for k in "${keys[@]}"; do
  out=$("$HDR" pane send-keys "$PANE" "$k" 2>&1)
  rc=$?
  err=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
  printf '%s\t%s\t%s\n' "$k" "$rc" "$err"
done
