//! Row fingerprinting and the OSC 8 grammar tracker.
//!
//! Two responsibilities live under this module:
//!
//! - Row fingerprinting (this file): pure functions for the row-mismatch
//!   suppression rule. No I/O, no protocol dependency. This is the Rust half
//!   of a function that is also ported to Dart; both implementations must
//!   produce byte-identical output for byte-identical input. The exact
//!   algorithm and a shared set of test vectors are captured in
//!   `testdata/fingerprint_vectors.json`, which this module's tests also load
//!   and cross-check against.
//! - The OSC 8 grammar tracker (`grammar`): a byte-grammar walk over one
//!   `TerminalAnsi` full-redraw frame, re-exported below so the public paths
//!   stay `tracker::track_frame` and friends.

mod grammar;
#[cfg(test)]
mod grammar_tests;

pub use grammar::{track_frame, RawLinkSpan, TrackError, TrackedFrame};

const FNV1A64_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV1A64_PRIME: u64 = 0x100000001b3;

/// 64-bit FNV-1a hash of `bytes`.
fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = FNV1A64_OFFSET_BASIS;
    for &byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV1A64_PRIME);
    }
    hash
}

/// `fnv1a64` formatted as a zero-padded 16-digit lowercase hex string
/// (`rowHashes` / `rowFingerprints` are zero-padded 16-digit lowercase hex
/// strings).
pub fn fnv1a64_hex(bytes: &[u8]) -> String {
    format!("{:016x}", fnv1a64(bytes))
}

/// Row fingerprint for the row-mismatch suppression rule.
///
/// `display_text` must already be the row's display string (the written
/// cells' characters concatenated; no double-wide
/// continuation cells). This function performs only the
/// normalization — stripping trailing U+0020 (space) characters — and then
/// hashes the remaining string's UTF-8 bytes. Returns `None` when the
/// string is empty after stripping: an empty row has no fingerprint.
pub fn row_fingerprint(display_text: &str) -> Option<String> {
    let trimmed = display_text.trim_end_matches('\u{0020}');
    if trimmed.is_empty() {
        None
    } else {
        Some(fnv1a64_hex(trimmed.as_bytes()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use std::fs;
    use std::path::Path;

    // Well-known FNV-1a-64 reference vectors (http://www.isthe.com/chongo/tech/comp/fnv/),
    // used to verify this from-scratch implementation independently of any
    // Herdr-specific behavior.
    #[test]
    fn fnv1a64_hex_matches_well_known_reference_vectors() {
        assert_eq!(fnv1a64_hex(b""), "cbf29ce484222325");
        assert_eq!(fnv1a64_hex(b"a"), "af63dc4c8601ec8c");
        assert_eq!(fnv1a64_hex(b"foobar"), "85944171f73967e8");
    }

    #[test]
    fn row_fingerprint_ascii() {
        assert_eq!(
            row_fingerprint("hello world"),
            Some(fnv1a64_hex(b"hello world"))
        );
    }

    #[test]
    fn row_fingerprint_strips_trailing_space_only() {
        // Trailing U+0020 is stripped; a trailing tab or other whitespace is
        // not (only U+0020 is specified, not "whitespace" broadly).
        assert_eq!(row_fingerprint("hello   "), Some(fnv1a64_hex(b"hello")));
        assert_eq!(
            row_fingerprint("hello\t"),
            Some(fnv1a64_hex("hello\t".as_bytes()))
        );
    }

    #[test]
    fn row_fingerprint_whitespace_only_row_has_no_fingerprint() {
        assert_eq!(row_fingerprint("   "), None);
        assert_eq!(row_fingerprint(""), None);
    }

    #[test]
    fn row_fingerprint_cjk_fullwidth() {
        let text = "こんにちは";
        assert_eq!(row_fingerprint(text), Some(fnv1a64_hex(text.as_bytes())));
    }

    #[test]
    fn row_fingerprint_combining_character() {
        // "e" + COMBINING ACUTE ACCENT (U+0301), not the precomposed U+00E9.
        let text = "cafe\u{0301}";
        assert_eq!(row_fingerprint(text), Some(fnv1a64_hex(text.as_bytes())));
    }

    #[derive(Deserialize)]
    struct FingerprintVector {
        #[serde(rename = "displayText")]
        display_text: String,
        #[serde(rename = "fingerprint")]
        fingerprint: Option<String>,
    }

    /// Cross-checks `row_fingerprint` against the shared test vectors
    /// (`testdata/fingerprint_vectors.json`) that the Dart port
    /// also consumes, so both implementations are pinned to the
    /// same fixed values rather than only to each other's source code.
    #[test]
    fn row_fingerprint_matches_shared_fingerprint_vectors_json() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/fingerprint_vectors.json");
        let raw = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
        let vectors: Vec<FingerprintVector> =
            serde_json::from_str(&raw).expect("fingerprint_vectors.json must be a JSON array");
        assert!(
            !vectors.is_empty(),
            "fingerprint_vectors.json must not be empty"
        );
        for vector in &vectors {
            assert_eq!(
                row_fingerprint(&vector.display_text),
                vector.fingerprint,
                "mismatch for displayText {:?}",
                vector.display_text
            );
        }
    }
}
