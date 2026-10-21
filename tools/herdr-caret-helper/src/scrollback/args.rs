//! Command-line argument parsing for `scrollback-links`.
//!
//! `ScrollbackParams` and `parse_args`, with the flag defaults and the
//! three-window limit.

use crate::is_scrollback_link_protocol_supported;

pub(super) const DEFAULT_TIMEOUT_MS: u64 = 1500;
pub(super) const DEFAULT_RESTORE_BUDGET_MS: u64 = 700;
pub(super) const DEFAULT_MAX_OUTPUT_BYTES: usize = 60_000;
const MAX_WINDOWS: usize = 3;

/// CLI parameters for `scrollback-links`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScrollbackParams {
    pub api_socket: String,
    pub socket: String,
    pub pane: String,
    pub protocol: u8,
    pub cols: u16,
    /// `offset_from_bottom` values from 1..=3 `--window` flags, in the
    /// order given on the command line.
    pub windows: Vec<u64>,
    pub timeout_ms: u64,
    pub restore_budget_ms: u64,
    pub max_output_bytes: usize,
    pub lock_dir: String,
}

fn parse_required(args: &[String], name: &str) -> Result<String, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            return iter
                .next()
                .cloned()
                .ok_or_else(|| format!("argument {} requires a value", name));
        }
    }
    Err(format!("missing required argument {}", name))
}

fn parse_optional_u64(args: &[String], name: &str, default: u64) -> Result<u64, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            let v = iter
                .next()
                .ok_or_else(|| format!("argument {} requires a value", name))?;
            return v
                .parse::<u64>()
                .map_err(|_| format!("invalid value for {}", name));
        }
    }
    Ok(default)
}

fn parse_optional_usize(args: &[String], name: &str, default: usize) -> Result<usize, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            let v = iter
                .next()
                .ok_or_else(|| format!("argument {} requires a value", name))?;
            return v
                .parse::<usize>()
                .map_err(|_| format!("invalid value for {}", name));
        }
    }
    Ok(default)
}

/// Collects every `--window <n>` occurrence, in order. Requires at least
/// one and at most `MAX_WINDOWS` (3).
fn parse_windows(args: &[String]) -> Result<Vec<u64>, String> {
    let mut out = Vec::new();
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == "--window" {
            let v = iter
                .next()
                .ok_or_else(|| "argument --window requires a value".to_owned())?;
            let n: u64 = v
                .parse()
                .map_err(|_| "invalid value for --window".to_owned())?;
            out.push(n);
        }
    }
    if out.is_empty() {
        return Err("missing required argument --window (at least one)".to_owned());
    }
    if out.len() > MAX_WINDOWS {
        return Err(format!(
            "too many --window arguments (max {}, got {})",
            MAX_WINDOWS,
            out.len()
        ));
    }
    Ok(out)
}

/// Parses `scrollback-links` CLI arguments (everything after the
/// subcommand name itself). The protocol allow-list check
/// (`SCROLLBACK_LINK_SUPPORTED_PROTOCOLS`) runs here, before any
/// connection is attempted (an unsupported protocol is a `usage_error`).
///
/// `--lock-dir` is **required** (it has no default, unlike the other
/// options): a caller-omitted default would
/// otherwise fall back to a world-writable location such as `/tmp` when
/// `$HOME` is unset, which is not an acceptable place to put a lock file.
pub fn parse_args(args: &[String]) -> Result<ScrollbackParams, String> {
    let api_socket = parse_required(args, "--api-socket")?;
    let socket = parse_required(args, "--socket")?;
    let pane = parse_required(args, "--pane")?;
    let protocol: u8 = parse_required(args, "--protocol")?
        .parse()
        .map_err(|_| "invalid --protocol".to_owned())?;
    let cols: u16 = parse_required(args, "--cols")?
        .parse()
        .map_err(|_| "invalid --cols".to_owned())?;
    let windows = parse_windows(args)?;
    let timeout_ms = parse_optional_u64(args, "--timeout-ms", DEFAULT_TIMEOUT_MS)?;
    let restore_budget_ms =
        parse_optional_u64(args, "--restore-budget-ms", DEFAULT_RESTORE_BUDGET_MS)?;
    let max_output_bytes =
        parse_optional_usize(args, "--max-output-bytes", DEFAULT_MAX_OUTPUT_BYTES)?;
    let lock_dir = parse_required(args, "--lock-dir")?;

    if !is_scrollback_link_protocol_supported(protocol) {
        return Err(format!("unsupported protocol {}", protocol));
    }
    if cols == 0 {
        // `cols == 0` is a `usage_error` (rejected on the helper
        // side), caught here before any connection is attempted, same
        // pattern as the protocol allow-list check above.
        return Err("--cols must be nonzero".to_owned());
    }

    Ok(ScrollbackParams {
        api_socket,
        socket,
        pane,
        protocol,
        cols,
        windows,
        timeout_ms,
        restore_budget_ms,
        max_output_bytes,
        lock_dir,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(pairs: &[&str]) -> Vec<String> {
        pairs.iter().map(|s| s.to_owned().to_owned()).collect()
    }

    #[test]
    fn parse_args_fills_defaults_and_parses_single_window() {
        let a = args(&[
            "--api-socket",
            "/tmp/herdr.sock",
            "--socket",
            "/tmp/client.sock",
            "--pane",
            "w1:p1",
            "--protocol",
            "22",
            "--cols",
            "80",
            "--window",
            "5",
            "--lock-dir",
            "/custom/locks",
        ]);
        let p = parse_args(&a).expect("should parse");
        assert_eq!(p.api_socket, "/tmp/herdr.sock");
        assert_eq!(p.socket, "/tmp/client.sock");
        assert_eq!(p.pane, "w1:p1");
        assert_eq!(p.protocol, 22);
        assert_eq!(p.cols, 80);
        assert_eq!(p.windows, vec![5]);
        assert_eq!(p.timeout_ms, DEFAULT_TIMEOUT_MS);
        assert_eq!(p.restore_budget_ms, DEFAULT_RESTORE_BUDGET_MS);
        assert_eq!(p.max_output_bytes, DEFAULT_MAX_OUTPUT_BYTES);
        assert_eq!(p.lock_dir, "/custom/locks");
    }

    #[test]
    fn parse_args_collects_up_to_three_windows_in_order() {
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "17",
            "--cols",
            "80",
            "--window",
            "3",
            "--window",
            "9",
            "--window",
            "0",
            "--lock-dir",
            "/locks",
        ]);
        let p = parse_args(&a).expect("should parse");
        assert_eq!(p.windows, vec![3, 9, 0]);
    }

    #[test]
    fn parse_args_rejects_more_than_three_windows() {
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "17",
            "--cols",
            "80",
            "--window",
            "1",
            "--window",
            "2",
            "--window",
            "3",
            "--window",
            "4",
            "--lock-dir",
            "/locks",
        ]);
        assert!(parse_args(&a).is_err());
    }

    #[test]
    fn parse_args_rejects_zero_windows() {
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "17",
            "--cols",
            "80",
            "--lock-dir",
            "/locks",
        ]);
        assert!(parse_args(&a).is_err());
    }

    #[test]
    fn parse_args_rejects_unsupported_protocol_before_any_connection() {
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "5",
            "--cols",
            "80",
            "--window",
            "0",
            "--lock-dir",
            "/locks",
        ]);
        let err = parse_args(&a).expect_err("protocol 5 is not in the allow-list");
        assert!(err.contains("unsupported protocol"));
    }

    #[test]
    fn parse_args_rejects_cols_zero_as_usage_error() {
        // `--cols 0`
        // is a usage_error, checked at parse time before any connection --
        // `parse_args`'s `Err(String)` becomes `RunError::Usage(..)` ->
        // `main.rs` prints kind `"usage_error"` (verified against
        // `RunError::json`'s match arms in `error.rs`).
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "17",
            "--cols",
            "0",
            "--window",
            "0",
            "--lock-dir",
            "/locks",
        ]);
        let err = parse_args(&a).expect_err("--cols 0 must be rejected");
        assert!(
            err.contains("--cols") && err.contains("nonzero"),
            "error message should name --cols as the offending flag, got: {err}"
        );
    }

    #[test]
    fn parse_args_parses_lock_dir_value() {
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "22",
            "--cols",
            "80",
            "--window",
            "0",
            "--lock-dir",
            "/custom/locks",
        ]);
        let p = parse_args(&a).expect("should parse");
        assert_eq!(p.lock_dir, "/custom/locks");
    }

    #[test]
    fn parse_args_rejects_missing_lock_dir() {
        // `--lock-dir` is required,
        // there is no fallback default (a missing $HOME would otherwise
        // resolve to a world-writable /tmp location).
        let a = args(&[
            "--api-socket",
            "s1",
            "--socket",
            "s2",
            "--pane",
            "p",
            "--protocol",
            "22",
            "--cols",
            "80",
            "--window",
            "0",
        ]);
        let err = parse_args(&a).expect_err("--lock-dir is required");
        assert!(err.contains("--lock-dir"));
    }
}
