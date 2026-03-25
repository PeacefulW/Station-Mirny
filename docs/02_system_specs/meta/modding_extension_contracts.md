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
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../03_content_bible/resources/flora_and_resources.md
---

# Modding Extension Contracts

This document defines the foundational extension contracts that keep the project open to future player-created mods.

## Purpose

The purpose of this spec is to turn "support mods later" from a slogan into architectural rules that influence implementation today.

## Core statement

The project should be expandable through data, registries, events and controlled hook surfaces.

New content should generally be addable without rewriting core systems.

## Scope

This spec owns:
- extension-friendly identity expectations
- registry and namespace direction for mod-added content
- override/extension principles
- content-pack structure direction
- hook/event surface expectations

This spec does not own:
- final external mod SDK packaging
- final scripting sandbox decisions
- exact future security model for untrusted code

## Modding targets

The mod architecture should aim to support:
- new biomes
- new flora/fungi/tree-like forms
- new fauna species or behavior profiles where allowed
- new resources
- new recipes
- new buildings and content definitions
- future total-conversion style packs where feasible

## Foundational rules

### 1. Content identity must be stable
Mod-added content must resolve by stable ids, not by fragile path assumptions.

### 2. Registries are the canonical content access layer
Systems should request gameplay definitions from registries rather than hardcoded asset paths.

### 3. Data-first extension is the default
If a new biome/flora/fauna/building can reasonably be expressed as data, the architecture should prefer that route over new handwritten branching logic.

### 4. Hook surfaces matter
Core systems should expose sensible event or extension points so that mods do not need to fork foundational code for common extensions.

### 5. Override rules must be explicit
Where overriding is permitted, precedence and conflict handling must be defined rather than left implicit.

## Namespacing direction

The project should support namespaced ids conceptually.

Direction example:
- `core:plains`
- `core:spore_trunk`
- `core:cleaner`
- `mod_author:crystal_tundra`

Exact syntax may evolve.
The principle should not.

## Extension classes

### Additive content
Examples:
- new biome definitions
- new flora species data
- new recipes
- new decor sets

### Override content
Examples:
- balance tweak pack
- replacement biome parameters
- alternative audio/art mappings

### System-hooked extension
Examples:
- event subscribers
- extra reaction rules
- additional spawn/profile definitions

## Engine/system boundary

Not everything should be equally modifiable.

The architecture should distinguish between:
- safe content/data extension surfaces
- controlled system hook surfaces
- deep engine/runtime internals that are not expected to be freely replaced

## Worldgen implications

World generation must remain open to content extension such as:
- new `BiomeData`
- new flora sets
- new decor sets
- new feature definitions where supported

The generator core should not require surgery every time a content pack adds a biome or flora family.

## Localization implications

Mods should be able to add localized content through the same localization key model instead of shipping hardcoded player-facing strings inside logic.

## Save/persistence implications

Stable ids and explicit definitions matter because save data may refer to content introduced by mods.
The project should avoid content identity models that collapse when mods are added or removed.

## Acceptance criteria

This foundation is successful when:
- new content families can be added through data and registries in common cases
- core systems expose enough extension seams that mods do not immediately require code forks
- content ids remain stable and namespaced enough for saves and overrides
- the architecture does not quietly hard-lock the game to a closed content set

## Failure signs

This foundation is wrong if:
- adding a biome or flora family requires editing generator internals directly
- content loads by hardcoded file path assumptions in gameplay logic
- no namespace/identity strategy exists for content collisions
- user-facing text for modded content must be embedded in code

## Open questions

- exact mod folder/manifest format
- exact override precedence and conflict resolution rules
- exact future scripting/plugin boundaries for advanced mods
- exact validation behavior when a save references missing mod content
