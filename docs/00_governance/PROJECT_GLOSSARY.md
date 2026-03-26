---
title: Project Glossary
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ENGINEERING_STANDARDS.md
  - PERFORMANCE_CONTRACTS.md
  - SIMULATION_AND_THREADING_MODEL.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../02_system_specs/world/world_generation_foundation.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
---

# Project Glossary

Canonical definitions for shared terminology across Station Mirny documentation and code.
If a term is used in specs, ADRs, or code comments — it must mean what this file says.

---

## Runtime & Performance

### Interactive path
Synchronous code that runs in direct response to a player action (click, keypress) within the same frame. Must complete in < 2 ms for building operations, < 1 ms for movement. Allowed to: mutate one local object, mark dirty regions, enqueue deferred work, emit signals. Forbidden to: trigger full rebuilds, scan all entities, do mass scene-tree mutations. See: PERFORMANCE_CONTRACTS.md.

### Background work
Deferred processing that runs during normal gameplay through FrameBudgetDispatcher within a per-frame time budget (~6 ms total). Shape: `event → dirty mark → queued work → bounded per-frame processing → completion`. Target for: room recomputation, power network recalculation, topology maintenance. See: ADR-0001.

### Boot-time work
Expensive operations that run during initialization (behind a loading screen), not during interactive gameplay. Allowed to: load all initial chunks, run full topology rebuilds, do synchronous room/power recalculation after save restore. Must not: leak into runtime interactive or background paths. See: ADR-0001, SIMULATION_AND_THREADING_MODEL.md.

### Dirty queue
A FIFO data structure with deduplication (`RuntimeDirtyQueue`) used to track which regions or systems need deferred recomputation. When a player action changes state (e.g., places a wall), the affected position is enqueued. A background job later pops items and processes them within frame budget. Prevents duplicate work and decouples interactive response from heavy computation.

### Frame budget
The total time allowed for background work per frame. Currently 6 ms out of ~16.6 ms (60 FPS target). Distributed across categories by priority: streaming > topology > visual > spawn. Managed by `FrameBudgetDispatcher`.

### Hitch
A single frame that exceeds 22 ms (drops below ~45 FPS). Tracked by `WorldPerfMonitor`. Hitches in interactive paths indicate performance contract violations.

### Performance contract
A documented maximum time for a specific interactive operation. Violations emit warnings via `WorldPerfProbe`. Contracts: building place/remove/destroy < 2 ms, mine tile < 2 ms, player step < 1 ms. See: PERFORMANCE_CONTRACTS.md.

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
A continuous deterministic scalar field sampled by world coordinates. Channels define what the world IS at any point. Target channels: height, temperature, moisture, ruggedness, flora_density. Same seed + same coordinates = same value, always. No chunk-local randomness. See: world_generation_foundation.md.

### Biome resolver
A data-driven system that takes world channel values at a position and returns the winning biome. Evaluates registered BiomeData candidates by score/conditions (min/max height, temperature, moisture). Adding a biome = adding a .tres file, not editing generator code. Not yet implemented.

### Large structure
A world-scale geographic feature generated at Layer 2: mountain ridges, river systems, floodplains, dry belts, cold belts. Large structures influence biome resolution and provide world readability at distance. Currently: mountains exist as noise blobs, not structured ridges. Rivers not implemented.

### Local variation / Subzone
A micro-region within a biome that modifies its character without replacing its identity. Types: sparse flora, dense flora, clearing, rocky edge, wet pocket. Reduces visual repetition without multiplying top-level biomes. Layer 4 of world generation. Not yet implemented.

### Wrap-world
World topology where the X axis wraps seamlessly (cylindrical). Moving far enough east returns you to the west. Y axis carries latitude logic (temperature gradient). Sampling must be wrap-safe — no seams at wrap boundary. Defined in spec, not yet enforced in code.

### Chunk
A fixed-size tile grid (default 64x64 tiles) used as the streaming, rendering, and persistence unit. Chunks are loaded/unloaded based on player proximity. A chunk is a cache/materialization of world truth, not a source of identity. World truth comes from channels + resolver + structures; chunks just render it.

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
Any underground layer (z < 0). Includes cellars, mines, and deeper excavated spaces. Has distinct environmental rules: no natural light, different threat profile, excavation-based traversal. See: subsurface_and_verticality_foundation.md.

### Connector / Vertical connector
A structure that links Z-levels: stairs, ladders, hatches. Has stable identity for persistence and streaming. Currently: `ZStairs` with source_z/target_z. Both ends must exist for the connection to work.

### Excavation
The process of converting solid rock mass into traversable space underground. Solid → mined floor → buildable room. Distinct from surface construction. Creates subsurface topology that must be streamed and persisted.

---

## Survival & Pressure

### Visibility pressure
The degree to which environmental conditions limit the player's ability to see and navigate. Sources: darkness (night, underground, power loss), weather (storms, fog), spore density. Light is safety; darkness is threat. Gameplay must expose explicit visibility state, not scrape the renderer. See: lighting_visibility_and_darkness.md.

### Spores
Pervasive biological hazard on the planet surface. Dual threat: damages the engineer (cough, hallucination, sickness) and contaminates machinery (clog, filter degradation). Sealed rooms with filtration protect against spores. Central to the Adaptation vs Terraformer late-game divergence.

### Life support
The set of base systems that maintain habitable conditions inside sealed rooms: O2 generation/distribution, temperature regulation, spore filtration, water supply. Requires power. Loss of life support = interior becomes hostile.

---

## Documents & Process

### Source of truth
A document marked `source_of_truth: true` in frontmatter. When multiple documents discuss the same topic, the source of truth wins. See: DOCUMENT_PRECEDENCE.md.

### Canon
Locked lore or design facts that cannot be contradicted by future content. Maintained in `docs/03_content_bible/lore/canon.md`. Example: "the planet has pervasive spores" is canon; "spores are sentient" is an open question.

### System spec
A technical specification in `docs/02_system_specs/` that defines how a game system works. Has approval status (draft/approved). Code must conform to approved specs. If code and spec disagree, spec is canon — update spec first, then code.

### ADR (Architecture Decision Record)
A document in `docs/05_adrs/` that records a significant architectural decision, its context, and consequences. Once approved, it governs implementation. Example: ADR-0001 defines the runtime work classification for the entire project.

### Iteration brief
An execution-level document that defines scope, deliverables, and success criteria for a single iteration of work. Lives in `docs/04_execution/` or `TASK.md`.

---

## Mod & Extension

### Registry
A canonical access point for game data: items, recipes, buildings, biomes, resource nodes. All gameplay lookups go through registries, not hardcoded lists. Mods extend registries by registering new .tres resources. Currently: `ItemRegistry` autoload handles items, recipes, buildings, resource nodes.

### Data-driven
Design principle: gameplay parameters (balance, content definitions, IDs) live in Resource files (.tres), not in GDScript code. Enables: mod extension, balance tuning without recompile, clean separation of design from engineering. Golden rule from ENGINEERING_STANDARDS.md.
