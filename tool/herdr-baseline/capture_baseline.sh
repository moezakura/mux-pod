#!/usr/bin/env bash
# Captures reproducible validation and G1 contract-test performance baselines.
# Usage: tool/herdr-baseline/capture_baseline.sh [output-directory]
set -u -o pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [output-directory]" >&2
  exit 64
fi

run_id=$(date -u +%Y%m%dT%H%M%SZ)
output_dir=${1:-"tool/herdr-baseline/results/$run_id"}
inventory_path="tool/herdr-inventory/tmux-contract-inventory.json"
if [[ -e "$output_dir" ]]; then
  echo "Refusing to overwrite existing output directory: $output_dir" >&2
  exit 73
fi
mkdir -p "$output_dir"

metadata="$output_dir/metadata.txt"
{
  printf 'captured_at_utc=%s\n' "$(date -u +%FT%TZ)"
  printf 'git_commit=%s\n' "$(git rev-parse HEAD)"
  printf 'git_branch=%s\n' "$(git branch --show-current)"
  printf 'contract_inventory=%s\n' "$inventory_path"
  printf 'contract_inventory_sha256=%s\n' "$(sha256sum "$inventory_path" | cut -d ' ' -f 1)"
  printf 'git_status_porcelain=\n'
  git status --porcelain
  printf 'platform=\n'
  uname -a
  printf 'flutter_version=\n'
  flutter --version
  printf 'dart_version=\n'
  dart --version
} >"$metadata" 2>&1

run_and_record() {
  local name=$1
  shift
  local log="$output_dir/$name.log"
  local started_ns ended_ns status elapsed_ms test_count command_line

  started_ns=$(date +%s%N)
  set +e
  "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  ended_ns=$(date +%s%N)
  elapsed_ms=$(( (ended_ns - started_ns) / 1000000 ))
  test_count=$(grep -Eo '\+[0-9]+:' "$log" | tail -n 1 | tr -d '+:' || true)
  test_count=${test_count:-unavailable}
  printf -v command_line '%q ' "$@"

  printf 'command=%s\nexit_status=%s\nelapsed_ms=%s\ntest_count=%s\n' \
    "$command_line" "$status" "$elapsed_ms" "$test_count" >"$output_dir/$name.summary"
  return "$status"
}

set -e
analyze_status=0
test_status=0
g1_contract_status=0

run_and_record analyze make analyze || analyze_status=$?
run_and_record test make test || test_status=$?

mapfile -t inventory_test_files < <(
  jq -r \
    '.rows[] | .tests[]? | select(type == "string" and endswith("_test.dart"))' \
    "$inventory_path" | sort -u
)
g1_contract_test_files=()
missing_inventory_test_files=()
for test_file in "${inventory_test_files[@]}"; do
  if [[ -f "$test_file" ]]; then
    g1_contract_test_files+=("$test_file")
  else
    missing_inventory_test_files+=("$test_file")
  fi
done

printf '%s\n' "${g1_contract_test_files[@]}" >"$output_dir/g1-contract-test-files.txt"
printf '%s\n' "${missing_inventory_test_files[@]}" \
  >"$output_dir/g1-contract-missing-test-files.txt"

if ((${#missing_inventory_test_files[@]} != 0)); then
  printf 'Inventory lists missing test files; refusing a partial G1 contract baseline.\n' \
    >"$output_dir/g1-contract.summary"
  g1_contract_status=1
elif ((${#g1_contract_test_files[@]} == 0)); then
  echo 'No existing *_test.dart files were listed by the contract inventory.' \
    >"$output_dir/g1-contract.summary"
  g1_contract_status=1
else
  run_and_record g1-contract flutter test "${g1_contract_test_files[@]}" \
    || g1_contract_status=$?
fi

printf 'analyze_exit_status=%s\ntest_exit_status=%s\ng1_contract_exit_status=%s\n' \
  "$analyze_status" "$test_status" "$g1_contract_status" >"$output_dir/result.summary"

if ((analyze_status != 0 || test_status != 0 || g1_contract_status != 0)); then
  exit 1
fi
