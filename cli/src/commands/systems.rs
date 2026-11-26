use super::table::{self, COMMAND_TABLE};
use super::{CmdResult, Failed, call_or_report, fail};
use crate::display;
use crate::engine::{Engine, EngineError};
use crate::prompts::{prompt_loop, prompt_nonempty_string, prompt_yes_no};
use crate::protocol::{
    AddedConceptType, ConceptsList, CopiedSystem, CreatedSystem, DeletedSystem, Request,
    SystemInfo, SystemsList,
};

pub(crate) fn handle_systems(tokens: &[&str], engine: &mut Engine) -> CmdResult {
    if table::dispatch_help(tokens, "systems") {
        return Ok(());
    }
    match tokens {
        ["list"] => handle_systems_list(engine),
        ["show", slug] => handle_systems_show(slug, None, engine),
        ["show", slug, "--concept-type", ct] => handle_systems_show(slug, Some(ct), engine),
        ["create"] => handle_systems_create(engine),
        ["create", extra, ..] => Err(fail(format!(
            "Unexpected argument '{extra}'. Try `systems create --help`."
        ))),
        ["copy", system] => handle_systems_copy(system, None, engine),
        ["copy", system, slug] => handle_systems_copy(system, Some(slug), engine),
        ["copy", ..] => Err(fail(
            "Expected a system and an optional new slug. Try `systems copy --help`.",
        )),
        ["delete", rest @ ..] => match parse_delete_args(rest) {
            Ok(args) => handle_systems_delete(args, engine),
            Err(msg) => Err(fail(format!("{msg} Try `systems delete --help`."))),
        },
        ["concept-type", "add", system] => handle_concept_type_add(system, engine),
        ["concept-type", "add", ..] => Err(fail(
            "Expected one system slug. Try `systems concept-type add --help`.",
        )),
        ["concept-type", ..] => Err(fail(
            "Expected `systems concept-type add <system>`. Try `systems --help`.",
        )),
        [] | ["--help"] => {
            print_systems_usage();
            Ok(())
        }
        [unknown, ..] => Err(fail(format!(
            "Unknown subcommand '{unknown}'. Try `systems --help`."
        ))),
    }
}

fn handle_systems_list(engine: &mut Engine) -> CmdResult {
    let result = call_or_report::<SystemsList>(engine, &Request::SystemsList)?;
    if result.systems.is_empty() {
        println!("No configured systems found.");
    } else {
        println!("Configured Systems:");
        for s in &result.systems {
            println!("  - {s}");
        }
    }
    Ok(())
}

/// Without a concept type, shows the system itself; with one, lists that
/// type's concepts. The two responses have different shapes.
fn handle_systems_show(slug: &str, concept_type: Option<&str>, engine: &mut Engine) -> CmdResult {
    let req = Request::SystemsShow {
        system: slug,
        concept_type,
        concept_id: None,
    };
    match concept_type {
        None => display::print_system_info(call_or_report::<SystemInfo>(engine, &req)?),
        Some(_) => display::print_concepts_list(&call_or_report::<ConceptsList>(engine, &req)?),
    }
    Ok(())
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
        version: prompt_optional("Version (optional): ")?,
        publisher: prompt_optional("Publisher (optional): ")?,
        family: prompt_optional("Family (optional): ")?,
        series: prompt_optional("Series (optional): ")?,
    })
}

/// The slug is derived from the name, collisions refused, and a blank
/// version defaulted, by the engine; the CLI doesn't repeat those rules,
/// and reports the version it stored rather than predicting it.
///
/// Every error the engine can return for what this command sends is
/// resolved through the name: its slug is taken, empty or too long, or
/// something that isn't a system occupies its directory. So on one the
/// user is asked for another name, keeping their other answers. The
/// occupied case can also be fixed by removing that directory and entering
/// the *same* name again, so the retry must not refuse an unchanged name.
/// Transport errors (the engine died) end the command instead, as does
/// declining to retry: the system asked for wasn't created, so the command
/// failed.
fn handle_systems_create(engine: &mut Engine) -> CmdResult {
    let Some(mut a) = prompt_create_answers() else {
        println!("Not created.");
        return Ok(());
    };
    loop {
        let req = Request::SystemsCreate {
            name: &a.name,
            version: a.version.as_deref(),
            publisher: a.publisher.as_deref(),
            family: a.family.as_deref(),
            series: a.series.as_deref(),
        };
        match engine.call::<_, CreatedSystem>(&req) {
            Ok(r) => {
                print_created(&r);
                return Ok(());
            }
            Err(EngineError::ErrorResponse(msg)) => eprintln!("Error: {msg}"),
            Err(e) => return Err(fail(format!("Error: {e}"))),
        }
        match prompt_optional("Try another name (blank to cancel): ") {
            Some(Some(name)) => a.name = name,
            _ => {
                println!("Not created.");
                return Err(Failed);
            }
        }
    }
}

fn print_created(r: &CreatedSystem) {
    println!();
    match &r.version {
        Some(v) => println!("Created rule system {} version {v}: {}", r.created, r.path),
        None => println!("Created rule system {}: {}", r.created, r.path),
    }
}

/// The engine picks the slug when none is given, names the copy, and
/// refuses a taken or malformed slug; the CLI repeats none of those rules.
fn handle_systems_copy(system: &str, slug: Option<&str>, engine: &mut Engine) -> CmdResult {
    let req = Request::SystemsCopy { system, slug };
    let r = call_or_report::<CopiedSystem>(engine, &req)?;
    println!(
        "Copied {} to {} (\"{}\"): {}",
        r.copied, r.created, r.name, r.path
    );
    Ok(())
}

/// The engine derives the ID, refuses a duplicate, an unusable ID, an
/// unknown system or a bundled one; the CLI repeats none of those rules.
///
/// Unlike `systems create`, a refusal ends the command rather than asking
/// for another name: some refusals (unknown or bundled system) no name can
/// fix, and the engine's errors don't say which kind they are.
fn handle_concept_type_add(system: &str, engine: &mut Engine) -> CmdResult {
    let Some(name) = prompt_nonempty_string("Concept type name:") else {
        println!("Not added.");
        return Ok(());
    };
    let Some(display_template) = prompt_optional("Display template (optional): ") else {
        println!("Not added.");
        return Ok(());
    };
    let req = Request::SystemsConceptTypeAdd {
        system,
        name: &name,
        display_template: display_template.as_deref(),
    };
    let r = call_or_report::<AddedConceptType>(engine, &req)?;
    println!();
    println!("Added concept type \"{}\" to {}", r.added, r.path);
    Ok(())
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
fn handle_systems_delete(args: DeleteArgs, engine: &mut Engine) -> CmdResult {
    if !args.yes {
        let question = format!(
            "Delete rule system \"{}\"? This cannot be undone.",
            args.system
        );
        if prompt_yes_no(&question) != Some(true) {
            println!("Not deleted.");
            return Ok(());
        }
    }
    let req = Request::SystemsDelete {
        system: args.system,
    };
    let r = call_or_report::<DeletedSystem>(engine, &req)?;
    println!("Deleted rule system: {} ({})", r.deleted, r.path);
    Ok(())
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
