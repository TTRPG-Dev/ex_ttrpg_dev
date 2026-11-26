# Changelog

All notable changes to `ex_ttrpg_dev` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Tracking starts at 0.15.0; earlier releases are not covered here.
## [0.16.0] - 2026-11-26

### Added

- Parse an optional library_requirement from module.toml

- Add Versioning helpers for canonical rule system content

- Mark dnd_5e_srd as canonical content for lib 0.15.x

- Record the rule system's content version on generated characters

- Query which saved characters depend on a rule system version

- Let host applications report rule system dependents

- Decide whether a canonical rule system release may be applied

- Write a rule system Source back to a TOML directory

- Define the RuleSystem.Store behaviour for rule system content

- Add a filesystem Store adapter under local_system_configs

- Seed and sync bundled systems into the rule system store

- Load a rule system at a character's recorded version

- List installed rule systems with their stored metadata

- Clone a rule system under a new slug

- Update a modifiable rule system, refusing non-modifiable ones

- Log no-op rule system sync decisions at debug level

- Make the character store adapter configurable (#164)

- Make the rule system store adapter configurable (#165)

- Accept slugs in any script, NFC-normalised and length-capped

- Characters_depending_on/1 finds a system's characters at any version

- RuleSystems.delete_system/1 removes a modifiable rule system (#95)

- RuleSystems.create_system/1 scaffolds an empty local system (#94)

- Clone_system/3 takes an optional :name for the clone

- RuleSystems.fetch_module/2 reads a system's metadata without loading it

- RuleSystems.add_concept_type/2 declares a concept type (#98)


### Changed

- Return plain :ok from validate_choice_options/1

- Extract RuleModule.from_map/1's validation and parsing

- Use reduce_while consistently in InventoryRules parsing

- Have InventoryItem.set_field/4 reuse fetch_schema_field/2

- Derive current level from the level node's own mapping steps

- Give RuleModule a t() type

- Split Loader into reading a Source and building from it

- Load and list rule systems through the store

- Extract installed-entry resolution from load_system

- Clarify the filesystem store's nested-version listing

- Encode the store's .store.toml sidecar with TomlElixir

- Rename Characters.Store to Characters.Store.FileSystem

- Define the Characters.Store behaviour over its adapters

- Move the store slug rule into a shared Slug module

- Take the match rule as a predicate when finding dependents

- Separate collecting results from choosing what to ask

- Share the store write of create_system and clone_system

- Let Editing's field validation serve more than [module]

- Let a library edit of a system refuse from inside the edit


### Documentation

- Add library-specific README for ex_ttrpg_dev

- Add CHANGELOG for ex_ttrpg_dev

- Fix Graph.build moduledoc to match its returned cycle error

- Document Characters.concept_options/4

- Document the unified rule system store, sync, and cloning

- Spell out what Store.put/3's :already_exists must cover (#193)

- Stop saying character_file_path!/1 never raises

- Note that characters saved under old-style slugs are no longer listed

- Note that rule systems with slugs over 200 bytes are no longer listed


### Fixed

- Include LICENSE in ex_ttrpg_dev Hex package

- Render README and CHANGELOG as hexdocs pages

- Don't crash on an explicit "options" => nil choice def

- Avoid O(n^2) effects accumulation while loading concept files

- Give Character.t() real field types

- Skip nested versions whose module.toml disagrees with their directory

- Fail listing the store when a slug directory can't be read

- Reject slugs that could escape the characters directory (#184)

- Make slugify/1 produce only valid slugs (#184)

- Save character files atomically (#183)

- Keep non-ASCII letters and digits in derived system slugs (#94)

- Refuse over-long system slugs with their own error (#94)

- Tell an occupied slug apart from a taken one (#193)

- Don't report :slug_taken when the occupied-slug recheck can't list (#193)

- Don't list a decomposed character file its slug can't load

- Strip a character file's .json extension only once

- Keep non-ASCII rule systems listed on macOS HFS+

- Don't delete another writer's temp file on a name clash

- Report where a character went when an overwrite can't restore it

- Don't fail an overwrite whose old file is already gone

- Hold clone_system's new slug to the form create_system requires

- Clone_system/3 refuses a non-string slug instead of raising

- Refuse a concept that isn't a table instead of crashing the load


## [Unreleased]

### Documentation

- Add library-specific README for ex_ttrpg_dev
- Add CHANGELOG for ex_ttrpg_dev

### Fixed

- Include LICENSE in ex_ttrpg_dev Hex package
- Render README and CHANGELOG as hexdocs pages

Prior releases (up through 0.15.0) aren't itemized here; see the
[GitHub releases page](https://github.com/TTRPG-Dev/ex_ttrpg_dev/releases)
and `git log` for that history.
