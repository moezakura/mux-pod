//! `run_scrollback_links` failure paths: restore still runs, tracker-rejected
//! windows, and move-response / confirm-poll timeouts.

use super::support::*;
use crate::scrollback::args::DEFAULT_MAX_OUTPUT_BYTES;
use crate::scrollback::*;
use crate::wire::*;
use crate::wire22::{ClientMessage22, ServerMessage22Known};
use std::os::unix::net::UnixListener;

// -- Finally-equivalent restore across failure paths --

#[test]
fn run_scrollback_links_window1_move_failure_still_restores_before_returning_err() {
    // window1's `pane.scroll` fails (no `scroll` field in the response,
    // classified `UnsupportedScroll`) before any window is
    // ever observed. Restore must still run (finally-equivalent)
    // even though nothing was ever confirmed to have moved -- and since
    // nothing actually moved, restore must land on `Exact` via its own
    // fresh `pane.get` read, not by (incorrectly) skipping straight to
    // "nothing to do". `observe_window` must never be reached: the
    // `socket` path below has no listener bound at all, so any attempt
    // to connect to it would itself surface as `RunError::Connect`.
    let api_path = json_socket_path("run22-move-fail-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0), // 1. record_original_position: o0=0
        pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong
        //    `type` tag -> falls back to params.cols/viewport_rows
        pane_info_response_without_scroll(), // 3. window1 move: pane.scroll -> no `scroll` field
        pane_info_response(0), // 4. restore: read o1 -> 0 == o0 -> Exact, no further call
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    let observe_socket = json_socket_path("run22-move-fail-observe-unbound");
    let lock_dir = fresh_lock_dir("run22-move-fail");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: observe_socket.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 22,
        cols: 80,
        windows: vec![10, 20],
        timeout_ms: 5000,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let err = run_scrollback_links(&params).expect_err("window1 move must fail");
    assert!(
        matches!(err, RunError::UnsupportedScroll),
        "expected UnsupportedScroll, got {err:?}"
    );

    // All 4 API responses were consumed (o0 read, the fail-open
    // pane.process_info, the failing move, and the restore's own o1
    // read) -- proving restore ran to completion after the loop's
    // early break, not skipped.
    let sent = api_thread.join().unwrap();
    assert_eq!(sent.len(), 4);
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&observe_socket);
}

#[test]
fn run_scrollback_links_window2_observe_failure_still_restores_from_the_moved_position() {
    // window1's move+observe succeed (position moves to 10, offset
    // tracked); window2's move succeeds (position moves to 20) but its
    // observe connect fails (each window uses its own fresh connection
    // -- no listener is available for the second connection).
    // Restore (finally-equivalent) must still run using the real
    // moved position (20), not the original (0), and must actually
    // attempt a bottom restore rather than treating this as "nothing
    // moved".
    let api_path = json_socket_path("run22-observe-fail-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses = [
        pane_info_response(0), // 1. record_original_position: o0=0
        pane_info_response(0), // 2. resolve_size_fail_open's pane.process_info: wrong `type`
        //    tag -> falls back to params.cols/viewport_rows
        pane_info_response(10), // 3. window1 move: pane.scroll -> 10
        pane_info_response(10), // 4. window1 move: confirm poll
        pane_info_response(20), // 5. window2 move: pane.scroll -> 20
        pane_info_response(20), // 6. window2 move: confirm poll
        pane_info_response(20), // 7. restore: read o1 -> 20 (t=20, o0=0 -> not equal -> bottom restore)
        pane_info_response(0),  // 8. restore: pane.scroll(0) -> 0
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });

    // Accepts exactly one connection (window1's observe), then the
    // listener is dropped immediately -- window2's connect then fails
    // with `RunError::Connect` (ECONNREFUSED against the orphaned
    // socket file), simulating an observation failure mid-loop.
    //
    // Race (flaky under host
    // load): the listener used to be dropped only implicitly, at the
    // end of this closure -- i.e. *after* the full window1 Hello/
    // Welcome/Observe/Resize/Terminal exchange below. Window2's
    // connect() happens on the main thread as soon as it reads back
    // window1's Terminal frame, which races this thread's own
    // (possibly descheduled, under load) return from that last
    // `write_frame` call back to the implicit listener drop. If
    // window2's connect() lands first, it can be queued into the
    // kernel's listen backlog while the socket is still nominally
    // open, succeeding instead of failing with ECONNREFUSED, and the
    // run then times out waiting for a reply instead of returning
    // `RunError::Connect` -- an intermittent failure with no code
    // defect, just a wider-than-necessary window for the race.
    // Dropping the listener right after `accept()` (before doing any
    // of the window1 IO) closes that window entirely: by the time
    // window2 is attempted, window1's full synchronous exchange has
    // already completed (the main thread's read returned), so the
    // listener has unconditionally been closed long before.
    let client_path = json_socket_path("run22-observe-fail-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let observe_thread = std::thread::spawn(move || {
        let mut stream = accept_with_deadline(&client_listener);
        drop(client_listener);
        let _hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut stream,
            &ServerMessage22Known::Welcome {
                version: 22,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
        let bytes = b"\x1b[1;1H\x1b]8;;https://example.com/w0\x1b\\link0\x1b]8;;\x1b\\".to_vec();
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
        // (listener was already dropped right after accept(), above)
    });

    let lock_dir = fresh_lock_dir("run22-observe-fail");
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

    let err = run_scrollback_links(&params).expect_err("window2 observe must fail");
    assert!(
        matches!(err, RunError::Connect),
        "expected Connect, got {err:?}"
    );

    // All 8 API responses were consumed, including the fail-open
    // pane.process_info, the restore's o1 read, and the
    // bottom-restore `pane.scroll(0)` call -- proving restore ran
    // using the real moved-to position (20), not skipped and not
    // restored from the stale original (0).
    let sent = api_thread.join().unwrap();
    assert_eq!(sent.len(), 8);
    assert!(
        sent[7].contains("\"offset_from_bottom\":0"),
        "restore must target the bottom (o0=0)"
    );
    observe_thread.join().unwrap();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}

// -- A window whose frame the tracker rejects (or that is not a
// full redraw) becomes an empty `truncated` window; the other windows
// and the restore carry on. Only when every window is rejected does
// the run fail with `render_rejected`. --

/// Protocol 22, two windows (offsets 10 and 20): serves `frames[i]`
/// (`bytes`, `full`) as window i's `TerminalAnsi` frame, with the same
/// 8-call api sequence as the happy-path test. Returns the run result
/// and the api requests actually sent.
fn run22_two_windows_with_frames(
    tag: &str,
    frames: [(&'static [u8], bool); 2],
) -> (Result<String, RunError>, Vec<String>) {
    let api_path = json_socket_path(&format!("run22-f3-{tag}-api"));
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let responses: Vec<String> = vec![
        pane_info_response(0),
        pane_info_response(0),
        pane_info_response(10),
        pane_info_response(10),
        pane_info_response(20),
        pane_info_response(20),
        pane_info_response(20),
        pane_info_response(0),
    ];
    let api_thread = std::thread::spawn(move || {
        let response_refs: Vec<&str> = responses.iter().map(String::as_str).collect();
        serve_sequence(api_listener, &response_refs)
    });
    let client_path = json_socket_path(&format!("run22-f3-{tag}-client"));
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let observe_thread = std::thread::spawn(move || {
        for (bytes, full) in frames {
            let mut stream = accept_with_deadline(&client_listener);
            let _hello: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut stream,
                &ServerMessage22Known::Welcome {
                    version: 22,
                    encoding: RenderEncoding::TerminalAnsi,
                    error: None,
                },
            )
            .unwrap();
            let _observe: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            let _resize: ClientMessage22 = read_frame(&mut stream, MAX_FRAME_SIZE).unwrap();
            write_frame(
                &mut stream,
                &ServerMessage22Known::Terminal(TerminalFrame {
                    seq: 1,
                    width: 80,
                    height: 24,
                    full,
                    bytes: bytes.to_vec(),
                }),
            )
            .unwrap();
            stream
                .set_read_timeout(Some(std::time::Duration::from_secs(2)))
                .unwrap();
            let _: Result<ClientMessage22, String> = read_frame(&mut stream, MAX_FRAME_SIZE);
        }
    });
    let lock_dir = fresh_lock_dir(&format!("run22-f3-{tag}"));
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
    let result = run_scrollback_links(&params);
    let sent = api_thread.join().unwrap();
    observe_thread.join().unwrap();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
    (result, sent)
}

const F3_GOOD: &[u8] = b"\x1b[1;1H\x1b]8;;https://example.com/ok\x1b\\link\x1b]8;;\x1b\\";
// An unknown CSI final byte: `TrackError::UnknownSequence` (not
// localizable to one link).
const F3_BAD: &[u8] = b"\x1b[1;1H\x1b[5x";

#[test]
fn run_scrollback_links_one_tracker_rejected_window_becomes_truncated_others_and_restore_continue()
{
    let (result, sent) = run22_two_windows_with_frames("trk", [(F3_BAD, true), (F3_GOOD, true)]);
    let json = result.expect("a single rejected window must not fail the run");
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["restore"], "exact");
    let w = parsed["windows"].as_array().unwrap();
    assert_eq!(w.len(), 2);
    assert_eq!(w[0]["requestedOffset"], 10);
    assert_eq!(w[0]["truncated"], true);
    assert_eq!(w[0]["links"].as_array().unwrap().len(), 0);
    assert_eq!(w[0]["rowHashes"].as_array().unwrap().len(), 0);
    // Frame size of a tracker-rejected window is the real frame's.
    assert_eq!(w[0]["frameWidth"], 80);
    assert_eq!(w[0]["frameHeight"], 24);
    assert_eq!(w[1]["truncated"], false);
    assert_eq!(w[1]["links"][0]["url"], "https://example.com/ok");
    // The restore (read o1 + scroll to bottom) was still sent.
    assert_eq!(sent.len(), 8);
    assert!(sent[7].contains("\"offset_from_bottom\":0"));
}

#[test]
fn run_scrollback_links_one_non_full_window_becomes_truncated_with_requested_size() {
    let (result, sent) = run22_two_windows_with_frames("nf", [(F3_GOOD, true), (F3_GOOD, false)]);
    let json = result.expect("a non-full window must not fail the run");
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    let w = parsed["windows"].as_array().unwrap();
    assert_eq!(w.len(), 2);
    assert_eq!(w[0]["truncated"], false);
    assert_eq!(w[0]["links"][0]["url"], "https://example.com/ok");
    assert_eq!(w[1]["requestedOffset"], 20);
    assert_eq!(w[1]["truncated"], true);
    assert_eq!(w[1]["links"].as_array().unwrap().len(), 0);
    assert_eq!(w[1]["rowHashes"].as_array().unwrap().len(), 0);
    // No frame is available: the size used for the observation
    // (params.cols = 80, pane.get viewport_rows = 24) is reported.
    assert_eq!(w[1]["frameWidth"], 80);
    assert_eq!(w[1]["frameHeight"], 24);
    assert_eq!(sent.len(), 8);
    assert!(sent[7].contains("\"offset_from_bottom\":0"));
}

#[test]
fn run_scrollback_links_all_windows_rejected_fails_with_render_rejected_after_restore() {
    let (result, sent) = run22_two_windows_with_frames("all", [(F3_BAD, true), (F3_GOOD, false)]);
    let err = result.expect_err("every window rejected must fail the run");
    assert!(matches!(err, RunError::RenderRejected(_)), "got {err:?}");
    assert_eq!(sent.len(), 8, "restore must still run");
    assert!(sent[7].contains("\"offset_from_bottom\":0"));
}

// -- "send succeeded, but the
// confirmation/response wait then timed out" must still restore, for
// both protocol 22 (pane.scroll's own response wait) and 17/20
// (AttachScroll's follow-up poll). --

#[test]
fn run_scrollback_links_protocol22_move_response_wait_timeout_still_restores() {
    // window1's `pane.scroll` request reaches the server (connect+write
    // succeed -- `attempted = true`), but the server never answers, so
    // the response wait itself times out (mirrors
    // `tests/api_client.rs`'s `no_response_before_deadline_is_timeout`).
    let api_path = json_socket_path("run22-move-timeout-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let resp0 = pane_info_response(0);
    let resp_procinfo = pane_info_response(0); // wrong `type` tag -> resolve_size_fail_open fallback
    let resp0b = pane_info_response(0);
    let api_thread = std::thread::spawn(move || {
        let entries = [
            Some(resp0.as_str()),         // 1. record_original_position: o0=0
            Some(resp_procinfo.as_str()), // 2. resolve_size_fail_open's pane.process_info
            None,                         // 3. window1 move: pane.scroll sent, never answered
            //    (last_move_confirmed=false)
            Some(resp0b.as_str()), // 4. restore: o0=0 && !last_move_confirmed -> sends the
                                   //    bottom restore unconditionally, WITHOUT reading o1
                                   //    first -> pane.scroll(0) -> 0
        ];
        serve_sequence_with_stall(api_listener, &entries)
    });

    let observe_socket = json_socket_path("run22-move-timeout-observe-unbound");
    let lock_dir = fresh_lock_dir("run22-move-timeout");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: observe_socket.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 22,
        cols: 80,
        windows: vec![10],
        timeout_ms: 200,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let err = run_scrollback_links(&params).expect_err("window1 move response wait must time out");
    assert!(
        matches!(err, RunError::Timeout),
        "expected Timeout, got {err:?}"
    );

    // All 4 entries were consumed -- including the fail-open
    // pane.process_info and the unconditional bottom-restore call --
    // proving restore ran to completion despite the timeout, not
    // skipped because `t` stayed stale at o0.
    let sent = api_thread.join().unwrap();
    assert_eq!(sent.len(), 4);
    assert!(sent[3].contains("\"method\":\"pane.scroll\""));
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&observe_socket);
}

#[test]
fn run_scrollback_links_protocol17_move_confirm_poll_timeout_still_restores() {
    // window1's `AttachScroll` send succeeds (over the attach
    // connection, which never itself responds to `AttachScroll` by
    // design) but the follow-up confirmation `pane.get` poll (over the
    // separate api_socket) then times out. Restore must still run --
    // and, since the caller's `t` is now kept at the *attempted* target
    // (10) rather than staying stale at o0, the
    // approximate math would use `t=10` correctly if o0 were nonzero;
    // here o0=0 so it goes through the unconditional bottom-restore path.
    let (mut real_shell, _real_pty_master) = spawn_real_pty_process(24, 80, 0, 0);
    let api_path = json_socket_path("run17-move-timeout-api");
    let api_listener = UnixListener::bind(&api_path).unwrap();
    let resp0 = pane_info_response(0);
    let resp_procinfo = pane_process_info_response(real_shell.id());
    let resp0b = pane_info_response(0);
    let api_thread = std::thread::spawn(move || {
        let entries = [
            Some(resp0.as_str()),         // 1. record_original_position: o0=0
            Some(resp_procinfo.as_str()), // 2. resolve_size_fail_closed's pane.process_info
            None,                         // 3. window1 move: confirm poll, never answered
            //    (last_move_confirmed=false)
            Some(resp0b.as_str()), // 4. restore: o0=0 && !last_move_confirmed -> sends the
                                   //    bottom restore unconditionally, no o1 read first ->
                                   //    confirm poll -> 0
        ];
        serve_sequence_with_stall(api_listener, &entries)
    });

    let client_path = json_socket_path("run17-move-timeout-client");
    let client_listener = UnixListener::bind(&client_path).unwrap();
    let client_thread = std::thread::spawn(move || {
        let mut attach = accept_with_deadline(&client_listener);
        let _hello: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        write_frame(
            &mut attach,
            &ServerMessage17::Welcome {
                version: 17,
                encoding: RenderEncoding::TerminalAnsi,
                error: None,
            },
        )
        .unwrap();
        let _attach_terminal: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        let _resize: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
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

        // window1 move: 0 -> 10 -> Up, 10 lines. Sent successfully; its
        // poll (over api_socket) is what times out, not this send.
        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 0);
                assert_eq!(lines, 10);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }

        // restore: o0=0 -> bottom -> AttachScroll{Down, 65535}.
        let scroll_msg: ClientMessage17 = read_frame(&mut attach, MAX_FRAME_SIZE).unwrap();
        match scroll_msg {
            ClientMessage17::AttachScroll {
                direction, lines, ..
            } => {
                assert_eq!(direction, 1, "1 = Down towards the bottom");
                assert_eq!(lines, 65535);
            }
            other => panic!("expected AttachScroll, got {:?}", other),
        }
    });

    let lock_dir = fresh_lock_dir("run17-move-timeout");
    let params = ScrollbackParams {
        api_socket: api_path.to_str().unwrap().to_owned(),
        socket: client_path.to_str().unwrap().to_owned(),
        pane: "w1:p2".to_owned(),
        protocol: 17,
        cols: 80,
        windows: vec![10],
        timeout_ms: 200,
        restore_budget_ms: 5000,
        max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        lock_dir: lock_dir.path().to_str().unwrap().to_owned(),
    };

    let err = run_scrollback_links(&params).expect_err("window1 confirm poll must time out");
    assert!(
        matches!(err, RunError::Timeout),
        "expected Timeout, got {err:?}"
    );

    let sent = api_thread.join().unwrap();
    assert_eq!(sent.len(), 4);
    client_thread.join().unwrap();
    let _ = real_shell.kill();
    let _ = real_shell.wait();
    let _ = std::fs::remove_file(&api_path);
    let _ = std::fs::remove_file(&client_path);
}
