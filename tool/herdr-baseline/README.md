# Herdr baseline

`capture_baseline.sh` records the current validation and G1 contract test
baseline in a timestamped directory. It deliberately does not modify source or
test files.

Run it after concurrent test changes have settled:

```bash
tool/herdr-baseline/capture_baseline.sh
```

The generated result directory contains:

- `metadata.txt`: commit, working-tree status, OS, Flutter, and Dart versions.
- `analyze.log` / `test.log`: output of the repository-standard `make analyze`
  and `make test` commands.
- `*.summary`: exact command, exit status, elapsed milliseconds, and test count
  parsed from Flutter's final progress line.
- `g1-contract-test-files.txt` and `g1-contract.*`: the separate measurement of
  every existing `*_test.dart` path referenced by a `tests` array in
  `tool/herdr-inventory/tmux-contract-inventory.json`. The selection is
  extracted with `jq`, deduplicated, sorted, and validated before execution.
- `g1-contract-missing-test-files.txt`: inventory test paths that did not exist
  at capture time. The script fails instead of measuring a partial subset when
  this file is non-empty.

The inventory path and its SHA-256 are written to `metadata.txt`, so the exact
contract-test selection source is identifiable later. The script requires
`jq`, in addition to the repository's normal Flutter tooling.

Pass an explicit output directory to make a rerun overwrite-free and easy to
compare:

```bash
tool/herdr-baseline/capture_baseline.sh /tmp/herdr-baseline
```
