//! `restore_position`: restore classification (straight-line form) for each
//! protocol and each combination of moved / confirmed / concurrent-reset state.

use super::support::*;
use crate::attach::Attach17;
use crate::scrollback::*;
use crate::wire::*;
use std::os::unix::net::{UnixListener, UnixStream};

#[test]
fn restore_position_not_moved_and_originally_at_bottom_confirms_exact() {
    // `moved = false` (no scroll
    // command was ever dispatched, judged by `move_to_offset`'s own
    // "attempted" flag -- not by comparing `t`/`o0`) with `o0 == 0`
    // still confirms via a single `pane.get` read; if it reads back 0,
    // the outcome is `Exact`.
    let path = json_socket_path("restore-not-moved-bottom");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(0);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 0,
            moved: false,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Exact);
    let sent = t.join().unwrap();
    assert_eq!(
        sent.len(),
        1,
        "must not issue any call beyond the single pane.get read"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_not_moved_and_originally_at_bottom_but_now_elsewhere_is_failed() {
    // moved=false, o0=0, but the confirming pane.get reads back
    // something other than 0 (e.g. concurrent PC-side scroll) -- must
    // not be reported as Exact.
    let path = json_socket_path("restore-not-moved-bottom-drifted");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(3);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 0,
            moved: false,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Failed);
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_not_moved_and_nonzero_origin_is_approximate_without_any_call() {
    // moved=false with o0 > 0 classifies as
    // `approximate` directly (the contract's `exact` is reserved for
    // "was at the bottom and confirmed back at the bottom") -- and, since
    // nothing moved, no
    // restore command AND no confirming `pane.get` call is sent at all.
    // An unreachable socket proves this: any attempted call would
    // surface as `RestoreOutcome::Failed`, not `Approximate`.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        "/dev/null/unreachable.sock",
        "w1:p2",
        RestorePlan {
            o0: 7,
            t: 7,
            moved: false,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Approximate);
}

#[test]
fn restore_position_moved_o0_gt_0_always_attempts_a_real_call_never_a_noop_shortcut() {
    // `restore_position` is a pure function of its inputs: it cannot
    // itself tell whether `t` accurately reflects the last window
    // move's attempted target (keeping that accurate on an unconfirmed
    // failure is `run_scrollback_links`'s job -- see the
    // `current_offset = target` fix on the loop's `Err` arm).
    // What this level *can* and must guarantee: once `moved = true`,
    // the `o0 > 0` branch always issues a real `move_to_offset` call
    // and classifies the result -- it never takes a "nothing to do"
    // shortcut just because the computed target happens to equal `o1`
    // (as it does here: o0=5, t=5, o1=25 -> target = o0+(o1-t) = 25).
    let path = json_socket_path("restore-o0-gt-0-real-call");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(25);
    let scroll_resp = pane_info_response(25);
    let poll_resp = pane_info_response(25);
    let t =
        std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &scroll_resp, &poll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 5,
            t: 5,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Approximate);
    let sent = t.join().unwrap();
    assert!(
        sent.len() >= 2,
        "must issue a real move_to_offset call, not skip because o1==target"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_protocol22_bottom_restore_is_exact() {
    let path = json_socket_path("restore22-bottom");
    let listener = UnixListener::bind(&path).unwrap();
    // 1: read o1 (pane.get). 2: pane.scroll(0) -> offset 0.
    let o1_resp = pane_info_response(12);
    let scroll_resp = pane_info_response(0);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &scroll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 12,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Exact);
    let sent = t.join().unwrap();
    assert!(sent[1].contains("\"method\":\"pane.scroll\""));
    assert!(sent[1].contains("\"offset_from_bottom\":0"));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_protocol17_bottom_restore_sends_max_attach_scroll_down() {
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
                width: 54,
                height: 23,
                full: true,
                bytes: vec![],
            }),
        )
        .unwrap();
        let scroll_msg: ClientMessage17 = read_frame(&mut server, MAX_FRAME_SIZE).unwrap();
        scroll_msg
    });
    let handshake_deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let session = Attach17::from_stream(
        client,
        "w1:p2",
        crate::winsize::Winsize {
            cols: 54,
            rows: 23,
            cell_width_px: 0,
            cell_height_px: 0,
        },
        handshake_deadline,
    )
    .expect("attach17");

    let path = json_socket_path("restore17-bottom");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(9);
    let poll_resp = pane_info_response(0);
    let poll_thread = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &poll_resp]));

    let (handle, outcome) = restore_position(
        RoundTripHandle::Attach17(session),
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 9,
            moved: true,
            last_move_confirmed: true,
        },
        handshake_deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Exact);

    let scroll_msg = attach_thread.join().unwrap();
    match scroll_msg {
        ClientMessage17::AttachScroll {
            direction, lines, ..
        } => {
            assert_eq!(direction, 1, "1 = Down towards the bottom");
            assert_eq!(lines, 65535, "maximal Down, not a computed relative delta");
        }
        other => panic!("expected AttachScroll, got {:?}", other),
    }
    let _ = poll_thread.join().unwrap();
    let _ = std::fs::remove_file(&path);
    close_round_trip(handle);
}

#[test]
fn restore_position_protocol22_nonzero_origin_is_approximate() {
    let path = json_socket_path("restore22-approx");
    let listener = UnixListener::bind(&path).unwrap();
    // o0=5, t=20 (last confirmed window position), o1=25 (3 lines of
    // output flowed in during the round trip -- o1 = t + k).
    // target = o0 + (o1 - t) = 5 + (25-20) = 10.
    let o1_resp = pane_info_response(25);
    let scroll_resp = pane_info_response(10);
    let poll_resp = pane_info_response(10);
    let t =
        std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &scroll_resp, &poll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 5,
            t: 20,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Approximate);
    let sent = t.join().unwrap();
    assert!(
        sent[1].contains("\"offset_from_bottom\":10"),
        "must target o0+(o1-t) = 10, got {:?}",
        sent[1]
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_skipped_reset_when_already_back_at_bottom() {
    // o1=0 but t>0: concurrent PC-side input already reset to the
    // bottom during the round trip -- must not move (no second call at
    // all beyond the o1 read).
    let path = json_socket_path("restore-skipped");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(0);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 8,
            t: 15,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::SkippedReset);
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_not_skipped_reset_when_o0_gt_0_but_t_already_confirmed_bottom() {
    // The skipped_reset condition must be
    // keyed on `t > 0`, not `o0 > 0`.
    // Here o0=5 (>0) but the round trip's last window already
    // *confirmed* landing at the bottom (t=0), and o1=0 simply agrees
    // with that -- this is not an unrelated concurrent reset to detect
    // and avoid, so it must fall through to a real approximate-restore
    // attempt (target = o0+(o1-t) = 5), not `SkippedReset`.
    let path = json_socket_path("restore-not-skipped-t-zero");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(0);
    let move_resp = pane_info_response(5);
    let poll_resp = pane_info_response(5);
    let t =
        std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &move_resp, &poll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 5,
            t: 0,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Approximate);
    let sent = t.join().unwrap();
    assert!(
        sent[1].contains("\"offset_from_bottom\":5"),
        "must target o0+(o1-t) = 5, got {:?}",
        sent[1]
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_confirmed_last_move_with_o0_zero_and_o1_zero_is_skipped_reset() {
    // The `skipped_reset` rule applies just as much when o0=0: the round
    // trip's last window *confirmed* landing away from the bottom
    // (t=10 > 0), and the restore's own fresh o1 read now finds it back
    // at 0 -- a genuine concurrent PC-side reset (trustworthy here
    // specifically because the last move *was* confirmed) --
    // so restore must send nothing, not the usual unconditional bottom
    // restore.
    let path = json_socket_path("restore-confirmed-o0-zero-skipped");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(0);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&o1_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 10,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::SkippedReset);
    let sent = t.join().unwrap();
    assert_eq!(
        sent.len(),
        1,
        "must not send a bottom-restore call once skipped_reset is detected"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_unconfirmed_last_move_with_o0_zero_sends_bottom_restore_without_reading_o1() {
    // When the last attempted move's own
    // confirmation never landed (last_move_confirmed=false), the
    // AttachScroll/pane.scroll send and this restore's own pane.get
    // travel over different sockets with no ordering guarantee, so an
    // o1 read here could return a stale pre-effect snapshot. With
    // o0=0 the bottom restore is sent unconditionally instead --
    // without even reading o1 first, since the decision does not
    // depend on it and the send is idempotent either way.
    let path = json_socket_path("restore-unconfirmed-o0-zero");
    let listener = UnixListener::bind(&path).unwrap();
    let scroll_resp = pane_info_response(0);
    let t = std::thread::spawn(move || serve_sequence(listener, &[&scroll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 10,
            moved: true,
            last_move_confirmed: false,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Exact);
    let sent = t.join().unwrap();
    assert_eq!(
        sent.len(),
        1,
        "must send the bottom restore directly, no preceding o1 read"
    );
    assert!(sent[0].contains("\"method\":\"pane.scroll\""));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_unconfirmed_last_move_with_o1_zero_is_not_skipped_reset() {
    // With o0=5 (>0) and last_move_confirmed=
    // false, a restore-time o1 read of 0 must NOT be trusted as a
    // genuine concurrent reset (it could be a stale pre-effect
    // snapshot of the still-unconfirmed move) -- so `skipped_reset`
    // must not fire here; restore is attempted regardless (approximate
    // target = o0 + (o1-t) = 5 + (0-20), saturating to 5).
    let path = json_socket_path("restore-unconfirmed-o1-zero");
    let listener = UnixListener::bind(&path).unwrap();
    let o1_resp = pane_info_response(0);
    let move_resp = pane_info_response(5);
    let poll_resp = pane_info_response(5);
    let t =
        std::thread::spawn(move || serve_sequence(listener, &[&o1_resp, &move_resp, &poll_resp]));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        path.to_str().unwrap(),
        "w1:p2",
        RestorePlan {
            o0: 5,
            t: 20,
            moved: true,
            last_move_confirmed: false,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Approximate);
    let sent = t.join().unwrap();
    assert!(
        sent.len() >= 2,
        "must not short-circuit to SkippedReset when the last move was unconfirmed"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn restore_position_is_failed_when_reading_o1_fails() {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let (_, outcome) = restore_position(
        RoundTripHandle::Api,
        "/dev/null/unreachable.sock",
        "w1:p2",
        RestorePlan {
            o0: 0,
            t: 9,
            moved: true,
            last_move_confirmed: true,
        },
        deadline,
    );
    assert_eq!(outcome, RestoreOutcome::Failed);
}
