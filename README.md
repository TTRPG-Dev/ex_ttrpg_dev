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
