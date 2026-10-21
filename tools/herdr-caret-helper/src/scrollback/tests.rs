//! Behavioural tests for the `scrollback-links` orchestration, driven by fake
//! herdr API and render sockets. `support` holds the shared fixtures; each
//! other module is one focused suite.

mod position;
mod restore;
mod round_trip;
mod run_attach_terminal_id;
mod run_failures;
mod run_guard_and_discard;
mod run_happy_path;
mod support;
