//! Shared fixtures for the `scrollback-links` suites: a fake herdr JSON-line
//! API server, canned `pane.get` / `pane.process_info` responses, a real-pty
//! child for the 17/20 fail-closed size resolution, and RAII guards that
//! clean up socket and lock-directory paths even when a test panics.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};

/// RAII guard for a test's unique Unix-socket bind path (see
/// `json_socket_path`): removes the socket file on drop, including
/// when a test panics partway through -- the same cleanup `LockDirGuard`
/// does for `--lock-dir` paths. A plain-`PathBuf` version would only be
/// cleaned up by each test's own end-of-function
/// `std::fs::remove_file(&path)`, which a panic skips, leaving
/// `/tmp/herdr-caret-helper-scrollback-test-*.sock` files behind.
///
/// Implements `Deref<Target = Path>` and `AsRef<Path>` so every
/// existing call site (`UnixListener::bind(&path)`, `path.to_str()`,
/// the now-redundant-but-harmless end-of-test
/// `std::fs::remove_file(&path)`) keeps compiling completely
/// unchanged -- only `json_socket_path` itself changes.
pub(super) struct SocketPathGuard(PathBuf);

impl std::ops::Deref for SocketPathGuard {
    type Target = Path;
    fn deref(&self) -> &Path {
        &self.0
    }
}

impl AsRef<Path> for SocketPathGuard {
    fn as_ref(&self) -> &Path {
        &self.0
    }
}

impl Drop for SocketPathGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

pub(super) fn json_socket_path(name: &str) -> SocketPathGuard {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "herdr-caret-helper-scrollback-test-{}-{}-{}.sock",
        name,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = std::fs::remove_file(&path);
    SocketPathGuard(path)
}

/// Bound for `accept_with_deadline`: generous relative to every
/// `timeout_ms`/`restore_budget_ms` used by these tests (at most
/// 5000ms), so it never fires under normal timing, but still finite.
const STUB_ACCEPT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

/// Accepts one connection within `STUB_ACCEPT_TIMEOUT`, instead of
/// blocking forever. Under
/// some regressions (e.g. calling `pane.process_info`
/// before the 17/20 attach guard and so starves `resolve_size_fail_
/// closed`'s own call of its queued response) the code under test can
/// fail and return *before ever reaching this connection*. A plain
/// `listener.accept().unwrap()` then blocks forever, and the test's
/// own unconditional `client_thread.join().unwrap()` hangs with it --
/// a regression then shows up as the whole test process timing out
/// (rc=124), not as a named FAILED test, and is much harder to
/// attribute. This turns that into an ordinary, named test failure: a
/// stub whose connection never arrives now panics with a clear
/// message instead of hanging, and `client_thread.join().unwrap()`
/// then also fails (propagating the panic), without hanging the test
/// process at all.
pub(super) fn accept_with_deadline(listener: &UnixListener) -> UnixStream {
    let deadline = std::time::Instant::now() + STUB_ACCEPT_TIMEOUT;
    listener.set_nonblocking(true).expect("set_nonblocking");
    loop {
        match listener.accept() {
            Ok((stream, _addr)) => {
                stream
                    .set_nonblocking(false)
                    .expect("set_nonblocking(stream)");
                return stream;
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                assert!(
                    std::time::Instant::now() < deadline,
                    "accept_with_deadline: no connection within {STUB_ACCEPT_TIMEOUT:?} -- \
                     the code under test likely failed/returned before ever reaching \
                     this connection"
                );
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
            Err(e) => panic!("accept_with_deadline: {e}"),
        }
    }
}

/// Accepts `responses.len()` connections in sequence, one request line
/// each, replying with the matching response. Returns every request
/// line received, in order.
pub(super) fn serve_sequence(listener: UnixListener, responses: &[&str]) -> Vec<String> {
    let mut received = Vec::new();
    for response in responses {
        let stream = accept_with_deadline(&listener);
        let mut reader = BufReader::new(&stream);
        let mut line = String::new();
        reader.read_line(&mut line).expect("read request line");
        received.push(line);
        let mut writer = &stream;
        writer.write_all(response.as_bytes()).unwrap();
        writer.write_all(b"\n").unwrap();
        writer.flush().unwrap();
    }
    received
}

/// Like `serve_sequence`, but each entry is `Some(response)` (answer
/// normally) or `None` (read the request, then deliberately never
/// respond -- the caller's own `set_read_timeout`/deadline must fire
/// first). Used for the "send succeeded, confirmation wait timed
/// out" regression tests, mirroring `tests/api_client.rs`'s
/// `no_response_before_deadline_is_timeout`.
pub(super) fn serve_sequence_with_stall(
    listener: UnixListener,
    entries: &[Option<&str>],
) -> Vec<String> {
    let mut received = Vec::new();
    for entry in entries {
        let stream = accept_with_deadline(&listener);
        let mut reader = BufReader::new(&stream);
        let mut line = String::new();
        reader.read_line(&mut line).expect("read request line");
        received.push(line);
        match entry {
            Some(response) => {
                let mut writer = &stream;
                writer.write_all(response.as_bytes()).unwrap();
                writer.write_all(b"\n").unwrap();
                writer.flush().unwrap();
            }
            None => {
                // Never respond -- hold the connection until the
                // caller's read side times out and moves on. Sleeping
                // here just keeps this thread (and the connection)
                // alive long enough for that to happen deterministically.
                std::thread::sleep(std::time::Duration::from_millis(500));
            }
        }
    }
    received
}

pub(super) fn pane_info_response(offset_from_bottom: u64) -> String {
    pane_info_response_with_max(offset_from_bottom, 9999)
}

pub(super) fn pane_info_response_with_max(
    offset_from_bottom: u64,
    max_offset_from_bottom: u64,
) -> String {
    format!(
        r#"{{"id":"1","result":{{"type":"pane_info","pane":{{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":1,"scroll":{{"offset_from_bottom":{offset_from_bottom},"max_offset_from_bottom":{max_offset_from_bottom},"viewport_rows":24}}}}}}}}"#
    )
}

pub(super) fn pane_info_response_without_scroll() -> String {
    r#"{"id":"1","result":{"type":"pane_info","pane":{"pane_id":"w1:p2","terminal_id":"term-abc","workspace_id":"w1","tab_id":"t1","focused":true,"agent_status":"idle","revision":1}}}"#.to_owned()
}

/// A genuine `pane.process_info` success response (`shell_pid` set).
/// Used by the 17/20 fail-closed `resolve_size_fail_closed` tests,
/// paired with `spawn_real_pty_process` below so the follow-up
/// `winsize::real_size(shell_pid)` call succeeds for real.
pub(super) fn pane_process_info_response(shell_pid: u32) -> String {
    format!(
        r#"{{"id":"1","result":{{"type":"pane_process_info","process_info":{{"pane_id":"w1:p2","shell_pid":{shell_pid}}}}}}}"#
    )
}

// -- Real-pty test helper for `winsize::real_size` (17/20 fail-closed
// real-size resolution) --------------------------------------------
//
// `resolve_size_fail_closed` genuinely calls `winsize::real_size`, which
// needs a *real* process with a *real* controlling pty -- there is no
// way to satisfy it with a JSON-level fake alone. This duplicates the
// minimal FFI `winsize.rs`'s own `#[cfg(test)]` helpers already use
// (`open`/`ioctl`/`TIOCSPTLCK`/`TIOCGPTN`/`TIOCSWINSZ`), since that
// module's helpers are private to its own test block, plus `setsid`+a
// fresh `open()` of the slave in the child's `pre_exec` (the standard
// way a process acquires a real controlling terminal) so
// `/proc/<pid>/stat`'s `tty_nr` resolves to this pty, exactly as a real
// shell would. Verified empirically that this
// combination makes `winsize::real_size(child.id())` succeed end-to-end.
#[repr(C)]
#[derive(Default)]
struct TestRawWinsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

// `ioctl`/`open`'s real C prototypes are variadic (`int ioctl(int,
// unsigned long, ...)` / `int open(const char *, int, ...)`); declaring
// them with a fixed trailing argument is unsound per the Rustonomicon's
// FFI chapter and clashes (`clashing_extern_declarations`) with
// `winsize.rs`'s own correctly-variadic test-only declarations of the
// same two symbols once both modules are linked into the same test
// binary -- see that file's matching doc comment for the full
// rationale. Declared variadic here too, always passing exactly one
// trailing argument at every call site below, matching the real
// prototype exactly.
extern "C" {
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn open(path: *const i8, flags: i32, ...) -> i32;
    fn setsid() -> i32;
    fn dup2(oldfd: i32, newfd: i32) -> i32;
    fn close(fd: i32) -> i32;
}

const TEST_O_RDWR: i32 = 0o2;
const TEST_O_NOCTTY: i32 = 0o400;
const TEST_TIOCSPTLCK: u64 = 0x4004_5431;
const TEST_TIOCGPTN: u64 = 0x8004_5430;
const TEST_TIOCSWINSZ: u64 = 0x5414;

/// Spawns a real `sleep` child with a real pty as its controlling
/// terminal, sized `rows`x`cols` (`xpixel`/`ypixel` in pixels, `0` for
/// "none", same meaning as `winsize::Winsize`'s own fields), so
/// `winsize::real_size(child.id())` succeeds for real. Returns the
/// `Child` (caller must `.kill()` + `.wait()` it) and the pty master
/// `File` (must be kept alive for the pty pair to stay valid -- dropping
/// it closes the pair).
pub(super) fn spawn_real_pty_process(
    rows: u16,
    cols: u16,
    xpixel: u16,
    ypixel: u16,
) -> (std::process::Child, std::fs::File) {
    use std::os::unix::io::FromRawFd;
    use std::os::unix::process::CommandExt;

    let ptmx = std::ffi::CString::new("/dev/ptmx").unwrap();
    let master_fd = unsafe { open(ptmx.as_ptr(), TEST_O_RDWR | TEST_O_NOCTTY) };
    assert!(master_fd >= 0, "open /dev/ptmx failed");
    let mut unlock: i32 = 0;
    assert_eq!(
        unsafe {
            ioctl(
                master_fd,
                TEST_TIOCSPTLCK,
                &mut unlock as *mut i32 as *mut std::ffi::c_void,
            )
        },
        0,
        "TIOCSPTLCK failed"
    );
    let mut n: i32 = 0;
    assert_eq!(
        unsafe {
            ioctl(
                master_fd,
                TEST_TIOCGPTN,
                &mut n as *mut i32 as *mut std::ffi::c_void,
            )
        },
        0,
        "TIOCGPTN failed"
    );
    let mut ws = TestRawWinsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: xpixel,
        ws_ypixel: ypixel,
    };
    assert_eq!(
        unsafe {
            ioctl(
                master_fd,
                TEST_TIOCSWINSZ,
                &mut ws as *mut TestRawWinsize as *mut std::ffi::c_void,
            )
        },
        0,
        "TIOCSWINSZ on the master side failed"
    );
    // SAFETY: `master_fd` is a freshly opened, valid, uniquely-owned fd
    // from the successful `open()` above.
    let master = unsafe { std::fs::File::from_raw_fd(master_fd) };

    let slave_path = std::ffi::CString::new(format!("/dev/pts/{n}")).unwrap();
    let mut cmd = std::process::Command::new("sleep");
    cmd.arg("30");
    cmd.stdin(std::process::Stdio::null());
    cmd.stdout(std::process::Stdio::null());
    cmd.stderr(std::process::Stdio::null());
    // SAFETY: the closure only calls `setsid`/`open`/`dup2`/`close`
    // (all async-signal-safe) between fork and exec, as `pre_exec`
    // requires; `slave_path` is a valid, null-terminated `CString`
    // moved into the closure.
    unsafe {
        cmd.pre_exec(move || {
            if setsid() == -1 {
                return Err(std::io::Error::last_os_error());
            }
            // A fresh `open()` of the pty slave, by a session leader
            // with no controlling terminal (just established above),
            // is what makes the kernel assign it as this process's
            // controlling terminal -- an inherited, already-open fd
            // would not trigger that assignment.
            let fd = open(slave_path.as_ptr(), TEST_O_RDWR);
            if fd < 0 {
                return Err(std::io::Error::last_os_error());
            }
            dup2(fd, 0);
            dup2(fd, 1);
            dup2(fd, 2);
            if fd > 2 {
                close(fd);
            }
            Ok(())
        });
    }
    let child = cmd.spawn().expect("spawn sleep for a real controlling pty");
    // Give the child a brief moment to run its `pre_exec` (setsid+open)
    // before any caller reads `/proc/<pid>/stat`.
    std::thread::sleep(std::time::Duration::from_millis(50));
    (child, master)
}

/// RAII guard around a test's unique `--lock-dir` path: removes the
/// directory (and anything `run_scrollback_links`'s `acquire_lock`
/// created under it) on drop, including when a test panics partway
/// through (an `assert!`/`expect` failure before the old manual
/// `remove_dir_all` call would otherwise skip cleanup entirely).
/// Without it, the manual
/// end-of-test cleanup leaves `/tmp/scrollback-test-locks-*`
/// directories behind from failed runs; this guard makes
/// cleanup unconditional instead of reachable only on the success
/// path.
pub(super) struct LockDirGuard(PathBuf);

impl LockDirGuard {
    pub(super) fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for LockDirGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub(super) fn fresh_lock_dir(name: &str) -> LockDirGuard {
    LockDirGuard(std::env::temp_dir().join(format!(
        "scrollback-test-locks-{}-{}-{}",
        name,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )))
}
