# Contributing

Hi there! If you're looking to contribute, you're in the right place :) also, thank you in advance!

## Things to know

By contributing to this repository, you are expected to know and follow the rules of laid out in our [Code of Conduct][conduct].

**Working on your first Pull Request?**
[How to Contribute to an Open Source Project on GitHub][egghead]


## How do

* Project setup?
	[We've got you covered!](#project-setup)

* Found a bug?
	[Report it so we can start working on a fix!][bugs]

* Want a new feature?
	[Shweeet, lay it out for us!][feature-request]

* Patched a bug?
	[Make a PR!][new-pr]


## Project setup

1. Fork and clone the repo
2. [Install Erlang/OTP & Elixir][Installing Erlang/OTP & Elixir]
3. Install project dependencies with `mix deps.install`
4. Create a branch for your PR

### Installing Erlang/OTP & Elixir

This project is built with Erlang/OTP & Elixir, the specific versions for these languages are outlined in [.tool-versions][tool-versions].
We use [asdf][asdf] for managing our language versions. To setup asdf, please follow their [getting started][asdf-setup].
With asdf installed, run `asdf install` from the project root.

**Note**: This is just our recommended way to install Erlang/OTP & Elixir, feel free to go your own way.
The official [Elixir Install Guide][elixir-install] lists a number of different ways to install Elixir


### Commit conventions

Commits should be as small as possible, with exceptions for large sweeping changes required by lint rule changes, package updates, etc.
Commit messages should be clear, as we additionally recommend (but don't require) that commits include descriptions describing: why the change is necessary, any forseen issues, and paths intentionally not taken (and why).



[asdf]: https://asdf-vm.com/
[asdf-setup]: https://asdf-vm.com/guide/getting-started.html
[bugs]: https://github.com/QMalcolm/ex_ttrpg_dev/issues/new?assignees=&labels=&template=bug_report.md
[conduct]: CODE_OF_CONDUCT.md
[egghead]: https://app.egghead.io/playlists/how-to-contribute-to-an-open-source-project-on-github
[elixir-install]: https://elixir-lang.org/install.html
[feature-request]: https://github.com/QMalcolm/ex_ttrpg_dev/issues/new?assignees=&labels=&template=feature_request.md
[new-pr]: https://github.com/QMalcolm/ex_ttrpg_dev/compare
[tool-versions]: .tool-versions
