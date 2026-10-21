//! Minimal wire subset for herdr protocol 22 (v0.9.1's unified endpoint
//! protocol). Reproduces just enough of the upstream `ClientMessage` /
//! `ServerMessage` enums (`src/protocol/wire.rs`, `PROTOCOL_VERSION = 22`) to
//! perform the read-only `TerminalHello` -> `Welcome` -> `ObserveTerminal` ->
//! `Resize` -> `Terminal` handshake used by
//! `ansi_runner::observe_terminal_ansi`.
//!
//! Unlike protocol 17/20, protocol 22 folds client and server messages into
//! single crate-wide enums with over 20 variants, most unrelated to a
//! read-only terminal observer (client-owned shell handshake, graphics
//! transmission, clipboard, ...). Reproducing all of them field-for-field is
//! unnecessary: this helper never constructs or inspects them. Two different
//! strategies are used, matched to which side of the wire each enum sits on:
//!
//! - `ClientMessage22` (sent by this helper) keeps every variant in the exact
//!   tag order of the upstream `ClientMessage` so the three variants actually
//!   serialized here (`TerminalHello`, `Resize`, `ObserveTerminal`) land on
//!   the correct bincode tag. Every other variant is a placeholder never
//!   constructed by this helper — the same "kept in the correct tag order but
//!   never serialized" convention already used for the never-sent
//!   `AttachScrollSource`/`ClientInputEvent` payloads in `wire.rs`. Since this
//!   type is only ever *encoded*, a placeholder's shape cannot desynchronize
//!   anything on the wire.
//! - `ServerMessage22Known` (received by this helper) is deliberately **not**
//!   a full reproduction of the upstream `ServerMessage`. That full enum has
//!   ~20 variants carrying real payloads (`Notify`, `WindowTitle`,
//!   `MouseCapture`, ...) that a live server may legitimately send to an
//!   observer before the first `Terminal` frame arrives. Reproducing them as
//!   tag-order placeholders (the `ClientMessage22` strategy) would risk
//!   misdecoding any such message that carries real payload bytes, since a
//!   placeholder's shape would not match the real fields on the wire — a
//!   full-enum decode only reads exactly as many bytes as the placeholder
//!   declares, then rejects the frame as `trailing_bytes` even though the
//!   frame was perfectly well-formed. Instead this type declares only the two
//!   variants this helper understands, at their real tag positions
//!   (`Welcome` = 0, `Terminal` = 1). Decoding any other (real) tag fails
//!   cleanly with an "unrecognized variant" error, without ever touching the
//!   payload bytes; the caller (`ansi_runner::observe22_ansi`) already holds
//!   the whole length-framed message as an opaque byte buffer at that point
//!   (see `wire::read_frame_bytes`), so it can simply discard it and read the
//!   next frame instead of misinterpreting it.

use crate::wire::{RenderEncoding, TerminalFrame};
use serde::{Deserialize, Serialize};

/// Messages sent from this helper to a herdr protocol-22 server.
///
/// Variant order mirrors upstream `ClientMessage` exactly, tag-for-tag, so
/// the variants this helper actually serializes (`TerminalHello` = 0,
/// `Resize` = 3, `ObserveTerminal` = 7) get the correct bincode tag. Every
/// other variant is a placeholder never constructed by this helper.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientMessage22 {
    /// Direct terminal handshake (tag 0). This helper always sends
    /// `cell_width_px: 0, cell_height_px: 0` (no Kitty graphics) and
    /// `pixel_mouse: false` (read-only observer, no mouse forwarding).
    TerminalHello {
        version: u32,
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
        pixel_mouse: bool,
    },
    /// Placeholder (tag 1, real shape `Input { data: Vec<u8> }`). Never
    /// constructed by this helper.
    Input,
    /// Placeholder (tag 2). Never constructed by this helper.
    ClipboardImage,
    /// Terminal resize notification (tag 3), used as the render kick (same
    /// role as `ClientMessage17`/`ClientMessage20`'s `Resize` after
    /// `ObserveTerminal`).
    Resize {
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
        pixel_mouse: bool,
    },
    /// Placeholder (tag 4, real shape is unit `Detach`). Never constructed
    /// by this helper — protocol 22's `scrollback-links` support uses
    /// `pane.scroll` over the JSON API instead of attach/detach.
    Detach,
    /// Placeholder (tag 5). Never constructed by this helper.
    AttachTerminal,
    /// Placeholder (tag 6). Never constructed by this helper.
    AttachScroll,
    /// Switch this connection into read-only terminal observe mode (tag 7).
    ObserveTerminal { target: String },
    /// Placeholder (tag 8). Never constructed by this helper.
    ControlTerminal,
    /// Placeholder (tag 9). Never constructed by this helper.
    GraphicsTransmissionResult,
    /// Placeholder (tag 10). Never constructed by this helper.
    GraphicsTransmissionStarted,
    /// Placeholder (tag 11). Never constructed by this helper.
    ClientShellHello,
    /// Placeholder (tag 12). Never constructed by this helper.
    ClientShellResize,
    /// Placeholder (tag 13). Never constructed by this helper.
    ClientShellPaneInput,
    /// Placeholder (tag 14). Never constructed by this helper.
    ClientShellPopupInput,
    /// Placeholder (tag 15). Never constructed by this helper.
    ClientShellEndpointRequest,
    /// Placeholder (tag 16). Never constructed by this helper.
    AttachMouse,
    /// Placeholder (tag 17). Never constructed by this helper.
    ClientShellHostTheme,
    /// Placeholder (tag 18). Never constructed by this helper.
    ClientShellFocus,
    /// Placeholder (tag 19). Never constructed by this helper.
    ClientShellMouseCapture,
    /// Placeholder (tag 20). Never constructed by this helper.
    EndpointControl,
}

/// The subset of upstream `ServerMessage` (protocol 22) this helper can fully
/// decode, at their real tag positions (`Welcome` = 0, `Terminal` = 1). See
/// the module doc comment for why this is deliberately not a full
/// reproduction of every server variant.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServerMessage22Known {
    Welcome {
        version: u32,
        encoding: RenderEncoding,
        error: Option<String>,
    },
    Terminal(TerminalFrame),
}
