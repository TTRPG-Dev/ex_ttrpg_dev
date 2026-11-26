//! Interactive sub-prompts for yes/no, integer, and option-list input.

use std::io::{self, BufRead};
use std::sync::atomic::{AtomicBool, Ordering};

use crate::protocol::OptionEntry;

/// Set when nobody can answer a prompt: one-shot mode with no terminal on
/// stdin. The REPL never sets it, even reading from a pipe, where answers
/// come from the next lines of input.
static PROMPTS_REFUSED: AtomicBool = AtomicBool::new(false);

/// From now on, commands must not prompt. Each command checks
/// [`can_prompt`] before it would ask, and fails with a message naming the
/// flag that answers the question, or saying it needs a terminal.
pub(crate) fn refuse_prompts() {
    PROMPTS_REFUSED.store(true, Ordering::Relaxed);
}

pub(crate) fn can_prompt() -> bool {
    !PROMPTS_REFUSED.load(Ordering::Relaxed)
}

/// Set when a prompt was reached while refused: a command that should
/// have checked [`can_prompt`] didn't. Its caller sees the prompt end as
/// if input had, which it treats as the user declining, so this is how one-shot
/// mode still knows to exit 1.
static PROMPT_REFUSED_UNCHECKED: AtomicBool = AtomicBool::new(false);

pub(crate) fn refused_an_unchecked_prompt() -> bool {
    PROMPT_REFUSED_UNCHECKED.load(Ordering::Relaxed)
}

/// Shared skeleton for a "print a prompt, read one stdin line, retry on bad
/// input" loop. `parse` turns the raw line into `Some(T)`, or prints its own
/// error and returns `None` to make the loop print `prompt` again.
pub(crate) fn prompt_loop<T>(
    prompt: &str,
    mut parse: impl FnMut(&str) -> Result<T, String>,
) -> Option<T> {
    // A command should have refused before getting here (see
    // `refuse_prompts`); the debug assertion makes the integration tests
    // catch one that doesn't. In a release build, behave as if input ended
    // rather than read an answer nobody gave, and record it so the exit
    // status still says the command failed.
    if !can_prompt() {
        debug_assert!(false, "prompt {prompt:?} reached with prompts refused");
        eprintln!("Error: no terminal to answer {:?}", prompt.trim());
        PROMPT_REFUSED_UNCHECKED.store(true, Ordering::Relaxed);
        return None;
    }
    loop {
        print!("{prompt}");
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => match parse(&line) {
                Ok(v) => return Some(v),
                Err(msg) => eprintln!("{msg}"),
            },
        }
    }
}

pub(crate) fn prompt_integer(question: &str) -> Option<i64> {
    prompt_loop(&format!("{question} "), |line| {
        line.trim()
            .parse::<i64>()
            .map_err(|_| "Please enter a valid number.".to_string())
    })
}

/// Retries until the trimmed input is non-empty.
pub(crate) fn prompt_nonempty_string(question: &str) -> Option<String> {
    prompt_loop(&format!("{question} "), |line| {
        let trimmed = line.trim().to_string();
        if trimmed.is_empty() {
            Err("Please enter a non-empty value.".to_string())
        } else {
            Ok(trimmed)
        }
    })
}

pub(crate) fn prompt_yes_no(question: &str) -> Option<bool> {
    prompt_loop(&format!("(y/n) {question} "), |line| {
        Ok(matches!(line.trim().to_lowercase().as_str(), "y" | "yes"))
    })
}

/// Prints a numbered list of `entries` and prompts the user to pick one by
/// number. Displays `entry.label`; returns `entry.id` on selection.
pub(crate) fn prompt_from_option_entries(label: &str, entries: &[OptionEntry]) -> Option<String> {
    println!();
    for (i, entry) in entries.iter().enumerate() {
        println!("  {}. {}", i + 1, entry.label);
    }
    prompt_loop(
        &format!("Select {} (1-{}): ", label, entries.len()),
        |line| {
            line.trim()
                .parse::<usize>()
                .ok()
                .filter(|&n| n >= 1 && n <= entries.len())
                .map(|n| entries[n - 1].id.clone())
                .ok_or_else(|| format!("Please enter a number between 1 and {}.", entries.len()))
        },
    )
}

/// Action returned by [`prompt_from_option_entries_or_detail`].
pub(crate) enum EntryAction {
    /// User selected an entry; contains the entry's `id`.
    Selected(String),
    /// User typed `show N`; contains the 0-based index.
    ShowDetail(usize),
}

fn parse_entry_input(trimmed: &str, entries: &[OptionEntry]) -> Result<EntryAction, String> {
    let len = entries.len();
    if let Some(rest) = trimmed.strip_prefix("show ") {
        return rest
            .trim()
            .parse::<usize>()
            .ok()
            .filter(|&n| n >= 1 && n <= len)
            .map(|n| EntryAction::ShowDetail(n - 1))
            .ok_or_else(|| format!("Please enter 'show N' where N is between 1 and {len}."));
    }
    trimmed
        .parse::<usize>()
        .ok()
        .filter(|&n| n >= 1 && n <= len)
        .map(|n| EntryAction::Selected(entries[n - 1].id.clone()))
        .ok_or_else(|| format!("Enter a number (1-{len}) or 'show N' for details."))
}

/// Like [`prompt_from_option_entries`] but also accepts `show N` to inspect an
/// entry before committing. The caller is responsible for fetching and printing
/// the detail when `ShowDetail` is returned.
pub(crate) fn prompt_from_option_entries_or_detail(
    label: &str,
    entries: &[OptionEntry],
) -> Option<EntryAction> {
    println!();
    for (i, entry) in entries.iter().enumerate() {
        println!("  {}. {}", i + 1, entry.label);
    }
    prompt_loop(
        &format!(
            "Select {} (1-{}, or 'show N' for details): ",
            label,
            entries.len()
        ),
        |line| parse_entry_input(line.trim().to_lowercase().as_str(), entries),
    )
}
