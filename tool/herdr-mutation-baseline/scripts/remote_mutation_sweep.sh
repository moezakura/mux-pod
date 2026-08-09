#!/usr/bin/env bash
# herdr 0.7.5 mutation 応答スイープ（リモートホストで実行）
# Usage: bash remote_mutation_sweep.sh <ROOT_PANE_ID>
# 対象: resize ステップ換算 / edges / focus / zoom / split の応答 JSON と layout 構造
set -u
HDR=${HDR:-~/.local/bin/herdr}
ROOT=${1:-w5:p1}
WORKSPACE=${ROOT%%:*}

# ベース snapshot（split 前）
printf '=== 1. base snapshot (workspace=%s) ===\n' "$WORKSPACE"
"$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
snap=d['result']['snapshot']
for l in snap['layouts']:
    if l['workspace_id']=='$WORKSPACE':
        print(json.dumps(l, indent=1))
"

# split を 1 回追加
printf '\n=== 2. split %s right ratio=0.5 (mutation response) ===\n' "$ROOT"
"$HDR" pane split "$ROOT" --direction right --ratio 0.5 2>&1

# split 後 snapshot layout
printf '\n=== 3. layout after split ===\n'
"$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
snap=d['result']['snapshot']
for l in snap['layouts']:
    if l['workspace_id']=='$WORKSPACE':
        print(json.dumps(l, indent=1))
"

# resize ステップ換算: amount を変えて rect を記録
printf '\n=== 4. resize step conversion (direction=right) ===\n'
for amount in 0.05 0.1 0.2 0.3 0.5; do
  printf '--- amount=%s ---\n' "$amount"
  "$HDR" pane resize --pane "$ROOT" --direction right --amount "$amount" 2>&1
  sleep 0.3
  "$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
snap=d['result']['snapshot']
for l in snap['layouts']:
    if l['workspace_id']=='$WORKSPACE':
        for p in l['panes']:
            print('  pane=%s rect=%s' % (p['pane_id'], p['rect']))
"
done

# 0.5 に戻す
"$HDR" pane resize --pane "$ROOT" --direction right --amount 0.5 >/dev/null 2>&1
sleep 0.3

# edges 応答
printf '\n=== 5. pane edges response ===\n'
"$HDR" pane edges --pane "$ROOT" 2>&1

# focus 応答（右隣 → 左に戻す）
printf '\n=== 6. pane focus right response ===\n'
"$HDR" pane focus --direction right --pane "$ROOT" 2>&1
printf '\n=== 7. pane focus left response (back) ===\n'
"$HDR" pane focus --direction left --pane "$ROOT" 2>&1

# zoom on/off 応答
printf '\n=== 8. pane zoom on response ===\n'
"$HDR" pane zoom --pane "$ROOT" --on 2>&1
printf '\n--- zoom on: layout ---\n'
"$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
snap=d['result']['snapshot']
for l in snap['layouts']:
    if l['workspace_id']=='$WORKSPACE':
        print(json.dumps(l, indent=1))
"
printf '\n=== 9. pane zoom off response ===\n'
"$HDR" pane zoom --pane "$ROOT" --off 2>&1
printf '\n--- zoom off: layout ---\n'
"$HDR" api snapshot 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
snap=d['result']['snapshot']
for l in snap['layouts']:
    if l['workspace_id']=='$WORKSPACE':
        print(json.dumps(l, indent=1))
"
