//! Loopback tests for the herdr.sock JSON API client (`pane.get` /
//! `pane.scroll`). Unlike the binary wire protocol tests (`tests/loopback/`,
//! which use `UnixStream::pair()`), `api_client::pane_get`/`pane_scroll`
//! connect by path, so these tests bind a real `UnixListener` under a
//! per-test temp directory and run a hand-written fake JSON-line server
//! one accepted connection per request, matching herdr's
//! real `handle_connection_with_stop` behavior (one line in, one line out,
//! then the connection is dropped; see `src/api/server.rs:156-183` in the
//! vendored source).

use herdr_caret_helper::api_client::{pane_get, pane_scroll};
use herdr_caret_helper::runner::RunError;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// A fresh socket path under the OS temp dir, unique per test run.
fn socket_path(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "herdr-caret-helper-api-client-test-{}-{}.sock",
        name,
        std::process::id()
    ));
    let _ = std::fs::remove_file(&path);
    path
}

/// Accepts exactly one connection, reads one line, writes back `response`,
/// then closes — mirroring herdr's one-shot-per-request `handle_connection`.
fn serve_one(listener: UnixListener, response: &'static str) -> String {
    let (stream, _) = listener.accept().expect("accept");
    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    reader.read_line(&mut line).expect("read request line");
    let mut writer = &stream;
    writer.write_all(response.as_bytes()).unwrap();
    writer.write_all(b"\n").unwrap();
    writer.flush().unwrap();
    line
}

#[test]
fn pane_get_reads_terminal_id_and_scroll() {
    let path = socket_path("get-ok");
    let listener = UnixListener::bind(&path).unwrap();
    let response = r#"{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":7,"scroll":{"offset_from_bottom":31,"max_offset_from_bottom":75,"viewport_rows":24}}}}"#;
    let t = std::thread::spawn({
        let path = path.clone();
        move || {
            let line = serve_one(listener, response);
            let _ = &path;
            line
        }
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let info = pane_get(path.to_str().unwrap(), "w1:p2", deadline).expect("pane_get");
    assert_eq!(info.terminal_id, "term-abc");
    let scroll = info.scroll.expect("scroll present");
    assert_eq!(scroll.offset_from_bottom, 31);
    assert_eq!(scroll.max_offset_from_bottom, 75);
    assert_eq!(scroll.viewport_rows, 24);
    let sent = t.join().unwrap();
    assert!(sent.contains("\"method\":\"pane.get\""));
    assert!(sent.contains("\"pane_id\":\"w1:p2\""));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn pane_get_without_scroll_field_is_none() {
    // A pane with no active runtime may omit `scroll` entirely.
    let path = socket_path("get-no-scroll");
    let listener = UnixListener::bind(&path).unwrap();
    let response = r#"{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":false,"agent_status":"idle","revision":1}}}"#;
    let t = std::thread::spawn(move || serve_one(listener, response));
    let deadline = Instant::now() + Duration::from_secs(5);
    let info = pane_get(path.to_str().unwrap(), "w1:p2", deadline).expect("pane_get");
    assert_eq!(info.terminal_id, "term-abc");
    assert!(info.scroll.is_none());
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn pane_scroll_sends_offset_and_reads_same_result_shape() {
    let path = socket_path("scroll-ok");
    let listener = UnixListener::bind(&path).unwrap();
    let response = r#"{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":8,"scroll":{"offset_from_bottom":0,"max_offset_from_bottom":75,"viewport_rows":24}}}}"#;
    let t = std::thread::spawn(move || serve_one(listener, response));
    let deadline = Instant::now() + Duration::from_secs(5);
    let info = pane_scroll(path.to_str().unwrap(), "w1:p2", 0, deadline).expect("pane_scroll");
    let scroll = info.scroll.expect("scroll present");
    assert_eq!(scroll.offset_from_bottom, 0);
    let sent = t.join().unwrap();
    assert!(sent.contains("\"method\":\"pane.scroll\""));
    assert!(sent.contains("\"offset_from_bottom\":0"));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn api_error_response_is_protocol_error_with_code() {
    let path = socket_path("api-error");
    let listener = UnixListener::bind(&path).unwrap();
    let response =
        r#"{"id":"1","error":{"code":"pane_not_found","message":"pane w9:p9 not found"}}"#;
    let t = std::thread::spawn(move || serve_one(listener, response));
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = pane_get(path.to_str().unwrap(), "w9:p9", deadline).expect_err("should fail");
    match err {
        RunError::Protocol(code) => assert_eq!(code, "pane_not_found"),
        other => panic!("expected Protocol(_), got {:?}", other),
    }
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn malformed_json_response_is_protocol_error() {
    let path = socket_path("malformed");
    let listener = UnixListener::bind(&path).unwrap();
    let t = std::thread::spawn(move || serve_one(listener, "not json at all"));
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = pane_get(path.to_str().unwrap(), "w1:p2", deadline).expect_err("should fail");
    assert!(matches!(err, RunError::Protocol(_)));
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn connect_failure_is_connect_error() {
    let deadline = Instant::now() + Duration::from_secs(5);
    let err = pane_get("/dev/null/no-such-herdr-api.sock", "w1:p2", deadline)
        .expect_err("should fail to connect");
    assert!(matches!(err, RunError::Connect));
}

#[test]
fn no_response_before_deadline_is_timeout() {
    let path = socket_path("stall");
    let listener = UnixListener::bind(&path).unwrap();
    let t = std::thread::spawn(move || {
        // Accept and read the request, then stall without responding.
        let (stream, _) = listener.accept().unwrap();
        let mut reader = BufReader::new(&stream);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        std::thread::sleep(Duration::from_secs(2));
    });
    let deadline = Instant::now() + Duration::from_millis(150);
    let err = pane_get(path.to_str().unwrap(), "w1:p2", deadline).expect_err("should time out");
    assert!(matches!(err, RunError::Timeout));
    t.join().unwrap();
    let _ = std::fs::remove_file(&path);
}

#[test]
fn deadline_already_elapsed_is_timeout() {
    // No listener at all: the deadline is checked before connecting, so this
    // must classify as Timeout rather than Connect (a socket that does not
    // exist would otherwise mask the "deadline already passed" case).
    let path = socket_path("elapsed");
    let deadline = Instant::now() - Duration::from_millis(1);
    let err = pane_get(path.to_str().unwrap(), "w1:p2", deadline).expect_err("should time out");
    assert!(matches!(err, RunError::Timeout));
}
