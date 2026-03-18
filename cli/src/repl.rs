//! Interactive REPL — prompt, tab completion, and command dispatch.
//!
//! Drives the Elixir engine subprocess. Command implementations live in
//! `commands`; protocol types in `protocol`; display in `display`.

use std::borrow::Cow;

use reedline::{
    ColumnarMenu, Completer, DefaultHinter, DefaultValidator, Emacs, KeyCode, KeyModifiers,
    MenuBuilder, Prompt, PromptEditMode, PromptHistorySearch, PromptHistorySearchStatus, Reedline,
    ReedlineEvent, ReedlineMenu, Signal, Suggestion, default_emacs_keybindings,
};

use crate::commands;
use crate::engine::Engine;

// ── Prompt ────────────────────────────────────────────────────────────────────

struct TtrpgPrompt;

impl Prompt for TtrpgPrompt {
    fn render_prompt_left(&self) -> Cow<'_, str> {
        Cow::Borrowed("ttrpg-dev")
    }
    fn render_prompt_right(&self) -> Cow<'_, str> {
        Cow::Borrowed("")
    }
    fn render_prompt_indicator(&self, _mode: PromptEditMode) -> Cow<'_, str> {
        Cow::Borrowed("> ")
    }
    fn render_prompt_multiline_indicator(&self) -> Cow<'_, str> {
        Cow::Borrowed("::: ")
    }
    fn render_prompt_history_search_indicator(
        &self,
        history_search: PromptHistorySearch,
    ) -> Cow<'_, str> {
        let indicator = match history_search.status {
            PromptHistorySearchStatus::Passing => "",
            PromptHistorySearchStatus::Failing => " (not found)",
        };
        Cow::Owned(format!("(search: {}{}): ", history_search.term, indicator))
    }
}

// ── Tab completion ─────────────────────────────────────────────────────────────

static COMMANDS: &[&str] = &[
    "roll",
    "systems list",
    "systems show",
    "characters gen",
    "characters list",
    "characters show",
    "characters roll",
    "characters award",
    "characters choices",
    "characters resolve_choice",
    "characters inventory",
    "characters inventory add",
    "characters inventory set",
    "help",
    "exit",
    "quit",
];

struct CommandCompleter;

impl Completer for CommandCompleter {
    fn complete(&mut self, line: &str, pos: usize) -> Vec<Suggestion> {
        let prefix = &line[..pos];
        let word_start = prefix.rfind(' ').map(|i| i + 1).unwrap_or(0);

        let mut seen = std::collections::HashSet::new();
        COMMANDS
            .iter()
            .filter(|cmd| cmd.starts_with(prefix))
            .filter_map(|cmd| {
                let token = cmd[word_start..].split_whitespace().next()?;
                if seen.insert(token) {
                    Some(Suggestion {
                        value: token.to_string(),
                        description: None,
                        style: None,
                        extra: None,
                        span: reedline::Span {
                            start: word_start,
                            end: pos,
                        },
                        append_whitespace: true,
                    })
                } else {
                    None
                }
            })
            .collect()
    }
}

// ── Command dispatch ───────────────────────────────────────────────────────────

fn handle_line(line: &str, engine: &mut Engine) -> bool {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    if tokens.is_empty() {
        return true;
    }
    match tokens.as_slice() {
        ["exit" | "quit" | "exit()"] => return false,
        ["help"] => commands::print_help(),
        ["roll"] | ["roll", "--help"] => {
            println!("Usage: roll <dice>  e.g. roll 3d6, roll 1d20, roll 2d8+3d6")
        }
        ["roll", rest @ ..] => commands::handle_roll(&rest.join(" "), engine),
        ["systems" | "system", rest @ ..] => commands::handle_systems(rest, engine),
        ["characters" | "character", rest @ ..] => commands::handle_characters(rest, engine),
        _ => eprintln!("Unknown command. Type `help` for available commands."),
    }
    true
}

// ── Entry point ────────────────────────────────────────────────────────────────

pub fn run() {
    let mut engine = match Engine::spawn() {
        Ok(e) => e,
        Err(e) => {
            eprintln!("Failed to start engine: {e}");
            eprintln!("Make sure `ttrpg-dev-engine` is in your PATH or next to this binary.");
            std::process::exit(1);
        }
    };

    let history: Box<dyn reedline::History> = Box::new(
        crate::history::DeduplicatingHistory::with_file(1000, history_path()),
    );

    let completion_menu = Box::new(ColumnarMenu::default().with_name("completion_menu"));

    let mut keybindings = default_emacs_keybindings();
    keybindings.add_binding(
        KeyModifiers::NONE,
        KeyCode::Tab,
        ReedlineEvent::UntilFound(vec![
            ReedlineEvent::Menu("completion_menu".to_string()),
            ReedlineEvent::MenuNext,
        ]),
    );

    let mut line_editor = Reedline::create()
        .with_history(history)
        .with_completer(Box::new(CommandCompleter))
        .with_menu(ReedlineMenu::EngineCompleter(completion_menu))
        .with_hinter(Box::new(DefaultHinter::default()))
        .with_validator(Box::new(DefaultValidator))
        .with_edit_mode(Box::new(Emacs::new(keybindings)));

    let prompt = TtrpgPrompt;

    println!("TTRPG Dev — interactive shell");
    println!("Type `help` for available commands, `exit` to quit.\n");

    loop {
        match line_editor.read_line(&prompt) {
            Ok(Signal::Success(line)) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if !handle_line(trimmed, &mut engine) {
                    println!("Goodbye!");
                    break;
                }
            }
            Ok(Signal::CtrlD) | Ok(Signal::CtrlC) => {
                println!("\nGoodbye!");
                break;
            }
            Err(e) => {
                eprintln!("Input error: {e}");
                break;
            }
        }
    }
}

fn history_path() -> std::path::PathBuf {
    let base = std::env::var("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("."));
    base.join(".ttrpg_dev_history")
}
