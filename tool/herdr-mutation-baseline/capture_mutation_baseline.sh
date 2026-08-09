#!/usr/bin/env bash
# herdr mutation baseline 実測収集＋ローカル検証オーケストレータ
# Usage: tool/herdr-mutation-baseline/capture_mutation_baseline.sh [SSH_TARGET]
#   SSH_TARGET: デフォルト mox@192.168.10.132
set -u -o pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

ssh_target=${1:-mox@192.168.10.132}
run_id=$(date -u +%Y%m%dT%H%M%SZ)
base_dir="tool/herdr-mutation-baseline"
out_dir="$base_dir/results/t0-spike-$run_id"
mkdir -p "$out_dir"

echo "==> remote scripts を転送"
scp -q "$base_dir"/scripts/*.sh "$ssh_target":/tmp/

echo "==> send-keys 受容性スイープ"
ssh "$ssh_target" 'bash /tmp/remote_sendkeys_sweep.sh' > "$out_dir/sendkeys_sweep.tsv" 2>&1

echo "==> エスケープ伝送スイープ"
ssh "$ssh_target" 'bash /tmp/remote_transmission_sweep.sh' > "$out_dir/transmission_sweep.log" 2>&1

echo "==> 制御文字伝送スイープ"
ssh "$ssh_target" 'bash /tmp/remote_controlchars_sweep.sh' > "$out_dir/controlchars_sweep.log" 2>&1

echo "==> mutation 応答スイープ"
ssh "$ssh_target" 'bash /tmp/remote_mutation_sweep.sh' > "$out_dir/mutation_sweep.log" 2>&1

echo "==> resize 精密実測"
ssh "$ssh_target" 'bash /tmp/remote_resize_precise.sh' > "$out_dir/resize_precise.log" 2>&1

echo "==> metadata"
{
  printf 'captured_at_utc=%s\n' "$(date -u +%FT%TZ)"
  printf 'host=%s\n' "$ssh_target"
  ssh "$ssh_target" 'uname -a; ~/.local/bin/herdr --version'
  printf 'repo_commit=%s\n' "$(git rev-parse HEAD)"
  printf 'git_status_porcelain:\n'
  git status --porcelain
} > "$out_dir/metadata.txt" 2>&1

echo "==> ローカル検証: make analyze"
make analyze 2>&1 | tee "$out_dir/analyze.log"
analyze_rc=${PIPESTATUS[0]}

echo "==> ローカル検証: make test"
make test 2>&1 | tee "$out_dir/test.log"
test_rc=${PIPESTATUS[0]}

printf 'analyze_exit_status=%s\ntest_exit_status=%s\n' "$analyze_rc" "$test_rc" \
  > "$out_dir/result.summary"

echo "==> 完了: $out_dir"
echo "analyze=$analyze_rc test=$test_rc"
exit $((analyze_rc != 0 || test_rc != 0))
