use super::call_or_report;
use super::table;
use crate::display;
use crate::engine::Engine;
use crate::protocol::{ConceptsList, Request, SystemInfo, SystemsList};

pub(crate) fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    if table::dispatch_help(tokens, "systems") {
        return;
    }
    match tokens {
        ["list"] => handle_systems_list(engine),
        ["show", slug] => handle_systems_show(slug, None, engine),
        ["show", slug, "--concept-type", ct] => handle_systems_show(slug, Some(ct), engine),
        [] | ["--help"] => {
            println!("Usage: systems list | systems show <slug> [--concept-type <type>]")
        }
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `systems --help`."),
    }
}

fn handle_systems_list(engine: &mut Engine) {
    let Some(result) = call_or_report::<SystemsList>(engine, &Request::SystemsList) else {
        return;
    };
    if result.systems.is_empty() {
        println!("No configured systems found.");
    } else {
        println!("Configured Systems:");
        for s in &result.systems {
            println!("  - {s}");
        }
    }
}

/// Without a concept type, shows the system itself; with one, lists that
/// type's concepts. The two responses have different shapes.
fn handle_systems_show(slug: &str, concept_type: Option<&str>, engine: &mut Engine) {
    let req = Request::SystemsShow {
        system: slug,
        concept_type,
        concept_id: None,
    };
    match concept_type {
        None => {
            if let Some(info) = call_or_report::<SystemInfo>(engine, &req) {
                display::print_system_info(info);
            }
        }
        Some(_) => {
            if let Some(cl) = call_or_report::<ConceptsList>(engine, &req) {
                display::print_concepts_list(&cl);
            }
        }
    }
}
