//! Herdr wire protocol types and framing, reproduced from the upstream
//! `src/protocol/wire.rs` for protocol 17 (herdr v0.7.5) and protocol 20
//! (herdr v0.8.2).
//!
//! Framing is identical to herdr: `[u32 little-endian length][bincode 2 payload]`
//! with `bincode::serde` and `bincode::config::standard()` (variable-int,
//! little-endian). Only `Hello` and `ObserveTerminal` are ever *produced* by
//! this helper; `ServerMessage` is decoded. The unused `ClientMessage` variants
//! are kept in the correct tag order with minimal payload shapes so tag numbers
//! remain stable, but they are never serialized.

use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

/// Maximum accepted frame payload size (16 MiB), well under `u32::MAX`.
pub const MAX_FRAME_SIZE: usize = 16 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Types shared by protocol 17 and protocol 20
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderEncoding {
    SemanticFrame,
    TerminalAnsi,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientKeybindings {
    Server,
    Local { keys_toml: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CellData {
    pub symbol: String,
    pub fg: u32,
    pub bg: u32,
    pub modifier: u16,
    pub skip: bool,
    pub hyperlink: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CursorState {
    pub x: u16,
    pub y: u16,
    pub visible: bool,
    #[serde(default)]
    pub shape: u8,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrameData {
    pub cells: Vec<CellData>,
    pub width: u16,
    pub height: u16,
    pub cursor: Option<CursorState>,
    pub hyperlinks: Vec<String>,
    pub graphics: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerminalFrame {
    pub seq: u64,
    pub width: u16,
    pub height: u16,
    pub full: bool,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NotifyKind {
    Sound,
    Toast,
    SystemToast,
}

// ---------------------------------------------------------------------------
// Protocol 17 (herdr v0.7.5): ClientLaunchMode = { App=0, TerminalAttach=1 }
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientLaunchMode17 {
    App,
    TerminalAttach,
}

/// Minimal placeholder for the never-serialized `AttachScroll.source` field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AttachScrollSource {
    Wheel,
    PageKey,
}

/// Minimal placeholder for the never-serialized `InputEvents` payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientInputEvent {
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientMessage17 {
    Hello {
        version: u32,
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
        requested_encoding: RenderEncoding,
        keybindings: ClientKeybindings,
        launch_mode: ClientLaunchMode17,
    },
    Input { data: Vec<u8> },
    ClipboardImage { extension: String, data: Vec<u8> },
    Resize {
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
    },
    Detach,
    AttachTerminal { terminal_id: String, takeover: bool },
    AttachScroll {
        source: AttachScrollSource,
        direction: u8,
        lines: u16,
        column: Option<u16>,
        row: Option<u16>,
        modifiers: u8,
    },
    InputEvents { events: Vec<ClientInputEvent> },
    ObserveTerminal { target: String },
    ControlTerminal { target: String, takeover: bool },
}

// ---------------------------------------------------------------------------
// Protocol 20 (herdr v0.8.2): ClientLaunchMode =
// { App=0, AppDirectGraphics=1, TerminalAttach=2 }
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientLaunchMode20 {
    App,
    AppDirectGraphics,
    TerminalAttach,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientMessage20 {
    Hello {
        version: u32,
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
        requested_encoding: RenderEncoding,
        keybindings: ClientKeybindings,
        launch_mode: ClientLaunchMode20,
    },
    Input { data: Vec<u8> },
    ClipboardImage { extension: String, data: Vec<u8> },
    Resize {
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
    },
    Detach,
    AttachTerminal { terminal_id: String, takeover: bool },
    AttachScroll {
        source: AttachScrollSource,
        direction: u8,
        lines: u16,
        column: Option<u16>,
        row: Option<u16>,
        modifiers: u8,
    },
    InputEvents { events: Vec<ClientInputEvent> },
    ObserveTerminal { target: String },
    ControlTerminal { target: String, takeover: bool },
}

// ---------------------------------------------------------------------------
// ServerMessage (protocol 17): Welcome=0 .. PrefixInputSource=10
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServerMessage17 {
    Welcome {
        version: u32,
        encoding: RenderEncoding,
        error: Option<String>,
    },
    Frame(FrameData),
    Terminal(TerminalFrame),
    Graphics { bytes: Vec<u8> },
    ServerShutdown { reason: Option<String> },
    Notify {
        kind: NotifyKind,
        message: String,
        body: Option<String>,
    },
    Clipboard { data: String },
    WindowTitle { title: Option<String> },
    ReloadSoundConfig,
    MouseCapture { enabled: bool },
    PrefixInputSource { active: bool },
}

// ---------------------------------------------------------------------------
// ServerMessage (protocol 20): Welcome=0 .. GraphicsTransmissionRetired=14
// (MouseCapture gained `sgr_pixels`; KittyKeyboardReportAll inserted)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServerMessage20 {
    Welcome {
        version: u32,
        encoding: RenderEncoding,
        error: Option<String>,
    },
    Frame(FrameData),
    Terminal(TerminalFrame),
    Graphics { bytes: Vec<u8> },
    ServerShutdown { reason: Option<String> },
    Notify {
        kind: NotifyKind,
        message: String,
        body: Option<String>,
    },
    Clipboard { data: String },
    WindowTitle { title: Option<String> },
    ReloadSoundConfig,
    MouseCapture { enabled: bool, sgr_pixels: bool },
    KittyKeyboardReportAll { enabled: bool },
    PrefixInputSource { active: bool },
    TerminalBell { count: u16 },
    GraphicsFile {
        path: String,
        expected_len: u64,
        image_id: u32,
        transfer_id: u64,
        leading: Vec<u8>,
        control: String,
    },
    GraphicsTransmissionRetired { transfer_id: u64, image_id: u32 },
}

// ---------------------------------------------------------------------------
// Framing: [u32 LE length][bincode 2 payload]
// ---------------------------------------------------------------------------

/// Serializes a message and writes it as `[u32LE length][payload]`.
pub fn write_frame<W: Write, M: Serialize>(writer: &mut W, msg: &M) -> Result<(), String> {
    let payload = bincode::serde::encode_to_vec(msg, bincode::config::standard())
        .map_err(|e| format!("encode_error: {}", e))?;
    if payload.len() > u32::MAX as usize {
        return Err("encode_error: payload exceeds u32::MAX".to_owned());
    }
    writer
        .write_all(&(payload.len() as u32).to_le_bytes())
        .map_err(io_err)?;
    writer.write_all(&payload).map_err(io_err)?;
    writer.flush().map_err(io_err)?;
    Ok(())
}

/// Reads a length-prefixed frame and decodes it, enforcing that the decoder
/// consumed the full payload (rejects trailing/truncated garbage).
pub fn read_frame<R: Read, M: for<'de> Deserialize<'de>>(
    reader: &mut R,
    max_frame_size: usize,
) -> Result<M, String> {
    let mut len_buf = [0u8; 4];
    read_exact(reader, &mut len_buf)?;
    let claimed_len = u32::from_le_bytes(len_buf) as usize;

    if claimed_len > max_frame_size {
        return Err(format!(
            "oversized_frame: declared {} bytes, max {}",
            claimed_len, max_frame_size
        ));
    }

    let mut payload = vec![0u8; claimed_len];
    read_exact(reader, &mut payload)?;

    let (msg, consumed) =
        bincode::serde::decode_from_slice(&payload, bincode::config::standard())
            .map_err(|e| format!("decode_error: {}", e))?;

    if consumed != claimed_len {
        return Err(format!(
            "trailing_bytes: decoded {} of declared {}",
            consumed, claimed_len
        ));
    }
    Ok(msg)
}

fn read_exact<R: Read>(reader: &mut R, buf: &mut [u8]) -> Result<(), String> {
    reader.read_exact(buf).map_err(io_err)
}

fn io_err(e: io::Error) -> String {
    if e.kind() == io::ErrorKind::UnexpectedEof {
        "unexpected_eof".to_owned()
    } else if e.kind() == io::ErrorKind::TimedOut || e.kind() == io::ErrorKind::WouldBlock {
        "timeout".to_owned()
    } else if e.kind() == io::ErrorKind::ConnectionReset {
        "connection_reset".to_owned()
    } else {
        "io_error".to_owned()
    }
}
