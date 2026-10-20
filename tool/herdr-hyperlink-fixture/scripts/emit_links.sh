#!/bin/bash
# コンテナ内の対象 pane で実行する。既知の OSC 8 リンクを 1 ケース分だけ出して待機する。
# Usage: emit_links.sh <case> [tag] [work-dir]
#   tag: 出力ファイル名に使う識別子（既定は case。実行ごとに変えると前回の待機プロセスと混ざらない）
#   case: ascii | cjk | kana | wrap | adjacent | alt | scrollback | scrollback-up
# 副作用: <work-dir>/fx-<tag>.size に "rows cols"、fx-<tag>.winch に SIGWINCH 1 回ごとに 1 行、fx-<tag>.pid に自分の PID を書く。
# 終了は Ctrl-C（INT）。alt スクリーンのケースは終了時に通常スクリーンへ戻す。
case_name=${1:?case required}
tag=${2:-$case_name}
work=${3:-/tmp/fx-work}
read -r ROWS COLS < <(stty size)
echo "$ROWS $COLS" > "$work/fx-$tag.size"
echo $$ > "$work/fx-$tag.pid"
: > "$work/fx-$tag.winch"
trap 'echo w >> "$work/fx-$tag.winch"' WINCH
trap '[ "$case_name" = alt ] && printf "\033[?1049l"; exit 0' INT TERM

link() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

clear
case "$case_name" in
  ascii) link https://example.com/fx-ascii ASCII-LINK; printf ' plain\n' ;;
  cjk) link https://example.com/fx-cjk 日本語リンク; printf ' end\n' ;;
  kana) link https://example.com/fx-kana ｶﾞｷﾞｸﾞ; printf ' end\n' ;;
  wrap)
    text=$(printf 'w%.0s' $(seq 1 $((COLS + 20))))
    link https://example.com/fx-wrap "$text"; printf '\n' ;;
  adjacent) link https://example.com/fx-adj-a AAA; link https://example.com/fx-adj-b BBBB; printf '\n' ;;
  alt)
    printf '\033[?1049h'; clear
    link https://example.com/fx-alt ALT-LINK; printf '\n' ;;
  scrollback|scrollback-up)
    link https://example.com/fx-scroll SCROLL-LINK; printf '\n'
    seq 1 $((ROWS + 30)) ;;
  *) echo "unknown case: $case_name" >&2; exit 2 ;;
esac
while :; do sleep 1; done
