//! Display helpers — functions that format and print engine responses to stdout.
//!
//! Also provides `page_output` for piping long content through the system pager.

use crate::protocol::{
    CharacterData, CharacterSummary, ConceptsList, InventoryItemData, PendingChoice, Proficiencies,
    SystemInfo,
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
    out.push_str(&format_proficiencies(&c.proficiencies));
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

pub(crate) fn format_proficiencies(p: &Proficiencies) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    let entries = [
        ("Skill Proficiencies", &p.skills),
        ("Languages", &p.languages),
        ("Weapon Proficiencies", &p.weapons),
        ("Armor Proficiencies", &p.armor),
        ("Tool Proficiencies", &p.tools),
    ];
    for (label, items) in entries {
        if !items.is_empty() {
            writeln!(out, "{label}: {}", items.join(", ")).unwrap();
        }
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
                println!("  • {} — {} remaining{}", c.name, count, roll_info);
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

    fn empty_proficiencies() -> Proficiencies {
        Proficiencies {
            skills: vec![],
            languages: vec![],
            weapons: vec![],
            armor: vec![],
            tools: vec![],
        }
    }

    fn minimal_character(name: &str) -> CharacterData {
        CharacterData {
            temp_id: None,
            slug: None,
            name: name.to_string(),
            rule_system: "test_system".to_string(),
            choices: vec![],
            proficiencies: empty_proficiencies(),
            concept_types: vec![],
            pending_choices: None,
        }
    }

    #[test]
    fn format_proficiencies_all_empty_returns_empty_string() {
        assert_eq!(format_proficiencies(&empty_proficiencies()), "");
    }

    #[test]
    fn format_proficiencies_single_category() {
        let p = Proficiencies {
            skills: vec!["Acrobatics".to_string(), "Stealth".to_string()],
            ..empty_proficiencies()
        };
        let out = format_proficiencies(&p);
        assert!(out.contains("Skill Proficiencies: Acrobatics, Stealth"));
        assert!(!out.contains("Languages"));
    }

    #[test]
    fn format_proficiencies_multiple_categories() {
        let p = Proficiencies {
            skills: vec!["Stealth".to_string()],
            languages: vec!["Common".to_string(), "Elvish".to_string()],
            ..empty_proficiencies()
        };
        let out = format_proficiencies(&p);
        assert!(out.contains("Skill Proficiencies: Stealth"));
        assert!(out.contains("Languages: Common, Elvish"));
        assert!(!out.contains("Weapons"));
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

    #[test]
    fn format_character_includes_proficiencies() {
        let c = CharacterData {
            proficiencies: Proficiencies {
                skills: vec!["Stealth".to_string()],
                languages: vec!["Common".to_string()],
                ..empty_proficiencies()
            },
            ..minimal_character("Aria")
        };
        let out = format_character(&c);
        assert!(out.contains("Skill Proficiencies: Stealth"));
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
