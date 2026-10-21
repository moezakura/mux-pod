//! Real pty winsize resolution: the helper reads the real terminal size itself
//! instead of trusting the caller's `--cols`/`--rows` unconditionally.
//!
//! Given a pane's `shell_pid` (from herdr's `pane.process_info`, added to
//! `api_client.rs`), this resolves the actual size the shell's
//! controlling pty currently has, via `TIOCGWINSZ` — no new crate
//! dependency (only `serde`/`bincode`/`serde_json` are dependencies of this
//! crate, and this needs none of those). `ioctl`/`isatty`/`open` are
//! declared here as plain `extern "C"` signatures (libc FFI declarations
//! only, no extra dependency); the flag/request constants below are Linux
//! kernel UAPI numbers, not libc-specific, so they are identical for the
//! musl targets this crate is built for (`x86_64-unknown-linux-musl`,
//! `aarch64-unknown-linux-musl`) as for glibc.
//!
//! Every failure path returns `Err` — this module never guesses a
//! dimension and never panics. Callers decide fail-open vs fail-closed
//! (see `hyperlinks.rs`'s `resolve_dimensions` for the fail-open observe
//! path, and `scrollback/position.rs`'s wiring for the fail-closed
//! `scrollback-links` path).

use std::ffi::c_void;
use std::fs::{self, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;

/// `O_NOCTTY` (Linux, all architectures this crate targets).
const O_NOCTTY: i32 = 0o400;
/// `O_NONBLOCK` (Linux, all architectures this crate targets).
const O_NONBLOCK: i32 = 0o4000;
/// `TIOCGWINSZ` (Linux asm-generic `ioctls.h`, shared by x86_64 and
/// aarch64 — the two targets this crate builds for).
const TIOCGWINSZ: u64 = 0x5413;
/// Unix98 pty slave major number (`/dev/pts/*`), confirmed via
/// `stat -c "%t:%T" /dev/pts/N`.
const PTS_MAJOR: u32 = 136;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
struct RawWinsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

// `ioctl`'s real C prototype is variadic (`int ioctl(int, unsigned long,
// ...)` on glibc; musl's own libc.h declares it as `int ioctl(int, int,
// ...)` -- in both cases the third parameter is part of the `...`, not a
// fixed, fully-typed parameter). Declaring it here as a plain fixed-arity
// `fn(i32, u64, *mut c_void) -> i32` is UB: a call through a function
// pointer whose declared signature does not match the variadic prototype
// the actual C symbol was compiled with is unsound per the Rustonomicon's
// FFI chapter, and differs in practice on some ABIs (e.g. which register
// class the trailing pointer argument is passed in). Declaring it
// variadic here (fixed `fd`/`request`, trailing `...`) and always passing
// exactly one trailing pointer argument at every call site matches the
// real prototype exactly.
extern "C" {
    fn isatty(fd: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
}

/// Resolved real pty size.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Winsize {
    pub rows: u16,
    pub cols: u16,
    /// `0` when the pty reported no pixel geometry (`ws_xpixel == 0`) —
    /// never computed from a zero numerator (see `real_size`'s doc comment
    /// on the division).
    pub cell_width_px: u16,
    pub cell_height_px: u16,
}

/// Why the real size could not be read. Every variant is fail-closed:
/// `real_size` never falls back to a guessed value on its own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WinsizeError {
    /// `/proc/<pid>` does not exist (process not running, or never did).
    ProcessNotRunning,
    /// `/proc/<pid>/stat` could not be read.
    StatUnreadable,
    /// `/proc/<pid>/stat` was read but its `tty_nr` field could not be
    /// parsed (unexpected format — e.g. an unterminated `comm` field).
    StatUnparseable,
    /// `tty_nr`'s major is not the Unix98 pty major (136) — the process
    /// has no pty as its controlling terminal — or `/proc/<pid>/fd/0`
    /// resolves to a *different* `/dev/pts/N` than `tty_nr` did (ambiguous:
    /// fail closed rather than pick one arbitrarily).
    NotATty,
    /// Opening `/dev/pts/N` failed (e.g. permission, ENOENT after a race).
    OpenFailed,
    /// `isatty` or the `TIOCGWINSZ` ioctl itself failed.
    IoctlFailed,
    /// The ioctl succeeded but reported `ws_row == 0` or `ws_col == 0`
    /// (a real but useless size — treated the same as "could not read").
    ZeroDimension,
}

/// Reads `shell_pid`'s controlling pty's real size.
///
/// Sync, no side effects beyond read-only `/proc` and `/dev/pts` access
/// (`O_RDONLY`; the only ioctl issued is the read-only `TIOCGWINSZ` — no
/// `TIOCSWINSZ`/`TIOCSPTLCK`/any `SET*` request is ever made). Never
/// panics: every OS call's return value is checked before use.
///
/// Residual risk: herdr does
/// not clear a pane's recorded `child_pid` once the shell underneath it
/// exits (vendored `pane.rs` v0.7.5:1872, 1882-1885) — so a `shell_pid`
/// this function is handed can, in principle, be stale (the original
/// shell is gone) *and* already reused by an unrelated process that does
/// have a pty. In that specific case `real_size` would report that other
/// process's pty size rather than failing, since nothing here can
/// distinguish "the same pid, reused" from "still running". This is not
/// fixed here: both callers already tolerate a materially wrong size
/// without corrupting state (the fail-closed `scrollback-links` path
/// re-resolves once per run and never free-runs on a stale value, and the
/// fail-open `hyperlinks`/caret path only ever affects cosmetic Hello/
/// Resize sizing) — but it is not a case this function can detect or rule
/// out on its own.
pub fn real_size(shell_pid: u32) -> Result<Winsize, WinsizeError> {
    if fs::metadata(format!("/proc/{shell_pid}")).is_err() {
        return Err(WinsizeError::ProcessNotRunning);
    }

    let pts_from_stat = pts_number_from_stat(shell_pid)?;
    if let Some(pts_from_fd0) = pts_number_from_fd0(shell_pid) {
        if pts_from_fd0 != pts_from_stat {
            // Ambiguous: the process's stdin and its controlling terminal
            // (per /proc/<pid>/stat) disagree. Fail closed rather than
            // guess which one is "real".
            return Err(WinsizeError::NotATty);
        }
    }

    let raw = read_raw_winsize(pts_from_stat)?;
    winsize_from_raw(raw)
}

/// The zero-dimension check and the cell-pixel-size division, split out of
/// `real_size` as a pure function so both can be unit-tested directly against
/// `RawWinsize` fixtures, without needing a real pty pair. The zero-
/// dimension check running *before* either division is what makes both
/// divisions safe: `ws_col`/`ws_row` are only used as a divisor once they
/// are known to be non-zero (a `ws_col == 0` with a non-zero `ws_xpixel`
/// would otherwise divide by zero and panic).
fn winsize_from_raw(raw: RawWinsize) -> Result<Winsize, WinsizeError> {
    if raw.ws_row == 0 || raw.ws_col == 0 {
        return Err(WinsizeError::ZeroDimension);
    }
    Ok(Winsize {
        rows: raw.ws_row,
        cols: raw.ws_col,
        // "xpixel/cols, ypixel/rows (0 if 0)": a zero pixel
        // dimension means the pty never reported pixel geometry at all
        // (observed on protocols 17/20 — the helper itself
        // always sent 0 for both fields) and is left as 0, never divided.
        cell_width_px: if raw.ws_xpixel == 0 {
            0
        } else {
            raw.ws_xpixel / raw.ws_col
        },
        cell_height_px: if raw.ws_ypixel == 0 {
            0
        } else {
            raw.ws_ypixel / raw.ws_row
        },
    })
}

/// Parses `/proc/<pid>/stat`'s `tty_nr` field (5th whitespace-separated
/// field *after* the `comm` field's closing `)`  — `comm` itself may
/// contain spaces or parentheses, so the split point is the *last* `)` on
/// the line, per `man proc`'s own documented caveat), and decodes it into
/// a pts number if its major is the Unix98 pty major.
///
/// Decoding uses the kernel's real `MAJOR()`/`MINOR()` macros for the
/// "new" `dev_t` encoding, not the simplified `major*256+minor` shorthand
/// (which misdecodes large minors) —
/// that shorthand is only correct for minors below 256, and a pty minor
/// can exceed that on a busy real system.
fn pts_number_from_stat(pid: u32) -> Result<u32, WinsizeError> {
    let contents = fs::read_to_string(format!("/proc/{pid}/stat"))
        .map_err(|_| WinsizeError::StatUnreadable)?;
    parse_tty_nr_pts(&contents)
}

/// Pure parsing half of `pts_number_from_stat`, split out so it can be
/// unit-tested against fixture strings without touching `/proc` at all.
/// `stat_contents` is the raw contents of a `/proc/<pid>/stat` file (or an
/// equivalently-shaped fixture).
///
/// `tty_nr` is the 5th whitespace-separated field *after* the `comm`
/// field's closing `)` — `comm` itself may contain spaces or parentheses,
/// so the split point is the *last* `)` on the line, per `man proc`'s own
/// documented caveat for parsing this file.
///
/// Decoding uses the kernel's real `MAJOR()`/`MINOR()` macros for the
/// "new" `dev_t` encoding, not the simplified `major*256+minor` shorthand
/// (which misdecodes large minors) —
/// that shorthand is only correct for minors below 256, and a pty minor
/// can exceed that on a busy real system.
fn parse_tty_nr_pts(stat_contents: &str) -> Result<u32, WinsizeError> {
    let after_comm = stat_contents
        .rfind(')')
        .map(|i| &stat_contents[i + 1..])
        .ok_or(WinsizeError::StatUnparseable)?;
    let mut fields = after_comm.split_whitespace();
    // after_comm's own fields: state(1) ppid(2) pgrp(3) session(4) tty_nr(5) ...
    let tty_nr: i64 = fields
        .nth(4)
        .ok_or(WinsizeError::StatUnparseable)?
        .parse()
        .map_err(|_| WinsizeError::StatUnparseable)?;
    if tty_nr <= 0 {
        // 0 means "no controlling terminal" (man proc, tty_nr).
        return Err(WinsizeError::NotATty);
    }
    let tty_nr = tty_nr as u32;
    let major = (tty_nr >> 8) & 0xfff;
    let minor = (tty_nr & 0xff) | ((tty_nr >> 12) & 0xfff00);
    if major != PTS_MAJOR {
        return Err(WinsizeError::NotATty);
    }
    Ok(minor)
}

/// Best-effort cross-check: resolves `/proc/<pid>/fd/0` and, if it points
/// at a `/dev/pts/N` path, returns `Some(N)`. Returns `None` (not an
/// error) when fd/0 is missing, unreadable, or not a pts path at all —
/// `real_size` only treats this as a problem when it resolves to a
/// *different* pts than `tty_nr` did, not when it is merely unavailable
/// (e.g. stdin redirected from a pipe/file is a legitimate, unambiguous
/// state: `tty_nr` alone is still authoritative there).
fn pts_number_from_fd0(pid: u32) -> Option<u32> {
    let target = fs::read_link(format!("/proc/{pid}/fd/0")).ok()?;
    let target = target.to_str()?;
    target.strip_prefix("/dev/pts/")?.parse().ok()
}

/// Opens `/dev/pts/<n>` read-only/non-controlling/non-blocking, confirms
/// it is actually a tty, and reads its current `TIOCGWINSZ` state.
fn read_raw_winsize(pts_number: u32) -> Result<RawWinsize, WinsizeError> {
    let path = format!("/dev/pts/{pts_number}");
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(O_NOCTTY | O_NONBLOCK)
        .open(&path)
        .map_err(|_| WinsizeError::OpenFailed)?;
    let fd = file.as_raw_fd();

    // SAFETY: `fd` is a valid, open file descriptor owned by `file` for
    // the duration of this call (it is not closed or moved until `file`
    // is dropped, after both FFI calls below return); `isatty` reads no
    // memory through `fd` beyond the kernel's own fd table, and `ioctl`'s
    // `argp` points at a fully-initialized, correctly-sized `RawWinsize`
    // that outlives the call.
    let is_tty = unsafe { isatty(fd) };
    if is_tty != 1 {
        return Err(WinsizeError::IoctlFailed);
    }

    let mut raw = RawWinsize::default();
    // SAFETY: see above; `&mut raw` is a valid, uniquely-owned, correctly
    // sized/aligned `RawWinsize` for `ioctl(TIOCGWINSZ)` to write into.
    let rc = unsafe { ioctl(fd, TIOCGWINSZ, &mut raw as *mut RawWinsize as *mut c_void) };
    if rc != 0 {
        return Err(WinsizeError::IoctlFailed);
    }
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- pts_number_from_stat: pure parsing, fixture strings --------------

    fn stat_line(tty_nr: i64) -> String {
        // Matches /proc/<pid>/stat's real shape closely enough for this
        // function's own parsing (pid, comm, state, ppid, pgrp, session,
        // tty_nr, ...); only the fields up to tty_nr matter here.
        format!("12345 (bash) S 1 12345 12345 {tty_nr} -1 4194624 ...")
    }

    fn stat_line_with_comm(comm: &str, tty_nr: i64) -> String {
        format!("12345 ({comm}) S 1 12345 12345 {tty_nr} -1 4194624 ...")
    }

    fn tty_nr_for(major: u32, minor: u32) -> i64 {
        (((major & 0xfff) << 8) | (minor & 0xff) | ((minor & 0xfff00) << 12)) as i64
    }

    #[test]
    fn decodes_low_minor_pts_tty_nr() {
        let tty_nr = tty_nr_for(136, 5);
        let line = stat_line(tty_nr);
        assert_eq!(parse_tty_nr_pts(&line), Ok(5));
    }

    #[test]
    fn decodes_high_minor_pts_tty_nr_beyond_simple_shorthand() {
        // Regression for the simplified shorthand
        // (major*256+minor), which is only correct below minor 256.
        let tty_nr = tty_nr_for(136, 4000);
        let line = stat_line(tty_nr);
        assert_eq!(parse_tty_nr_pts(&line), Ok(4000));
    }

    #[test]
    fn comm_containing_parens_and_spaces_does_not_break_the_split() {
        let tty_nr = tty_nr_for(136, 7);
        let line = stat_line_with_comm("my (weird) proc name", tty_nr);
        assert_eq!(parse_tty_nr_pts(&line), Ok(7));
    }

    #[test]
    fn pts_number_from_stat_rejects_non_pty_major() {
        // major 4 is the legacy BSD-style console/serial range, never 136.
        let tty_nr = tty_nr_for(4, 1);
        let line = stat_line(tty_nr);
        assert_eq!(parse_tty_nr_pts(&line), Err(WinsizeError::NotATty));
    }

    #[test]
    fn pts_number_from_stat_rejects_zero_tty_nr() {
        // tty_nr == 0 means "no controlling terminal" (man proc).
        let line = stat_line(0);
        assert_eq!(parse_tty_nr_pts(&line), Err(WinsizeError::NotATty));
    }

    #[test]
    fn pts_number_from_stat_rejects_unparseable_stat_line() {
        assert_eq!(
            parse_tty_nr_pts("no closing paren at all"),
            Err(WinsizeError::StatUnparseable)
        );
        assert_eq!(
            parse_tty_nr_pts("12345 (bash) S"),
            Err(WinsizeError::StatUnparseable)
        );
    }

    // -- real_size: integration against real /proc entries -----------------

    #[test]
    fn nonexistent_pid_is_process_not_running() {
        // A pid this large is never a real process on any system this
        // crate targets (max_pid on 64-bit Linux defaults well below
        // this), so /proc/<pid> reliably does not exist.
        let err = real_size(u32::MAX).unwrap_err();
        assert_eq!(err, WinsizeError::ProcessNotRunning);
    }

    #[test]
    fn exited_child_pid_is_process_not_running() {
        let mut child = std::process::Command::new("/bin/true")
            .spawn()
            .expect("spawn /bin/true");
        let pid = child.id();
        child.wait().expect("wait for /bin/true");
        // The pid may or may not be reused by the time this runs, but
        // /bin/true exits near-instantly and this process does not spawn
        // enough children concurrently for reuse to be likely; if it is
        // ever reused, this assertion would need a different fixture, not
        // a code change -- documented here rather than silently ignored.
        let err = real_size(pid);
        assert!(
            matches!(
                err,
                Err(WinsizeError::ProcessNotRunning) | Err(WinsizeError::NotATty)
            ),
            "expected the exited child's pid to be unusable one way or another, got {err:?}"
        );
    }

    #[test]
    fn child_with_stdin_redirected_from_dev_null_has_no_pty() {
        use std::process::Stdio;
        let mut child = std::process::Command::new("/bin/sleep")
            .arg("5")
            .stdin(Stdio::null())
            .spawn()
            .expect("spawn /bin/sleep");
        let pid = child.id();
        let err = real_size(pid);
        let _ = child.kill();
        let _ = child.wait();
        assert_eq!(err, Err(WinsizeError::NotATty));
    }

    // -- read_raw_winsize / isatty+ioctl: real pty pair, no extra deps ----

    const O_RDWR: i32 = 0o2;

    // `open`'s real C prototype is also variadic (`int open(const char *,
    // int, ...)` -- the trailing `mode_t` only applies when `O_CREAT`/
    // `O_TMPFILE` is set, but the symbol itself is always variadic; see
    // this file's `ioctl` doc comment above for why a fixed-arity
    // declaration here would be unsound). This test never passes a
    // trailing argument (no `O_CREAT`), matching real callers of `open`
    // without `O_CREAT`.
    extern "C" {
        fn open(path: *const i8, flags: i32, ...) -> i32;
        fn close(fd: i32) -> i32;
        fn setsid() -> i32;
        fn dup2(oldfd: i32, newfd: i32) -> i32;
    }

    const TIOCSPTLCK: u64 = 0x4004_5431;
    const TIOCGPTN: u64 = 0x8004_5430;
    const TIOCSWINSZ: u64 = 0x5414;

    /// Opens `/dev/ptmx` and unlocks+numbers its slave, for test use only
    /// (production code never opens `/dev/ptmx` or issues `TIOCSPTLCK`/
    /// `TIOCSWINSZ` — those are exclusively in this `#[cfg(test)]` block).
    /// Returns `None` if the sandbox has no usable `/dev/ptmx`, so by
    /// default these two tests degrade to a visible-but-passing skip
    /// there instead of failing the suite on an environment it cannot
    /// control -- *unless* `HERDR_CARET_HELPER_REQUIRE_PTY=1` is set in
    /// the environment, in which case the same failure is a hard test
    /// failure instead (a
    /// silent skip can hide a sandbox regression that drops `/dev/ptmx`
    /// support entirely; CI can set this env var to turn that into a
    /// loud failure instead).
    fn open_test_pty_pair() -> Option<(std::fs::File, u32)> {
        use std::os::unix::io::FromRawFd;
        let require_pty =
            std::env::var("HERDR_CARET_HELPER_REQUIRE_PTY").unwrap_or_default() == "1";
        let path = std::ffi::CString::new("/dev/ptmx").unwrap();
        let master_fd = unsafe { open(path.as_ptr(), O_RDWR | O_NOCTTY) };
        if master_fd < 0 {
            assert!(
                !require_pty,
                "HERDR_CARET_HELPER_REQUIRE_PTY=1 but opening /dev/ptmx failed"
            );
            return None;
        }
        let mut unlock: i32 = 0;
        if unsafe {
            ioctl(
                master_fd,
                TIOCSPTLCK,
                &mut unlock as *mut i32 as *mut c_void,
            )
        } != 0
        {
            unsafe { close(master_fd) };
            assert!(
                !require_pty,
                "HERDR_CARET_HELPER_REQUIRE_PTY=1 but TIOCSPTLCK failed"
            );
            return None;
        }
        let mut n: i32 = 0;
        if unsafe { ioctl(master_fd, TIOCGPTN, &mut n as *mut i32 as *mut c_void) } != 0 {
            unsafe { close(master_fd) };
            assert!(
                !require_pty,
                "HERDR_CARET_HELPER_REQUIRE_PTY=1 but TIOCGPTN failed"
            );
            return None;
        }
        let master = unsafe { std::fs::File::from_raw_fd(master_fd) };
        Some((master, n as u32))
    }

    /// Spawns a real `sleep` child with a real pty as its controlling
    /// terminal, sized `rows`x`cols` (`xpixel`/`ypixel` in pixels, `0` for
    /// "none", same meaning as `Winsize`'s own fields), so
    /// `real_size(child.id())` resolves this exact pty end to end --
    /// unlike `open_test_pty_pair` alone, which opens a pty but never
    /// makes any process's `/proc/<pid>/stat` `tty_nr` point at it.
    /// `setsid` + a fresh `open()` of the slave in the child's `pre_exec`
    /// is the standard way a process acquires a real controlling terminal
    /// (an inherited, already-open fd would not trigger the kernel's
    /// assignment). Mirrors `scrollback/tests/support.rs::spawn_real_pty_process`
    /// test helper (same technique, needed here so the `ZeroDimension` test
    /// goes through `real_size` itself, not just `read_raw_winsize`).
    /// Returns `None` under the same `open_test_pty_pair` skip/
    /// `HERDR_CARET_HELPER_REQUIRE_PTY` rule. The caller must `.kill()` +
    /// `.wait()` the returned `Child`, and keep the returned master `File`
    /// alive for as long as the pty pair is needed (dropping it closes
    /// the pair).
    fn spawn_real_pty_process(
        rows: u16,
        cols: u16,
        xpixel: u16,
        ypixel: u16,
    ) -> Option<(std::process::Child, std::fs::File)> {
        use std::os::unix::process::CommandExt;

        let (master, pts_number) = open_test_pty_pair()?;
        let mut ws = RawWinsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: xpixel,
            ws_ypixel: ypixel,
        };
        let rc = unsafe {
            ioctl(
                master.as_raw_fd(),
                TIOCSWINSZ,
                &mut ws as *mut RawWinsize as *mut c_void,
            )
        };
        assert_eq!(rc, 0, "test setup: TIOCSWINSZ on the master side failed");

        let slave_path = std::ffi::CString::new(format!("/dev/pts/{pts_number}")).unwrap();
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
                let fd = open(slave_path.as_ptr(), O_RDWR);
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
        // Give the child a brief moment to run its `pre_exec`
        // (setsid+open) before any caller reads `/proc/<pid>/stat`.
        std::thread::sleep(std::time::Duration::from_millis(50));
        Some((child, master))
    }

    #[test]
    fn real_size_rejects_zero_dimension_end_to_end() {
        // The `ZeroDimension` rejection must be covered by a test that
        // genuinely goes through `real_size` itself, via a real process
        // with a real controlling pty set to 0x0 -- not just
        // `read_raw_winsize` (that gap is why
        // `read_raw_winsize_reports_zero_dimension_values_verbatim` below
        // was renamed rather than treated as sufficient coverage on its
        // own). This fails if the check in `real_size`/`winsize_from_raw`
        // is ever removed, exactly as the pure
        // `winsize_from_raw_rejects_zero_rows`/`_cols` tests do, but
        // end-to-end through the real pid/pty resolution path too.
        let Some((mut child, _master)) = spawn_real_pty_process(0, 0, 0, 0) else {
            eprintln!(
                "skipping: /dev/ptmx unavailable in this sandbox \
                 (set HERDR_CARET_HELPER_REQUIRE_PTY=1 to make this fail instead)"
            );
            return;
        };
        let got = real_size(child.id());
        let _ = child.kill();
        let _ = child.wait();
        assert_eq!(got, Err(WinsizeError::ZeroDimension));
    }

    #[test]
    fn read_raw_winsize_matches_what_was_set_on_the_master_side() {
        let Some((master, pts_number)) = open_test_pty_pair() else {
            eprintln!(
                "skipping: /dev/ptmx unavailable in this sandbox \
                 (set HERDR_CARET_HELPER_REQUIRE_PTY=1 to make this fail instead)"
            );
            return;
        };
        let want = RawWinsize {
            ws_row: 23,
            ws_col: 71,
            ws_xpixel: 568,
            ws_ypixel: 368,
        };
        let mut want_mut = want;
        let rc = unsafe {
            ioctl(
                master.as_raw_fd(),
                TIOCSWINSZ,
                &mut want_mut as *mut RawWinsize as *mut c_void,
            )
        };
        assert_eq!(rc, 0, "test setup: TIOCSWINSZ on the master side failed");

        let got =
            read_raw_winsize(pts_number).expect("read_raw_winsize on the freshly opened slave");
        assert_eq!(got.ws_row, want.ws_row);
        assert_eq!(got.ws_col, want.ws_col);
        assert_eq!(got.ws_xpixel, want.ws_xpixel);
        assert_eq!(got.ws_ypixel, want.ws_ypixel);
    }

    #[test]
    fn read_raw_winsize_reports_zero_dimension_values_verbatim() {
        // Renamed from `real_size_rejects_zero_dimension`: this test only exercises
        // `read_raw_winsize` against a real pty whose master side was set
        // to 0x0 -- it never calls `real_size` or `winsize_from_raw`, so
        // its old name overstated what it covers. It confirms
        // `read_raw_winsize` itself does not invent or clamp a zero
        // dimension; `winsize_from_raw_rejects_zero_rows`/`_cols` below
        // are the actual (pty-free) regression tests for the rejection
        // logic itself.
        let Some((master, pts_number)) = open_test_pty_pair() else {
            eprintln!(
                "skipping: /dev/ptmx unavailable in this sandbox \
                 (set HERDR_CARET_HELPER_REQUIRE_PTY=1 to make this fail instead)"
            );
            return;
        };
        let mut zero = RawWinsize::default();
        let rc = unsafe {
            ioctl(
                master.as_raw_fd(),
                TIOCSWINSZ,
                &mut zero as *mut RawWinsize as *mut c_void,
            )
        };
        assert_eq!(
            rc, 0,
            "test setup: TIOCSWINSZ(0,0,0,0) on the master side failed"
        );
        let got =
            read_raw_winsize(pts_number).expect("read_raw_winsize on the freshly opened slave");
        assert_eq!(got.ws_row, 0);
        assert_eq!(got.ws_col, 0);
    }

    // -- winsize_from_raw: pure, no pty needed -----------------------------
    // (these replace the
    // old `cell_px_*` tests, which reimplemented the division formula
    // instead of calling production code, and add direct, pty-free
    // coverage for the zero-dimension rejection itself -- including the
    // specific `ws_col == 0` + nonzero `ws_xpixel` combination that would
    // panic on a divide-by-zero if the rejection check were ever removed
    // or reordered after the division.)

    #[test]
    fn winsize_from_raw_rejects_zero_rows() {
        let raw = RawWinsize {
            ws_row: 0,
            ws_col: 80,
            ws_xpixel: 640,
            ws_ypixel: 480,
        };
        assert_eq!(winsize_from_raw(raw), Err(WinsizeError::ZeroDimension));
    }

    #[test]
    fn winsize_from_raw_rejects_zero_cols() {
        // `ws_xpixel` is deliberately non-zero: if the zero-dimension
        // check were removed or moved after the `cell_width_px` division,
        // this would divide by `ws_col == 0` and panic instead of
        // returning `Err`.
        let raw = RawWinsize {
            ws_row: 24,
            ws_col: 0,
            ws_xpixel: 640,
            ws_ypixel: 480,
        };
        assert_eq!(winsize_from_raw(raw), Err(WinsizeError::ZeroDimension));
    }

    #[test]
    fn winsize_from_raw_cell_px_is_zero_when_pixel_dims_are_zero_even_if_rows_cols_are_not() {
        let raw = RawWinsize {
            ws_row: 24,
            ws_col: 80,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let got = winsize_from_raw(raw).expect("non-zero rows/cols must succeed");
        assert_eq!(got.cell_width_px, 0);
        assert_eq!(got.cell_height_px, 0);
    }

    #[test]
    fn winsize_from_raw_divides_nonzero_pixel_dims_by_rows_cols() {
        let raw = RawWinsize {
            ws_row: 16,
            ws_col: 71,
            ws_xpixel: 568,
            ws_ypixel: 368,
        };
        let got = winsize_from_raw(raw).expect("non-zero rows/cols must succeed");
        assert_eq!(got.rows, 16);
        assert_eq!(got.cols, 71);
        assert_eq!(got.cell_width_px, 8);
        assert_eq!(got.cell_height_px, 23);
    }
}
