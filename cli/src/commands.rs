//! Command handlers — one function per CLI command or subcommand group.
//!
//! Each `handle_*` function receives the remaining tokens after the top-level
//! command word and an `Engine` reference, then dispatches to the engine and
//! prints results via `display`.

use serde_json::json;

use crate::display;
use crate::engine::Engine;
use crate::prompts::{prompt_integer, prompt_yes_no};
use crate::protocol::{
    CharacterData, CharacterSummary, CharactersList, ChoicesResponse, ConceptRollResult,
    ConceptsList, DeletedCharacter, InventoryResponse, PendingChoice, RollResult, SaveResult,
    SystemInfo, SystemsList,
};

// ── Argument bundles ──────────────────────────────────────────────────────────

pub(crate) struct ConceptRollArgs<'a> {
    pub(crate) concept_type: &'a str,
    pub(crate) concept_id: &'a str,
}

pub(crate) struct CharacterAwardArgs<'a> {
    pub(crate) award_id: &'a str,
    pub(crate) value_str: &'a str,
}

struct DeleteAllArgs<'a> {
    yes: bool,
    system: Option<&'a str>,
}

fn parse_delete_all_flags<'a>(tokens: &[&'a str]) -> Option<DeleteAllArgs<'a>> {
    let mut yes = false;
    let mut system = None;
    let mut i = 0;
    while i < tokens.len() {
        match tokens[i] {
            "--yes" | "-y" => yes = true,
            "--system" => {
                i += 1;
                match tokens.get(i) {
                    Some(s) => system = Some(*s),
                    None => {
                        eprintln!("Error: --system requires a value");
                        return None;
                    }
                }
            }
            unknown => {
                eprintln!("Unknown flag '{unknown}'. Try `characters delete-all --help`.");
                return None;
            }
        }
        i += 1;
    }
    Some(DeleteAllArgs { yes, system })
}

// ── roll ──────────────────────────────────────────────────────────────────────

pub(crate) fn handle_roll(dice: &str, engine: &mut Engine) {
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

// ── systems ───────────────────────────────────────────────────────────────────

pub(crate) fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list", "--help"] => println!("Usage: systems list"),
        ["show", "--help"] => {
            println!("Usage: systems show <slug> [--concept-type <type>]")
        }
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
        [] | ["--help"] => {
            println!("Usage: systems list | systems show <slug> [--concept-type <type>]")
        }
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `systems --help`."),
    }
}

// ── characters ────────────────────────────────────────────────────────────────

pub(crate) fn handle_characters(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["gen", "--help"] => println!("Usage: characters gen <system>"),
        ["list", "--help"] => println!("Usage: characters list [--system <system>]"),
        ["delete", "--help"] => println!("Usage: characters delete <slug>"),
        ["delete-all", "--help"] => {
            println!("Usage: characters delete-all [-y|--yes] [--system <system>]")
        }
        ["show", "--help"] => println!("Usage: characters show <slug>"),
        ["roll", "--help"] => println!("Usage: characters roll <slug> <type> <concept>"),
        ["award", "--help"] => println!("Usage: characters award <slug> <award_id> <value>"),
        ["choices", "--help"] => println!("Usage: characters choices <slug>"),
        ["resolve_choice", "--help"] => println!("Usage: characters resolve_choice <slug>"),
        ["inventory", "--help"] => println!(
            "Usage: characters inventory <slug>\n\
             \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20      characters inventory set <slug> <index> <field> <value>"
        ),
        ["list"] => handle_characters_list(None, engine),
        ["list", "--system", system] => handle_characters_list(Some(system), engine),
        ["gen", system] => handle_characters_gen(system, engine),
        ["show", slug] => handle_characters_show(slug, engine),
        ["roll", slug, type_id, concept_id] => handle_characters_roll(
            slug,
            ConceptRollArgs {
                concept_type: type_id,
                concept_id,
            },
            engine,
        ),
        ["award", slug, award_id, value] => handle_characters_award(
            slug,
            CharacterAwardArgs {
                award_id,
                value_str: value,
            },
            engine,
        ),
        ["delete", slug] => handle_characters_delete(slug, engine),
        ["delete-all", rest @ ..] => {
            if let Some(args) = parse_delete_all_flags(rest) {
                handle_characters_delete_all(engine, args);
            }
        }
        ["choices", slug] => handle_characters_choices(slug, engine),
        ["resolve_choice", slug] => handle_characters_resolve_choice(slug, engine),
        ["inventory", rest @ ..] => handle_inventory(rest, engine),
        [] | ["--help"] => println!(
            "Usage: characters list | gen <system> | show <slug> | delete <slug> | delete-all\n\
             \x20      characters roll <slug> <type> <concept>\n\
             \x20      characters award <slug> <award_id> <value> | choices <slug> | resolve_choice <slug>\n\
             \x20      characters inventory <slug>\n\
             \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20      characters inventory set <slug> <index> <field> <value>"
        ),
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `characters --help`."),
    }
}

fn handle_characters_gen(system: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.gen", "system": system});
    match engine.call::<_, CharacterData>(&req) {
        Ok(character) => {
            display::print_character(&character);
            if let Some(temp_id) = &character.temp_id
                && prompt_yes_no("Save this character?").unwrap_or(false)
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

fn handle_characters_list(system: Option<&&str>, engine: &mut Engine) {
    let req = match system {
        Some(s) => json!({"command": "characters.list", "system": s}),
        None => json!({"command": "characters.list"}),
    };
    let empty_msg = match system {
        Some(s) => format!(
            "No saved characters found for system `{s}`. Run `characters gen {s}` to create one."
        ),
        None => "No saved characters found. Run `characters gen <system>` to create one.".into(),
    };
    match engine.call::<_, CharactersList>(&req) {
        Ok(r) => display::print_characters_list(&r.characters, &empty_msg),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn confirm_delete_character(character: &CharacterSummary, yes: bool) -> Option<bool> {
    if yes {
        Some(true)
    } else {
        let question = format!("Delete \"{}\" ({})? [y/N]", character.name, character.slug);
        prompt_yes_no(&question)
    }
}

fn handle_characters_delete_all(engine: &mut Engine, args: DeleteAllArgs) {
    let req = match args.system {
        Some(s) => json!({"command": "characters.list", "system": s}),
        None => json!({"command": "characters.list"}),
    };
    let characters = match engine.call::<_, CharactersList>(&req) {
        Ok(r) => r.characters,
        Err(e) => {
            eprintln!("Error: {e}");
            return;
        }
    };
    if characters.is_empty() {
        println!("No saved characters found.");
        return;
    }
    for character in &characters {
        match confirm_delete_character(character, args.yes) {
            Some(true) => handle_characters_delete(&character.slug, engine),
            Some(false) => println!("Skipped {}", character.slug),
            None => return,
        }
    }
}

fn handle_characters_delete(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.delete", "character": slug});
    match engine.call::<_, DeletedCharacter>(&req) {
        Ok(r) => println!("Deleted character: {}", r.deleted),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_show(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.show", "character": slug});
    match engine.call::<_, CharacterData>(&req) {
        Ok(c) => display::page_output(&display::format_character(&c)),
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
    let idx = prompt_integer("Select choice (number):")? as usize;
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
        let v = prompt_integer(&format!("Value for {}:", choice.name))?;
        return Some((v, "manual".to_string()));
    };

    let sides: i64 = die.trim_start_matches('d').parse().unwrap_or(8);
    let average = sides / 2 + 1;
    println!("\nResolving: {} ({})", choice.name, die);
    println!("Average HP (no roll): {average}");

    if !prompt_yes_no(&format!(
        "Roll {die} for HP? (no = take average of {average})"
    ))? {
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

// ── inventory ─────────────────────────────────────────────────────────────────

fn handle_inventory(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["add", "--help"] => {
            println!("Usage: characters inventory add <slug> <type> <id> [--equipped]")
        }
        ["set", "--help"] => {
            println!("Usage: characters inventory set <slug> <index> <field> <value>")
        }
        [slug] => {
            let req = json!({"command": "characters.inventory", "character": slug});
            call_inventory(&req, engine);
        }
        ["add", slug, type_id, id] => call_inventory(
            &json!({"command": "characters.inventory.add", "character": slug,
                    "type": type_id, "id": id, "fields": {}}),
            engine,
        ),
        ["add", slug, type_id, id, "--equipped"] => call_inventory(
            &json!({"command": "characters.inventory.add", "character": slug,
                    "type": type_id, "id": id, "fields": {"equipped": true}}),
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
            call_inventory(
                &json!({"command": "characters.inventory.set", "character": slug,
                        "index": index, "field": field, "value": value}),
                engine,
            );
        }
        _ => eprintln!(
            "Usage: characters inventory <slug>\n\
             \x20       characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20       characters inventory set <slug> <index> <field> <value>"
        ),
    }
}

fn call_inventory(req: &serde_json::Value, engine: &mut Engine) {
    match engine.call::<_, InventoryResponse>(req) {
        Ok(r) => display::print_inventory(&r.inventory),
        Err(e) => eprintln!("Error: {e}"),
    }
}

// ── Help ──────────────────────────────────────────────────────────────────────

pub(crate) fn print_help() {
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
  characters delete <slug>                               Delete a saved character
  characters delete-all                                  Delete all characters (confirms each)
  characters delete-all --yes                            Delete all characters without confirmation
  characters delete-all --system <system>                Delete all characters for a system
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
