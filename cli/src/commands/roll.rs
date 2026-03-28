use serde_json::json;

use crate::engine::Engine;
use crate::protocol::RollResult;

pub(crate) fn handle_roll(dice: &str, engine: &mut Engine) {
    match engine.call::<_, RollResult>(&json!({"command": "roll", "dice": dice})) {
        Ok(result) => {
            for r in &result.results {
                let rolls_str: Vec<String> = r.rolls.iter().map(|n| n.to_string()).collect();
                println!("{}: [{}] = {}", r.spec, rolls_str.join(", "), r.total);
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}
