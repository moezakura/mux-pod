#!/usr/bin/env python3
"""G0 inventory checker.

Reads the JSON ledger and the source tree under REPO.
Verifies:
- Ledger schema and row ID uniqueness.
- Every public row has at least one consumer, one test, or a non-null unverifiedReason.
- Every ledger row in the G0 file set has a corresponding // inventory: <rowId>
  comment in its sourceFile and the comment is followed by a non-comment line.
- Every // inventory: <rowId> comment in the G0 file set maps to a ledger row
  with the same sourceFile.
- Consumers and tests arrays are consistent with the source/test files
  (mechanical extraction is reported even when no explicit list is given).
- Warns about potentially missing public symbols (non-fatal).

Writes tool/herdr-inventory/check-report-G0.json.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
G0_FILE_SET = {
    'lib/services/tmux/tmux_commands.dart',
    'lib/services/tmux/tmux_parser.dart',
    'lib/providers/tmux_provider.dart',
    'lib/providers/active_session_provider.dart',
    'lib/providers/terminal_display_provider.dart',
    'lib/services/ssh/ssh_client.dart',
    'lib/services/ssh/persistent_shell.dart',
    'lib/screens/terminal/terminal_screen.dart',
    'lib/providers/notification_panes_provider.dart',
    'lib/services/deep_link/deep_link_service.dart',
    'lib/providers/file_browser_provider.dart',
}

REQUIRED_FIELDS = {
    'id', 'name', 'sourceFile', 'line', 'public', 'symbolType', 'signature',
    'contract', 'characterization', 'failureMode', 'sideEffects', 'consumers',
    'tests', 'searchTokens',
}

REPORT_PATH = REPO / 'tool/herdr-inventory/check-report-G0.json'


def load_ledger(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def is_dart(path):
    return path.suffix == '.dart'


def load_texts(root, glob, cache=None):
    cache = cache or {}
    for p in (REPO / root).rglob(glob):
        if p.is_file():
            cache[str(p.relative_to(REPO))] = p.read_text(encoding='utf-8')
    return cache


def token_found(file_rel, r, caches):
    fp = REPO / file_rel
    if not fp.exists():
        return False
    cache = caches.get(file_rel)
    if cache is None:
        cache = fp.read_text(encoding='utf-8')
        caches[file_rel] = cache
    text = cache
    for tok in r.get('searchTokens', []):
        if not tok:
            continue
        if tok.isidentifier():
            pat = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(tok) + r'(?![A-Za-z0-9_])')
        else:
            pat = re.compile(re.escape(tok))
        if pat.search(text):
            return True
    return False


def find_next_code(lines, start_idx):
    for j in range(start_idx, len(lines)):
        nxt = lines[j].strip()
        if nxt and not nxt.startswith('//') and not nxt.startswith('*'):
            return j + 1
    return None


def extract_public_symbols(text):
    """Best-effort extraction of public top-level or member symbols.
    Returns a list of dicts with file, kind, name, line.
    """
    syms = []
    lines = text.splitlines()
    for i, line in enumerate(lines, start=1):
        s = line.strip()
        if not s or s.startswith('//') or s.startswith('*'):
            continue
        # top-level class / enum / extension / typedef
        m = re.match(r'^(?:abstract\s+|final\s+)?(?:class|enum|extension)\s+(\w+)', s)
        if m and not m.group(1).startswith('_'):
            syms.append({'line': i, 'kind': 'class/enum/extension', 'name': m.group(1)})
            continue
        m = re.match(r'^typedef\s+(?:[\w<>,\[\] ]+\s+)?(\w+)', s)
        if m and not m.group(1).startswith('_'):
            syms.append({'line': i, 'kind': 'typedef', 'name': m.group(1)})
            continue
        # providers: final Type name = ... or final name = Provider...
        m = re.match(r'^final\s+(?:[\w<>\[\]\(\),.? ]+\s+)?(\w+Provider)\s*=', s)
        if m:
            syms.append({'line': i, 'kind': 'provider', 'name': m.group(1)})
            continue
        # public methods / getters / fields:  <type>[<...>] [get] <name> ( / => / = / ;
        m = re.match(
            r'^(?:@\w+\s+)*([\w<>\[\]\(\),.? ]+?)\s+(?:[A-Za-z_]\w*\s*\.\s*)?([A-Za-z_]\w*)\s*(?:\(|=>|;)',
            s,
        )
        if m:
            pre = m.group(1).strip()
            name = m.group(2)
            if not name.startswith('_'):
                # avoid obvious calls like `return foo(...)` or `if (cond) bar()`
                first = re.match(r'([A-Za-z_]\w*)', pre)
                if first and first.group(1) not in {
                    'return', 'await', 'if', 'else', 'for', 'while', 'switch', 'case',
                    'assert', 'throw', 'catch', 'break', 'continue',
                }:
                    syms.append({'line': i, 'kind': 'method/getter/field', 'name': name})
    return syms


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <ledger.json>', file=sys.stderr)
        sys.exit(2)

    ledger_path = Path(sys.argv[1])
    if not ledger_path.exists():
        print(f'Ledger not found: {ledger_path}', file=sys.stderr)
        sys.exit(1)

    data = load_ledger(ledger_path)
    rows = data.get('rows', [])
    issues = []
    warnings = []
    mechanical = []

    # Schema and uniqueness
    seen_ids = set()
    for i, row in enumerate(rows):
        missing = REQUIRED_FIELDS - set(row.keys())
        if missing:
            issues.append(f'schema error row {i}: missing {sorted(missing)}')
        if row['id'] in seen_ids:
            issues.append(f'duplicate id: {row["id"]}')
        seen_ids.add(row['id'])

    id_to_row = {r['id']: r for r in rows}
    rows_by_file = {r['sourceFile']: r for r in rows}

    # Public row coverage
    unconsumed = []
    for r in rows:
        if r.get('public'):
            covered = r.get('consumers') or r.get('tests') or r.get('unverifiedReason') or r.get('nextTest')
            if not covered:
                issues.append(f'unconsumed public row {r["id"]}: {r["name"]}')
            elif not r.get('consumers') and not r.get('tests'):
                unconsumed.append(r['id'])

    # Scan G0 file set for inventory comments and ensure every ledger row has one
    comments_by_file = {}
    for fpath in G0_FILE_SET:
        p = REPO / fpath
        if not p.exists():
            issues.append(f'source file missing: {fpath}')
            continue

        text = p.read_text(encoding='utf-8')
        lines = text.splitlines()
        seen_in_file = set()

        for i, line in enumerate(lines, start=1):
            m = re.search(r'// inventory:\s*([A-Z]+(?:-[A-Z]+)?-\d+)', line)
            if not m:
                continue
            rid = m.group(1)
            if rid in seen_in_file:
                issues.append(f'duplicate inventory comment {rid} in {fpath}:{i}')
                continue
            seen_in_file.add(rid)
            def_line = find_next_code(lines, i)
            if def_line is None:
                issues.append(f'no code line after inventory comment {rid} in {fpath}:{i}')
                continue
            if rid not in id_to_row:
                issues.append(f'unknown inventory id {rid} in {fpath}:{i}')
                continue
            r = id_to_row[rid]
            if r['sourceFile'] != fpath:
                issues.append(f'id {rid} comment in {fpath} but ledger sourceFile is {r["sourceFile"]}')
                continue
            if r.get('line') and abs(r['line'] - def_line) > 50:
                warnings.append(
                    f'line number mismatch for {rid}: ledger {r["line"]} vs definition {def_line}'
                )
            comments_by_file.setdefault(fpath, {})[rid] = i

    for fpath in G0_FILE_SET:
        file_rows = [r for r in rows if r['sourceFile'] == fpath]
        file_comments = comments_by_file.get(fpath, {})
        for r in file_rows:
            if r['id'] not in file_comments:
                issues.append(f'missing inventory comment for {r["id"]} in {fpath}')

    # Caches for consumer/test verification
    lib_texts = load_texts('lib', '*.dart')
    test_texts = load_texts('test', '*.dart')
    extra_texts = {}  # lazily loaded for tool/docs consumers

    # Consumers/tests consistency
    for r in rows:
        if not r.get('sourceFile') or r.get('unverifiedReason'):
            continue

        for consumer in r.get('consumers', []):
            if consumer.startswith('lib/') or consumer.startswith('test/'):
                cache = lib_texts if consumer.startswith('lib/') else test_texts
                if not token_found(consumer, r, cache):
                    issues.append(f'consumer {consumer} listed for {r["id"]} but no search token found')
            else:
                if not token_found(consumer, r, extra_texts):
                    issues.append(f'consumer {consumer} listed for {r["id"]} but no search token found')

        for test in r.get('tests', []):
            if not token_found(test, r, test_texts):
                issues.append(f'test {test} listed for {r["id"]} but no search token found')

    # Mechanical consumer / test extraction
    all_texts = {}
    all_texts.update(lib_texts)
    all_texts.update(test_texts)
    for r in rows:
        if not r.get('sourceFile'):
            continue
        expected_consumers = []
        for file_rel, text in all_texts.items():
            if file_rel == r['sourceFile']:
                continue
            if token_found(file_rel, r, {file_rel: text}):
                expected_consumers.append(file_rel)
        expected_tests = [f for f in expected_consumers if f.startswith('test/')]
        expected_consumers = [f for f in expected_consumers if not f.startswith('test/')]
        mechanical.append({
            'id': r['id'],
            'name': r['name'],
            'mechanical_consumers': expected_consumers,
            'mechanical_tests': expected_tests,
        })

    # Public symbol extraction (warnings only)
    for fpath in G0_FILE_SET:
        p = REPO / fpath
        if not p.exists():
            continue
        text = p.read_text(encoding='utf-8')
        ledger_names = {
            r['name'] for r in rows if r['sourceFile'] == fpath
        }
        for sym in extract_public_symbols(text):
            if sym['name'] not in ledger_names:
                warnings.append(
                    f'possibly missing public symbol {sym["name"]} ({sym["kind"]}) at {fpath}:{sym["line"]}'
                )

    # Write report
    report = {
        'status': 'FAIL' if issues else 'PASS',
        'ledger': str(ledger_path),
        'row_count': len(rows),
        'public_row_count': sum(1 for r in rows if r.get('public')),
        'unconsumed_public_rows': unconsumed,
        'issues': issues,
        'warnings': warnings,
        'mechanical_extraction': mechanical,
    }
    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    if issues:
        print('Inventory check FAILED')
        for issue in issues:
            print(f'  - {issue}')
        sys.exit(1)
    else:
        print('Inventory check PASSED')
        print(f'  rows: {len(rows)}')
        print(f'  public rows with unverifiedReason: {len(unconsumed)}')
        print(f'  warnings: {len(warnings)}')
        print(f'  report: {REPORT_PATH}')
        sys.exit(0)


if __name__ == '__main__':
    main()
