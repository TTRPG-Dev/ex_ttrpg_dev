//! Display helpers — functions that format and print engine responses to stdout.
//!
//! Also provides `page_output` for piping long content through the system pager.

use crate::protocol::{
    CharacterData, CharacterListCategory, CharacterSummary, ConceptsList, InventoryItemData,
    PendingChoice, SelectedConcept, SpellsResponse, SystemInfo,
};

pub(crate) fn format_character(c: &CharacterData) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    let header = match &c.slug {
        Some(slug) => format!("── {} ({}) ──", c.name, slug),
        None => format!("── {} ──", c.name),
    };
    writeln!(out, "\n{header}").unwrap();
    writeln!(out, "System: {}", c.rule_system).unwrap();
    for choice in &c.choices {
        writeln!(out, "{}: {}", choice.type_name, choice.value).unwrap();
    }
    out.push_str(&format_character_lists(&c.character_lists));
    out.push_str(&format_selected_concepts(&c.selected_concepts));
    for ct in &c.concept_types {
        writeln!(out, "\n{}s:", ct.name).unwrap();
        for concept in &ct.concepts {
            let fields: Vec<String> = concept
                .fields
                .iter()
                .map(|f| format!("{}: {}", f.name, f.value))
                .collect();
            writeln!(out, "  {}: {}", concept.name, fields.join("  ")).unwrap();
        }
    }
    writeln!(out).unwrap();
    out
}

pub(crate) fn print_character(c: &CharacterData) {
    print!("{}", format_character(c));
}

pub(crate) fn format_character_lists(lists: &[CharacterListCategory]) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    for list in lists {
        if !list.items.is_empty() {
            writeln!(out, "{}: {}", list.label, list.items.join(", ")).unwrap();
        }
    }
    out
}

pub(crate) fn format_selected_concepts(concepts: &[SelectedConcept]) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    let mut last_progression: Option<&str> = None;
    for concept in concepts {
        if last_progression != Some(concept.progression.as_str()) {
            writeln!(out, "{}:", concept.progression).unwrap();
            last_progression = Some(&concept.progression);
        }
        writeln!(out, "  {}", concept.label).unwrap();
    }
    out
}

pub(crate) fn print_inventory(inventory: &[InventoryItemData]) {
    if inventory.is_empty() {
        println!("Inventory: (empty)");
        return;
    }
    println!(
        "Inventory ({} item{}):",
        inventory.len(),
        if inventory.len() == 1 { "" } else { "s" }
    );
    for item in inventory {
        let fields_str = item
            .fields
            .as_object()
            .map(|m| {
                m.iter()
                    .map(|(k, v)| format!("{k}: {v}"))
                    .collect::<Vec<_>>()
                    .join("  ")
            })
            .unwrap_or_default();
        println!(
            "  [{}] {}/{}  {}",
            item.index, item.concept_type, item.concept_id, fields_str
        );
    }
}

pub(crate) fn print_system_info(info: SystemInfo) {
    println!("Name:    {}", info.name);
    println!("Slug:    {}", info.slug);
    println!("Version: {}", info.version);
    if let Some(p) = &info.publisher {
        println!("Publisher: {p}");
    }
    if let Some(f) = &info.family {
        println!("Family: {f}");
    }
    if let Some(s) = &info.series {
        println!("Series: {s}");
    }
    if let Some(cts) = &info.concept_types {
        println!("\nConcept Types:");
        for ct in cts {
            println!("  {}: {}", ct.id, ct.name);
        }
    }
}

pub(crate) fn print_concepts_list(cl: &ConceptsList) {
    println!("{}:", cl.concept_type);
    for c in &cl.concepts {
        println!("  {}: {}", c.id, c.name);
    }
}

pub(crate) fn print_characters_list(characters: &[CharacterSummary], empty_msg: &str) {
    if characters.is_empty() {
        println!("{empty_msg}");
    } else {
        for c in characters {
            println!("  - {}: {} [{}]", c.slug, c.name, c.rule_system);
        }
    }
}

pub(crate) fn print_spells(r: &SpellsResponse) {
    match r.preparation_mode.as_deref() {
        None | Some("") => {
            println!("No spellcasting class found for this character.");
        }
        Some("all") => {
            println!(
                "All {} spell(s) prepared (no manual preparation needed).",
                r.prepared_spells.len()
            );
            if !r.always_prepared.is_empty() {
                println!("Always prepared: {}", r.always_prepared.join(", "));
            }
            if !r.prepared_spells.is_empty() {
                println!("Prepared: {}", r.prepared_spells.join(", "));
            }
        }
        Some("prepared") => {
            let prepared = r.prepared_spells.len();
            let cap = r.cap.unwrap_or(0);
            println!("Prepared spells: {prepared}/{cap}");
            if !r.always_prepared.is_empty() {
                println!("Always prepared: {}", r.always_prepared.join(", "));
            }
            if !r.prepared_spells.is_empty() {
                println!("Prepared: {}", r.prepared_spells.join(", "));
            } else {
                println!("Prepared: (none)");
            }
            println!("Eligible pool: {} spell(s)", r.eligible_spells.len());
        }
        Some(mode) => {
            println!("Preparation mode: {mode}");
        }
    }
}

pub(crate) fn print_pending_choices(choices: &[PendingChoice]) {
    println!("\nPending choices:");
    for c in choices {
        let roll_info = c
            .roll
            .as_deref()
            .map(|r| format!(" ({})", r))
            .unwrap_or_default();
        match c.choice_type.as_str() {
            "pending" => {
                let count = c.count.unwrap_or(1);
                let level_info = c
                    .earned_at_level
                    .map(|l| format!(" [level {}]", l))
                    .unwrap_or_default();
                println!(
                    "  • {} — {} remaining{}{}",
                    c.name, count, roll_info, level_info
                );
            }
            _ => println!("  • {}{} (available)", c.name, roll_info),
        }
    }
    println!("  Use `characters resolve_choice <slug>` to resolve.");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::*;

    fn minimal_character(name: &str) -> CharacterData {
        CharacterData {
            temp_id: None,
            slug: None,
            name: name.to_string(),
            rule_system: "test_system".to_string(),
            choices: vec![],
            character_lists: vec![],
            concept_types: vec![],
            selected_concepts: vec![],
            pending_choices: None,
            awarded_xp: None,
        }
    }

    fn list(label: &str, items: &[&str]) -> CharacterListCategory {
        CharacterListCategory {
            label: label.to_string(),
            items: items.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn format_character_lists_empty_returns_empty_string() {
        assert_eq!(format_character_lists(&[]), "");
    }

    #[test]
    fn format_character_lists_single_entry() {
        let out = format_character_lists(&[list("Skills", &["Acrobatics", "Stealth"])]);
        assert!(out.contains("Skills: Acrobatics, Stealth"));
        assert!(!out.contains("Languages"));
    }

    #[test]
    fn format_character_lists_multiple_entries() {
        let out = format_character_lists(&[
            list("Skills", &["Stealth"]),
            list("Languages", &["Common", "Elvish"]),
        ]);
        assert!(out.contains("Skills: Stealth"));
        assert!(out.contains("Languages: Common, Elvish"));
        assert!(!out.contains("Weapons"));
    }

    #[test]
    fn format_character_lists_damage_resistances() {
        let out = format_character_lists(&[list("Damage Resistances", &["Poison", "Fire"])]);
        assert!(out.contains("Damage Resistances: Poison, Fire"));
        assert!(!out.contains("Languages"));
    }

    #[test]
    fn format_character_without_slug() {
        let out = format_character(&minimal_character("Aria"));
        assert!(out.contains("── Aria ──"));
        assert!(out.contains("System: test_system"));
    }

    #[test]
    fn format_character_with_slug() {
        let c = CharacterData {
            slug: Some("aria-1".to_string()),
            ..minimal_character("Aria")
        };
        assert!(format_character(&c).contains("── Aria (aria-1) ──"));
    }

    #[test]
    fn format_character_includes_choices() {
        let c = CharacterData {
            choices: vec![ChoiceEntry {
                type_name: "Race".to_string(),
                value: "Elf".to_string(),
            }],
            ..minimal_character("Aria")
        };
        assert!(format_character(&c).contains("Race: Elf"));
    }

    #[test]
    fn format_character_includes_concept_types_and_fields() {
        let c = CharacterData {
            concept_types: vec![ConceptTypeValues {
                name: "Ability".to_string(),
                concepts: vec![ConceptValues {
                    name: "Strength".to_string(),
                    fields: vec![FieldValue {
                        name: "score".to_string(),
                        value: "16".to_string(),
                    }],
                }],
            }],
            ..minimal_character("Aria")
        };
        let out = format_character(&c);
        assert!(out.contains("Strength"));
        assert!(out.contains("score: 16"));
    }

    fn selected(progression: &str, id: &str, label: &str) -> SelectedConcept {
        SelectedConcept {
            progression: progression.to_string(),
            id: id.to_string(),
            label: label.to_string(),
        }
    }

    #[test]
    fn format_selected_concepts_empty() {
        assert_eq!(format_selected_concepts(&[]), "");
    }

    #[test]
    fn format_selected_concepts_groups_by_progression() {
        let concepts = vec![
            selected(
                "Spells Known",
                "fire_bolt",
                "Fire Bolt: Level 0, evocation (VS)",
            ),
            selected(
                "Spells Known",
                "magic_missile",
                "Magic Missile: Level 1, evocation (S)",
            ),
        ];
        let out = format_selected_concepts(&concepts);
        assert!(out.contains("Spells Known:"));
        assert!(out.contains("  Fire Bolt: Level 0, evocation (VS)"));
        assert!(out.contains("  Magic Missile: Level 1, evocation (S)"));
    }

    #[test]
    fn format_selected_concepts_multiple_progressions() {
        let concepts = vec![
            selected("Spells Known", "fire_bolt", "Fire Bolt"),
            selected("Blessings", "second_wind", "Second Wind"),
        ];
        let out = format_selected_concepts(&concepts);
        assert!(out.contains("Spells Known:"));
        assert!(out.contains("  Fire Bolt"));
        assert!(out.contains("Blessings:"));
        assert!(out.contains("  Second Wind"));
    }

    #[test]
    fn format_character_includes_character_lists() {
        let c = CharacterData {
            character_lists: vec![list("Skills", &["Stealth"]), list("Languages", &["Common"])],
            ..minimal_character("Aria")
        };
        let out = format_character(&c);
        assert!(out.contains("Skills: Stealth"));
        assert!(out.contains("Languages: Common"));
    }
}

pub(crate) fn page_output(content: &str) {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let terminal_height = crossterm::terminal::size()
        .map(|(_, h)| h as usize)
        .unwrap_or(24);
    if content.lines().count() <= terminal_height {
        print!("{content}");
        return;
    }

    let pager = std::env::var("PAGER").unwrap_or_else(|_| "less".to_string());
    if let Ok(mut child) = Command::new(&pager).stdin(Stdio::piped()).spawn() {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(content.as_bytes());
        }
        let _ = child.wait();
    } else {
        print!("{content}");
    }
}
