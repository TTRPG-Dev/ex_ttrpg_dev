//! One-shot mode: `ttrpg-dev <command> [args...]` runs a single command
//! through the REPL's dispatcher and exits with a status scripts can check.

use std::io::IsTerminal;

use crate::commands::DisplayMode;
use crate::{prompts, repl};

/// Runs the command `args` names and returns the process exit status: `0`
/// if it succeeded, `1` if the engine didn't start or the command failed.
///
/// `args` are passed to the dispatcher as tokens as they are, not joined
/// and re-split, so an argument the shell quoted stays one token.
pub(crate) fn run(args: &[String]) -> i32 {
    let tokens: Vec<&str> = args.iter().map(String::as_str).collect();
    // Exiting is what one-shot mode does anyway.
    if let ["exit" | "quit" | "exit()"] = tokens.as_slice() {
        return 0;
    }
    // Unlike the REPL's pipe mode, piped stdin here isn't a stream of
    // answers someone prepared: one-shot mode is for scripts, and a script
    // should pass the flag that answers a prompt, or be told which one.
    if !std::io::stdin().is_terminal() {
        prompts::refuse_prompts();
    }
    let Some(mut engine) = repl::start_engine() else {
        return 1;
    };
    let mut display_mode = DisplayMode::Default;
    let result = repl::dispatch(&tokens, &mut engine, &mut display_mode);
    // Shut the engine down before the caller calls `process::exit`, which
    // skips destructors.
    drop(engine);
    match result {
        Ok(()) => 0,
        Err(_) => 1,
    }
}
