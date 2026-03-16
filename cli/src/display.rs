//! Display helpers — functions that format and print engine responses to stdout.

use crate::protocol::{
    CharacterData, CharacterSummary, ConceptsList, InventoryItemData, PendingChoice, Proficiencies,
    SystemInfo,
};

pub(crate) fn print_character(c: &CharacterData) {
    let header = match &c.slug {
        Some(slug) => format!("── {} ({}) ──", c.name, slug),
        None => format!("── {} ──", c.name),
    };
    println!("\n{header}");
    println!("System: {}", c.rule_system);
    for choice in &c.choices {
        println!("{}: {}", choice.type_name, choice.value);
    }
    print_proficiencies(&c.proficiencies);
    for ct in &c.concept_types {
        println!("\n{}s:", ct.name);
        for concept in &ct.concepts {
            let fields: Vec<String> = concept
                .fields
                .iter()
                .map(|f| format!("{}: {}", f.name, f.value))
                .collect();
            println!("  {}: {}", concept.name, fields.join("  "));
        }
    }
    println!();
}

pub(crate) fn print_proficiencies(p: &Proficiencies) {
    let entries = [
        ("Skill Proficiencies", &p.skills),
        ("Languages", &p.languages),
        ("Weapon Proficiencies", &p.weapons),
        ("Armor Proficiencies", &p.armor),
        ("Tool Proficiencies", &p.tools),
    ];
    for (label, items) in entries {
        if !items.is_empty() {
            println!("{label}: {}", items.join(", "));
        }
    }
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
