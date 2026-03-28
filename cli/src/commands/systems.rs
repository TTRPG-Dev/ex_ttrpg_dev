use serde_json::json;

use crate::display;
use crate::engine::Engine;
use crate::protocol::{ConceptsList, SystemInfo, SystemsList};

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
