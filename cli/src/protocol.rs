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
pub(crate) struct DeletedCharacter {
    pub(crate) deleted: String,
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
    pub(crate) character_lists: Vec<CharacterListCategory>,
    pub(crate) concept_types: Vec<ConceptTypeValues>,
    #[serde(default)]
    pub(crate) selected_concepts: Vec<SelectedConcept>,
    pub(crate) pending_choices: Option<Vec<PendingChoice>>,
    #[serde(default)]
    pub(crate) awarded_xp: Option<i64>,
}

#[derive(Deserialize)]
pub(crate) struct SelectedConcept {
    pub(crate) progression: String,
    #[allow(dead_code)]
    pub(crate) id: String,
    pub(crate) label: String,
}

#[derive(Deserialize, Clone)]
pub(crate) struct OptionEntry {
    pub(crate) id: String,
    pub(crate) label: String,
}

#[derive(Deserialize, Clone)]
pub(crate) struct PendingChoice {
    #[serde(rename = "type")]
    pub(crate) choice_type: String,
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) count: Option<i64>,
    pub(crate) roll: Option<String>,
    pub(crate) options: Option<Vec<OptionEntry>>,
    pub(crate) earned_at_level: Option<i64>,
    pub(crate) scope_type: Option<String>,
    pub(crate) scope_id: Option<String>,
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
pub(crate) struct CharacterListCategory {
    pub(crate) label: String,
    pub(crate) items: Vec<String>,
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

#[derive(Deserialize)]
pub(crate) struct RandomResolveResult {
    pub(crate) name: String,
    pub(crate) character_lists: Vec<CharacterListCategory>,
    pub(crate) resolutions: Vec<ResolutionEntry>,
}

#[derive(Deserialize)]
pub(crate) struct ResolutionEntry {
    pub(crate) name: String,
    pub(crate) selection_id: Option<String>,
    pub(crate) selection_name: Option<String>,
    pub(crate) rolled_value: Option<i64>,
    pub(crate) method: Option<String>,
    pub(crate) earned_at_level: Option<i64>,
}

#[derive(Deserialize)]
pub(crate) struct BuildStartResult {
    pub(crate) temp_id: String,
    pub(crate) building_choices: Vec<BuildingChoiceGroup>,
}

#[derive(Deserialize)]
pub(crate) struct BuildingChoiceGroup {
    pub(crate) concept_type: String,
    pub(crate) name: String,
    pub(crate) concepts: Vec<OptionEntry>,
}

#[derive(Deserialize)]
pub(crate) struct BuildSubChoiceResult {
    pub(crate) sub_choices: Vec<PendingChoice>,
}

#[derive(Deserialize)]
pub(crate) struct ConceptDetail {
    pub(crate) concept_type: String,
    pub(crate) fields: serde_json::Value,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_roll_result_structure() {
        let json = r#"{"results":[{"spec":"2d6","rolls":[3,4],"total":7}]}"#;
        let r: RollResult = serde_json::from_str(json).unwrap();
        assert_eq!(r.results.len(), 1);
        assert_eq!(r.results[0].spec, "2d6");
    }

    #[test]
    fn deserialize_roll_result_values() {
        let json = r#"{"results":[{"spec":"2d6","rolls":[3,4],"total":7}]}"#;
        let r: RollResult = serde_json::from_str(json).unwrap();
        assert_eq!(r.results[0].rolls, vec![3, 4]);
        assert_eq!(r.results[0].total, 7);
    }

    #[test]
    fn deserialize_systems_list() {
        let json = r#"{"systems":["dnd_5e_srd","pathfinder"]}"#;
        let s: SystemsList = serde_json::from_str(json).unwrap();
        assert_eq!(s.systems, vec!["dnd_5e_srd", "pathfinder"]);
    }

    #[test]
    fn deserialize_character_data_minimal() {
        let json = r#"{
            "name": "Aria",
            "rule_system": "dnd_5e_srd",
            "choices": [],
            "character_lists": [],
            "concept_types": []
        }"#;
        let c: CharacterData = serde_json::from_str(json).unwrap();
        assert_eq!(c.name, "Aria");
        assert_eq!(c.rule_system, "dnd_5e_srd");
        assert!(c.slug.is_none());
        assert!(c.temp_id.is_none());
        assert!(c.pending_choices.is_none());
    }

    #[test]
    fn deserialize_character_data_with_optionals() {
        let json = r#"{
            "temp_id": "abc123",
            "slug": "aria-1",
            "name": "Aria",
            "rule_system": "dnd_5e_srd",
            "choices": [{"type_name":"Race","value":"Elf"}],
            "character_lists": [{"label":"Skill Proficiencies","items":["Stealth"]},{"label":"Languages","items":["Common"]}],
            "concept_types": [],
            "pending_choices": [{"type":"pending","id":"hp_1","name":"Level 1 HP","count":1,"roll":"d8","options":[{"id":"fire_bolt","label":"Fire Bolt: Level 0, evocation (VS)"}]}]
        }"#;
        let c: CharacterData = serde_json::from_str(json).unwrap();
        assert_eq!(c.slug.as_deref(), Some("aria-1"));
        assert_eq!(c.choices[0].type_name, "Race");
        assert_eq!(c.character_lists[0].label, "Skill Proficiencies");
        assert_eq!(c.character_lists[0].items, vec!["Stealth"]);
        let pending = c.pending_choices.unwrap();
        assert_eq!(pending[0].id, "hp_1");
        assert_eq!(pending[0].roll.as_deref(), Some("d8"));
        assert_eq!(pending[0].count, Some(1));
    }

    #[test]
    fn deserialize_pending_choice_type_rename() {
        // The `type` JSON field maps to `choice_type` via serde rename
        let json = r#"{"type":"available","id":"feat_1","name":"Feat Choice"}"#;
        let p: PendingChoice = serde_json::from_str(json).unwrap();
        assert_eq!(p.choice_type, "available");
        assert_eq!(p.id, "feat_1");
        assert!(p.count.is_none());
        assert!(p.roll.is_none());
    }

    #[test]
    fn deserialize_selected_concept() {
        let json = r#"{"progression":"Spells Known","id":"fire_bolt","label":"Fire Bolt: Level 0, evocation (VS)"}"#;
        let s: SelectedConcept = serde_json::from_str(json).unwrap();
        assert_eq!(s.progression, "Spells Known");
        assert_eq!(s.id, "fire_bolt");
        assert_eq!(s.label, "Fire Bolt: Level 0, evocation (VS)");
    }

    #[test]
    fn deserialize_inventory_response() {
        let json = r#"{"inventory":[{"index":0,"concept_type":"weapon","concept_id":"shortsword","fields":{"equipped":true}}]}"#;
        let r: InventoryResponse = serde_json::from_str(json).unwrap();
        assert_eq!(r.inventory.len(), 1);
        assert_eq!(r.inventory[0].concept_id, "shortsword");
        assert_eq!(r.inventory[0].fields["equipped"], true);
    }
}
