use serde_json::json;

use super::build::{ChoiceResolution, handle_characters_build, prompt_choice_value};
use super::inventory::handle_inventory;
use super::table::{self, COMMAND_TABLE};
use super::{
    CharacterAwardArgs, CmdResult, ConceptRollArgs, DisplayMode, Failed, call_or_report, fail,
    require_terminal,
};
use crate::display;
use crate::engine::Engine;
use crate::prompts::{can_prompt, prompt_integer, prompt_yes_no};
use crate::protocol::{
    CharacterData, CharacterSummary, CharactersList, ChoicesResponse, ConceptRollResult,
    CopiedCharacter, InventoryResponse, PendingChoice, PreparationStateResponse,
    RandomResolveResult, Request, SaveResult,
};

pub(crate) fn handle_characters(
    tokens: &[&str],
    session_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    let (tokens, display_mode) = strip_display_flags(tokens, session_mode);
    let tokens = tokens.as_slice();
    if table::dispatch_help(tokens, "characters") {
        return Ok(());
    }
    match tokens {
        ["list"] => handle_characters_list(None, engine),
        ["list", "--system", system] => handle_characters_list(Some(system), engine),
        ["gen", rest @ ..] => handle_characters_gen(parse_gen_args(rest)?, engine),
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
        ["copy", ..] => Err(fail(
            "Expected a character and an optional new slug. Try `characters copy --help`.",
        )),
        ["delete", slug] => handle_characters_delete(slug, engine),
        ["delete-all", rest @ ..] => {
            handle_characters_delete_all(engine, parse_delete_all_flags(rest)?)
        }
        ["choices", slug] => handle_characters_choices(slug, display_mode, engine),
        ["resolve_choice", rest @ ..] => dispatch_resolve_choice(rest, display_mode, engine),
        ["inventory", rest @ ..] => handle_inventory(rest, engine),
        ["spells", slug] => handle_characters_spells(slug, engine),
        ["prepare", slug, items @ ..] if !items.is_empty() => {
            handle_activate("prepare", slug, items, engine)
        }
        [] | ["--help"] => {
            print_characters_usage();
            Ok(())
        }
        [unknown, ..] => Err(fail(format!(
            "Unknown subcommand '{unknown}'. Try `characters --help`."
        ))),
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

fn parse_delete_all_flags<'a>(tokens: &[&'a str]) -> Result<DeleteAllArgs<'a>, Failed> {
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
                    None => return Err(fail("Error: --system requires a value")),
                }
            }
            unknown => {
                return Err(fail(format!(
                    "Unknown flag '{unknown}'. Try `characters delete-all --help`."
                )));
            }
        }
        i += 1;
    }
    Ok(DeleteAllArgs { yes, system })
}

#[derive(Debug, PartialEq)]
struct GenArgs<'a> {
    system: &'a str,
    save: bool,
}

/// `<system> [--save]`, flag in any position.
fn parse_gen_args<'a>(tokens: &[&'a str]) -> Result<GenArgs<'a>, Failed> {
    let mut save = false;
    let mut system = None;
    for &t in tokens {
        match t {
            "--save" => save = true,
            flag if flag.starts_with('-') => {
                return Err(fail(format!(
                    "Unknown flag '{flag}'. Try `characters gen --help`."
                )));
            }
            s if system.is_none() => system = Some(s),
            extra => {
                return Err(fail(format!(
                    "Unexpected argument '{extra}'. Try `characters gen --help`."
                )));
            }
        }
    }
    let system = system.ok_or_else(|| fail("Missing system. Try `characters gen --help`."))?;
    Ok(GenArgs { system, save })
}

/// With `--save` the character is saved without asking, so `gen` can run
/// where nobody can answer the prompt.
fn handle_characters_gen(args: GenArgs, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersGen {
        system: args.system,
    };
    let character = call_or_report::<CharacterData>(engine, &req)?;
    display::print_character(&character);
    // Without a `temp_id` there's nothing to save. That's only a failure
    // if saving was asked for: otherwise a script would see `--save`
    // succeed with nothing saved.
    let Some(temp_id) = &character.temp_id else {
        if args.save {
            return Err(fail("Error: the engine returned no character to save"));
        }
        return Ok(());
    };
    // Checked here, after generating, rather than up front: the character
    // is still shown, and nothing has been saved.
    if !args.save && !can_prompt() {
        return Err(fail(
            "Error: no terminal to ask \"Save this character?\"; pass --save to save it",
        ));
    }
    let save = args.save || prompt_yes_no("Save this character?").unwrap_or(false);
    if save {
        let save_req = Request::CharactersSave { temp_id };
        let saved = engine
            .call::<_, SaveResult>(&save_req)
            .map_err(|e| fail(format!("Error saving: {e}")))?;
        println!("Saved as '{}'.", saved.slug);
    }
    Ok(())
}

fn handle_characters_list(system: Option<&&str>, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersList {
        system: system.copied(),
    };
    let empty_msg = match system {
        Some(s) => format!(
            "No saved characters found for system `{s}`. Run `characters gen {s}` to create one."
        ),
        None => "No saved characters found. Run `characters gen <system>` to create one.".into(),
    };
    let r = call_or_report::<CharactersList>(engine, &req)?;
    display::print_characters_list(&r.characters, &empty_msg);
    Ok(())
}

fn confirm_delete_character(character: &CharacterSummary, yes: bool) -> Option<bool> {
    if yes {
        Some(true)
    } else {
        let question = format!("Delete \"{}\" ({})? [y/N]", character.name, character.slug);
        prompt_yes_no(&question)
    }
}

/// A failed delete doesn't stop the rest: each character is its own
/// delete, and the command fails at the end if any of them did.
fn handle_characters_delete_all(engine: &mut Engine, args: DeleteAllArgs) -> CmdResult {
    let req = Request::CharactersList {
        system: args.system,
    };
    let characters = call_or_report::<CharactersList>(engine, &req)?.characters;
    if characters.is_empty() {
        println!("No saved characters found.");
        return Ok(());
    }
    if !args.yes && !can_prompt() {
        return Err(fail(
            "Error: no terminal to confirm the deletes; pass -y to delete without asking",
        ));
    }
    let mut result = Ok(());
    for character in &characters {
        match confirm_delete_character(character, args.yes) {
            Some(true) => result = result.and(handle_characters_delete(&character.slug, engine)),
            Some(false) => println!("Skipped {}", character.slug),
            None => break,
        }
    }
    result
}

/// The engine picks the slug when none is given, names the copy, and
/// refuses a taken or malformed slug; the CLI repeats none of those rules.
fn handle_characters_copy(slug: &str, new_slug: Option<&str>, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersCopy {
        character: slug,
        slug: new_slug,
    };
    let r = call_or_report::<CopiedCharacter>(engine, &req)?;
    println!("Copied {} to {} (\"{}\")", r.copied, r.created, r.name);
    Ok(())
}

fn handle_characters_delete(slug: &str, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersDelete { character: slug };
    let r = call_or_report::<crate::protocol::DeletedCharacter>(engine, &req)?;
    println!("Deleted character: {}", r.deleted);
    Ok(())
}

fn handle_characters_show(slug: &str, display_mode: DisplayMode, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersShow {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let c = call_or_report::<CharacterData>(engine, &req)?;
    display::page_output(&display::format_character(&c));
    Ok(())
}

fn handle_characters_roll(slug: &str, args: ConceptRollArgs<'_>, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersRoll {
        character: slug,
        concept_type: args.concept_type,
        concept: args.concept_id,
    };
    let result = call_or_report::<ConceptRollResult>(engine, &req)?;
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
    Ok(())
}

fn handle_characters_award(
    slug: &str,
    args: CharacterAwardArgs<'_>,
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
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
    let c = call_or_report::<CharacterData>(engine, &req)?;
    display::print_character(&c);
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
    }
    Ok(())
}

fn handle_characters_award_no_value(
    slug: &str,
    award_id: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    let mode = display_mode.as_str();
    let req = Request::CharactersAward {
        character: slug,
        award: award_id,
        value: None,
        display_mode: mode,
    };
    let c = call_or_report::<CharacterData>(engine, &req)?;
    display::print_character(&c);
    if let Some(xp) = c.awarded_xp {
        println!("Awarded {award_id}: +{xp} XP");
    }
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
    }
    Ok(())
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

fn handle_characters_random_resolve(
    slug: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    let req = Request::CharactersRandomResolve {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let result = call_or_report::<RandomResolveResult>(engine, &req)?;
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
    Ok(())
}

fn handle_characters_choices(
    slug: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    let req = Request::CharactersChoices {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let r = call_or_report::<ChoicesResponse>(engine, &req)?;
    if r.pending_choices.is_empty() {
        println!("No pending choices.");
    } else {
        display::print_pending_choices(&r.pending_choices);
    }
    Ok(())
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

fn dispatch_resolve_choice(
    rest: &[&str],
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    match rest {
        // A bare `--help` here is already intercepted by
        // `table::dispatch_help` before dispatch reaches this match.
        [slug] => handle_characters_resolve_choice(slug, display_mode, engine),
        [slug, "--random-resolve"] => handle_characters_random_resolve(slug, display_mode, engine),
        _ => Err(fail(
            "Unknown subcommand. Try `characters resolve_choice --help`.",
        )),
    }
}

fn handle_characters_resolve_choice(
    slug: &str,
    display_mode: DisplayMode,
    engine: &mut Engine,
) -> CmdResult {
    let req = Request::CharactersChoices {
        character: slug,
        display_mode: display_mode.as_str(),
    };
    let choices = call_or_report::<ChoicesResponse>(engine, &req)?.pending_choices;
    // Every pending choice is resolved by asking, so a terminal is needed
    // exactly when there's at least one. Checked after the (read-only)
    // fetch, so "nothing to resolve" still succeeds without one.
    if !choices.is_empty() {
        require_terminal(
            "characters resolve_choice",
            "; pass --random-resolve to resolve its choices randomly",
        )?;
    }

    let Some(choice) = select_pending_choice(&choices)? else {
        return Ok(());
    };

    let Some(resolution) = prompt_choice_value(choice, engine)? else {
        return Ok(());
    };

    let req = build_resolve_choice_request(slug, choice, &resolution);
    let c = call_or_report::<CharacterData>(engine, &req)?;
    display::print_character(&c);
    if !c.pending_choices.is_empty() {
        display::print_pending_choices(&c.pending_choices);
    }
    Ok(())
}

/// `Ok(None)` when there's nothing to choose (no pending choices) or input
/// ended at the prompt; an out-of-range selection is a failure.
pub(crate) fn select_pending_choice(
    choices: &[PendingChoice],
) -> Result<Option<&PendingChoice>, Failed> {
    if choices.is_empty() {
        println!("No pending choices to resolve.");
        return Ok(None);
    }
    if choices.len() == 1 {
        return Ok(Some(&choices[0]));
    }
    println!("Pending choices:");
    for (i, c) in choices.iter().enumerate() {
        println!("  {}: {}", i + 1, c.name);
    }
    let Some(idx) = prompt_integer("Select choice (number):") else {
        return Ok(None);
    };
    match selection_index(idx, choices.len()) {
        Some(i) => Ok(Some(&choices[i])),
        None => Err(fail("Invalid selection.")),
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

fn handle_characters_spells(slug: &str, engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersSpells { character: slug };
    let r = call_or_report::<PreparationStateResponse>(engine, &req)?;
    display::print_spells(&r);
    Ok(())
}

fn handle_activate(verb: &str, slug: &str, items: &[&str], engine: &mut Engine) -> CmdResult {
    let req = Request::CharactersActivate {
        character: slug,
        verb,
        items,
    };
    let r = call_or_report::<InventoryResponse>(engine, &req)?;
    display::print_inventory(&r.inventory);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{GenArgs, parse_gen_args, selection_index};

    #[test]
    fn gen_takes_a_system_and_an_optional_save_flag_in_any_position() {
        assert_eq!(
            parse_gen_args(&["dnd_5e_srd"]),
            Ok(GenArgs {
                system: "dnd_5e_srd",
                save: false
            })
        );
        for tokens in [&["dnd_5e_srd", "--save"][..], &["--save", "dnd_5e_srd"][..]] {
            assert_eq!(
                parse_gen_args(tokens),
                Ok(GenArgs {
                    system: "dnd_5e_srd",
                    save: true
                })
            );
        }
    }

    #[test]
    fn gen_rejects_a_missing_system_unknown_flags_and_extra_arguments() {
        assert!(parse_gen_args(&[]).is_err());
        assert!(parse_gen_args(&["--save"]).is_err());
        assert!(parse_gen_args(&["dnd_5e_srd", "--force"]).is_err());
        assert!(parse_gen_args(&["dnd_5e_srd", "other"]).is_err());
    }

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
