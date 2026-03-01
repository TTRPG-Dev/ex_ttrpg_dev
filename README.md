# ExTTRPGDev

![GitHub watchers](https://img.shields.io/github/watchers/ttrpg-dev/ex_ttrpg_dev?style=social)
![GitHub forks](https://img.shields.io/github/forks/ttrpg-dev/ex_ttrpg_dev?style=social)
![GitHub Repo stars](https://img.shields.io/github/stars/ttrpg-dev/ex_ttrpg_dev?style=social)

[![Hex.pm](https://img.shields.io/hexpm/v/ex_ttrpg_dev)](https://hex.pm/packages/ex_ttrpg_dev)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_ttrpg_dev)](https://hex.pm/packages/ex_ttrpg_dev)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ex_ttrpg_dev)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_ttrpg_dev)](https://github.com/TTRPG-Dev/ex_ttrpg_dev/blob/main/LICENSE)
[![Coverage Status](https://coveralls.io/repos/github/TTRPG-Dev/ex_ttrpg_dev/badge.svg?branch=main)](https://coveralls.io/github/TTRPG-Dev/ex_ttrpg_dev?branch=main)

ExTTRPGDev is a general tabletop role-playing game utility written in Elixir.

## CLI Installation

Pre-built binaries are available on the [releases page](https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases).

### Linux

```bash
curl -fsSL https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases/latest/download/ttrpg_dev_cli_linux.tar.gz | tar -xz
sudo mv ttrpg-dev /usr/local/bin/
```

### macOS (Intel)

```bash
curl -fsSL https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases/latest/download/ttrpg_dev_cli_macos.tar.gz | tar -xz
sudo mv ttrpg-dev /usr/local/bin/
```

### macOS (Apple Silicon)

```bash
curl -fsSL https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases/latest/download/ttrpg_dev_cli_macos_arm.tar.gz | tar -xz
sudo mv ttrpg-dev /usr/local/bin/
```

### Windows

Download `ttrpg_dev_cli_windows.zip` from the [releases page](https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases), extract it, and add `ttrpg-dev.exe` to your `PATH`.

## Usage

`ttrpg-dev` can be used as a one-shot command or as an interactive shell (run with no arguments):

```
ttrpg-dev
```
```
TTRPG Dev — interactive shell
Type `help` for available commands, `exit` to quit.
ttrpg-dev> _
```

### Rolling dice

```
ttrpg-dev roll 3d6
# 3d6: [2, 4, 5]

ttrpg-dev roll 2d6,1d10
# 2d6: [3, 6]
# 1d10: [7]
```

### Rule systems

```
ttrpg-dev systems list
ttrpg-dev systems show dnd_5e_srd
ttrpg-dev systems show dnd_5e_srd --concept-type skill
```

### Characters

```
# Generate a character (prompts to save)
ttrpg-dev characters gen dnd_5e_srd

# Generate and save immediately
ttrpg-dev characters gen dnd_5e_srd --save

# List and inspect saved characters
ttrpg-dev characters list
ttrpg-dev characters show misu_park

# Roll a skill or attribute check for a character
ttrpg-dev characters roll misu_park skill acrobatics
# Acrobatics check: 18 (1d20: 14, bonus: +4)
```

## Development Setup

**Prerequisites**: [asdf](https://asdf-vm.com/) with the `erlang`, `elixir`, and `zig` plugins.

```bash
git clone https://github.com/TTRPG-Dev/ex_ttrpg_dev.git
cd ex_ttrpg_dev
asdf install        # installs Erlang, Elixir, and Zig from .tool-versions
mix deps.get
```

**Run the CLI locally** (no Zig required):

```bash
mix escript
./ttrpg-dev
```

**Build Burrito binaries** (requires Zig):

```bash
./scripts/build_cli.sh
./burrito_out/ttrpg_dev_cli_linux
```

## Contributing

1. Fork the repo and create a branch from `main`
2. Install dependencies: `mix deps.get`
3. Make your changes and add tests
4. Run the test suite: `mix test --umbrella`
5. Run the linter: `mix credo --umbrella`
6. Submit a pull request against `main`

## Library Installation

ExTTRPGDev is [available in Hex](https://hex.pm/packages/ex_ttrpg_dev), the package can be installed
by adding `ex_ttrpg_dev` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_ttrpg_dev, "~> 0.2.1"}
  ]
end
```
