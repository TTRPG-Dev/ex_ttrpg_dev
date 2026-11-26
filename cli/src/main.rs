mod commands;
mod display;
mod engine;
mod history;
mod one_shot;
mod prompts;
mod protocol;
mod repl;

/// With no arguments, starts the interactive REPL; with arguments, runs
/// them as a single command (see `one_shot`) and exits with its status.
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        repl::run();
    } else {
        std::process::exit(one_shot::run(&args));
    }
}
