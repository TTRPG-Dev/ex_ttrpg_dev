use super::call_or_report;
use super::table::{self, COMMAND_TABLE};
use crate::display;
use crate::engine::Engine;
use crate::prompts::{prompt_loop, prompt_nonempty_string, prompt_yes_no};
use crate::protocol::{
    ConceptsList, CreatedSystem, DeletedSystem, Request, SystemInfo, SystemsList,
};

pub(crate) fn handle_systems(tokens: &[&str], engine: &mut Engine) {
    if table::dispatch_help(tokens, "systems") {
        return;
    }
    match tokens {
        ["list"] => handle_systems_list(engine),
        ["show", slug] => handle_systems_show(slug, None, engine),
        ["show", slug, "--concept-type", ct] => handle_systems_show(slug, Some(ct), engine),
        ["create"] => handle_systems_create(engine),
        ["create", extra, ..] => {
            eprintln!("Unexpected argument '{extra}'. Try `systems create --help`.")
        }
        ["delete", rest @ ..] => match parse_delete_args(rest) {
            Ok(args) => handle_systems_delete(args, engine),
            Err(msg) => eprintln!("{msg} Try `systems delete --help`."),
        },
        [] | ["--help"] => print_systems_usage(),
        [unknown, ..] => eprintln!("Unknown subcommand '{unknown}'. Try `systems --help`."),
    }
}

fn handle_systems_list(engine: &mut Engine) {
    let Some(result) = call_or_report::<SystemsList>(engine, &Request::SystemsList) else {
        return;
    };
    if result.systems.is_empty() {
        println!("No configured systems found.");
    } else {
        println!("Configured Systems:");
        for s in &result.systems {
            println!("  - {s}");
        }
    }
}

/// Without a concept type, shows the system itself; with one, lists that
/// type's concepts. The two responses have different shapes.
fn handle_systems_show(slug: &str, concept_type: Option<&str>, engine: &mut Engine) {
    let req = Request::SystemsShow {
        system: slug,
        concept_type,
        concept_id: None,
    };
    match concept_type {
        None => {
            if let Some(info) = call_or_report::<SystemInfo>(engine, &req) {
                display::print_system_info(info);
            }
        }
        Some(_) => {
            if let Some(cl) = call_or_report::<ConceptsList>(engine, &req) {
                display::print_concepts_list(&cl);
            }
        }
    }
}

/// Lists every `systems` subcommand's usage from `COMMAND_TABLE`, so it
/// can't drift from each subcommand's own `--help`.
fn print_systems_usage() {
    println!("Usage:");
    for spec in COMMAND_TABLE {
        if spec.path.starts_with("systems ") {
            println!("  {}", spec.usage);
        }
    }
}

/// What the user typed for `systems create`, blanks already turned into
/// `None` so they're left out of the request (and so of module.toml).
struct CreateAnswers {
    name: String,
    version: Option<String>,
    publisher: Option<String>,
    family: Option<String>,
    series: Option<String>,
}

/// Outer `None` on EOF; inner `None` for a blank answer.
fn prompt_optional(prompt: &str) -> Option<Option<String>> {
    prompt_loop(prompt, |line| {
        let answer = line.trim();
        Ok((!answer.is_empty()).then(|| answer.to_string()))
    })
}

/// `None` if input ends (EOF) at any prompt, which cancels the create.
fn prompt_create_answers() -> Option<CreateAnswers> {
    Some(CreateAnswers {
        name: prompt_nonempty_string("System name:")?,
        version: prompt_optional("Version [1.0.0]: ")?,
        publisher: prompt_optional("Publisher (optional): ")?,
        family: prompt_optional("Family (optional): ")?,
        series: prompt_optional("Series (optional): ")?,
    })
}

/// The slug is derived from the name, and collisions refused, by the
/// engine; the CLI doesn't repeat those rules.
fn handle_systems_create(engine: &mut Engine) {
    let Some(a) = prompt_create_answers() else {
        println!("Not created.");
        return;
    };
    let req = Request::SystemsCreate {
        name: &a.name,
        version: a.version.as_deref(),
        publisher: a.publisher.as_deref(),
        family: a.family.as_deref(),
        series: a.series.as_deref(),
    };
    let Some(r) = call_or_report::<CreatedSystem>(engine, &req) else {
        return;
    };
    println!();
    println!("Created rule system {}: {}", r.created, r.path);
}

#[derive(Debug, PartialEq)]
struct DeleteArgs<'a> {
    system: &'a str,
    yes: bool,
}

/// `<system> [-y|--yes]`, flag in any position. Rejects unknown flags and
/// extra positionals rather than guessing, since this deletes data.
fn parse_delete_args<'a>(tokens: &[&'a str]) -> Result<DeleteArgs<'a>, String> {
    let mut yes = false;
    let mut system = None;
    for &t in tokens {
        match t {
            "-y" | "--yes" => yes = true,
            flag if flag.starts_with('-') => return Err(format!("Unknown flag '{flag}'.")),
            slug if system.is_none() => system = Some(slug),
            extra => return Err(format!("Unexpected argument '{extra}'.")),
        }
    }
    match system {
        Some(system) => Ok(DeleteArgs { system, yes }),
        None => Err("Missing system slug.".into()),
    }
}

/// The engine refuses bundled systems and systems still in use, so those
/// errors surface after confirming; checking first would need a second
/// round trip that could disagree with the delete anyway.
fn handle_systems_delete(args: DeleteArgs, engine: &mut Engine) {
    if !args.yes {
        let question = format!(
            "Delete rule system \"{}\"? This cannot be undone.",
            args.system
        );
        if prompt_yes_no(&question) != Some(true) {
            println!("Not deleted.");
            return;
        }
    }
    let req = Request::SystemsDelete {
        system: args.system,
    };
    let Some(r) = call_or_report::<DeletedSystem>(engine, &req) else {
        return;
    };
    println!("Deleted rule system: {} ({})", r.deleted, r.path);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_slug_with_optional_yes_in_any_position() {
        assert_eq!(
            parse_delete_args(&["homebrew"]),
            Ok(DeleteArgs {
                system: "homebrew",
                yes: false
            })
        );
        for tokens in [&["homebrew", "-y"][..], &["--yes", "homebrew"][..]] {
            assert_eq!(
                parse_delete_args(tokens),
                Ok(DeleteArgs {
                    system: "homebrew",
                    yes: true
                })
            );
        }
    }

    #[test]
    fn rejects_missing_slug_unknown_flags_and_extra_arguments() {
        assert!(parse_delete_args(&[]).is_err());
        assert!(parse_delete_args(&["-y"]).is_err());
        assert!(parse_delete_args(&["homebrew", "--force"]).is_err());
        assert!(parse_delete_args(&["homebrew", "other"]).is_err());
    }
}
