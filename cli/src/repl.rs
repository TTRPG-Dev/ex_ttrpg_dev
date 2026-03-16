//! Interactive REPL using reedline.
//!
//! Drives the Elixir engine subprocess. Command dispatch and interactive
//! prompts live here; protocol types are in `protocol`, display in `display`.

use std::borrow::Cow;

use reedline::{
    ColumnarMenu, Completer, DefaultHinter, DefaultValidator, Emacs, FileBackedHistory, KeyCode,
    KeyModifiers, MenuBuilder, Prompt, PromptEditMode, PromptHistorySearch,
    PromptHistorySearchStatus, Reedline, ReedlineEvent, ReedlineMenu, Signal, Suggestion,
    default_emacs_keybindings,
};
use serde_json::json;

use crate::display;
use crate::engine::Engine;
use crate::protocol::{
    CharacterData, CharactersList, ChoicesResponse, ConceptRollResult, ConceptsList,
    InventoryResponse, PendingChoice, RollResult, SaveResult, SystemInfo, SystemsList,
};

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
                        span: reedline::Span { start: word_start, end: pos },
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
        ["help"] => print_help(),
        ["roll"] | ["roll", "--help"] => {
            println!("Usage: roll <dice>  e.g. roll 3d6, roll 1d20, roll 2d8+3d6")
        }
        ["roll", rest @ ..] => handle_roll(&rest.join(" "), engine),
        ["systems" | "system", rest @ ..] => handle_systems(rest, engine),
        ["characters" | "character", rest @ ..] => handle_characters(rest, engine),
        _ => eprintln!("Unknown command. Type `help` for available commands."),
    }
    true
}

fn handle_roll(dice: &str, engine: &mut Engine) {
    match engine.call::<_, RollResult>(&json!({"command": "roll", "dice": dice})) {
        Ok(result) => {
            for r in &result.results {
                let rolls_str: Vec<String> = r.rolls.iter().map(|n| n.to_string()).collect();
                println!("{}: [{}] = {}", r.spec, rolls_str.join(", "), r.total);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list"] => match engine.call::<_, SystemsList>(&json!({"command": "systems.list"})) {
            Ok(result) => {
                if result.systems.is_empty() {
                    println!("No configured systems found.");
                } else {
                    println!("Configured Systems:");
                    for s in &result.systems {
                        println!("  - {s}");
                    }
                }
            }
            Err(e) => eprintln!("Error: {e}"),
        },
        ["show", slug] => {
            let req = json!({"command": "systems.show", "system": slug});
            match engine.call::<_, SystemInfo>(&req) {
                Ok(info) => display::print_system_info(info),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["show", slug, "--concept-type", ct] => {
            let req = json!({"command": "systems.show", "system": slug, "concept_type": ct});
            match engine.call::<_, ConceptsList>(&req) {
                Ok(cl) => display::print_concepts_list(&cl),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        _ => eprintln!("Usage: systems list | systems show <slug> [--concept-type <type>]"),
    }
}

fn handle_characters(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list"] => {
            let req = json!({"command": "characters.list"});
            match engine.call::<_, CharactersList>(&req) {
                Ok(r) => display::print_characters_list(&r.characters, "No saved characters found."),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["list", "--system", system] => {
            let req = json!({"command": "characters.list", "system": system});
            match engine.call::<_, CharactersList>(&req) {
                Ok(r) => display::print_characters_list(
                    &r.characters,
                    &format!("No saved characters found for system `{system}`."),
                ),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["gen", system] => handle_characters_gen(system, engine),
        ["show", slug] => {
            let req = json!({"command": "characters.show", "character": slug});
            match engine.call::<_, CharacterData>(&req) {
                Ok(c) => display::print_character(&c),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["roll", slug, type_id, concept_id] => handle_characters_roll(
            slug,
            ConceptRollArgs { concept_type: type_id, concept_id },
            engine,
        ),
        ["award", slug, award_id, value] => handle_characters_award(
            slug,
            CharacterAwardArgs { award_id, value_str: value },
            engine,
        ),
        ["choices", slug] => handle_characters_choices(slug, engine),
        ["resolve_choice", slug] => handle_characters_resolve_choice(slug, engine),
        ["inventory", rest @ ..] => handle_inventory(rest, engine),
        _ => eprintln!(
            "Usage: characters list | gen <system> | show <slug> | roll <slug> <type> <concept>\n\
             \x20      characters award <slug> <award_id> <value> | choices <slug> | resolve_choice <slug>\n\
             \x20      characters inventory <slug>\n\
             \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20      characters inventory set <slug> <index> <field> <value>"
        ),
    }
}

fn handle_characters_gen(system: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.gen", "system": system});
    match engine.call::<_, CharacterData>(&req) {
        Ok(character) => {
            display::print_character(&character);
            if let Some(temp_id) = &character.temp_id
                && prompt_yes_no("Save this character?")
            {
                let save_req = json!({"command": "characters.save", "temp_id": temp_id});
                match engine.call::<_, SaveResult>(&save_req) {
                    Ok(saved) => println!("Saved as '{}'.", saved.slug),
                    Err(e) => eprintln!("Error saving: {e}"),
                }
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_roll(slug: &str, args: ConceptRollArgs<'_>, engine: &mut Engine) {
    let req = json!({
        "command": "characters.roll",
        "character": slug,
        "type": args.concept_type,
        "concept": args.concept_id,
    });
    match engine.call::<_, ConceptRollResult>(&req) {
        Ok(result) => {
            let rolls_str: Vec<String> = result.rolls.iter().map(|n| n.to_string()).collect();
            let bonus_str = if result.bonus >= 0 {
                format!("+{}", result.bonus)
            } else {
                result.bonus.to_string()
            };
            println!(
                "{} check: {} ({}: {}, bonus: {})",
                result.concept_name,
                result.total,
                result.dice,
                rolls_str.join(", "),
                bonus_str,
            );
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_award(slug: &str, args: CharacterAwardArgs<'_>, engine: &mut Engine) {
    // Send value as integer if it parses as one, otherwise as a string.
    // The server uses the award's value_type to validate; string values support
    // future award types (equipment IDs, feat names, etc.).
    let req = if let Ok(n) = args.value_str.parse::<i64>() {
        json!({"command": "characters.award", "character": slug, "award": args.award_id, "value": n})
    } else {
        json!({"command": "characters.award", "character": slug, "award": args.award_id, "value": args.value_str})
    };
    match engine.call::<_, CharacterData>(&req) {
        Ok(c) => {
            display::print_character(&c);
            if let Some(choices) = &c.pending_choices {
                display::print_pending_choices(choices);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_choices(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.choices", "character": slug});
    match engine.call::<_, ChoicesResponse>(&req) {
        Ok(r) => {
            if r.pending_choices.is_empty() {
                println!("No pending choices.");
            } else {
                display::print_pending_choices(&r.pending_choices);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_resolve_choice(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.choices", "character": slug});
    let choices = match engine.call::<_, ChoicesResponse>(&req) {
        Ok(r) => r.pending_choices,
        Err(e) => {
            eprintln!("Error: {e}");
            return;
        }
    };

    let Some(choice) = select_pending_choice(&choices) else {
        return;
    };

    let Some((value, selection)) = prompt_choice_value(choice, engine) else {
        return;
    };

    let req = json!({
        "command": "characters.resolve_choice",
        "character": slug,
        "progression": choice.id,
        "value": value,
        "selection": selection,
    });
    match engine.call::<_, CharacterData>(&req) {
        Ok(c) => {
            display::print_character(&c);
            if let Some(remaining) = &c.pending_choices
                && !remaining.is_empty()
            {
                display::print_pending_choices(remaining);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn select_pending_choice(choices: &[PendingChoice]) -> Option<&PendingChoice> {
    if choices.is_empty() {
        println!("No pending choices to resolve.");
        return None;
    }
    if choices.len() == 1 {
        return Some(&choices[0]);
    }
    println!("Pending choices:");
    for (i, c) in choices.iter().enumerate() {
        println!("  {}: {}", i + 1, c.name);
    }
    let idx = prompt_integer("Select choice (number):") as usize;
    match choices.get(idx.saturating_sub(1)) {
        Some(c) => Some(c),
        None => {
            eprintln!("Invalid selection.");
            None
        }
    }
}

fn prompt_choice_value(choice: &PendingChoice, engine: &mut Engine) -> Option<(i64, String)> {
    let Some(die) = &choice.roll else {
        let v = prompt_integer(&format!("Value for {}:", choice.name));
        return Some((v, "manual".to_string()));
    };

    let sides: i64 = die.trim_start_matches('d').parse().unwrap_or(8);
    let average = sides / 2 + 1;
    println!("\nResolving: {} ({})", choice.name, die);
    println!("Average HP (no roll): {average}");

    if !prompt_yes_no(&format!("Roll {die} for HP? (no = take average of {average})")) {
        return Some((average, "average".to_string()));
    }

    let roll_req = json!({"command": "roll", "dice": format!("1{die}")});
    match engine.call::<_, RollResult>(&roll_req) {
        Ok(result) => {
            let rolled = result.results[0].total;
            println!("Rolled: {rolled}");
            Some((rolled, "rolled".to_string()))
        }
        Err(e) => {
            eprintln!("Error rolling: {e}");
            None
        }
    }
}

fn prompt_integer(question: &str) -> i64 {
    use std::io::{self, BufRead};
    loop {
        print!("{question} ");
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        if let Some(Ok(line)) = stdin.lock().lines().next()
            && let Ok(n) = line.trim().parse::<i64>()
        {
            return n;
        }
        eprintln!("Please enter a valid number.");
    }
}

fn prompt_yes_no(question: &str) -> bool {
    use std::io::{self, BufRead};
    print!("(y/n) {question} ");
    let _ = std::io::Write::flush(&mut io::stdout());
    let stdin = io::stdin();
    let line = stdin.lock().lines().next().and_then(|l| l.ok());
    matches!(
        line.as_deref().map(str::trim).map(str::to_lowercase).as_deref(),
        Some("y") | Some("yes")
    )
}

// ── Argument bundles ──────────────────────────────────────────────────────────

struct ConceptRollArgs<'a> {
    concept_type: &'a str,
    concept_id: &'a str,
}

struct CharacterAwardArgs<'a> {
    award_id: &'a str,
    value_str: &'a str,
}

struct InventoryAddArgs<'a> {
    concept_type: &'a str,
    concept_id: &'a str,
    fields: serde_json::Value,
}

struct InventorySetArgs<'a> {
    index: u64,
    field: &'a str,
    value: serde_json::Value,
}

fn handle_inventory(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        [slug] => handle_characters_inventory(slug, engine),
        ["add", slug, type_id, id] => handle_characters_inventory_add(
            slug,
            InventoryAddArgs { concept_type: type_id, concept_id: id, fields: json!({}) },
            engine,
        ),
        ["add", slug, type_id, id, "--equipped"] => handle_characters_inventory_add(
            slug,
            InventoryAddArgs {
                concept_type: type_id,
                concept_id: id,
                fields: json!({"equipped": true}),
            },
            engine,
        ),
        ["set", slug, index_str, field, value_str] => {
            let Ok(index) = index_str.parse::<u64>() else {
                eprintln!("Error: index must be a non-negative integer");
                return;
            };
            let value: serde_json::Value = match *value_str {
                "true" => json!(true),
                "false" => json!(false),
                s => s.parse::<f64>().map_or_else(|_| json!(s), |n| json!(n)),
            };
            handle_characters_inventory_set(slug, InventorySetArgs { index, field, value }, engine)
        }
        _ => eprintln!(
            "Usage: characters inventory <slug>\n\
             \x20       characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20       characters inventory set <slug> <index> <field> <value>"
        ),
    }
}

fn handle_characters_inventory(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.inventory", "character": slug});
    match engine.call::<_, InventoryResponse>(&req) {
        Ok(r) => display::print_inventory(&r.inventory),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_inventory_add(slug: &str, args: InventoryAddArgs<'_>, engine: &mut Engine) {
    let req = json!({
        "command": "characters.inventory.add",
        "character": slug,
        "type": args.concept_type,
        "id": args.concept_id,
        "fields": args.fields,
    });
    match engine.call::<_, InventoryResponse>(&req) {
        Ok(r) => display::print_inventory(&r.inventory),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_inventory_set(slug: &str, args: InventorySetArgs<'_>, engine: &mut Engine) {
    let req = json!({
        "command": "characters.inventory.set",
        "character": slug,
        "index": args.index,
        "field": args.field,
        "value": args.value,
    });
    match engine.call::<_, InventoryResponse>(&req) {
        Ok(r) => display::print_inventory(&r.inventory),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn print_help() {
    println!(
        r#"
Commands:
  roll <dice>                                            Roll dice, e.g. roll 3d6, 1d20
  systems list                                           List configured rule systems
  systems show <system>                                  Show system info
  systems show <system> --concept-type <t>               List concepts of a type
  characters gen <system>                                Generate a character
  characters list                                        List saved characters
  characters list --system <system>                      List characters for a system
  characters show <slug>                                 Show a saved character
  characters roll <slug> <type> <concept>                Roll for a character concept
  characters award <slug> <award_id> <value>             Award something to a character
  characters choices <slug>                              Show pending progression choices
  characters resolve_choice <slug>                       Interactively resolve a pending choice
  characters inventory <slug>                            Show a character's inventory
  characters inventory add <slug> <type> <id>            Add an item to inventory
  characters inventory add <slug> <type> <id> --equipped Add an item and equip it
  characters inventory set <slug> <index> <field> <val>  Update an inventory item field
  help                                                   Show this help
  exit / quit                                            Exit
"#
    );
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

    let history: Box<dyn reedline::History> =
        match FileBackedHistory::with_file(1000, history_path()) {
            Ok(h) => Box::new(h),
            Err(_) => Box::new(FileBackedHistory::new(1000).expect("in-memory history")),
        };

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
