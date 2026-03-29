pub(crate) fn print_help() {
    println!(
        r#"
Commands:
  roll <dice>                                            Roll dice, e.g. roll 3d6, 1d20
  systems list                                           List configured rule systems
  systems show <system>                                  Show system info
  systems show <system> --concept-type <t>               List concepts of a type
  characters gen <system>                                Generate a character
  characters list                                        List saved characters
  characters list --system <system>                      List characters for a system
  characters show <slug>                                 Show a saved character
  characters delete <slug>                               Delete a saved character
  characters delete-all                                  Delete all characters (confirms each)
  characters delete-all --yes                            Delete all characters without confirmation
  characters delete-all --system <system>                Delete all characters for a system
  characters roll <slug> <type> <concept>                Roll for a character concept
  characters award <slug> <award_id> <value>             Award something to a character
  characters award <slug> level_up                       Advance to next level (milestone leveling)
  characters choices <slug>                              Show pending progression choices
  characters resolve_choice <slug>                       Interactively resolve a pending choice
  characters resolve_choice <slug> --random-resolve      Randomly resolve all pending choices
  characters inventory <slug>                            Show a character's inventory
  characters inventory add <slug> <type> <id>            Add an item to inventory
  characters inventory add <slug> <type> <id> --equipped Add an item and equip it
  characters inventory set <slug> <index> <field> <val>  Update an inventory item field
  help                                                   Show this help
  exit / quit                                            Exit
"#
    );
}
