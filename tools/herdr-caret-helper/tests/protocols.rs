use herdr_caret_helper::protocols::CARET_SUPPORTED_PROTOCOLS;
use herdr_caret_helper::runner::{run, Params, RunError};
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
