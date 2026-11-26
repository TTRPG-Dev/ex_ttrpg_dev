//! Interactive REPL — prompt, tab completion, and command dispatch.
//!
//! Drives the Elixir engine subprocess. Command implementations live in
//! `commands`; protocol types in `protocol`; display in `display`.

use std::borrow::Cow;
use std::sync::{Arc, Mutex};

use reedline::{
    ColumnarMenu, Completer, CompletionResult, DefaultHinter, DefaultValidator, Emacs, KeyCode,
    KeyModifiers, MenuBuilder, Prompt, PromptEditMode, PromptHistorySearch,
    PromptHistorySearchStatus, Reedline, ReedlineEvent, ReedlineMenu, Signal, Suggestion,
    default_emacs_keybindings,
};

use crate::commands::{self, COMMAND_TABLE, CmdResult, Completion, DisplayMode, fail};
use crate::engine::Engine;
use crate::protocol::{CharactersList, Request, SystemsList};

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
//
// The command list and what (if anything) completes after each one come
// from `commands::COMMAND_TABLE` — the single source of truth also used for
// dispatch and `help` (see `commands::table`).

/// Finds the `COMMAND_TABLE` row whose path is the longest exact-token
/// prefix of `tokens`, and returns what completes next — unless a
/// positional (non-flag) argument has already been typed past that row's
/// path, in which case nothing from the table applies anymore.
///
/// Matching by token position (rather than comparing the typed prefix
/// against the row's path as a string) means a flag between the path and
/// the cursor — e.g. `characters show --verbose <TAB>` — doesn't defeat
/// completion the way an exact-prefix match would.
fn resolve_completion_kind(tokens: &[&str]) -> Option<Completion> {
    let mut best: Option<(&'static str, Completion)> = None;
    for spec in COMMAND_TABLE {
        let words: Vec<&str> = spec.path.split(' ').collect();
        let len = words.len();
        if len <= tokens.len() && tokens[..len] == words[..] {
            let best_len = best.map(|(path, _)| path.split(' ').count()).unwrap_or(0);
            if len > best_len {
                best = Some((spec.path, spec.completion));
            }
        }
    }
    let (path, completion) = best?;
    let path_len = path.split(' ').count();
    let positional_typed = tokens[path_len..].iter().any(|t| !t.starts_with('-'));
    if positional_typed {
        None
    } else {
        Some(completion)
    }
}

struct CommandCompleter {
    engine: Option<Arc<Mutex<Engine>>>,
}

impl CommandCompleter {
    fn call_engine<T: for<'de> serde::Deserialize<'de>>(&self, req: &Request<'_>) -> Option<T> {
        let engine = self.engine.as_ref()?;
        // A poisoned lock degrades completion to no-suggestions rather than
        // panicking inside reedline's event loop.
        engine.lock().ok()?.call::<_, T>(req).ok()
    }

    fn fetch_character_slugs(&self) -> Vec<String> {
        self.call_engine(&Request::CharactersList { system: None })
            .map(|r: CharactersList| r.characters.into_iter().map(|c| c.slug).collect())
            .unwrap_or_default()
    }

    fn fetch_system_slugs(&self) -> Vec<String> {
        self.call_engine(&Request::SystemsList)
            .map(|r: SystemsList| r.systems)
            .unwrap_or_default()
    }
}

impl Completer for CommandCompleter {
    fn complete(&mut self, line: &str, pos: usize) -> CompletionResult {
        let prefix = &line[..pos];
        let word_start = prefix.rfind(' ').map(|i| i + 1).unwrap_or(0);
        let current_word = &prefix[word_start..];
        let typed_tokens: Vec<&str> = prefix[..word_start].split_whitespace().collect();

        let completions: Option<Vec<String>> = match resolve_completion_kind(&typed_tokens) {
            Some(Completion::Slug) => Some(self.fetch_character_slugs()),
            Some(Completion::System) => Some(self.fetch_system_slugs()),
            Some(Completion::None) => Some(Vec::new()),
            None => None,
        };

        if let Some(values) = completions {
            let suggestions: Vec<Suggestion> = values
                .into_iter()
                .filter(|s| s.starts_with(current_word))
                .map(|value| Suggestion {
                    value,
                    display_override: None,
                    description: None,
                    style: None,
                    extra: None,
                    span: reedline::Span {
                        start: word_start,
                        end: pos,
                    },
                    append_whitespace: true,
                    match_indices: None,
                })
                .collect();
            return CompletionResult::fresh(suggestions);
        }

        let mut seen = std::collections::HashSet::new();
        let suggestions: Vec<Suggestion> = COMMAND_TABLE
            .iter()
            .map(|spec| spec.path)
            .filter(|cmd| cmd.starts_with(prefix))
            .filter_map(|cmd| {
                let token = cmd[word_start..].split_whitespace().next()?;
                if seen.insert(token) {
                    Some(Suggestion {
                        value: token.to_string(),
                        display_override: None,
                        description: None,
                        style: None,
                        extra: None,
                        span: reedline::Span {
                            start: word_start,
                            end: pos,
                        },
                        append_whitespace: true,
                        match_indices: None,
                    })
                } else {
                    None
                }
            })
            .collect();
        CompletionResult::fresh(suggestions)
    }
}

// ── Command dispatch ───────────────────────────────────────────────────────────

fn handle_line(line: &str, engine: &mut Engine, display_mode: &mut DisplayMode) -> bool {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    if tokens.is_empty() {
        return true;
    }
    if let ["exit" | "quit" | "exit()"] = tokens.as_slice() {
        return false;
    }
    // The REPL reports a failure and carries on; the result only matters
    // to a caller that turns it into an exit status.
    let _ = dispatch(&tokens, engine, display_mode);
    true
}

/// Runs one command. Shared by the REPL and anything else that runs
/// commands, so a command behaves the same wherever it's typed.
pub(crate) fn dispatch(
    tokens: &[&str],
    engine: &mut Engine,
    display_mode: &mut DisplayMode,
) -> CmdResult {
    match tokens {
        ["help"] => {
            commands::print_help();
            Ok(())
        }
        ["set", "display", mode] => {
            *display_mode = match *mode {
                "succinct" => DisplayMode::Succinct,
                "default" => DisplayMode::Default,
                "verbose" => DisplayMode::Verbose,
                other => {
                    return Err(fail(format!(
                        "Unknown display mode '{other}'. Use: succinct, default, verbose"
                    )));
                }
            };
            Ok(())
        }
        ["set", ..] => Err(fail(
            "Unknown set command. Try: set display succinct|default|verbose",
        )),
        ["roll"] | ["roll", "--help"] => {
            println!("Usage: roll <dice>  e.g. roll 3d6, roll 1d20, roll 2d8+3d6");
            Ok(())
        }
        ["roll", rest @ ..] => commands::handle_roll(&rest.join(" "), engine),
        ["systems" | "system", rest @ ..] => commands::handle_systems(rest, engine),
        ["characters" | "character", rest @ ..] => {
            commands::handle_characters(rest, *display_mode, engine)
        }
        [unknown, ..] => Err(fail(format!("Unknown command '{unknown}'. Try `help`."))),
        [] => Ok(()),
    }
}

// ── Entry point ────────────────────────────────────────────────────────────────

/// Starts the engine, or reports why it couldn't and returns `None`.
pub(crate) fn start_engine() -> Option<Engine> {
    match Engine::spawn() {
        Ok(e) => Some(e),
        Err(e) => {
            eprintln!("Failed to start engine: {e}");
            eprintln!("Make sure `ttrpg-dev-engine` is in your PATH or next to this binary.");
            None
        }
    }
}

pub fn run() {
    let Some(engine) = start_engine() else {
        std::process::exit(1);
    };
    let engine = Arc::new(Mutex::new(engine));

    println!("TTRPG Dev — interactive shell");
    println!("Type `help` for available commands, `exit` to quit.\n");

    let mut display_mode = DisplayMode::Default;

    if std::env::var("TTRPG_NO_REEDLINE").is_ok() {
        run_pipe(engine, &mut display_mode);
        return;
    }

    run_reedline(engine, &mut display_mode);
}

/// Locks the engine, recovering from a poisoned mutex: the REPL is
/// single-threaded, so the engine state behind a poisoned lock is still
/// consistent and continuing beats crashing the session.
fn lock_engine(engine: &Arc<Mutex<Engine>>) -> std::sync::MutexGuard<'_, Engine> {
    engine
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn run_pipe(engine: Arc<Mutex<Engine>>, display_mode: &mut DisplayMode) {
    use std::io::BufRead;
    loop {
        let line = std::io::stdin().lock().lines().next();
        match line {
            None | Some(Err(_)) => break,
            Some(Ok(l)) => {
                let trimmed = l.trim().to_string();
                if trimmed.is_empty() {
                    continue;
                }
                if !handle_line(&trimmed, &mut lock_engine(&engine), display_mode) {
                    println!("Goodbye!");
                    break;
                }
            }
        }
    }
}

fn run_reedline(engine: Arc<Mutex<Engine>>, display_mode: &mut DisplayMode) {
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
        .with_completer(Box::new(CommandCompleter {
            engine: Some(Arc::clone(&engine)),
        }))
        .with_menu(ReedlineMenu::EngineCompleter(completion_menu))
        .with_hinter(Box::new(DefaultHinter::default()))
        .with_validator(Box::new(DefaultValidator))
        .with_edit_mode(Box::new(Emacs::new(keybindings)));

    let prompt = TtrpgPrompt;

    loop {
        match line_editor.read_line(&prompt) {
            Ok(Signal::Success(line)) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if !handle_line(trimmed, &mut lock_engine(&engine), display_mode) {
                    println!("Goodbye!");
                    break;
                }
            }
            Ok(Signal::CtrlD) | Ok(Signal::CtrlC(_)) => {
                println!("\nGoodbye!");
                break;
            }
            // `Signal` is `#[non_exhaustive]`; `HostCommand`/`ExternalBreak` are
            // only emitted by event bindings we don't register, so just loop.
            Ok(_) => continue,
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

#[cfg(test)]
mod tests {
    use super::*;
    use reedline::Completer;

    fn completion_values(result: CompletionResult) -> Vec<String> {
        result
            .suggestions()
            .iter()
            .map(|s| s.value.clone())
            .collect()
    }

    #[test]
    fn static_completions() {
        struct Case {
            input: &'static str,
            contains: &'static [&'static str],
            excludes: &'static [&'static str],
        }
        let cases = [
            Case {
                input: "",
                contains: &["roll", "characters", "systems", "help", "exit"],
                excludes: &[],
            },
            Case {
                input: "ch",
                contains: &["characters"],
                excludes: &["roll", "systems"],
            },
            Case {
                input: "characters ",
                contains: &[
                    "list",
                    "gen",
                    "show",
                    "roll",
                    "inventory",
                    "spells",
                    "prepare",
                ],
                excludes: &[],
            },
        ];
        let mut c = CommandCompleter { engine: None };
        for case in &cases {
            let pos = case.input.len();
            let values = completion_values(c.complete(case.input, pos));
            for token in case.contains {
                assert!(
                    values.contains(&token.to_string()),
                    "expected '{token}' in completions for '{}'",
                    case.input
                );
            }
            for token in case.excludes {
                assert!(
                    !values.contains(&token.to_string()),
                    "did not expect '{token}' in completions for '{}'",
                    case.input
                );
            }
        }
    }

    #[test]
    fn no_completions_for_unknown_prefix() {
        let mut c = CommandCompleter { engine: None };
        assert!(completion_values(c.complete("zzz", 3)).is_empty());
    }

    #[test]
    fn deduplicates_suggestions_for_shared_subcommand_prefix() {
        // "characters inventory", "characters inventory add", "characters inventory set"
        // all share the "inventory" token — it should appear only once
        let mut c = CommandCompleter { engine: None };
        let values = completion_values(c.complete("characters inv", 14));
        let inventory_count = values.iter().filter(|v| *v == "inventory").count();
        assert_eq!(inventory_count, 1);
    }

    #[test]
    fn slug_position_returns_no_static_completions() {
        // Without an engine, slug completion returns empty rather than
        // falling through to static command completions.
        let mut c = CommandCompleter { engine: None };
        let values = completion_values(c.complete("characters show ", 16));
        assert!(values.is_empty());
    }

    #[test]
    fn system_position_returns_no_static_completions() {
        // Without an engine, system slug completion returns empty rather than
        // falling through to static command completions.
        let mut c = CommandCompleter { engine: None };
        for cmd in &["characters gen ", "systems show "] {
            let pos = cmd.len();
            let values = completion_values(c.complete(cmd, pos));
            assert!(values.is_empty(), "expected empty for '{cmd}'");
        }
    }

    #[test]
    fn resolve_completion_kind_finds_the_longest_matching_path() {
        assert_eq!(
            resolve_completion_kind(&["characters", "show"]),
            Some(Completion::Slug)
        );
        assert_eq!(
            resolve_completion_kind(&["characters", "gen"]),
            Some(Completion::System)
        );
        // "characters inventory" (Slug) is a prefix of "characters inventory
        // add" (None) — the longer, more specific path should win.
        assert_eq!(
            resolve_completion_kind(&["characters", "inventory", "add"]),
            Some(Completion::None)
        );
    }

    #[test]
    fn resolve_completion_kind_sees_past_flags_typed_before_the_slug() {
        // A flag between the subcommand and the cursor used to defeat
        // completion entirely, because it broke the old exact
        // prefix-against-context string match.
        assert_eq!(
            resolve_completion_kind(&["characters", "show", "--verbose"]),
            Some(Completion::Slug)
        );
    }

    #[test]
    fn resolve_completion_kind_stops_once_the_positional_arg_is_typed() {
        // Once the slug itself has been typed, nothing further completes
        // from the table.
        assert_eq!(
            resolve_completion_kind(&["characters", "show", "some-slug"]),
            None
        );
    }
}
