---
title: Modding Extension Contracts
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - multiplayer_and_modding.md
  - save_and_persistence.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../03_content_bible/resources/flora_and_resources.md
  - ../../03_content_bible/fauna/catalog.md
---

# Modding Extension Contracts

This document defines the foundational extension contracts that keep Station Mirny open to future player-made mods, content packs, and data-driven expansion.

This file exists to turn "we want modding later" from a vague wish into architectural rules that affect implementation now.

The goal is not to finalize a full public mod SDK today.
The goal is to ensure that content, registries, IDs, loading rules, and extension seams are designed in a way that does not hard-lock the game into a closed architecture.

## Purpose

The purpose of this document is to define a stable foundation for:

- mod-extensible content architecture
- registry-first content access
- stable content identity
- content packs and namespace rules
- additive and override content loading direction
- extension seams for worldgen, flora, fauna, resources, buildings, and future systems
- compatibility with persistence, localization, and future co-op

## Gameplay goal

Modding is not only a community feature.
It is also a pressure test for whether the game's core architecture is actually data-driven and scalable.

The project should be able to grow through:

- new biomes
- new flora families
- new fauna families
- new resources
- new recipes
- new buildings and machine variants
- new decor and environmental content
- future total-conversion-like content directions where feasible

This should happen primarily through extension, not surgery.

## Scope

This spec owns:

- the architectural rules for mod-extensible content
- namespace and identity direction
- registry expectations
- content pack and override principles
- extension seam expectations
- compatibility expectations for saves and localization

This spec does not own:

- final public mod tooling UX
- final scripting sandbox design
- exact external packaging distribution format
- exact future security model for arbitrary user code
- exact workshop/platform integration

Those belong in later implementation or platform docs.

## Core architectural statement

Station Mirny should be expandable by data, registries, resources, and controlled hooks.

Adding common classes of new content should generally be possible **without rewriting core systems**.

If a new biome, flora family, fauna family, recipe, or building requires generator or gameplay core surgery every time, the architecture is failing the modding goal.

## Canonical design rules

### Rule 1: Registry-first content access
Gameplay systems should request content through registries, definitions, IDs, or other canonical lookup layers.

They should not rely on:

- hardcoded asset paths in gameplay logic
- ad-hoc per-system local content lists
- fragile scene path assumptions as canonical gameplay identity

### Rule 2: Stable content identity is mandatory
Content must have stable IDs that survive:

- save/load
- reordering of files
- content pack loading
- mod combination
- later content growth

### Rule 3: Data-first extension is the default
If a new piece of gameplay content can reasonably be represented as data, the project should prefer that route over handwritten one-off code branches.

### Rule 4: Core systems should expose extension seams
Common extension cases should not require forking the engine or rewriting foundational systems.

### Rule 5: Override behavior must be explicit
If overrides are supported, conflict behavior and precedence must be defined intentionally rather than implied by random load order accidents.

### Rule 6: User-facing text must remain localization-key based
Modded content should integrate into the localization pipeline rather than forcing user-facing text into logic scripts.

## What modding should be able to extend

The target direction should support extension of at least the following content categories.

### World generation content
Examples:

- new biomes
- new flora sets
- new decor sets
- new surface feature definitions
- new POI definitions where supported
- new worldgen tuning profiles where supported

### Flora content
Examples:

- new tree-like forms
- new alien growth families
- new biome-specific vegetation
- new wind-reactive flora definitions
- new decorative or functional flora variants

### Fauna content
Examples:

- new species definitions
- new habitat or spawn profiles
- new visual families
- new risk-tier variants
- future behavior profile variants where supported

### Resources and crafting content
Examples:

- new resources
- new refined materials
- new recipes
- new processing chains
- new decryption outputs or progression definitions where allowed

### Building and machine content
Examples:

- new placeable structures
- new machine definitions
- new room utility objects
- new light source definitions
- new logistics parts

### Presentation/support content
Examples:

- new ambience sets
- new audio references
- new VFX mappings
- new UI-linked content strings

## What should not be assumed freely moddable

Not everything should be equally replaceable.

The architecture should distinguish between:

- **safe data/content extension surfaces**
- **controlled hook surfaces**
- **deep engine/runtime internals** that are not expected to be casually replaced

Examples of things that may remain tightly controlled:

- low-level renderer internals
- native core storage layouts
- some networking internals
- some fundamental persistence plumbing

The important thing is to define extension boundaries clearly, not pretend everything is equally hot-swappable.

## Namespace and identity direction

The project should support namespaced content identity.

Example direction:

- `core:plains`
- `core:spore_trunk`
- `core:ore_iron`
- `core:storm_lamp`
- `authorname:crystal_tundra`
- `authorname:glass_spire_fauna`

Exact syntax may evolve.
The principle should not.

Canonical rule:

content identity must not rely on filenames alone as the long-term gameplay truth.

## Content pack direction

The project should assume the idea of content packs from the start.

A content pack may contain things like:

- manifest/metadata
- content definitions/resources
- localization additions
- art/audio references
- optional override declarations
- dependency declarations later if needed

This document does not lock the exact final folder format.
It locks the architectural expectation that mod content is grouped, identifiable, and loadable as a coherent extension unit.

## Additive vs override content

The architecture should distinguish conceptually between:

### Additive content
New things added alongside core content.

Examples:

- a new biome
- a new flora species
- a new resource
- a new recipe
- a new decorative ruin set

### Override content
Intentional replacement or alteration of existing definitions.

Examples:

- a balance pack that changes a biome range
- a total-conversion pack that replaces certain progression definitions
- an art/audio replacement pack

### Patch-like extension
Content that modifies or augments existing systems in controlled ways.

Examples:

- adding a species to an existing biome spawn set
- adding new localized strings
- injecting new recipes into an existing tech/progression context where supported

Canonical rule:

The project should not leave the difference between additive and override behavior ambiguous.

## Load order and precedence direction

Where multiple content packs affect the same domain, the architecture should allow explicit precedence or deterministic resolution.

This document does not define the final exact loader policy.
It does define the need for:

- deterministic load behavior
- clear conflict handling direction
- explicit rather than accidental override outcomes

## Registry expectations

Registries should be the canonical content access layer for mod-extensible definitions.

Typical registry-managed content categories may include:

- biomes
- flora species
- flora sets
- fauna species
- resources
- recipes
- buildings
- machines
- loot/POI definitions
- environmental profiles

Gameplay systems should consume these through registry lookup rather than hardcoding references in many places.

## Worldgen implications

World generation is one of the biggest tests of mod extensibility.

The architecture should allow adding common worldgen content such as:

- new `BiomeData`
- new `FloraSetData`
- new `DecorSetData`
- new `FeatureData` where supported
- new tuning profiles or resolver candidates where supported

Canonical rule:

Adding a new biome or flora family should usually be a data registration problem, not a generator rewrite problem.

## Flora implications

Flora must remain extensible because the game may later grow a very large catalogue of alien tree-like and wind-reactive life forms.

The architecture should allow:

- adding new species definitions
- grouping species into biome or environment-relevant sets
- tagging content by habitat, season, wind response, or aesthetic family
- extending flora without hardcoding special cases into the world generator every time

## Fauna implications

Fauna extension should be considered from the beginning.

The architecture should leave room for:

- new species definitions
- new spawn/habitat profiles
- new migration/environment compatibility definitions later
- controlled behavior-profile references where supported

Canonical rule:

The project should not require handwritten global `if species == ...` branches every time a new creature family is introduced.

## Building and progression implications

Modding should remain compatible with:

- building definitions
- machine definitions
- crafting recipes
- progression-linked unlock definitions where exposed
- light source definitions
- infrastructure variants

This does not mean every progression rule must be fully overrideable from day one.
It means the architecture should not block data-driven extension by accident.

## Localization implications

Modded content must fit into the localization pipeline.

The architecture should support the idea that a mod provides:

- localization keys
- per-language data files
- no need to hunt through scripts for raw user-facing text

Canonical rule:

A translated mod should be possible without editing gameplay code just to replace visible strings.

## Save and persistence implications

Persistence must remain stable in the presence of modded content.

This means the project should care about:

- stable content IDs
- clear namespace handling
- graceful behavior when save data refers to missing mod content later
- avoiding fragile save formats that depend on file order or accidental indexes

This document does not define all missing-mod recovery behavior.
It defines the requirement that content identity be save-safe.

## Multiplayer implications

Multiplayer and modding interact in important ways.

At minimum, the architecture should not assume that:

- client-local undefined content is acceptable for authoritative gameplay
- content identity is loose or informal
- gameplay-relevant content can differ silently between participants

This does not mean the full mod sync protocol is solved here.
It means mod-extensible gameplay content must still have strong identity and deterministic loading expectations.

## Extension seams and hooks

The architecture should support extension through controlled seams such as:

- registries
- resource definitions
- event subscriptions where appropriate
- tagged definition lookups
- explicit extension points in worldgen and content resolution pipelines

The project should avoid making extension depend on:

- patching random core scripts everywhere
- fragile file replacement hacks as the only route
- uncontrolled global monkey-patching of logic

## Performance direction

Mod-extensible does not mean unbounded or chaotic.

The architecture must still respect performance contracts.
This means:

- mod-added content should plug into existing bounded systems
- content loading and registration should be deterministic and controlled
- data-driven extension should not encourage heavy runtime reflection in hot paths
- worldgen/content lookup should remain cacheable and efficient

## Documentation direction

Extension-friendly architecture is easier when content contracts are documented clearly.

The project should progressively define stable data contracts for major moddable domains such as:

- `BiomeData`
- `FloraSpeciesData`
- `FaunaSpeciesData`
- `ResourceData`
- `RecipeData`
- `BuildingData`
- `LightSourceData`

The exact final class names may evolve.
The principle should remain.

## Minimal architectural seams

These are illustrative, not final APIs.

### Registry access direction

```gdscript
class_name ContentRegistryService
extends RefCounted

func get_definition(content_type: StringName, content_id: StringName) -> Resource:
    pass
```

### Mod/content pack direction

```gdscript
class_name ContentPackManifest
extends Resource

@export var pack_id: StringName
@export var display_name_key: StringName
@export var version: String
@export var supported_content_types: Array[StringName]
```

### Namespace example direction

```gdscript
class_name ContentId
extends RefCounted

var namespace: StringName
var local_id: StringName
```

These are examples only.
They illustrate the architectural expectation that content identity and lookup be deliberate.

## Success conditions

This foundation is successful when:

- common new content can be added through data/registries rather than core rewrites
- worldgen remains extensible for new biomes and flora
- fauna/content families can grow without global hardcoded branching explosion
- saves remain stable because content has strong identity
- localization remains compatible with modded content
- the architecture is meaningfully more open than a closed hardcoded game

## Failure signs

This foundation is wrong if:

- adding a biome requires editing generator internals every time
- gameplay logic relies on hardcoded asset paths as canonical truth
- content identity is ambiguous or fragile
- saves depend on file order, enum positions, or accidental indexes
- modded content must hardcode user-facing strings into scripts
- the only way to extend gameplay content is to fork core systems

## Open questions

The following remain intentionally open:

- exact final content pack folder structure
- exact manifest schema
- exact override precedence and conflict handling policy
- exact dependency/version resolution model
- exact future scripting/plugin boundary for advanced mods
- exact missing-mod save recovery behavior

These may evolve without changing the foundation above.
