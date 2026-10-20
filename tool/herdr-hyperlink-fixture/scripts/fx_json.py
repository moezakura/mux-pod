#!/usr/bin/env python3
"""capture_fixtures.sh 用の小さな JSON ヘルパー（標準ライブラリのみ）。

  fx_json.py get <dotted.path>            stdin の JSON から値を取り出して表示する
  fx_json.py compare --expected <tsv> --case <name> --kind <visible|scrollback> --cols <n>
                     [--rows <n>]  stdin の helper 出力と expected.tsv を完全一致で比較する（kind に caret も指定できる）

compare の終了コード: 0 = 完全一致、1 = 不一致、2 = 入力エラー。
"""
import json
import re
import sys


def get(path):
    value = json.load(sys.stdin)
    for key in path.split("."):
        value = value[int(key)] if isinstance(value, list) else value[key]
    print(json.dumps(value) if isinstance(value, (dict, list)) else value)


def expr(text, cols, rows=0):
    if not re.fullmatch(r"[0-9CR+\-*() ]+", text):
        raise ValueError(f"unsafe expression: {text!r}")
    return int(eval(text, {"__builtins__": {}}, {"C": cols, "R": rows}))


def expected_set(path, case, kind, cols, rows=0):
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c, k, url, row, start, end = line.split("\t")
            if c == case and k == kind:
                out.add((url, expr(row, cols, rows), expr(start, cols, rows), expr(end, cols, rows)))
    return out


def actual_set(doc, kind):
    if kind == "caret":
        cur = doc["cursor"]
        if cur is None:
            return set()
        return {("-", cur["y"], cur["x"], 1 if cur["visible"] else 0)}
    if kind == "visible":
        links = doc["links"]
        truncated = doc.get("truncated", False)
    else:
        windows = doc["windows"]
        if len(windows) != 1:
            raise ValueError(f"expected exactly 1 window, got {len(windows)}")
        links = windows[0]["links"]
        truncated = windows[0].get("truncated", False)
    if truncated:
        raise ValueError("output truncated")
    out = set()
    for link in links:
        for row, start, end in link["ranges"]:
            out.add((link["url"], row, start, end))
    return out


def compare(argv):
    opts = {}
    it = iter(argv)
    for name in it:
        opts[name] = next(it)
    try:
        cols = int(opts["--cols"])
        want = expected_set(opts["--expected"], opts["--case"], opts["--kind"], cols, int(opts.get("--rows", 0)))
        got = actual_set(json.load(sys.stdin), opts["--kind"])
    except (KeyError, ValueError, json.JSONDecodeError) as e:
        print(f"INPUT_ERROR {e}")
        sys.exit(2)
    missing = sorted(want - got)
    extra = sorted(got - want)
    print(f"expected={len(want)} actual={len(got)} missing={len(missing)} unexpected={len(extra)}")
    for m in missing:
        print(f"  MISSING {m}")
    for x in extra:
        print(f"  UNEXPECTED {x}")
    sys.exit(0 if not missing and not extra else 1)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "get":
        get(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "compare":
        compare(sys.argv[2:])
    else:
        print(__doc__)
        sys.exit(2)
