//! The interactive `characters build` wizard: walking the user through a
//! system's building choices, their sub-choices, and the level-1 progression
//! choices (e.g. rolling or averaging hit points) that follow.

use super::characters::{build_resolve_choice_request, select_pending_choice};
use super::{CmdResult, Failed, call_or_report, fail, require_terminal};
use crate::display;
use crate::engine::Engine;
use crate::prompts::{
    EntryAction, prompt_from_option_entries, prompt_from_option_entries_or_detail, prompt_integer,
    prompt_nonempty_string, prompt_yes_no,
};
use crate::protocol::{
    BuildStartResult, BuildSubChoiceResult, BuildingChoiceGroup, CharacterData, ConceptDetail,
    OptionEntry, PendingChoice, Request, RollResult,
};

/// How a pending choice was resolved: by picking from its `options`, or by
/// arriving at a numeric value (manual entry, a die roll, or taking the
/// average) along with the method name the engine records.
pub(crate) enum ChoiceResolution {
    Option(String),
    Value { value: i64, method: String },
}

/// Ending input at any prompt cancels the build without it being a
/// failure, as declining a prompt is elsewhere; an engine error fails it.
pub(crate) fn handle_characters_build(system: &str, engine: &mut Engine) -> CmdResult {
    require_terminal("characters build", "")?;
    let Some(name) = prompt_nonempty_string("Character name:") else {
        return Ok(());
    };
    let req = Request::CharactersBuildStart {
        system,
        name: &name,
    };
    let build_start = call_or_report::<BuildStartResult>(engine, &req)?;
    let temp_id = build_start.temp_id;
    if !resolve_building_choices(&temp_id, &build_start.building_choices, system, engine)? {
        return Ok(());
    }
    let finish_req = Request::CharactersBuildFinish { temp_id: &temp_id };
    let character = call_or_report::<CharacterData>(engine, &finish_req)?;
    let slug = character
        .slug
        .clone()
        .ok_or_else(|| fail("Error: build_finish did not return a slug"))?;
    let Some(final_char) = resolve_build_progressions(&slug, character, engine)? else {
        return Ok(());
    };
    display::print_character(&final_char);
    Ok(())
}

/// `Ok(false)` if input ended at a prompt, cancelling the build.
fn resolve_building_choices(
    temp_id: &str,
    groups: &[BuildingChoiceGroup],
    system: &str,
    engine: &mut Engine,
) -> Result<bool, Failed> {
    for group in groups {
        let concept_id = loop {
            match prompt_from_option_entries_or_detail(&group.name, &group.concepts) {
                None => return Ok(false),
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
        let req = Request::CharactersBuildSelect {
            temp_id,
            concept_type: &group.concept_type,
            concept_id: &concept_id,
        };
        let r = call_or_report::<BuildSubChoiceResult>(engine, &req)?;
        if !resolve_sub_choices(temp_id, r.sub_choices, engine)? {
            return Ok(false);
        }
    }
    Ok(true)
}

fn show_concept_detail(system: &str, concept_type: &str, concept_id: &str, engine: &mut Engine) {
    let req = Request::SystemsShow {
        system,
        concept_type: Some(concept_type),
        concept_id: Some(concept_id),
    };
    match engine.call::<_, ConceptDetail>(&req) {
        Ok(detail) => println!("\n{}\n", display::format_concept_detail(&detail)),
        Err(e) => eprintln!("Could not load details: {e}"),
    }
}

/// `Ok(false)` if input ended at a prompt, cancelling the build.
fn resolve_sub_choices(
    temp_id: &str,
    mut sub_choices: Vec<PendingChoice>,
    engine: &mut Engine,
) -> Result<bool, Failed> {
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
            return Ok(false);
        };
        let req = Request::CharactersBuildResolveSub {
            temp_id,
            scope_type: &scope_type,
            scope_id: &scope_id,
            choice: &choice_id,
            selection: &selection,
        };
        let r = call_or_report::<BuildSubChoiceResult>(engine, &req)?;
        sub_choices = r.sub_choices;
    }
    Ok(true)
}

/// `Ok(None)` if input ended at a prompt, cancelling the build.
fn resolve_build_progressions(
    slug: &str,
    mut character: CharacterData,
    engine: &mut Engine,
) -> Result<Option<CharacterData>, Failed> {
    loop {
        if character.pending_choices.is_empty() {
            return Ok(Some(character));
        }
        let pending = character.pending_choices.clone();
        let Some(choice) = select_pending_choice(&pending)?.cloned() else {
            return Ok(None);
        };
        let Some(resolution) = prompt_choice_value(&choice, engine)? else {
            return Ok(None);
        };
        let req = build_resolve_choice_request(slug, &choice, &resolution);
        character = call_or_report::<CharacterData>(engine, &req)?;
    }
}

/// Resolves a single pending choice to a [`ChoiceResolution`]: a selected
/// option, a manually-entered value, or a hit-die roll/average. `Ok(None)`
/// if input ended at a prompt.
pub(crate) fn prompt_choice_value(
    choice: &PendingChoice,
    engine: &mut Engine,
) -> Result<Option<ChoiceResolution>, Failed> {
    if let Some(options) = &choice.options {
        let selection = prompt_from_option_entries(&choice.name, options);
        return Ok(selection.map(ChoiceResolution::Option));
    }

    let Some(die) = &choice.roll else {
        let value = prompt_integer(&format!("Value for {}:", choice.name));
        return Ok(value.map(|value| ChoiceResolution::Value {
            value,
            method: "manual".to_string(),
        }));
    };

    let Some(sides) = die.strip_prefix('d').and_then(|s| s.parse::<i64>().ok()) else {
        return Err(fail(format!(
            "Error: malformed die spec '{die}' for choice '{}'.",
            choice.name
        )));
    };
    let average = sides / 2 + 1;
    println!("\nResolving: {} ({})", choice.name, die);
    println!("Average HP (no roll): {average}");

    let Some(roll) = prompt_yes_no(&format!(
        "Roll {die} for HP? (no = take average of {average})"
    )) else {
        return Ok(None);
    };
    if !roll {
        return Ok(Some(ChoiceResolution::Value {
            value: average,
            method: "average".to_string(),
        }));
    }

    let dice = format!("1{die}");
    let roll_req = Request::Roll { dice: &dice };
    let result = engine
        .call::<_, RollResult>(&roll_req)
        .map_err(|e| fail(format!("Error rolling: {e}")))?;
    let first = result
        .results
        .first()
        .ok_or_else(|| fail("Error rolling: engine returned no results."))?;
    let rolled = first.total;
    println!("Rolled: {rolled}");
    Ok(Some(ChoiceResolution::Value {
        value: rolled,
        method: "rolled".to_string(),
    }))
}
