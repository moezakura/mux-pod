//! herdr-caret-helper: one-shot read-only Herdr caret snapshot reader, plus
//! the `hyperlinks` subcommand for structured OSC 8 link ranges.
//!
//! Connects to a herdr client socket, performs the semantic-frame terminal
//! attach handshake, sends ObserveTerminal, and prints the first FrameData
//! cursor as a single JSON line. Exits 0 on success.
//!
//! Usage (existing caret call, no positional subcommand — unchanged):
//!   herdr-caret-helper --socket <path> --pane <id> --protocol <17|20|22>
//!                      [--cols <n>] [--rows <n>] [--timeout-ms <n>]
//!
//! Usage (`hyperlinks` subcommand):
//!   herdr-caret-helper hyperlinks --socket <path> --pane <id>
//!                      --protocol <17|20|22> [--cols <n>] [--rows <n>]
//!                      [--api-socket <path>] [--timeout-ms <n>]
//!                      [--max-output-bytes <n>]
//!
//! `--api-socket`:
//! optional, `hyperlinks`-only. When given, the real pty size is looked up
//! (`pane.process_info` -> `winsize::real_size`) and preferred over
//! `--cols`/`--rows` for the Hello/Resize sent to herdr; any failure along
//! that path falls back to `--cols`/`--rows` unchanged (fail-open; see
//! `hyperlinks::resolve_dimensions`). Omitting it keeps today's behaviour
//! byte-for-byte. The plain caret path never gains this flag.
//!
//! Usage (`scrollback-links` subcommand):
//!   herdr-caret-helper scrollback-links --api-socket <path> --socket <path>
//!                      --pane <id> --protocol <17|20|22> --cols <n>
//!                      --window <offset> [--window <offset> ...]
//!                      --lock-dir <path> [--timeout-ms <n>]
//!                      [--restore-budget-ms <n>] [--max-output-bytes <n>]
//!
//! Subcommand detection: the first positional
//! argument is matched against a fixed string, exact match only
//! (`"hyperlinks"` or `"scrollback-links"`); anything else — including no
//! arguments, or an existing caret call whose first token is always a
//! `--flag` — falls through to the existing caret path unchanged, so
//! existing caret invocations stay byte-for-byte compatible
//! (`tests/loopback.rs` is unmodified by this change). Any other positional
//! first argument (one that does not start with `-`) is rejected outright as
//! `usage_error` rather than silently falling through to the caret path
//! — see `main()`'s own comment on that check.
//!
//! No socket path, raw payload, or pane content is ever written to stderr.

use std::process::ExitCode;

use herdr_caret_helper::hyperlinks::{run_hyperlinks, HyperlinksParams, DEFAULT_MAX_OUTPUT_BYTES};
use herdr_caret_helper::is_caret_protocol_supported;
use herdr_caret_helper::is_hyperlink_protocol_supported;
use herdr_caret_helper::protocols::{CARET_SUPPORTED_PROTOCOLS, HYPERLINK_SUPPORTED_PROTOCOLS};
use herdr_caret_helper::runner::{run, CaretOutput, Params, RunError};
use herdr_caret_helper::scrollback;

fn usage() -> String {
    let protocols = CARET_SUPPORTED_PROTOCOLS
        .iter()
        .map(u8::to_string)
        .collect::<Vec<_>>()
        .join("|");
    format!("usage: herdr-caret-helper --socket <path> --pane <id> --protocol <{}> [--cols <n>] [--rows <n>] [--timeout-ms <n>]", protocols)
}

fn hyperlinks_usage() -> String {
    let protocols = HYPERLINK_SUPPORTED_PROTOCOLS
        .iter()
        .map(u8::to_string)
        .collect::<Vec<_>>()
        .join("|");
    format!("usage: herdr-caret-helper hyperlinks --socket <path> --pane <id> --protocol <{}> [--cols <n>] [--rows <n>] [--api-socket <path>] [--timeout-ms <n>] [--max-output-bytes <n>]", protocols)
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

fn parse_optional_u16(args: &[String], name: &str, default: u16) -> Result<u16, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            let v = iter
                .next()
                .ok_or_else(|| format!("argument {} requires a value", name))?;
            return v
                .parse::<u16>()
                .map_err(|_| format!("invalid value for {}", name));
        }
    }
    Ok(default)
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

/// `--api-socket` is optional, and only ever parsed for `hyperlinks`:
/// the plain caret path does
/// not gain this flag at all, so it stays byte-compatible. Omitting it for
/// `hyperlinks` keeps today's behaviour byte-for-byte -- no
/// `pane.process_info` lookup is attempted (see
/// `hyperlinks::resolve_dimensions`'s fail-open fallback).
fn parse_optional_string(args: &[String], name: &str) -> Result<Option<String>, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            return iter
                .next()
                .cloned()
                .map(Some)
                .ok_or_else(|| format!("argument {} requires a value", name));
        }
    }
    Ok(None)
}

fn parse_args(args: &[String]) -> Result<Params, String> {
    if args.contains(&"--help".to_owned()) || args.contains(&"-h".to_owned()) {
        return Err(usage());
    }
    let socket = parse_required(args, "--socket")?;
    let pane = parse_required(args, "--pane")?;
    let protocol = parse_required(args, "--protocol")?
        .parse::<u8>()
        .map_err(|_| "invalid --protocol".to_owned())?;
    let cols = parse_optional_u16(args, "--cols", 80)?;
    let rows = parse_optional_u16(args, "--rows", 24)?;
    let timeout_ms = parse_optional_u64(args, "--timeout-ms", 1000)?;

    // An explicit
    // `--cols 0` is nonsensical (the default is 80, never 0, so this only
    // ever rejects a caller-supplied zero) and must not be silently
    // forwarded to Hello/Resize, where herdr's own `clamp_terminal_size`
    // would turn it into a destructive 1x1.
    if cols == 0 {
        return Err("--cols must be non-zero".to_owned());
    }
    // Same rule for
    // `--rows 0`, by symmetry with `--cols 0` above -- it closes the same
    // destructive `clamp_terminal_size`-to-1 path, just on the row axis.
    if rows == 0 {
        return Err("--rows must be non-zero".to_owned());
    }

    if !is_caret_protocol_supported(protocol) {
        return Err(format!("unsupported protocol {}", protocol));
    }

    Ok(Params {
        socket,
        pane,
        protocol,
        cols,
        rows,
        timeout_ms,
    })
}

fn parse_hyperlinks_args(args: &[String]) -> Result<HyperlinksParams, String> {
    if args.contains(&"--help".to_owned()) || args.contains(&"-h".to_owned()) {
        return Err(hyperlinks_usage());
    }
    let socket = parse_required(args, "--socket")?;
    let pane = parse_required(args, "--pane")?;
    let protocol = parse_required(args, "--protocol")?
        .parse::<u8>()
        .map_err(|_| "invalid --protocol".to_owned())?;
    let cols = parse_optional_u16(args, "--cols", 80)?;
    let rows = parse_optional_u16(args, "--rows", 24)?;
    let timeout_ms = parse_optional_u64(args, "--timeout-ms", 1000)?;
    let max_output_bytes =
        parse_optional_usize(args, "--max-output-bytes", DEFAULT_MAX_OUTPUT_BYTES)?;
    // Optional, `hyperlinks`-only.
    // `None` when omitted -- see `resolve_dimensions`'s fail-open fallback.
    let api_socket = parse_optional_string(args, "--api-socket")?;

    // Same rule as the caret path above.
    if cols == 0 {
        return Err("--cols must be non-zero".to_owned());
    }
    // Same `--rows 0` rule,
    // same reason, mirroring the caret path above.
    if rows == 0 {
        return Err("--rows must be non-zero".to_owned());
    }

    if !is_hyperlink_protocol_supported(protocol) {
        return Err(format!("unsupported protocol {}", protocol));
    }

    Ok(HyperlinksParams {
        socket,
        api_socket,
        pane,
        protocol,
        cols,
        rows,
        timeout_ms,
        max_output_bytes,
    })
}

fn main() -> ExitCode {
    let all_args: Vec<String> = std::env::args().skip(1).collect();

    if all_args.first().map(String::as_str) == Some("hyperlinks") {
        return main_hyperlinks(&all_args[1..]);
    }
    if all_args.first().map(String::as_str) == Some("scrollback-links") {
        return main_scrollback_links(&all_args[1..]);
    }
    // Any other positional first argument (i.e. one
    // that does not itself start with `-`/`--`, so it cannot be one of the
    // existing caret call's own flags) is an unrecognized subcommand, not a
    // caret invocation to fall through to. Without this, an unwired or
    // misspelled subcommand (e.g. a typo of `hyperlinks`/`scrollback-links`)
    // would silently be parsed as caret flags instead -- confirmed
    // reproducible before this fix. `-h`/`--help` (single or double dash)
    // are excluded from this check so they still reach `parse_args`'s own
    // `--help`/`-h` handling below, unchanged.
    if let Some(first) = all_args.first() {
        if !first.starts_with('-') {
            eprintln!(
                "{}",
                RunError::Usage(format!("unknown subcommand {first}")).json()
            );
            return ExitCode::FAILURE;
        }
    }

    let params = match parse_args(&all_args) {
        Ok(p) => p,
        Err(msg) => {
            let hint = usage();
            eprintln!("{} {}", RunError::Usage(msg.clone()).json(), hint);
            return ExitCode::FAILURE;
        }
    };

    match run(&params) {
        Ok(out) => {
            println!("{}", to_json(&out));
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("{}", e.json());
            ExitCode::FAILURE
        }
    }
}

fn main_hyperlinks(args: &[String]) -> ExitCode {
    let params = match parse_hyperlinks_args(args) {
        Ok(p) => p,
        Err(_msg) => {
            // Unlike the existing caret
            // path (kept byte-compatible, hint intact), a NEW subcommand's
            // usage-error stderr must be *exactly* `{"error":"usage_error"}`
            // and nothing else -- no hint text. The app-side classifier
            // only accepts stderr that is <=256B and matches
            // `{"error":"<kind>"}` exactly; appending a hint after the JSON
            // (as the caret path does) would break that match. The rejected
            // `msg` detail is intentionally discarded here for the same
            // reason `RunError::json()` never includes it.
            eprintln!("{}", RunError::Usage(String::new()).json());
            return ExitCode::FAILURE;
        }
    };

    match run_hyperlinks(&params) {
        Ok(json) => {
            println!("{}", json);
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("{}", e.json());
            ExitCode::FAILURE
        }
    }
}

fn main_scrollback_links(args: &[String]) -> ExitCode {
    // `scrollback::parse_args` already validates the protocol allow-list
    // and every required flag itself (see its own doc comment); unlike
    // `parse_hyperlinks_args`/`parse_args` above, there is no separate
    // `--help`/`-h` short-circuit here since its parser does not define
    // one -- a bare `--help` simply falls through as an unknown/missing
    // flag, still surfacing as the same pure-JSON `usage_error` below.
    let params = match scrollback::parse_args(args) {
        Ok(p) => p,
        Err(_msg) => {
            // Same rule as
            // `main_hyperlinks`: a NEW subcommand's usage-error stderr must
            // be *exactly* `{"error":"usage_error"}`, no hint text.
            eprintln!("{}", RunError::Usage(String::new()).json());
            return ExitCode::FAILURE;
        }
    };

    match scrollback::run_scrollback_links(&params) {
        Ok(json) => {
            println!("{}", json);
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("{}", e.json());
            ExitCode::FAILURE
        }
    }
}

fn to_json(out: &CaretOutput) -> String {
    serde_json::to_string(out).unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
}
