//! Subprocess wrapper for the Elixir engine.
//!
//! Spawns `ttrpg-dev-engine --server` (located next to this binary) and drives
//! it with newline-delimited JSON over stdin/stdout.

use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

pub struct Engine {
    _child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

#[derive(Debug)]
pub enum EngineError {
    Io(std::io::Error),
    Json(serde_json::Error),
    ErrorResponse(String),
    UnexpectedEof,
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::Io(e) => write!(f, "engine I/O error: {e}"),
            EngineError::Json(e) => write!(f, "JSON error: {e}"),
            EngineError::ErrorResponse(msg) => write!(f, "{msg}"),
            EngineError::UnexpectedEof => write!(f, "engine process closed unexpectedly"),
        }
    }
}

impl From<std::io::Error> for EngineError {
    fn from(e: std::io::Error) -> Self {
        EngineError::Io(e)
    }
}

impl From<serde_json::Error> for EngineError {
    fn from(e: serde_json::Error) -> Self {
        EngineError::Json(e)
    }
}

impl Engine {
    /// Spawn the engine process. Looks for `ttrpg-dev-engine` next to the
    /// current executable, falling back to PATH for development convenience.
    pub fn spawn() -> Result<Self, EngineError> {
        let engine_path = engine_binary_path();

        let mut child = Command::new(&engine_path)
            .arg("--server")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| {
                EngineError::Io(std::io::Error::other(format!(
                    "failed to launch engine at {}: {}",
                    engine_path.display(),
                    e
                )))
            })?;

        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());

        Ok(Engine {
            _child: child,
            stdin,
            stdout,
        })
    }

    /// Send a command and return the parsed `data` field on success, or an
    /// `EngineError::ErrorResponse` if the engine returns `status: "error"`.
    pub fn call<Req: Serialize, Res: DeserializeOwned>(
        &mut self,
        request: &Req,
    ) -> Result<Res, EngineError> {
        let line = serde_json::to_string(request)?;
        writeln!(self.stdin, "{line}")?;
        self.stdin.flush()?;

        let mut response_line = String::new();
        let bytes = self.stdout.read_line(&mut response_line)?;
        if bytes == 0 {
            return Err(EngineError::UnexpectedEof);
        }

        let response: Value = serde_json::from_str(response_line.trim())?;

        match response["status"].as_str() {
            Some("ok") => {
                let data = serde_json::from_value(response["data"].clone())?;
                Ok(data)
            }
            Some("error") => {
                let msg = response["message"]
                    .as_str()
                    .unwrap_or("unknown error")
                    .to_string();
                Err(EngineError::ErrorResponse(msg))
            }
            _ => Err(EngineError::ErrorResponse(
                "malformed engine response".into(),
            )),
        }
    }
}

fn engine_binary_path() -> PathBuf {
    // In a release build, look next to the current executable.
    if let Ok(mut path) = env::current_exe() {
        path.pop();
        let candidate = path.join("ttrpg-dev-engine");
        if candidate.exists() {
            return candidate;
        }
    }
    // Fall back to PATH (useful during development with `mix escript`).
    PathBuf::from("ttrpg-dev-engine")
}
