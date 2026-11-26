//! Protocol types for the JSON RPC protocol with the Elixir engine.
//!
//! Response types are deserialized by `Engine::call` and passed to display
//! or command handlers. `Request` models every outbound command; command
//! handlers build a variant instead of hand-rolling a `json!({"command": ...})`
//! literal, so each command name and its field names live in this one file.

use serde::{Deserialize, Serialize};

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
pub(crate) struct CreatedSystem {
    pub(crate) created: String,
    /// The version stored, possibly the library's default; `None` if the
    /// engine couldn't read it back.
    pub(crate) version: Option<String>,
    pub(crate) path: String,
}

#[derive(Deserialize)]
pub(crate) struct CopiedSystem {
    pub(crate) copied: String,
    pub(crate) created: String,
    pub(crate) name: String,
    pub(crate) path: String,
}

#[derive(Deserialize)]
pub(crate) struct AddedConceptType {
    pub(crate) added: String,
    pub(crate) path: String,
}

#[derive(Deserialize)]
pub(crate) struct DeletedSystem {
    pub(crate) deleted: String,
    pub(crate) path: String,
}

#[derive(Deserialize)]
pub(crate) struct CopiedCharacter {
    pub(crate) copied: String,
    pub(crate) created: String,
    pub(crate) name: String,
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
    #[serde(default)]
    pub(crate) choices: Vec<ChoiceEntry>,
    #[serde(default)]
    pub(crate) character_lists: Vec<CharacterListCategory>,
    #[serde(default)]
    pub(crate) concept_types: Vec<ConceptTypeValues>,
    #[serde(default)]
    pub(crate) selected_concepts: Vec<SelectedConcept>,
    #[serde(default)]
    pub(crate) pending_choices: Vec<PendingChoice>,
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
    pub(crate) fields: ConceptFields,
}

/// Concept metadata as rendered by `show_concept_detail` — the fields a
/// `race`/`class`/`background` concept may define in its TOML entry (see
/// `ConceptDetail`'s `fields`). Not every concept type sets every field;
/// absent ones deserialize to `None`/empty.
#[derive(Deserialize)]
pub(crate) struct ConceptFields {
    pub(crate) name: Option<String>,
    pub(crate) hit_die: Option<String>,
    #[serde(default)]
    pub(crate) armor_proficiencies: Vec<String>,
    #[serde(default)]
    pub(crate) weapon_proficiencies: Vec<String>,
    #[serde(default)]
    pub(crate) languages: Vec<String>,
    #[serde(default)]
    pub(crate) damage_resistances: Vec<String>,
    #[serde(default)]
    pub(crate) contributes: Vec<ContributeEntry>,
    #[serde(default)]
    pub(crate) choices: std::collections::BTreeMap<String, RequiredChoice>,
}

#[derive(Deserialize)]
pub(crate) struct ContributeEntry {
    pub(crate) target: String,
    pub(crate) value: serde_json::Value,
    pub(crate) when: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct RequiredChoice {
    pub(crate) name: Option<String>,
    #[serde(default)]
    pub(crate) required: bool,
    #[serde(rename = "type")]
    pub(crate) choice_type: Option<String>,
    pub(crate) count: Option<u64>,
    #[serde(default)]
    pub(crate) options: Vec<String>,
}

#[derive(Deserialize)]
pub(crate) struct PreparationStateResponse {
    pub(crate) preparation_mode: Option<String>,
    pub(crate) cap: Option<i64>,
    #[serde(default)]
    pub(crate) eligible_items: Vec<String>,
    #[serde(default)]
    pub(crate) prepared_items: Vec<String>,
    #[serde(default)]
    pub(crate) always_active: Vec<String>,
}

// ── Requests ───────────────────────────────────────────────────────────────
//
// One `Request` variant per command the engine's dispatcher understands (see
// `apps/ttrpg_dev_cli/lib/cli/server.ex`), tagged by the `command` field via
// `#[serde(rename = ...)]`. Each command name string appears exactly once,
// on its variant.
//
// `characters.resolve_choice` has two argument shapes depending on whether
// the choice is scope-based (a feat/sub-choice) or progression-based (a
// leveling slot); both are modeled by one variant with the irrelevant fields
// skipped, built through the `resolve_choice_scope`/`resolve_choice_progression`
// constructors rather than two tags sharing the same rename string.
#[derive(Serialize)]
#[serde(tag = "command")]
pub(crate) enum Request<'a> {
    #[serde(rename = "roll")]
    Roll { dice: &'a str },

    #[serde(rename = "systems.list")]
    SystemsList,

    #[serde(rename = "systems.show")]
    SystemsShow {
        system: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        concept_type: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        concept_id: Option<&'a str>,
    },

    /// Optional fields left out are given library defaults (version) or
    /// omitted from the created module.toml.
    #[serde(rename = "systems.create")]
    SystemsCreate {
        name: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        version: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        publisher: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        family: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        series: Option<&'a str>,
    },

    /// Without `slug`, the engine picks the first free `<system>_copy_N`.
    #[serde(rename = "systems.copy")]
    SystemsCopy {
        system: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        slug: Option<&'a str>,
    },

    #[serde(rename = "systems.delete")]
    SystemsDelete { system: &'a str },

    /// The engine derives the type's ID from `name`.
    #[serde(rename = "systems.concept_type.add")]
    SystemsConceptTypeAdd {
        system: &'a str,
        name: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        display_template: Option<&'a str>,
    },

    #[serde(rename = "characters.gen")]
    CharactersGen { system: &'a str },

    #[serde(rename = "characters.save")]
    CharactersSave { temp_id: &'a str },

    #[serde(rename = "characters.list")]
    CharactersList {
        #[serde(skip_serializing_if = "Option::is_none")]
        system: Option<&'a str>,
    },

    /// Without `slug`, the engine picks the first free `<character>_copy_N`.
    #[serde(rename = "characters.copy")]
    CharactersCopy {
        character: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        slug: Option<&'a str>,
    },

    #[serde(rename = "characters.delete")]
    CharactersDelete { character: &'a str },

    #[serde(rename = "characters.show")]
    CharactersShow {
        character: &'a str,
        display_mode: &'a str,
    },

    #[serde(rename = "characters.roll")]
    CharactersRoll {
        character: &'a str,
        #[serde(rename = "type")]
        concept_type: &'a str,
        concept: &'a str,
    },

    #[serde(rename = "characters.award")]
    CharactersAward {
        character: &'a str,
        award: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        value: Option<serde_json::Value>,
        display_mode: &'a str,
    },

    #[serde(rename = "characters.choices")]
    CharactersChoices {
        character: &'a str,
        display_mode: &'a str,
    },

    #[serde(rename = "characters.resolve_choice")]
    CharactersResolveChoice {
        character: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        scope_type: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        scope_id: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        choice: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        progression: Option<&'a str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        value: Option<i64>,
        selection: &'a str,
    },

    #[serde(rename = "characters.random_resolve")]
    CharactersRandomResolve {
        character: &'a str,
        display_mode: &'a str,
    },

    #[serde(rename = "characters.build_start")]
    CharactersBuildStart { system: &'a str, name: &'a str },

    #[serde(rename = "characters.build_select")]
    CharactersBuildSelect {
        temp_id: &'a str,
        concept_type: &'a str,
        concept_id: &'a str,
    },

    #[serde(rename = "characters.build_resolve_sub")]
    CharactersBuildResolveSub {
        temp_id: &'a str,
        scope_type: &'a str,
        scope_id: &'a str,
        choice: &'a str,
        selection: &'a str,
    },

    #[serde(rename = "characters.build_finish")]
    CharactersBuildFinish { temp_id: &'a str },

    #[serde(rename = "characters.inventory")]
    CharactersInventory { character: &'a str },

    #[serde(rename = "characters.inventory.add")]
    CharactersInventoryAdd {
        character: &'a str,
        #[serde(rename = "type")]
        item_type: &'a str,
        id: &'a str,
        fields: serde_json::Value,
    },

    #[serde(rename = "characters.inventory.set")]
    CharactersInventorySet {
        character: &'a str,
        index: u64,
        field: &'a str,
        value: serde_json::Value,
    },

    #[serde(rename = "characters.spells")]
    CharactersSpells { character: &'a str },

    #[serde(rename = "characters.activate")]
    CharactersActivate {
        character: &'a str,
        verb: &'a str,
        items: &'a [&'a str],
    },
}

impl<'a> Request<'a> {
    /// A scope-based `resolve_choice` (a feat or sub-choice keyed by
    /// `scope_type`/`scope_id`), as opposed to a progression-based one.
    pub(crate) fn resolve_choice_scope(
        character: &'a str,
        scope: (&'a str, &'a str),
        choice: &'a str,
        selection: &'a str,
    ) -> Self {
        let (scope_type, scope_id) = scope;
        Request::CharactersResolveChoice {
            character,
            scope_type: Some(scope_type),
            scope_id: Some(scope_id),
            choice: Some(choice),
            progression: None,
            value: None,
            selection,
        }
    }

    /// A progression-based `resolve_choice` (a leveling slot keyed by
    /// `progression`), as opposed to a scope-based one.
    pub(crate) fn resolve_choice_progression(
        character: &'a str,
        progression: &'a str,
        value: i64,
        selection: &'a str,
    ) -> Self {
        Request::CharactersResolveChoice {
            character,
            scope_type: None,
            scope_id: None,
            choice: None,
            progression: Some(progression),
            value: Some(value),
            selection,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn to_value(req: &Request<'_>) -> serde_json::Value {
        serde_json::to_value(req).unwrap()
    }

    #[test]
    fn serializes_roll_and_systems_list_requests() {
        assert_eq!(
            to_value(&Request::Roll { dice: "3d6" }),
            serde_json::json!({"command": "roll", "dice": "3d6"})
        );
        assert_eq!(
            to_value(&Request::SystemsList),
            serde_json::json!({"command": "systems.list"})
        );
    }

    #[test]
    fn serializes_systems_show_requests() {
        assert_eq!(
            to_value(&Request::SystemsShow {
                system: "dnd_5e_srd",
                concept_type: None,
                concept_id: None
            }),
            serde_json::json!({"command": "systems.show", "system": "dnd_5e_srd"})
        );
        assert_eq!(
            to_value(&Request::SystemsShow {
                system: "dnd_5e_srd",
                concept_type: Some("skill"),
                concept_id: None
            }),
            serde_json::json!({
                "command": "systems.show",
                "system": "dnd_5e_srd",
                "concept_type": "skill"
            })
        );
        assert_eq!(
            to_value(&Request::SystemsShow {
                system: "dnd_5e_srd",
                concept_type: Some("race"),
                concept_id: Some("dwarf")
            }),
            serde_json::json!({
                "command": "systems.show",
                "system": "dnd_5e_srd",
                "concept_type": "race",
                "concept_id": "dwarf"
            })
        );
    }

    #[test]
    fn serializes_systems_create_request_omitting_unset_fields() {
        assert_eq!(
            to_value(&Request::SystemsCreate {
                name: "My Fantasy System",
                version: None,
                publisher: Some("Acme Games"),
                family: None,
                series: None,
            }),
            serde_json::json!({
                "command": "systems.create",
                "name": "My Fantasy System",
                "publisher": "Acme Games"
            })
        );
    }

    #[test]
    fn serializes_systems_copy_request() {
        assert_eq!(
            to_value(&Request::SystemsCopy {
                system: "dnd_5e_srd",
                slug: Some("my_dnd")
            }),
            serde_json::json!({"command": "systems.copy", "system": "dnd_5e_srd", "slug": "my_dnd"})
        );
        assert_eq!(
            to_value(&Request::SystemsCopy {
                system: "dnd_5e_srd",
                slug: None
            }),
            serde_json::json!({"command": "systems.copy", "system": "dnd_5e_srd"})
        );
    }

    #[test]
    fn serializes_systems_delete_request() {
        assert_eq!(
            to_value(&Request::SystemsDelete {
                system: "my_homebrew"
            }),
            serde_json::json!({"command": "systems.delete", "system": "my_homebrew"})
        );
    }

    #[test]
    fn serializes_systems_concept_type_add_request() {
        assert_eq!(
            to_value(&Request::SystemsConceptTypeAdd {
                system: "homebrew",
                name: "Feat",
                display_template: Some("{{name}}")
            }),
            serde_json::json!({
                "command": "systems.concept_type.add",
                "system": "homebrew",
                "name": "Feat",
                "display_template": "{{name}}"
            })
        );
        assert_eq!(
            to_value(&Request::SystemsConceptTypeAdd {
                system: "homebrew",
                name: "Feat",
                display_template: None
            }),
            serde_json::json!({"command": "systems.concept_type.add", "system": "homebrew", "name": "Feat"})
        );
    }

    #[test]
    fn serializes_characters_gen_and_save_requests() {
        assert_eq!(
            to_value(&Request::CharactersGen {
                system: "dnd_5e_srd"
            }),
            serde_json::json!({"command": "characters.gen", "system": "dnd_5e_srd"})
        );
        assert_eq!(
            to_value(&Request::CharactersSave { temp_id: "1" }),
            serde_json::json!({"command": "characters.save", "temp_id": "1"})
        );
    }

    #[test]
    fn serializes_characters_list_requests() {
        assert_eq!(
            to_value(&Request::CharactersList { system: None }),
            serde_json::json!({"command": "characters.list"})
        );
        assert_eq!(
            to_value(&Request::CharactersList {
                system: Some("dnd_5e_srd")
            }),
            serde_json::json!({"command": "characters.list", "system": "dnd_5e_srd"})
        );
    }

    #[test]
    fn serializes_characters_copy_request() {
        assert_eq!(
            to_value(&Request::CharactersCopy {
                character: "aria",
                slug: Some("aria_backup")
            }),
            serde_json::json!({"command": "characters.copy", "character": "aria", "slug": "aria_backup"})
        );
        assert_eq!(
            to_value(&Request::CharactersCopy {
                character: "aria",
                slug: None
            }),
            serde_json::json!({"command": "characters.copy", "character": "aria"})
        );
    }

    #[test]
    fn serializes_characters_delete_show_and_roll_requests() {
        assert_eq!(
            to_value(&Request::CharactersDelete {
                character: "thorin-stoneback"
            }),
            serde_json::json!({"command": "characters.delete", "character": "thorin-stoneback"})
        );
        assert_eq!(
            to_value(&Request::CharactersShow {
                character: "thorin-stoneback",
                display_mode: "verbose"
            }),
            serde_json::json!({
                "command": "characters.show",
                "character": "thorin-stoneback",
                "display_mode": "verbose"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersRoll {
                character: "thorin-stoneback",
                concept_type: "skill",
                concept: "acrobatics"
            }),
            serde_json::json!({
                "command": "characters.roll",
                "character": "thorin-stoneback",
                "type": "skill",
                "concept": "acrobatics"
            })
        );
    }

    #[test]
    fn serializes_characters_award_requests() {
        assert_eq!(
            to_value(&Request::CharactersAward {
                character: "thorin-stoneback",
                award: "level_up",
                value: None,
                display_mode: "default"
            }),
            serde_json::json!({
                "command": "characters.award",
                "character": "thorin-stoneback",
                "award": "level_up",
                "display_mode": "default"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersAward {
                character: "thorin-stoneback",
                award: "experience_points",
                value: Some(serde_json::json!(300)),
                display_mode: "default"
            }),
            serde_json::json!({
                "command": "characters.award",
                "character": "thorin-stoneback",
                "award": "experience_points",
                "value": 300,
                "display_mode": "default"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersAward {
                character: "thorin-stoneback",
                award: "feat",
                value: Some(serde_json::json!("alert")),
                display_mode: "default"
            }),
            serde_json::json!({
                "command": "characters.award",
                "character": "thorin-stoneback",
                "award": "feat",
                "value": "alert",
                "display_mode": "default"
            })
        );
    }

    #[test]
    fn serializes_characters_choices_and_resolve_choice_requests() {
        assert_eq!(
            to_value(&Request::CharactersChoices {
                character: "thorin-stoneback",
                display_mode: "default"
            }),
            serde_json::json!({
                "command": "characters.choices",
                "character": "thorin-stoneback",
                "display_mode": "default"
            })
        );
        assert_eq!(
            to_value(&Request::resolve_choice_progression(
                "thorin-stoneback",
                "hp_per_level",
                7,
                "rolled"
            )),
            serde_json::json!({
                "command": "characters.resolve_choice",
                "character": "thorin-stoneback",
                "progression": "hp_per_level",
                "value": 7,
                "selection": "rolled"
            })
        );
        assert_eq!(
            to_value(&Request::resolve_choice_scope(
                "thorin-stoneback",
                ("feat", "ability_score_improvement"),
                "asi_point_1",
                "strength"
            )),
            serde_json::json!({
                "command": "characters.resolve_choice",
                "character": "thorin-stoneback",
                "scope_type": "feat",
                "scope_id": "ability_score_improvement",
                "choice": "asi_point_1",
                "selection": "strength"
            })
        );
    }

    #[test]
    fn serializes_characters_random_resolve_and_build_start_requests() {
        assert_eq!(
            to_value(&Request::CharactersRandomResolve {
                character: "thorin-stoneback",
                display_mode: "default"
            }),
            serde_json::json!({
                "command": "characters.random_resolve",
                "character": "thorin-stoneback",
                "display_mode": "default"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersBuildStart {
                system: "dnd_5e_srd",
                name: "Thorin Stoneback"
            }),
            serde_json::json!({
                "command": "characters.build_start",
                "system": "dnd_5e_srd",
                "name": "Thorin Stoneback"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersBuildSelect {
                temp_id: "1",
                concept_type: "class",
                concept_id: "cleric"
            }),
            serde_json::json!({
                "command": "characters.build_select",
                "temp_id": "1",
                "concept_type": "class",
                "concept_id": "cleric"
            })
        );
    }

    #[test]
    fn serializes_characters_build_resolve_sub_and_finish_requests() {
        assert_eq!(
            to_value(&Request::CharactersBuildResolveSub {
                temp_id: "1",
                scope_type: "class",
                scope_id: "cleric",
                choice: "skill_proficiency_1",
                selection: "history"
            }),
            serde_json::json!({
                "command": "characters.build_resolve_sub",
                "temp_id": "1",
                "scope_type": "class",
                "scope_id": "cleric",
                "choice": "skill_proficiency_1",
                "selection": "history"
            })
        );
        assert_eq!(
            to_value(&Request::CharactersBuildFinish { temp_id: "1" }),
            serde_json::json!({"command": "characters.build_finish", "temp_id": "1"})
        );
    }

    #[test]
    fn serializes_inventory_requests() {
        assert_eq!(
            to_value(&Request::CharactersInventory {
                character: "thorin-stoneback"
            }),
            serde_json::json!({"command": "characters.inventory", "character": "thorin-stoneback"})
        );
        assert_eq!(
            to_value(&Request::CharactersInventoryAdd {
                character: "thorin-stoneback",
                item_type: "equipment",
                id: "chain_mail",
                fields: serde_json::json!({"equipped": true})
            }),
            serde_json::json!({
                "command": "characters.inventory.add",
                "character": "thorin-stoneback",
                "type": "equipment",
                "id": "chain_mail",
                "fields": {"equipped": true}
            })
        );
        assert_eq!(
            to_value(&Request::CharactersInventorySet {
                character: "thorin-stoneback",
                index: 0,
                field: "equipped",
                value: serde_json::json!(true)
            }),
            serde_json::json!({
                "command": "characters.inventory.set",
                "character": "thorin-stoneback",
                "index": 0,
                "field": "equipped",
                "value": true
            })
        );
    }

    #[test]
    fn serializes_spells_and_activate_requests() {
        assert_eq!(
            to_value(&Request::CharactersSpells {
                character: "thorin-stoneback"
            }),
            serde_json::json!({"command": "characters.spells", "character": "thorin-stoneback"})
        );
        let items = ["bless", "cure_wounds"];
        assert_eq!(
            to_value(&Request::CharactersActivate {
                character: "thorin-stoneback",
                verb: "prepare",
                items: &items
            }),
            serde_json::json!({
                "command": "characters.activate",
                "character": "thorin-stoneback",
                "verb": "prepare",
                "items": ["bless", "cure_wounds"]
            })
        );
    }

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
    fn deserialize_created_system() {
        let json = r#"{"created":"homebrew","version":"1.0.0","path":"/x/homebrew/module.toml"}"#;
        let c: CreatedSystem = serde_json::from_str(json).unwrap();
        assert_eq!(c.created, "homebrew");
        assert_eq!(c.version.as_deref(), Some("1.0.0"));
        assert_eq!(c.path, "/x/homebrew/module.toml");

        let json = r#"{"created":"homebrew","version":null,"path":"/x/homebrew/module.toml"}"#;
        let c: CreatedSystem = serde_json::from_str(json).unwrap();
        assert_eq!(c.version, None);
    }

    #[test]
    fn deserialize_copied_system() {
        let json = r#"{"copied":"dnd_5e_srd","created":"dnd_5e_srd_copy_1","name":"SRD (copy)","path":"/x/dnd_5e_srd_copy_1"}"#;
        let c: CopiedSystem = serde_json::from_str(json).unwrap();
        assert_eq!(
            (&*c.copied, &*c.created, &*c.name, &*c.path),
            (
                "dnd_5e_srd",
                "dnd_5e_srd_copy_1",
                "SRD (copy)",
                "/x/dnd_5e_srd_copy_1"
            )
        );
    }

    #[test]
    fn deserialize_added_concept_type() {
        let json = r#"{"added":"feat","system":"homebrew","path":"/x/homebrew/module.toml"}"#;
        let a: AddedConceptType = serde_json::from_str(json).unwrap();
        assert_eq!((&*a.added, &*a.path), ("feat", "/x/homebrew/module.toml"));
    }

    #[test]
    fn deserialize_deleted_system() {
        let json = r#"{"deleted":"my_homebrew","path":"/x/local_system_configs/my_homebrew"}"#;
        let d: DeletedSystem = serde_json::from_str(json).unwrap();
        assert_eq!(d.deleted, "my_homebrew");
        assert_eq!(d.path, "/x/local_system_configs/my_homebrew");
    }

    #[test]
    fn deserialize_copied_character() {
        let json = r#"{"copied":"aria","created":"aria_copy_1","name":"Aria (copy)"}"#;
        let c: CopiedCharacter = serde_json::from_str(json).unwrap();
        assert_eq!(
            (&*c.copied, &*c.created, &*c.name),
            ("aria", "aria_copy_1", "Aria (copy)")
        );
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
        assert!(c.pending_choices.is_empty());
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
        let pending = &c.pending_choices;
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

    #[test]
    fn deserialize_preparation_state_prepared_mode() {
        let json = r#"{
            "preparation_mode": "prepared",
            "cap": 5,
            "eligible_items": ["bless","cure_wounds","guiding_bolt"],
            "prepared_items": ["bless","cure_wounds"],
            "always_active": ["sacred_flame"]
        }"#;
        let r: PreparationStateResponse = serde_json::from_str(json).unwrap();
        assert_eq!(r.preparation_mode.as_deref(), Some("prepared"));
        assert_eq!(r.prepared_items, vec!["bless", "cure_wounds"]);
        assert_eq!(r.always_active, vec!["sacred_flame"]);
    }

    #[test]
    fn deserialize_preparation_state_no_class() {
        let json = r#"{"preparation_mode": null}"#;
        let r: PreparationStateResponse = serde_json::from_str(json).unwrap();
        assert!(r.preparation_mode.is_none());
        assert!(r.cap.is_none());
        assert!(r.eligible_items.is_empty());
    }
}
