//! Regression: the 17/20 `AttachTerminal` must carry the resolved terminal id,
//! not pane notation.

use super::support::*;
use crate::scrollback::args::DEFAULT_MAX_OUTPUT_BYTES;
use crate::scrollback::*;
use crate::wire::*;
use std::os::unix::net::UnixListener;

// -- Regression: `AttachTerminal.terminal_id`
// must be the resolved terminal_id from `pane.get`, never the raw
// `--pane` (pane-target) notation. Real herdr servers (v0.7.5/v0.8.2
// `attach_terminal_client`) match `terminal_id` by exact equality only
// -- they never resolve pane notation themselves (confirmed by reading the
// herdr v0.7.5/v0.8.2 sources and by attaching to a real herdr server).
// Before the fix,
// `open_round_trip` passed `params.pane` ("w1:p2") straight through,
// which a real server rejects with `attach_rejected`; these fake
// servers reproduce that exact real-server behavior (mirroring the
// observed `"terminal attach failed: terminal <id> not found"` reason
// text) so a regression here fails loudly instead of silently passing
// against the previously-lenient fake sockets.
//
// `--window` is deliberately empty in both tests below: this keeps each
// test to exactly one `pane.get` round trip (`record_original_position`
// only -- `restore_position`'s `!moved && o0 != 0` branch then returns
// `Approximate` without any further API call, since `o0` is set to a
// non-zero 5 below), regardless of whether AttachTerminal is accepted
// or rejected, so the fake API server thread never blocks forever
// waiting for a second request that a rejected run would never send.
// An empty `--window` list does *not* skip the attach handshake itself
// (`open_round_trip` runs unconditionally, before the window loop) --
// `attach_reached` below asserts that directly, so a future change that
// accidentally short-circuits attach for an empty window list cannot
// slip past this test as a false GREEN.

#[test]
fn run_scrollback_links_protocol17_attach_terminal_uses_resolved_terminal_id_not_pane_notation() {
    // o0 must be 0 (not the test's original 5): the 17/20 guard
    // now gates attaching at all on
    // `o0 == 0 && max_offset_from_bottom > 0` -- this test's purpose
    // (terminal_id resolution during attach) is
    // independent of the o0 value, so using 0 keeps the regression
    // coverage while still reaching the attach handshake this test
    // asserts on.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run17-termid-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0),
        pane_process_info_response(real_shell.id()),
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run17-termid-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage17::Hello { .. }),
            "expected Hello, got {:?}",
            hello
        );
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
        let terminal_id = match attach_terminal {
            ClientMessage17::AttachTerminal { terminal_id, .. } => terminal_id,
            other => panic!("expected AttachTerminal, got {:?}", other),
        };
        // Explicit proof the attach handshake
        // was actually reached (not just inferred from the overall
        // Result), so an accidental short-circuit for an empty
        // `--window` list cannot pass this test as a false GREEN.
        let attach_reached = true;
        let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage17::Resize { .. }),
            "expected Resize, got {:?}",
            resize
        );

        // Mirrors the real herdr server: exact match against the
        // resolved terminal_id ("term-abc", `pane_info_response`'s
        // fixture value) only -- pane notation ("w1:p2", `params.pane`
        // below) is never resolved server-side.
        if terminal_id == "term-abc" {
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
            let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(detach, ClientMessage17::Detach),
                "expected Detach, got {:?}",
                detach
            );
        } else {
            write_frame(
                &mut attach,
                &ServerMessage17::ServerShutdown {
                    reason: Some(format!(
                        "terminal attach failed: terminal {terminal_id} not found"
                    )),
                },
            )
            .unwrap();
        }
        (terminal_id, attach_reached)
    });

    let lock_dir = fresh_lock_dir("run17-termid");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let result = run_scrollback_links(&params);
    let (sent_terminal_id, attach_reached) = client_thread.join().unwrap();
    assert!(
        attach_reached,
        "open_round_trip must attach even when --window is empty"
    );
    // Checked before the terminal_id equality below so a regression's
    // raw test output shows the *classified* `RunError` (e.g.
    // `AttachRejected("terminal attach failed: terminal w1:p2 not
    // found")`, matching the real server's exact wording) together with
    // what was actually sent, not just a bare string mismatch.
    assert!(
        result.is_ok(),
        "expected success once AttachTerminal carries the resolved terminal_id, \
         got {:?} (sent_terminal_id was {:?}, expected \"term-abc\")",
        result,
        sent_terminal_id
    );
    assert_eq!(
        sent_terminal_id, "term-abc",
        "AttachTerminal.terminal_id must be the resolved terminal_id from pane.get \
         (\"term-abc\"), not the raw --pane notation (\"w1:p2\")"
    );

    api_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

#[test]
fn run_scrollback_links_protocol20_attach_terminal_uses_resolved_terminal_id_not_pane_notation() {
    // See the matching comment in the protocol17 version of this test:
    // o0 must be 0 to satisfy the 17/20 attach guard.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run20-termid-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0),
        pane_process_info_response(real_shell.id()),
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run20-termid-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage20::Hello { .. }),
            "expected Hello, got {:?}",
            hello
        );
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
        let terminal_id = match attach_terminal {
            ClientMessage20::AttachTerminal { terminal_id, .. } => terminal_id,
            other => panic!("expected AttachTerminal, got {:?}", other),
        };
        let attach_reached = true;
        let resize: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage20::Resize { .. }),
            "expected Resize, got {:?}",
            resize
        );

        if terminal_id == "term-abc" {
            write_frame(
                &mut attach,
                &ServerMessage20::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full: true,
                    bytes: vec![],
                }),
            )
            .unwrap();
            let detach: ClientMessage20 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
            assert!(
                matches!(detach, ClientMessage20::Detach),
                "expected Detach, got {:?}",
                detach
            );
        } else {
            write_frame(
                &mut attach,
                &ServerMessage20::ServerShutdown {
                    reason: Some(format!(
                        "terminal attach failed: terminal {terminal_id} not found"
                    )),
                },
            )
            .unwrap();
        }
        (terminal_id, attach_reached)
    });

    let lock_dir = fresh_lock_dir("run20-termid");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 20,
        cols: 80,
        windows: vec![],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let result = run_scrollback_links(&params);
    let (sent_terminal_id, attach_reached) = client_thread.join().unwrap();
    assert!(
        attach_reached,
        "open_round_trip must attach even when --window is empty"
    );
    // Checked before the terminal_id equality below so a regression's
    // raw test output shows the *classified* `RunError` (e.g.
    // `AttachRejected("terminal attach failed: terminal w1:p2 not
    // found")`, matching the real server's exact wording) together with
    // what was actually sent, not just a bare string mismatch.
    assert!(
        result.is_ok(),
        "expected success once AttachTerminal carries the resolved terminal_id, \
         got {:?} (sent_terminal_id was {:?}, expected \"term-abc\")",
        result,
        sent_terminal_id
    );
    assert_eq!(
        sent_terminal_id, "term-abc",
        "AttachTerminal.terminal_id must be the resolved terminal_id from pane.get \
         (\"term-abc\"), not the raw --pane notation (\"w1:p2\")"
    );

    api_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}
