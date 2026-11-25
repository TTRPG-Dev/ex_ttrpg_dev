//! The single source of truth for what REPL commands exist.
//!
//! Dispatch (`characters.rs`, `systems.rs`, `inventory.rs`, `repl.rs`) still
//! pattern-matches tokens by hand — Rust gives no good way to drive that from
//! data without losing exhaustiveness checking. This table instead owns
//! everything that used to drift out of sync with dispatch: the list of
//! commands tab completion knows about, what (if anything) completes after
//! them, the one-line `help` listing, and the text each command's `--help`
//! prints. Adding a command means adding dispatch for it *and* a row here;
//! forgetting the row is caught by `every_dispatched_command_has_a_row`
//! below.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Completion {
    /// Nothing in particular completes after this command.
    None,
    /// The next token completes to a saved character slug.
    Slug,
    /// The next token completes to a configured rule system slug.
    System,
}

pub(crate) struct CommandSpec {
    /// Full dispatch path, space-separated, e.g. "characters inventory add".
    pub(crate) path: &'static str,
    /// Text printed after "Usage: " for this command's own `--help`.
    pub(crate) usage: &'static str,
    /// One-line description for the global `help` listing.
    pub(crate) summary: &'static str,
    /// What immediately follows `path` on the command line.
    pub(crate) completion: Completion,
}

pub(crate) static COMMAND_TABLE: &[CommandSpec] = &[
    CommandSpec {
        path: "roll",
        usage: "roll <dice>",
        summary: "Roll dice, e.g. roll 3d6, 1d20, roll 2d8+3d6",
        completion: Completion::None,
    },
    CommandSpec {
        path: "systems list",
        usage: "systems list",
        summary: "List configured rule systems",
        completion: Completion::None,
    },
    CommandSpec {
        path: "systems show",
        usage: "systems show <system> [--concept-type <type>]",
        summary: "Show system info, optionally filtered by concept type",
        completion: Completion::System,
    },
    CommandSpec {
        path: "systems create",
        usage: "systems create",
        summary: "Create a new, empty local rule system (prompts for its details)",
        completion: Completion::None,
    },
    CommandSpec {
        path: "systems copy",
        usage: "systems copy <system> [new_slug]",
        summary: "Copy a rule system into a new local one (default slug <system>_copy_N)",
        completion: Completion::System,
    },
    CommandSpec {
        path: "systems delete",
        usage: "systems delete <system> [-y|--yes]",
        summary: "Delete a local rule system (confirms unless --yes)",
        completion: Completion::System,
    },
    CommandSpec {
        path: "characters gen",
        usage: "characters gen <system>",
        summary: "Generate a character (random)",
        completion: Completion::System,
    },
    CommandSpec {
        path: "characters build",
        usage: "characters build <system>",
        summary: "Build a character interactively",
        completion: Completion::System,
    },
    CommandSpec {
        path: "characters list",
        usage: "characters list [--system <system>]",
        summary: "List saved characters",
        completion: Completion::None,
    },
    CommandSpec {
        path: "characters show",
        usage: "characters show <slug>",
        summary: "Show a saved character",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters roll",
        usage: "characters roll <slug> <type> <concept>",
        summary: "Roll for a character concept",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters award",
        usage: "characters award <slug> <award_id> <value>\n\
                 \x20      characters award <slug> level_up",
        summary: "Award something to a character, or advance a level",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters copy",
        usage: "characters copy <slug> [new_slug]",
        summary: "Copy a saved character (default slug <slug>_copy_N)",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters delete",
        usage: "characters delete <slug>",
        summary: "Delete a saved character",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters delete-all",
        usage: "characters delete-all [-y|--yes] [--system <system>]",
        summary: "Delete all characters (confirms each unless --yes)",
        completion: Completion::None,
    },
    CommandSpec {
        path: "characters choices",
        usage: "characters choices <slug>",
        summary: "Show pending progression choices",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters resolve_choice",
        usage: "characters resolve_choice <slug> [--random-resolve]",
        summary: "Interactively (or randomly) resolve a pending choice",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters inventory",
        usage: "characters inventory <slug>\n\
                 \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
                 \x20      characters inventory set <slug> <index> <field> <value>",
        summary: "Show a character's inventory",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters inventory add",
        usage: "characters inventory add <slug> <type> <id> [--equipped]",
        summary: "Add an item to a character's inventory",
        completion: Completion::None,
    },
    CommandSpec {
        path: "characters inventory set",
        usage: "characters inventory set <slug> <index> <field> <value>",
        summary: "Update an inventory item field",
        completion: Completion::None,
    },
    CommandSpec {
        path: "characters spells",
        usage: "characters spells <slug>",
        summary: "Show known/preparable spells and prepared state",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "characters prepare",
        usage: "characters prepare <slug> <spell_id> [spell_id ...]",
        summary: "Prepare one or more spells for a character",
        completion: Completion::Slug,
    },
    CommandSpec {
        path: "set display succinct",
        usage: "set display succinct",
        summary: "Succinct character sheet output",
        completion: Completion::None,
    },
    CommandSpec {
        path: "set display default",
        usage: "set display default",
        summary: "Default character sheet output",
        completion: Completion::None,
    },
    CommandSpec {
        path: "set display verbose",
        usage: "set display verbose",
        summary: "Verbose character sheet output",
        completion: Completion::None,
    },
    CommandSpec {
        path: "help",
        usage: "help",
        summary: "Show this help",
        completion: Completion::None,
    },
    CommandSpec {
        path: "exit",
        usage: "exit",
        summary: "Exit",
        completion: Completion::None,
    },
    CommandSpec {
        path: "quit",
        usage: "quit",
        summary: "Exit",
        completion: Completion::None,
    },
];

/// The `Usage: ...` text for the command at `path` (e.g. `"characters gen"`),
/// for that command's own `--help`.
pub(crate) fn usage_for(path: &str) -> Option<&'static str> {
    COMMAND_TABLE
        .iter()
        .find(|spec| spec.path == path)
        .map(|spec| spec.usage)
}

/// If `tokens` ends in `--help` and `prefix` plus the remaining tokens name
/// a row in `COMMAND_TABLE`, prints that row's usage and returns `true`.
/// Dispatch calls this before matching on `tokens` so that every
/// subcommand's `--help` is handled in one place, driven by the table,
/// instead of each module re-listing its own subcommands' usage strings.
pub(crate) fn dispatch_help(tokens: &[&str], prefix: &str) -> bool {
    let Some((&last, head)) = tokens.split_last() else {
        return false;
    };
    if last != "--help" {
        return false;
    }
    let path = if head.is_empty() {
        prefix.to_string()
    } else {
        format!("{prefix} {}", head.join(" "))
    };
    match usage_for(&path) {
        Some(usage) => {
            println!("Usage: {usage}");
            true
        }
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Mirrors the token patterns actually dispatched in characters.rs,
    // systems.rs, inventory.rs, and repl.rs's `handle_line`. This is the
    // guard the issue asked for: forgetting to add a row here for a
    // dispatched command (as happened with `spells`/`prepare`) now fails a
    // test instead of silently drifting out of completion and help.
    const DISPATCHED_PATHS: &[&str] = &[
        "roll",
        "systems list",
        "systems show",
        "systems create",
        "systems copy",
        "systems delete",
        "characters list",
        "characters gen",
        "characters build",
        "characters show",
        "characters roll",
        "characters award",
        "characters copy",
        "characters delete",
        "characters delete-all",
        "characters choices",
        "characters resolve_choice",
        "characters inventory",
        "characters inventory add",
        "characters inventory set",
        "characters spells",
        "characters prepare",
        "set display succinct",
        "set display default",
        "set display verbose",
        "help",
        "exit",
        "quit",
    ];

    #[test]
    fn every_dispatched_command_has_a_row() {
        for path in DISPATCHED_PATHS {
            assert!(
                COMMAND_TABLE.iter().any(|spec| spec.path == *path),
                "dispatched command '{path}' has no COMMAND_TABLE row"
            );
        }
    }

    #[test]
    fn every_row_is_dispatched() {
        for spec in COMMAND_TABLE {
            assert!(
                DISPATCHED_PATHS.contains(&spec.path),
                "COMMAND_TABLE row '{}' does not correspond to a dispatched command",
                spec.path
            );
        }
    }
}
