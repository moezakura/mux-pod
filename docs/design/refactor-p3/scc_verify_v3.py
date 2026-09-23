#!/usr/bin/env python3
"""P3 design v3: SCC verification of lib/screens import graph before/after fix.

Builds the real import graph from lib/**.dart, then applies the v3 virtual
transformations (new neutral modules, removed home inverse edges) and runs
Tarjan SCC. Prints edge lists and SCC results for:
  - PRE : as-is HEAD
  - POST: after v3 fix (home inverse edges removed, neutral modules added)
RB: only reads files; writes nothing to the repo.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path("/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines")
LIB = ROOT / "lib"

IMPORT_RE = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]\s*;", re.M)


def resolve_import(src: Path, imp: str) -> Path | None:
    if imp.startswith("package:"):
        rest = imp[len("package:") :]
        _, _, path = rest.partition("/")
        if not path:
            return None
        c = LIB / path
        return c if c.exists() else None
    if imp.startswith("dart:"):
        return None
    c = (src.parent / imp).resolve()
    return c if c.exists() else None


def real_edges() -> dict[str, set[str]]:
    edges: dict[str, set[str]] = {}
    for f in sorted(p for p in LIB.rglob("*.dart") if not p.name.endswith(".g.dart")):
        rel = str(f.relative_to(LIB))
        edges.setdefault(rel, set())
        text = f.read_text(encoding="utf-8")
        for m in IMPORT_RE.finditer(text):
            tgt = resolve_import(f, m.group(1))
            if tgt is not None and str(tgt.relative_to(LIB)) != rel:
                edges[rel].add(str(tgt.relative_to(LIB)))
    return edges


def tarjan(edges: dict[str, set[str]]):
    index = 0
    stack, onstack = [], set()
    idx, low = {}, {}
    sccs = []

    def strongconnect(v):
        nonlocal index
        idx[v] = low[v] = index
        index += 1
        stack.append(v)
        onstack.add(v)
        for w in edges.get(v, set()):
            if w not in edges:
                continue
            if w not in idx:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif w in onstack:
                low[v] = min(low[v], idx[w])
        if low[v] == idx[v]:
            comp = []
            while True:
                w = stack.pop()
                onstack.remove(w)
                comp.append(w)
                if w == v:
                    break
            sccs.append(comp)

    for v in edges:
        if v not in idx:
            strongconnect(v)
    return sccs


def print_edges(edges, scope="screens", comment=""):
    print(f"--- import edges (scope={scope}) {comment}")
    for s in sorted(edges):
        if scope == "screens" and "screens/" not in s:
            continue
        for t in sorted(edges[s]):
            if scope == "screens" and "screens/" not in t:
                continue
            print(f"  {s} -> {t}")
    print()


def report(edges, scope, label):
    print(f"=== {label} ===")
    sccs = tarjan(edges)
    big = sorted([c for c in sccs if len(c) >= 2], key=len, reverse=True)
    if not big:
        print("  SCC size>=2: NONE (acyclic within scope)")
    for c in big:
        if scope == "screens" and not all("screens/" in x for x in c):
            continue
        print(f"  size={len(c)}: {', '.join(sorted(c))}")
    print()


def main():
    edges = real_edges()

    # ---- PRE: as-is HEAD ----
    print("############ PRE (HEAD, as-is) ############")
    print_edges(edges, scope="screens", comment="")
    report(edges, scope="screens", label="PRE SCC (lib-wide, size>=2)")

    # ---- POST: v3 design ----
    # Virtual nodes (future files, no outgoing edges -> cannot form cycle)
    NAV = "navigation/current_tab_provider.dart"
    MD_KEYS = "screens/file_browser/markdown_scroll_keys.dart"
    post = {k: set(v) for k, v in edges.items()}
    post.setdefault(NAV, set())
    post.setdefault(MD_KEYS, set())

    # A. Remove home inverse edges (3): connections/keys/settings_search_field -> home_screen
    home = "screens/home_screen.dart"
    for src in ["screens/connections/connections_screen.dart",
                "screens/keys/keys_screen.dart",
                "screens/settings/widgets/settings_search_field.dart"]:
        post[src].discard(home)
        # B. re-target these to the neutral module (direct import)
        post[src].add(NAV)

    # home_screen shim re-exports the neutral module (export edge, not import;
    # no reverse edge). home_screen shim -> home impl handled by P3 v3 files:
    # home_screen.dart(shim) -> home/home_screen.dart(impl) is import edge.
    post.setdefault("screens/home/home_screen.dart", set())
    post.setdefault("screens/home/widgets/home_bottom_nav_bar.dart", set())
    post[home].add("screens/home/home_screen.dart")
    post["screens/home/home_screen.dart"].add(NAV)          # HomeScreen watches neutral provider
    post["screens/home/home_screen.dart"].add("screens/home/widgets/home_bottom_nav_bar.dart")

    # C. markdown v3: split screen(impl), body, code_block; body references neutral MD_KEYS only.
    md_screen = "screens/file_browser/markdown_preview/markdown_preview_screen.dart"
    md_body = "screens/file_browser/markdown_preview/markdown_preview_body.dart"
    md_code = "screens/file_browser/markdown_preview/markdown_code_block.dart"
    post.setdefault(md_screen, set())
    post.setdefault(md_body, set())
    post.setdefault(md_code, set())
    # implement screen imports body (one-way only)
    post[md_screen].add(md_body)
    # body references ONLY neutral keys file (not the screen impl) -> no reverse edge
    post[md_body].add(MD_KEYS)
    # code_block is standalone (no cycle)
    # shim file (file_browser/markdown_preview_screen.dart) exports md_screen + md_code;
    # it imports the impl to re-export.
    post["screens/file_browser/markdown_preview_screen.dart"].add(md_screen)
    post["screens/file_browser/markdown_preview_screen.dart"].add(md_code)

    print("\n\n############ POST (v3 design) ############")
    print_edges(post, scope="screens", comment="")
    report(post, scope="screens", label="POST SCC (lib-wide /*screens*/ size>=2)")

    # full-lib residual SCCs (known/out-of-scope)
    print("=== POST full-lib SCC size>=2 (out-of-scope remnants) ===")
    for c in sorted(tarjan(post), key=lambda x: -len(x)):
        if len(c) >= 2 and not all("screens/" in x for x in c):
            print(f"  size={len(c)}: {', '.join(sorted(c))}")


if __name__ == "__main__":
    main()