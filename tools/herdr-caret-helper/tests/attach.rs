//! Loopback tests for the writable 17/20 attach + scroll control
//! (`AttachTerminal` -> `AttachScroll` -> `Detach`), driven over
//! `UnixStream::pair()` with a hand-written fake server (same style as
//! `tests/loopback/`).

use herdr_caret_helper::attach::{Attach17, Attach20, ScrollDirection};
use herdr_caret_helper::runner::RunError;
use herdr_caret_helper::winsize::Winsize;
use herdr_caret_helper::wire::*;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

/// Shorthand for building a test `Winsize` with zeroed cell pixel geometry
/// (untested by these loopback tests, which only exercise `cols`/`rows`).
fn winsize(cols: u16, rows: u16) -> Winsize {
    Winsize {
        cols,
        rows,
        cell_width_px: 0,
        cell_height_px: 0,
    }
}

/// Reads Hello, replies Welcome (TerminalAnsi), reads AttachTerminal (checks
/// takeover:true and the terminal_id), reads Resize (checks dimensions),
/// then sends a Terminal frame — the full success path.
fn accept_and_confirm17(
    sock: &mut UnixStream,
    expect_pane: &str,
    expect_cols: u16,
    expect_rows: u16,
) {
    let hello: ClientMessage17 = read_frame(sock, MAX_FRAME_SIZE).expect("read hello");
    match hello {
        ClientMessage17::Hello {
            version,
            requested_encoding,
            launch_mode,
            cols,
            rows,
            ..
        } => {
            assert_eq!(version, 17);
            assert_eq!(requested_encoding, RenderEncoding::TerminalAnsi);
            assert_eq!(launch_mode, ClientLaunchMode17::TerminalAttach);
            assert_eq!(cols, expect_cols);
            assert_eq!(rows, expect_rows);
        }
        _ => panic!("expected Hello"),
    }
    write_frame(
        sock,
        &ServerMessage17::Welcome {
            version: 17,
            encoding: RenderEncoding::TerminalAnsi,
            error: None,
        },
    )
    .unwrap();
    let attach: ClientMessage17 = read_frame(sock, MAX_FRAME_SIZE).expect("read attach");
    match attach {
        ClientMessage17::AttachTerminal {
            terminal_id,
            takeover,
        } => {
            assert_eq!(terminal_id, expect_pane);
            assert!(takeover, "takeover must always be true");
        }
        _ => panic!("expected AttachTerminal"),
    }
    let resize: ClientMessage17 = read_frame(sock, MAX_FRAME_SIZE).expect("read resize");
    match resize {
        ClientMessage17::Resize { cols, rows, .. } => {
            assert_eq!(cols, expect_cols);
            assert_eq!(rows, expect_rows);
        }
        _ => panic!("expected Resize"),
    }
    write_frame(
        sock,
        &ServerMessage17::Terminal(TerminalFrame {
            seq: 1,
            width: expect_cols,
            height: expect_rows,
            full: true,
            bytes: vec![],
        }),
    )
    .unwrap();
}

#[test]
fn attach17_connect_succeeds_and_sends_expected_handshake() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || accept_and_confirm17(&mut server, "w1:p2", 80, 24));
    let deadline = Instant::now() + Duration::from_secs(5);
    let session =
        Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline).expect("attach17");
    session.detach();
    t.join().unwrap();
}

#[test]
fn attach17_welcome_error_is_welcome_rejected() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: Some("bad version".to_owned()),
            },
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline)
        .expect_err("should reject");
    assert!(matches!(err, RunError::WelcomeRejected(_)));
    t.join().unwrap();
}

#[test]
fn attach17_server_shutdown_after_attach_is_attach_rejected() {
    // Simulates an existing attach owner refusing to be taken over is not
    // the case here (takeover is always true) — this covers any other
    // ServerShutdown the server may send before the first Terminal frame
    // (e.g. the terminal_id does not resolve).
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::ServerShutdown {
                reason: Some("terminal attach failed: unknown terminal".to_owned()),
            },
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline)
        .expect_err("should reject");
    match err {
        RunError::AttachRejected(reason) => {
            assert!(reason.contains("unknown terminal"));
        }
        other => panic!("expected AttachRejected(_), got {:?}", other),
    }
    t.join().unwrap();
}

#[test]
fn attach17_unexpected_frame_data_under_terminal_ansi_is_protocol_error() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        // A SemanticFrame-shaped push under a TerminalAnsi handshake is a
        // protocol violation, not a legitimate "no frame yet" state.
        write_frame(
            &mut server,
            &ServerMessage17::Frame(FrameData {
                cells: vec![],
                width: 10,
                height: 5,
                cursor: None,
                hyperlinks: vec![],
                graphics: vec![],
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline)
        .expect_err("should reject");
    assert!(matches!(err, RunError::Protocol(_)));
    t.join().unwrap();
}

#[test]
fn attach17_ignores_harmless_pushes_before_terminal_frame() {
    // Accepting on any non-`ServerShutdown` message was tried and reverted: a
    // server-wide broadcast (e.g. `ReloadSoundConfig`
    // via `send_to_all_clients()`) can land on this connection before its
    // `AttachTerminal` is decided, so acceptance must still wait
    // specifically for the first `Terminal` frame — other pushes are
    // ignored, not treated as an accept signal.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(&mut server, &ServerMessage17::ReloadSoundConfig).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let session =
        Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline).expect("attach17");
    session.detach();
    t.join().unwrap();
}

#[test]
fn attach17_scroll_sends_direction_and_lines() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        accept_and_confirm17(&mut server, "w1:p2", 80, 24);
        let up: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        match up {
            ClientMessage17::AttachScroll {
                source,
                direction,
                lines,
                ..
            } => {
                // The wire source for
                // every AttachScroll this crate sends is `PageKey{input:
                // vec![]}`, never `Wheel` (a real herdr server's scroll
                // handling differs by source).
                assert!(
                    matches!(source, AttachScrollSource::PageKey { ref input } if input.is_empty()),
                    "scroll() must send PageKey{{input: []}}, not Wheel or any other source, got {:?}",
                    source
                );
                assert_eq!(direction, 0);
                assert_eq!(lines, 30);
            }
            _ => panic!("expected AttachScroll"),
        }
        let down: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        match down {
            ClientMessage17::AttachScroll {
                source,
                direction,
                lines,
                ..
            } => {
                assert!(
                    matches!(source, AttachScrollSource::PageKey { ref input } if input.is_empty()),
                    "scroll() must send PageKey{{input: []}}, not Wheel or any other source, got {:?}",
                    source
                );
                assert_eq!(direction, 1);
                assert_eq!(lines, 30);
            }
            _ => panic!("expected AttachScroll"),
        }
        let detach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        assert!(matches!(detach, ClientMessage17::Detach));
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut session =
        Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline).expect("attach17");
    session
        .scroll(ScrollDirection::Up, 30, deadline)
        .expect("scroll up");
    session
        .scroll(ScrollDirection::Down, 30, deadline)
        .expect("scroll down");
    session.detach();
    t.join().unwrap();
}

#[test]
fn attach17_scroll_splits_across_u16_boundary() {
    // 70_000 lines exceeds u16::MAX (65535), so it must split into two
    // AttachScroll messages: 65535 + 4465.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        accept_and_confirm17(&mut server, "w1:p2", 80, 24);
        let mut chunks = vec![];
        for _ in 0..2 {
            let msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
            match msg {
                ClientMessage17::AttachScroll {
                    direction, lines, ..
                } => {
                    assert_eq!(direction, 0);
                    chunks.push(lines);
                }
                _ => panic!("expected AttachScroll"),
            }
        }
        chunks
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut session =
        Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline).expect("attach17");
    session
        .scroll(ScrollDirection::Up, 70_000, deadline)
        .expect("scroll up");
    let chunks = t.join().unwrap();
    assert_eq!(chunks, vec![u16::MAX, 4465]);
    assert_eq!(chunks[0] as u32 + chunks[1] as u32, 70_000);
}

#[test]
fn attach17_timeout_when_no_welcome() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        std::thread::sleep(Duration::from_secs(2));
    });
    let deadline = Instant::now() + Duration::from_millis(200);
    let err = Attach17::from_stream(client, "w1:p2", winsize(80, 24), deadline)
        .expect_err("should time out");
    assert!(matches!(err, RunError::Timeout));
    t.join().unwrap();
}

// --- Protocol 20: same coverage as 17 for the success and rejection paths
// (the two protocols intentionally duplicate logic, matching runner.rs's
// run_observe17/run_observe20 split; a representative subset is enough
// here since the wire-level codec differences are already covered by
// tests/codec.rs).

fn accept_and_confirm20(
    sock: &mut UnixStream,
    expect_pane: &str,
    expect_cols: u16,
    expect_rows: u16,
) {
    let hello: ClientMessage20 = read_frame(sock, MAX_FRAME_SIZE).expect("read hello");
    match hello {
        ClientMessage20::Hello {
            version,
            requested_encoding,
            launch_mode,
            cols,
            rows,
            ..
        } => {
            assert_eq!(version, 20);
            assert_eq!(requested_encoding, RenderEncoding::TerminalAnsi);
            assert_eq!(launch_mode, ClientLaunchMode20::TerminalAttach);
            assert_eq!(cols, expect_cols);
            assert_eq!(rows, expect_rows);
        }
        _ => panic!("expected Hello"),
    }
    write_frame(
        sock,
        &ServerMessage20::Welcome {
            version: 20,
            encoding: RenderEncoding::TerminalAnsi,
            error: None,
        },
    )
    .unwrap();
    let attach: ClientMessage20 = read_frame(sock, MAX_FRAME_SIZE).expect("read attach");
    match attach {
        ClientMessage20::AttachTerminal {
            terminal_id,
            takeover,
        } => {
            assert_eq!(terminal_id, expect_pane);
            assert!(takeover);
        }
        _ => panic!("expected AttachTerminal"),
    }
    let resize: ClientMessage20 = read_frame(sock, MAX_FRAME_SIZE).expect("read resize");
    assert!(matches!(resize, ClientMessage20::Resize { .. }));
    write_frame(
        sock,
        &ServerMessage20::Terminal(TerminalFrame {
            seq: 1,
            width: expect_cols,
            height: expect_rows,
            full: true,
            bytes: vec![],
        }),
    )
    .unwrap();
}

#[test]
fn attach20_connect_succeeds_and_scroll_and_detach_round_trip() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        accept_and_confirm20(&mut server, "w1:p3", 100, 30);
        let scroll: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        match scroll {
            ClientMessage20::AttachScroll {
                source,
                direction,
                lines,
                ..
            } => {
                // See the matching assertion/rationale in
                // `attach17_scroll_sends_direction_and_lines`.
                assert!(
                    matches!(source, AttachScrollSource::PageKey { ref input } if input.is_empty()),
                    "scroll() must send PageKey{{input: []}}, not Wheel or any other source, got {:?}",
                    source
                );
                assert_eq!(direction, 0);
                assert_eq!(lines, 12);
            }
            _ => panic!("expected AttachScroll"),
        }
        let detach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        assert!(matches!(detach, ClientMessage20::Detach));
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut session =
        Attach20::from_stream(client, "w1:p3", winsize(100, 30), deadline).expect("attach20");
    session
        .scroll(ScrollDirection::Up, 12, deadline)
        .expect("scroll");
    session.detach();
    t.join().unwrap();
}

#[test]
fn attach20_server_shutdown_after_attach_is_attach_rejected() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::ServerShutdown {
                reason: Some("terminal attach taken over".to_owned()),
            },
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = Attach20::from_stream(client, "w1:p3", winsize(100, 30), deadline)
        .expect_err("should reject");
    assert!(matches!(err, RunError::AttachRejected(_)));
    t.join().unwrap();
}

#[test]
fn attach20_ignores_harmless_pushes_before_terminal_frame() {
    // Mirrors attach17_ignores_harmless_pushes_before_terminal_frame; accepting on
    // any non-`ServerShutdown` message was reverted for both protocols.
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let _hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(&mut server, &ServerMessage20::ReloadSoundConfig).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 100,
                height: 30,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let session =
        Attach20::from_stream(client, "w1:p3", winsize(100, 30), deadline).expect("attach20");
    session.detach();
    t.join().unwrap();
}
