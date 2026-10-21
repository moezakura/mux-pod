//! `record_original_position` and `move_to_offset`: pane scroll offset reads,
//! absolute (22) and attach-based (17/20) moves, and their confirmation polls.
//!
//! The 17/20 cases reuse `attach::Attach17`/`Attach20`'s own `from_stream`
//! (over `UnixStream::pair()`, no filesystem socket needed).

use super::support::*;
use crate::attach::{Attach17, Attach20};
use crate::frame_io::read_frame_deadline;
use crate::scrollback::*;
use crate::wire::*;
use std::os::unix::net::{UnixListener, UnixStream};

#[test]
fn record_original_position_reads_offset_and_viewport_rows() {
    let path = json_socket_path("record-original");
    let listener = UnixListener::bind(&path).unwrap();
    let response = pane_info_response(31);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let original = record_original_position(path.to_str().unwrap(), "w1:p2", deadline)
        .expect("record_original_position");
    assert_eq!(original.offset_from_bottom, 31);
    assert_eq!(original.viewport_rows, 24);
    assert_eq!(
        original.terminal_id, "term-abc",
        "must carry pane_info's terminal_id"
    );
    let sent = t.join().unwrap();
    assert!(sent[0].contains("\"method\":\"pane.get\""));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn move_to_offset_protocol22_sends_absolute_pane_scroll_then_confirms() {
    let path = json_socket_path("move22");
    let listener = UnixListener::bind(&path).unwrap();
    // First response: `pane.scroll`'s own result. Second: the
    // defensive `pane.get` re-check poll (settled on the first try).
    let scroll_resp = pane_info_response(12);
    let poll_resp = pane_info_response(12);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&scroll_resp, &poll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let mut handle = RoundTripHandle::Api;
    let (attempted, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        0,
        12,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert!(attempted, "protocol 22 always dispatches pane.scroll");
    assert_eq!(confirmed.offset_from_bottom, 12);
    let sent = t.join().unwrap();
    assert!(sent[0].contains("\"method\":\"pane.scroll\""));
    assert!(sent[0].contains("\"offset_from_bottom\":12"));
    assert!(sent[1].contains("\"method\":\"pane.get\""));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn move_to_offset_protocol17_sends_attach_scroll_up_and_confirms_via_poll() {
    // Fake attach server (like tests/attach.rs's accept_and_confirm17)
    // over UnixStream::pair(), plus a separate fake JSON listener for
    // the confirmation poll (move_to_offset's poll connects by path,
    // independent of the attach session's own stream).
    let (client, mut server) = UnixStream::pair().unwrap();
    let attach_thread = std::thread::spawn(move || {
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
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        // Now expect the AttachScroll this test's move_to_offset call
        // should send (current=5, target=20 -> Up, 15 lines).
        let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        scroll_msg
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach17::from_stream(
        client,
        "w1:p2",
        crate::winsize::Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("attach17");
    let mut handle = RoundTripHandle::Attach17(session);

    let path = json_socket_path("move17");
    let listener = UnixListener::bind(&path).unwrap();
    let poll_resp = pane_info_response(20);
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

    let (attempted, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        5,
        20,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert!(attempted, "a nonzero relative delta must be dispatched");
    assert_eq!(confirmed.offset_from_bottom, 20);

    let scroll_msg = attach_thread.join().unwrap();
    match scroll_msg {
        ClientMessage17::AttachScroll {
            direction, lines, ..
        } => {
            assert_eq!(direction, 0, "0 = Up into scrollback");
            assert_eq!(lines, 15);
        }
        other => panic!("expected AttachScroll, got {:?}", other),
    }
    let sent = poll_thread.join().unwrap();
    assert!(sent[0].contains("\"method\":\"pane.get\""));
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

#[test]
fn move_to_offset_protocol20_sends_attach_scroll_down_and_confirms_via_poll() {
    let (client, mut server) = UnixStream::pair().unwrap();
    let attach_thread = std::thread::spawn(move || {
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
            &ServerMessage20::Terminal(TerminalFrame {
                seq: 1,
                width: 100,
                height: 30,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        let scroll_msg: ClientMessage20 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        scroll_msg
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach20::from_stream(
        client,
        "w1:p3",
        crate::winsize::Winsize {
            cols: 100,
            rows: 30,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("attach20");
    let mut handle = RoundTripHandle::Attach20(session);

    let path = json_socket_path("move20");
    let listener = UnixListener::bind(&path).unwrap();
    let poll_resp = pane_info_response(5);
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

    // current=20 (further from bottom), target=5 (closer) -> Down.
    let (attempted, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p3",
        20,
        5,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert!(attempted);
    assert_eq!(confirmed.offset_from_bottom, 5);

    let scroll_msg = attach_thread.join().unwrap();
    match scroll_msg {
        ClientMessage20::AttachScroll {
            direction, lines, ..
        } => {
            assert_eq!(direction, 1, "1 = Down towards the bottom");
            assert_eq!(lines, 15);
        }
        other => panic!("expected AttachScroll, got {:?}", other),
    }
    let _ = poll_thread.join().unwrap();
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

#[test]
fn move_to_offset_protocol17_skips_attach_scroll_when_already_at_target() {
    // relative_scroll_of returns None when current == target: no
    // AttachScroll should be sent at all, just the confirmation poll.
    let (client, mut server) = UnixStream::pair().unwrap();
    let attach_thread = std::thread::spawn(move || {
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
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        // No AttachScroll should arrive; confirm the connection stays
        // idle (best-effort — reading with a short deadline should
        // time out rather than yield a frame).
        let short_deadline = std::time::Instant::now() + std::time::Duration::from_millis(150);
        let result = read_frame_deadline::<ClientMessage17>(&server, short_deadline);
        assert!(
            result.is_err(),
            "no AttachScroll expected, got {:?}",
            result
        );
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach17::from_stream(
        client,
        "w1:p2",
        crate::winsize::Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("attach17");
    let mut handle = RoundTripHandle::Attach17(session);

    let path = json_socket_path("move17-noop");
    let listener = UnixListener::bind(&path).unwrap();
    let poll_resp = pane_info_response(10);
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

    let (attempted, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        10,
        10,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert!(
        !attempted,
        "already at target -- relative_scroll_of is None, nothing should be dispatched"
    );
    assert_eq!(confirmed.offset_from_bottom, 10);

    attach_thread.join().unwrap();
    let _ = poll_thread.join().unwrap();
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

// -----------------------------------------------------------------
// Regression test (the
// direction-agnostic `scroll_settled` false-positive) plus the
// coverage of (unsupported_scroll, a
// non-exact-but-changed confirmation, and a multi-poll settle).
// -----------------------------------------------------------------

#[test]
fn move_to_offset_protocol17_down_from_max_does_not_settle_on_the_unmoved_first_poll() {
    // Regression: starting exactly at max_offset_from_bottom
    // and moving Down (back towards the bottom) -- the old
    // direction-agnostic `scroll_settled` would treat the very first
    // poll (still reading offset == max, before AttachScroll took
    // effect) as "settled" without the position having moved. This
    // must now wait for the second poll, where the position actually
    // changed.
    let (client, mut server) = UnixStream::pair().unwrap();
    let attach_thread = std::thread::spawn(move || {
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
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        // current=500=max, target=100 -> Down, 400 lines.
        let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        scroll_msg
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach17::from_stream(
        client,
        "w1:p2",
        crate::winsize::Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("attach17");
    let mut handle = RoundTripHandle::Attach17(session);

    let path = json_socket_path("move17-down-from-max");
    let listener = UnixListener::bind(&path).unwrap();
    // Poll 1: AttachScroll not yet applied -- still at max (500),
    // unchanged from the start. Must NOT be accepted as settled.
    let poll1 = pane_info_response_with_max(500, 500);
    // Poll 2: the move has now taken effect.
    let poll2 = pane_info_response_with_max(300, 500);
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll1, &poll2]));

    let (_, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        500,
        100,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert_eq!(
        confirmed.offset_from_bottom, 300,
        "must keep polling past the unmoved first response"
    );

    let scroll_msg = attach_thread.join().unwrap();
    match scroll_msg {
        ClientMessage17::AttachScroll {
            direction, lines, ..
        } => {
            assert_eq!(direction, 1, "1 = Down towards the bottom");
            assert_eq!(lines, 400);
        }
        other => panic!("expected AttachScroll, got {:?}", other),
    }
    let sent = poll_thread.join().unwrap();
    assert_eq!(
        sent.len(),
        2,
        "must have polled exactly twice, not settled on the first"
    );
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

#[test]
fn move_to_offset_protocol17_settles_on_a_changed_but_not_exact_target_match() {
    // herdr may round/clamp so the confirmed position
    // differs from the requested target (18, not the requested 20) --
    // `move_to_offset` must still accept it (report the *actual*
    // position) rather than treating it as unsettled.
    let (client, mut server) = UnixStream::pair().unwrap();
    let attach_thread = std::thread::spawn(move || {
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
            &ServerMessage17::Terminal(TerminalFrame {
                seq: 1,
                width: 80,
                height: 24,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        let _scroll: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach17::from_stream(
        client,
        "w1:p2",
        crate::winsize::Winsize {
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        deadline,
    )
    .expect("attach17");
    let mut handle = RoundTripHandle::Attach17(session);

    let path = json_socket_path("move17-inexact");
    let listener = UnixListener::bind(&path).unwrap();
    let poll_resp = pane_info_response(18); // requested target is 20
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&poll_resp]));

    let (_, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        5,
        20,
        deadline,
    );
    let confirmed = result.expect("move_to_offset");
    assert_eq!(
        confirmed.offset_from_bottom, 18,
        "must report the real (clamped/rounded) position"
    );

    attach_thread.join().unwrap();
    let _ = poll_thread.join().unwrap();
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

#[test]
fn record_original_position_is_unsupported_scroll_when_pane_has_no_scroll_field() {
    let path = json_socket_path("record-unsupported");
    let listener = UnixListener::bind(&path).unwrap();
    let response = pane_info_response_without_scroll();
    let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let err = record_original_position(path.to_str().unwrap(), "w1:p2", deadline)
        .expect_err("must fail without a scroll field");
    assert!(matches!(err, RunError::UnsupportedScroll));
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn move_to_offset_protocol22_is_unsupported_scroll_when_pane_scroll_response_has_no_scroll_field() {
    let path = json_socket_path("move22-unsupported");
    let listener = UnixListener::bind(&path).unwrap();
    let response = pane_info_response_without_scroll();
    let t = std::thread::spawn(move || serve_sequence(listener, &[&response]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let mut handle = RoundTripHandle::Api;
    let (attempted, result) = move_to_offset(
        &mut handle,
        path.to_str().unwrap(),
        "w1:p2",
        0,
        12,
        deadline,
    );
    let err = result.expect_err("must fail without a scroll field");
    assert!(
        attempted,
        "the send was attempted even though it then failed to confirm"
    );
    assert!(matches!(err, RunError::UnsupportedScroll));
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}
