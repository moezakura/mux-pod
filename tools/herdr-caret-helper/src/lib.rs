//! Library facade for the herdr-caret-helper wire codec and runner.

pub mod ansi_runner;
pub mod api_client;
pub mod attach;
mod error;
mod frame_io;
pub mod hyperlinks;
pub mod protocols;
pub mod runner;
pub mod scrollback;
pub mod tracker;
pub mod winsize;
pub mod wire;
pub mod wire22;

pub fn is_caret_protocol_supported(protocol: u8) -> bool {
    protocols::CARET_SUPPORTED_PROTOCOLS.contains(&protocol)
}

/// Allow-list check for the `hyperlinks` subcommand
/// (`HYPERLINK_SUPPORTED_PROTOCOLS`).
pub fn is_hyperlink_protocol_supported(protocol: u8) -> bool {
    protocols::HYPERLINK_SUPPORTED_PROTOCOLS.contains(&protocol)
}

/// Allow-list check for the `scrollback-links` subcommand.
pub fn is_scrollback_link_protocol_supported(protocol: u8) -> bool {
    protocols::SCROLLBACK_LINK_SUPPORTED_PROTOCOLS.contains(&protocol)
}
