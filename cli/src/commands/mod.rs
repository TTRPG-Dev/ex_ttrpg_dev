//! Command handlers — one function per CLI command or subcommand group.
//!
//! Each submodule owns one domain of commands. Shared types (DisplayMode,
//! argument bundles) live here and are imported by the submodules.

mod characters;
mod help;
mod inventory;
mod roll;
mod systems;
mod table;

use serde::de::DeserializeOwned;

use crate::engine::Engine;
use crate::protocol::Request;

pub(crate) use characters::handle_characters;
pub(crate) use help::print_help;
pub(crate) use roll::handle_roll;
pub(crate) use systems::handle_systems;
pub(crate) use table::{COMMAND_TABLE, Completion};

/// Send `req` to the engine and return its parsed response, or print a
/// uniform `Error: {e}` to stderr and return `None` on failure. Collapses
/// the call-and-report-error shape that used to be repeated by hand in
/// every command handler.
pub(crate) fn call_or_report<T: DeserializeOwned>(
    engine: &mut Engine,
    req: &Request<'_>,
) -> Option<T> {
    match engine.call(req) {
        Ok(v) => Some(v),
        Err(e) => {
            eprintln!("Error: {e}");
            None
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) enum DisplayMode {
    Succinct,
    Default,
    Verbose,
}

impl DisplayMode {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            DisplayMode::Succinct => "succinct",
            DisplayMode::Default => "default",
            DisplayMode::Verbose => "verbose",
        }
    }
}

pub(crate) struct ConceptRollArgs<'a> {
    pub(crate) concept_type: &'a str,
    pub(crate) concept_id: &'a str,
}

pub(crate) struct CharacterAwardArgs<'a> {
    pub(crate) award_id: &'a str,
    pub(crate) value_str: &'a str,
}
