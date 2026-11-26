# D&D 5e SRD Coverage Audit

This document tracks how much of the D&D 5e System Reference Document is
encoded in the bundled `dnd_5e_srd` rule system
(`apps/ex_ttrpg_dev/priv/system_configs/dnd_5e_srd/`), and — where something
is *not* encoded — whether that is because the content simply hasn't been
written yet, or because `ex_ttrpg_dev` can't express it today.

The second category is the important one: each library gap (`G1`, `G2`, …) is
written so it can be lifted into a GitHub issue.

## Source

The audit was done against a plain-text extraction of **SRD 5.0** (the text's
own page footers read "System Reference Document 5.0"). Line ranges below refer
to that file (`dnd_5e_srd.txt`, 66,952 lines). The extraction comes from a PDF,
so tables are flattened column-by-column and OCR substitutes `I`/`l` and `1`/`l`
freely (`ld6` for `1d6`); every number encoded from it should be checked
against the prose, not just the flattened table.

### Spells not in SRD 5.0 were removed

The system used to ship 326 spells; the SRD 5.0 text defines 304. The other
22 (Animal Friendship, Arcane Gate, Beast Sense, Blade Ward, Branding Smite,
Compulsion, Counterspell, Druidcraft, Eldritch Blast, Feign Death, Find
Familiar, Fire Bolt, Friends, Goodberry, Guardian of Faith, Hellish Rebuke,
Hunter's Mark, Poison Spray, Power Word Heal, Spare the Dying, Tsunami,
Vicious Mockery) came from SRD 5.1 or the Player's Handbook and were removed
in system version 2.0.0. The bundled system ships SRD 5.0 Open Game Content
only.

Several SRD 5.0 features *name* spells the document never defines: Guardian
of Faith in the Life Domain and Oath of Devotion spell lists, *hellish
rebuke* in Tiefling Infernal Legacy, *eldritch blast* in warlock invocation
prerequisites, *find familiar* in Pact of the Chain. Those references are
omitted from the encoding rather than filled in from another source.

## Status legend

| Status | Meaning |
| --- | --- |
| **Encoded** | Present and mechanically wired. |
| **Partial** | Some of it is encoded; the rest is listed. |
| **Encodable** | Not encoded yet, but the library can express it today. Content work only. |
| **Gap** | Needs library work first. Linked to a `G` entry below. |
| **Reference** | Descriptive content with no character mechanics (lore, GM procedure). Could be stored as metadata-only concepts; low priority. |

## Coverage by section

| SRD section | Lines | Status | Notes |
| --- | --- | --- | --- |
| Legal / OGL | 1–244 | n/a | |
| Races (9 races, 7 subraces) | 245–1055 | Partial | Ability increases, speed, darkvision, languages, weapon/tool proficiencies, resistances encoded. See [Races](#races). |
| Classes (12 classes, 1 subclass each) | 1056–12649 | Partial | Hit points, proficiencies, saves, skills, starting equipment, ASI slots, spellcasting encoded. Class *features* largely absent. See [Classes](#classes). |
| Multiclassing | 12650–13615 | Gap | G2. |
| Alignment | 13616–13727 | Encodable | Concept type + character choice. Nothing in the SRD keys mechanics off it for PCs. |
| Languages | 13728–13921 | Encoded | |
| Inspiration | 13922–13975 | Gap | G7 (play state: a boolean the GM awards and the player spends). |
| Backgrounds (Acolyte only) | 13976–14236 | Partial | Skills (with proficiency bonus), languages, equipment encoded. Starting gold (15 gp) and the personality trait / ideal / bond / flaw d6–d8 tables are not — G13. |
| Equipment: wealth, armor, weapons, gear, tools | 14237–17540 | Partial | All armor, weapons, tools encoded. Starting wealth by class (e.g. `5d4 × 10 gp`) is G13. Weapon damage rolls are G10. Encumbrance is Encodable (weights exist; needs a carried-weight accumulator). |
| Mounts, vehicles, trade goods | 17541–17965 | Partial | Trade goods encoded. Mounts / tack / vehicles are Encodable as equipment. Mount stat blocks are G11. |
| Expenses, lifestyle, food, services | 17966–18440 | Encodable | Equipment-like price lists. |
| Feats (Grappler only) | 18441–18492 | Encoded | Prerequisite (Str 13) encoded; the feat's benefits (advantage vs grappled, pin) are G5. |
| Using Ability Scores | 18493–19682 | Encoded | Modifiers, proficiency bonus, checks, saves, passive checks, carrying capacity formula is Encodable. Advantage/disadvantage is G5. |
| Adventuring: time, movement, environment | 19683–20210 | Reference / Gap | Travel pace, falling, suffocation, vision — procedure. Exhaustion-producing hazards are G7. |
| Resting | 20211–20278 | Gap | G7 (spending hit dice, recovering resources). |
| Between adventures (downtime) | 20279–20470 | Reference | |
| Combat | 20471–21881 | Partial / Gap | Initiative and AC encoded. Attack/damage rolls G10; HP/death saves/temp HP G7; conditions G7; cover and two-weapon fighting G5/G10. |
| Spellcasting rules | 21882–22487 | Encoded | Slots, known/prepared, save DC, attack bonus. Multiclass slot table G2. Per-source spellcasting ability G14. |
| Spell lists | 22488–24131 | Encoded | `classes` on each spell. |
| Spell descriptions (304) | 24132–35812 | Partial | All 304, and only these, are encoded. Name, level, school, casting time, range, components, duration, concentration, ritual, classes encoded. Description text, material component text, "at higher levels" scaling, damage/save info are Encodable as metadata. Cantrip damage scaling is Encodable as a mapping node. |
| Appendix: Conditions (14 + exhaustion) | 35813–36062 | Encodable / Gap | Encodable as reference concepts; *applying* a condition to a character is G7. |
| Appendix: Pantheons | 36063–37114 | Reference | |
| Appendix: Planes of existence | 37115–37399 | Reference | |
| Traps | 37400–38021 | Reference | |
| Diseases | 38022–38189 | Reference / Gap | Effects on a character (e.g. sewer plague exhaustion) are G7. |
| Madness | 38190–38557 | Reference / Gap | Random tables G13; applied effects G7. |
| Objects | 38558–38723 | Reference | Object AC/HP tables. |
| Poisons | 38724–39040 | Encodable / Gap | Purchasable as equipment (Encodable); effects G7. |
| Magic items A–Z (~240) | 39041–46959 | Encodable / Gap | Name, type, rarity, attunement Encodable as equipment metadata. Flat bonuses (`+1` armor, Ring/Cloak of Protection) Encodable via `when = "item.equipped"`. "Set a score to N" items (Gauntlets of Ogre Power, Belt of Giant Strength, Amulet of Health) Encodable with `max(0, N - score)`. Attunement limit is G9. Charges are G7. |
| Sentient items, artifacts | 46960–47362 | Reference | |
| Monsters (rules + ~210 stat blocks) | 47363–61763 | Gap | G11. |
| Appendix: Misc. creatures (~97) | 61764–65798 | Gap | G11. |
| Appendix: NPCs (21) | 65799–66952 | Gap | G11. |

## Races

| Trait | Status |
| --- | --- |
| Ability score increases, speed, darkvision, languages | Encoded |
| Dwarf: poison resistance, combat training, tool choice | Encoded |
| Hill Dwarf: Dwarven Toughness (+1 HP per level) | Encoded |
| Elf: Keen Senses (Perception proficiency) | Encoded |
| High Elf: wizard cantrip (Intelligence-based) | Partial — the choice is Encodable; casting it with Int while a class casts with another ability is G14 |
| Half-Elf: +1 to two other abilities, two skills (Skill Versatility) | Encoded as choices. "Two *different* abilities" is not enforced — G3 |
| Half-Orc: Menacing (Intimidation proficiency) | Encoded |
| Half-Orc: Relentless Endurance, Savage Attacks | G7, G10 |
| Dragonborn: Draconic Ancestry (damage type, resistance, breath weapon DC and dice) | Encoded (`draconic_ancestry` concept type) |
| Tiefling: Infernal Legacy (thaumaturgy; *hellish rebuke* at 3rd, *darkness* at 5th) | G1 (level-gated grants), G14 |
| Fey Ancestry, Brave, Gnome Cunning, Dwarven Resilience (advantage) | G5 |
| Lucky (reroll 1s), Stonecunning / Artificer's Lore (conditional double proficiency) | G5 |
| Size, age, alignment tendencies | Encodable as metadata (no mechanics) |

## Classes

Every class-table column that is a number derived from level is now encoded
as a `mapping` or `formula` node on the class concept. Class concepts are
only displayed while active, so these appear only for characters of that class.
All of them key off *character* level, which is correct for a single-class
character and wrong for a multiclassed one (G2) — the same limitation the
existing HP and ASI encodings already have.

| Class | Encoded | Still open |
| --- | --- | --- |
| Barbarian | Rages per day (and unlimited at 20th), rage damage, Brutal Critical dice, Unarmored Defense (Con, shield allowed), Fast Movement (+10 ft unless in heavy armor), Primal Champion | Rage itself as a toggled state (G7, G12); Reckless Attack / Danger Sense (G5); Berserker features (G7) |
| Bard | Bardic Inspiration die and uses (Cha mod, min 1), Song of Rest die | Jack of All Trades (Encodable after the skill proficiency restructure — see note); Expertise limited to proficient skills (G3); Magical Secrets cross-list choice (G3); level-gated feature list (G1) |
| Cleric | Channel Divinity uses, Destroy Undead CR | Life Domain always-prepared spells exist already; Disciple of Life healing bonus is G10 |
| Druid | Wild Shape max CR, swim/fly unlock | Wild Shape replaces stats with a beast's (G11, G12) |
| Fighter | Action Surge uses, Indomitable uses, Extra Attack count, Second Wind healing bonus, Champion crit range | Remarkable Athlete (needs the skill restructure); Fighting Style choice: Defense (+1 AC in armor) Encodable; Archery / Dueling / Great Weapon / Protection / Two-Weapon need G10 |
| Monk | Martial Arts die, Ki points, Ki save DC, Unarmored Defense (Wis, no shield), Unarmored Movement | Martial Arts using Dex for monk weapons (G10); Ki spending (G7) |
| Paladin | Lay on Hands pool, Divine Sense uses, Aura of Protection (+Cha to all saves), aura range | Divine Smite (G10); Channel Divinity Oaths (G7) |
| Ranger | Favored Enemy / Natural Explorer counts | Favored enemy creature-type choice (Encodable as concept type), Hunter's choices at 3/7/11/15 (G1) |
| Rogue | Sneak Attack dice | Expertise (G3), Reliable Talent (minimum roll — G5), Evasion / Uncanny Dodge (G5/G7) |
| Sorcerer | Sorcery points, Metamagic known count, Draconic Resilience (+1 HP/level, AC 13 + Dex unarmored) | Metamagic options as a progression (Encodable), Dragon Ancestor choice (Encodable, can reuse `draconic_ancestry`), Elemental Affinity (G10) |
| Warlock | Invocations known count, Mystic Arcanum levels | Invocation prerequisites by pact / spell (G3), Pact Boon choice (Encodable) |
| Wizard | Arcane Recovery slot levels | Spell Mastery / Signature Spells (G7) |

**Note — skill proficiency restructure.** Today proficiency is contributed
straight into `skill('x').modifier`. Jack of All Trades and Remarkable Athlete
need to know whether a skill is *already* proficient, and Expertise needs to
double it. A content-only fix is to add a `proficiency` accumulator per skill
(0 = none, 1 = proficient, 2 = expertise) and make
`modifier = ability mod + floor(proficiency × PB)`. Half-proficiency then
contributes `floor(PB / 2) × (1 - min(1, proficiency))`. This is Encodable
but touches every skill-granting choice in the system, so it is its own
change.

## Library bugs found while encoding

These are defects in existing behaviour, not missing features. Each should be
filed as a bug.

### B1. Effect `when` formulas don't add DAG edges

`Graph.add_effect_edges/3` adds edges for the node references in an effect's
`value`, but not for those in its `when`. An effect gated on another node
(`when = "character_trait('armor_worn').body == 0"`) can therefore be
evaluated before that node is resolved. It works today only because every
`when` in the bundled system is `item.equipped`, which references no nodes.
This system writes gating into `value` formulas instead
(`x * (1 - min(1, worn))`) to stay clear of the bug.

### B2. Numeric `contributes_value` crashes the loader

The Loader documents a choice's `contributes_value` as *any* value, but an
integer (`contributes_value = 1`) reaches `Expression.extract_refs/1`, which
only accepts strings, and the system fails to load with a
`FunctionClauseError`. Workaround in this system: `contributes_value = "1"`.

## Library gaps

Each entry is written to be filed as an issue.

### G1. Level-gated grants

**Problem.** Most class and subclass features, and some racial traits
(Tiefling's Infernal Legacy), are granted automatically when the character
reaches a level. The library has no "grant this concept / effect when
expression X becomes true" mechanism. Effects support `when`, so *numeric*
effects can be gated, but concepts (a feature with a name and description
that should appear on the sheet) cannot.

**Wanted.** A way for a concept to declare child grants with a condition, e.g.
`grants = [{type = "class_feature", id = "rage", when = "class_level('barbarian') >= 1"}]`,
with granted concepts becoming active (and displayed) only while the condition
holds.

**Unblocks.** Every class's feature list; subclass features; Infernal Legacy.

### G2. Per-class levels (multiclassing)

**Problem.** The system has one `character_level`. Multiclassing needs a level
per class: hit dice, class features, and class-table columns key off class
level; proficiency bonus and XP key off total level; multiclass spell slots
use a weighted sum (full + ½ half + ⅓ third casters); only a subset of
proficiencies is granted when taking a second class; prerequisites (13 in the
primary ability of both classes) gate the choice.

**Wanted.** A notion of class levels (a level-up decision records *which*
class gained the level) and an expression to reference them, with total level
derived from their sum.

### G3. Choice constraints that depend on character state

**Problem.** Choices take a static `options` list or a level/class filter.
Several SRD choices are constrained by what the character already has:
Expertise (only skills you're proficient in), Half-Elf ability increases
(two *different* abilities), Magical Secrets (any class's list), warlock
invocations (prerequisites such as "Pact of the Blade feature" or "*eldritch
blast* cantrip").

**Wanted.** Choice options filtered by an expression over the candidate and
the character (e.g. `option_when = "skill(option).proficiency >= 1"`), plus
a "distinct from sibling choice" constraint, plus prerequisites on concepts
that reference other active concepts rather than only numeric nodes.

### G4. Spell replacement on level-up

Already tracked as **#92**.

### G5. Roll modifiers: advantage, rerolls, minimums, crit range

**Problem.** A `roll` concept is `dice + bonus_field`. A large share of the
SRD's character mechanics are roll modifiers rather than bonuses: advantage /
disadvantage (Fey Ancestry, Brave, Danger Sense, Reckless Attack, heavy armor
stealth disadvantage), rerolling (Halfling Lucky, Great Weapon Fighting),
minimum results (Reliable Talent), expanded crit range (Champion), and
conditional bonuses (Stonecunning applies only to stonework).

**Wanted.** Effects that target a *roll* rather than a node, carrying a
modifier kind (advantage, disadvantage, reroll-below, minimum, crit-range)
and an optional situational tag so callers can show them as "applies when…".

### G6. Dice-valued nodes

**Problem.** Nodes evaluate to numbers or booleans. Martial Arts die, Bardic
Inspiration die, Sneak Attack dice, Brutal Critical, breath weapon damage are
all dice. Today they can only be encoded as two numbers (count and size) and
re-assembled by the reader.

**Wanted.** A dice value type (`3d6`) that formulas can build
(`dice(ceil(level / 2), 6)`) and roll definitions can roll.

### G7. Play state and resources

**Problem.** A character is a build (decisions, inventory, rolled values,
effects). The SRD's table-time state has nowhere to live: current and
temporary hit points, hit dice spent, death saves, expended spell slots,
limited-use features (Rage, Ki, Action Surge, Channel Divinity, item
charges) with short/long-rest recovery, conditions applied to the character,
exhaustion level, inspiration, and toggled states (raging, wild-shaped).

**Wanted.** A resource model: a node declares a maximum, the character
stores current usage, and named recovery events (short rest, long rest, dawn)
reset it. Conditions and toggles as character-applied concepts whose effects
are active while applied.

**Note.** This may belong in a host application rather than the library; the
issue should decide that boundary explicitly.

### G8. Conditional expressions

**Problem.** The expression grammar has comparisons and boolean logic but no
way to turn a boolean into a number, and no `if`. Gated values are written as
arithmetic tricks: `x * (1 - min(1, armor_worn))`, `max(0, 19 - strength)`.

**Wanted.** `if(cond, a, b)` (or boolean → 0/1 coercion). Small change, large
readability win across Unarmored Defense, Fast Movement, magic items.

### G9. Inventory-wide state in formulas and caps on activation

**Problem.** Formulas can't ask "is any body armor equipped?", "how many
items are attuned?", or "total carried weight". The workaround is to have each
item contribute to a counter accumulator — this works (it's what the armor
counter in this system does), but caps cannot be enforced: attunement is
limited to three items, and activation caps only exist for preparation-managed
spell inventories.

**Wanted.** A generic activation cap on any inventory type (`max_active =
"3"`), and optionally item-quantity awareness for weight.

### G10. Attack and damage rolls

**Problem.** `weapon_attack` rolls a d20 + `attack_bonus`, and that bonus is a
per-weapon formula, so nothing can contribute to it (Archery fighting style,
`+1` weapons, magic item bonuses). There is no damage roll: a roll
definition's dice are fixed, but damage dice live in each weapon's metadata,
and the damage modifier depends on finesse/ranged/versatile/two-handed and
class features (Rage, Dueling, Divine Smite, Sneak Attack).

**Wanted.** Roll definitions that read dice from the target concept
(`dice_field = "damages"`), and weapon `attack_bonus` / `damage_bonus` as
accumulators so features and items can contribute.

### G11. Creatures and stat blocks

**Problem.** About 330 stat blocks (monsters, misc. creatures, NPCs) can't be
represented as anything but text. Characters also *use* them: Wild Shape,
Find Familiar, conjuration spells, mounts.

**Wanted.** A decision on whether creatures are (a) characters with fixed,
non-generated values in the same system, (b) a separate entity kind in the
library, or (c) out of scope for the library. Wild Shape needs at minimum a
way to reference a creature's stats from a character.

### G12. State-dependent effects (stances, forms)

**Problem.** Some features change what applies while active: Rage
(resistance to physical damage, bonus damage, advantage on Str checks), Wild
Shape (replace physical stats), Bladesong-style toggles. Effects can be gated
by `when`, but there is no character-owned toggle for `when` to read.

**Wanted.** Character toggles (booleans owned by the character, set by the
caller) addressable from `when` expressions. Overlaps G7.

### G13. Random tables and free-text character fields

**Problem.** Backgrounds carry d6/d8 personality trait, ideal, bond and flaw
tables; classes have starting-wealth dice (`5d4 × 10 gp`); madness and trinket
tables are random tables. There's no random-table concept and no free-text
field on a character.

**Wanted.** A table concept (`dice`, `entries`) that a choice can roll on or
pick from, and string-valued character fields.

### G14. Per-source spellcasting ability

**Problem.** `spellcasting_ability_modifier` is a single accumulator. A
High Elf wizard cantrip uses Intelligence, a Tiefling's Infernal Legacy uses
Charisma, and a multiclassed caster has two abilities. Save DC and attack
bonus are currently character-wide.

**Wanted.** Spellcasting ability attached to the *source* of the spell (the
class, race, or item that granted it), with DC/attack computed per source.

## Encoded on this branch (system versions 1.1.0 and 2.0.0)

- An `armor_worn` counter (body, heavy, shield) contributed by equipped
  armor, so formulas can gate on wearing armor (workaround for G9).
- Class-table columns for all twelve classes, plus the ones that change
  other stats: Barbarian and Monk Unarmored Defense, Draconic Resilience,
  Fast Movement, Unarmored Movement, Primal Champion, Aura of Protection.
- Racial traits: Keen Senses, Menacing, Dwarven Toughness, Half-Elf ability
  and skill choices, Dragonborn Draconic Ancestry and Breath Weapon.
- Removed the 22 spells not defined in SRD 5.0 (2.0.0).
- Fix: the Acolyte's Insight and Religion now get the proficiency bonus
  (they were listed on the sheet but not added to the modifier).

Everything else marked **Encodable** is unblocked content work, best split into
follow-up changes by section (magic items, spell descriptions, conditions,
mounts and services, the skill proficiency restructure).
