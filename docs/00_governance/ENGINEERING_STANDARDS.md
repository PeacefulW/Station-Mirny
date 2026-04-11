---
title: Engineering Standards
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 2.2
last_updated: 2026-04-09
depends_on:
  - DOCUMENT_PRECEDENCE.md
related_docs:
  - PERFORMANCE_CONTRACTS.md
---

# Engineering Standards

This document is the canonical engineering standard for Station Mirny.

It defines the non-runtime-law side of implementation:
- code organization
- naming
- architectural boundaries
- data-driven rules
- localization
- persistence boundaries
- mod extensibility
- AI assistant coding behavior

## 1. Golden rules

These rules are not optional.

1. No hardcoded gameplay data.
2. Systems must not directly couple when an event, registry, command, component, or service boundary is the correct abstraction.
3. One script, one responsibility.
4. Explicit typing is mandatory.
5. Mod compatibility is a first-class requirement.
6. No user-facing text in code.
7. Every runtime-sensitive or extensible system must declare one authoritative source of truth, one write owner, and explicit derived/cache boundaries.

## 2. Naming and style

Follow consistent GDScript naming:
- files/folders: `snake_case`
- classes: `PascalCase`
- variables/functions: `snake_case`
- constants/enum values: `UPPER_SNAKE_CASE`
- private members: `_private_name`
- signals: past tense
- booleans: `is_`, `has_`, `can_`

## 3. Script ordering

Use this order:
1. `class_name`
2. `extends`
3. class docs
4. signals
5. enums
6. constants
7. exported vars
8. public vars
9. private vars
10. built-in Godot methods
11. public methods
12. private methods

## 4. Typing and documentation

Rules:
- every variable, parameter, and return value is typed
- public classes and important public methods should have concise `##` docs
- unclear systems need brief intent-level comments, not noise

## 5. Required architectural patterns

Use approved patterns where they fit:
- Data-Driven Resources
- Registry
- EventBus
- State Machine
- Component Pattern
- Command Pattern
- Factory Pattern
- Services

Do not create parallel ad-hoc architectures when one of these patterns already fits the problem.

## 6. Data-driven rules

Gameplay data belongs in data assets, not in logic branches.

Rules:
- use `Resource` or equivalent structured data for gameplay definitions
- new content should be addable through data
- do not load gameplay data by hardcoded paths if a registry exists
- prefer ids and registries over path-based assumptions
- distinguish immutable base data from runtime diff when persistence matters

## 7. Registry rules

Registries are the canonical access point for gameplay definitions.

Implications:
- do not directly `load()` content assets in gameplay logic when registry access should exist
- content identity should use stable ids
- modded or overridden content should still resolve through the registry layer

## 8. EventBus rules

EventBus is the default boundary for inter-system communication when systems would otherwise become tightly coupled.

Rules:
- systems emit domain events instead of mutating other systems directly
- UI subscribes and dispatches, but does not own game-state mutation
- mods/extensions may subscribe to events instead of patching core systems directly

## 9. Mandatory architectural patterns

The following four patterns are not suggestions — they are required wherever applicable. Each exists because of a specific architectural constraint.

### 9.1 Command Pattern for world mutations

**Rule:** Every action that mutates authoritative world state (place building, remove building, mine tile, craft item) MUST be expressed as a Command object with deterministic application.

**Why:** ADR-0003 (immutable base + runtime diff) requires all mutations to be recordable as diffs. ADR-0004 (host-authoritative multiplayer) requires mutations to be replayable on host and clients. Undo/redo requires reversible commands. Save/load requires deterministic state reconstruction.

**Shape:**
- Command has `execute()` and optionally `undo()`
- Command carries all parameters needed to reproduce the action
- Commands flow through CommandExecutor, not direct system calls
- No side-channel mutations that bypass the command path

**Applies to:** building placement/removal, terrain excavation, crafting, item pickup/drop, future: research, equipment changes.

### 9.2 Compute → Apply as standard two-phase pattern

**Rule:** Any operation that produces derived state from authoritative data MUST separate into a compute phase and an apply phase.

**Why:** PERFORMANCE_CONTRACTS requires that interactive paths stay under 2ms. SIMULATION_AND_THREADING_MODEL requires that heavy computation does not block the main thread. The compute phase can be deferred, budgeted, or run on a worker thread. The apply phase stays bounded and main-thread-safe.

**Shape:**
- Compute: read inputs, produce result (pure data, no scene tree mutation)
- Apply: write result to scene tree / state (bounded, local, main-thread)
- Never mix the two — a function that computes AND mutates is a violation

**Applies to:** chunk terrain generation, mountain topology rebuild, room flood-fill, power network recalculation, shadow/cover rebuild, fog of war updates, future: pathfinding, AI decisions.

### 9.3 Data-driven registries with namespaced IDs

**Rule:** Every category of extensible game content MUST be accessible through a registry with stable namespaced string IDs (`"namespace:content_id"`). No direct `load()` by path in gameplay logic.

**Why:** ADR-0004 requires clean entity identity. Mod compatibility requires content to be addable without code surgery. Save/load requires stable IDs that survive refactors. Multiplayer requires all peers to resolve the same ID to the same definition.

**Shape:**
- Registry autoload (e.g., `ItemRegistry`) scans data directories on init
- Content defined as `.tres` Resource files with `id: StringName`
- All gameplay lookups go through `Registry.get_by_id(id)`, never `load("res://data/...")`
- Namespace convention: `"base:iron_ore"`, `"mod_name:custom_item"`

**Currently implemented for:** items, recipes, buildings, resource nodes (via `ItemRegistry`).
**Must be extended to:** biomes, flora sets, fauna types, POI definitions, events, workstations.

### 9.4 Deterministic hashing by world position

**Rule:** Visual and content variation that depends on world location MUST use deterministic hashing from world coordinates, not runtime randomness.

**Why:** ADR-0003 (immutable base) requires that the same seed + coordinates produce the same result always. Multiplayer requires all clients to see the same world without synchronizing random state. Save/load requires that visual variation reconstructs identically from seed.

**Shape:**
- Hash function: `pos.x * PRIME_A + pos.y * PRIME_B`, XOR-shifted (see `Chunk._tile_hash()`)
- Use for: rock wall variant selection, flora placement, terrain detail variation, POI eligibility, resource node distribution
- Never use `randf()` or `randi()` for anything that depends on world position
- Per-frame randomness (particles, sound variation) is exempt — it's client-local presentation

**Applies to:** terrain tile variants, mountain wall faces, future: flora distribution, POI placement, resource vein patterns, biome transition noise.

### 9.5 Authoritative owner + scalable path

**Rule:** Every new runtime-sensitive or extensible feature MUST document:
- authoritative source of truth
- single write owner
- any derived/cache mirrors and their invalidation path
- local dirty unit
- what work is allowed synchronously
- what escalates to queue / worker / native cache / C++

**Why:** Small local features accumulate into systemic hitching when ownership and scale path are left implicit. The project must remain safe not only for today's tiny content count, but for future density, mods, and expanded simulation.

**Shape:**
- one mutable truth, not several competing mirrors
- one owner writes authoritative state
- readers consume authoritative state or clearly derived read models
- derived data has explicit rebuild/invalidation triggers
- synchronous work is bounded by local dirty unit, not by "how many objects happened to exist today"

**Forbidden reasoning:**
- "right now there is only one tree"
- "this chunk usually has only a few objects"
- "we can keep it synchronous until it becomes a problem"

### 9.6 Other approved patterns

#### State Machine
Use for entities or flows with explicit modes:
- player states, AI states, machine states

#### Component Pattern
Use for reusable cross-entity behavior:
- health, noise, fuel usage, power source/sink

#### Factory Pattern
Use for construction of complex entities from data:
- creatures, buildings, pickups, items with setup requirements

#### Services
Use to decompose larger systems cleanly instead of creating god classes.

## 10. Anti-patterns

Avoid:
- magic numbers in gameplay logic
- string-path node coupling
- god classes
- direct system references across domain boundaries
- type-switching on ids/strings when data or polymorphism should drive behavior

## 11. UI rules

UI must:
- observe state
- render state
- dispatch commands/events

UI must not:
- own hidden gameplay truth
- directly mutate core systems without approved boundaries

All user-visible text remains localization-driven.

## 12. Localization rules

### Core rule

No user-facing text in code.

### Format

Use localization keys and the project localization service pattern.

### Key model

Expected key families include:
- `UI_*`
- `ITEM_*`
- `BUILD_*`
- `FAUNA_*`
- `FLORA_*`
- `RECIPE_*`
- `LORE_*`
- `TUTORIAL_*`
- `SYSTEM_*`

`_DESC` remains the preferred suffix for descriptions/tooltips.

### Data-resource rule

Data resources should store keys, not translated text.

Examples:
- `display_name_key`
- `description_key`

### Command/UI contract

Commands and actions should return:
- `message_key`
- optional `message_args`

not preformatted final text.

### Content update rule

When adding new player-facing content:
- add keys for Russian and English
- ensure UI/data usage resolves by key

## 13. Save/load rules

Persistent systems must:
- define what belongs in save state
- define what is generated/base data
- serialize state as data rather than implicit scene state

The system should be understandable in terms of save boundaries, not only runtime behavior.

## 14. Mod compatibility rules

New systems must be designed so content can be:
- added
- overridden
- extended

Use:
- ids
- registries
- data resources
- event/hook points

Avoid assumptions that lock the game to a closed content set.

## 15. Git / workflow conventions

Preferred commit style:
- `feat(system): ...`
- `fix(system): ...`
- `refactor(system): ...`
- `docs: ...`
- `data(scope): ...`

This is not a runtime law, but helps keep project history navigable.

## 16. Engineering checklist

Before considering implementation done:
- no hidden hardcoded gameplay data
- no direct forbidden system coupling
- all public APIs are typed
- script size remains responsible
- authoritative source of truth and write owner are explicit for new mutable/runtime-sensitive work
- derived/cache layers have an invalidation path
- runtime-sensitive changes define dirty unit and escalation path beyond today's tiny content count
- registry/event updates exist if a new content/system surface was introduced
- localization is complete for new user-facing content
- save/load boundary is understood
- mod extension path is not accidentally blocked

## 17. AI assistant behavior

When an AI assistant writes code for this project, it must:
- prefer canonical docs under `docs/`
- follow this file first for engineering law
- follow [Performance Contracts](PERFORMANCE_CONTRACTS.md) for runtime-sensitive systems
- preserve approved patterns instead of inventing parallel ones
- challenge designs that are only justified by current low object counts
- name the authoritative truth, write owner, dirty unit, and escalation path when adding runtime-sensitive behavior
- explain architecture choices clearly when tradeoffs matter

## 18. Final principle

The project should remain:
- data-driven
- event-friendly
- modular
- persistent
- mod-extensible

If a change violates those properties, it should be redesigned before being accepted.
