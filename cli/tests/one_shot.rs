//! Integration tests for one-shot mode: `ttrpg-dev <command> [args...]`
//! run as a plain subprocess (no PTY), checking stdout, stderr and the exit
//! status the way a script would.
//!
//! Like `workflow.rs`, these use the real engine through the dev wrapper at
//! `target/debug/ttrpg-dev-engine`, and saved characters land in
//! `local_characters/` at the repo root, so tests clean up what they save.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::Mutex;

// Two BEAM instances sharing build artefacts corrupt each other (see
// `workflow.rs`), so every test that starts the engine holds this lock.
static ENGINE_LOCK: Mutex<()> = Mutex::new(());

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

/// A fresh, empty directory under the system temp dir, unique to `name`
/// and this test process.
fn temp_dir(name: &str) -> PathBuf {
    let dir =
        std::env::temp_dir().join(format!("ttrpg-dev-one-shot-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn command(bin: &Path, args: &[&str]) -> Command {
    let mut cmd = Command::new(bin);
    cmd.args(args).stdin(Stdio::null());
    cmd
}

/// Runs `ttrpg-dev` with `args` and stdin from `/dev/null` (so it has no
/// terminal), holding the engine lock.
fn run(args: &[&str]) -> Output {
    run_command(command(Path::new(env!("CARGO_BIN_EXE_ttrpg-dev")), args))
}

fn run_command(mut cmd: Command) -> Output {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    cmd.output().expect("failed to run ttrpg-dev")
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn saved_slug(out: &str) -> String {
    let start = out.find("Saved as '").expect("no 'Saved as' line") + "Saved as '".len();
    let len = out[start..].find('\'').unwrap();
    out[start..start + len].to_string()
}

fn cleanup_character(slug: &str) {
    let _ = fs::remove_file(
        repo_root()
            .join("local_characters")
            .join(format!("{slug}.json")),
    );
}

#[test]
fn a_successful_command_prints_to_stdout_and_exits_0() {
    let o = run(&["roll", "3d6"]);
    assert_eq!(o.status.code(), Some(0), "stderr: {}", stderr(&o));
    assert!(stdout(&o).starts_with("3d6: ["), "stdout: {}", stdout(&o));
    assert_eq!(stderr(&o), "");
    // No REPL banner in one-shot mode.
    assert!(!stdout(&o).contains("interactive shell"));
}

#[test]
fn an_engine_error_goes_to_stderr_and_exits_1() {
    let o = run(&["characters", "show", "nobody_by_this_slug"]);
    assert_eq!(o.status.code(), Some(1));
    assert!(stderr(&o).starts_with("Error:"), "stderr: {}", stderr(&o));
    assert_eq!(stdout(&o), "");
}

#[test]
fn an_unknown_command_exits_1() {
    let o = run(&["frobnicate"]);
    assert_eq!(o.status.code(), Some(1));
    assert!(
        stderr(&o).contains("Unknown command"),
        "stderr: {}",
        stderr(&o)
    );
    assert_eq!(stdout(&o), "");
}

#[test]
fn bad_arguments_exit_1() {
    let o = run(&["characters", "copy"]);
    assert_eq!(o.status.code(), Some(1));
    assert!(
        stderr(&o).contains("characters copy --help"),
        "stderr: {}",
        stderr(&o)
    );
}

#[test]
fn help_prints_the_same_help_as_the_repl() {
    let o = run(&["help"]);
    assert_eq!(o.status.code(), Some(0));
    assert!(stdout(&o).contains("Commands:"));
    assert!(stdout(&o).contains("characters gen"));

    let o = run(&["characters", "gen", "--help"]);
    assert_eq!(o.status.code(), Some(0));
    assert_eq!(stdout(&o), "Usage: characters gen <system> [--save]\n");
}

#[test]
fn gen_save_saves_and_display_flags_apply() {
    let o = run(&["characters", "gen", "dnd_5e_srd", "--save"]);
    assert_eq!(o.status.code(), Some(0), "stderr: {}", stderr(&o));
    let slug = saved_slug(&stdout(&o));

    let succinct = run(&["characters", "show", &slug, "--succinct"]);
    let verbose = run(&["characters", "show", &slug, "--verbose"]);
    cleanup_character(&slug);

    assert_eq!(
        succinct.status.code(),
        Some(0),
        "stderr: {}",
        stderr(&succinct)
    );
    assert_eq!(
        verbose.status.code(),
        Some(0),
        "stderr: {}",
        stderr(&verbose)
    );
    assert!(stdout(&succinct).contains(&slug));
    assert!(
        stdout(&verbose).len() > stdout(&succinct).len(),
        "--verbose should show more than --succinct"
    );
}

#[test]
fn one_shot_mode_does_not_write_the_history_file() {
    let home = temp_dir("history");
    let mut cmd = command(Path::new(env!("CARGO_BIN_EXE_ttrpg-dev")), &["roll", "1d6"]);
    cmd.env("HOME", &home);
    let o = run_command(cmd);
    assert_eq!(o.status.code(), Some(0), "stderr: {}", stderr(&o));
    assert!(!home.join(".ttrpg_dev_history").exists());
    let _ = fs::remove_dir_all(&home);
}

#[test]
fn an_engine_that_fails_to_start_exits_1() {
    // A copy of the binary with no engine beside it and none on PATH.
    let dir = temp_dir("no-engine");
    let bin = dir.join("ttrpg-dev");
    fs::copy(env!("CARGO_BIN_EXE_ttrpg-dev"), &bin).unwrap();
    let mut cmd = command(&bin, &["roll", "1d6"]);
    cmd.env("PATH", &dir);
    let o = cmd.output().unwrap();
    let _ = fs::remove_dir_all(&dir);

    assert_eq!(o.status.code(), Some(1));
    assert!(
        stderr(&o).contains("Failed to start engine"),
        "stderr: {}",
        stderr(&o)
    );
    assert_eq!(stdout(&o), "");
}
