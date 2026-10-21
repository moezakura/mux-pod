//! Crate-wide error type for the helper's subcommands.
//!
//! `RunError` is shared by the caret runner, `ansi_runner`, `attach`,
//! `api_client`, `hyperlinks`, and `scrollback`; it lives here so those
//! modules do not depend on the caret runner. `runner` re-exports it, so
//! `herdr_caret_helper::runner::RunError` keeps working.

/// Error kinds safe for stderr emission (never carry socket path / payload / content).
///
/// Kind strings (see `json()`) follow the documented failure classification
/// verbatim: the common set (`usage_error`/`connect_failed`/`io_error`/
/// `timeout`/`welcome_rejected`/`protocol_error`/`decode_error`) plus
/// `render_rejected` (the `hyperlinks`/caret-22 tracker rejecting a frame)
/// and, for `scrollback-links` only, `busy`,
/// `unsupported_scroll`, and `attach_rejected`.
#[derive(Debug)]
pub enum RunError {
    /// Could not connect to the socket.
    Connect,
    /// An I/O failure (EOF, reset, partial frame).
    Io,
    /// Deadline elapsed before a usable frame arrived.
    Timeout,
    /// The server rejected the handshake (Welcome.error present).
    WelcomeRejected(String),
    /// Protocol-level mismatch (version, encoding, wrong message, unknown variant).
    Protocol(String),
    /// Bincode/serialization failure.
    Bincode(String),
    /// CLI usage error.
    Usage(String),
    /// The tracker rejected an observed `TerminalAnsi` frame (unknown escape
    /// sequence, invariant violation, wrong `full` state —
    /// fail-closed condition). Kind: `render_rejected`.
    RenderRejected(String),
    /// `AttachTerminal` was rejected, or the attach connection was
    /// disconnected mid-session (`ServerShutdown`, protocol error while
    /// attached). Used by the 17/20 `scrollback-links` attach path.
    /// Kind: `attach_rejected`.
    AttachRejected(String),
    /// The per-pane `scrollback-links` lock file could not be acquired
    /// (another invocation already holds it for this pane). Kind: `busy`.
    Busy,
    /// The connected herdr server does not support `pane.scroll`
    /// (added in v0.9.0; 17/20 servers predate it). Kind: `unsupported_scroll`.
    UnsupportedScroll,
    /// The real pty size could not be
    /// determined (`winsize::real_size` failed, or `pane.process_info`
    /// returned no `shell_pid`) for a `scrollback-links` invocation on
    /// 17/20, which needs it to avoid resizing the pane's live terminal.
    /// None of the other 11 kinds fit -- this is a local failure before any
    /// wire connection is even attempted, not a wire-level I/O/protocol
    /// issue (`Io`/`Protocol`) or a server-side rejection
    /// (`AttachRejected`). Kind: `winsize_unavailable`.
    WinsizeUnavailable(String),
}

impl RunError {
    pub fn json(&self) -> String {
        let kind = match self {
            RunError::Connect => "connect_failed",
            RunError::Io => "io_error",
            RunError::Timeout => "timeout",
            RunError::WelcomeRejected(_) => "welcome_rejected",
            RunError::Protocol(_) => "protocol_error",
            RunError::Bincode(_) => "decode_error",
            RunError::Usage(_) => "usage_error",
            RunError::RenderRejected(_) => "render_rejected",
            RunError::AttachRejected(_) => "attach_rejected",
            RunError::Busy => "busy",
            RunError::UnsupportedScroll => "unsupported_scroll",
            RunError::WinsizeUnavailable(_) => "winsize_unavailable",
        };
        // The detail is macro-safe: only the reason string (no path/payload/content).
        serde_json::to_string(&serde_json::json!({ "error": kind }))
            .unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
    }
}

#[cfg(test)]
mod run_error_json_tests {
    use super::RunError;

    /// One assertion per kind, so a future rename/typo in `json()` breaks a
    /// test instead of silently drifting from the documented wording.
    #[test]
    fn json_kind_matches_documented_wording() {
        let cases: &[(RunError, &str)] = &[
            (RunError::Connect, "connect_failed"),
            (RunError::Io, "io_error"),
            (RunError::Timeout, "timeout"),
            (
                RunError::WelcomeRejected("x".to_owned()),
                "welcome_rejected",
            ),
            (RunError::Protocol("x".to_owned()), "protocol_error"),
            (RunError::Bincode("x".to_owned()), "decode_error"),
            (RunError::Usage("x".to_owned()), "usage_error"),
            (RunError::RenderRejected("x".to_owned()), "render_rejected"),
            (RunError::AttachRejected("x".to_owned()), "attach_rejected"),
            (RunError::Busy, "busy"),
            (RunError::UnsupportedScroll, "unsupported_scroll"),
            (
                RunError::WinsizeUnavailable("x".to_owned()),
                "winsize_unavailable",
            ),
        ];
        for (err, expected_kind) in cases {
            assert_eq!(
                err.json(),
                format!("{{\"error\":\"{}\"}}", expected_kind),
                "kind mismatch for {:?}",
                err
            );
        }
    }
}
