//! Interactive sub-prompts for yes/no, integer, and option-list input.

use std::io::{self, BufRead};

use crate::protocol::OptionEntry;

pub(crate) fn prompt_integer(question: &str) -> Option<i64> {
    loop {
        print!("{question} ");
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => {
                if let Ok(n) = line.trim().parse::<i64>() {
                    return Some(n);
                }
                eprintln!("Please enter a valid number.");
            }
        }
    }
}

pub(crate) fn prompt_string(question: &str) -> Option<String> {
    print!("{question} ");
    let _ = std::io::Write::flush(&mut io::stdout());
    let stdin = io::stdin();
    match stdin.lock().lines().next() {
        None | Some(Err(_)) => {
            println!();
            None
        }
        Some(Ok(line)) => Some(line),
    }
}

pub(crate) fn prompt_yes_no(question: &str) -> Option<bool> {
    let line = prompt_string(&format!("(y/n) {question}"))?;
    Some(matches!(line.trim().to_lowercase().as_str(), "y" | "yes"))
}

/// Prints a numbered list of `entries` and prompts the user to pick one by
/// number. Displays `entry.label`; returns `entry.id` on selection.
pub(crate) fn prompt_from_option_entries(label: &str, entries: &[OptionEntry]) -> Option<String> {
    println!();
    for (i, entry) in entries.iter().enumerate() {
        println!("  {}. {}", i + 1, entry.label);
    }
    loop {
        print!("Select {} (1-{}): ", label, entries.len());
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => match line.trim().parse::<usize>() {
                Ok(n) if n >= 1 && n <= entries.len() => return Some(entries[n - 1].id.clone()),
                _ => eprintln!("Please enter a number between 1 and {}.", entries.len()),
            },
        }
    }
}

/// Action returned by [`prompt_from_option_entries_or_detail`].
pub(crate) enum EntryAction {
    /// User selected an entry; contains the entry's `id`.
    Selected(String),
    /// User typed `show N`; contains the 0-based index.
    ShowDetail(usize),
}

fn parse_entry_input(trimmed: &str, entries: &[OptionEntry]) -> Option<EntryAction> {
    let len = entries.len();
    if let Some(rest) = trimmed.strip_prefix("show ") {
        let idx = rest
            .trim()
            .parse::<usize>()
            .ok()
            .filter(|&n| n >= 1 && n <= len);
        if idx.is_none() {
            eprintln!("Please enter 'show N' where N is between 1 and {len}.");
        }
        return idx.map(|n| EntryAction::ShowDetail(n - 1));
    }
    let n = trimmed
        .parse::<usize>()
        .ok()
        .filter(|&n| n >= 1 && n <= len);
    if let Some(n) = n {
        return Some(EntryAction::Selected(entries[n - 1].id.clone()));
    }
    eprintln!("Enter a number (1-{len}) or 'show N' for details.");
    None
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
    loop {
        print!(
            "Select {} (1-{}, or 'show N' for details): ",
            label,
            entries.len()
        );
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => {
                let trimmed = line.trim().to_lowercase();
                if let Some(action) = parse_entry_input(&trimmed, entries) {
                    return Some(action);
                }
            }
        }
    }
}
