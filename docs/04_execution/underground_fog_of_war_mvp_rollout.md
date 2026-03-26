---
title: Underground Fog of War MVP Rollout
doc_type: execution
status: draft
owner: design+engineering
source_of_truth: true
version: 0.3
last_updated: 2026-03-26
depends_on:
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - ../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
  - ../02_system_specs/meta/save_and_persistence.md
---

# Underground Fog of War MVP Rollout

This document is the canonical execution brief for the first playable underground visibility slice.

It exists to guide AI-assisted implementation in a strict, documentation-compliant way.

This is **not** a new system foundation.
This is a concrete implementation rollout brief for a specific MVP slice.

## Mandatory instruction to the implementing AI

The implementing AI must act in **strict accordance** with the existing documentation hierarchy of the project.

Before proposing architecture or writing code for this task, the AI must read and obey at minimum:

1. `docs/00_governance/DOCUMENT_PRECEDENCE.md`
2. `docs/00_governance/ENGINEERING_STANDARDS.md`
3. `docs/00_governance/PERFORMANCE_CONTRACTS.md`
4. `docs/00_governance/SIMULATION_AND_THREADING_MODEL.md`
5. `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`
6. `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
7. `docs/02_system_specs/world/lighting_visibility_and_darkness.md`
8. `docs/02_system_specs/world/environment_runtime_foundation.md`
9. `docs/02_system_specs/meta/multiplayer_authority_and_replication.md`
10. `docs/02_system_specs/meta/save_and_persistence.md`

If any implementation idea conflicts with those documents, the documents win.

The AI must **not** invent a parallel architecture for underground visibility, hidden geometry, streaming, lighting, or persistence.

## Why this rollout exists

Current underground entry has a visible problem:
- the underground space can appear to draw/reveal itself in front of the player
- this weakens atmosphere
- this weakens underground identity
- this exposes streaming/rebuild behavior visually

At the same time, the current underground slice is intentionally still primitive:
- no full deterministic cave generation yet
- no full underground world catalog yet
- no advanced underground ecology yet

Therefore the correct next step is **not** to jump into full underground generation.
The correct next step is to make underground entry, visibility, and discovery feel correct in the current MVP.

## MVP goal

Create an MVP underground visibility/discovery layer that makes underground exploration feel:
- dark
- local
- tense
- readable only near the player or local light
- hidden beyond the immediate revealed area

The player should not see the full underground mass at once.
The player should not see the world visibly "painting in" around them when entering the underground.

## Product intent this rollout must protect

This implementation must reinforce the existing product fantasy:
- inside / controlled pocket = safer
- darkness = uncertainty and pressure
- underground = local light, limited visibility, discovery through excavation
- player expands a safe underground pocket by digging, not by having the entire underground already readable

The result must feel like the player is carving visibility and knowledge out of darkness.

## Current MVP underground rule

For this rollout, the underground is still intentionally simplified.

### Canonical temporary rule

Until full underground deterministic generation is introduced:
- underground base space is treated as solid rock by default
- the debug/test staircase creates only a tiny underground pocket
- everything outside that tiny starting pocket is solid enclosed rock
- the player expands underground space primarily by excavation
- no separate roof-open/roof-close system is used underground in this MVP

This rule is intentional and must not be bypassed by "helpful" AI creativity.

## Debug/testing rule for this rollout

The implementing AI must treat the staircase as a temporary testing feature.

### Temporary debug behavior

- remove automatic staircase spawn behavior if still present
- do not spawn the player into the basement automatically on normal game start
- staircase placement for testing should be tied to a temporary debug hotkey, currently `J`, unless the project already defines a different debug input path
- when the staircase is placed for testing, a linked underground pocket should be created immediately

This rollout assumes the underground is being actively tested through this debug path.

## Underground pocket rule for this rollout

When the debug staircase is placed and linked underground space is created, the initial underground pocket must be extremely small.

### Initial pocket target

Allowed initial open space:
- staircase destination tile
- player arrival tile next to it
- optionally one additional adjacent open tile if needed for movement/readability

Everything else around it must be solid rock.

No large starter room.
No auto-open cavern.
No accidental half-revealed underground chunk.

## Fog of war / discovery intent

This rollout introduces a simple underground visibility model that supports the current MVP and future expansion.

The model should conceptually distinguish between at least these states:

### 1. Unseen
The player has never revealed this underground area.

Desired presentation:
- very dark / black mass
- not readable as open traversable shape
- should not show full underground geometry in detail

### 2. Discovered but not currently visible
The player revealed this area previously, but it is not currently in local visibility / local light.

Desired presentation:
- much darker than currently visible space
- may preserve memory of excavated/open shape if desired
- should not read as fully safe or fully readable

### 3. Currently visible
The area is within the player's immediate visibility / local light / current reveal zone.

Desired presentation:
- normal readable underground presentation
- clear nearby navigation
- readable digging target surfaces

## Core visual rule

Underground should not show the entire surrounding rock mass in a fully readable way.

The player should mostly perceive:
- nearby visible open space
- nearby visible rock face
- dark unknown mass beyond that

This is a gameplay and atmosphere requirement, not just a cosmetic preference.

## Rock visual rule

The underground must not reuse the same visual language as surface mountain rock.

### Required distinction

There should be a clear visual difference between:
- surface rock / outdoor mountain rock
- interior underground rock / enclosed rock mass

The MVP must account for separate underground rock textures or underground rock visual styling.

The underground should feel:
- enclosed
- heavy
- dark
- interior
- unweathered compared to surface rock

## Scope of this rollout

This rollout includes:
- temporary debug staircase path for testing underground entry
- tiny linked underground starting pocket
- underground fog of war / discovery state MVP
- underground-specific hidden-mass presentation
- underground-specific rock visuals direction
- visibility-limited underground reveal around the player
- reveal-by-excavation behavior for nearby underground expansion

This rollout does **not** include:
- full procedural cave generation
- full deterministic underground content generation
- underground biome catalog
- underground fauna systems
- advanced line-of-sight simulation
- advanced stealth system
- full underground lighting overhaul beyond what is needed for this MVP
- full co-op replication of every visual nuance

## Strict non-goals

The implementing AI must **not** do any of the following in this rollout:

- do not implement full underground procedural generation yet
- do not invent a large starter underground room
- do not reveal the full chunk or full local underground region on entry
- do not add surface-style roof-open/roof-close logic underground
- do not solve this by simply making the entire underground instantly visible
- do not introduce expensive global visibility recomputation on every dig
- do not couple gameplay-critical visibility logic directly to renderer internals
- do not trigger large synchronous rebuilds in the interactive path

## Architecture constraints

The implementation must respect these project laws:

### From Performance Contracts
- no heavy rebuild in the interactive path
- background work must stay budgeted
- local action must remain local where possible
- degraded presentation is preferable to hitching

### From Simulation and Threading Model
- immediate local response is allowed
- heavier derived work must be staged or budgeted
- presentation and gameplay truth must remain conceptually separable

### From Subsurface Foundation
- underground is a real linked world layer
- underground is not a surface copy with darker tiles
- connector identity must remain stable
- local digging must not imply whole-underground rebuild

### From Lighting / Visibility Foundation
- darkness is pressure
- underground should rely on local visibility
- the edge of light/visibility matters
- gameplay systems should consume explicit visibility meaning, not scrape renderer internals

## Recommended implementation shape

The AI should prefer a simple, layered MVP implementation over a smart but unstable one.

### Recommended conceptual pieces

#### 1. Temporary staircase debug path
A debug input path that places a linked staircase and creates the tiny starting pocket.

#### 2. Underground discovery/visibility state
A lightweight underground state model for at least:
- unseen
- discovered
- currently visible

#### 3. Local reveal bubble
A small reveal radius around the player or local active underground pocket.

#### 4. Excavation-driven reveal
When solid rock is excavated, the newly opened space becomes visible/revealed according to local underground visibility rules.

#### 5. Underground hidden-mass presentation
Unseen or not-currently-readable underground space is shown as dark mass rather than fully readable terrain.

#### 6. Underground-specific rock visuals
Interior rock faces and hidden rock mass use underground-specific visuals, not surface mountain visuals.

## Iteration plan

The implementing AI must deliver this work in the following order.
Do not skip ahead.

### Iteration 0 — Read, align, and clean up entry path

Goal:
- confirm all required docs are read and implementation plan respects them
- remove bad automatic basement entry; establish debug-only underground access

Tasks:
- read all mandatory docs listed above
- identify existing staircase/underground test hooks and current auto-spawn behavior
- remove automatic staircase spawn from normal startup (player must not start underground)
- wire temporary debug hotkey `J` to place a staircase and create a tiny linked underground pocket (stair tile + arrival tile + optionally one extra tile, everything else solid rock)
- ensure underground does not use surface-style roof-open/roof-close logic in this MVP

Acceptance:
- normal game start: player spawns on surface, no staircase auto-placed
- pressing `J`: staircase appears, descending leads to tiny pocket surrounded by solid rock
- underground presentation does not behave like a house roof system
- no architecture conflicts with canonical docs

### Iteration 1 — Fog of war state model + reveal bubble

Goal:
- introduce the discovery/visibility state layer and local reveal radius for underground

Tasks:
- implement a lightweight underground visibility model with three states per tile:
  - **unseen**: player has never revealed this area
  - **discovered**: previously revealed, not currently in reveal radius
  - **visible**: within player's current reveal radius
- add a small reveal radius around the player when underground
- ensure immediate walking/digging space is readable
- ensure distant underground remains dark/hidden
- ensure entry into underground does not expose a large region at once

Acceptance:
- nearby underground space is clearly readable
- distant underground is not fully visible
- visibility feels local and claustrophobic, not map-like
- unseen tiles remain hidden enough to prevent reading surrounding mass geometry

### Iteration 2 — Excavation-driven reveal + hidden mass presentation

Goal:
- digging expands the known pocket; unseen mass reads as darkness, not readable geometry

Tasks:
- when solid rock is excavated, newly opened space transitions to visible/discovered locally
- adjacent discovery updates are bounded and local (no whole-region reveal)
- add presentation treatment for unseen underground: dark/black mass, not readable terrain
- ensure player does not see full rock geometry far beyond visibility
- presentation hides streaming/rebuild artifacts

Acceptance:
- digging feels like expanding a readable pocket into darkness
- only local space changes on dig, no global repaint
- unseen underground reads as unknown heavy darkness
- player no longer watches distant underground visibly draw in

### Iteration 3 — Underground-specific rock visuals

Goal:
- underground rock has its own interior visual identity, distinct from surface mountain rock

Tasks:
- add or wire distinct underground rock textures/tiles/visual states
- visible underground rock face uses the underground style (enclosed, heavy, dark, unweathered)
- unseen hidden mass and visible rock face remain distinguishable where art supports it

Acceptance:
- underground no longer looks like surface mountain tiles in a different location
- carved underground space feels visually interior and enclosed

### Iteration 4 — Performance validation, cleanup, and doc update

Goal:
- confirm the solution improves feel without violating runtime law; close the rollout cleanly

Tasks:
- profile underground entry and first reveal behavior
- ensure no large synchronous rebuild is triggered on entry or on dig
- ensure local dig does not trigger full underground redraw/recompute
- clean up temporary debug comments, keep only intended testing hooks
- update canonical docs if implementation changed any contracts:
  - `docs/00_governance/PROJECT_GLOSSARY.md`
  - `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
  - `docs/02_system_specs/world/lighting_visibility_and_darkness.md`

Acceptance:
- underground entry no longer visibly paints in large nearby space
- no obvious hitch introduced by the visibility system
- implementation is local, bounded, and consistent with performance rules
- docs and code are in sync

## Technical guidance for the AI

### Keep the MVP cheap
Prefer:
- small local visibility radius
- simple state flags
- local dirty updates
- budgeted rebuilds for any heavier visual products

Avoid:
- expensive real-time global line-of-sight
- whole-layer scans on every move
- full chunk reveal updates from one local dig
- renderer-driven gameplay logic

### Keep the MVP explicit
Prefer:
- explicit underground visibility/discovery state
- explicit distinction between visible and hidden mass
- explicit underground-only presentation path where needed

Avoid:
- vague shader-only magic with no gameplay-facing meaning
- hidden coupling to unrelated surface room systems

### Keep the MVP future-safe
This rollout must not block later:
- deterministic underground base generation from seed
- underground POIs/caves/features later
- underground fauna later
- save/load restoration of discovered or excavated underground states
- host-authoritative multiplayer later

## Suggested smoke tests

The implementing AI should use or enable smoke tests like these:

### Smoke test 1 — Normal startup
- start the game normally
- confirm player does not spawn underground
- confirm staircase is not auto-placed in ordinary startup flow

### Smoke test 2 — Debug staircase
- press `J`
- confirm staircase is placed
- descend
- confirm only tiny starting underground pocket exists
- confirm the rest is solid rock

### Smoke test 3 — Visibility feel
- descend into underground pocket
- confirm only nearby space is visible/readable
- confirm distant underground is hidden or shown as dark mass

### Smoke test 4 — Digging
- excavate one adjacent rock tile
- confirm only local space is revealed
- confirm no large-area underground repaint happens

### Smoke test 5 — Visual identity
- compare surface rock vs underground rock
- confirm underground rock feels like interior mass rather than outdoor mountain terrain

## Required documentation updates after implementation

If code is changed for this rollout, the implementing AI must also update any canonical docs that become stale.

At minimum, the AI must check whether the implementation requires updates to:
- `docs/00_governance/AI_PLAYBOOK.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
- `docs/02_system_specs/world/lighting_visibility_and_darkness.md`

The AI must not leave the code and docs silently drifting apart.

## Completion criteria

This rollout is complete when all of the following are true:
- the player no longer starts in the basement accidentally
- underground entry is controlled by an explicit temporary debug path
- entering underground no longer visually reveals a broad area around the player in an ugly way
- underground nearby readability is good enough for movement and digging
- distant underground remains hidden or strongly obscured
- excavation expands the known underground pocket locally
- underground uses an interior rock visual language distinct from the surface
- the implementation does not violate performance contracts or introduce obvious new hitches

## Final instruction to the implementing AI

Do not overbuild this.
Do not replace the current MVP with a premature full underground generation system.
Do not solve an atmosphere/visibility problem with a giant expensive simulation.

Implement the smallest correct architecture-compliant slice that:
- hides bad underground draw-in
- strengthens underground darkness and discovery
- supports digging-driven expansion
- stays compatible with the documented future direction

## Implementation Status

### Iteration Status

| # | Iteration | Status |
|---|-----------|--------|
| 0 | Read, align, clean up entry path | DONE |
| 1 | Fog state model + reveal bubble | DONE |
| 2 | Excavation reveal + hidden mass + wall visuals | IN PROGRESS |
| 3 | Underground-specific rock visuals | PENDING |
| 4 | Performance validation and cleanup | PENDING |

### Iteration 0 Changes (2026-03-26)

- Removed auto-spawn stairs from `GameWorld._ready()` — normal startup no longer places player underground
- Added KEY_J debug hotkey in `GameWorldDebug` to place staircase at mouse cursor position
- Underground pocket: 4x3 MINED_FLOOR tiles around staircase destination
- Underground chunks generate as solid ROCK (`_generate_solid_rock_chunk()` in ChunkManager)
- MountainRoofSystem z-guard: `_request_refresh()` skips when active z != 0 (ADR-0006)

**New files:** `core/systems/world/underground_fog_state.gd`

### Iteration 1 Changes (2026-03-26)

- `UndergroundFogState` class: tracks revealed/visible tiles, compute visible circle (radius 5), update delta
- Fog tileset: 2 tiles (UNSEEN = opaque black, DISCOVERED = semi-transparent dark) via `ChunkTilesetFactory.create_fog_tileset()`
- `Chunk._fog_layer` (TileMapLayer, z_index 7): initialized for z != 0, filled with UNSEEN on creation
- `Chunk.apply_fog_visible()` / `apply_fog_discovered()`: toggle fog tiles per visibility state
- `ChunkManager._fog_update_tick()`: TOPOLOGY budget job, updates fog when player moves underground
- All chunk creation paths (boot, runtime, ensure_pocket) init fog layer for z != 0

### Iteration 2 Changes (2026-03-26)

- `Chunk.is_fog_revealable()`: fog reveals only MINED_FLOOR, MOUNTAIN_ENTRANCE, GROUND, and cave-edge rocks. Solid rock mass stays hidden under fog.
- `Chunk._is_underground` flag: set before populate/redraw. Underground ROCK renders as dark `TILE_ROCK_INTERIOR` except cave-edge rocks which use full 47-variant wall faces.
- `Chunk._redraw_cover_tile()`: skips entirely for underground (no roof system underground).
- `ChunkManager.try_harvest_at_world()`: excavation force-reveals mined tile + neighbors in fog state.
- `ChunkManager.get_terrain_type_at_global()`: underground fallback returns ROCK instead of surface terrain, fixing wall variant calculation at chunk boundaries.
