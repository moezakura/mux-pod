//! Per-pane exclusive lock for `scrollback-links`.
//!
//! `acquire_lock` takes an OS-level file lock keyed by the herdr API socket
//! and pane, so two invocations never move the same pane's viewport at once.

use crate::error::RunError;
use std::fs::{DirBuilder, OpenOptions};
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};

/// Holds the per-pane exclusive lock for the lifetime of one
/// `scrollback-links` invocation. Dropping it (including on panic or
/// process exit) releases the OS-level lock automatically — no stale
/// lock can be left behind by a crash.
pub struct ScrollbackLock {
    _file: std::fs::File,
}

fn lock_file_path(lock_dir: &str, api_socket: &str, pane: &str) -> PathBuf {
    // `<fnv1a64(apiSocket + NUL + paneId)>.lock`.
    let mut bytes = Vec::with_capacity(api_socket.len() + 1 + pane.len());
    bytes.extend_from_slice(api_socket.as_bytes());
    bytes.push(0);
    bytes.extend_from_slice(pane.as_bytes());
    let name = crate::tracker::fnv1a64_hex(&bytes);
    Path::new(lock_dir).join(format!("{name}.lock"))
}

/// Acquires the per-pane lock: creates `lock_dir` with mode 0700 if it
/// does not already exist (an existing directory's permissions are left
/// untouched — `DirBuilder::create` with `recursive(true)` is a no-op on
/// an already-existing directory and does not chmod it, verified against
/// this toolchain), then opens (create-if-missing, **not** truncating —
/// `OpenOptions` without `.truncate(true)`) the lock file and takes a
/// non-blocking exclusive lock via `File::try_lock` (stable since Rust
/// 1.89; toolchain here is 1.94.1, `rust-toolchain.toml`).
///
/// Failure classification: a directory creation I/O failure (e.g. permission
/// denied) is `RunError::Io` (`io_error`); *only* `try_lock` contention
/// (`TryLockError::WouldBlock`, another `scrollback-links` invocation
/// already holds it for this pane) is `RunError::Busy` (`busy`). Any other
/// `try_lock` failure (`TryLockError::Error`, e.g. `ENOLCK`, a filesystem
/// that does not support locking) is `RunError::Io`, not `Busy` — the
/// caller must not blindly retry an unrelated I/O failure as if it were
/// ordinary contention.
pub fn acquire_lock(
    lock_dir: &str,
    api_socket: &str,
    pane: &str,
) -> Result<ScrollbackLock, RunError> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(lock_dir)
        .map_err(|_| RunError::Io)?;

    let path = lock_file_path(lock_dir, api_socket, pane);
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        // Explicitly false (not the default's ambiguity): a re-run must
        // never wipe the lock file's contents, only `try_lock()` it below.
        .truncate(false)
        .open(&path)
        .map_err(|_| RunError::Io)?;
    classify_try_lock_result(file.try_lock())?;
    Ok(ScrollbackLock { _file: file })
}

fn classify_try_lock_result(result: Result<(), std::fs::TryLockError>) -> Result<(), RunError> {
    match result {
        Ok(()) => Ok(()),
        Err(std::fs::TryLockError::WouldBlock) => Err(RunError::Busy),
        Err(std::fs::TryLockError::Error(_)) => Err(RunError::Io),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acquire_lock_creates_missing_lock_dir_as_0700() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.join("locks");
        let _lock = acquire_lock(lock_dir.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let mode = std::fs::metadata(&lock_dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700);
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_does_not_change_permissions_of_an_existing_lock_dir() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-existing-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let _lock = acquire_lock(tmp.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let mode = std::fs::metadata(&tmp).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            mode, 0o755,
            "pre-existing directory permissions must be left untouched"
        );
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_second_holder_for_the_same_pane_is_busy() {
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-busy-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.to_str().unwrap();
        let first = acquire_lock(lock_dir, "api.sock", "w1:p1").expect("first lock");
        let second = acquire_lock(lock_dir, "api.sock", "w1:p1");
        assert!(matches!(second, Err(RunError::Busy)));
        drop(first);
        // Once released, a fresh acquire succeeds again.
        let third = acquire_lock(lock_dir, "api.sock", "w1:p1");
        assert!(third.is_ok());
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_different_panes_do_not_contend() {
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-multi-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let lock_dir = tmp.to_str().unwrap();
        let a = acquire_lock(lock_dir, "api.sock", "w1:p1").expect("lock pane 1");
        let b = acquire_lock(lock_dir, "api.sock", "w1:p2").expect("lock pane 2 (different pane)");
        drop(a);
        drop(b);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn acquire_lock_preserves_existing_lock_file_contents() {
        // The lock file must be `create`d, not
        // truncated — a re-run must not wipe any content that might
        // already be there (even though this module never writes to it
        // today, the open mode itself must not truncate).
        let tmp = std::env::temp_dir().join(format!(
            "scrollback-lock-test-notrunc-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&tmp).unwrap();
        let path = lock_file_path(tmp.to_str().unwrap(), "api.sock", "w1:p1");
        std::fs::write(&path, b"marker").unwrap();
        let _lock = acquire_lock(tmp.to_str().unwrap(), "api.sock", "w1:p1").expect("lock");
        let contents = std::fs::read(&path).unwrap();
        assert_eq!(contents, b"marker");
        drop(_lock);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn try_lock_would_block_classifies_as_busy() {
        // Only WouldBlock (genuine contention) is Busy.
        let r = classify_try_lock_result(Err(std::fs::TryLockError::WouldBlock));
        assert!(matches!(r, Err(RunError::Busy)));
    }

    #[test]
    fn try_lock_other_error_classifies_as_io_not_busy() {
        // A non-contention try_lock failure (e.g. ENOLCK, a filesystem
        // without lock support) must not be reported as `busy` — the
        // caller would otherwise retry it as if another invocation held
        // the lock, which is not what happened.
        let io_err = std::io::Error::other("simulated");
        let r = classify_try_lock_result(Err(std::fs::TryLockError::Error(io_err)));
        assert!(matches!(r, Err(RunError::Io)));
    }

    #[test]
    fn try_lock_ok_classifies_as_ok() {
        let r = classify_try_lock_result(Ok(()));
        assert!(r.is_ok());
    }
}
