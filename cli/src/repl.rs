//! Interactive REPL using reedline.
//!
//! Drives the Elixir engine subprocess and handles all display formatting.

use std::borrow::Cow;

use reedline::{
    Completer, DefaultHinter, DefaultValidator, FileBackedHistory, Prompt, PromptEditMode,
    PromptHistorySearch, PromptHistorySearchStatus, Reedline, Signal, Suggestion,
};
use serde::Deserialize;
use serde_json::json;

use crate::engine::Engine;

// ── Prompt ────────────────────────────────────────────────────────────────────

struct TtrpgPrompt;

impl Prompt for TtrpgPrompt {
    fn render_prompt_left(&self) -> Cow<'_, str> {
        Cow::Borrowed("ttrpg-dev")
    }
    fn render_prompt_right(&self) -> Cow<'_, str> {
        Cow::Borrowed("")
    }
    fn render_prompt_indicator(&self, _mode: PromptEditMode) -> Cow<'_, str> {
        Cow::Borrowed("> ")
    }
    fn render_prompt_multiline_indicator(&self) -> Cow<'_, str> {
        Cow::Borrowed("::: ")
    }
    fn render_prompt_history_search_indicator(
        &self,
        history_search: PromptHistorySearch,
    ) -> Cow<'_, str> {
        let indicator = match history_search.status {
            PromptHistorySearchStatus::Passing => "",
            PromptHistorySearchStatus::Failing => " (not found)",
        };
        Cow::Owned(format!("(search: {}{}): ", history_search.term, indicator))
    }
}

// ── Tab completion ─────────────────────────────────────────────────────────────

static COMMANDS: &[&str] = &[
    "roll",
    "systems list",
    "systems show",
    "characters gen",
    "characters list",
    "characters show",
    "characters roll",
    "characters levelup",
    "help",
    "exit",
    "quit",
];

struct CommandCompleter;

impl Completer for CommandCompleter {
    fn complete(&mut self, line: &str, pos: usize) -> Vec<Suggestion> {
        let prefix = &line[..pos];
        COMMANDS
            .iter()
            .filter(|cmd| cmd.starts_with(prefix))
            .map(|cmd| Suggestion {
                value: cmd.to_string(),
                description: None,
                style: None,
                extra: None,
                span: reedline::Span { start: 0, end: pos },
                append_whitespace: true,
            })
            .collect()
    }
}

// ── Response types ─────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SystemsList {
    systems: Vec<String>,
}

#[derive(Deserialize)]
struct SystemInfo {
    name: String,
    slug: String,
    version: String,
    publisher: Option<String>,
    family: Option<String>,
    series: Option<String>,
    concept_types: Option<Vec<ConceptTypeSummary>>,
}

#[derive(Deserialize)]
struct ConceptTypeSummary {
    id: String,
    name: String,
}

#[derive(Deserialize)]
struct ConceptsList {
    concept_type: String,
    concepts: Vec<ConceptSummary>,
}

#[derive(Deserialize)]
struct ConceptSummary {
    id: String,
    name: String,
}

#[derive(Deserialize)]
struct RollResult {
    results: Vec<DiceResult>,
}

#[derive(Deserialize)]
struct DiceResult {
    spec: String,
    rolls: Vec<i64>,
    total: i64,
}

#[derive(Deserialize)]
struct CharactersList {
    characters: Vec<CharacterSummary>,
}

#[derive(Deserialize)]
struct CharacterSummary {
    slug: String,
    name: String,
    rule_system: String,
}

#[derive(Deserialize)]
struct CharacterData {
    temp_id: Option<String>,
    slug: Option<String>,
    name: String,
    rule_system: String,
    hit_die: Option<String>,
    choices: Vec<ChoiceEntry>,
    proficiencies: Proficiencies,
    concept_types: Vec<ConceptTypeValues>,
}

#[derive(Deserialize)]
struct ChoiceEntry {
    type_name: String,
    value: String,
}

#[derive(Deserialize)]
struct Proficiencies {
    skills: Vec<String>,
    languages: Vec<String>,
    weapons: Vec<String>,
    armor: Vec<String>,
    tools: Vec<String>,
}

#[derive(Deserialize)]
struct ConceptTypeValues {
    id: String,
    name: String,
    concepts: Vec<ConceptValues>,
}

#[derive(Deserialize)]
struct ConceptValues {
    id: String,
    name: String,
    fields: Vec<FieldValue>,
}

#[derive(Deserialize)]
struct FieldValue {
    name: String,
    value: String,
}

#[derive(Deserialize)]
struct SaveResult {
    slug: String,
}

#[derive(Deserialize)]
struct ConceptRollResult {
    concept_name: String,
    dice: String,
    rolls: Vec<i64>,
    bonus: i64,
    total: i64,
}

// ── Display helpers ────────────────────────────────────────────────────────────

fn print_character(c: &CharacterData) {
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

fn print_proficiencies(p: &Proficiencies) {
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

fn print_system_info(info: SystemInfo) {
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

fn print_concepts_list(cl: &ConceptsList) {
    println!("{}:", cl.concept_type);
    for c in &cl.concepts {
        println!("  {}: {}", c.id, c.name);
    }
}

fn print_characters_list(characters: &[CharacterSummary], empty_msg: &str) {
    if characters.is_empty() {
        println!("{empty_msg}");
    } else {
        for c in characters {
            println!("  - {}: {} [{}]", c.slug, c.name, c.rule_system);
        }
    }
}

// ── Command dispatch ───────────────────────────────────────────────────────────

fn handle_line(line: &str, engine: &mut Engine) -> bool {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    if tokens.is_empty() {
        return true;
    }
    match tokens.as_slice() {
        ["exit" | "quit"] => return false,
        ["help"] => print_help(),
        ["roll", rest @ ..] => handle_roll(&rest.join(" "), engine),
        ["systems", rest @ ..] => handle_systems(rest, engine),
        ["characters", rest @ ..] => handle_characters(rest, engine),
        _ => eprintln!("Unknown command. Type `help` for available commands."),
    }
    true
}

fn handle_roll(dice: &str, engine: &mut Engine) {
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

fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list"] => match engine.call::<_, SystemsList>(&json!({"command": "systems.list"})) {
            Ok(result) => {
                if result.systems.is_empty() {
                    println!("No configured systems found.");
                } else {
                    println!("Configured Systems:");
                    for s in &result.systems {
                        println!("  - {s}");
                    }
                }
            }
            Err(e) => eprintln!("Error: {e}"),
        },
        ["show", slug] => {
            let req = json!({"command": "systems.show", "system": slug});
            match engine.call::<_, SystemInfo>(&req) {
                Ok(info) => print_system_info(info),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["show", slug, "--concept-type", ct] => {
            let req = json!({"command": "systems.show", "system": slug, "concept_type": ct});
            match engine.call::<_, ConceptsList>(&req) {
                Ok(cl) => print_concepts_list(&cl),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        _ => eprintln!("Usage: systems list | systems show <slug> [--concept-type <type>]"),
    }
}

fn handle_characters(tokens: &[&str], engine: &mut Engine) {
    match tokens {
        ["list"] => {
            let req = json!({"command": "characters.list"});
            match engine.call::<_, CharactersList>(&req) {
                Ok(r) => print_characters_list(&r.characters, "No saved characters found."),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["list", "--system", system] => {
            let req = json!({"command": "characters.list", "system": system});
            match engine.call::<_, CharactersList>(&req) {
                Ok(r) => print_characters_list(
                    &r.characters,
                    &format!("No saved characters found for system `{system}`."),
                ),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["gen", system] => handle_characters_gen(system, engine),
        ["show", slug] => {
            let req = json!({"command": "characters.show", "character": slug});
            match engine.call::<_, CharacterData>(&req) {
                Ok(c) => print_character(&c),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        ["roll", slug, type_id, concept_id] => handle_characters_roll(slug, type_id, concept_id, engine),
        ["levelup", slug] => handle_characters_levelup(slug, engine),
        _ => eprintln!(
            "Usage: characters list | gen <system> | show <slug> | roll <slug> <type> <concept> | levelup <slug>"
        ),
    }
}

fn handle_characters_gen(system: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.gen", "system": system});
    match engine.call::<_, CharacterData>(&req) {
        Ok(character) => {
            print_character(&character);
            if let Some(temp_id) = &character.temp_id
                && prompt_yes_no("Save this character?")
            {
                let save_req = json!({"command": "characters.save", "temp_id": temp_id});
                match engine.call::<_, SaveResult>(&save_req) {
                    Ok(saved) => println!("Saved as '{}'.", saved.slug),
                    Err(e) => eprintln!("Error saving: {e}"),
                }
            }
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_roll(slug: &str, type_id: &str, concept_id: &str, engine: &mut Engine) {
    let req = json!({
        "command": "characters.roll",
        "character": slug,
        "type": type_id,
        "concept": concept_id,
    });
    match engine.call::<_, ConceptRollResult>(&req) {
        Ok(result) => {
            let rolls_str: Vec<String> = result.rolls.iter().map(|n| n.to_string()).collect();
            let bonus_str = if result.bonus >= 0 {
                format!("+{}", result.bonus)
            } else {
                result.bonus.to_string()
            };
            println!(
                "{} check: {} ({}: {}, bonus: {})",
                result.concept_name,
                result.total,
                result.dice,
                rolls_str.join(", "),
                bonus_str,
            );
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn handle_characters_levelup(slug: &str, engine: &mut Engine) {
    let req = json!({"command": "characters.show", "character": slug});
    let character = match engine.call::<_, CharacterData>(&req) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error: {e}");
            return;
        }
    };

    let hit_die = match &character.hit_die {
        Some(hd) => hd.clone(),
        None => {
            eprintln!("Could not determine hit die for this character.");
            return;
        }
    };

    let current_level = find_character_level(&character);
    let sides = parse_die_sides(&hit_die);
    let average = sides / 2 + 1;

    println!(
        "\nLeveling up {} from level {current_level} to {}.",
        character.name,
        current_level + 1
    );
    println!("Hit die: {hit_die}  Average HP (no roll): {average}");
    println!();

    let xp = prompt_integer("XP gained:");

    let (hp, hp_method) =
        if prompt_yes_no(&format!("Roll {hit_die} for HP? (no = take average of {average})")) {
            let roll_req = json!({"command": "roll", "dice": format!("1{hit_die}")});
            match engine.call::<_, RollResult>(&roll_req) {
                Ok(result) => {
                    let rolled = result.results[0].total;
                    println!("Rolled: {rolled}");
                    (rolled, "rolled")
                }
                Err(e) => {
                    eprintln!("Error rolling: {e}");
                    return;
                }
            }
        } else {
            (average, "average")
        };

    let levelup_req = json!({
        "command": "characters.levelup",
        "character": slug,
        "xp": xp,
        "hp": hp,
        "hp_method": hp_method,
    });

    match engine.call::<_, CharacterData>(&levelup_req) {
        Ok(updated) => {
            println!("\nReached level {}!", current_level + 1);
            print_character(&updated);
        }
        Err(e) => eprintln!("Error: {e}"),
    }
}

fn find_character_level(character: &CharacterData) -> i64 {
    character
        .concept_types
        .iter()
        .find(|ct| ct.id == "character_trait")
        .and_then(|ct| ct.concepts.iter().find(|c| c.id == "character_level"))
        .and_then(|c| c.fields.iter().find(|f| f.name == "level"))
        .and_then(|f| f.value.parse::<i64>().ok())
        .unwrap_or(1)
}

fn parse_die_sides(hit_die: &str) -> i64 {
    hit_die.trim_start_matches('d').parse().unwrap_or(8)
}

fn prompt_integer(question: &str) -> i64 {
    use std::io::{self, BufRead};
    loop {
        print!("{question} ");
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        if let Some(Ok(line)) = stdin.lock().lines().next()
            && let Ok(n) = line.trim().parse::<i64>()
        {
            return n;
        }
        eprintln!("Please enter a valid number.");
    }
}

fn prompt_yes_no(question: &str) -> bool {
    use std::io::{self, BufRead};
    print!("(y/n) {question} ");
    let _ = std::io::Write::flush(&mut io::stdout());
    let stdin = io::stdin();
    let line = stdin.lock().lines().next().and_then(|l| l.ok());
    matches!(
        line.as_deref().map(str::trim).map(str::to_lowercase).as_deref(),
        Some("y") | Some("yes")
    )
}

fn print_help() {
    println!(
        r#"
Commands:
  roll <dice>                              Roll dice, e.g. roll 3d6, 1d20
  systems list                             List configured rule systems
  systems show <system>                    Show system info
  systems show <system> --concept-type <t> List concepts of a type
  characters gen <system>                  Generate a character
  characters list                          List saved characters
  characters list --system <system>        List characters for a system
  characters show <slug>                   Show a saved character
  characters roll <slug> <type> <concept>  Roll for a character concept
  characters levelup <slug>                Level up a character (add XP + HP gain)
  help                                     Show this help
  exit / quit                              Exit
"#
    );
}

// ── Entry point ────────────────────────────────────────────────────────────────

pub fn run() {
    let mut engine = match Engine::spawn() {
        Ok(e) => e,
        Err(e) => {
            eprintln!("Failed to start engine: {e}");
            eprintln!("Make sure `ttrpg-dev-engine` is in your PATH or next to this binary.");
            std::process::exit(1);
        }
    };

    let history: Box<dyn reedline::History> =
        match FileBackedHistory::with_file(1000, history_path()) {
            Ok(h) => Box::new(h),
            Err(_) => Box::new(FileBackedHistory::new(1000).expect("in-memory history")),
        };

    let mut line_editor = Reedline::create()
        .with_history(history)
        .with_completer(Box::new(CommandCompleter))
        .with_hinter(Box::new(DefaultHinter::default()))
        .with_validator(Box::new(DefaultValidator));

    let prompt = TtrpgPrompt;

    println!("TTRPG Dev — interactive shell");
    println!("Type `help` for available commands, `exit` to quit.\n");

    loop {
        match line_editor.read_line(&prompt) {
            Ok(Signal::Success(line)) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if !handle_line(trimmed, &mut engine) {
                    println!("Goodbye!");
                    break;
                }
            }
            Ok(Signal::CtrlD) | Ok(Signal::CtrlC) => {
                println!("\nGoodbye!");
                break;
            }
            Err(e) => {
                eprintln!("Input error: {e}");
                break;
            }
        }
    }
}

fn history_path() -> std::path::PathBuf {
    let base = std::env::var("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("."));
    base.join(".ttrpg_dev_history")
}
