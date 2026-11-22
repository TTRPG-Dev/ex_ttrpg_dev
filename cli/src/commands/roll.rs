use serde_json::json;

use super::call_or_report;
use crate::engine::Engine;
use crate::protocol::RollResult;

pub(crate) fn handle_roll(dice: &str, engine: &mut Engine) {
    let req = json!({"command": "roll", "dice": dice});
    let Some(result) = call_or_report::<RollResult>(engine, &req) else {
        return;
    };
    for r in &result.results {
        let rolls_str: Vec<String> = r.rolls.iter().map(|n| n.to_string()).collect();
        println!("{}: [{}] = {}", r.spec, rolls_str.join(", "), r.total);
    }
}
