//! End-to-end CLI dispatch tests for the `hyperlinks` subcommand,
//! exercising the actual compiled binary (mirrors `tests/protocols.rs`'s
//! `Command`-based style) rather than calling `main.rs`'s private
//! `parse_hyperlinks_args`/`main_hyperlinks` directly. This is the only way
//! to confirm the first-argument exact-string subcommand detection itself
//! (main.rs:1's doc comment) actually dispatches correctly, since that
//! logic lives in `main()`.

use std::process::Command;

fn run(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_herdr-caret-helper"))
        .args(args)
        .output()
        .expect("failed to run the compiled binary")
}

#[test]
fn hyperlinks_subcommand_with_unsupported_protocol_is_usage_error_before_connecting() {
    // A protocol unsupported by any allow-list -- must not attempt to
    // connect at all (mirrors protocols.rs's caret-path assertion).
    let output = run(&[
        "hyperlinks",
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "255",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("usage_error"), "stderr={stderr}");
}

#[test]
fn hyperlinks_subcommand_with_protocol_22_is_connect_failed_not_usage_error() {
    // Protocol 22 is accepted by the `hyperlinks` allow-list -- the allow-list
    // actually consulted here must be `HYPERLINK_SUPPORTED_PROTOCOLS`, so this
    // must reach (and fail) the connect step, not be rejected before it as a bad
    // protocol.
    let output = run(&[
        "hyperlinks",
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "22",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("connect_failed"), "stderr={stderr}");
}

#[test]
fn hyperlinks_subcommand_missing_required_flag_is_pure_json_usage_error_with_no_hint() {
    // Unlike the existing caret path
    // (which keeps its hint, unchanged -- see
    // `existing_caret_missing_flag_still_gets_its_hint_unchanged` below), a
    // NEW subcommand's usage-error stderr must be *exactly*
    // `{"error":"usage_error"}` with no trailing hint text, since the
    // app-side classifier only accepts stderr that is <=256B and
    // matches `{"error":"<kind>"}` exactly.
    let output = run(&["hyperlinks", "--pane", "w1:p1", "--protocol", "22"]);
    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
    assert!(stderr.len() <= 256, "stderr={stderr}");
}

#[test]
fn hyperlinks_subcommand_with_cols_zero_is_usage_error_before_connecting() {
    // In `main.rs::parse_hyperlinks_args`:
    // an explicit `--cols 0` must be rejected as `usage_error` before ever
    // attempting to connect -- forwarding it would let herdr's own
    // `clamp_terminal_size` turn it into a destructive 1x1 resize. Tested at
    // the binary level: deleting the `cols == 0` check in
    // `parse_hyperlinks_args` must fail `cargo test`.
    let output = run(&[
        "hyperlinks",
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
        "--cols",
        "0",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn existing_caret_cols_zero_is_usage_error_before_connecting() {
    // Same rule, existing caret path (`parse_args`). Unlike the `hyperlinks` subcommand
    // above, the caret path keeps its hinted usage_error format unchanged
    // (see `existing_caret_missing_flag_still_gets_its_hint_unchanged`),
    // so this only checks the JSON kind prefix, not an exact match.
    let output = run(&[
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
        "--cols",
        "0",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        stderr.starts_with(r#"{"error":"usage_error"}"#),
        "stderr={stderr}"
    );
}

#[test]
fn hyperlinks_subcommand_with_rows_zero_is_usage_error_before_connecting() {
    // `--rows 0` is
    // rejected the same way as `--cols 0` above, by symmetry (same
    // destructive `clamp_terminal_size`-to-1 path, row axis instead of
    // column). Deleting the `rows == 0` check in `parse_hyperlinks_args`
    // must fail this test.
    let output = run(&[
        "hyperlinks",
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
        "--rows",
        "0",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn existing_caret_rows_zero_is_usage_error_before_connecting() {
    // Same `--rows 0` rule, existing caret path (`parse_args`) -- mirrors
    // `existing_caret_cols_zero_is_usage_error_before_connecting` above.
    let output = run(&[
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
        "--rows",
        "0",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        stderr.starts_with(r#"{"error":"usage_error"}"#),
        "stderr={stderr}"
    );
}

#[test]
fn hyperlinks_subcommand_help_flag_is_also_pure_json_usage_error_with_no_hint() {
    // `--help`/`-h` goes through the same `parse_hyperlinks_args` -> `Err`
    // -> `main_hyperlinks` path as any other usage error, so it must be
    // just as pure -- no help text leaks onto stderr for the new
    // subcommand family (unlike the untouched caret `--help` path).
    let output = run(&["hyperlinks", "--help"]);
    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn existing_caret_missing_flag_still_gets_its_hint_unchanged() {
    // Byte-compatibility guard: the
    // existing caret usage-error path must keep appending its hint after
    // the JSON, exactly as before this change -- only the NEW subcommand
    // paths (`hyperlinks`, and later `scrollback-links`) switch to pure
    // JSON.
    let output = run(&["--pane", "w1:p1", "--protocol", "17"]);
    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        stderr.starts_with(r#"{"error":"usage_error"}"#),
        "stderr={stderr}"
    );
    assert!(
        stderr.contains("herdr-caret-helper --socket"),
        "stderr={stderr}"
    );
}

#[test]
fn unrecognized_positional_subcommand_is_rejected_as_usage_error_not_treated_as_caret() {
    // A positional first argument that is neither
    // `hyperlinks` nor `scrollback-links` nor a caret flag (e.g. a typo)
    // must be rejected outright as `usage_error`, not silently parsed as
    // if it were caret flags. Reproduces the originally reported case
    // (back when `scrollback-links` itself was still unwired): this used
    // to return `connect_failed` (it was being parsed as caret, which then
    // tried and failed to connect) -- exactly the misrouting this test
    // guards against. `scrollback-links` is now a real subcommand (see
    // `scrollback_links_subcommand_dispatches_to_its_own_path_not_caret`
    // below), so a plain typo is used here instead to keep testing the
    // *unrecognized*-subcommand path specifically.
    let output = run(&[
        "scrollback-lnks",
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn scrollback_links_subcommand_dispatches_to_its_own_path_not_caret() {
    // `scrollback-links` must dispatch to
    // `main_scrollback_links`, not fall through to caret. Missing every
    // required flag reaches `scrollback::parse_args`'s own validation
    // (distinct from caret's/hyperlinks' `--socket`/`--pane`/`--protocol`
    // set -- it additionally requires `--api-socket`, `--cols`, `--window`,
    // `--lock-dir`), which is proof enough that this argument list was
    // parsed as `scrollback-links`, not caret (caret's `parse_args` would
    // instead fail on the missing `--protocol`... but with a *hinted*
    // usage_error, which this pure-JSON assertion also rules out).
    let output = run(&["scrollback-links", "--socket", "/dev/null/x.sock"]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn unrecognized_positional_subcommand_with_no_flags_at_all_is_still_usage_error() {
    let output = run(&["not-a-real-subcommand"]);
    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert_eq!(
        stderr.trim_end(),
        r#"{"error":"usage_error"}"#,
        "stderr={stderr}"
    );
}

#[test]
fn existing_caret_invocation_is_unaffected_by_hyperlinks_dispatch() {
    // The existing caret call never has "hyperlinks" as its first token
    // (it always starts with a `--flag`), so this must take the untouched
    // caret path end to end: same as protocols.rs's existing assertion,
    // repeated here as a direct regression guard against the dispatch
    // change itself (not just against the caret arg-parsing helpers).
    let output = run(&[
        "--socket",
        "/dev/null/herdr-hyperlinks-cli-test.sock",
        "--pane",
        "w1:p1",
        "--protocol",
        "17",
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("connect_failed"), "stderr={stderr}");
    assert!(
        !stderr.contains("hyperlinks"),
        "must be the caret usage hint, not the hyperlinks one: {stderr}"
    );
}
