//! The interactive `characters build` wizard: walking the user through a
//! system's building choices, their sub-choices, and the level-1 progression
//! choices (e.g. rolling or averaging hit points) that follow.

use super::call_or_report;
use super::characters::{build_resolve_choice_request, select_pending_choice};
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

pub(crate) fn handle_characters_build(system: &str, engine: &mut Engine) {
    let Some(name) = prompt_nonempty_string("Character name:") else {
        return;
    };
    let req = Request::CharactersBuildStart {
        system,
        name: &name,
    };
    let Some(build_start) = call_or_report::<BuildStartResult>(engine, &req) else {
        return;
    };
    let temp_id = build_start.temp_id;
    if !resolve_building_choices(&temp_id, &build_start.building_choices, system, engine) {
        return;
    }
    let finish_req = Request::CharactersBuildFinish { temp_id: &temp_id };
    let Some(character) = call_or_report::<CharacterData>(engine, &finish_req) else {
        return;
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

fn resolve_building_choices(
    temp_id: &str,
    groups: &[BuildingChoiceGroup],
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
        let req = Request::CharactersBuildSelect {
            temp_id,
            concept_type: &group.concept_type,
            concept_id: &concept_id,
        };
        let Some(r) = call_or_report::<BuildSubChoiceResult>(engine, &req) else {
            return false;
        };
        if !resolve_sub_choices(temp_id, r.sub_choices, engine) {
            return false;
        }
    }
    true
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
        let req = Request::CharactersBuildResolveSub {
            temp_id,
            scope_type: &scope_type,
            scope_id: &scope_id,
            choice: &choice_id,
            selection: &selection,
        };
        let Some(r) = call_or_report::<BuildSubChoiceResult>(engine, &req) else {
            return false;
        };
        sub_choices = r.sub_choices;
    }
    true
}

fn resolve_build_progressions(
    slug: &str,
    mut character: CharacterData,
    engine: &mut Engine,
) -> Option<CharacterData> {
    loop {
        if character.pending_choices.is_empty() {
            return Some(character);
        }
        let pending = character.pending_choices.clone();
        let choice = select_pending_choice(&pending)?.clone();
        let (value, selection) = prompt_choice_value(&choice, engine)?;
        let req = build_resolve_choice_request(slug, &choice, value, &selection);
        character = call_or_report::<CharacterData>(engine, &req)?;
    }
}

pub(crate) fn prompt_choice_value(
    choice: &PendingChoice,
    engine: &mut Engine,
) -> Option<(i64, String)> {
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

    let dice = format!("1{die}");
    let roll_req = Request::Roll { dice: &dice };
    match engine.call::<_, RollResult>(&roll_req) {
        Ok(result) => match result.results.first() {
            Some(first) => {
                let rolled = first.total;
                println!("Rolled: {rolled}");
                Some((rolled, "rolled".to_string()))
            }
            None => {
                eprintln!("Error rolling: engine returned no results.");
                None
            }
        },
        Err(e) => {
            eprintln!("Error rolling: {e}");
            None
        }
    }
}
