//! Regression tests for `hyperlinks::aggregate_frame` against the
//! real captured fixtures, confirming same-URL aggregation and
//! `rowHashes` coverage against the fixtures' known content.

use herdr_caret_helper::hyperlinks::{aggregate_frame, AggregatedLink};
use std::fs;

#[test]
fn v22_full_redraw_fixture_aggregates_five_distinct_links_with_one_range_each() {
    // v22_full_redraw.bin holds 5 known links, none repeated, so 5
    // AggregatedLink entries. The "osc8-wrapped-long-url" one's text (78
    // chars, starting at col 2) happens to land exactly on the fixture's
    // last column (width 80, cols 0-79) — confirmed by inspecting the raw
    // fixture bytes directly: the link closes at col 79 and the row-change
    // CUP that follows (`ESC[7;1H`) is for unrelated, unlinked text
    // ("end") on the next row, not a continuation of this link. This is
    // exactly the case `tracker.rs`'s row-change-close fix handles: a single
    // range ending at `width - 1`,
    // not a spurious empty second range on the next row.
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let out = aggregate_frame(&bytes, 80, 40).expect("v22 fixture must not be rejected");
    assert_eq!(out.links.len(), 5, "links={:?}", out.links);

    let wrapped = out
        .links
        .iter()
        .find(|l| l.url == "https://example.com/osc8-wrapped-long-url")
        .expect("wrapped-long-url must be present");
    assert_eq!(wrapped.ranges.len(), 1, "ranges={:?}", wrapped.ranges);
    let (_, _, end_col) = wrapped.ranges[0];
    assert_eq!(
        end_col, 79,
        "must close exactly at the fixture's last column (width 80)"
    );

    for link in &out.links {
        assert_eq!(
            link.ranges.len(),
            1,
            "url={} ranges={:?}",
            link.url,
            link.ranges
        );
    }
}

/// The *exact* `(row,
/// startCol, endCol)` triples for every one of the 5 known v22 links, not
/// just counts/presence — same ground-truth values as `tests/
/// hyperlinks_grammar.rs`'s tracker-level exact-range test (this is the
/// aggregation layer's own regression guard that `aggregate_links`'s
/// URL-grouping does not perturb any range while grouping).
#[test]
fn v22_full_redraw_fixture_aggregates_exact_known_ranges_per_url() {
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let out = aggregate_frame(&bytes, 80, 40).expect("v22 fixture must not be rejected");
    let mut links = out.links.clone();
    links.sort_by(|a, b| a.url.cmp(&b.url));
    let mut expected = vec![
        AggregatedLink {
            url: "https://example.com/osc8-https".to_owned(),
            ranges: vec![(1, 2, 11)],
        },
        AggregatedLink {
            url: "http://example.com/osc8-http".to_owned(),
            ranges: vec![(2, 2, 10)],
        },
        AggregatedLink {
            url: "file:///etc/hostname".to_owned(),
            ranges: vec![(3, 2, 10)],
        },
        AggregatedLink {
            url: "https://example.com/osc8-red".to_owned(),
            ranges: vec![(4, 2, 9)],
        },
        AggregatedLink {
            url: "https://example.com/osc8-wrapped-long-url".to_owned(),
            ranges: vec![(5, 2, 79)],
        },
    ];
    expected.sort_by(|a, b| a.url.cmp(&b.url));
    assert_eq!(links, expected, "links={:?}", out.links);
}

#[test]
fn v17_and_v20_full_redraw_fixtures_aggregate_two_distinct_single_range_links() {
    for (path, width, height) in [
        ("tests/fixtures/v17_full_redraw.bin", 80u16, 24u16),
        ("tests/fixtures/v20_full_redraw.bin", 100u16, 29u16),
    ] {
        let bytes = fs::read(path).unwrap_or_else(|e| panic!("failed to read {path}: {e}"));
        let out = aggregate_frame(&bytes, width, height)
            .unwrap_or_else(|e| panic!("{path} must not be rejected: {e:?}"));
        assert_eq!(out.links.len(), 2, "{path}: links={:?}", out.links);
        for link in &out.links {
            assert_eq!(
                link.ranges.len(),
                1,
                "{path}: url={} ranges={:?}",
                link.url,
                link.ranges
            );
        }
    }
}

/// Exact ranges for v17/v20 too, mirroring the v22 exact
/// range test above — both fixtures were captured from the same demo
/// script, so (per `tests/hyperlinks_grammar.rs`'s version-parity test)
/// they must aggregate to the identical two ranges despite v17's
/// every-cell CUP vs v20's CUP-omission-after-ASCII grammar.
#[test]
fn v17_and_v20_full_redraw_fixtures_aggregate_identical_exact_ranges() {
    for (path, width, height) in [
        ("tests/fixtures/v17_full_redraw.bin", 80u16, 24u16),
        ("tests/fixtures/v20_full_redraw.bin", 100u16, 29u16),
    ] {
        let bytes = fs::read(path).unwrap_or_else(|e| panic!("failed to read {path}: {e}"));
        let out = aggregate_frame(&bytes, width, height)
            .unwrap_or_else(|e| panic!("{path} must not be rejected: {e:?}"));
        let mut links = out.links.clone();
        links.sort_by(|a, b| a.url.cmp(&b.url));
        let mut expected = vec![
            AggregatedLink {
                url: "https://example.com/osc8-https".to_owned(),
                ranges: vec![(1, 2, 11)],
            },
            AggregatedLink {
                url: "http://example.com/osc8-http".to_owned(),
                ranges: vec![(2, 2, 10)],
            },
        ];
        expected.sort_by(|a, b| a.url.cmp(&b.url));
        assert_eq!(links, expected, "{path}: links={:?}", out.links);
    }
}

/// Real row-crossing fixtures: a link that genuinely
/// spans multiple physical rows, aggregated. v20/v22 open the URL once and
/// continue silently across the row-changing CUP, so each aggregates to a
/// single `AggregatedLink` with 2 ranges (one per row) -- byte-identical
/// between the two versions (same demo script, same 73-column width). v17
/// instead re-opens the same URL once per physical row (3 explicit
/// open/close pairs per link -- see `tests/hyperlinks_grammar.rs`'s
/// `v17_wrapped_link_fixture_...` test), so this is also the test that
/// `aggregate_links`'s URL-grouping correctly merges those 3 separate raw
/// spans into a single 3-range `AggregatedLink`, not 3 separate entries.
#[test]
fn v20_and_v22_wrapped_link_fixtures_aggregate_identical_exact_two_row_ranges() {
    for (path, width, height) in [
        ("tests/fixtures/v20_wrapped_link.bin", 73u16, 28u16),
        ("tests/fixtures/v22_wrapped_link.bin", 73u16, 29u16),
    ] {
        let bytes = fs::read(path).unwrap_or_else(|e| panic!("failed to read {path}: {e}"));
        let out = aggregate_frame(&bytes, width, height)
            .unwrap_or_else(|e| panic!("{path} must not be rejected: {e:?}"));
        let mut links = out.links.clone();
        links.sort_by(|a, b| a.url.cmp(&b.url));
        let mut expected = vec![
            AggregatedLink {
                url: "https://example.com/osc8-wrap-ascii".to_owned(),
                ranges: vec![(1, 2, 72), (2, 0, 39)],
            },
            AggregatedLink {
                url: "https://example.com/osc8-wrap-cjk".to_owned(),
                ranges: vec![(3, 2, 72), (4, 0, 49)],
            },
        ];
        expected.sort_by(|a, b| a.url.cmp(&b.url));
        assert_eq!(links, expected, "{path}: links={:?}", out.links);
    }
}

#[test]
fn v17_wrapped_link_fixture_aggregates_three_per_row_spans_into_one_link_each() {
    let bytes = fs::read("tests/fixtures/v17_wrapped_link.bin").expect("fixture must exist");
    let out =
        aggregate_frame(&bytes, 53, 23).expect("v17 wrapped-link fixture must not be rejected");
    let mut links = out.links.clone();
    links.sort_by(|a, b| a.url.cmp(&b.url));
    let mut expected = vec![
        AggregatedLink {
            url: "https://example.com/osc8-wrap-ascii".to_owned(),
            ranges: vec![(1, 2, 52), (2, 0, 52), (3, 0, 6)],
        },
        AggregatedLink {
            url: "https://example.com/osc8-wrap-cjk".to_owned(),
            ranges: vec![(4, 2, 52), (5, 0, 52), (6, 0, 17)],
        },
    ];
    expected.sort_by(|a, b| a.url.cmp(&b.url));
    assert_eq!(links, expected, "links={:?}", out.links);
}

#[test]
fn v22_full_redraw_fixture_row_hashes_are_non_empty_and_row_ascending() {
    let bytes = fs::read("tests/fixtures/v22_full_redraw.bin").expect("fixture must exist");
    let out = aggregate_frame(&bytes, 80, 40).expect("v22 fixture must not be rejected");
    assert!(!out.row_hashes.is_empty());
    let mut prev: Option<u16> = None;
    for (row, fingerprint) in &out.row_hashes {
        assert_eq!(
            fingerprint.len(),
            16,
            "fingerprint must be 16 lowercase hex digits"
        );
        if let Some(p) = prev {
            assert!(*row > p, "row_hashes must be strictly row-ascending");
        }
        prev = Some(*row);
    }
}

#[test]
fn aggregate_frame_drops_only_the_link_whose_uri_has_a_control_byte() {
    // A C0 byte in one OSC 8 URI excludes that link only; the valid
    // link, the row text fingerprint and the other rows stay intact.
    let bytes = "\x1b[1;1H\x1b]8;;https://bad/\x00x\x1b\\bad\x1b]8;;https://good/\x1b\\ok\x1b]8;;\x1b\\\x1b[2;1Hrow2";
    let out = aggregate_frame(bytes.as_bytes(), 80, 24).expect("must not be rejected");
    assert_eq!(out.links.len(), 1, "links={:?}", out.links);
    assert_eq!(out.links[0].url, "https://good/");
    assert_eq!(out.links[0].ranges, vec![(0, 3, 4)]);
    let rows: Vec<u16> = out.row_hashes.iter().map(|(r, _)| *r).collect();
    assert_eq!(rows, vec![0, 1]);
}
