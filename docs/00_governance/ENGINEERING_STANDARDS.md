---
title: Engineering Standards for Station Mirny
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 3.2
lang: en
last_updated: 2026-04-18
depends_on:
  - WORKFLOW.md
related_docs:
  - PROJECT_GLOSSARY.md
  - ../02_system_specs/meta/system_api.md
  - ../02_system_specs/meta/event_contracts.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/commands.md
---

# Engineering Standards for Station Mirny

This file is the only canonical engineering standard for the project.
It supersedes all previous versions of `ENGINEERING_STANDARDS`.
AI agents and developers read it before code, not after.

---

## LAW 0 - Classification before code

**Before any new feature or system change, answer every question below.**
If even one answer is unknown, stop and figure it out before coding.

```
1.  Is this canonical world data, a runtime overlay, or visual only?
2.  Does it require save/load?
3.  Does it affect determinism (the same result on every client)?
4.  Must it work on unloaded chunks?
5.  Is this C++ compute or main-thread apply?
6.  What is the dirty unit (minimum recomputation unit)?
7.  Who is the single owner of this data?
8.  Does it scale at 10x or 100x the object count?
9.  Does it block the main thread under load?
10. Is there a hidden GDScript fallback when native code is unavailable?
11. Could this operation become heavy in the future?
12. Do we need a whole-world prepass or only local compute?
```

If an operation **could become heavy in the future**, move it into native code
**immediately**, not "later."

---

## LAW 1 - GDScript / C++ boundary

### GDScript is only for:
- orchestration and queues
- state machines
- calls into the native layer
- UI and presentation
- loading / saving
- debug and dev tools

### Must be in C++ (GDExtension):
- chunk generation
- noise / field sampling
- biome / mountain solve
- placement lists
- tile mask / transition mask / atlas decisions
- merging base chunk + diff
- bulk packet prep
- any large-scale calculation over tiles or objects

**Rule:** If an operation runs in a loop over thousands of tiles or objects, it
belongs in C++, not GDScript.
**Violation:** a GDScript loop over a chunk / tiles / placement list.

---

## LAW 2 - The main thread only publishes

The main thread **does not compute the world**. It only applies finished
results.

### Allowed on the main thread:
- create / reuse a chunk view
- apply TileMap cells
- enable / disable visibility
- register collisions
- attach / detach MultiMesh, particles, and sound

### Forbidden on the main thread:
- generating terrain
- resolving biomes, POIs, or large terrain masks
- building tile-transition / atlas arrays
- iterating through the whole chunk synchronously
- doing anything whose scale is not bounded by the number of local objects

**Pattern:** Compute (worker / C++) -> Apply (main thread, bounded).
A function that both computes and mutates the scene tree is a violation.

---

## LAW 3 - The chunk generator is a pure function

The chunk generator depends **only** on:
- `world_seed`
- `chunk_coord`
- `world_version`
- `generation_settings`

### The generator may not read:
- the scene tree
- loaded chunks
- save state
- player position
- the current camera
- visual state
- any runtime state of the world

**Why:** This guarantees determinism, parallel generation, and correctness on
clients.

---

## LAW 4 - World versioning (`world_version`)

Any change to canonical world generation that changes the result for the same
`world_seed + chunk_coord` **must bump `world_version`**.

### Without increasing `world_version`, you may not change:
- terrain solve
- water-generation output
- mountains / cliffs
- biome classification
- placement rules (flora, POIs, resources)

### Allowed without a version bump:
- visual parameters that do not affect tile type / walkability
- performance optimizations with identical output
- bug fixes that do not change the canonical result

**Why:** Otherwise existing saves / chunks stop matching the generator and the
world breaks in ways that are hard to explain.

```gdscript
# In WorldGenerationSettings or an equivalent location
const WORLD_VERSION: int = 1  # Bump on any change to canonical output
```

---

## LAW 5 - The base world is immutable

Canonical world data **does not mutate** after chunk generation.
All player and simulation changes are stored as a **runtime diff / overlay**,
separate from the base.

### Forbidden:
- rewriting a chunk's base terrain as a new source of truth
- mixing generated data and player-made mutations into one layer without a
  clear boundary
- saving base data into the save file (it is deterministically recreated from
  seed + version)

### Layer architecture:
```
base layer   = f(world_seed, chunk_coord, world_version)  -> never mutates
diff layer   = player mutations, excavations, placements  -> persisted
overlay      = environmental simulation (snow, ice, fire) -> may be transient
visual layer = derived from base + diff + overlay         -> not persisted
```

**Why:** The base / diff split is the only reason save files stay small and
correct.

---

## LAW 6 - Native <-> script boundary only through a chunk packet

Chunk data moves between C++ (GDExtension) and GDScript **through one compact
packet at a time**.

### Forbidden:
- hundreds of tiny calls across the C++/GDScript boundary for one chunk
- `Dictionary` inside `Dictionary` on a hot path
- sending tiles, objects, or masks item by item in separate calls

### Allowed:
- `PackedInt32Array`, `PackedFloat32Array`, `PackedByteArray`
- placement arrays with a compact struct-like layout
- one call per chunk that returns the whole packet

**Why:** C++/GDScript call overhead accumulates. A thousand calls instead of one
packet destroys performance even when the underlying computation is light.

```gdscript
# BAD - a thousand calls
for tile in chunk_tiles:
    NativeGen.get_tile_type(tile.x, tile.y)  # VIOLATION

# GOOD - one batch boundary
var packets: Array = world_core.generate_chunk_packets_batch(seed, coords, world_version, settings_packed)
```

---

## LAW 7 - No sync resource loading on a runtime path

Forbidden on a runtime path:
- `load()` during gameplay
- `ResourceLoader.load()` without prior preparation
- `PackedScene.instantiate()` inside mass loops (see LAW 9)
- synchronous loading of textures, scenes, or materials when entering a new
  chunk

### Allowed:
- `preload()` for always-used resources
- background loading through `ResourceLoader.load_threaded_*`
- publishing already prepared resources from a preloaded pool

**Why:** Synchronous `load()` blocks the main thread unpredictably. Chunk-change
hitches often come from this, not from world generation.

---

## LAW 8 - One owner, one truth

Every data type has exactly **one write owner**.

| Data | Owner |
|---|---|
| Base chunk terrain | `WorldCore` / C++ generator |
| Player changes | `WorldDiffStore` |
| Time of day | `TimeSystem` |
| Seasonal overlays | future environment-runtime owner |
| Visual shadows | `WorldView` |
| Building state | `BuildingRegistry` |

### Forbidden:
- `ChunkView` owning terrain truth
- a visual system owning gameplay truth
- the save system generating the world
- the streamer deciding biomes
- multiple systems writing the same data

---

## LAW 9 - No hidden fallbacks

**Rule:** If a hot path requires native compute, then when native code is
unavailable, the path must **fail** with an explicit error. It must not
"temporarily" switch to GDScript.

A "temporary" GDScript fallback becomes permanent architecture.
That is forbidden.

```gdscript
# BAD
if NativeChunkGen.is_available():
    result = NativeChunkGen.generate(coord)
else:
    result = _slow_gdscript_fallback(coord)  # VIOLATION

# GOOD
assert(NativeChunkGen.is_available(), "NativeChunkGen required - build GDExtension first")
result = NativeChunkGen.generate(coord)
```

---

## LAW 10 - A chunk is visible only when the gameplay layer is ready

### You may show a chunk only when these are ready:
- terrain
- terrain affecting movement
- blocking cells
- cliff / block masks
- everything that affects movement and collisions

### These may load later (after reveal):
- grass and small decor
- leaves, snow, dust
- cosmetic shadows
- non-interactive decoration

**Principle:** `terrain now, cosmetics later`.
It is unacceptable to show a raw chunk and "draw in later" gameplay-critical
layers.

---

## LAW 11 - Every runtime-sensitive system has a dirty unit

**Rule:** Every system must declare its **minimum update unit (dirty unit)**.

| System | Dirty unit |
|---|---|
| Terrain redraw | `16x16` subchunk |
| World generation | `32x32` chunk |
| Flora rebuild | chunk packet |
| Ice / snow overlay | tile block / subchunk |
| Save diff | tile / object mutation |
| Power network | network segment |
| Room flood-fill | room boundary |

**Forbidden:** updating "everything around it" when a dirty unit is enough.
**Forbidden:** using "the object count is still small" to justify having no
dirty unit.

---

## LAW 12 - No global planet prepass

**Rule:** The game must not require generating the whole planet before startup.

### Allowed:
- local chunk generation
- a lazy macro-region cache
- deterministic large-scale fields on demand
- `WorldPrePass` only when a spec explicitly classifies it as a bounded,
  one-time world-load / new-game-preview worker task, RAM-only, cache-keyed by
  seed/version/bounds/settings, and forbidden from interactive gameplay paths

### Forbidden:
- a mandatory interactive-path or main-thread global `WorldPrePass`
- "first compute the entire planet, then start the game"
- synchronous preloading of all biomes

---

## LAW 13 - No node-per-object for mass objects

**Rule:** Mass flora, decor, and debris must not be instantiated as one `Node`
per object.

### Use:
- `MultiMeshInstance2D` for static mass flora
- batch placement packets
- activation of "real" interactive objects only near the player
  (proximity activation)

**Violation:** a loop like `add_child(FlowerScene.instantiate())` across
thousands of tiles.

---

## LAW 14 - Script size

| Size | Status |
|---|---|
| Up to 500 lines | Normal |
| 500-800 lines | Reason to split; must explain why it is still combined |
| Over 800 lines | **Violation** - must be split |

**Exceptions:** pure data tables, generated files.

If a file simultaneously stores data, generates data, renders data, manages
queues, and contains state patches, it is wrong and must be split regardless of
line count.

---

## LAW 15 - One file, one responsibility

Each script does exactly **one thing** from this list:
- stores data (`data`)
- computes data (`compute`)
- presents data (`view/render`)
- manages a queue (`queue/scheduler`)
- orchestrates systems (`orchestrator`)
- manages state (`state machine`)

A script that combines multiple roles is a violation.

---

## Style and conventions

### Naming (GDScript)
- files / folders: `snake_case`
- classes: `PascalCase`
- variables / functions: `snake_case`
- constants / enums: `UPPER_SNAKE_CASE`
- private names: `_private_name`
- signals: past tense (`tile_mined`, `chunk_loaded`)
- booleans: `is_`, `has_`, `can_`

### Typing
- every variable, parameter, and return value must be typed explicitly
- no exceptions, even in temporary code

### Comments
- add a comment only when **WHY is not obvious** from the code
- do not describe what the code does, only why it is done this way
- do not write multi-page docstrings

---

## Architectural patterns

### Required patterns

**Command Pattern** - for any mutation of world state (`place building`,
`mine tile`, `craft`).
The command has `execute()`, optionally `undo()`, contains all parameters, and
goes through `CommandExecutor`.

**Compute -> Apply** - the standard two-phase pattern.
- Compute: reads input data and returns a pure result (no scene-tree mutation)
- Apply: writes the result into the scene tree / state in a bounded way on the
  main thread

**Registry + namespaced IDs** - all content is accessed through a registry with
stable IDs such as `"namespace:id"`.
It is forbidden to call `load("res://data/...")` directly inside gameplay
logic.

**Deterministic hashing** - visual variation that depends on world position must
come only from a deterministic hash of coordinates and seed.
It is forbidden to use `randf()` / `randi()` for anything position-dependent.

### Recommended patterns
- State Machine - for entities with explicit modes
- Component Pattern - for reusable behavior (`health`, `fuel`, `power`)
- Factory Pattern - for building complex entities from data
- Services - for decomposing large systems

### Boundary Contract Docs

The following canonical docs are part of the architecture, not decorative
description:

- `docs/02_system_specs/meta/system_api.md` - safe entrypoints and public reads
- `docs/02_system_specs/meta/commands.md` - allowed mutation paths
- `docs/02_system_specs/meta/event_contracts.md` - important domain events and
  their payloads
- `docs/02_system_specs/meta/packet_schemas.md` - boundary data shapes and
  save/payload/result schemas

Mandatory rules:

- before any new feature or cross-system integration, read the relevant
  boundary docs first, then code
- if a documented safe path already exists, use it instead of another system's
  private/internal method
- if a new public API, safe entrypoint, or public read surface appears, update
  `system_api.md` in the same task
- if a new command or allowed mutation path appears, update `commands.md` in
  the same task
- if an important event changes, or its payload / emitter / listener-facing
  contract changes, update `event_contracts.md` in the same task
- if the shape of a `Dictionary`, save payload, command result, event payload,
  or any other boundary packet/schema changes, update `packet_schemas.md` in
  the same task
- if the needed surface does not exist yet, you may not silently bypass it
  through raw state; first define and document the new safe path explicitly

### EventBus

`docs/02_system_specs/meta/event_contracts.md` owns the documented surface of
important domain events.

Default boundary for communication between systems:
- systems emit domain events; they do not mutate other systems directly
- UI subscribes and dispatches, but does not own game state
- mods subscribe to events instead of patching core

---

## Data, localization, and saves

### Data
- gameplay data belongs in data assets (`.tres` `Resource`), not in code
- new content is added through data, not by editing logic
- content identity uses stable string IDs, not paths

### Localization
- no user-facing text in code
- key families: `UI_*`, `ITEM_*`, `BUILD_*`, `LORE_*`, `SYSTEM_*`
- data resources store keys such as `display_name_key`, not translated text
- new content must ship RU and EN keys together

### Saves
- persistent systems explicitly define what belongs in save state
- base world data is not saved; it is recreated from seed + `world_version`
- diff / overlay are persisted explicitly
- state is serialized as data, not as implicit scene state

### Mods
- new systems must be designed so content can be added, overridden, and
  extended
- use IDs, registries, data resources, and event hooks
- forbidden: assumptions that close off the content set

---

## Anti-patterns (forbidden)

- magic numbers in gameplay logic
- string-path node coupling (`$"../../../SomeNode"`)
- God classes (one class knows everything)
- direct system-to-system references that bypass `EventBus` / `Command`
- type switching on strings instead of polymorphism
- "the object count is still small" as an argument against a dirty unit
- a "temporary" GDScript fallback instead of native code
- synchronous heavy work on the main thread
- `load()` on a runtime path without preloading
- hundreds of tiny C++/GDScript calls instead of one chunk packet
- `add_child` in a loop over mass objects
- multiple systems acting as owners of the same data
- mutating base terrain after chunk generation
- changing canonical generation without bumping `world_version`

---

## Checklist before finishing a task

```
[ ] Law 0:  all 12 classification questions answered
[ ] Law 1:  heavy operations are in C++ GDExtension, not GDScript
[ ] Law 2:  the main thread is not blocked by compute work
[ ] Law 3:  the chunk generator is a pure function with no external dependencies
[ ] Law 4:  world_version was increased if canonical output changed
[ ] Law 5:  base terrain does not mutate; diff / overlay are separate
[ ] Law 6:  data crosses the C++/GDScript boundary in one packet
[ ] Law 7:  no load() / ResourceLoader.load() on the runtime path
[ ] Law 8:  each data type has a single owner
[ ] Law 9:  no hidden GDScript fallback for native-dependent paths
[ ] Law 10: a chunk is shown only after the gameplay layer is ready
[ ] Law 11: a dirty unit is defined for each runtime-sensitive system
[ ] Law 12: no global prepass at startup
[ ] Law 13: no node-per-object for mass objects
[ ] Law 14: the script is under 500 lines (or justified up to 800)
[ ] Law 15: one script - one responsibility
[ ] All public APIs are typed
[ ] No hardcoded gameplay data
[ ] Registries / events updated for new systems or content
[ ] Localization complete for new player-facing text
[ ] Save/load boundary defined
[ ] The mod path is not blocked
```

---

## AI agent behavior

An AI agent writing code for this project must:

1. Read this file before writing code.
2. Answer all 12 questions from Law 0 before a new feature.
3. Not create GDScript code for operations that may become heavy.
4. Not add a hidden GDScript fallback when native code is unavailable.
5. Name the dirty unit, data owner, and escalation path for runtime-sensitive
   changes.
6. Challenge designs justified only by "the object count is still small."
7. Not mix compute and apply inside one function.
8. Not create parallel architectures when an approved pattern already exists.
9. Check `world_version` on any generation change.
10. Not use `load()` on a runtime path.
