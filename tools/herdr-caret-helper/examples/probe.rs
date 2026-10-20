//! Throwaway investigation probe for measurement — NOT part of
//! the distributed `herdr-caret-helper` binary and not installed on any SSH
//! target. Combines the building blocks under active development
//! (`api_client`, `attach`, `ansi_runner`) into small, composable
//! subcommands so a wrapper shell script can time and orchestrate the
//! measurement procedures without baking any particular
//! sequencing into this binary.
//!
//! Each subcommand does exactly one wire-level thing and prints a single
//! line of output (plain text, not JSON — this is not the product's stdout
//! contract). Usage:
//!
//!   probe observe --socket <path> --pane <id> --protocol <17|20|22>
//!                 [--cols <n>] [--rows <n>] [--timeout-ms <n>] [--dump-bytes]
//!   probe pane-get --api-socket <path> --pane <id> [--timeout-ms <n>]
//!   probe pane-scroll --api-socket <path> --pane <id> --offset <n> [--timeout-ms <n>]
//!   probe attach-hold --socket <path> --pane <id> --protocol <17|20>
//!                     [--cols <n>] [--rows <n>] [--takeover <true|false>] --hold-secs <n>
//!   probe attach-scroll --socket <path> --pane <id> --protocol <17|20>
//!                       [--cols <n>] [--rows <n>] --direction <up|down> --lines <n>
//!                       [--pause-ms <n>] [--timeout-ms <n>]
//!   probe raw-api --api-socket <path> --method <name> --params '<json>' [--timeout-ms <n>]
//!
//! `raw-api` is a generic passthrough for any herdr.sock JSON-RPC method
//! *not* in the product's contract (`pane.get`/`pane.scroll`/`pane.process_info`).
//! It exists only for investigation (e.g. `pane.send_text` to
//! set up a WINCH trap, `pane.read` to read it back) and is deliberately
//! kept out of `api_client.rs`'s public surface so the library's contract
//! stays minimal.

use herdr_caret_helper::ansi_runner::observe_terminal_ansi;
use herdr_caret_helper::api_client::{pane_get, pane_scroll};
use herdr_caret_helper::attach::{Attach17, Attach20, ScrollDirection};
use herdr_caret_helper::winsize::Winsize;
use herdr_caret_helper::wire::TerminalFrame;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

fn arg(args: &[String], name: &str) -> Option<String> {
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == name {
            return it.next().cloned();
        }
    }
    None
}

fn flag(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == name)
}

fn arg_or(args: &[String], name: &str, default: &str) -> String {
    arg(args, name).unwrap_or_else(|| default.to_owned())
}

fn require(args: &[String], name: &str) -> String {
    arg(args, name).unwrap_or_else(|| panic!("missing required argument {}", name))
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let Some(subcommand) = args.first().cloned() else {
        eprintln!("usage: probe <observe|pane-get|pane-scroll|attach-hold|attach-scroll> ...");
        std::process::exit(2);
    };
    args.remove(0);

    match subcommand.as_str() {
        "observe" => cmd_observe(&args),
        "pane-get" => cmd_pane_get(&args),
        "pane-scroll" => cmd_pane_scroll(&args),
        "attach-hold" => cmd_attach_hold(&args),
        "attach-read-hold" => cmd_attach_read_hold(&args),
        "attach-scroll" => cmd_attach_scroll(&args),
        "raw-api" => cmd_raw_api(&args),
        other => {
            eprintln!("unknown subcommand: {other}");
            std::process::exit(2);
        }
    }
}

/// Connects, performs the TerminalAnsi observe handshake for the given
/// protocol, and prints the resulting frame's metadata and (optionally) its
/// raw bytes. Used for checking `full`, byte-grammar
/// sanity, and (with `--dump-bytes`) manual/ad-hoc cursor-tail inspection —
/// the real cursor-extraction grammar is the tracker's job (`tracker.rs`),
/// not reimplemented here.
fn cmd_observe(args: &[String]) {
    let socket = require(args, "--socket");
    let pane = require(args, "--pane");
    let protocol: u8 = require(args, "--protocol")
        .parse()
        .expect("invalid --protocol");
    let cols: u16 = arg_or(args, "--cols", "80")
        .parse()
        .expect("invalid --cols");
    let rows: u16 = arg_or(args, "--rows", "24")
        .parse()
        .expect("invalid --rows");
    let cell_width_px: u16 = arg_or(args, "--cell-width-px", "0")
        .parse()
        .expect("invalid --cell-width-px");
    let cell_height_px: u16 = arg_or(args, "--cell-height-px", "0")
        .parse()
        .expect("invalid --cell-height-px");
    let timeout_ms: u64 = arg_or(args, "--timeout-ms", "1500")
        .parse()
        .expect("invalid --timeout-ms");
    let dump_bytes = flag(args, "--dump-bytes");
    let save_raw = arg(args, "--save-raw");

    let size = Winsize {
        cols,
        rows,
        cell_width_px,
        cell_height_px,
    };
    let stream = UnixStream::connect(&socket).expect("connect failed");
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let started = Instant::now();
    let result = observe_terminal_ansi(stream, &pane, protocol, size, deadline);
    let elapsed_ms = started.elapsed().as_millis();

    match result {
        Ok(frame) => {
            print_frame_summary(&frame, elapsed_ms);
            if dump_bytes {
                println!("bytes_escaped={}", escape_bytes(&frame.bytes));
                describe_cursor_tail(&frame.bytes);
            }
            // Investigation-only: write the exact raw frame bytes verbatim
            // (no escaping) for fixture capture.
            // Never used by the distributed hyperlinks/scrollback-links
            // subcommands.
            if let Some(path) = save_raw {
                std::fs::write(&path, &frame.bytes).expect("failed to write --save-raw file");
                println!("saved_raw_bytes path={path} len={}", frame.bytes.len());
            }
        }
        Err(e) => {
            println!("observe_failed elapsed_ms={elapsed_ms} error={}", e.json());
            std::process::exit(1);
        }
    }
}

fn print_frame_summary(frame: &TerminalFrame, elapsed_ms: u128) {
    println!(
        "observe_ok elapsed_ms={elapsed_ms} seq={} width={} height={} full={} byte_len={}",
        frame.seq,
        frame.width,
        frame.height,
        frame.full,
        frame.bytes.len()
    );
}

/// Escapes non-printable bytes as `\xHH` for safe terminal-safe stdout
/// (investigation output only, never the product's stdout contract).
fn escape_bytes(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len());
    for &b in bytes {
        match b {
            0x20..=0x7e if b != b'\\' => out.push(b as char),
            b'\\' => out.push_str("\\\\"),
            _ => out.push_str(&format!("\\x{:02x}", b)),
        }
    }
    out
}

/// Ad-hoc, investigation-only scan for a trailing cursor-position sequence
/// (`ESC[<row>;<col>H` or `ESC[<row>;<col>f`) followed by an optional
/// `ESC[?<n> q` (DECSCUSR) and a final `ESC[?25h`/`ESC[?25l` — the grammar
/// from which position and visibility can be extracted (`render_ansi.rs:816-828`).
/// This is a manual sanity check, not the tracker's actual parser (that is
/// `tracker.rs`).
fn describe_cursor_tail(bytes: &[u8]) {
    let text = String::from_utf8_lossy(bytes);
    let last_cup = text.rfind("\u{1b}[").map(|_| {
        // Find the last CUP-shaped escape (`ESC[<digits>;<digits>H` or `f`).
        let mut last = None;
        let b = text.as_bytes();
        let mut i = 0;
        while let Some(pos) = text[i..].find("\u{1b}[") {
            let start = i + pos;
            let mut j = start + 2;
            let digits_start = j;
            while j < b.len() && (b[j].is_ascii_digit() || b[j] == b';') {
                j += 1;
            }
            if j > digits_start && j < b.len() && (b[j] == b'H' || b[j] == b'f') {
                last = Some((start, j + 1));
            }
            i = start + 2;
            if i >= text.len() {
                break;
            }
        }
        last
    });
    let visible = if text.ends_with("\u{1b}[?25h") {
        Some(true)
    } else if text.ends_with("\u{1b}[?25l") {
        Some(false)
    } else {
        None
    };
    match (last_cup.flatten(), visible) {
        (Some((s, e)), Some(v)) => println!(
            "cursor_tail_scan cup={:?} visible={} (manual scan, not the tracker's grammar)",
            &text[s..e],
            v
        ),
        (cup, v) => println!(
            "cursor_tail_scan cup={:?} visible={:?} (inconclusive manual scan)",
            cup, v
        ),
    }
}

/// Calls `pane.get` and prints the pane's `terminal_id` and scroll state.
/// Used for recording o0 before a round trip.
fn cmd_pane_get(args: &[String]) {
    let api_socket = require(args, "--api-socket");
    let pane = require(args, "--pane");
    let timeout_ms: u64 = arg_or(args, "--timeout-ms", "1500")
        .parse()
        .expect("invalid --timeout-ms");
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    match pane_get(&api_socket, &pane, deadline) {
        Ok(info) => println!(
            "pane_get_ok terminal_id={} scroll={:?}",
            info.terminal_id, info.scroll
        ),
        Err(e) => {
            println!("pane_get_failed error={}", e.json());
            std::process::exit(1);
        }
    }
}

/// Calls `pane.scroll` and prints the resulting scroll state. Used for
/// moving to a window, and confirming the restore.
fn cmd_pane_scroll(args: &[String]) {
    let api_socket = require(args, "--api-socket");
    let pane = require(args, "--pane");
    let offset: u64 = require(args, "--offset").parse().expect("invalid --offset");
    let timeout_ms: u64 = arg_or(args, "--timeout-ms", "1500")
        .parse()
        .expect("invalid --timeout-ms");
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    match pane_scroll(&api_socket, &pane, offset, deadline) {
        Ok(info) => println!(
            "pane_scroll_ok terminal_id={} scroll={:?}",
            info.terminal_id, info.scroll
        ),
        Err(e) => {
            println!("pane_scroll_failed error={}", e.json());
            std::process::exit(1);
        }
    }
}

/// Attaches (with the given takeover flag) and holds the connection open for
/// `--hold-secs`, printing every server push it receives, then detaches.
/// Used for observing takeover / eviction from a second probe
/// instance run concurrently against the same pane while this one holds.
/// Mirrors `legacy-scroll-probe`'s `hold17`/`hold20` (investigation-only,
/// this crate's copy is written independently against `attach.rs`).
///
/// `--pane` here is passed straight through to `attach.rs`'s
/// `connect_with_takeover`, which expects the pane's
/// *resolved* terminal_id (e.g. `term_65c85b8010f252`, from `pane-get`'s
/// output), **not** pane notation (`w1:p2`) -- a real herdr server rejects
/// pane notation there with `attach_rejected`. This CLI flag is kept as
/// `--pane` rather than renamed to `--terminal-id` since this is an
/// investigation-only tool (never shipped); resolve it yourself first via
/// `probe pane-get` if you only have pane notation.
fn cmd_attach_hold(args: &[String]) {
    let socket = require(args, "--socket");
    let pane = require(args, "--pane");
    let protocol: u8 = require(args, "--protocol")
        .parse()
        .expect("invalid --protocol");
    let cols: u16 = arg_or(args, "--cols", "80")
        .parse()
        .expect("invalid --cols");
    let rows: u16 = arg_or(args, "--rows", "24")
        .parse()
        .expect("invalid --rows");
    let cell_width_px: u16 = arg_or(args, "--cell-width-px", "0")
        .parse()
        .expect("invalid --cell-width-px");
    let cell_height_px: u16 = arg_or(args, "--cell-height-px", "0")
        .parse()
        .expect("invalid --cell-height-px");
    let hold_secs: u64 = require(args, "--hold-secs")
        .parse()
        .expect("invalid --hold-secs");
    let takeover: bool = arg_or(args, "--takeover", "true")
        .parse()
        .expect("invalid --takeover");
    let connect_timeout_ms: u64 = arg_or(args, "--timeout-ms", "5000")
        .parse()
        .expect("invalid --timeout-ms");

    let size = Winsize {
        cols,
        rows,
        cell_width_px,
        cell_height_px,
    };
    let connect_deadline = Instant::now() + Duration::from_millis(connect_timeout_ms);
    macro_rules! run {
        ($ty:ident) => {{
            match $ty::connect_with_takeover(&socket, &pane, size, takeover, connect_deadline) {
                Ok(session) => {
                    println!("attach_ok");
                    std::thread::sleep(Duration::from_secs(hold_secs));
                    session.detach();
                    println!("attach_hold_detached_after_secs={hold_secs}");
                }
                Err(e) => {
                    // {:?} is investigation-only detail (probe.rs is never
                    // distributed): the product's stderr contract only ever emits e.json()'s
                    // classification, but the probe needs the raw ServerShutdown{reason} text to
                    // find root causes.
                    println!("attach_failed error={} detail={:?}", e.json(), e);
                    std::process::exit(1);
                }
            }
        }};
    }
    match protocol {
        17 => run!(Attach17),
        20 => run!(Attach20),
        _ => {
            eprintln!("attach-hold only supports protocol 17 or 20");
            std::process::exit(2);
        }
    }
}

/// Like `attach-hold`, but actively reads pushes for up to `--hold-secs`
/// instead of blind-sleeping, so it can observe an eviction
/// (`ServerShutdown`) if a concurrent takeover happens during the hold. It
/// confirms which of several concurrently-attached clients
/// actually gets evicted by a takeover.
///
/// `--pane` semantics: see `cmd_attach_hold`'s doc comment (resolved
/// terminal_id required, not pane notation).
fn cmd_attach_read_hold(args: &[String]) {
    let socket = require(args, "--socket");
    let pane = require(args, "--pane");
    let protocol: u8 = require(args, "--protocol")
        .parse()
        .expect("invalid --protocol");
    let cols: u16 = arg_or(args, "--cols", "80")
        .parse()
        .expect("invalid --cols");
    let rows: u16 = arg_or(args, "--rows", "24")
        .parse()
        .expect("invalid --rows");
    let cell_width_px: u16 = arg_or(args, "--cell-width-px", "0")
        .parse()
        .expect("invalid --cell-width-px");
    let cell_height_px: u16 = arg_or(args, "--cell-height-px", "0")
        .parse()
        .expect("invalid --cell-height-px");
    let hold_secs: u64 = require(args, "--hold-secs")
        .parse()
        .expect("invalid --hold-secs");
    let takeover: bool = arg_or(args, "--takeover", "true")
        .parse()
        .expect("invalid --takeover");
    let connect_timeout_ms: u64 = arg_or(args, "--timeout-ms", "5000")
        .parse()
        .expect("invalid --timeout-ms");

    let size = Winsize {
        cols,
        rows,
        cell_width_px,
        cell_height_px,
    };
    let connect_deadline = Instant::now() + Duration::from_millis(connect_timeout_ms);
    let hold_deadline = Instant::now() + Duration::from_secs(hold_secs);
    macro_rules! run {
        ($ty:ident) => {{
            match $ty::connect_with_takeover(&socket, &pane, size, takeover, connect_deadline) {
                Ok(mut session) => {
                    println!("attach_ok");
                    match session.wait_for_shutdown(hold_deadline) {
                        Some(reason) => println!("evicted reason={reason:?}"),
                        None => println!("not_evicted_within_hold_secs={hold_secs}"),
                    }
                }
                Err(e) => {
                    println!("attach_failed error={} detail={:?}", e.json(), e);
                    std::process::exit(1);
                }
            }
        }};
    }
    match protocol {
        17 => run!(Attach17),
        20 => run!(Attach20),
        _ => {
            eprintln!("attach-read-hold only supports protocol 17 or 20");
            std::process::exit(2);
        }
    }
}

/// Attaches, scrolls `--lines` in `--direction`, optionally pauses
/// `--pause-ms` (to let an external process inject output for the
/// concurrent-output investigation), scrolls back by the same
/// amount, and detaches — printing the elapsed time for the whole scroll
/// round trip (for 17/20). Deliberately does *not* observe a
/// frame itself: observation happens over a *separate*
/// connection (invoke `probe observe` from another process while this one
/// is paused, or sequence it externally), matching the production design
/// where the attach/scroll connection and the observe connection are never
/// the same socket connection.
///
/// `--pane` semantics: see `cmd_attach_hold`'s doc comment (resolved
/// terminal_id required, not pane notation).
fn cmd_attach_scroll(args: &[String]) {
    let socket = require(args, "--socket");
    let pane = require(args, "--pane");
    let protocol: u8 = require(args, "--protocol")
        .parse()
        .expect("invalid --protocol");
    let cols: u16 = arg_or(args, "--cols", "80")
        .parse()
        .expect("invalid --cols");
    let rows: u16 = arg_or(args, "--rows", "24")
        .parse()
        .expect("invalid --rows");
    let cell_width_px: u16 = arg_or(args, "--cell-width-px", "0")
        .parse()
        .expect("invalid --cell-width-px");
    let cell_height_px: u16 = arg_or(args, "--cell-height-px", "0")
        .parse()
        .expect("invalid --cell-height-px");
    let direction = match require(args, "--direction").as_str() {
        "up" => ScrollDirection::Up,
        "down" => ScrollDirection::Down,
        other => {
            eprintln!("invalid --direction {other} (expected up|down)");
            std::process::exit(2);
        }
    };
    let lines: u32 = require(args, "--lines").parse().expect("invalid --lines");
    let pause_ms: u64 = arg_or(args, "--pause-ms", "0")
        .parse()
        .expect("invalid --pause-ms");
    let timeout_ms: u64 = arg_or(args, "--timeout-ms", "5000")
        .parse()
        .expect("invalid --timeout-ms");
    // `--no-restore` (default: off, unchanged round-trip behavior below) --
    // added for cleanup: a plain single-direction scroll (e.g. "down"
    // by exactly the pane's current offset_from_bottom) to move a pane back
    // to the bottom, without the built-in opposite-direction restore this
    // subcommand otherwise always performs. Not used by any existing
    // timing measurement.
    let no_restore = flag(args, "--no-restore");
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);

    let size = Winsize {
        cols,
        rows,
        cell_width_px,
        cell_height_px,
    };
    let started = Instant::now();
    macro_rules! run {
        ($ty:ident) => {{
            let mut session = match $ty::connect(&socket, &pane, size, deadline) {
                Ok(s) => s,
                Err(e) => {
                    // {:?} is investigation-only detail (probe.rs is never
                    // distributed): the product's stderr contract only ever emits e.json()'s
                    // classification, but the probe needs the raw ServerShutdown{reason} text to
                    // find root causes.
                    println!("attach_failed error={} detail={:?}", e.json(), e);
                    std::process::exit(1);
                }
            };
            if let Err(e) = session.scroll(direction, lines, deadline) {
                println!("scroll_up_failed error={}", e.json());
                std::process::exit(1);
            }
            let up_elapsed_ms = started.elapsed().as_millis();
            println!("scrolled_up_elapsed_ms={up_elapsed_ms}");
            if no_restore {
                session.detach();
                let total_elapsed_ms = started.elapsed().as_millis();
                println!("single_direction_ok total_elapsed_ms={total_elapsed_ms}");
                return;
            }
            if pause_ms > 0 {
                std::thread::sleep(Duration::from_millis(pause_ms));
            }
            let restore_started = Instant::now();
            let opposite = match direction {
                ScrollDirection::Up => ScrollDirection::Down,
                ScrollDirection::Down => ScrollDirection::Up,
            };
            if let Err(e) = session.scroll(opposite, lines, deadline) {
                println!("scroll_down_failed error={}", e.json());
                std::process::exit(1);
            }
            let restore_elapsed_ms = restore_started.elapsed().as_millis();
            session.detach();
            let total_elapsed_ms = started.elapsed().as_millis();
            println!(
                "roundtrip_ok restore_elapsed_ms={restore_elapsed_ms} total_elapsed_ms={total_elapsed_ms}"
            );
        }};
    }
    match protocol {
        17 => run!(Attach17),
        20 => run!(Attach20),
        _ => {
            eprintln!("attach-scroll only supports protocol 17 or 20");
            std::process::exit(2);
        }
    }
}

/// Sends one arbitrary `{"id":"1","method":<name>,"params":<json>}` line to
/// herdr.sock and prints the raw response line verbatim. Investigation-only
/// (see module doc comment) — opens one connection per call, matching the
/// one-shot-per-request behavior `api_client.rs` relies on
/// (`src/api/server.rs:156-183` in the vendored source).
fn cmd_raw_api(args: &[String]) {
    let api_socket = require(args, "--api-socket");
    let method = require(args, "--method");
    let params = arg_or(args, "--params", "{}");
    let timeout_ms: u64 = arg_or(args, "--timeout-ms", "1500")
        .parse()
        .expect("invalid --timeout-ms");

    let params_value: serde_json::Value =
        serde_json::from_str(&params).expect("--params must be valid JSON");
    let request = serde_json::json!({ "id": "1", "method": method, "params": params_value });

    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    match raw_call(&api_socket, &request.to_string(), deadline) {
        Ok(line) => println!("raw_api_ok response={}", line.trim_end()),
        Err(e) => {
            println!("raw_api_failed error={e}");
            std::process::exit(1);
        }
    }
}

fn raw_call(socket: &str, request_line: &str, deadline: Instant) -> Result<String, String> {
    let now = Instant::now();
    if now >= deadline {
        return Err("timeout (deadline already elapsed)".to_owned());
    }
    let timeout = deadline - now;
    let stream = UnixStream::connect(socket).map_err(|e| format!("connect_failed: {e}"))?;
    stream
        .set_write_timeout(Some(timeout))
        .map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(timeout))
        .map_err(|e| e.to_string())?;
    {
        let mut writer = &stream;
        writer
            .write_all(request_line.as_bytes())
            .map_err(|e| e.to_string())?;
        writer.write_all(b"\n").map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
    }
    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    let read = reader.read_line(&mut line).map_err(|e| e.to_string())?;
    if read == 0 {
        return Err("connection closed before a response line arrived".to_owned());
    }
    Ok(line)
}
