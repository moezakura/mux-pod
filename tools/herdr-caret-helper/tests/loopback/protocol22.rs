//! Loopback tests for protocol 22: the `observe_terminal_ansi` frame loop and
//! `run_observe22`, including unknown-tag skipping and decode failures.

use super::terminal_frame;
use herdr_caret_helper::ansi_runner::observe_terminal_ansi;
use herdr_caret_helper::runner::{run_observe22, Params, RunError};
use herdr_caret_helper::winsize::Winsize;
use herdr_caret_helper::wire::*;
use herdr_caret_helper::wire22::{ClientMessage22, ServerMessage22Known};
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// Writes one length-prefixed frame from already-encoded raw payload bytes,
/// bypassing `write_frame`'s `Serialize` bound. Used to hand-craft a frame
/// whose tag this crate has no type for (a real `ServerMessage` variant this
/// helper does not decode, e.g. `WindowTitle`), to prove the protocol-22
/// observe loop skips it instead of misdecoding or misaligning on it.
fn write_raw_frame(stream: &mut UnixStream, payload: &[u8]) {
    stream
        .write_all(&(payload.len() as u32).to_le_bytes())
        .unwrap();
    stream.write_all(payload).unwrap();
}

#[test]
fn loopback22_reads_terminal_frame_skipping_unrecognized_tag_first() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        match hello {
            ClientMessage22::TerminalHello { version, .. } => assert_eq!(version, 22),
            _ => panic!("expected TerminalHello"),
        }
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let _resize: ClientMessage22 =
            read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        // Hand-crafted real `WindowTitle { title: Some("x") }` shape (tag 6
        // in the real upstream `ServerMessage`) — a variant
        // `ServerMessage22Known` has no case for. This must be skipped
        // whole, not misdecoded as Welcome/Terminal and not desynchronize
        // the framing for the Terminal frame that follows.
        write_raw_frame(&mut server, &[0x06, 0x01, 0x01, 0x78]);
        write_frame(
            &mut server,
            &ServerMessage22Known::Terminal(terminal_frame(1, 12, 6, b"\x1b[2Jansi22")),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let frame = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("observe_terminal_ansi(22)");
    assert_eq!(frame.width, 12);
    assert_eq!(frame.height, 6);
    assert_eq!(frame.bytes, b"\x1b[2Jansi22");
    t.join().unwrap();
}

#[test]
fn loopback22_run_observe22_tracks_the_frame_and_produces_caret_output() {
    // Unlike the raw-decode test above, this exercises the
    // actual `run()`/`run_observe22` path a real caret 22 invocation takes
    // -- `observe_terminal_ansi` -> `tracker::track_frame` ->
    // `CaretOutput::from_tracked_frame` -- with a grammar-valid frame (a
    // leading CUP, unlike the raw-decode test's bytes, which
    // `track_frame` would reject as `PrintWithoutPosition`). Proves
    // `run_observe22` (now wired into `run()`'s `match`, replacing the
    // prior `unreachable!()` panic on protocol 22) works end to end, not
    // just the pure `CaretOutput::from_tracked_frame` function
    // `caret22_pure.rs` already covers.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        match hello {
            ClientMessage22::TerminalHello { version, .. } => assert_eq!(version, 22),
            _ => panic!("expected TerminalHello"),
        }
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let _resize: ClientMessage22 =
            read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        write_frame(
            &mut server,
            &ServerMessage22Known::Terminal(terminal_frame(
                1,
                12,
                6,
                b"\x1b[1;1HX\x1b[2;3H\x1b[?25h",
            )),
        )
        .unwrap();
    });
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 22,
        cols: 80,
        rows: 24,
        timeout_ms: 10_000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let out = run_observe22(client, &params, deadline).expect("run_observe22 must not be rejected");
    assert_eq!(out.protocol_version, 22);
    assert_eq!(out.pane_id, "w2:p1");
    assert_eq!(out.frame_width, 12);
    assert_eq!(out.frame_height, 6);
    let cursor = out
        .cursor
        .expect("trailing ?25h must yield a visible cursor");
    assert!(cursor.visible);
    assert_eq!((cursor.x, cursor.y), (2, 1));
    t.join().unwrap();
}

#[test]
fn loopback22_run_observe22_survives_a_control_char_link_in_the_frame() {
    // A C0 byte inside one OSC 8 URI used to reject the whole frame
    // (and with it the caret). Only that link is excluded now; the caret
    // position still comes out.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let _resize: ClientMessage22 =
            read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        write_frame(
            &mut server,
            &ServerMessage22Known::Terminal(terminal_frame(
                1,
                12,
                6,
                b"\x1b[1;1H\x1b]8;;https://bad/\x00x\x1b\\X\x1b]8;;\x1b\\\x1b[2;3H\x1b[?25h",
            )),
        )
        .unwrap();
    });
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 22,
        cols: 80,
        rows: 24,
        timeout_ms: 10_000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let out = run_observe22(client, &params, deadline).expect("must not be render_rejected");
    let cursor = out.cursor.expect("trailing ?25h must yield a cursor");
    assert_eq!((cursor.x, cursor.y), (2, 1));
    t.join().unwrap();
}

#[test]
fn loopback22_run_observe22_hello_and_resize_cell_px_stay_zero() {
    // The caret path does not use `--api-socket`: `run_observe22` always builds
    // its `Winsize { cell_width_px: 0, cell_height_px: 0, .. }` explicitly
    // for `observe_terminal_ansi`'s bundled `size` parameter, so its
    // Hello/Resize must keep sending `cell_width_px: 0, cell_height_px: 0`
    // regardless of the new cell-pixel-aware path added for `hyperlinks`.
    // This asserts both messages' actual field values, unlike the
    // `_hello`/`_resize` discard-pattern test above.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        match hello {
            ClientMessage22::TerminalHello {
                version,
                cell_width_px,
                cell_height_px,
                ..
            } => {
                assert_eq!(version, 22);
                assert_eq!(cell_width_px, 0);
                assert_eq!(cell_height_px, 0);
            }
            _ => panic!("expected TerminalHello"),
        }
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let resize: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        match resize {
            ClientMessage22::Resize {
                cell_width_px,
                cell_height_px,
                ..
            } => {
                assert_eq!(cell_width_px, 0);
                assert_eq!(cell_height_px, 0);
            }
            _ => panic!("expected Resize"),
        }
        write_frame(
            &mut server,
            &ServerMessage22Known::Terminal(terminal_frame(1, 1, 1, b"\x1b[1;1HX")),
        )
        .unwrap();
    });
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 22,
        cols: 80,
        rows: 24,
        timeout_ms: 10_000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    run_observe22(client, &params, deadline).expect("run_observe22 must not be rejected");
    t.join().unwrap();
}

#[test]
fn loopback22_malformed_known_tag_frame_is_decode_error_not_skipped() {
    // Tag 1 (Terminal) is a tag this helper *does* claim to understand, but
    // the frame carries no field bytes at all (not even `seq: u64`). Unlike
    // an unrecognized tag (see the test above), this must surface as a
    // decode error immediately — silently skipping it would hide the fault
    // until the deadline's timeout instead.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        // Tag byte for `Terminal` (1) with zero payload bytes following it.
        write_raw_frame(&mut server, &[0x01]);
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("a malformed Terminal-tagged frame must not be treated as unknown-and-skippable");
    assert!(
        matches!(err, RunError::Bincode(_)),
        "expected a decode error, got {err:?}"
    );
    t.join().unwrap();
}

#[test]
fn loopback22_truncated_welcome_is_decode_error_not_skipped() {
    // Same guarantee as `loopback22_malformed_known_tag_frame_is_decode_error_not_skipped`,
    // but exercised through the *first* frame's decode path
    // (`decode_known22` called from the `first` binding in `observe22_ansi`,
    // before `ObserveTerminal`/`Resize` are ever sent) rather than through
    // the main receive loop. Tag 0 (Welcome) is a tag this helper claims to
    // understand, but the frame carries only the tag byte — none of
    // `version`/`encoding`/`error`. This must surface as a decode error
    // immediately, not be treated as an unrecognized-and-skippable tag.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        // Tag byte for `Welcome` (0) with zero payload bytes following it.
        write_raw_frame(&mut server, &[0x00]);
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("a truncated Welcome-tagged frame must not be treated as unknown-and-skippable");
    assert!(
        matches!(err, RunError::Bincode(_)),
        "expected a decode error, got {err:?}"
    );
    t.join().unwrap();
}

#[test]
fn loopback22_non_full_frame_is_render_rejected() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage22Known::Terminal(TerminalFrame {
                full: false,
                ..terminal_frame(1, 12, 6, b"\x1b[3;1Hpartial")
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("a non-full first frame must be rejected, not returned");
    assert!(matches!(err, RunError::RenderRejected(_)));
    t.join().unwrap();
}

#[test]
fn loopback22_welcome_error_rejected() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: Some("bad version".to_owned()),
            },
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("should reject");
    assert!(matches!(err, RunError::WelcomeRejected(_)));
    t.join().unwrap();
}

#[test]
fn loopback22_timeout_when_no_frame() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage22 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        std::thread::sleep(Duration::from_secs(2));
    });
    let deadline = Instant::now() + Duration::from_millis(200);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        22,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("should time out");
    assert!(matches!(err, RunError::Timeout));
    t.join().unwrap();
}

#[test]
fn observe_terminal_ansi_rejects_unsupported_protocol() {
    let (client, _server) = UnixStream::pair().unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        19,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("protocol 19 is not 17/20/22");
    assert!(matches!(err, RunError::Usage(_)));
}
