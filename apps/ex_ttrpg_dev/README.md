# ExTTRPGDev

[![Hex.pm](https://img.shields.io/hexpm/v/ex_ttrpg_dev)](https://hex.pm/packages/ex_ttrpg_dev)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_ttrpg_dev)](https://hex.pm/packages/ex_ttrpg_dev)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ex_ttrpg_dev)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_ttrpg_dev)](https://github.com/TTRPG-Dev/ex_ttrpg_dev/blob/main/LICENSE)

ExTTRPGDev is a general tabletop role-playing game utility library for Elixir:
rule-system loading/evaluation and character generation/persistence, driven by
TOML-defined rule systems rather than hardcoded game rules.

This library also powers the `ttrpg-dev` CLI; see the
[project repository](https://github.com/TTRPG-Dev/ex_ttrpg_dev) for the CLI and
for contributing.

## Installation

Add `ex_ttrpg_dev` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ttrpg_dev, "~> 0.15"}
  ]
end
```

## Usage

### Rule systems

Rule systems are TOML-defined directed acyclic graphs of concepts (abilities,
skills, classes, etc.). Load one, then evaluate it against a character's
generated (rolled) base values to resolve every derived node:

```elixir
system = ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd")

attrs = ~w[strength dexterity constitution wisdom intelligence charisma]
generated = Map.new(attrs, &{{"ability", &1, "base_score"}, 10})

{:ok, resolved} = ExTTRPGDev.RuleSystem.Evaluator.evaluate(system, generated)
resolved[{"ability", "strength", "modifier"}]
#=> 0
```

`ExTTRPGDev.RuleSystems.list_systems/0` lists bundled and user-defined
("local") systems available to load.

### Characters

Characters hold generated values, active effects (equipped items, feats,
etc.), and metadata, and are persisted as JSON:

```elixir
alias ExTTRPGDev.Characters
alias ExTTRPGDev.Characters.{Character, Metadata}

character = %Character{
  name: "Doctest Character",
  generated_values: %{},
  metadata: %Metadata{slug: "doctest_character", rule_system: "dnd_5e_srd"}
}

Characters.save_character!(character)
Characters.character_exists?(character)
#=> true
```

See `ExTTRPGDev.Characters` for the full API — generation, leveling,
advancement, and preparation-managed inventory are all exposed there.

## Documentation

Full API documentation is available on [HexDocs](https://hexdocs.pm/ex_ttrpg_dev).

## License

Released under the AGPL-3.0-or-later license. See [LICENSE](LICENSE).
