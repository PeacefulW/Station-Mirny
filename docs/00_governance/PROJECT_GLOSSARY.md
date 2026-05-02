---
title: Project Glossary
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.4
last_updated: 2026-04-25
related_docs:
  - ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../05_adrs/0005-light-is-gameplay-system.md
  - ../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Project Glossary

Canonical definitions for shared terminology across Station Mirny documentation and code.
If a term is used in specs, ADRs, or code comments — it must mean what this file says.

---

## Runtime & Performance

### Interactive path
Synchronous code that runs in direct response to a player action (click, keypress) within the same frame. Must complete in < 2 ms for building operations, < 1 ms for movement. Allowed to: mutate one local object, mark dirty regions, enqueue deferred work, emit signals. Forbidden to: trigger full rebuilds, scan all entities, do mass scene-tree mutations. See: ADR-0001.

### Background work
Deferred processing that runs during normal gameplay through FrameBudgetDispatcher within a per-frame time budget (~6 ms total). Shape: `event → dirty mark → queued work → bounded per-frame processing → completion`. Target for: room recomputation, power network recalculation, topology maintenance. See: ADR-0001.

### Boot-time work
Expensive operations that run during initialization (behind a loading screen), not during interactive gameplay. Allowed to: load all initial chunks, run full topology rebuilds, do synchronous room/power recalculation after save restore. Must not: leak into runtime interactive or background paths. See: ADR-0001.

### Dirty queue
A FIFO data structure with deduplication (`RuntimeDirtyQueue`) used to track which regions or systems need deferred recomputation. When a player action changes state (e.g., places a wall), the affected position is enqueued. A background job later pops items and processes them within frame budget. Prevents duplicate work and decouples interactive response from heavy computation.

### Frame budget
The total time allowed for background work per frame. Currently 6 ms out of ~16.6 ms (60 FPS target). Distributed across categories by priority: streaming > topology > visual > spawn. Managed by `FrameBudgetDispatcher`.

### Hitch
A single frame that exceeds 22 ms (drops below ~45 FPS). Tracked by `WorldPerfMonitor`. Hitches in interactive paths indicate performance contract violations.

### Performance contract
A documented maximum time for a specific interactive operation. Violations emit warnings via `WorldPerfProbe`. Contracts: building place/remove/destroy < 2 ms, mine tile < 2 ms, player step < 1 ms. See: ADR-0001 and ENGINEERING_STANDARDS.md.

---

## State & Authority

### Authoritative state
Game truth that drives gameplay decisions and is persisted in save files. Examples: wall positions, player health, inventory contents, power supply/demand. If authoritative state is lost, the game is broken. Contrast with: derived state.

### Derived state
Data reconstructed from authoritative state. Not saved — recalculated on load or when source changes. Examples: indoor_cells (derived from wall positions via flood-fill), total_supply/total_demand (derived from active power components), mountain topology (derived from terrain). Losing derived state is acceptable — it can be rebuilt.

### Transient runtime state
Temporary structures that exist only during a play session and have no meaning across save/load boundaries. Examples: dirty queues, dispatcher job handles, heartbeat timers, deficit edge-detection flags (_was_deficit). Never serialized.

### Runtime diff
Modifications made to the deterministic world base during gameplay. The world is generated from a seed (immutable base); player actions (mining, building) create diffs stored per-chunk. Save files contain only diffs, not the full world. On load: base is regenerated from seed, diffs are applied on top.

### Canonical identity
A stable, unique identifier for a game entity that survives save/load, multiplayer replication, and mod extension. Examples: `"base:iron_ore"` (item ID), `"wall"` (building ID), biome StringName. Canonical IDs live in registries (`ItemRegistry`), not in code branches.

---

## World & Generation

### World channel
A continuous deterministic scalar field sampled by world coordinates. Channels define what the world IS at any point. Target channels: height, temperature, moisture, ruggedness, flora_density. Same seed + same coordinates = same value, always. No chunk-local randomness. See: ADR-0002 and ADR-0007.

### World bounds
The finite size of a V1 cylindrical world in tiles: `width_tiles` wraps on X,
`height_tiles` bounds Y. Stored in `worldgen_settings.world_bounds` for
`world_version >= 9`.

### WorldPrePass substrate
The coarse world-foundation substrate defined by `world_foundation_v1.md`.
It is native worldgen data, seed-derived, RAM-only, and owned by `WorldCore`.
V1-R1A lands the settings/save boundary; V1-R1B lands the native substrate
compute, cache, spawn-result read, and dev/debug snapshot surface. V1-R1D
documents the future biome resolver read seam, but does not add new biome
content.

### Hard-band Y edge
A finite-world Y boundary expressed as an impassable biome band derived from
latitude, not as a literal wall terrain override.

### Ocean band
The top-Y hard band in V1 worlds. Its thickness is saved as
`worldgen_settings.foundation.ocean_band_tiles`.

### Burning band
The bottom-Y hard band in V1 worlds. Its thickness is saved as
`worldgen_settings.foundation.burning_band_tiles`.

### Biome resolver
A data-driven system that takes world channel values at a position and returns
the winning biome. It evaluates registered `BiomeData` candidates by
score/conditions: channel ranges plus bounded structure context. Adding a biome
must be a `.tres` / registry extension path, not a generator code branch. V1-R1D
documents that future substrate-aware biome resolution reads structure context
through `WorldComputeContext.sample_structure_context(world_tile)` backed by
`WorldPrePass`; implementation of ocean, burning, latitude-belt, and
continental biomes belongs to a future biome spec.

### Large structure
A world-scale geographic feature generated at Layer 2: mountain ridges and
future macro-landform systems. Large structures influence biome resolution and
provide world readability at distance. Current code stores finite
bounds/foundation settings and owns shared macro-structure fields through the
native `WorldPrePass` substrate for future consumers.

### Local variation / Subzone
A micro-region within a biome that modifies its character without replacing its identity. Types: sparse flora, dense flora, clearing, rocky edge, wet pocket. Reduces visual repetition without multiplying top-level biomes. Layer 4 of world generation. Implemented: `LocalVariationResolver` samples five variation kinds from seeded periodic noise; variation ids and modulation channels (`flora_modulation`, `wetness_modulation`, `rockiness_modulation`, `openness_modulation`) propagate into chunk output and downstream consumers.

### Wrap-world
World topology where the X axis wraps seamlessly (cylindrical). Moving far enough east returns you to the west. Y axis carries latitude logic (temperature gradient). Sampling must be wrap-safe - no seams at wrap boundary. For `world_version >= 9`, X wraps at the saved `world_bounds.width_tiles`; Y does not wrap and is bounded by biome bands.

### Biome
A named world region with distinct environmental identity: terrain palette, flora set, resource distribution, threat profile, temperature range, spore density. Determined by the biome resolver from world channel values at a position. Biomes define what a place IS — its permanent geographic character. Examples: plains, foothills, mountains, wet lowland, dry/scorched zone, cold zone. Each biome is a `.tres` resource (BiomeData), not a code branch.

### Height
World channel (0.0–1.0) representing elevation. Drives: mountain placement,
biome selection (high = mountains/foothills, low = lowlands), and visibility
distance. The most fundamental channel — everything else builds on top of it.

### Moisture
World channel (0.0–1.0) representing water availability at a position. Drives:
biome selection (high = wet lowland, low = dry/scorched), flora density, and
resource distribution.

### Cave
An underground space inside a mountain, accessed by mining through rock. Distinct from cellar (player-built underground beneath base). Caves are discovered, not constructed. Environmental rules: no natural light, potential for unique resources, enclosed threat profile. Cave topology is generated from mountain structure + player excavation. See: ADR-0006.

### Tile
A logical world cell used for gameplay coordinates, building placement, and world mutations. The current rebuild contract maps one world tile to `32x32` presentation pixels. Gameplay and save math stay tile-based; pixels are presentation scale only.

### Chunk
A fixed-size tile grid (current rebuild contract: `32x32` tiles) used as the streaming, rendering, and persistence unit. Chunks are loaded/unloaded based on player proximity. A chunk is a cache/materialization of world truth, not a source of identity. World truth comes from channels + resolver + structures; chunks just render it.

---

## Environment Runtime

The environment runtime is the layer that answers: **"what does this place feel like RIGHT NOW?"**

World generation defines what a place IS (biome, terrain, elevation). Environment runtime defines what state it is IN (time of day, weather, season, wind, temperature exposure, visibility). Generation is stable and deterministic. Environment runtime changes every frame.

See: ADR-0007.

### World generation vs Environment runtime
- **Generation**: "this is a cold mountain biome at elevation 0.8 with low moisture" — permanent, from seed
- **Runtime**: "it's night, a storm is passing, wind is 15 m/s from the north, temperature is -22C, visibility is 40 tiles" — transient, changes over time

Generation is the stable base. Runtime is the changing layer on top.

### Time of day
Runtime dimension. Drives: ambient light level, shadow angles, fauna activity patterns, player visibility. Phases: dawn, day, dusk, night. Night = darkness = exposure pressure. Currently implemented in `TimeManager` + `DaylightSystem`.

### Season
Runtime dimension on a slow cycle. Drives: base temperature offset, storm frequency, spore density, flora state. Phases: warm, spore, cold, storm. Each season shifts the balance of survival pressure. Currently: enum exists in `TimeManager`, gameplay effects not implemented.

### Weather
Runtime dimension. Transient events that modify environmental state: storms (reduce visibility, increase wind), fog (reduce visibility), clear sky. Weather is not biome — any biome can have any weather, but frequency differs. Not yet implemented.

### Wind
Runtime dimension. Direction and strength. Drives: spore drift direction, storm severity, sound occlusion, flag/smoke animation. Gameplay-authoritative (affects spore spread, not just visuals). Not yet implemented.

### Temperature exposure
Runtime-computed value combining: biome base temperature + time-of-day modifier + season modifier + weather modifier + altitude modifier + shelter state. Determines thermal stress on the player. Inside sanctuary: controlled. Outside in exposure: driven by all these factors. Not yet implemented as gameplay system.

---

## Base & Building

### Room
An enclosed space formed by walls on all sides (detected by flood-fill from exterior). A sealed room can support controlled atmosphere (O2 recovery, temperature regulation). Any breach opens the room to exterior conditions. Room state is derived (recalculated from wall positions).

### Room graph
The set of all detected rooms and their connectivity (doors, vents, breaches). Drives engineering network distribution (power per room, air per room). Currently: flat indoor_cells dictionary. Future: structured room objects with adjacency.

### Engineering room
A room classification where infrastructure systems operate: power distribution, air compression, water processing, heat regulation. Interior networks are room-scoped abstractions; exterior networks are visible infrastructure. See: engineering_networks.md.

### Airlock
A transitional structure between sealed interior and hostile exterior. Prevents instant atmospheric loss when a player exits. Not yet implemented.

---

## Underground & Verticality

### Cellar
A shallow underground space directly beneath the base (z=-1). Built by the player for shelter, storage, or protected infrastructure. The safe underground fantasy: "bunker beneath the station."

### Subsurface
Any underground layer (z < 0). Includes cellars, mines, and deeper excavated spaces. Has distinct environmental rules: no natural light, different threat profile, excavation-based traversal. See: ADR-0006.

### Underground fog of war
Per-tile visibility system for underground z-levels. Three states: **unseen** (opaque black — player has never been here), **discovered** (dimmed — player was here but moved away), **visible** (clear — within reveal radius). Fog is transient: not persisted to save, cleared on z-level entry. Implemented as a TileMapLayer (`_fog_layer`, z_index 7) on each underground chunk. See: ADR-0006.

### Connector / Vertical connector
A structure that links Z-levels: stairs, ladders, hatches. Has stable identity for persistence and streaming. Currently: `ZStairs` with source_z/target_z. Both ends must exist for the connection to work.

### Excavation
The process of converting solid rock mass into traversable space underground. Solid → mined floor → buildable room. Distinct from surface construction. Creates subsurface topology that must be streamed and persisted.

---

## Survival & Pressure

### Visibility pressure
The degree to which environmental conditions limit the player's ability to see and navigate. Sources: darkness (night, underground, power loss), weather (storms, fog), spore density. Light is safety; darkness is threat. Gameplay must expose explicit visibility state, not scrape the renderer. See: ADR-0005.

### Sanctuary
The emotional and mechanical state of being inside a sealed, powered base. Core fantasy of the game: "inside feels safe." Sanctuary means: O2 recovers, temperature is controlled, spores are filtered, light is stable, threats are outside. The contrast between sanctuary and exposure drives every gameplay decision. See: GAME_VISION_GDD.md, NON_NEGOTIABLE_EXPERIENCE.md.

### Exposure
The opposite of sanctuary — being outside the base or in a breached/unpowered room. Exposure means: O2 depletes, temperature is hostile, spores accumulate, visibility degrades, fauna is a threat. The player's primary motivation is to minimize exposure time while maximizing what they accomplish during it. Every expedition is a race against exposure.

### Spores
Pervasive biological hazard on the planet surface. Dual threat: damages the engineer (cough, hallucination, sickness) and contaminates machinery (clog, filter degradation). Sealed rooms with filtration protect against spores.

### Life support
The set of base systems that maintain habitable conditions inside sealed rooms: O2 generation/distribution, temperature regulation, spore filtration, water supply. Requires power. Loss of life support = interior becomes hostile.

---

## Documents & Process

### Source of truth
A document marked `source_of_truth: true` in frontmatter. When multiple documents discuss the same topic, the source of truth wins. Use `docs/README.md` as the navigation entrypoint for the current canonical set.

### Canon
Locked lore or design facts that cannot be contradicted by future content. Maintained in `docs/03_content_bible/lore/canon.md`. Example: "the planet has pervasive spores" is canon; "spores are sentient" is an open question.

### System spec
A technical specification in `docs/02_system_specs/` that defines how a game system works. Has approval status (draft/approved). Code must conform to approved specs. If code and spec disagree, spec is canon — update spec first, then code.

### ADR (Architecture Decision Record)
A document in `docs/05_adrs/` that records a significant architectural decision, its context, and consequences. Once approved, it governs implementation. Example: ADR-0001 defines the runtime work classification for the entire project.

### Iteration brief
An execution-level document that defines scope, deliverables, and success criteria for a single iteration of work. Lives in the current approved spec, task brief, or another explicitly named task-local document.

---

## Mod & Extension

### Registry
A canonical access point for game data: items, recipes, buildings, biomes, resource nodes. All gameplay lookups go through registries, not hardcoded lists. Mods extend registries by registering new .tres resources. Currently: `ItemRegistry` autoload handles items, recipes, buildings, resource nodes.

### Data-driven
Design principle: gameplay parameters (balance, content definitions, IDs) live in Resource files (.tres), not in GDScript code. Enables: mod extension, balance tuning without recompile, clean separation of design from engineering. Golden rule from ENGINEERING_STANDARDS.md.
