//! Interactive sub-prompts for yes/no, integer, and option-list input.

use std::borrow::Cow;
use std::io::{self, BufRead};

use reedline::{
    ColumnarMenu, Completer, DefaultValidator, Emacs, KeyCode, KeyModifiers, MenuBuilder, Prompt,
    PromptEditMode, PromptHistorySearch, Reedline, ReedlineEvent, ReedlineMenu, Signal, Span,
    Suggestion, default_emacs_keybindings,
};

pub(crate) fn prompt_integer(question: &str) -> Option<i64> {
    loop {
        print!("{question} ");
        let _ = std::io::Write::flush(&mut io::stdout());
        let stdin = io::stdin();
        match stdin.lock().lines().next() {
            None | Some(Err(_)) => {
                println!();
                return None;
            }
            Some(Ok(line)) => {
                if let Ok(n) = line.trim().parse::<i64>() {
                    return Some(n);
                }
                eprintln!("Please enter a valid number.");
            }
        }
    }
}

pub(crate) fn prompt_yes_no(question: &str) -> Option<bool> {
    print!("(y/n) {question} ");
    let _ = std::io::Write::flush(&mut io::stdout());
    let stdin = io::stdin();
    match stdin.lock().lines().next() {
        None | Some(Err(_)) => {
            println!();
            None
        }
        Some(Ok(line)) => Some(matches!(line.trim().to_lowercase().as_str(), "y" | "yes")),
    }
}

/// Prompts the user to select one value from `options` using a reedline editor
/// with Tab completion. Re-prompts if the entered value is not in the list.
pub(crate) fn prompt_from_options(label: &str, options: &[String]) -> Option<String> {
    struct OptionsCompleter(Vec<String>);

    impl Completer for OptionsCompleter {
        fn complete(&mut self, line: &str, pos: usize) -> Vec<Suggestion> {
            let prefix = &line[..pos];
            self.0
                .iter()
                .filter(|opt| opt.starts_with(prefix))
                .map(|opt| Suggestion {
                    value: opt.clone(),
                    description: None,
                    style: None,
                    extra: None,
                    span: Span { start: 0, end: pos },
                    append_whitespace: false,
                })
                .collect()
        }
    }

    struct SelectionPrompt(String);

    impl Prompt for SelectionPrompt {
        fn render_prompt_left(&self) -> Cow<'_, str> {
            Cow::Borrowed(self.0.as_str())
        }
        fn render_prompt_right(&self) -> Cow<'_, str> {
            Cow::Borrowed("")
        }
        fn render_prompt_indicator(&self, _: PromptEditMode) -> Cow<'_, str> {
            Cow::Borrowed("> ")
        }
        fn render_prompt_multiline_indicator(&self) -> Cow<'_, str> {
            Cow::Borrowed("")
        }
        fn render_prompt_history_search_indicator(&self, _: PromptHistorySearch) -> Cow<'_, str> {
            Cow::Borrowed("")
        }
    }

    let menu = Box::new(ColumnarMenu::default().with_name("selection_menu"));

    let mut keybindings = default_emacs_keybindings();
    keybindings.add_binding(
        KeyModifiers::NONE,
        KeyCode::Tab,
        ReedlineEvent::UntilFound(vec![
            ReedlineEvent::Menu("selection_menu".to_string()),
            ReedlineEvent::MenuNext,
        ]),
    );

    let mut editor = Reedline::create()
        .with_completer(Box::new(OptionsCompleter(options.to_vec())))
        .with_menu(ReedlineMenu::EngineCompleter(menu))
        .with_validator(Box::new(DefaultValidator))
        .with_edit_mode(Box::new(Emacs::new(keybindings)));

    let prompt = SelectionPrompt(label.to_string());

    loop {
        match editor.read_line(&prompt) {
            Ok(Signal::Success(input)) => {
                let trimmed = input.trim().to_string();
                if options.contains(&trimmed) {
                    return Some(trimmed);
                }
                eprintln!("Please select one of the available options (Tab to complete).");
            }
            _ => return None,
        }
    }
}
