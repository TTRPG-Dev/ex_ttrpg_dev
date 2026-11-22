use super::call_or_report;
use crate::display;
use crate::engine::Engine;
use crate::protocol::{ConceptsList, Request, SystemInfo, SystemsList};

pub(crate) fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list", "--help"] => println!("Usage: systems list"),
        ["show", "--help"] => {
            println!("Usage: systems show <slug> [--concept-type <type>]")
        }
        ["list"] => {
            let req = Request::SystemsList;
            let Some(result) = call_or_report::<SystemsList>(engine, &req) else {
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
        ["show", slug] => {
            let req = Request::SystemsShow {
                system: slug,
                concept_type: None,
                concept_id: None,
            };
            let Some(info) = call_or_report::<SystemInfo>(engine, &req) else {
                return;
            };
            display::print_system_info(info);
        }
        ["show", slug, "--concept-type", ct] => {
            let req = Request::SystemsShow {
                system: slug,
                concept_type: Some(ct),
                concept_id: None,
            };
            let Some(cl) = call_or_report::<ConceptsList>(engine, &req) else {
                return;
            };
            display::print_concepts_list(&cl);
        }
        [] | ["--help"] => {
            println!("Usage: systems list | systems show <slug> [--concept-type <type>]")
        }
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `systems --help`."),
    }
}
