//! Interactive sub-prompts for yes/no, integer, and option-list input.

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

/// Prints a numbered list of `options` and prompts the user to pick one by
/// number. Re-prompts on invalid input.
pub(crate) fn prompt_from_options(label: &str, options: &[String]) -> Option<String> {
    println!();
    for (i, opt) in options.iter().enumerate() {
        println!("  {}. {opt}", i + 1);
    }
    loop {
        print!("Select {} (1-{}): ", label, options.len());
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => match line.trim().parse::<usize>() {
                Ok(n) if n >= 1 && n <= options.len() => return Some(options[n - 1].clone()),
                _ => eprintln!("Please enter a number between 1 and {}.", options.len()),
            },
        }
    }
}
