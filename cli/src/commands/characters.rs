use serde_json::json;

use super::inventory::handle_inventory;
use super::{CharacterAwardArgs, ConceptRollArgs, DisplayMode};
use crate::display;
use crate::engine::Engine;
use crate::prompts::{
    EntryAction, prompt_from_option_entries, prompt_from_option_entries_or_detail, prompt_integer,
    prompt_string, prompt_yes_no,
};
use crate::protocol::{
    BuildStartResult, BuildSubChoiceResult, CharacterData, CharacterSummary, CharactersList,
    ChoicesResponse, ConceptDetail, ConceptRollResult, OptionEntry, PendingChoice, PrepareResult,
    RandomResolveResult, RollResult, SaveResult, SpellsResponse,
};

pub(crate) fn handle_characters(tokens: &[&str], session_mode: DisplayMode, engine: &mut Engine) {
    let (tokens, display_mode) = strip_display_flags(tokens, session_mode);
    let tokens = tokens.as_slice();
    if dispatch_characters_help(tokens) {
        return;
    }
    match tokens {
        ["list"] => handle_characters_list(None, engine),
        ["list", "--system", system] => handle_characters_list(Some(system), engine),
        ["gen", system] => handle_characters_gen(system, engine),
        ["build", system] => handle_characters_build(system, engine),
        ["show", slug] => handle_characters_show(slug, display_mode, engine),
        ["roll", slug, type_id, concept_id] => handle_characters_roll(
            slug,
            ConceptRollArgs {
                concept_type: type_id,
                concept_id,
            },
            engine,
        ),
        ["award", slug, award_id] => {
            handle_characters_award_no_value(slug, award_id, display_mode, engine)
        }
        ["award", slug, award_id, value] => handle_characters_award(
            slug,
            CharacterAwardArgs {
                award_id,
                value_str: value,
            },
            display_mode,
            engine,
        ),
        ["delete", slug] => handle_characters_delete(slug, engine),
        ["delete-all", rest @ ..] => {
            if let Some(args) = parse_delete_all_flags(rest) {
                handle_characters_delete_all(engine, args);
            }
        }
        ["choices", slug] => handle_characters_choices(slug, display_mode, engine),
        ["resolve_choice", rest @ ..] => dispatch_resolve_choice(rest, display_mode, engine),
        ["inventory", rest @ ..] => handle_inventory(rest, engine),
        ["spells", slug] => handle_characters_spells(slug, engine),
        ["prepare", slug, spells @ ..] if !spells.is_empty() => {
            handle_characters_prepare(slug, spells, engine)
        }
        [] | ["--help"] => println!(
            "Usage: characters list | gen <system> | build <system> | show <slug> | delete <slug> | delete-all\n\
             \x20      characters roll <slug> <type> <concept>\n\
             \x20      characters award <slug> <award_id> <value> | choices <slug>\n\
             \x20      characters resolve_choice <slug> [--random-resolve]\n\
             \x20      characters inventory <slug>\n\
             \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20      characters inventory set <slug> <index> <field> <value>\n\
             \x20      characters spells <slug>\n\
             \x20      characters prepare <slug> <spell_id> [spell_id ...]"
        ),
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `characters --help`."),
    }
}

fn dispatch_characters_help(tokens: &[&str]) -> bool {
    match tokens {
        ["gen", "--help"] => println!("Usage: characters gen <system>"),
        ["list", "--help"] => println!("Usage: characters list [--system <system>]"),
        ["delete", "--help"] => println!("Usage: characters delete <slug>"),
        ["delete-all", "--help"] => {
            println!("Usage: characters delete-all [-y|--yes] [--system <system>]")
        }
        ["show", "--help"] => println!("Usage: characters show <slug>"),
        ["roll", "--help"] => println!("Usage: characters roll <slug> <type> <concept>"),
        ["award", "--help"] => println!(
            "Usage: characters award <slug> <award_id> <value>\n\
             \x20      characters award <slug> level_up"
        ),
        ["choices", "--help"] => println!("Usage: characters choices <slug>"),
        ["build", "--help"] => println!("Usage: characters build <system>"),
        ["inventory", "--help"] => println!(
            "Usage: characters inventory <slug>\n\
             \x20      characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20      characters inventory set <slug> <index> <field> <value>"
        ),
        ["spells", "--help"] => println!("Usage: characters spells <slug>"),
        ["prepare", "--help"] => {
            println!("Usage: characters prepare <slug> <spell_id> [spell_id ...]")
        }
        _ => return false,
    }
    true
}

fn strip_display_flags<'a>(
    tokens: &[&'a str],
    session_mode: DisplayMode,
) -> (Vec<&'a str>, DisplayMode) {
    let mut mode = session_mode;
    let mut remaining = Vec::new();
    for &t in tokens {
        match t {
            "--verbose" => mode = DisplayMode::Verbose,
            "--succinct" => mode = DisplayMode::Succinct,
            other => remaining.push(other),
        }
    }
    (remaining, mode)
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
    match engine.call::<_, crate::protocol::DeletedCharacter>(&req) {
        Ok(r) => println!("Deleted character: {}", r.deleted),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_show(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = json!({"command": "characters.show", "character": slug, "display_mode": display_mode.as_str()});
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

fn handle_characters_award(
    slug: &str,
    args: CharacterAwardArgs<'_>,
    display_mode: DisplayMode,
    engine: &mut Engine,
) {
    // Send value as integer if it parses as one, otherwise as a string.
    // The server uses the award's value_type to validate; string values support
    // future award types (equipment IDs, feat names, etc.).
    let mode = display_mode.as_str();
    let req = if let Ok(n) = args.value_str.parse::<i64>() {
        json!({"command": "characters.award", "character": slug, "award": args.award_id, "value": n, "display_mode": mode})
    } else {
        json!({"command": "characters.award", "character": slug, "award": args.award_id, "value": args.value_str, "display_mode": mode})
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

fn handle_characters_award_no_value(
    slug: &str,
    award_id: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) {
    let mode = display_mode.as_str();
    let req = json!({"command": "characters.award", "character": slug, "award": award_id, "display_mode": mode});
    match engine.call::<_, CharacterData>(&req) {
        Ok(c) => {
            display::print_character(&c);
            if let Some(xp) = c.awarded_xp {
                println!("Awarded {award_id}: +{xp} XP");
            }
            if let Some(choices) = &c.pending_choices {
                display::print_pending_choices(choices);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn format_resolution_line(r: &crate::protocol::ResolutionEntry) -> String {
    let level_str = r
        .earned_at_level
        .map(|l| format!(" (level {l})"))
        .unwrap_or_default();
    let detail = if let Some(name) = &r.selection_name {
        name.clone()
    } else if let Some(id) = &r.selection_id {
        id.clone()
    } else if let (Some(v), Some(m)) = (r.rolled_value, &r.method) {
        format!("{v} ({m})")
    } else {
        String::new()
    };
    if detail.is_empty() {
        format!("  • {}{}", r.name, level_str)
    } else {
        format!("  • {}: {}{}", r.name, detail, level_str)
    }
}

fn handle_characters_random_resolve(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = json!({"command": "characters.random_resolve", "character": slug, "display_mode": display_mode.as_str()});
    match engine.call::<_, RandomResolveResult>(&req) {
        Ok(result) => {
            let header = format!("# {}\n\n", result.name);
            let body = display::format_character_lists(&result.character_lists);
            display::page_output(&format!("{header}{body}"));
            if result.resolutions.is_empty() {
                println!("No pending choices to resolve.");
            } else {
                println!("\nResolved {} choice(s):", result.resolutions.len());
                for r in &result.resolutions {
                    println!("{}", format_resolution_line(r));
                }
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_choices(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = json!({"command": "characters.choices", "character": slug, "display_mode": display_mode.as_str()});
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

fn build_resolve_choice_request(
    slug: &str,
    choice: &PendingChoice,
    value: i64,
    selection: &str,
) -> serde_json::Value {
    match (&choice.scope_type, &choice.scope_id) {
        (Some(scope_type), Some(scope_id)) => json!({
            "command": "characters.resolve_choice",
            "character": slug,
            "scope_type": scope_type,
            "scope_id": scope_id,
            "choice": choice.id,
            "selection": selection,
        }),
        _ => json!({
            "command": "characters.resolve_choice",
            "character": slug,
            "progression": choice.id,
            "value": value,
            "selection": selection,
        }),
    }
}

fn dispatch_resolve_choice(rest: &[&str], display_mode: DisplayMode, engine: &mut Engine) {
    match rest {
        ["--help"] => println!("Usage: characters resolve_choice <slug> [--random-resolve]"),
        [slug] => handle_characters_resolve_choice(slug, display_mode, engine),
        [slug, "--random-resolve"] => handle_characters_random_resolve(slug, display_mode, engine),
        _ => eprintln!("Unknown subcommand. Try `characters resolve_choice --help`."),
    }
}

fn handle_characters_resolve_choice(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = json!({"command": "characters.choices", "character": slug, "display_mode": display_mode.as_str()});
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

    let req = build_resolve_choice_request(slug, choice, value, &selection);
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

fn resolve_build_progressions(
    slug: &str,
    mut character: CharacterData,
    engine: &mut Engine,
) -> Option<CharacterData> {
    loop {
        let pending: Vec<PendingChoice> = match &character.pending_choices {
            Some(p) if !p.is_empty() => p.clone(),
            _ => return Some(character),
        };
        let choice = select_pending_choice(&pending)?.clone();
        let (value, selection) = prompt_choice_value(&choice, engine)?;
        let req = build_resolve_choice_request(slug, &choice, value, &selection);
        character = match engine.call::<_, CharacterData>(&req) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("Error: {e}");
                return None;
            }
        };
    }
}

fn resolve_sub_choices(
    temp_id: &str,
    mut sub_choices: Vec<PendingChoice>,
    engine: &mut Engine,
) -> bool {
    while let Some(choice) = sub_choices.first() {
        let options: Vec<OptionEntry> = match &choice.options {
            Some(opts) if !opts.is_empty() => opts.clone(),
            _ => {
                sub_choices.remove(0);
                continue;
            }
        };
        let scope_type = choice.scope_type.clone().unwrap_or_default();
        let scope_id = choice.scope_id.clone().unwrap_or_default();
        let choice_id = choice.id.clone();
        let Some(selection) = prompt_from_option_entries(&choice.name, &options) else {
            return false;
        };
        let req = json!({
            "command": "characters.build_resolve_sub",
            "temp_id": temp_id,
            "scope_type": scope_type,
            "scope_id": scope_id,
            "choice": choice_id,
            "selection": selection,
        });
        sub_choices = match engine.call::<_, BuildSubChoiceResult>(&req) {
            Ok(r) => r.sub_choices,
            Err(e) => {
                eprintln!("Error: {e}");
                return false;
            }
        };
    }
    true
}

fn format_field_value(val: &serde_json::Value) -> Option<String> {
    if let Some(s) = val.as_str() {
        return if s.is_empty() {
            None
        } else {
            Some(s.to_string())
        };
    }
    let arr = val.as_array()?;
    let text = arr
        .iter()
        .filter_map(|v| v.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    if text.is_empty() { None } else { Some(text) }
}

fn format_choice_entry(id: &str, cd: &serde_json::Value) -> String {
    let cname = cd["name"].as_str().unwrap_or(id).replace('_', " ");
    let count = cd.get("count").and_then(|v| v.as_u64()).unwrap_or(1);
    let from = match cd.get("options").and_then(|v| v.as_array()) {
        Some(o) => format!("{} option(s)", o.len()),
        None => format!("all {}", cd["type"].as_str().unwrap_or("?")),
    };
    format!("  • {cname} (pick {count} from {from})")
}

fn format_contribute_entry(c: &serde_json::Value) -> Option<String> {
    let target = c.get("target")?.as_str()?;
    let value = c.get("value")?;
    Some(match c.get("when").and_then(|w| w.as_str()) {
        Some(w) => format!("  • {target}: {value} (when {w})"),
        None => format!("  • {target}: {value}"),
    })
}

fn format_contributes(f: &serde_json::Value) -> Vec<String> {
    let Some(arr) = f.get("contributes").and_then(|v| v.as_array()) else {
        return vec![];
    };
    arr.iter().filter_map(format_contribute_entry).collect()
}

fn format_required_choices(f: &serde_json::Value) -> Vec<String> {
    let Some(choices) = f.get("choices").and_then(|c| c.as_object()) else {
        return vec![];
    };
    choices
        .iter()
        .filter(|(_, cd)| {
            cd.get("required")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
        })
        .map(|(id, cd)| format_choice_entry(id, cd))
        .collect()
}

fn format_concept_detail(detail: &ConceptDetail) -> String {
    const FIELDS: &[(&str, &str)] = &[
        ("hit_die", "Hit die"),
        ("armor_proficiencies", "Armor"),
        ("weapon_proficiencies", "Weapons"),
        ("languages", "Languages"),
        ("damage_resistances", "Resistances"),
    ];
    let f = &detail.fields;
    let name = f["name"].as_str().unwrap_or(&detail.concept_type);
    let mut lines = vec![format!("=== {name} ===")];
    lines.extend(FIELDS.iter().filter_map(|(key, label)| {
        f.get(*key)
            .and_then(format_field_value)
            .map(|t| format!("{label}: {t}"))
    }));
    let contributes = format_contributes(f);
    if !contributes.is_empty() {
        lines.push("Contributes:".to_string());
        lines.extend(contributes);
    }
    let required = format_required_choices(f);
    if !required.is_empty() {
        lines.push("Choices to make:".to_string());
        lines.extend(required);
    }
    lines.join("\n")
}

fn show_concept_detail(system: &str, concept_type: &str, concept_id: &str, engine: &mut Engine) {
    let req = json!({
        "command": "systems.show",
        "system": system,
        "concept_type": concept_type,
        "concept_id": concept_id,
    });
    match engine.call::<_, ConceptDetail>(&req) {
        Ok(detail) => println!("\n{}\n", format_concept_detail(&detail)),
        Err(e) => eprintln!("Could not load details: {e}"),
    }
}

fn resolve_building_choices(
    temp_id: &str,
    groups: &[crate::protocol::BuildingChoiceGroup],
    system: &str,
    engine: &mut Engine,
) -> bool {
    for group in groups {
        let concept_id = loop {
            match prompt_from_option_entries_or_detail(&group.name, &group.concepts) {
                None => return false,
                Some(EntryAction::Selected(id)) => break id,
                Some(EntryAction::ShowDetail(idx)) => {
                    show_concept_detail(
                        system,
                        &group.concept_type,
                        &group.concepts[idx].id,
                        engine,
                    );
                }
            }
        };
        let req = json!({
            "command": "characters.build_select",
            "temp_id": temp_id,
            "concept_type": group.concept_type,
            "concept_id": concept_id,
        });
        let sub_choices = match engine.call::<_, BuildSubChoiceResult>(&req) {
            Ok(r) => r.sub_choices,
            Err(e) => {
                eprintln!("Error: {e}");
                return false;
            }
        };
        if !resolve_sub_choices(temp_id, sub_choices, engine) {
            return false;
        }
    }
    true
}

fn handle_characters_build(system: &str, engine: &mut Engine) {
    let name = loop {
        let Some(input) = prompt_string("Character name:") else {
            return;
        };
        let trimmed = input.trim().to_string();
        if !trimmed.is_empty() {
            break trimmed;
        }
    };
    let req = json!({"command": "characters.build_start", "system": system, "name": name});
    let build_start = match engine.call::<_, BuildStartResult>(&req) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Error: {e}");
            return;
        }
    };
    let temp_id = build_start.temp_id;
    if !resolve_building_choices(&temp_id, &build_start.building_choices, system, engine) {
        return;
    }
    let finish_req = json!({"command": "characters.build_finish", "temp_id": temp_id});
    let character = match engine.call::<_, CharacterData>(&finish_req) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error: {e}");
            return;
        }
    };
    let slug = match &character.slug {
        Some(s) => s.clone(),
        None => {
            eprintln!("Error: build_finish did not return a slug");
            return;
        }
    };
    let final_char = match resolve_build_progressions(&slug, character, engine) {
        Some(c) => c,
        None => return,
    };
    display::print_character(&final_char);
}

fn handle_characters_spells(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.spells", "character": slug});
    match engine.call::<_, SpellsResponse>(&req) {
        Ok(r) => display::print_spells(&r),
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_prepare(slug: &str, spells: &[&str], engine: &mut Engine) {
    let spell_ids: Vec<&str> = spells.to_vec();
    let req = json!({"command": "characters.prepare", "character": slug, "spells": spell_ids});
    match engine.call::<_, PrepareResult>(&req) {
        Ok(r) => {
            println!("Prepared {}/{} spells.", r.prepared_spells.len(), r.cap);
            if !r.always_prepared.is_empty() {
                println!("Always prepared: {}", r.always_prepared.join(", "));
            }
            println!("Prepared: {}", r.prepared_spells.join(", "));
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn prompt_choice_value(choice: &PendingChoice, engine: &mut Engine) -> Option<(i64, String)> {
    if let Some(options) = &choice.options {
        let selection = prompt_from_option_entries(&choice.name, options)?;
        return Some((0, selection));
    }

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
