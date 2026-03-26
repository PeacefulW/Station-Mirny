---
title: Underground Fog of War MVP Rollout
doc_type: execution
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
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
Do not merge multiple iterations into one giant unreviewable implementation if that increases risk.

## Iteration 0 — Read and align

Goal:
- confirm all required docs are read
- confirm implementation plan respects them
- identify existing staircase/underground test hooks and current auto-spawn behavior

Deliverables:
- short implementation note or PR summary listing the docs used
- confirmation of what existing staircase spawn behavior is removed or preserved

Acceptance:
- no architecture is introduced that conflicts with current docs
- current bug source is identified (or at least current auto-spawn path is identified)

## Iteration 1 — Remove bad automatic basement entry behavior

Goal:
- normal game start must no longer dump the player into the basement by accident
- auto staircase placement must be removed if it still exists as default startup behavior

Tasks:
- identify and disable automatic staircase spawn on ordinary startup
- ensure the normal player spawn flow remains surface-correct
- ensure underground entry happens only through explicit debug/test action for now

Acceptance:
- starting a normal session does not automatically place the player underground
- staircase no longer appears automatically as part of normal startup

## Iteration 2 — Debug staircase placement and tiny underground pocket

Goal:
- temporary debug hotkey `J` creates a staircase and linked underground pocket

Tasks:
- add or wire temporary debug staircase placement to `J`
- create a linked underground destination when placed
- create only a tiny initial open pocket:
  - stair destination tile
  - player spawn/arrival tile
  - optionally one extra support tile if needed
- everything else remains solid rock

Acceptance:
- pressing `J` produces a valid test staircase
- descending leads to a tiny underground pocket only
- the rest of surrounding underground remains enclosed rock

## Iteration 3 — Underground no-roof MVP rule

Goal:
- underground does not use surface-style roof-open/roof-close presentation in this MVP

Tasks:
- ensure underground tiles/spaces do not rely on surface room roof reveal logic
- ensure excavated underground cells remain visible according to underground visibility/fog rules instead of room-roof rules

Acceptance:
- underground presentation no longer behaves like a house roof opening/closing system
- digging out space underground results in stable visible carved space according to the underground rules

## Iteration 4 — Underground fog of war state MVP

Goal:
- introduce the discovery/visibility layer for underground space

Tasks:
- implement a simple underground visibility/discovery model with at least:
  - unseen
  - discovered but not currently visible
  - currently visible
- apply this only to underground scope for the MVP
- keep the model cheap and local

Acceptance:
- newly entered underground space is not fully readable beyond the immediate reveal radius
- previously visited underground may remain partially remembered if implemented
- unseen underground remains hidden/dark enough to prevent fully reading the surrounding mass

## Iteration 5 — Local reveal bubble around player / local light context

Goal:
- only nearby underground space is clearly visible

Tasks:
- add a small reveal radius around the player underground
- ensure immediate walking/copying/digging space is readable
- ensure distant underground remains dark/hidden
- ensure entry into underground does not visually expose a large region at once

Acceptance:
- player can read immediate nearby space
- distant underground is not fully visible
- visibility feels local and claustrophobic rather than map-like

## Iteration 6 — Reveal-by-excavation behavior

Goal:
- excavation expands visible knowledge of the underground naturally

Tasks:
- when a solid rock cell is excavated, it becomes open space
- newly opened space becomes visible/revealed locally
- adjacent underground discovery may update in a bounded local way if needed
- no whole-region reveal is allowed

Acceptance:
- digging feels like expanding a safe/readable pocket into darkness
- only local space changes visibility when digging
- no global underground repaint occurs

## Iteration 7 — Underground hidden-mass presentation

Goal:
- unseen underground reads as dark mass, not fully readable mountain geometry

Tasks:
- add a presentation treatment for unseen underground mass
- ensure the player does not see clear full rock geometry far beyond visibility
- presentation should hide build/reveal behavior rather than expose streaming artifacts

Acceptance:
- unseen underground reads as unknown heavy darkness / black mass
- the player no longer watches distant underground visibly draw in around them

## Iteration 8 — Underground-specific rock visuals

Goal:
- underground rock and rock faces have an interior visual identity distinct from the surface

Tasks:
- add or wire distinct underground rock textures/tiles/visual states
- ensure visible underground rock face uses the underground style
- ensure unseen hidden mass and visible rock face remain distinguishable if the art supports that split

Acceptance:
- underground no longer looks like surface mountain tiles shown in a different place
- carved underground space feels visually interior and enclosed

## Iteration 9 — Performance validation and cleanup

Goal:
- confirm the solution improves the feel without violating runtime law

Tasks:
- profile underground entry and first reveal behavior
- ensure no large synchronous rebuild is triggered on entry
- ensure local dig does not trigger full underground redraw/recompute
- clean up temporary debug comments and keep only the intended temporary testing hooks

Acceptance:
- underground entry no longer visibly paints in large nearby space
- no obvious hitch is introduced by the new visibility system
- the implementation remains local, bounded, and consistent with performance rules

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
