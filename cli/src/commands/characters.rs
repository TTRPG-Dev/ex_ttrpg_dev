use serde_json::json;

use super::build::{ChoiceResolution, handle_characters_build, prompt_choice_value};
use super::inventory::handle_inventory;
use super::table::{self, COMMAND_TABLE};
use super::{CharacterAwardArgs, ConceptRollArgs, DisplayMode, call_or_report};
use crate::display;
use crate::engine::Engine;
use crate::prompts::{prompt_integer, prompt_yes_no};
use crate::protocol::{
    CharacterData, CharacterSummary, CharactersList, ChoicesResponse, ConceptRollResult,
    CopiedCharacter, InventoryResponse, PendingChoice, PreparationStateResponse,
    RandomResolveResult, Request, SaveResult,
};

pub(crate) fn handle_characters(tokens: &[&str], session_mode: DisplayMode, engine: &mut Engine) {
    let (tokens, display_mode) = strip_display_flags(tokens, session_mode);
    let tokens = tokens.as_slice();
    if table::dispatch_help(tokens, "characters") {
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
        ["copy", slug] => handle_characters_copy(slug, None, engine),
        ["copy", slug, new_slug] => handle_characters_copy(slug, Some(new_slug), engine),
        ["copy", ..] => {
            eprintln!(
                "Expected a character and an optional new slug. Try `characters copy --help`."
            )
        }
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
        ["prepare", slug, items @ ..] if !items.is_empty() => {
            handle_activate("prepare", slug, items, engine)
        }
        [] | ["--help"] => print_characters_usage(),
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `characters --help`."),
    }
}

/// Lists every `characters` subcommand's usage, pulled from the same
/// `COMMAND_TABLE` row each subcommand's own `--help` prints from (see
/// `table::dispatch_help`).
// "characters inventory"'s own usage already lists these as continuation
// lines; their standalone rows are skipped in the overview below so it
// doesn't show each of them twice.
const COVERED_BY_INVENTORY_USAGE: &[&str] =
    &["characters inventory add", "characters inventory set"];

fn print_characters_usage() {
    println!("Usage:");
    for spec in COMMAND_TABLE {
        if !spec.path.starts_with("characters ") {
            continue;
        }
        if COVERED_BY_INVENTORY_USAGE.contains(&spec.path) {
            continue;
        }
        println!("  {}", spec.usage);
    }
}

/// Pulls `--verbose`/`--succinct` out of the token stream before subcommand
/// dispatch, so they can appear anywhere in a `characters` invocation
/// regardless of which subcommand follows — intentionally including
/// subcommands (`list`, `delete`, `gen`, ...) that don't take a
/// `DisplayMode` and so end up ignoring the result. This is deliberately
/// more permissive than `delete-all`'s own flag parser
/// (`parse_delete_all_flags`), which rejects any flag it doesn't recognize;
/// these two are treated as cross-cutting session flags rather than
/// per-subcommand arguments.
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
    let req = Request::CharactersGen { system };
    let Some(character) = call_or_report::<CharacterData>(engine, &req) else {
        return;
    };
    display::print_character(&character);
    if let Some(temp_id) = &character.temp_id
        && prompt_yes_no("Save this character?").unwrap_or(false)
    {
        let save_req = Request::CharactersSave { temp_id };
        match engine.call::<_, SaveResult>(&save_req) {
            Ok(saved) => println!("Saved as '{}'.", saved.slug),
            Err(e) => eprintln!("Error saving: {e}"),
        }
    }
}

fn handle_characters_list(system: Option<&&str>, engine: &mut Engine) {
    let req = Request::CharactersList {
        system: system.copied(),
    };
    let empty_msg = match system {
        Some(s) => format!(
            "No saved characters found for system `{s}`. Run `characters gen {s}` to create one."
        ),
        None => "No saved characters found. Run `characters gen <system>` to create one.".into(),
    };
    let Some(r) = call_or_report::<CharactersList>(engine, &req) else {
        return;
    };
    display::print_characters_list(&r.characters, &empty_msg);
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
    let req = Request::CharactersList {
        system: args.system,
    };
    let Some(r) = call_or_report::<CharactersList>(engine, &req) else {
        return;
    };
    let characters = r.characters;
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

/// The engine picks the slug when none is given, names the copy, and
/// refuses a taken or malformed slug; the CLI repeats none of those rules.
fn handle_characters_copy(slug: &str, new_slug: Option<&str>, engine: &mut Engine) {
    let req = Request::CharactersCopy {
        character: slug,
        slug: new_slug,
    };
    let Some(r) = call_or_report::<CopiedCharacter>(engine, &req) else {
        return;
    };
    println!("Copied {} to {} (\"{}\")", r.copied, r.created, r.name);
}

fn handle_characters_delete(slug: &str, engine: &mut Engine) {
    let req = Request::CharactersDelete { character: slug };
    let Some(r) = call_or_report::<crate::protocol::DeletedCharacter>(engine, &req) else {
        return;
    };
    println!("Deleted character: {}", r.deleted);
}

fn handle_characters_show(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = Request::CharactersShow {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let Some(c) = call_or_report::<CharacterData>(engine, &req) else {
        return;
    };
    display::page_output(&display::format_character(&c));
}

fn handle_characters_roll(slug: &str, args: ConceptRollArgs<'_>, engine: &mut Engine) {
    let req = Request::CharactersRoll {
        character: slug,
        concept_type: args.concept_type,
        concept: args.concept_id,
    };
    let Some(result) = call_or_report::<ConceptRollResult>(engine, &req) else {
        return;
    };
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
    let value = if let Ok(n) = args.value_str.parse::<i64>() {
        json!(n)
    } else {
        json!(args.value_str)
    };
    let req = Request::CharactersAward {
        character: slug,
        award: args.award_id,
        value: Some(value),
        display_mode: mode,
    };
    let Some(c) = call_or_report::<CharacterData>(engine, &req) else {
        return;
    };
    display::print_character(&c);
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
    }
}

fn handle_characters_award_no_value(
    slug: &str,
    award_id: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) {
    let mode = display_mode.as_str();
    let req = Request::CharactersAward {
        character: slug,
        award: award_id,
        value: None,
        display_mode: mode,
    };
    let Some(c) = call_or_report::<CharacterData>(engine, &req) else {
        return;
    };
    display::print_character(&c);
    if let Some(xp) = c.awarded_xp {
        println!("Awarded {award_id}: +{xp} XP");
    }
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
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
    let req = Request::CharactersRandomResolve {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let Some(result) = call_or_report::<RandomResolveResult>(engine, &req) else {
        return;
    };
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

fn handle_characters_choices(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = Request::CharactersChoices {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let Some(r) = call_or_report::<ChoicesResponse>(engine, &req) else {
        return;
    };
    if r.pending_choices.is_empty() {
        println!("No pending choices.");
    } else {
        display::print_pending_choices(&r.pending_choices);
    }
}

pub(crate) fn build_resolve_choice_request<'a>(
    slug: &'a str,
    choice: &'a PendingChoice,
    resolution: &'a ChoiceResolution,
) -> Request<'a> {
    let (value, selection): (i64, &str) = match resolution {
        ChoiceResolution::Option(selection) => (0, selection),
        ChoiceResolution::Value { value, method } => (*value, method),
    };
    match (&choice.scope_type, &choice.scope_id) {
        (Some(scope_type), Some(scope_id)) => {
            Request::resolve_choice_scope(slug, (scope_type, scope_id), &choice.id, selection)
        }
        _ => Request::resolve_choice_progression(slug, &choice.id, value, selection),
    }
}

fn dispatch_resolve_choice(rest: &[&str], display_mode: DisplayMode, engine: &mut Engine) {
    match rest {
        // A bare `--help` here is already intercepted by
        // `table::dispatch_help` before dispatch reaches this match.
        [slug] => handle_characters_resolve_choice(slug, display_mode, engine),
        [slug, "--random-resolve"] => handle_characters_random_resolve(slug, display_mode, engine),
        _ => eprintln!("Unknown subcommand. Try `characters resolve_choice --help`."),
    }
}

fn handle_characters_resolve_choice(slug: &str, display_mode: DisplayMode, engine: &mut Engine) {
    let req = Request::CharactersChoices {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let Some(r) = call_or_report::<ChoicesResponse>(engine, &req) else {
        return;
    };
    let choices = r.pending_choices;

    let Some(choice) = select_pending_choice(&choices) else {
        return;
    };

    let Some(resolution) = prompt_choice_value(choice, engine) else {
        return;
    };

    let req = build_resolve_choice_request(slug, choice, &resolution);
    let Some(c) = call_or_report::<CharacterData>(engine, &req) else {
        return;
    };
    display::print_character(&c);
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
    }
}

pub(crate) fn select_pending_choice(choices: &[PendingChoice]) -> Option<&PendingChoice> {
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
    let idx = prompt_integer("Select choice (number):")?;
    match selection_index(idx, choices.len()) {
        Some(i) => Some(&choices[i]),
        None => {
            eprintln!("Invalid selection.");
            None
        }
    }
}

/// Maps 1-based user input onto a 0-based index, rejecting anything outside
/// `1..=len` (notably `0`, which `saturating_sub` used to alias to entry 1).
fn selection_index(input: i64, len: usize) -> Option<usize> {
    if input >= 1 && (input as usize) <= len {
        Some(input as usize - 1)
    } else {
        None
    }
}

fn handle_characters_spells(slug: &str, engine: &mut Engine) {
    let req = Request::CharactersSpells { character: slug };
    let Some(r) = call_or_report::<PreparationStateResponse>(engine, &req) else {
        return;
    };
    display::print_spells(&r);
}

fn handle_activate(verb: &str, slug: &str, items: &[&str], engine: &mut Engine) {
    let req = Request::CharactersActivate {
        character: slug,
        verb,
        items,
    };
    let Some(r) = call_or_report::<InventoryResponse>(engine, &req) else {
        return;
    };
    display::print_inventory(&r.inventory);
}

#[cfg(test)]
mod tests {
    use super::selection_index;

    #[test]
    fn selection_index_accepts_the_full_valid_range() {
        assert_eq!(selection_index(1, 3), Some(0));
        assert_eq!(selection_index(3, 3), Some(2));
    }

    #[test]
    fn selection_index_rejects_zero() {
        // 0 used to alias to entry 1 via saturating_sub
        assert_eq!(selection_index(0, 3), None);
    }

    #[test]
    fn selection_index_rejects_out_of_range_and_negative_input() {
        assert_eq!(selection_index(4, 3), None);
        assert_eq!(selection_index(-1, 3), None);
    }
}
