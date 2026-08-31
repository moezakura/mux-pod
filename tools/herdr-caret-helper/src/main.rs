//! herdr-caret-helper: one-shot read-only Herdr caret snapshot reader.
//!
//! Connects to a herdr client socket, performs the semantic-frame terminal
//! attach handshake, sends ObserveTerminal, and prints the first FrameData
//! cursor as a single JSON line. Exits 0 on success.
//!
//! Usage:
//!   herdr-caret-helper --socket <path> --pane <id> --protocol <17|20>
//!                      [--cols <n>] [--rows <n>] [--timeout-ms <n>]
//!
//! No socket path, raw payload, or pane content is ever written to stderr.

use std::process::ExitCode;

use herdr_caret_helper::runner::{run, CaretOutput, Params, RunError};

fn parse_required(args: &[String], name: &str) -> Result<String, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            return iter.next().cloned().ok_or_else(|| {
                format!("argument {} requires a value", name)
            });
        }
    }
    Err(format!("missing required argument {}", name))
}

fn parse_optional_u16(args: &[String], name: &str, default: u16) -> Result<u16, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            let v = iter.next().ok_or_else(|| format!("argument {} requires a value", name))?;
            return v
                .parse::<u16>()
                .map_err(|_| format!("invalid value for {}", name));
        }
    }
    Ok(default)
}

fn parse_optional_u64(args: &[String], name: &str, default: u64) -> Result<u64, String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == name {
            let v = iter.next().ok_or_else(|| format!("argument {} requires a value", name))?;
            return v
                .parse::<u64>()
                .map_err(|_| format!("invalid value for {}", name));
        }
    }
    Ok(default)
}

fn parse_args() -> Result<Params, String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.contains(&"--help".to_owned()) || args.contains(&"-h".to_owned()) {
        return Err("usage: herdr-caret-helper --socket <path> --pane <id> --protocol <17|20> [--cols <n>] [--rows <n>] [--timeout-ms <n>]".to_owned());
    }
    let socket = parse_required(&args, "--socket")?;
    let pane = parse_required(&args, "--pane")?;
    let protocol = parse_required(&args, "--protocol")?.parse::<u8>().map_err(|_| "invalid --protocol".to_owned())?;
    let cols = parse_optional_u16(&args, "--cols", 80)?;
    let rows = parse_optional_u16(&args, "--rows", 24)?;
    let timeout_ms = parse_optional_u64(&args, "--timeout-ms", 1000)?;

    if protocol != 17 && protocol != 20 {
        return Err(format!("unsupported protocol {}; expected 17 or 20", protocol));
    }

    Ok(Params {
        socket,
        pane,
        protocol,
        cols,
        rows,
        timeout_ms,
    })
}

fn main() -> ExitCode {
    let params = match parse_args() {
        Ok(p) => p,
        Err(msg) => {
            let hint = "usage: herdr-caret-helper --socket <path> --pane <id> --protocol <17|20> [--cols <n>] [--rows <n>] [--timeout-ms <n>]";
            eprintln!("{} {}", RunError::Usage(msg.clone()).json(), hint);
            return ExitCode::FAILURE;
        }
    };

    match run(&params) {
        Ok(out) => {
            println!("{}", to_json(&out));
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("{}", e.json());
            ExitCode::FAILURE
        }
    }
}

fn to_json(out: &CaretOutput) -> String {
    serde_json::to_string(out).unwrap_or_else(|_| r#"{"error":"internal"}"#.to_owned())
}
