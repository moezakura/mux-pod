#!/usr/bin/env bash
# herdr 0.7.5 resize amount 換算の精密実測
# Usage: bash remote_resize_precise.sh <WORKSPACE_ID> <TARGET_PANE_ID>
set -u
HDR=${HDR:-~/.local/bin/herdr}
WS=${1:-w5}
PANE=${2:-w5:p1}

snapshot_rects() {
  "$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
for l in d['result']['snapshot']['layouts']:
    if l['workspace_id']=='$WS':
        for s in l['splits']:
            print('    split id=%s dir=%s ratio=%s' % (s['id'], s['direction'], s['ratio']))
        for p in l['panes']:
            print('    pane=%s rect=%s' % (p['pane_id'], p['rect']))
"
}

# クリーンな 2-pane 状態にする: w5:p3 を閉じる（存在すれば）
"$HDR" pane close "$WS:p3" >/dev/null 2>&1
"$HDR" pane close "$WS:p2" >/dev/null 2>&1
sleep 0.3
printf '=== clean state (single pane) ===\n'
snapshot_rects

# 0.5 で右分割
printf '\n=== split right ratio=0.5 ===\n'
"$HDR" pane split "$PANE" --direction right --ratio 0.5 >/dev/null 2>&1
sleep 0.3
snapshot_rects

printf '\n=== resize right: 0.05 を 3 回連続（加算/絶対の判別） ===\n'
for i in 1 2 3; do
  printf -- '--- step %s (amount=0.05) ---\n' "$i"
  "$HDR" pane resize --pane "$PANE" --direction right --amount 0.05 >/dev/null 2>&1
  sleep 0.3
  snapshot_rects
done

printf '\n=== resize right: 0.1 / 0.2 / 0.5 を個別 ===\n'
for amount in 0.1 0.2 0.5; do
  printf -- '--- amount=%s ---\n' "$amount"
  "$HDR" pane resize --pane "$PANE" --direction right --amount "$amount" >/dev/null 2>&1
  sleep 0.3
  snapshot_rects
done

printf '\n=== resize right: 負値 -0.1 ===\n'
"$HDR" pane resize --pane "$PANE" --direction right --amount -0.1 >/dev/null 2>&1
sleep 0.3
snapshot_rects

printf '\n=== resize right: amount=0 ===\n'
"$HDR" pane resize --pane "$PANE" --direction right --amount 0 >/dev/null 2>&1
sleep 0.3
snapshot_rects

printf '\n=== resize up: amount=0.1（縦方向） ===\n'
"$HDR" pane split "$PANE" --direction down --ratio 0.5 >/dev/null 2>&1
sleep 0.3
printf -- '--- after split down 0.5 ---\n'
snapshot_rects
"$HDR" pane resize --pane "$PANE" --direction down --amount 0.1 >/dev/null 2>&1
sleep 0.3
printf -- '--- after resize down 0.1 ---\n'
snapshot_rects
