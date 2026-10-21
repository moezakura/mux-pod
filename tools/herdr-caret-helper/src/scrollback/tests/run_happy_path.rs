//! End-to-end `run_scrollback_links` happy paths for protocols 22, 17, and 20.

use super::support::*;
use crate::scrollback::args::DEFAULT_MAX_OUTPUT_BYTES;
use crate::scrollback::*;
use crate::wire::*;
use crate::wire22::{ClientMessage22, ServerMessage22Known};
use std::os::unix::net::UnixListener;

// -- end-to-end `run_scrollback_links` happy path (protocol 22) --

#[test]
fn run_scrollback_links_protocol22_happy_path_two_windows_restores_to_bottom() {
    let api_path = json_socket_path("run22-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses: Vec<String> = vec![
        pane_info_response(0), // 1. record_original_position: o0=0
        pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong
        //    `type` tag (this is a `pane_info` shape) -> treated
        //    as a failure -> falls back to params.cols/viewport_rows
        //    (protocol 22 is fail-*open*, not fail-closed).
        pane_info_response(10), // 3. window1 move: pane.scroll -> offset 10
        pane_info_response(10), // 4. window1 move: confirm poll
        pane_info_response(20), // 5. window2 move: pane.scroll -> offset 20
        pane_info_response(20), // 6. window2 move: confirm poll
        pane_info_response(20), // 7. restore: read o1 (t=20, o1=20 -- no
        //    output flowed in)
        pane_info_response(0), // 8. restore: pane.scroll(0) -> offset 0
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run22-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let observe_thread = std::thread::spawn(move || {
        for i in 0..2u16 {
            let mut stream = accept_with_deadline(&client_listener);
            // Allow-list: only TerminalHello/ObserveTerminal/Resize
            // are allowed on this connection -- exhaustive matches below
            // fail closed on any other variant (Input/ClipboardImage/
            // ControlTerminal/GraphicsTransmissionResult/AttachTerminal/
            // AttachScroll/Detach).
            let hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            match hello {
                ClientMessage22::TerminalHello { cols, rows, .. } => {
                    assert_eq!(cols, 80, "TerminalHello cols must be params.cols");
                    assert_eq!(
                        rows, 24,
                        "TerminalHello rows must be pane.get's viewport_rows"
                    );
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            write_frame(
                &mut stream,
                &ServerMessage22Known::Welcome {
                    version: 22,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            match observe {
                ClientMessage22::ObserveTerminal { .. } => {}
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            match resize {
                ClientMessage22::Resize { cols, rows, .. } => {
                    assert_eq!(cols, 80, "Resize cols must be params.cols");
                    assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
                }
                other => panic!("disallowed message type (allow-list): {:?}", other),
            }
            let bytes =
                format!("\x1b[1;1H\x1b]8;;https://example.com/w{i}\x1b\\link{i}\x1b]8;;\x1b\\")
                    .into_bytes();
            write_frame(
                &mut stream,
                &ServerMessage22Known::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes,
                }),
            )
            .unwrap();

            // The observe connection sends
            // nothing further -- it is simply dropped once
            // `observe_window` returns (protocol 22 never sends `Detach`
            // at all: scrolling goes through `pane.scroll` on the api
            // socket, not this client socket).
            stream
                .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let extra: Result<ClientMessage22, String> = read_frame(&mut stream, MAX_FRAME_SIZE);
            assert_eq!(
                extra.unwrap_err(),
                "unexpected_eof",
                "observe connection must close after the frame, got a different error"
            );
        }
    });

    let lock_dir = fresh_lock_dir("run22");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 22,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect("run_scrollback_links");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["paneId"], "w1:p2");
    assert_eq!(parsed["protocolVersion"], 22);
    assert_eq!(parsed["restore"], "exact");
    let windows = parsed["windows"].as_array().unwrap();
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0]["requestedOffset"], 10);
    assert_eq!(windows[0]["actualOffset"], 10);
    assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
    assert_eq!(windows[1]["requestedOffset"], 20);
    assert_eq!(windows[1]["actualOffset"], 20);
    assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

    // Parse each api_socket request line as
    // JSON and compare `method` by exact equality, not substring match.
    let sent = api_thread.join().unwrap();
    for line in &sent {
        let value: serde_json::Value = serde_json::from_str(line).expect("valid json request line");
        let method = value["method"].as_str().expect("method field present");
        assert!(
            method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
            "disallowed api method (allow-list): {method}"
        );
    }
    observe_thread.join().unwrap();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

// -- 17/20 end-to-end integration (the happy-path integration test
// previously only
// covered protocol 22) --

#[test]
fn run_scrollback_links_protocol17_happy_path_two_windows_restores_to_bottom() {
    // A real pty+process, sized exactly 80x24 with no pixel geometry
    // (xpixel/ypixel=0), so `resolve_size_fail_closed`'s
    // `winsize::real_size` call succeeds for real and returns exactly
    // the same cols/rows/cell_px this test already asserted when the
    // dimensions were still hardcoded -- see `spawn_real_pty_process`.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run17-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0), // 1. record_original_position: o0=0
        pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed's pane.process_info
        pane_info_response(10), // 3. window1 move: confirm poll (AttachScroll has no response)
        pane_info_response(20), // 4. window2 move: confirm poll
        pane_info_response(20), // 5. restore: read o1 -> 20 (o0=0 -> bottom restore)
        pane_info_response(0),  // 6. restore: confirm poll -> 0
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    // `params.socket`: one persistent attach connection (open_round_trip,
    // held for both window moves and the final restore's AttachScroll),
    // plus one fresh connection per window for `observe_window`).
    let client_path = json_socket_path("run17-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        // Allow-list: every frame read on this connection is
        // matched against an exhaustive allow-list (Hello/AttachTerminal/
        // AttachScroll/ObserveTerminal/Resize/Detach) -- `other => panic!`
        // fails closed on Input/ClipboardImage/InputEvents/ControlTerminal.
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage17::Hello { cols, rows, .. } => {
                assert_eq!(cols, 80, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut attach,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match attach_terminal {
            ClientMessage17::AttachTerminal { terminal_id, .. } => {
                // Note: this
                // representative happy-path test's fake previously
                // didn't check terminal_id at all, which is exactly how
                // the pane-notation-vs-terminal_id bug slipped past
                // the other tests before the dedicated regression tests existed.
                assert_eq!(
                    terminal_id, "term-abc",
                    "AttachTerminal.terminal_id must be pane.get's terminal_id, not params.pane"
                );
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage17::Resize { cols, rows, .. } => {
                assert_eq!(cols, 80, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut attach,
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();

        // window1 move: 0 -> 10 (further from bottom) -> Up, 10 lines.
        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0, "0 = Up into scrollback");
                assert_eq!(lines, 10);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        let mut obs1 = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage17::Hello { cols, rows, .. } => {
                assert_eq!(cols, 80, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut obs1,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let observe: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match observe {
            ClientMessage17::ObserveTerminal { .. } => {}
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage17::Resize { cols, rows, .. } => {
                assert_eq!(cols, 80, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let bytes0 = b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
        write_frame(
            &mut obs1,
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: bytes0,
            }),
        )
        .unwrap();
        // The observe connection is simply
        // dropped once `observe_window` returns -- never `Detach`.
        obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage17, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "obs1 must close after the frame, got a different error"
        );

        // window2 move: 10 -> 20 -> Up, 10 lines.
        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0);
                assert_eq!(lines, 10);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        let mut obs2 = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage17::Hello { cols, rows, .. } => {
                assert_eq!(cols, 80, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut obs2,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let observe: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match observe {
            ClientMessage17::ObserveTerminal { .. } => {}
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage17 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage17::Resize { cols, rows, .. } => {
                assert_eq!(cols, 80, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let bytes1 = b"\x1b[1;1H\x1b]8;;https://example.com/w1\x1b\\link1\x1b]8;;\x1b\\".to_vec();
        write_frame(
            &mut obs2,
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: bytes1,
            }),
        )
        .unwrap();
        obs2.set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage17, String> = read_frame(&mut obs2, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "obs2 must close after the frame, got a different error"
        );

        // restore: bottom -> AttachScroll{Down, 65535}.
        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 65535);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        // `close_round_trip` sends `Detach` and
        // nothing after it.
        let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(detach, ClientMessage17::Detach),
            "expected Detach, got {:?}",
            detach
        );
        attach
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage17, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "attach connection must close after Detach, got a different error"
        );
    });

    let lock_dir = fresh_lock_dir("run17");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect("run_scrollback_links");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["paneId"], "w1:p2");
    assert_eq!(parsed["protocolVersion"], 17);
    assert_eq!(parsed["restore"], "exact");
    let windows = parsed["windows"].as_array().unwrap();
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0]["requestedOffset"], 10);
    assert_eq!(windows[0]["actualOffset"], 10);
    assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
    assert_eq!(windows[1]["requestedOffset"], 20);
    assert_eq!(windows[1]["actualOffset"], 20);
    assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

    // Parse each api_socket request line as
    // JSON and compare `method` by exact equality, not substring match.
    let sent = api_thread.join().unwrap();
    for line in &sent {
        let value: serde_json::Value = serde_json::from_str(line).expect("valid json request line");
        let method = value["method"].as_str().expect("method field present");
        assert!(
            method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
            "disallowed api method (allow-list): {method}"
        );
    }
    client_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

#[test]
fn run_scrollback_links_protocol20_happy_path_two_windows_restores_to_bottom() {
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 100, 0, 0);
    let api_path = json_socket_path("run20-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0), // 1. record_original_position: o0=0
        pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed's pane.process_info
        pane_info_response(10),                      // 3. window1 move: confirm poll
        pane_info_response(20),                      // 4. window2 move: confirm poll
        pane_info_response(20), // 5. restore: read o1 -> 20 (o0=0 -> bottom restore)
        pane_info_response(0),  // 6. restore: confirm poll -> 0
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run20-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        // Allow-list: every frame read on this connection is
        // matched against an exhaustive allow-list (Hello/AttachTerminal/
        // AttachScroll/ObserveTerminal/Resize/Detach) -- `other => panic!`
        // fails closed on Input/ClipboardImage/InputEvents/ControlTerminal.
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage20::Hello { cols, rows, .. } => {
                assert_eq!(cols, 100, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut attach,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let attach_terminal: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match attach_terminal {
            ClientMessage20::AttachTerminal { terminal_id, .. } => {
                // As in the protocol17 happy-path test above: the fake checks terminal_id.
                assert_eq!(
                    terminal_id, "term-abc",
                    "AttachTerminal.terminal_id must be pane.get's terminal_id, not params.pane"
                );
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage20::Resize { cols, rows, .. } => {
                assert_eq!(cols, 100, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut attach,
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 100,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();

        let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage20::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0, "0 = Up into scrollback");
                assert_eq!(lines, 10);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        let mut obs1 = accept_with_deadline(&client_listener);
        let hello: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage20::Hello { cols, rows, .. } => {
                assert_eq!(cols, 100, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut obs1,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let observe: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match observe {
            ClientMessage20::ObserveTerminal { .. } => {}
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage20 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage20::Resize { cols, rows, .. } => {
                assert_eq!(cols, 100, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let bytes0 = b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
        write_frame(
            &mut obs1,
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 100,
                height: 24,
                full: true,
                bytes: bytes0,
            }),
        )
        .unwrap();
        // The observe connection is simply
        // dropped once `observe_window` returns -- never `Detach`.
        obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage20, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "obs1 must close after the frame, got a different error"
        );

        let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage20::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0);
                assert_eq!(lines, 10);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        let mut obs2 = accept_with_deadline(&client_listener);
        let hello: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match hello {
            ClientMessage20::Hello { cols, rows, .. } => {
                assert_eq!(cols, 100, "Hello cols must be params.cols");
                assert_eq!(rows, 24, "Hello rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        write_frame(
            &mut obs2,
            &ServerMessage20::Welcome {
                version: 20,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let observe: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match observe {
            ClientMessage20::ObserveTerminal { .. } => {}
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let resize: ClientMessage20 = read_frame(&mut obs2, MAX_FRAME_SIZE).unwrap();
        match resize {
            ClientMessage20::Resize { cols, rows, .. } => {
                assert_eq!(cols, 100, "Resize cols must be params.cols");
                assert_eq!(rows, 24, "Resize rows must be pane.get's viewport_rows");
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }
        let bytes1 = b"\x1b[1;1H\x1b]8;;https://example.com/w1\x1b\\link1\x1b]8;;\x1b\\".to_vec();
        write_frame(
            &mut obs2,
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 100,
                height: 24,
                full: true,
                bytes: bytes1,
            }),
        )
        .unwrap();
        obs2.set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage20, String> = read_frame(&mut obs2, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "obs2 must close after the frame, got a different error"
        );

        let scroll_msg: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage20::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 65535);
            }
            other => panic!("disallowed message type (allow-list): {:?}", other),
        }

        // `close_round_trip` sends `Detach` and
        // nothing after it.
        let detach: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(detach, ClientMessage20::Detach),
            "expected Detach, got {:?}",
            detach
        );
        attach
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage20, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
        assert_eq!(
            extra.unwrap_err(),
            "unexpected_eof",
            "attach connection must close after Detach, got a different error"
        );
    });

    let lock_dir = fresh_lock_dir("run20");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 20,
        cols: 100,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect("run_scrollback_links");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["paneId"], "w1:p2");
    assert_eq!(parsed["protocolVersion"], 20);
    assert_eq!(parsed["restore"], "exact");
    let windows = parsed["windows"].as_array().unwrap();
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0]["requestedOffset"], 10);
    assert_eq!(windows[0]["actualOffset"], 10);
    assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
    assert_eq!(windows[1]["requestedOffset"], 20);
    assert_eq!(windows[1]["actualOffset"], 20);
    assert_eq!(windows[1]["links"][0]["url"], "https://example.com/w1");

    // Parse each api_socket request line as
    // JSON and compare `method` by exact equality, not substring match.
    let sent = api_thread.join().unwrap();
    for line in &sent {
        let value: serde_json::Value = serde_json::from_str(line).expect("valid json request line");
        let method = value["method"].as_str().expect("method field present");
        assert!(
            method == "pane.get" || method == "pane.scroll" || method == "pane.process_info",
            "disallowed api method (allow-list): {method}"
        );
    }
    client_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}
