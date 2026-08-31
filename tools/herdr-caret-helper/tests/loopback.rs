//! Loopback integration tests: a mock herdr server on one end of a UnixStream
//! pair and the observe runner on the other.

use herdr_caret_helper::runner::{run_observe17, run_observe20, CaretOutput, Params, RunError};
use herdr_caret_helper::wire::*;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

fn frame17(cursor: CursorState, width: u16, height: u16) -> ServerMessage17 {
    ServerMessage17::Frame(FrameData {
        cells: vec![],
        width,
        height,
        cursor: Some(cursor),
        hyperlinks: vec![],
        graphics: vec![],
    })
}

fn frame20(cursor: CursorState, width: u16, height: u16) -> ServerMessage20 {
    ServerMessage20::Frame(FrameData {
        cells: vec![],
        width,
        height,
        cursor: Some(cursor),
        hyperlinks: vec![],
        graphics: vec![],
    })
}

fn mock_server17(mut sock: UnixStream) {
    let hello: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read hello");
    match hello {
        ClientMessage17::Hello {
            version,
            requested_encoding,
            launch_mode,
            ..
        } => {
            assert_eq!(version, 17);
            assert_eq!(requested_encoding, RenderEncoding::SemanticFrame);
            assert_eq!(launch_mode, ClientLaunchMode17::TerminalAttach);
        }
        _ => panic!("expected Hello"),
    }
    write_frame(
        &mut sock,
        &ServerMessage17::Welcome {
            version: 17,
            encoding: RenderEncoding::SemanticFrame,
            error: None,
        },
    )
    .unwrap();
    let obs: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read observe");
    match obs {
        ClientMessage17::ObserveTerminal { target } => assert_eq!(target, "w2:p1"),
        _ => panic!("expected ObserveTerminal"),
    }
    // The helper sends a Resize after ObserveTerminal as a render kick.
    let resize: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read resize");
    match resize {
        ClientMessage17::Resize { .. } => {}
        _ => panic!("expected Resize"),
    }
    // Send a harmless non-Frame message first, then the real frame.
    write_frame(&mut sock, &ServerMessage17::ReloadSoundConfig).unwrap();
    write_frame(
        &mut sock,
        &frame17(
            CursorState {
                x: 3,
                y: 1,
                visible: true,
                shape: 5,
            },
            10,
            5,
        ),
    )
    .unwrap();
}

fn mock_server20(mut sock: UnixStream) {
    let hello: ClientMessage20 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read hello");
    match hello {
        ClientMessage20::Hello {
            version,
            requested_encoding,
            launch_mode,
            ..
        } => {
            assert_eq!(version, 20);
            assert_eq!(requested_encoding, RenderEncoding::SemanticFrame);
            assert_eq!(launch_mode, ClientLaunchMode20::TerminalAttach);
        }
        _ => panic!("expected Hello"),
    }
    write_frame(
        &mut sock,
        &ServerMessage20::Welcome {
            version: 20,
            encoding: RenderEncoding::SemanticFrame,
            error: None,
        },
    )
    .unwrap();
    let obs: ClientMessage20 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read observe");
    match obs {
        ClientMessage20::ObserveTerminal { target } => assert_eq!(target, "w2:p1"),
        _ => panic!("expected ObserveTerminal"),
    }
    // The helper sends a Resize after ObserveTerminal as a render kick.
    let resize: ClientMessage20 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read resize");
    match resize {
        ClientMessage20::Resize { .. } => {}
        _ => panic!("expected Resize"),
    }
    write_frame(
        &mut sock,
        &frame20(
            CursorState {
                x: 0,
                y: 0,
                visible: false,
                shape: 0,
            },
            4,
            2,
        ),
    )
    .unwrap();
}

/// Sends a Welcome with an error then closes.
fn mock_server17_reject(mut sock: UnixStream) {
    let _hello: ClientMessage17 = read_frame(&mut sock, MAX_FRAME_SIZE).expect("read hello");
    write_frame(
        &mut sock,
        &ServerMessage17::Welcome {
            version: 17,
            encoding: RenderEncoding::SemanticFrame,
            error: Some("bad version".to_owned()),
        },
    )
    .unwrap();
}

#[test]
fn loopback17_reads_cursor() {
    let (client, server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || mock_server17(server));
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 17,
        cols: 80,
        rows: 24,
        timeout_ms: 5000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let out: CaretOutput = run_observe17(client, &params, deadline).expect("observe17");
    let cursor = out.cursor.expect("cursor present");
    assert_eq!(cursor.x, 3);
    assert_eq!(cursor.y, 1);
    assert!(cursor.visible);
    assert_eq!(cursor.shape, 5);
    assert_eq!(out.frame_width, 10);
    assert_eq!(out.frame_height, 5);
    assert_eq!(out.protocol_version, 17);
    assert_eq!(out.pane_id, "w2:p1");
    t.join().unwrap();
}

#[test]
fn loopback20_reads_cursor() {
    let (client, server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || mock_server20(server));
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 20,
        cols: 80,
        rows: 24,
        timeout_ms: 5000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let out: CaretOutput = run_observe20(client, &params, deadline).expect("observe20");
    let cursor = out.cursor.expect("cursor present");
    assert_eq!(cursor.x, 0);
    assert_eq!(cursor.y, 0);
    assert!(!cursor.visible);
    assert_eq!(cursor.shape, 0);
    assert_eq!(out.protocol_version, 20);
    assert_eq!(out.pane_id, "w2:p1");
    t.join().unwrap();
}

#[test]
fn loopback17_cursor_null_is_legitimate() {
    // A frame with cursor: None must return promptly (no timeout) with
    // cursor == null — the "no visible cursor" observation (TUI apps).
    let (client, server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        let mut server = server;
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::SemanticFrame,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Frame(FrameData {
                cells: vec![],
                width: 4,
                height: 2,
                cursor: None,
                hyperlinks: vec![],
                graphics: vec![],
            }),
        )
        .unwrap();
    });
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 17,
        cols: 80,
        rows: 24,
        timeout_ms: 5000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let out: CaretOutput = run_observe17(client, &params, deadline).expect("observe17");
    assert!(out.cursor.is_none());
    assert_eq!(out.protocol_version, 17);
    t.join().unwrap();
}

#[test]
fn loopback17_welcome_error_rejected() {
    let (client, server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || mock_server17_reject(server));
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 17,
        cols: 80,
        rows: 24,
        timeout_ms: 5000,
    };
    let deadline = Instant::now() + Duration::from_secs(10);
    let err = run_observe17(client, &params, deadline).expect_err("should reject");
    assert!(matches!(err, RunError::WelcomeRejected(_)));
    t.join().unwrap();
}

#[test]
fn loopback17_timeout_when_no_frame() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let t = std::thread::spawn(move || {
        // Acknowledge handshake and observe, then send nothing (stall).
        let _hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::SemanticFrame,
                error: None,
            },
        )
        .unwrap();
        let _obs: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        std::thread::sleep(Duration::from_secs(2));
    });
    let params = Params {
        socket: String::new(),
        pane: "w2:p1".to_owned(),
        protocol: 17,
        cols: 80,
        rows: 24,
        timeout_ms: 200,
    };
    let deadline = Instant::now() + Duration::from_millis(200);
    let err = run_observe17(client, &params, deadline).expect_err("should time out");
    assert!(matches!(err, RunError::Timeout));
    t.join().unwrap();
}
