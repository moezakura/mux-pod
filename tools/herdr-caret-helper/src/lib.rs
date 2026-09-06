//! Library facade for the herdr-caret-helper wire codec and runner.

pub mod wire;
pub mod runner;
pub mod protocols;

pub fn is_caret_protocol_supported(protocol: u8) -> bool {
    protocols::CARET_SUPPORTED_PROTOCOLS.contains(&protocol)
}
