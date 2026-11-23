use super::table::COMMAND_TABLE;

/// Builds the display rows for the global command listing, merging adjacent
/// table entries that share a summary (`exit` / `quit`) onto one line.
fn help_rows() -> Vec<(String, &'static str)> {
    let mut rows: Vec<(String, &'static str)> = Vec::new();
    for spec in COMMAND_TABLE {
        if let Some(last) = rows.last_mut()
            && last.1 == spec.summary
        {
            last.0 = format!("{} / {}", last.0, spec.path);
            continue;
        }
        rows.push((spec.path.to_string(), spec.summary));
    }
    rows
}

pub(crate) fn print_help() {
    let rows = help_rows();
    let width = rows.iter().map(|(path, _)| path.len()).max().unwrap_or(0);

    println!("\nCommands:");
    for (path, summary) in &rows {
        println!("  {path:<width$}  {summary}");
    }
    println!();
}
