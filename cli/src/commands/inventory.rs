use serde_json::json;

use super::{CmdResult, call_or_report, fail};
use crate::display;
use crate::engine::Engine;
use crate::protocol::{InventoryResponse, Request};

pub(crate) fn handle_inventory(tokens: &[&str], engine: &mut Engine) -> CmdResult {
    // A trailing `--help` here is already intercepted by
    // `table::dispatch_help(tokens, "characters")` before dispatch reaches
    // `handle_characters`'s `["inventory", rest @ ..]` arm.
    match tokens {
        [slug] => {
            let req = Request::CharactersInventory { character: slug };
            call_inventory(&req, engine)
        }
        ["add", slug, type_id, id] => call_inventory(
            &Request::CharactersInventoryAdd {
                character: slug,
                item_type: type_id,
                id,
                fields: json!({}),
            },
            engine,
        ),
        ["add", slug, type_id, id, "--equipped"] => call_inventory(
            &Request::CharactersInventoryAdd {
                character: slug,
                item_type: type_id,
                id,
                fields: json!({"equipped": true}),
            },
            engine,
        ),
        ["set", slug, index_str, field, value_str] => {
            let index = index_str
                .parse::<u64>()
                .map_err(|_| fail("Error: index must be a non-negative integer"))?;
            let value: serde_json::Value = match *value_str {
                "true" => json!(true),
                "false" => json!(false),
                s => s.parse::<f64>().map_or_else(|_| json!(s), |n| json!(n)),
            };
            call_inventory(
                &Request::CharactersInventorySet {
                    character: slug,
                    index,
                    field,
                    value,
                },
                engine,
            )
        }
        _ => Err(fail(
            "Usage: characters inventory <slug>\n\
             \x20       characters inventory add <slug> <type> <id> [--equipped]\n\
             \x20       characters inventory set <slug> <index> <field> <value>",
        )),
    }
}

fn call_inventory(req: &Request<'_>, engine: &mut Engine) -> CmdResult {
    let r = call_or_report::<InventoryResponse>(engine, req)?;
    display::print_inventory(&r.inventory);
    Ok(())
}
