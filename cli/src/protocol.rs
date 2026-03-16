//! Protocol types for the JSON RPC protocol with the Elixir engine.
//!
//! Each struct models a response payload from the engine. They are
//! deserialized by `Engine::call` and passed to display or command handlers.

use serde::Deserialize;

#[derive(Deserialize)]
pub(crate) struct SystemsList {
    pub(crate) systems: Vec<String>,
}

#[derive(Deserialize)]
pub(crate) struct SystemInfo {
    pub(crate) name: String,
    pub(crate) slug: String,
    pub(crate) version: String,
    pub(crate) publisher: Option<String>,
    pub(crate) family: Option<String>,
    pub(crate) series: Option<String>,
    pub(crate) concept_types: Option<Vec<ConceptTypeSummary>>,
}

#[derive(Deserialize)]
pub(crate) struct ConceptTypeSummary {
    pub(crate) id: String,
    pub(crate) name: String,
}

#[derive(Deserialize)]
pub(crate) struct ConceptsList {
    pub(crate) concept_type: String,
    pub(crate) concepts: Vec<ConceptSummary>,
}

#[derive(Deserialize)]
pub(crate) struct ConceptSummary {
    pub(crate) id: String,
    pub(crate) name: String,
}

#[derive(Deserialize)]
pub(crate) struct RollResult {
    pub(crate) results: Vec<DiceResult>,
}

#[derive(Deserialize)]
pub(crate) struct DiceResult {
    pub(crate) spec: String,
    pub(crate) rolls: Vec<i64>,
    pub(crate) total: i64,
}

#[derive(Deserialize)]
pub(crate) struct CharactersList {
    pub(crate) characters: Vec<CharacterSummary>,
}

#[derive(Deserialize)]
pub(crate) struct CharacterSummary {
    pub(crate) slug: String,
    pub(crate) name: String,
    pub(crate) rule_system: String,
}

#[derive(Deserialize)]
pub(crate) struct CharacterData {
    pub(crate) temp_id: Option<String>,
    pub(crate) slug: Option<String>,
    pub(crate) name: String,
    pub(crate) rule_system: String,
    pub(crate) choices: Vec<ChoiceEntry>,
    pub(crate) proficiencies: Proficiencies,
    pub(crate) concept_types: Vec<ConceptTypeValues>,
    pub(crate) pending_choices: Option<Vec<PendingChoice>>,
}

#[derive(Deserialize)]
pub(crate) struct PendingChoice {
    #[serde(rename = "type")]
    pub(crate) choice_type: String,
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) count: Option<i64>,
    pub(crate) roll: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct ChoicesResponse {
    pub(crate) pending_choices: Vec<PendingChoice>,
}

#[derive(Deserialize)]
pub(crate) struct ChoiceEntry {
    pub(crate) type_name: String,
    pub(crate) value: String,
}

#[derive(Deserialize)]
pub(crate) struct Proficiencies {
    pub(crate) skills: Vec<String>,
    pub(crate) languages: Vec<String>,
    pub(crate) weapons: Vec<String>,
    pub(crate) armor: Vec<String>,
    pub(crate) tools: Vec<String>,
}

#[derive(Deserialize)]
pub(crate) struct ConceptTypeValues {
    pub(crate) name: String,
    pub(crate) concepts: Vec<ConceptValues>,
}

#[derive(Deserialize)]
pub(crate) struct ConceptValues {
    pub(crate) name: String,
    pub(crate) fields: Vec<FieldValue>,
}

#[derive(Deserialize)]
pub(crate) struct FieldValue {
    pub(crate) name: String,
    pub(crate) value: String,
}

#[derive(Deserialize)]
pub(crate) struct SaveResult {
    pub(crate) slug: String,
}

#[derive(Deserialize)]
pub(crate) struct InventoryResponse {
    pub(crate) inventory: Vec<InventoryItemData>,
}

#[derive(Deserialize)]
pub(crate) struct InventoryItemData {
    pub(crate) index: usize,
    pub(crate) concept_type: String,
    pub(crate) concept_id: String,
    pub(crate) fields: serde_json::Value,
}

#[derive(Deserialize)]
pub(crate) struct ConceptRollResult {
    pub(crate) concept_name: String,
    pub(crate) dice: String,
    pub(crate) rolls: Vec<i64>,
    pub(crate) bonus: i64,
    pub(crate) total: i64,
}
