//! `open_round_trip`: the attach dimensions sent for protocols 17 and 20.

use super::support::*;
use crate::scrollback::args::{
    DEFAULT_MAX_OUTPUT_BYTES, DEFAULT_RESTORE_BUDGET_MS, DEFAULT_TIMEOUT_MS,
};
use crate::scrollback::*;
use crate::wire::*;
use std::os::unix::net::UnixListener;

// -----------------------------------------------------------------
// `open_round_trip` must pass
// (params.cols, original.viewport_rows) as both `Hello`'s and
// `Resize`'s dimensions — a mismatch resizes the user's real terminal
// and triggers an unwanted SIGWINCH. These go through
// `open_round_trip` itself (not `Attach17::from_stream` directly, like
// the `move_to_offset_*` tests in the position suite) over a real socket path, since
// `open_round_trip` only exposes `Attach17::connect`/`Attach20::connect`.
// -----------------------------------------------------------------

fn scrollback_params(socket: &str, protocol: u8, cols: u16) -> ScrollbackParams {
    ScrollbackParams {
        api_socket: "unused".to_owned(),
        socket: socket.to_owned(),
        pane: "w1:p2".to_owned(),
        protocol,
        cols,
        windows: vec![5],
        timeout_ms: DEFAULT_TIMEOUT_MS,
        restore_budget_ms: DEFAULT_RESTORE_BUDGET_MS,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: "/tmp".to_owned(),
    }
}

#[test]
fn open_round_trip_protocol17_sends_pane_width_and_viewport_rows_as_attach_dims() {
    let path = json_socket_path("open-round-trip17");
    let listener = UnixListener::bind(&path).unwrap();
    let server_thread = std::thread::spawn(move || {
        let mut server = accept_with_deadline(&listener);
        let hello: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let attach: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let resize: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 73,
                height: 29,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        (hello, attach, resize)
    });

    let path_str = path.to_str().unwrap().to_owned();
    let params = scrollback_params(&path_str, 17, 73);
    let original = OriginalPosition {
        offset_from_bottom: 0,
        max_offset_from_bottom: 0,
        viewport_rows: 29,
        terminal_id: "term-abc".to_owned(),
    };
    let size = crate::winsize::Winsize {
        cols: 73,
        rows: 29,
        cell_width_px: 480,
        cell_height_px: 290,
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let handle = open_round_trip(&params, &original, size, deadline).expect("open_round_trip");

    let (hello, attach, resize) = server_thread.join().unwrap();
    match attach {
        ClientMessage17::AttachTerminal { terminal_id, .. } => {
            assert_eq!(
                terminal_id, "term-abc",
                "AttachTerminal.terminal_id must be original.terminal_id, not params.pane"
            );
        }
        other => panic!("expected AttachTerminal, got {:?}", other),
    }
    match hello {
        ClientMessage17::Hello {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
            ..
        } => {
            assert_eq!(
                cols, 73,
                "Hello cols must come from the resolved real size, not params.cols"
            );
            assert_eq!(rows, 29, "Hello rows must come from the resolved real size");
            assert_eq!(
                cell_width_px, 480,
                "Hello cell_width_px must come from the resolved real size"
            );
            assert_eq!(
                cell_height_px, 290,
                "Hello cell_height_px must come from the resolved real size"
            );
        }
        other => panic!("expected Hello, got {:?}", other),
    }
    match resize {
        ClientMessage17::Resize {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
        } => {
            assert_eq!(cols, 73);
            assert_eq!(rows, 29);
            assert_eq!(
                cell_width_px, 480,
                "Resize cell_width_px must match Hello's"
            );
            assert_eq!(
                cell_height_px, 290,
                "Resize cell_height_px must match Hello's"
            );
        }
        other => panic!("expected Resize, got {:?}", other),
    }
    close_round_trip(handle);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn open_round_trip_protocol20_sends_pane_width_and_viewport_rows_as_attach_dims() {
    let path = json_socket_path("open-round-trip20");
    let listener = UnixListener::bind(&path).unwrap();
    let server_thread = std::thread::spawn(move || {
        let mut server = accept_with_deadline(&listener);
        let hello: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let attach: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        let resize: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut server,
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 54,
                height: 23,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        (hello, attach, resize)
    });

    let path_str = path.to_str().unwrap().to_owned();
    let params = scrollback_params(&path_str, 20, 54);
    let original = OriginalPosition {
        offset_from_bottom: 0,
        max_offset_from_bottom: 0,
        viewport_rows: 23,
        terminal_id: "term-abc".to_owned(),
    };
    let size = crate::winsize::Winsize {
        cols: 54,
        rows: 23,
        cell_width_px: 378,
        cell_height_px: 230,
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let handle = open_round_trip(&params, &original, size, deadline).expect("open_round_trip");

    let (hello, attach, resize) = server_thread.join().unwrap();
    match attach {
        ClientMessage20::AttachTerminal { terminal_id, .. } => {
            assert_eq!(
                terminal_id, "term-abc",
                "AttachTerminal.terminal_id must be original.terminal_id, not params.pane"
            );
        }
        other => panic!("expected AttachTerminal, got {:?}", other),
    }
    match hello {
        ClientMessage20::Hello {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
            ..
        } => {
            assert_eq!(
                cols, 54,
                "Hello cols must come from the resolved real size, not params.cols"
            );
            assert_eq!(rows, 23, "Hello rows must come from the resolved real size");
            assert_eq!(
                cell_width_px, 378,
                "Hello cell_width_px must come from the resolved real size"
            );
            assert_eq!(
                cell_height_px, 230,
                "Hello cell_height_px must come from the resolved real size"
            );
        }
        other => panic!("expected Hello, got {:?}", other),
    }
    match resize {
        ClientMessage20::Resize {
            cols,
            rows,
            cell_width_px,
            cell_height_px,
        } => {
            assert_eq!(cols, 54);
            assert_eq!(rows, 23);
            assert_eq!(
                cell_width_px, 378,
                "Resize cell_width_px must match Hello's"
            );
            assert_eq!(
                cell_height_px, 230,
                "Resize cell_height_px must match Hello's"
            );
        }
        other => panic!("expected Resize, got {:?}", other),
    }
    close_round_trip(handle);
    let _ = std::fs::remove_file(&path);
}
