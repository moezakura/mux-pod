//! Codec tests for protocol 17 and 20: exact Hello/ObserveTerminal encodings,
//! Welcome/FrameData decodings, unknown-variant rejection, oversized/truncated
//! rejection.

use herdr_caret_helper::wire::*;

fn encode<M: serde::Serialize>(msg: &M) -> Vec<u8> {
    bincode::serde::encode_to_vec(msg, bincode::config::standard()).unwrap()
}

// ---------------------------------------------------------------------------
// Hello exact byte encodings
// ---------------------------------------------------------------------------

#[test]
fn hello_17_terminal_attach_exact_bytes() {
    let hello = ClientMessage17::Hello {
        version: 17,
        cols: 80,
        rows: 24,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode17::TerminalAttach,
    };
    // tag 0 (Hello), version 0x11=17, cols 0x50=80, rows 0x18=24,
    // cell_w 0, cell_h 0, encoding 0, keybindings 0, launch_mode TerminalAttach=1
    assert_eq!(encode(&hello), vec![0x00, 0x11, 0x50, 0x18, 0x00, 0x00, 0x00, 0x00, 0x01]);
}

#[test]
fn hello_20_terminal_attach_exact_bytes() {
    let hello = ClientMessage20::Hello {
        version: 20,
        cols: 80,
        rows: 24,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode20::TerminalAttach,
    };
    // launch_mode TerminalAttach=2 in protocol 20 (App=0, AppDirectGraphics=1)
    assert_eq!(encode(&hello), vec![0x00, 0x14, 0x50, 0x18, 0x00, 0x00, 0x00, 0x00, 0x02]);
}

#[test]
fn observe_terminal_exact_bytes_both_protocols() {
    let obs17 = ClientMessage17::ObserveTerminal {
        target: "w2:p1".to_owned(),
    };
    // tag 8 (ObserveTerminal), string len 5, "w2:p1"
    assert_eq!(encode(&obs17), vec![0x08, 0x05, 0x77, 0x32, 0x3a, 0x70, 0x31]);

    let obs20 = ClientMessage20::ObserveTerminal {
        target: "w2:p1".to_owned(),
    };
    assert_eq!(encode(&obs20), vec![0x08, 0x05, 0x77, 0x32, 0x3a, 0x70, 0x31]);
}

// ---------------------------------------------------------------------------
// Welcome / FrameData decoding
// ---------------------------------------------------------------------------

#[test]
fn welcome_17_decode() {
    let bytes = vec![0x00, 0x11, 0x00, 0x00]; // Welcome, version 17, SemanticFrame, error=None
    let decoded: ServerMessage17 = encode_and_decode(&bytes);
    assert_eq!(
        decoded,
        ServerMessage17::Welcome {
            version: 17,
            encoding: RenderEncoding::SemanticFrame,
            error: None,
        }
    );
}

#[test]
fn welcome_20_decode() {
    let bytes = vec![0x00, 0x14, 0x00, 0x00]; // Welcome, version 20, SemanticFrame, error=None
    let decoded: ServerMessage20 = encode_and_decode(&bytes);
    assert_eq!(
        decoded,
        ServerMessage20::Welcome {
            version: 20,
            encoding: RenderEncoding::SemanticFrame,
            error: None,
        }
    );
}

fn encode_and_decode<M: for<'de> serde::Deserialize<'de>>(bytes: &[u8]) -> M {
    let (decoded, _) = bincode::serde::decode_from_slice(bytes, bincode::config::standard()).unwrap();
    decoded
}

#[test]
fn frame_data_with_cursor_roundtrips_17() {
    let frame = ServerMessage17::Frame(FrameData {
        cells: vec![CellData {
            symbol: "A".to_owned(),
            fg: 0x02000000,
            bg: 0,
            modifier: 0,
            skip: false,
            hyperlink: None,
        }],
        width: 1,
        height: 1,
        cursor: Some(CursorState {
            x: 0,
            y: 0,
            visible: true,
            shape: 2,
        }),
        hyperlinks: vec![],
        graphics: vec![],
    });
    let bytes = encode(&frame);
    println!("frame17 bytes: {:02x?}", bytes);
    let decoded: ServerMessage17 = encode_and_decode(&bytes);
    assert_eq!(decoded, frame);
}

#[test]
fn frame_data_with_cursor_roundtrips_20() {
    let frame = ServerMessage20::Frame(FrameData {
        cells: vec![],
        width: 4,
        height: 2,
        cursor: Some(CursorState {
            x: 3,
            y: 1,
            visible: true,
            shape: 5,
        }),
        hyperlinks: vec![],
        graphics: vec![],
    });
    let bytes = encode(&frame);
    let decoded: ServerMessage20 = encode_and_decode(&bytes);
    assert_eq!(decoded, frame);
}

#[test]
fn framewrapper_exact_bytes() {
    // Frame(FrameData) with one empty-ish frame and a visible shape-2 cursor,
    // matching the known hand-derived fixture.
    let msg = ServerMessage17::Frame(FrameData {
        cells: vec![CellData {
            symbol: "A".to_owned(),
            fg: 0x02000000,
            bg: 0,
            modifier: 0,
            skip: false,
            hyperlink: None,
        }],
        width: 1,
        height: 1,
        cursor: Some(CursorState {
            x: 0,
            y: 0,
            visible: true,
            shape: 2,
        }),
        hyperlinks: vec![],
        graphics: vec![],
    });
    assert_eq!(
        encode(&msg),
        vec![
            0x01, 0x01, 0x01, 0x41, 0xfc, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x01, 0x01, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00,
        ]
    );
}

// ---------------------------------------------------------------------------
// Unknown-variant / malformed rejection
// ---------------------------------------------------------------------------

#[test]
fn unknown_server_variant_rejected() {
    // ServerMessage tag 99 is out of range for both protocols.
    let bytes = vec![99u8];
    let r17: Result<(ServerMessage17, usize), _> =
        bincode::serde::decode_from_slice(&bytes, bincode::config::standard());
    assert!(r17.is_err());
    let r20: Result<(ServerMessage20, usize), _> =
        bincode::serde::decode_from_slice(&bytes, bincode::config::standard());
    assert!(r20.is_err());
}

#[test]
fn unknown_client_variant_rejected() {
    let bytes = vec![99u8];
    let r17: Result<(ClientMessage17, usize), _> =
        bincode::serde::decode_from_slice(&bytes, bincode::config::standard());
    assert!(r17.is_err());
    let r20: Result<(ClientMessage20, usize), _> =
        bincode::serde::decode_from_slice(&bytes, bincode::config::standard());
    assert!(r20.is_err());
}

#[test]
fn trailing_bytes_rejected_by_read_frame() {
    // Declare a frame one byte longer than the real message: the decoder
    // consumes only the message bytes, so consumed != declared length and the
    // frame must be rejected (trailing bytes are a protocol violation).
    let hello = ClientMessage17::Hello {
        version: 17,
        cols: 80,
        rows: 24,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode17::TerminalAttach,
    };
    let payload = encode(&hello);
    let mut framed = vec![];
    framed.extend_from_slice(&((payload.len() as u32 + 1).to_le_bytes()));
    framed.extend_from_slice(&payload);
    framed.push(0xAA);

    let mut reader = std::io::Cursor::new(&framed);
    let r: Result<ClientMessage17, _> = read_frame(&mut reader, MAX_FRAME_SIZE);
    assert!(r.is_err());
    assert!(r.unwrap_err().starts_with("trailing_bytes"));
}

#[test]
fn oversized_frame_rejected() {
    let mut framed = vec![];
    // Declare 17MB > 16MB max.
    framed.extend_from_slice(&((17 * 1024 * 1024) as u32).to_le_bytes());
    framed.extend_from_slice(&vec![0u8; 17 * 1024 * 1024]);
    let mut reader = std::io::Cursor::new(&framed);
    let r: Result<ClientMessage17, _> = read_frame(&mut reader, MAX_FRAME_SIZE);
    assert!(r.is_err());
    assert!(r.unwrap_err().starts_with("oversized_frame"));
}

#[test]
fn truncated_frame_rejected() {
    let mut framed = vec![];
    let payload = encode(&ClientMessage17::ObserveTerminal {
        target: "w1:p1".to_owned(),
    });
    framed.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    // only header + partial payload
    framed.extend_from_slice(&payload[..2]);
    let mut reader = std::io::Cursor::new(&framed);
    let r: Result<ClientMessage17, _> = read_frame(&mut reader, MAX_FRAME_SIZE);
    assert!(r.is_err());
}

#[test]
fn framing_composes_and_reads_back() {
    let hello = ClientMessage17::Hello {
        version: 17,
        cols: 80,
        rows: 24,
        cell_width_px: 0,
        cell_height_px: 0,
        requested_encoding: RenderEncoding::SemanticFrame,
        keybindings: ClientKeybindings::Server,
        launch_mode: ClientLaunchMode17::TerminalAttach,
    };
    let obs = ClientMessage17::ObserveTerminal {
        target: "w7:p3".to_owned(),
    };
    let mut buf = Vec::new();
    write_frame(&mut buf, &hello).unwrap();
    write_frame(&mut buf, &obs).unwrap();

    let mut reader = std::io::Cursor::new(&buf);
    let h: ClientMessage17 = read_frame(&mut reader, MAX_FRAME_SIZE).unwrap();
    let o: ClientMessage17 = read_frame(&mut reader, MAX_FRAME_SIZE).unwrap();
    assert_eq!(h, hello);
    assert_eq!(o, obs);
}
