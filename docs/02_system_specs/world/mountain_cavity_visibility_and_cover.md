---
title: Mountain Cavity Visibility and Cover
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-04-21
related_docs:
  - mountain_generation.md
  - terrain_hybrid_presentation.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../meta/multiplayer_authority_and_replication.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Mountain Cavity Visibility and Cover

## Purpose

Define a mountain-cave visibility system that separates:

- canonical terrain geometry
- cover / roof masking
- visible openings on the surface
- viewer-specific visibility policy

so mountain excavation no longer depends on roof-presentation heuristics to show
interior cave walls.

## Gameplay Goal

The intended player experience is:

- outside a mountain, the player sees a monolithic mountain silhouette plus any
  actually opened entrances
- the interior of a mountain base or cave is never visible from outside
- when the player crosses an entrance, they are already considered inside
- while inside their current mountain cavity, they immediately see the full
  connected orthogonal cavity, including all connected tunnels and rooms
- 47-tile cave walls are always driven by actual terrain geometry, not by roof
  reveal timing
- multiple separate mountain cavities do not reveal each other
- diagonal-only cavity connectivity is forbidden
- diagonal harvest aiming is allowed only for an actually exposed tile; a
  diagonal-only enclosed mountain tile must remain unmineable

This system must also leave an extension seam for future player-specific
visibility policy:

- own base: full connected cavity on entry
- foreign / unknown base: room-by-room visibility up to closed doors
- granted access: elevated visibility policy

## Scope

This spec owns:

- separation of terrain geometry from roof / cover presentation
- cavity-component topology for excavated mountain space
- opening detection and outside visibility rules
- player-specific current visibility policy for mountains
- presentation ordering so cover fade never races geometry updates
- debug surfaces for validating visibility state
- future extension seam for room / door-based visibility without rewriting the
  mountain foundation

## Out of Scope

This spec does not yet implement:

- room graph logic for foreign bases
- door-driven visibility propagation
- faction or team-wide access rules
- save persistence for future explored / room-by-room visibility memory
- generic reuse for all non-mountain structures
- full line-of-sight or per-ray occlusion

Those belong to later iterations built on top of this foundation.

## Related Documents

- mountain generation still owns canonical mountain packet fields
- terrain hybrid presentation still owns terrain-layer rendering rules
- save and persistence still owns the high-level runtime diff model
- multiplayer docs still own authority and replication direction

## Dependencies

- `WorldCore` packet fields for canonical mountain ownership and terrain
- `WorldDiffStore` for excavated terrain mutations
- `WorldStreamer` for loaded-chunk orchestration
- `ChunkView` for terrain and cover presentation
- `MountainRevealRegistry` for time-based alpha animation only
- `MountainResolver` or successor viewer-state resolver

## Core Architectural Statement

The system is split into four layers:

1. **Canonical geometry**
   - `terrain_ids`
   - `walkable_flags`
   - `mountain_id_per_tile`
   - future blockers such as doors remain geometry / topology inputs

2. **Derived topology**
   - `cavity_component_id`
   - `opening_id`
   - future `visibility_zone_id` / room graph data

3. **Viewer visibility policy**
   - outside: show surface openings only
   - inside current mountain cavity: show the entire connected orthogonal cavity
   - future policies may swap this for room-by-room visibility

4. **Presentation**
   - terrain layers always render geometry and 47-tile walls from terrain state
   - cover mask layers hide cells that are not visible to the current viewer
   - fade animates cover alpha only; it never decides geometry

## Data Model

### Canonical Inputs

Canonical world truth remains:

- `terrain_ids`
- `terrain_atlas_indices`
- `walkable_flags`
- `mountain_id_per_tile`
- `mountain_flags`
- `mountain_atlas_indices`

No new canonical world field is introduced in Iteration 1 unless required by a
later implementation brief.

### Derived Runtime Topology

The mountain visibility stack derives:

- `cavity_component_id`
  - non-zero only for walkable tiles with `mountain_id > 0`
  - connectivity is strictly 4-neighbor
  - diagonal-only contact does not connect cavities
- `opening_id`
  - groups one or more adjacent entrance tiles on the surface edge
- `opening tiles`
  - any walkable mountain tile with at least one 4-neighbor walkable non-mountain tile
- `viewer_visible_cavity_components`
  - for Iteration 1, either empty (outside) or exactly one full connected cavity
- `viewer_visible_openings`
  - all loaded openings around the player, independent of current active cavity

### Future Extension Seam

The runtime model must be able to add:

- `visibility_policy_id`
- `room_id`
- `portal / door blocker graph`
- per-viewer saved visibility memory

without changing canonical world ownership.

## Runtime Architecture

### 1. Geometry Presenter

`ChunkView` terrain presentation must render cave walls and floors only from
terrain geometry:

- 47-tile edges come from terrain adjacency
- roof / cover animation must not toggle cave wall signatures
- entrance edges remain correct whether the player is inside or outside

### 2. Cover Mask Presenter

A separate cover-mask presentation layer hides mountain cells that are not
currently visible to the active viewer.

Rules:

- outside:
  - all non-opening mountain cover remains closed
  - all visible openings remain visible, together with the one-tile geometry
    shell needed to render their 47-tile edge silhouette
- inside current cavity:
  - cover is open for the full connected cavity immediately on state change
  - cover also opens the one-tile mountain geometry shell around that cavity
    so interior 47-tile wall geometry, including diagonal corner notches, is
    visible while inside
  - cover stays active outside that cavity
- fade applies to cover-mask alpha only, symmetrically on reveal and conceal
- ordering must avoid one-frame artifacts where cave geometry is visible only
  after cover changes late

### 3. Viewer State Resolver

Viewer state is derived from the player tile:

- standing on an entrance tile counts as `inside`
- if the player is on a walkable mountain tile, they inherit that
  `cavity_component_id`
- if the player is outside, no cavity component is visible
- regardless of inside/outside state, visible surface openings remain available
  for presentation

### 4. Topology Updates

Digging or closing terrain must update:

- geometry presentation in the bounded dirty region
- cavity component membership for the affected loaded region
- opening membership around the affected edge
- viewer visible set if the player is currently inside the changed cavity

Interactive-path rule:

- while the player is inside a cavity, newly excavated connected tiles must
  become visible immediately with no delayed second pass

### 5. Diagonal Dig Constraint

Mountain excavation targeting may use diagonal cursor aiming, but excavation
authority remains face-based rather than corner-based.

Rules:

- a diggable mountain tile may be harvested from any cursor angle if at least
  one of its 4-neighbor faces is already exposed to a walkable tile
- the player must not be able to excavate a diagonal-only enclosed target from
  inside a room
- diagonal-only cavities must not become passable
- diagonal-only contact must render as a corner wall, not as a connected opening

## Event Contracts

The current reveal system should evolve toward viewer-cover events rather than
mountain-identity reveal events.

Iteration 1 minimum:

- preserve a single owner for cover alpha animation
- emit cover open / close transitions for the current visible cavity set
- keep debug information for:
  - `inside_outside_state`
  - `cavity_component_id`
  - `is_opening`
  - `roof_cover_open`
  - `visible_opening`
  - `wall_signature`

Later iterations may add:

- `viewer_id`
- `visibility_policy_id`
- `room_id`
- `access_mode`

## Save / Persistence Contracts

Iteration 1 mountain behavior is fully derivable and does not require new saved
viewer visibility state.

Current direction:

- outside concealment is recalculated from geometry + openings
- inside full-cavity visibility is recalculated from current player position

However, the architecture must reserve a seam for future persistent
viewer-specific explored state because foreign-base room-by-room visibility is
intended to survive save/load later.

Required seam:

- visibility policy must not be hard-coded into terrain presentation
- a later per-viewer visibility store can be attached without changing the
  canonical world packet

## Performance Class

### Interactive

- player tile change -> O(1) viewer-state lookup from cached component/opening membership
- fade tick -> alpha interpolation only
- no per-frame flood fill
- no per-frame chunk-wide rescan

### Interactive mutation

- digging updates terrain geometry in a bounded dirty region
- topology invalidation must be limited to the impacted loaded cavity / opening area
- if a larger rebuild is required, the design must keep the player-facing result
  correct immediately and defer only non-critical cache rebuild work

### Streaming / Background

- loaded chunk publish may rebuild topology products for loaded tiles
- unloaded world must not require global cave scans
- multiple caves around the player must remain viable without per-cave per-frame work

## Modding / Extension Points

Iteration 1 does not expose new modding APIs.

But the architecture must be extension-safe for:

- future door blockers
- room graph providers
- ownership / access policy providers
- player-specific visibility policies

## File Scope For Iteration 1

Likely implementation files:

- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/mountain_resolver.gd`
- `core/systems/world/mountain_entrance.gd`
- `core/entities/player/player.gd`
- `core/systems/world/*visibility*` or `*topology*` helper files introduced by the implementation brief
- `docs/02_system_specs/world/mountain_generation.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md` if a real persistence seam changes in the implementation step

Must not expand into unrelated systems in Iteration 1:

- building placement architecture
- generic door gameplay
- full room graph simulation
- networking transport
- non-mountain structure visibility

## Acceptance Criteria

- outside a mountain, only actual surface openings are visible
- outside a mountain, no interior cave room or tunnel shape leaks through cover
- entering on an entrance tile counts as inside immediately
- on entry, the entire connected orthogonal cavity opens for the player with no
  logic delay
- cover fade does not produce a frame where walls appear before or after cover in
  the wrong order
- cave wall 47-tiles come strictly from geometry and stay correct regardless of
  cover state
- diagonal harvest aiming is allowed only for exposed targets; diagonal-only
  enclosed targets remain blocked
- diagonal-only cavity contact does not connect visibility or passability
- separate cavities in the same mountain remain isolated
- multiple visible openings can exist simultaneously while the player is outside
- debug mode can show the active cavity component, opening status, inside/outside
  state, and cover-open state

## Failure Cases / Risks

- geometry and cover remain coupled, causing the same class of regressions again
- active-cavity updates require chunk-wide or world-wide synchronous scans
- entrance tiles still behave as half-inside / half-outside special cases
- openings leak interior tiles from outside
- future room/door policy would require replacing the mountain foundation instead
  of extending it

## Open Questions

- how large a loaded-cavity incremental update can remain on the interactive path
  before escalation to background work is required
- whether the final implementation should store topology cache per chunk, per
  loaded cave graph, or in a dedicated world visibility service
- how the future foreign-base room graph should handshake with mountain cavity
  components

## Implementation Iterations

### Iteration 1 - Mountain cavity / cover split

- split cave geometry from cover-mask presentation
- make opening visibility independent from interior cavity visibility
- make entry on the opening tile count as inside
- enforce exposed-face mountain excavation targeting with diagonal cursor aiming
- add debug surfaces for cavity / opening / cover state

### Iteration 2 - Viewer visibility service seam

- centralize viewer-specific visibility policy
- keep mountain policy as `full connected cavity on entry`
- add stable extension points for future room/door policies

### Iteration 3 - Foreign base / room visibility

- introduce room graph
- closed doors block visibility
- foreign / unknown bases reveal room-by-room
- granted access upgrades policy
