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

pub(crate) fn prompt_yes_no(question: &str) -> Option<bool> {
    print!("(y/n) {question} ");
    let _ = std::io::Write::flush(&mut io::stdout());
    let stdin = io::stdin();
    match stdin.lock().lines().next() {
        None | Some(Err(_)) => {
            println!();
            None
        }
        Some(Ok(line)) => Some(matches!(line.trim().to_lowercase().as_str(), "y" | "yes")),
    }
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
