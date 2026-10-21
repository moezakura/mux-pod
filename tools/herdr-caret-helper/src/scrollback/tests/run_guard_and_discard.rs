//! `run_scrollback_links` guard / fail-closed skips and the discard rule for
//! windows whose move did not land.

use super::support::*;
use crate::scrollback::args::DEFAULT_MAX_OUTPUT_BYTES;
use crate::scrollback::*;
use crate::wire::*;
use crate::wire22::{ClientMessage22, ServerMessage22Known};
use std::os::unix::net::UnixListener;

// -- Guard/fail-closed tests ------------------------------------------
//
// Both tests below deliberately do *not* bind a `UnixListener` on
// `params.socket` at all: if a regression ever made `open_round_trip`
// reachable in either scenario, `UnixStream::connect` would fail with
// `RunError::Connect` (no listener exists at that path) rather than the
// test hanging -- so a would-be-attach regression fails loudly as a
// *different*, immediately-visible error variant instead of silently
// passing or deadlocking.

#[test]
fn run_scrollback_links_protocol17_guard_skip_sends_no_attach_and_returns_empty_windows() {
    // o0 = 5 (not already at the bottom) -> the 17/20 guard
    // (`o0 == 0 && max_offset_from_bottom > 0`) fails on its first
    // condition. No `pane.process_info`/`winsize::real_size` call, no
    // attach, no `AttachScroll` -- just the one `record_original_position`
    // `pane.get` read, then an immediate return with `windows: []`.
    let api_path = json_socket_path("run17-guardskip-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [pane_info_response(5)];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let lock_dir = fresh_lock_dir("run17-guardskip");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: "/nonexistent/no-listener-here.sock".to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect(
        "guard-skip must succeed (no attach attempted) even though params.socket has no listener",
    );
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["paneId"], "w1:p2");
    assert_eq!(parsed["protocolVersion"], 17);
    assert_eq!(parsed["restore"], "approximate");
    assert_eq!(
        parsed["windows"].as_array().unwrap().len(),
        0,
        "guard-skip must fetch no windows at all"
    );

    let sent = api_thread.join().unwrap();
    assert_eq!(
        sent.len(),
        1,
        "guard-skip must make exactly one pane.get call and nothing else"
    );
    let value: serde_json::Value = serde_json::from_str(&sent[0]).expect("valid json request");
    assert_eq!(value["method"], "pane.get");

    let _ = std::fs::remove_file(&api_path);
}

#[test]
fn run_scrollback_links_protocol17_guard_skip_on_zero_max_offset_sends_no_attach() {
    // The test
    // above only exercises the guard's *first* condition (`o0 == 0`)
    // failing -- it never exercises the second condition
    // (`max_offset_from_bottom > 0`) on its own, so a mutation that
    // drops the `max_offset_from_bottom > 0` check entirely would still
    // pass every existing test. Here `o0 == 0` (already at the bottom)
    // but `max_offset_from_bottom == 0` (no scrollback at all to move
    // into) -- the guard must still fail and skip the whole round
    // trip: no `pane.process_info`/`winsize::real_size` call, no
    // attach, no `AttachScroll`, `windows: []`.
    let api_path = json_socket_path("run17-guardskip-zeromax-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response_with_max(0, 0), // 1. record_original_position: o0=0, max=0
        pane_info_response_with_max(0, 0), // 2. restore's `!moved, o0==0` confirmatory pane.get -> still 0 -> Exact
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let lock_dir = fresh_lock_dir("run17-guardskip-zeromax");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: "/nonexistent/no-listener-here.sock".to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params)
        .expect("guard-skip (max_offset_from_bottom == 0) must succeed with no attach attempted");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["restore"], "exact");
    assert_eq!(
        parsed["windows"].as_array().unwrap().len(),
        0,
        "guard-skip must fetch no windows at all"
    );

    let sent = api_thread.join().unwrap();
    assert_eq!(
        sent.len(),
        2,
        "must make exactly record_original_position's pane.get plus restore's \
         confirmatory pane.get -- no pane.process_info call at all"
    );
    for line in &sent {
        let value: serde_json::Value = serde_json::from_str(line).expect("valid json request");
        assert_eq!(
            value["method"], "pane.get",
            "guard-skip must never call pane.process_info"
        );
    }

    let _ = std::fs::remove_file(&api_path);
}

#[test]
fn run_scrollback_links_protocol17_winsize_failure_fails_closed_with_no_attach() {
    // o0 = 0, max_offset_from_bottom = 9999 (default) -> the guard
    // passes, so `resolve_size_fail_closed` is reached and calls
    // `pane.process_info`. Its response names a `shell_pid` that
    // (practically) never corresponds to a running process, so
    // `winsize::real_size` genuinely fails with `ProcessNotRunning` --
    // this is a real failure of the real function, not a mocked-away
    // shortcut. Per the fail-closed rule, this must fail the
    // *whole* run with `RunError::WinsizeUnavailable` before any attach
    // is attempted.
    let bogus_shell_pid: u32 = u32::MAX;
    let api_path = json_socket_path("run17-winsizefail-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0),
        pane_process_info_response(bogus_shell_pid),
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let lock_dir = fresh_lock_dir("run17-winsizefail");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: "/nonexistent/no-listener-here.sock".to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let err = run_scrollback_links(&params)
        .expect_err("a winsize::real_size failure must fail the whole run");
    assert!(
        matches!(err, RunError::WinsizeUnavailable(_)),
        "expected WinsizeUnavailable, got {:?}",
        err
    );
    assert!(
        err.json().contains("winsize_unavailable"),
        "RunError::json() kind must be winsize_unavailable, got {}",
        err.json()
    );

    let sent = api_thread.join().unwrap();
    assert_eq!(
        sent.len(),
        2,
        "must make exactly pane.get + pane.process_info, no attach-adjacent calls"
    );
    let v0: serde_json::Value = serde_json::from_str(&sent[0]).expect("valid json request");
    assert_eq!(v0["method"], "pane.get");
    let v1: serde_json::Value = serde_json::from_str(&sent[1]).expect("valid json request");
    assert_eq!(v1["method"], "pane.process_info");

    let _ = std::fs::remove_file(&api_path);
}

// -- Discard rule:
// 17/20 only; condition is "a move was dispatched
// but the confirmed offset (including a poll timeout's last-observed
// value) is unchanged from this window's own pre-move offset" -- not
// "actual != requested" (hitting the scrollback's range end is a
// legitimate, non-discarded outcome).

#[test]
fn run_scrollback_links_protocol17_first_window_never_moves_is_discarded_with_no_restore_sent() {
    // Single window (target 10); every poll of its AttachScroll Up(10)
    // confirms the offset is still 0 (stuck -- e.g. an alt-screen/
    // mouse-tracking mode absorbing the input), so `poll_scroll_until`
    // exhausts its budget and returns the last-observed value (`Ok`,
    // not `Err`). Expected: the window is discarded (not observed, not
    // in `fetches`), and since nothing in this run ever genuinely
    // moved, `restore_position` must take the "nothing to restore, no
    // restore command sent" branch -- confirmed here by the
    // attach connection never seeing anything beyond the dispatched
    // AttachScroll and the final `Detach`.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run17-discard1-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let stuck_at_zero = pane_info_response_with_max(0, 9999);
    let mut responses: Vec<String> = vec![
        pane_info_response_with_max(0, 9999), // 1. record_original_position: o0=0, max=9999
        pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed
    ];
    for _ in 0..10 {
        // 3..=12. window1's AttachScroll Up(10) poll: stuck at 0 for
        // every one of SCROLL_POLL_MAX_ATTEMPTS attempts.
        responses.push(stuck_at_zero.clone());
    }
    responses.push(stuck_at_zero.clone()); // 13. restore's `!moved, o0==0` confirmatory pane.get -> still 0 -> Exact
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run17-discard1-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage17::Hello { .. }),
            "{:?}",
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
        assert!(
            matches!(attach_terminal, ClientMessage17::AttachTerminal { .. }),
            "{:?}",
            attach_terminal
        );
        let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage17::Resize { .. }),
            "{:?}",
            resize
        );
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

        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0, "0 = Up into scrollback");
                assert_eq!(lines, 10);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }

        // The discarded window must never be observed: `close_round_trip`
        // sends `Detach` directly next, with no intervening ObserveTerminal
        // handshake and no restore AttachScroll (restore never touches this
        // attach session at all for the `!moved, o0 == 0` branch -- it is
        // pure `pane.get` over the api socket).
        let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(matches!(detach, ClientMessage17::Detach), "{:?}", detach);
        attach
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage17, String> = read_frame(&mut attach, MAX_FRAME_SIZE);
        assert_eq!(extra.unwrap_err(), "unexpected_eof");

        // No second connection (an observe attempt) must ever arrive.
        client_listener.set_nonblocking(true).unwrap();
        assert!(
            client_listener.accept().is_err(),
            "a discarded window must never open an observe connection"
        );
    });

    let lock_dir = fresh_lock_dir("run17-discard1");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect("run_scrollback_links");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(
        parsed["windows"].as_array().unwrap().len(),
        0,
        "the only window never moved, so it must be discarded, not fetched"
    );
    assert_eq!(
        parsed["restore"], "exact",
        "nothing ever moved, so restore must take the no-op `!moved, o0 == 0` branch"
    );

    client_thread.join().unwrap();
    let _ = api_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

#[test]
fn run_scrollback_links_protocol17_second_window_never_moves_keeps_first_and_restores_bottom_once()
{
    // window1 (target 10) genuinely moves 0 -> 10; window2 (target 20)
    // is stuck at 10 for every poll attempt (same "last-observed value"
    // timeout shape as the single-window test above). Expected: only
    // window1's fetch survives, window2 is never observed, processing
    // stops after window2 (no further windows -- none exist here, but
    // the discard `break` is what stops it), and because window1 did
    // genuinely move, restore still runs its normal bottom-restore
    // (`AttachScroll{Down, 65535}`) exactly once.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run17-discard2-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let stuck_at_ten = pane_info_response_with_max(10, 9999);
    let mut responses: Vec<String> = vec![
        pane_info_response_with_max(0, 9999), // 1. record_original_position: o0=0
        pane_process_info_response(real_shell.id()), // 2. resolve_size_fail_closed
        pane_info_response_with_max(10, 9999), // 3. window1 move poll: settles at 10 immediately
    ];
    for _ in 0..10 {
        // 4..=13. window2's AttachScroll Up(10) poll: stuck at 10 (its
        // own pre-move offset) for every attempt.
        responses.push(stuck_at_ten.clone());
    }
    responses.push(pane_info_response_with_max(10, 9999)); // 14. restore: read o1 -> 10 (t=10, no concurrent reset)
    responses.push(pane_info_response_with_max(0, 9999)); // 15. restore: confirm poll after Down 65535 -> 0
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run17-discard2-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        let mut attach = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage17::Hello { .. }),
            "{:?}",
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
        assert!(
            matches!(attach_terminal, ClientMessage17::AttachTerminal { .. }),
            "{:?}",
            attach_terminal
        );
        let resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage17::Resize { .. }),
            "{:?}",
            resize
        );
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

        // window1: AttachScroll Up(10), 0 -> 10.
        let scroll1: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll1 {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0);
                assert_eq!(lines, 10);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }

        // window1's observe (it genuinely moved, so it must be fetched).
        let mut obs1 = accept_with_deadline(&client_listener);
        let hello: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage17::Hello { .. }),
            "{:?}",
            hello
        );
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
        assert!(
            matches!(observe, ClientMessage17::ObserveTerminal { .. }),
            "{:?}",
            observe
        );
        let resize: ClientMessage17 = read_frame(&mut obs1, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage17::Resize { .. }),
            "{:?}",
            resize
        );
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
        obs1.set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let extra: Result<ClientMessage17, String> = read_frame(&mut obs1, MAX_FRAME_SIZE);
        assert_eq!(extra.unwrap_err(), "unexpected_eof");

        // window2: AttachScroll Up(10), stuck at 10 -- never observed.
        let scroll2: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll2 {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0);
                assert_eq!(lines, 10);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }

        // Restore: window1 genuinely moved, so a real bottom restore is
        // still sent exactly once (`AttachScroll{Down, 65535}`), then
        // `Detach`. No third connection (window2's would-be observe)
        // is ever accepted.
        let restore_scroll: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match restore_scroll {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 65535);
            }
            other => panic!("expected the bottom-restore AttachScroll, got {:?}", other),
        }
        let detach: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        assert!(matches!(detach, ClientMessage17::Detach), "{:?}", detach);

        client_listener.set_nonblocking(true).unwrap();
        assert!(
            client_listener.accept().is_err(),
            "window2 was discarded, so it must never open an observe connection"
        );
    });

    let lock_dir = fresh_lock_dir("run17-discard2");
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
    let windows = parsed["windows"].as_array().unwrap();
    assert_eq!(
        windows.len(),
        1,
        "only window1 must survive; window2 is discarded"
    );
    assert_eq!(windows[0]["requestedOffset"], 10);
    assert_eq!(windows[0]["actualOffset"], 10);
    assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");
    assert_eq!(
        parsed["restore"], "exact",
        "window1 genuinely moved, so a real bottom restore must still run"
    );

    client_thread.join().unwrap();
    let _ = api_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

#[test]
fn run_scrollback_links_protocol22_window_that_does_not_move_is_still_observed_not_discarded() {
    // Note: the
    // discard rule is 17/20-only; protocol 22's
    // `pane.scroll` path always dispatches a request (`attempted` is
    // unconditionally `true` in `move_to_offset`'s `RoundTripHandle::
    // Api` branch) and, when the requested target already equals the
    // pane's current position, the confirmed offset is trivially
    // unchanged from the pre-move offset -- exactly the shape the
    // 17/20 discard condition checks for. This must *not* discard the
    // window for protocol 22: it must still be observed and kept in
    // `fetches`.
    let api_path = json_socket_path("run22-nodiscard-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response_with_max(15, 9999), // 1. record_original_position: o0=15
        pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong `type` -> fallback
        pane_info_response_with_max(15, 9999), // 3. window0's pane.scroll(target=15) -> still 15
        pane_info_response_with_max(15, 9999), // 4. window0's defensive re-check poll -> still 15
        pane_info_response_with_max(15, 9999), // 5. restore: read o1 -> 15 (t=15, no concurrent reset)
        pane_info_response_with_max(15, 9999), // 6. restore: approximate target o0+(o1-t)=15 -> pane.scroll
        pane_info_response_with_max(15, 9999), // 7. restore: approximate's poll confirm -> 15
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let client_path = json_socket_path("run22-nodiscard-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        // Protocol 22 has no persistent attach session: this is the
        // one-shot observe connection for window0, which must be
        // reached even though the pane never moved.
        let mut obs = accept_with_deadline(&client_listener);
        let hello: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(hello, ClientMessage22::TerminalHello { .. }),
            "{:?}",
            hello
        );
        write_frame(
            &mut obs,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let observe: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(observe, ClientMessage22::ObserveTerminal { .. }),
            "{:?}",
            observe
        );
        let resize: ClientMessage22 = read_frame(&mut obs, MAX_FRAME_SIZE).unwrap();
        assert!(
            matches!(resize, ClientMessage22::Resize { .. }),
            "{:?}",
            resize
        );
        let bytes0 = b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
        write_frame(
            &mut obs,
            &ServerMessage22Known::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: bytes0,
            }),
        )
        .unwrap();
    });

    let lock_dir = fresh_lock_dir("run22-nodiscard");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 22,
        cols: 80,
        windows: vec![15],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let json = run_scrollback_links(&params).expect("run_scrollback_links");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    let windows = parsed["windows"].as_array().unwrap();
    assert_eq!(
        windows.len(),
        1,
        "protocol 22 must never discard a window that didn't move"
    );
    assert_eq!(windows[0]["requestedOffset"], 15);
    assert_eq!(windows[0]["actualOffset"], 15);
    assert_eq!(windows[0]["links"][0]["url"], "https://example.com/w0");

    client_thread.join().unwrap();
    let _ = api_thread.join().unwrap();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}
