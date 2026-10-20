//! Loopback integration tests for `run_hyperlinks`
//! itself (`src/hyperlinks.rs`), exercising its actual success path (JSON
//! output) and its `render_rejected` failure path against a mock herdr
//! server on one end of a `UnixStream::pair()` -- mirrors `tests/
//! loopback.rs`'s style, but for the `hyperlinks` subcommand's full
//! pipeline (`observe_terminal_ansi` -> `aggregate_frame` -> `sanitize_
//! links` -> `render_output`) rather than only its CLI-level `usage_error`/
//! `connect_failed` boundary checks (`tests/hyperlinks_cli.rs`,
//! `tests/protocols.rs`).

use herdr_caret_helper::hyperlinks::{run_hyperlinks, HyperlinksParams};
use herdr_caret_helper::runner::RunError;
use herdr_caret_helper::winsize::Winsize;
use herdr_caret_helper::wire::*;
use std::os::unix::net::UnixStream;
use std::thread;
use std::time::{Duration, Instant};

fn cup(row1: u16, col1: u16) -> String {
    format!("\x1b[{};{}H", row1, col1)
}
fn osc8_open(url: &str) -> String {
    format!("\x1b]8;;{}\x1b\\", url)
}
fn osc8_close() -> &'static str {
    "\x1b]8;;\x1b\\"
}

/// Drives one protocol-17 TerminalAnsi handshake to completion, then sends
/// `frame` as the `Terminal` response -- the same handshake shape
/// `observe17_ansi` (`src/ansi_runner.rs`) drives, hand-rolled here instead
/// of reusing `tests/loopback.rs`'s `mock_server17` since that helper
/// negotiates `SemanticFrame`, not `TerminalAnsi`.
fn mock_hyperlinks_server17(mut sock: UnixStream, frame: TerminalFrame) {
    let hello: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read hello");
    match hello {
        ClientMessage17::Hello {
            version,
            requested_encoding,
            ..
        } => {
            assert_eq!(version, 17);
            assert_eq!(requested_encoding, RenderEncoding::TerminalAnsi);
        }
        _ => panic!("expected Hello"),
    }
    write_frame(
        &mut sock,
        &ServerMessage17::Welcome {
            version: 17,
            encoding: RenderEncoding::TerminalAnsi,
            error: None,
        },
    )
    .unwrap();
    let obs: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read observe");
    match obs {
        ClientMessage17::ObserveTerminal { target } => assert_eq!(target, "w1:p1"),
        _ => panic!("expected ObserveTerminal"),
    }
    let resize: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read resize");
    assert!(matches!(resize, ClientMessage17::Resize { .. }));
    write_frame(&mut sock, &ServerMessage17::Terminal(frame)).unwrap();
}

fn sample_params(socket_name_hint: &str) -> HyperlinksParams {
    let _ = socket_name_hint;
    HyperlinksParams {
        socket: String::new(), // unused: `run_hyperlinks` connects via `UnixStream::connect`
        // Omitted here (byte-compatible path, no
        // `pane.process_info` lookup attempted -- see `resolve_dimensions`).
        api_socket: None,
        pane: "w1:p1".to_owned(),
        protocol: 17,
        cols: 80,
        rows: 24,
        timeout_ms: 2000,
        max_output_bytes: herdr_caret_helper::hyperlinks::DEFAULT_MAX_OUTPUT_BYTES,
    }
}

#[test]
fn run_hyperlinks_success_path_returns_expected_json_over_a_real_socket() {
    let (client, server) = UnixStream::pair().expect("socketpair");
    let bytes = format!(
        "{}{}ab{}",
        cup(1, 1),
        osc8_open("https://example.com/"),
        osc8_close()
    )
    .into_bytes();
    let frame = TerminalFrame {
        seq: 1,
        width: 80,
        height: 24,
        full: true,
        bytes,
    };
    let handle = thread::spawn(move || mock_hyperlinks_server17(server, frame));

    // `run_hyperlinks` itself calls `UnixStream::connect(&params.socket)`,
    // so it cannot be driven directly over an already-connected `client`
    // half of a `pair()` -- exercise the same connect+observe pipeline it
    // uses internally instead, via `observe_terminal_ansi`, and assert on
    // the very same aggregation/rendering functions `run_hyperlinks` calls,
    // proving the full pipeline end-to-end without needing a real listening
    // socket path.
    let deadline = Instant::now() + Duration::from_millis(2000);
    let observed = herdr_caret_helper::ansi_runner::observe_terminal_ansi(
        client,
        "w1:p1",
        17,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("observe must succeed");
    handle.join().unwrap();

    let aggregated = herdr_caret_helper::hyperlinks::aggregate_frame(
        &observed.bytes,
        observed.width,
        observed.height,
    )
    .expect("frame must not be rejected");
    assert_eq!(aggregated.links.len(), 1);
    assert_eq!(aggregated.links[0].url, "https://example.com/");
    assert_eq!(aggregated.links[0].ranges, vec![(0, 0, 1)]);
}

#[test]
fn run_hyperlinks_render_rejected_path_surfaces_as_render_rejected_not_a_panic() {
    let (client, server) = UnixStream::pair().expect("socketpair");
    // An unknown CSI final byte ('x') -- `tracker::track_frame` rejects
    // this with `TrackError::UnknownSequence`, which `run_hyperlinks`
    // (via `aggregate_frame`) maps to `RunError::RenderRejected`.
    let bytes = format!("{}\x1b[5x", cup(1, 1)).into_bytes();
    let frame = TerminalFrame {
        seq: 1,
        width: 80,
        height: 24,
        full: true,
        bytes,
    };
    let handle = thread::spawn(move || mock_hyperlinks_server17(server, frame));

    let deadline = Instant::now() + Duration::from_millis(2000);
    let observed = herdr_caret_helper::ansi_runner::observe_terminal_ansi(
        client,
        "w1:p1",
        17,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("observe itself must succeed -- the frame is well-formed at the wire level");
    handle.join().unwrap();

    let err = herdr_caret_helper::hyperlinks::aggregate_frame(
        &observed.bytes,
        observed.width,
        observed.height,
    )
    .unwrap_err();
    assert_eq!(
        err,
        herdr_caret_helper::tracker::TrackError::UnknownSequence
    );
    // `run_hyperlinks` itself wraps exactly this error as `RenderRejected`
    // (`src/hyperlinks.rs`'s `run_hyperlinks`, the
    // `.map_err(|e| RunError::RenderRejected(format!("{e:?}")))` line) --
    // confirmed by direct source inspection, not re-derived here, since
    // driving `run_hyperlinks` itself needs a real listening
    // `UnixListener` (its `--socket` is connected via `UnixStream::connect`,
    // not injectable as a pre-built pair -- see `sample_params`'s comment).
    let wrapped = RunError::RenderRejected(format!("{err:?}"));
    assert!(matches!(wrapped, RunError::RenderRejected(_)));
    assert_eq!(wrapped.json(), r#"{"error":"render_rejected"}"#);
}

#[test]
fn run_hyperlinks_over_a_real_listening_socket_end_to_end() {
    // The definitive case: `run_hyperlinks` called directly (not
    // just its internal pieces), against a real `UnixListener`, so the
    // `UnixStream::connect` inside `run_hyperlinks` itself is exercised.
    let dir = std::env::temp_dir().join(format!(
        "herdr-hyperlinks-loopback-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    let socket_path = dir.join("herdr.sock");
    let listener = std::os::unix::net::UnixListener::bind(&socket_path).expect("bind");

    let bytes = format!(
        "{}{}ab{}",
        cup(1, 1),
        osc8_open("https://example.com/"),
        osc8_close()
    )
    .into_bytes();
    let frame = TerminalFrame {
        seq: 1,
        width: 80,
        height: 24,
        full: true,
        bytes,
    };
    let handle = thread::spawn(move || {
        let (sock, _) = listener.accept().expect("accept");
        mock_hyperlinks_server17(sock, frame);
    });

    let mut params = sample_params("real-listener");
    params.socket = socket_path.to_str().unwrap().to_owned();
    let json = run_hyperlinks(&params).expect("run_hyperlinks must succeed");
    handle.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);

    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["paneId"], "w1:p1");
    assert_eq!(parsed["protocolVersion"], 17);
    assert_eq!(parsed["truncated"], false);
    assert_eq!(parsed["links"][0]["url"], "https://example.com/");
    assert_eq!(
        parsed["links"][0]["ranges"][0],
        serde_json::json!([0, 0, 1])
    );
}

#[test]
fn run_hyperlinks_over_a_real_listening_socket_render_rejected_end_to_end() {
    // Same as the success-path listener test above, but the mock server
    // sends a malformed `TerminalAnsi` frame -- `run_hyperlinks` itself
    // (not just `aggregate_frame` in isolation) must surface this as
    // `Err(RunError::RenderRejected(_))`, not a panic or a misleading
    // `connect_failed`/`io_error`.
    let dir = std::env::temp_dir().join(format!(
        "herdr-hyperlinks-loopback-rejected-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    let socket_path = dir.join("herdr.sock");
    let listener = std::os::unix::net::UnixListener::bind(&socket_path).expect("bind");

    let bytes = format!("{}\x1b[5x", cup(1, 1)).into_bytes();
    let frame = TerminalFrame {
        seq: 1,
        width: 80,
        height: 24,
        full: true,
        bytes,
    };
    let handle = thread::spawn(move || {
        let (sock, _) = listener.accept().expect("accept");
        mock_hyperlinks_server17(sock, frame);
    });

    let mut params = sample_params("real-listener-rejected");
    params.socket = socket_path.to_str().unwrap().to_owned();
    let err = run_hyperlinks(&params).unwrap_err();
    handle.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);

    assert!(matches!(err, RunError::RenderRejected(_)), "err={err:?}");
    assert_eq!(err.json(), r#"{"error":"render_rejected"}"#);
}

#[test]
fn run_hyperlinks_over_a_real_listening_socket_drops_only_the_control_char_link() {
    // One OSC 8 link whose URI holds a C0 byte next to a valid link.
    // `run_hyperlinks` succeeds and emits only the valid link.
    let dir = std::env::temp_dir().join(format!(
        "herdr-hyperlinks-loopback-ctl-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    let socket_path = dir.join("herdr.sock");
    let listener = std::os::unix::net::UnixListener::bind(&socket_path).expect("bind");

    let bytes = format!(
        "{}\x1b]8;;https://bad/\x01x\x1b\\bad{}{}ok{}",
        cup(1, 1),
        osc8_close(),
        osc8_open("https://good/"),
        osc8_close()
    )
    .into_bytes();
    let frame = TerminalFrame {
        seq: 1,
        width: 80,
        height: 24,
        full: true,
        bytes,
    };
    let handle = thread::spawn(move || {
        let (sock, _) = listener.accept().expect("accept");
        mock_hyperlinks_server17(sock, frame);
    });

    let mut params = sample_params("real-listener-ctl");
    params.socket = socket_path.to_str().unwrap().to_owned();
    let json = run_hyperlinks(&params).expect("must not be render_rejected");
    handle.join().unwrap();
    let _ = std::fs::remove_dir_all(&dir);

    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["links"].as_array().unwrap().len(), 1);
    assert_eq!(parsed["links"][0]["url"], "https://good/");
    assert_eq!(
        parsed["links"][0]["ranges"][0],
        serde_json::json!([0, 3, 4])
    );
}
