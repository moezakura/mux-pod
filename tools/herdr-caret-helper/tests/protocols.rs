use herdr_caret_helper::hyperlinks::{run_hyperlinks, HyperlinksParams, DEFAULT_MAX_OUTPUT_BYTES};
use herdr_caret_helper::protocols::{CARET_SUPPORTED_PROTOCOLS, HYPERLINK_SUPPORTED_PROTOCOLS};
use herdr_caret_helper::runner::{run, Params, RunError};
use herdr_caret_helper::{
    is_caret_protocol_supported, is_hyperlink_protocol_supported,
    is_scrollback_link_protocol_supported,
};
use std::process::Command;

#[test]
fn cli_and_runner_use_the_shared_protocol_policy_before_connecting() {
    for protocol in 0..=u8::MAX {
        let supported = CARET_SUPPORTED_PROTOCOLS.contains(&protocol);
        let params = Params {
            // A child of a regular device cannot be a socket.
            socket: "/dev/null/herdr-protocol-test.sock".into(),
            pane: "w1:p1".into(),
            protocol,
            cols: 80,
            rows: 24,
            timeout_ms: 10,
        };
        let error = run(&params).unwrap_err();
        if supported {
            assert!(matches!(error, RunError::Connect), "protocol {protocol}");
        } else {
            assert!(matches!(error, RunError::Usage(_)), "protocol {protocol}");
        }
        let output = Command::new(env!("CARGO_BIN_EXE_herdr-caret-helper"))
            .args([
                "--socket",
                &params.socket,
                "--pane",
                &params.pane,
                "--protocol",
                &protocol.to_string(),
            ])
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        let stderr = String::from_utf8(output.stderr).unwrap();
        let expected = if supported {
            "connect_failed"
        } else {
            "usage_error"
        };
        assert!(stderr.contains(expected), "protocol {protocol}: {stderr}");
    }
}

/// The `hyperlinks` subcommand's own protocol allow-list
/// (`HYPERLINK_SUPPORTED_PROTOCOLS`) checked exhaustively over the full
/// `u8` range, mirroring `cli_and_runner_use_the_shared_protocol_policy_
/// before_connecting` above exactly (both the direct `run_hyperlinks` call
/// and the compiled binary, so this also re-confirms the CLI dispatch
/// itself for every value, not just 22/255 as the two `hyperlinks_cli.rs`
/// spot checks already do).
#[test]
fn hyperlinks_cli_and_run_hyperlinks_use_the_shared_hyperlink_protocol_policy_before_connecting() {
    for protocol in 0..=u8::MAX {
        let supported = HYPERLINK_SUPPORTED_PROTOCOLS.contains(&protocol);
        let params = HyperlinksParams {
            // A child of a regular device cannot be a socket.
            socket: "/dev/null/herdr-hyperlinks-protocol-test.sock".into(),
            api_socket: None,
            pane: "w1:p1".into(),
            protocol,
            cols: 80,
            rows: 24,
            timeout_ms: 10,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
        };
        let error = run_hyperlinks(&params).unwrap_err();
        if supported {
            assert!(matches!(error, RunError::Connect), "protocol {protocol}");
        } else {
            assert!(matches!(error, RunError::Usage(_)), "protocol {protocol}");
        }
        let output = Command::new(env!("CARGO_BIN_EXE_herdr-caret-helper"))
            .args([
                "hyperlinks",
                "--socket",
                &params.socket,
                "--pane",
                &params.pane,
                "--protocol",
                &protocol.to_string(),
            ])
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        let stderr = String::from_utf8(output.stderr).unwrap();
        let expected = if supported {
            "connect_failed"
        } else {
            "usage_error"
        };
        assert!(stderr.contains(expected), "protocol {protocol}: {stderr}");
    }
}

/// The three allow-lists (caret / hyperlink /
/// scrollback-link) are three independent `pub const` bindings in
/// `protocols.rs` (`tools/herdr-protocols.json` regenerates all three
/// separately), not one shared list aliased under three names. Before protocol 22 was added to the caret
/// allow-list, 22 was a value-level witness of that
/// independence (hyperlink/scrollback-link supported it, caret did not).
/// Adding 22 to the caret list intentionally converged all three
/// lists to identical values, so 22 is no longer a differentiating
/// witness; this test now instead confirms that convergence landed
/// correctly (22 supported by all three) and that an always-unsupported
/// protocol (21 — never listed in any of the three source arrays) is still
/// rejected by all three, proving each is a real allow-list check, not a
/// stub that always returns `true`.
#[test]
fn protocol_22_is_supported_by_all_three_allow_lists() {
    assert!(is_caret_protocol_supported(22));
    assert!(is_hyperlink_protocol_supported(22));
    assert!(is_scrollback_link_protocol_supported(22));
}

#[test]
fn protocol_21_is_supported_by_none_of_the_three_allow_lists() {
    assert!(!is_caret_protocol_supported(21));
    assert!(!is_hyperlink_protocol_supported(21));
    assert!(!is_scrollback_link_protocol_supported(21));
}
