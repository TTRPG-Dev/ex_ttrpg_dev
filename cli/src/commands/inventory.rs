use serde_json::json;

use crate::display;
use crate::engine::Engine;
use crate::protocol::InventoryResponse;

pub(crate) fn handle_inventory(tokens: &[&str], engine: &mut Engine) {
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
