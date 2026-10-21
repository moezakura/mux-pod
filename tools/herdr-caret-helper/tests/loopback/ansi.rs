//! Loopback tests for `observe_terminal_ansi` on protocols 17 and 20.

use super::terminal_frame;
use herdr_caret_helper::ansi_runner::observe_terminal_ansi;
use herdr_caret_helper::runner::RunError;
use herdr_caret_helper::winsize::Winsize;
use herdr_caret_helper::wire::*;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

// ---------------------------------------------------------------------------
// ansi_runner::observe_terminal_ansi loopback tests (protocols 17 and 20).
// ---------------------------------------------------------------------------

#[test]
fn loopback17_ansi_reads_terminal_frame_skipping_unknown_content_first() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        match hello {
            ClientMessage17::Hello {
                requested_encoding, ..
            } => assert_eq!(requested_encoding, RenderEncoding::TerminalAnsi),
            _ => panic!("expected Hello"),
        }
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let _resize: ClientMessage17 =
            read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        // A real, fully-shaped message with actual content arrives before the
        // frame we're waiting for (e.g. a sound notification). The receive
        // loop must decode and discard it, not choke on it.
        write_frame(
            &mut server,
            &ServerMessage17::Notify {
                kind: NotifyKind::Sound,
                message: "bell".to_owned(),
                body: None,
            },
        )
        .unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Terminal(terminal_frame(1, 10, 5, b"\x1b[2J\x1b[Hhi")),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let frame = observe_terminal_ansi(
        client,
        "w2:p1",
        17,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("observe_terminal_ansi(17)");
    assert_eq!(frame.width, 10);
    assert_eq!(frame.height, 5);
    assert!(frame.full);
    assert_eq!(frame.bytes, b"\x1b[2J\x1b[Hhi");
    t.join().unwrap();
}

#[test]
fn loopback17_ansi_semantic_frame_is_protocol_error() {
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
        let _obs: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        // A server that switched back to SemanticFrame data despite the
        // negotiated TerminalAnsi encoding must not be silently accepted.
        write_frame(
            &mut server,
            &ServerMessage17::Frame(FrameData {
                cells: vec![],
                width: 1,
                height: 1,
                cursor: None,
                hyperlinks: vec![],
                graphics: vec![],
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        17,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("should reject SemanticFrame data");
    assert!(matches!(err, RunError::Protocol(_)));
    t.join().unwrap();
}

#[test]
fn loopback17_ansi_non_full_frame_is_render_rejected() {
    // `TerminalFrame.full == true` is required before running a frame through
    // the tracker — checked centrally in observe_terminal_ansi so
    // no caller (hyperlinks, caret 22, scrollback-links) can forget it.
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
        let _obs: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Terminal(TerminalFrame {
                full: false,
                ..terminal_frame(1, 10, 5, b"\x1b[3;1Hpartial")
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        17,
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
fn loopback20_ansi_reads_terminal_frame() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read hello");
        match hello {
            ClientMessage20::Hello {
                requested_encoding, ..
            } => assert_eq!(requested_encoding, RenderEncoding::TerminalAnsi),
            _ => panic!("expected Hello"),
        }
        write_frame(
            &mut server,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).expect("read observe");
        let _resize: ClientMessage20 =
            read_frame(&mut server, MAX_FRAME_SIZE).expect("read resize");
        write_frame(
            &mut server,
            &ServerMessage20::WindowTitle {
                title: Some("agent".to_owned()),
            },
        )
        .unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Terminal(terminal_frame(1, 4, 2, b"\x1b[2Jyo")),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let frame = observe_terminal_ansi(
        client,
        "w2:p1",
        20,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("observe_terminal_ansi(20)");
    assert_eq!(frame.width, 4);
    assert_eq!(frame.height, 2);
    assert_eq!(frame.bytes, b"\x1b[2Jyo");
    t.join().unwrap();
}

#[test]
fn loopback20_ansi_semantic_frame_is_protocol_error() {
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
        let _obs: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Frame(FrameData {
                cells: vec![],
                width: 1,
                height: 1,
                cursor: None,
                hyperlinks: vec![],
                graphics: vec![],
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        20,
        Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect_err("should reject SemanticFrame data");
    assert!(matches!(err, RunError::Protocol(_)));
    t.join().unwrap();
}

#[test]
fn loopback20_ansi_non_full_frame_is_render_rejected() {
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
        let _obs: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Terminal(TerminalFrame {
                full: false,
                ..terminal_frame(1, 4, 2, b"\x1b[3;1Hpartial")
            }),
        )
        .unwrap();
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = observe_terminal_ansi(
        client,
        "w2:p1",
        20,
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
