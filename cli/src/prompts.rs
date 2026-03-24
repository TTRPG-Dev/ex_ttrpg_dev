//! Interactive sub-prompts for yes/no and integer input.

use std::io::{self, BufRead};

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

pub(crate) fn prompt_string_from_list(question: &str, options: &[String]) -> Option<String> {
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
                let trimmed = line.trim().to_string();
                if options.contains(&trimmed) {
                    return Some(trimmed);
                }
                eprintln!("Invalid selection. Please choose from the list above.");
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
