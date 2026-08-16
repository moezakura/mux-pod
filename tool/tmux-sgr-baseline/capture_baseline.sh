#!/usr/bin/env bash
# Captures the SGR passthrough / copy-mode / concatenated-send baseline (B1-B4)
# for the scroll-send feature (PaneCapabilities.wheelSend flip gate, D11).
#
# Reference: tool/herdr-baseline/capture_baseline.sh (structure only).
# Scope: B1-B4 are measured here. B5 (1-finger drag vs 2-finger pinch gesture
# arena) is intentionally NOT scriptable and is covered by widget tests /
# on-device checks (Implementation Plan Phase 0 #4).
#
# Each B result is recorded as PASS / FAIL / SKIPPED(未実施) / OBSERVED.
# Missing tools or an unreachable herdr server are recorded as SKIPPED, never
# as a hard failure (the wheelSend flip stays false under D11 until measured).
#
# Usage: tool/tmux-sgr-baseline/capture_baseline.sh [output-directory]
set -u -o pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root" || exit 1

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [output-directory]" >&2
  exit 64
fi

run_id=$(date -u +%Y%m%dT%H%M%SZ)
output_dir=${1:-"tool/tmux-sgr-baseline/results/$run_id"}
# Absolute-path the output dir: `tmux pipe-pane` runs its command in the tmux
# server's cwd, so relative paths would not resolve to this checkout.
case "$output_dir" in
  /*) ;;
  *) output_dir="$repo_root/$output_dir" ;;
esac
if [[ -e "$output_dir" ]]; then
  echo "Refusing to overwrite existing output directory: $output_dir" >&2
  exit 73
fi
mkdir -p "$output_dir"

# --- metadata (Open Questions #5: reproduce the measurement environment) ---
metadata="$output_dir/metadata.txt"
{
  printf 'captured_at_utc=%s\n' "$(date -u +%FT%TZ)"
  printf 'git_commit=%s\n' "$(git rev-parse HEAD)"
  printf 'git_branch=%s\n' "$(git branch --show-current)"
  printf 'git_status_porcelain=\n'
  git status --porcelain
  printf 'platform=\n'
  uname -a
  printf 'tmux_version=\n'
  if command -v tmux >/dev/null; then tmux -V; else echo '(tmux not found)'; fi
  printf 'herdr_version=\n'
  if command -v herdr >/dev/null; then herdr --version 2>&1; else echo '(herdr not found)'; fi
  printf 'flutter_version=\n'
  flutter --version 2>/dev/null | head -n 1 || echo '(flutter not found)'
  printf 'dart_version=\n'
  dart --version 2>&1 || echo '(dart not found)'
} >"$metadata" 2>&1

# --- result recording -------------------------------------------------------
record() {
  # usage: record <KEY> <PASS|FAIL|SKIPPED|OBSERVED> <detail>
  local key=$1 result=$2 detail=$3
  printf '%s=%s\n' "$key" "$result" >>"$output_dir/result.summary"
  printf '%-12s %-8s %s\n' "$key" "$result" "$detail" | tee -a "$output_dir/summary.log"
}

# hex (no whitespace) of the byte stream read by a receiver pane
hex_of() {
  # "$1" が実在ファイルなら読み、`-`（stdin）ならパイプから読む
  if [[ -n "${1:-}" && "$1" != "-" && -e "$1" ]]; then
    tr -d ' \n' <"$1"
  else
    tr -d ' \n'
  fi
}

# start a raw `cat` receiver whose output is piped to a file.
# The pane runs fish; we type `stty raw -echo; cat` into it (Enter confirms the
# command) so `cat` owns the pane tty in raw mode - exactly like a TUI app
# (vim/less) would. `tmux pipe-pane` then records every byte cat echoes, which
# is how SGR passthrough is verified byte-for-byte.
start_receiver() {
  local session=$1 out=$2
  tmux new-session -d -s "$session" -x 80 -y 24
  tmux pipe-pane -t "$session" "cat > '$out'"
  sleep 0.5
  tmux send-keys -t "$session" 'stty raw -echo; cat' Enter
  sleep 0.5
}

stop_receiver() {
  local session=$1 out=$2
  tmux pipe-pane -t "$session" -o 2>/dev/null || tmux pipe-pane -t "$session" || true
  tmux kill-session -t "$session" 2>/dev/null || true
}

# true if <file> contains the exact byte sequence <payload> (binary-safe)
contains_bytes() {
  local payload=$1 file=$2
  grep -aqF "$payload" "$file"
}

# --- B1: tmux `send-keys -l` SGR passthrough -------------------------------
# Send ESC[<64;1;1M (SGR 1006 wheel-up) with send-keys -l to a pane running
# `od -An -tx1 > file`, then compare the received hex with the expected bytes.
run_b1() {
  if ! command -v tmux >/dev/null; then
    record B1_RESULT SKIPPED 'tmux not found'
    return
  fi
  local session="sgr-b1-$$"
  local out="$output_dir/b1-receiver.out"
  local payload expected_hex actual_hex
  payload=$'\x1b[<64;1;1M'
  start_receiver "$session" "$out"
  tmux send-keys -l -t "$session" "$payload"
  sleep 0.5
  stop_receiver "$session" "$out"
  expected_hex=$(printf '%s' "$payload" | od -An -tx1 | hex_of -)
  actual_hex=$(hex_of "$out")
  {
    printf 'expected=%s\n' "$expected_hex"
    printf 'received=%s\n' "$actual_hex"
  } >"$output_dir/b1.log"
  if contains_bytes "$payload" "$out"; then
    record B1_RESULT PASS "send-keys -l SGR passthrough (receiver bytes contain $expected_hex)"
  else
    record B1_RESULT FAIL "SGR not passed through literally (received '$actual_hex')"
  fi
}

# --- B4: concatenated send (8 ticks in a single command) -------------------
# Send 8 concatenated SGR wheel-up sequences in one send-keys -l and verify the
# receiver gets all 8 sequences (coalescing validity, D6).
run_b4() {
  if ! command -v tmux >/dev/null; then
    record B4_RESULT SKIPPED 'tmux not found'
    return
  fi
  local session="sgr-b4-$$"
  local out="$output_dir/b4-receiver.out"
  local payload expected_hex actual_hex
  payload=$'\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M\x1b[<64;1;1M'
  start_receiver "$session" "$out"
  tmux send-keys -l -t "$session" "$payload"
  sleep 0.5
  stop_receiver "$session" "$out"
  expected_hex=$(printf '%s' "$payload" | od -An -tx1 | hex_of -)
  actual_hex=$(hex_of "$out")
  {
    printf 'expected_8x=%s\n' "$expected_hex"
    printf 'received=%s\n' "$actual_hex"
  } >"$output_dir/b4.log"
  if contains_bytes "$payload" "$out"; then
    record B4_RESULT PASS "8x concatenated SGR passthrough (receiver bytes contain $expected_hex)"
  else
    record B4_RESULT FAIL "concatenated SGR not passed through literally (received '$actual_hex')"
  fi
}

# --- B3: copy-mode behavior while sending SGR ------------------------------
# Enter tmux copy-mode, send SGR, then observe whether the leading ESC cancels
# copy-mode and the remainder becomes input garbage (R1 validation). The result
# is recorded as OBSERVED (version-dependent fact, not a pass/fail gate).
run_b3() {
  if ! command -v tmux >/dev/null; then
    record B3_RESULT SKIPPED 'tmux not found'
    return
  fi
  local session="sgr-b3-$$"
  local out="$output_dir/b3-receiver.out"
  local mode_before mode_after actual_hex payload send_status
  payload=$'\x1b[<64;1;1M'
  start_receiver "$session" "$out"
  tmux copy-mode -t "$session"
  mode_before=$(tmux display-message -t "$session" -p '#{pane_in_mode}' 2>/dev/null)
  tmux send-keys -l -t "$session" "$payload" 2>/dev/null
  send_status=$?
  sleep 0.5
  mode_after=$(tmux display-message -t "$session" -p '#{pane_in_mode}' 2>/dev/null)
  stop_receiver "$session" "$out"
  actual_hex=$(hex_of "$out")
  {
    printf 'pane_in_mode_before=%s\n' "$mode_before"
    printf 'pane_in_mode_after=%s\n' "$mode_after"
    printf 'send_keys_exit_status=%s\n' "$send_status"
    printf 'receiver_hex=%s\n' "$actual_hex"
  } >"$output_dir/b3.log"
  if contains_bytes "$payload" "$out"; then
    record B3_RESULT OBSERVED "garbage reached receiver (mode $mode_before -> $mode_after, send exit $send_status, hex $actual_hex)"
  else
    record B3_RESULT OBSERVED "no garbage reached receiver; ESC cancelled copy-mode and send-keys aborted (mode $mode_before -> $mode_after, send exit $send_status)"
  fi
}

# --- B2: herdr `send-text` SGR passthrough ---------------------------------
# Creates a dedicated throwaway workspace (never injects bytes into real user
# panes), starts an `od -An -tx1` receiver inside the pane via send-text
# (stdin stays attached to the pane's tty, unlike `pane run` which closes it),
# sends SGR bytes, and confirms the received hex via `pane read`. A plain-text
# send additionally covers the (b) character-key sendText check (L0-a #6).
run_b2() {
  if ! command -v herdr >/dev/null; then
    record B2_RESULT SKIPPED 'herdr CLI not found'
    return
  fi
  if ! command -v jq >/dev/null; then
    record B2_RESULT SKIPPED 'jq not found (needed to parse herdr JSON)'
    return
  fi
  # Server reachability probe (workspace list must not fail).
  if ! herdr workspace list >/dev/null 2>&1; then
    record B2_RESULT SKIPPED 'herdr server unreachable (workspace list failed)'
    return
  fi

  local ws_out ws_id pane_id sgr plain log read_out sgr_status plain_status
  ws_out=$(herdr workspace create --label sgr-baseline 2>&1)
  ws_id=$(printf '%s' "$ws_out" | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)
  pane_id=$(printf '%s' "$ws_out" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null)
  if [[ -z "$ws_id" || -z "$pane_id" ]]; then
    record B2_RESULT SKIPPED "workspace create returned no id (output: ${ws_out:0:120}...)"
    return
  fi

  sgr="$(printf '\033[<64;1;1M')"
  plain="hello-sgr-baseline"
  log="$output_dir/b2.log"
  {
    printf 'workspace=%s\npane=%s\n' "$ws_id" "$pane_id"
    # Start the raw receiver inside the pane (stdin stays on the pane tty).
    printf 'start_receiver:\n'
    herdr pane send-text "$pane_id" "stty raw -echo; od -An -tx1"$'\r' 2>&1
    printf 'start_exit_status=%s\n' "$?"
    sleep 2
    printf 'send_text_sgr:\n'
    herdr pane send-text "$pane_id" "$sgr" 2>&1
    printf 'sgr_exit_status=%s\n' "$?"
    sleep 1
    printf 'send_text_plain:\n'
    herdr pane send-text "$pane_id" "$plain" 2>&1
    printf 'plain_exit_status=%s\n' "$?"
    sleep 1
    printf 'pane_read:\n'
    herdr pane read "$pane_id" 2>&1
  } >"$log"

  # Cleanup (must not leak the throwaway workspace even on failure).
  herdr workspace close "$ws_id" >/dev/null 2>&1 || true

  read_out=$(cat "$log")
  sgr_status=$(sed -n 's/^sgr_exit_status=//p' "$log")
  plain_status=$(sed -n 's/^plain_exit_status=//p' "$log")
  # od prints the received SGR as "1b 5b 3c 36 34 3b 31 3b 31 4d" on the pane.
  if [[ "$sgr_status" == 0 && "$plain_status" == 0 ]] &&
    printf '%s' "$read_out" | grep -qF '1b 5b 3c 36 34'; then
    record B2_RESULT PASS "herdr send-text passed SGR through (od hex seen in pane read)"
  else
    record B2_RESULT FAIL "herdr send-text SGR not confirmed (sgr=$sgr_status plain=$plain_status)"
  fi
}

# --- main ------------------------------------------------------------------
run_b1
run_b4
run_b3
run_b2

{
  printf 'captured_at_utc=%s\n' "$(date -u +%FT%TZ)"
  printf 'output_dir=%s\n' "$output_dir"
} >>"$metadata"

cat "$output_dir/result.summary"
echo "Report: $output_dir"
