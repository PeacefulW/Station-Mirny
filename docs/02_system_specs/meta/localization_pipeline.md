---
title: Localization Pipeline
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../../AGENTS.md
  - modding_extension_contracts.md
  - save_and_persistence.md
  - ../../01_product/GAME_VISION_GDD.md
---

# Localization Pipeline

This document defines the canonical localization pipeline for Station Mirny.

It exists to make localization a real project contract rather than a best-effort habit.

The goal is that:
- user-facing text is never scattered across gameplay code
- translators work in predictable locations
- mods can add localized content without patching code
- UI, data resources, messages, and content definitions all use the same key-based model

## Purpose

The purpose of this document is to define a stable foundation for:

- where localized text lives
- how localized text is identified
- how gameplay systems request localized text
- how data resources reference text
- how UI consumes text
- how translators and mod authors add new languages or new translated content
- what patterns are forbidden

## Gameplay goal

Localization is not only a technical convenience.
It affects:

- UI readability
- content scalability
- mod friendliness
- translation workflow
- maintainability of all future systems

The project should be localizable without requiring a translator to search through gameplay code for visible text.

Canonical product-level expectation:

A new translator should be able to add or improve a language by working in the localization folder structure and not by hunting random Russian or English strings across scripts and scenes.

## Scope

This spec owns:

- localization folder/layout direction
- key-based localization rules
- data-resource localization contracts
- UI and command/message localization contracts
- fallback expectations
- mod localization compatibility direction
- forbidden patterns

This spec does not own:

- exact translation wording
- exact final list of supported languages
- exact external localization tooling integration
- exact font/rendering support for every language

Those belong in content, UI, and platform-specific docs.

## Core architectural statement

Station Mirny uses **key-based localization**.

Canonical rule:

- gameplay code does not own final player-facing text
- data resources store localization keys, not translated text
- UI resolves and displays localized text through a localization service or equivalent pipeline
- messages, tooltips, labels, descriptions, lore snippets, and content names all follow the same model

## Canonical design rules

### Rule 1: No user-facing text in code
This rule already exists in engineering standards and is repeated here because it is absolute.

Gameplay code must not hardcode:

- button labels
- item names
- structure names
- tooltip text
- error messages shown to the player
- tutorial text
- lore text
- interaction result text

### Rule 2: Use keys, not final strings
The canonical exchange unit between systems is a localization key, optionally with arguments.

### Rule 3: Data resources store keys
Resources that define gameplay/content should store fields like:

- `display_name_key`
- `description_key`
- `tooltip_key`
- `lore_entry_key`
- `message_key`

not final translated text.

### Rule 4: UI resolves text, not gameplay logic
UI or localization-facing presentation layers should resolve final text from keys.
Gameplay logic should provide keys and arguments.

### Rule 5: Translators must work in predictable places
A translator should not need to inspect gameplay code just to translate visible text.

### Rule 6: Mods must be able to bring their own localized content
Mod-added content should use the same key-based model and merge into the same localization pipeline.

## Canonical folder/layout direction

This document does not force an exact shipping folder structure today, but it does require a centralized predictable layout.

The intended direction is something conceptually like:

- a dedicated localization root
- one subfolder or file family per language
- optional separation by domain if helpful
- predictable mod-localization integration points

Example direction:

- `localization/en/...`
- `localization/ru/...`
- `localization/zh/...`

or an equivalent centralized structure.

Canonical rule:

There must be one clear localization home in the project, not random scattered text files across unrelated folders.

## Key model

Localization keys should be stable and domain-oriented.

The engineering standards already define expected key families such as:

- `UI_*`
- `ITEM_*`
- `BUILD_*`
- `FAUNA_*`
- `FLORA_*`
- `RECIPE_*`
- `LORE_*`
- `TUTORIAL_*`
- `SYSTEM_*` fileciteturn60file0L1-L1

This document extends that direction.

### Key naming expectations

Keys should be:

- stable
- descriptive
- domain-oriented
- reusable when appropriate
- not tied to transient scene structure

Examples:

- `UI_MAIN_MENU_NEW_GAME`
- `ITEM_IRON_ORE_NAME`
- `ITEM_IRON_ORE_DESC`
- `BUILD_WALL_BASIC_NAME`
- `BUILD_WALL_BASIC_DESC`
- `FAUNA_CLEANER_NAME`
- `FAUNA_CLEANER_DESC`
- `SYSTEM_NOT_ENOUGH_POWER`
- `SYSTEM_CANNOT_PLACE_HERE`
- `LORE_ARCHIVE_INTRO_01`

### Description suffix

`_DESC` remains the preferred suffix for descriptions/tooltips, consistent with engineering standards fileciteturn60file0L1-L1

## Data-resource contract

Gameplay/content data should reference localization keys, not final strings.

Examples of expected fields:

- `display_name_key`
- `description_key`
- `short_name_key`
- `tooltip_key`
- `lore_key`
- `failure_message_key`

This applies to content such as:

- items
- flora
- fauna
- buildings
- machines
- recipes
- biomes where displayed
- UI-driven content definitions

Canonical rule:

A new content resource should be translatable by updating localization data, not by editing the code or the resource text itself in multiple languages.

## UI contract

UI should not own hardcoded display text for game content.

UI responsibilities:

- request/display localized text by key
- pass formatting args where needed
- react to language changes if supported live
- remain decoupled from raw translated string ownership

UI must not:

- embed domain content text directly in scripts for convenience
- bypass localization for "temporary" visible text that later becomes permanent
- duplicate translated strings already owned by data/content keys

## Command and message contract

Commands, actions, and gameplay systems should return message keys plus optional arguments.

Expected shape direction:

- `message_key`
- `message_args`

Examples:

- `SYSTEM_NOT_ENOUGH_POWER`
- `SYSTEM_BUILD_BLOCKED_BY_TERRAIN`
- `SYSTEM_STORAGE_FULL`

Canonical rule:

Gameplay systems communicate meaning.
Localization resolves final wording.

## Formatting arguments

The localization pipeline should support argument substitution where needed.

Typical use cases:

- item counts
- machine names
- percentages
- resource names
- dynamic warnings

Canonical rule:

Use structured args rather than string concatenation in gameplay code.

Bad direction:

- manually stitching Russian/English fragments together in code

Preferred direction:

- one key
- one argument payload
- formatter/localization layer produces final display text

## Fallback behavior

The localization pipeline should have deterministic fallback behavior.

At minimum, the project should define:

- a primary fallback language
- behavior for missing keys
- behavior for partially translated content

Expected direction:

- if a key is missing in the active language, use fallback language if available
- if still missing, show a clearly diagnosable fallback form rather than silently hiding text

The exact formatting of missing-key display is implementation-specific.
The need for deterministic fallback is not.

## Language support direction

The project currently already expects Russian and English coverage for new player-facing content according to engineering standards fileciteturn60file0L1-L1

The architecture should remain open to adding additional languages later without changing gameplay logic.

This includes languages with potentially different text length, grammar, and script needs.

## Modding implications

Mod-added content must be able to integrate into the localization system.

That means mods should be able to provide:

- their own localization keys
- their own language files
- namespaced content text where appropriate
- translated display text without editing core code

Canonical rule:

A mod should not need to patch gameplay code just to localize its own item names, flora descriptions, or UI-facing strings.

## Namespace direction for mod localization

Where namespacing is used for content IDs, localization should remain compatible with that identity model.

Example direction:

- content id: `modauthor:crystal_tundra`
- localization keys associated with that content should remain stable and not collide with core content or other mods

The exact mapping may vary.
The anti-collision principle should remain.

## Save and persistence implications

Localization should not leak unstable translated text into save-critical identity.

Canonical rule:

- save data should rely on stable IDs and game data identity
- localized text should be resolved at presentation time
- changing a translation must not corrupt save identity

This is especially important for:

- items
- buildings
- flora/fauna definitions
- modded content

## Multiplayer implications

Localized text should remain presentation-facing.

Canonical rule:

- shared gameplay truth should use stable IDs, enums, keys, or canonical data references
- final localized strings should be resolved locally for display

This helps avoid making language choice a networking problem.

## Tooling expectations

The project should eventually support or encourage tooling/workflows that make localization practical.

Helpful future capabilities may include:

- validation for missing keys
- validation for missing translations in required languages
- duplicate key detection
- unused key reporting
- export/import support for translators if desired later

This document does not require those tools immediately.
It requires the architecture to remain compatible with them.

## Forbidden patterns

The following patterns should be treated as violations.

### 1. Raw visible strings in gameplay code
Examples:

- hardcoded warning text in system logic
- hardcoded item names in factory/build scripts
- tutorial text directly embedded in gameplay scripts

### 2. String concatenation for localization-sensitive sentences
Examples:

- building sentences from translated fragments in code
- assuming all languages share the same grammar structure

### 3. Storing translated text inside save-critical content identity
Examples:

- serialized item identity based on display string
- save logic depending on translated names

### 4. Per-feature hidden text islands
Examples:

- one subsystem keeping its own private visible text format outside the project localization pipeline

### 5. Temporary text that never gets cleaned up
Examples:

- debug placeholder strings that become accidental shipping UI text

## Minimal architectural seams

These are illustrative, not final APIs.

### Localization service direction

```gdscript
class_name LocalizationService
extends RefCounted

func tr_key(key: StringName, args: Dictionary = {}) -> String:
    pass
```

### Content resource direction

```gdscript
class_name ItemData
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
```

### Command/message direction

```gdscript
class_name GameplayMessage
extends RefCounted

var message_key: StringName
var message_args: Dictionary
```

These are examples only.
They illustrate the core rule that systems exchange keys and arguments, not final display strings.

## Acceptance criteria

This foundation is successful when:

- translators can work primarily inside the localization folder structure
- gameplay systems return keys/args instead of final visible text
- content resources remain language-agnostic and reference keys
- UI resolves localized text consistently
- adding a new language does not require editing gameplay code
- modded content can bring its own translations without forking core logic
- save and multiplayer systems remain based on stable identity, not translated strings

## Failure signs

This foundation is wrong if:

- visible text is scattered through scripts and scenes
- new content requires touching code to translate names/descriptions
- translators need to search the codebase for Russian or English strings
- language choice leaks into gameplay identity or persistence
- mods cannot localize their own content cleanly

## Open questions

The following remain intentionally open:

- exact final on-disk localization format
- exact folder structure under the localization root
- exact live language-switch support behavior
- exact validation tooling and automation
- exact font/rendering policy for additional scripts and long strings

These may evolve without changing the foundational rules above.
