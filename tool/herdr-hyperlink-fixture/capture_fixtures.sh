#!/usr/bin/env bash
# herdr の OSC 8 ハイパーリンク fixture 再取得と再判定（分離環境の podman コンテナ内の herdr が対象）。
#
# Usage:
#   tool/herdr-hyperlink-fixture/capture_fixtures.sh \
#     --container <name> --protocol <17|20|22> --herdr-bin <name-in-container> \
#     --env-dir <dir-in-container> --probe <host-path> --helper <host-path> \
#     --out-dir <host-dir> [--user probe] [--cases ascii,cjk,...]
#
#   --env-dir  : コンテナ内の herdr の API socket（herdr.sock）と client socket（herdr-client.sock）がある
#                ディレクトリ。実行中のサーバーに対して動く（サーバーの起動・停止はしない）。
#   --cases    : 実行するケース（カンマ区切り）。既定は scrollback-up を除く 7 ケース。
#                scrollback-up（スクロールバックの窓を取る前に最下部から 5 行上げておき、往復後の位置を見る）は
#                17/20 では実行できない（17/20 は最下部以外では往復しない契約）。
#
# --protocol は 17|20|22 に限らない任意の番号を受け付けるが、サーバーが名乗る protocol（`herdr status --json` の
# server.protocol）と一致しなければ exit 2 にする。helper と probe が未登録の番号を拒否した場合（usage_error）は、
# そのケースが NG になり FAIL のまま。未登録の新しい番号を判定するには、その番号を allow-list と codec・runner に
# 加えた開発用の helper と probe をビルドして渡す（docs/herdr-caret-helper.md の「herdr 新版への追従」参照）。
#   --probe    : tools/herdr-caret-helper の `cargo build --release --example probe`（musl 静的）の成果物。
#   --helper   : 検証対象の herdr-caret-helper（配布用の helper バイナリなど）。
#   --out-dir  : 出力先。tests/fixtures 配下は拒否する（コミット済み fixture を上書きしない）。
#
# 副作用: コンテナ内に /tmp/fx-work を作り、ケースごとに新しい workspace（label fx-<case>-p<protocol>）
# とその pane を作る。作った workspace・pane・待機中のプロセスは閉じない（削除は利用者が判断する）。
# ホストの herdr と ~/.config/herdr には触れない。
#
# 終了コード: 0 = 全ケース合格、1 = 不合格あり、2 = 使い方の誤り・環境の問題。
set -u -o pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
container="" protocol="" herdr_bin="" env_dir="" probe="" helper="" out_dir=""
cuser="probe"
cases="ascii,cjk,kana,wrap,adjacent,alt,scrollback"
all_cases="ascii cjk kana wrap adjacent alt scrollback scrollback-up"
run_tag=$(date +%s)

usage() { awk 'NR > 1 && /^set -u/ { exit } NR > 1' "${BASH_SOURCE[0]}" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --container) container=$2 ;;
    --protocol) protocol=$2 ;;
    --herdr-bin) herdr_bin=$2 ;;
    --env-dir) env_dir=$2 ;;
    --probe) probe=$2 ;;
    --helper) helper=$2 ;;
    --out-dir) out_dir=$2 ;;
    --user) cuser=$2 ;;
    --cases) cases=$2 ;;
    *) usage ;;
  esac
  shift 2 || usage
done
for v in container protocol herdr_bin env_dir probe helper out_dir; do
  [ -n "${!v}" ] || { echo "missing --${v//_/-}" >&2; usage; }
done
case "$protocol" in
  ''|*[!0-9]*) echo "protocol must be a number (1-255)" >&2; exit 2 ;;
esac
[ "$protocol" -ge 1 ] && [ "$protocol" -le 255 ] || { echo "protocol must be 1-255" >&2; exit 2; }
[ -f "$probe" ] && [ -f "$helper" ] || { echo "probe/helper not found" >&2; exit 2; }
mkdir -p "$out_dir" || exit 2
out_dir=$(cd "$out_dir" && pwd)
case "$out_dir/" in
  */tests/fixtures/*) echo "refusing to write under tests/fixtures: $out_dir" >&2; exit 2 ;;
esac
out="$out_dir/p$protocol"
mkdir -p "$out"

fxj="python3 -I $here/scripts/fx_json.py"
cexec() { podman exec -u "$cuser" -e "HERDR_SOCKET_PATH=$env_dir/herdr.sock" "$container" "$@"; }
hx() { cexec "$herdr_bin" "$@"; }
api="$env_dir/herdr.sock"
client="$env_dir/herdr-client.sock"
fxw=/tmp/fx-work

echo "==> setup ($container, protocol $protocol)"
cexec mkdir -p "$fxw/out" "$fxw/lock" || exit 2
podman cp "$probe" "$container:$fxw/probe" || exit 2
podman cp "$helper" "$container:$fxw/helper" || exit 2
podman cp "$here/scripts/emit_links.sh" "$container:$fxw/emit_links.sh" || exit 2
cexec test -x "$fxw/probe" && cexec test -x "$fxw/helper" || { echo "probe/helper not executable in container" >&2; exit 2; }
helper_sha=$(sha256sum "$helper" | cut -d' ' -f1)
cexec sha256sum "$fxw/helper" | grep -q "^$helper_sha" || { echo "helper sha256 mismatch in container" >&2; exit 2; }
herdr_version=$(hx --version 2>&1 | head -1)
# 名乗っている protocol の照合（既存番号を新版サーバーへ渡して、誤った番号の PASS を記録しないため）。
server_protocol=$(hx status --json 2>/dev/null | $fxj get server.protocol 2>/dev/null)
if [ "$server_protocol" != "$protocol" ]; then
  echo "server protocol mismatch: --protocol $protocol but herdr status --json reports server.protocol=${server_protocol:-unknown}" >&2
  exit 2
fi
echo "server.protocol: $server_protocol"
{ echo "herdr: $herdr_version"; echo "server.protocol: $server_protocol"; echo "helper sha256: $helper_sha"; } > "$out/environment.txt"
echo "herdr: $herdr_version / helper sha256: $helper_sha"

summary="$out/summary.tsv"
printf 'case\tobserve\thyperlinks\tcaret\tscrollback\trestore\toffset_after\twinch_after_observe\twinch_after_scroll\twinch_control\tverdict\n' > "$summary"
overall=0

IFS=',' read -r -a case_list <<< "$cases"
for c in "${case_list[@]}"; do
  case " $all_cases " in *" $c "*) ;; *) echo "unknown case: $c" >&2; exit 2 ;; esac
  case "$protocol" in 17|20) [ "$c" != scrollback-up ] || { echo "scrollback-up is not available for protocol 17/20" >&2; exit 2; } ;; esac
done
for c in "${case_list[@]}"; do
  echo "==> case: $c"
  log="$out/$c"
  tag="$c-$run_tag"
  fail=0
  ws=$(hx workspace create --cwd /home/probe --label "fx-$c-p$protocol" 2>"$log.err") || { echo "workspace create failed" >&2; overall=1; continue; }
  pane=$(printf '%s' "$ws" | $fxj get result.root_pane.pane_id) || { overall=1; continue; }
  hx pane run "$pane" "bash $fxw/emit_links.sh $c $tag $fxw" >/dev/null 2>>"$log.err"
  sleep 2.5
  read -r rows cols < <(cexec cat "$fxw/fx-$tag.size")
  max_off=$(hx pane get "$pane" | $fxj get result.pane.scroll.max_offset_from_bottom)
  off_before=$(hx pane get "$pane" | $fxj get result.pane.scroll.offset_from_bottom)

  # 1. 生フレーム（probe observe --save-raw）
  obs=NG
  if cexec "$fxw/probe" observe --socket "$client" --pane "$pane" --protocol "$protocol" \
       --cols "$cols" --rows "$rows" --timeout-ms 3000 --save-raw "$fxw/out/$c.bin" > "$log.observe.txt" 2>&1; then
    obs=OK
    podman cp "$container:$fxw/out/$c.bin" "$out/$c.bin" 2>>"$log.err"
  fi

  # 2. hyperlinks（通常表示）。終了コード 0 でなければ拒否（render_rejected など）として不合格。
  hl=NG
  if cexec "$fxw/helper" hyperlinks --socket "$client" --pane "$pane" --protocol "$protocol" \
       --cols "$cols" --rows "$rows" --api-socket "$api" --timeout-ms 3000 --max-output-bytes 60000 \
       > "$log.hyperlinks.json" 2> "$log.hyperlinks.err"; then
    if $fxj compare --expected "$here/expected.tsv" --case "$c" --kind visible --cols "$cols" \
         < "$log.hyperlinks.json" > "$log.hyperlinks.compare.txt"; then hl=OK; fi
  else
    cp "$log.hyperlinks.err" "$log.hyperlinks.compare.txt"
  fi

  # 2b. caret（サブコマンド省略）。exit 0 かつ期待位置（expected.tsv の kind=caret）と一致。
  caret=NG
  if cexec "$fxw/helper" --socket "$client" --pane "$pane" --protocol "$protocol" \
       --cols "$cols" --rows "$rows" --timeout-ms 3000 > "$log.caret.json" 2> "$log.caret.err"; then
    if $fxj compare --expected "$here/expected.tsv" --case "$c" --kind caret --cols "$cols" --rows "$rows" \
         < "$log.caret.json" > "$log.caret.compare.txt"; then caret=OK; fi
  else
    cp "$log.caret.err" "$log.caret.compare.txt"
  fi
  sleep 1.5
  winch1=$(cexec cat "$fxw/fx-$tag.winch" | wc -l)

  # 3. scrollback-links（scrollback ケースのみ）
  sb=- restore=- off_after=- winch2=-
  case "$c" in scrollback|scrollback-up)
    sb=NG
    if [ "$c" = scrollback-up ]; then
      # 最下部以外からの往復: 先に 5 行上げ、往復後に同じ位置へ戻る（restore=approximate）ことを見る。
      cexec "$fxw/probe" pane-scroll --api-socket "$api" --pane "$pane" --offset 5 > "$log.prescroll.txt" 2>&1
      off_before=$(hx pane get "$pane" | $fxj get result.pane.scroll.offset_from_bottom)
    fi
    if cexec "$fxw/helper" scrollback-links --api-socket "$api" --socket "$client" --pane "$pane" \
         --protocol "$protocol" --cols "$cols" --window "$max_off" --timeout-ms 1500 \
         --restore-budget-ms 700 --max-output-bytes 60000 --lock-dir "$fxw/lock" \
         > "$log.scrollback.json" 2> "$log.scrollback.err"; then
      if $fxj compare --expected "$here/expected.tsv" --case "$c" --kind scrollback --cols "$cols" \
           < "$log.scrollback.json" > "$log.scrollback.compare.txt"; then sb=OK; fi
      restore=$($fxj get restore < "$log.scrollback.json")
    else
      cp "$log.scrollback.err" "$log.scrollback.compare.txt"
    fi
    off_after=$(hx pane get "$pane" | $fxj get result.pane.scroll.offset_from_bottom)
    sleep 1.5
    winch2=$(cexec cat "$fxw/fx-$tag.winch" | wc -l)
    ;;
  esac

  # SIGWINCH 計数の陽性対照: emit_links.sh 自身へ WINCH を 1 回送り、計数が 1 増えることを見る
  # （herdr による resize の再現ではなく、trap と計数の仕組みが働くことの確認）。
  wc_control=NG
  epid=$(cexec cat "$fxw/fx-$tag.pid")
  before_ctl=$(cexec cat "$fxw/fx-$tag.winch" | wc -l)
  cexec bash -c "kill -WINCH $epid" 2>>"$log.err"
  sleep 1.5
  after_ctl=$(cexec cat "$fxw/fx-$tag.winch" | wc -l)
  [ "$after_ctl" = $((before_ctl + 1)) ] && wc_control=OK

  # 判定。基準は docs/herdr-caret-helper.md「herdr 新版への追従」の合格基準と同じで、緩めない。
  #  拒否 0（hyperlinks・caret・scrollback-links が全て exit 0）、既知リンク範囲・caret 位置との完全一致、
  #  往復後の位置（scrollback: 元が最下部なら 0 に戻り restore=exact。scrollback-up（17/20 以外）: 元の 5 に戻り
  #  restore=approximate。最下部以外から往復するケースは scrollback-up だけ）、観測での SIGWINCH 0 回
  #  （scrollback-links 後の SIGWINCH は 17/20 以外は 0 回が必須、17/20 は attach 由来のため記録のみ）、SIGWINCH 計数の陽性対照。
  [ "$obs" = OK ] && [ "$hl" = OK ] && [ "$caret" = OK ] && [ "$wc_control" = OK ] || fail=1
  [ "$winch1" = 0 ] || fail=1
  case "$c" in
    scrollback)
      [ "$sb" = OK ] && [ "$restore" = exact ] && [ "$off_before" = 0 ] && [ "$off_after" = 0 ] || fail=1 ;;
    scrollback-up)
      [ "$sb" = OK ] && [ "$restore" = approximate ] && [ "$off_before" = 5 ] && [ "$off_after" = "$off_before" ] || fail=1 ;;
  esac
  case "$c" in scrollback|scrollback-up) case "$protocol" in 17|20) ;; *) [ "$winch2" = 0 ] || fail=1 ;; esac ;; esac
  verdict=PASS; [ "$fail" = 0 ] || { verdict=FAIL; overall=1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$obs" "$hl" "$caret" "$sb" "$restore" "$off_after" "$winch1" "$winch2" "$wc_control" "$verdict" >> "$summary"

  # 4. meta
  {
    echo "# $c.bin (protocol $protocol)"
    echo
    echo "capture_fixtures.sh で採取した生バイト列（probe observe --save-raw、エスケープ加工なし）。"
    echo
    echo "- 採取元: $container（$herdr_version、server.protocol=$server_protocol）"
    echo "- pane: $pane（ケース $c、emit_links.sh 実行直後）"
    echo "- observe: cols=$cols rows=$rows（pane 内の stty size で実寸を確認してから指定。リサイズ操作なし）"
    echo "- helper sha256: $helper_sha"
    echo "- pane.get: offset_from_bottom=$off_before max_offset_from_bottom=$max_off"
    [ -f "$out/$c.bin" ] && echo "- sha256: $(sha256sum "$out/$c.bin" | cut -d' ' -f1)"
    echo "- 期待値: expected.tsv のケース $c（C=$cols）。判定: $verdict"
    echo "- 採取コマンド: probe observe --socket $client --pane $pane --protocol $protocol --cols $cols --rows $rows --save-raw <path>"
  } > "$out/$c.meta.md"
done

echo
echo "==> summary ($summary)"
column -t -s $'\t' "$summary" 2>/dev/null || cat "$summary"
if [ "$overall" = 0 ]; then echo "RESULT: PASS (protocol $protocol)"; else echo "RESULT: FAIL (protocol $protocol)"; fi
exit "$overall"
