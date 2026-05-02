---
title: Lake Generation L3 — Water Presentation Layer
doc_type: iteration_brief
status: ready
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-05-02
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_L1_substrate_basin_solve.md
  - lake_generation_L2_bed_terrain_packet.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/world/terrain_hybrid_presentation.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Lake Generation L3 — Water Presentation Layer

## Required reading before you start

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/02_system_specs/world/lake_generation.md` (water presentation
   layer section)
6. Closure reports of L1 and L2
7. `docs/02_system_specs/world/mountain_generation.md` — section
   "Roof Presentation". The water layer is the structural twin of
   `roof_layers_by_mountain`; reuse the same lifecycle ideas.
8. `docs/02_system_specs/world/terrain_hybrid_presentation.md`
9. `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`
   (the future drying mechanic seam this iteration prepares)

## Goal

Render water on top of lake-bed tiles. Add one `TileMapLayer` per
chunk, populated from the `lake_flags.is_water_present` bit produced in
L2, with two visual variants (light over `LAKE_BED_SHALLOW`, dark over
`LAKE_BED_DEEP`).

The water layer is the seam for a future drying mechanic from
ADR-0007: it must be possible to mask water tiles off without writing
back into base packet, diff, or `lake_flags`. This iteration ships
only the layer; runtime masking is a future spec.

## Context

L2 now writes `lake_flags` per chunk and forwards the buffer to
`ChunkView`. Bed terrain ids are visible. The remaining gap is the
visual water surface, which the player sees as a coloured film on top
of bed tiles.

The architectural twin is `roof_layers_by_mountain` from
`mountain_generation.md`: presentation-only layer, never authoritative,
destroyed on chunk unload. We reuse the pattern, with one important
difference — only one variant axis (light vs dark), so we can use a
single `TileMapLayer` per chunk and pick the atlas variant per cell at
publish time.

## Boundary contract check

- Existing safe paths to use:
  - `ChunkView` already owns presentation; the new water layer is its
    child, sharing chunk root lifecycle
  - `WorldTileSetFactory` is the only registration seam for tile sets
  - `terrain_presentation_registry.gd` is the only registration seam for
    presentation profiles and shape/material sets
  - `FrameBudgetDispatcher.CATEGORY_STREAMING` is the existing budget
    bucket for sliced publish
- Canonical docs to update in this task:
  - `docs/02_system_specs/world/lake_generation.md` — status note
  - `docs/02_system_specs/world/terrain_hybrid_presentation.md` — only
    if the existing presentation contract is touched in shape; if you
    only add new resource registration without changing the contract,
    record `not required` with grep evidence
- New public API / event / command: none. Water masking lives in a
  future environment-runtime spec.

## Performance / scalability guardrails

- Runtime class: `background` apply (sliced publish)
- Target scale / density: at most one extra `TileMapLayer` per chunk;
  the layer is empty for chunks that contain no water; cell count is
  bounded by `1024` per chunk
- Source of truth + write owner: `ChunkView` (one per chunk)
- Dirty unit: one chunk on publish, one tile on local mutation patch
- Escalation path: if water cell count per chunk regresses publish
  budget, slice the population pass into row batches identical to the
  base layer slicing; do not move work to GDScript loops at chunk
  scale (LAW 1)

## Scope — what to do

1. Add water atlas resources:
   - `data/terrain/shape_sets/water_surface.tres` — `autotile_47` shape
     family (water tiles autotile against same-class neighbours
     in `lake_flags`)
   - `data/terrain/material_sets/water_surface_light.tres` and
     `water_surface_dark.tres` — placeholder textures are acceptable;
     `light` is roughly the colour `(170, 210, 232)`, `dark` is roughly
     `(56, 96, 140)`. The contract is that they are addressable, not
     final art.
   - `data/terrain/presentation_profiles/water_surface.tres` linking
     the shape set to the two material variants. Only **one** profile
     resource; variant choice is per-cell.
2. Extend `core/systems/world/world_tile_set_factory.gd`:
   - add `get_water_tile_set() -> TileSet` returning the shared water
     tile set with two atlas sources (light, dark)
   - register the water profile via the existing factory pattern; do
     not add a new top-level factory class
3. Extend `core/systems/world/chunk_view.gd`:
   - add `var _water_layer: TileMapLayer` initialised lazily on first
     water cell
   - on publish, iterate received `lake_flags`:
     - if bit `0` set, place a water cell at the local coordinate
     - choose `light` atlas source if the corresponding `terrain_id`
       at that local coord is `TERRAIN_LAKE_BED_SHALLOW`, otherwise
       `dark`
     - resolve atlas coords through `Autotile47.atlas_index_to_coords`
       using same-class neighbours from `lake_flags`
   - on local mutation patch (e.g. dug bed): re-evaluate the water
     cell at that coord only, plus its 4 cardinal neighbours for
     autotile-47 correction
   - on chunk unload: `_water_layer` is destroyed implicitly by
     `queue_free` of the chunk root; do not call `TileMapLayer.clear()`
4. Make sure the water layer is rendered above the base layer:
   - set `z_index` or layer order so water tiles draw over the bed
     and below any building / decor layer
   - keep the water layer non-collidable (no physics body, no input)
5. Documentation updates in the same task:
   - `docs/02_system_specs/world/lake_generation.md`: status note ("L3
     landed"); confirm the water-layer lifecycle paragraph matches the
     implementation
   - `docs/02_system_specs/world/terrain_hybrid_presentation.md`: add
     a one-line entry pointing at the water shape/material set if the
     doc currently enumerates presentation profiles by id; otherwise
     `not required` with grep evidence
   - `docs/00_governance/PROJECT_GLOSSARY.md`: add `Water presentation
     layer` and `Lake bed shallow` / `Lake bed deep` entries

## Scope — what NOT to do

- do not implement the drying / masking mechanic (future spec, not L3)
- do not animate water (no shader work in V1)
- do not add particle effects or ripples
- do not write `lake_flags` to chunk diff
- do not change packet shape (`ChunkPacketV1` is L2-frozen at this
  point)
- do not add new-game UI controls (L4)
- do not add a spawn rejection rule (L4)
- do not bump `WORLD_VERSION`
- do not modify save collectors / appliers
- do not introduce a new `EventBus` signal
- do not refactor `ChunkView` beyond adding the water layer
- do not pre-build the water layer for chunks that never received a
  water tile (lazy creation only)

## Files that may be touched

### New
- `data/terrain/shape_sets/water_surface.tres`
- `data/terrain/material_sets/water_surface_light.tres`
- `data/terrain/material_sets/water_surface_dark.tres`
- `data/terrain/presentation_profiles/water_surface.tres`

### Modified
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/world/terrain_hybrid_presentation.md` (only
  if presentation contract changes; default `not required`)
- `docs/00_governance/PROJECT_GLOSSARY.md`

## Files that must NOT be touched

- `gdextension/src/world_core.{h,cpp}` (packet output is L2-frozen)
- `gdextension/src/world_prepass.{h,cpp}` (substrate is L1-frozen)
- `gdextension/src/lake_field.{h,cpp}`
- `gdextension/src/mountain_field.{h,cpp}`
- `core/systems/world/world_runtime_constants.gd`
  (`WORLD_VERSION` does not change)
- `core/systems/world/world_diff_store.gd`
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`, `save_io.gd`
- `core/systems/world/world_foundation_palette.gd` (overview palette
  was finalised in L2)
- `scenes/ui/new_game_panel.gd`
- `core/entities/player/player.gd`
- combat, lore, UI flows unrelated to chunk presentation

## Acceptance tests

- [ ] Static: water atlas resources exist and are loaded by
      `WorldTileSetFactory.get_water_tile_set()`.
- [ ] Static: `ChunkView` exposes `_water_layer` and the population
      pass reads `lake_flags` and `terrain_ids`, never writes back
      into either.
- [ ] Static: water layer cells are placed only where bit `0` of
      `lake_flags` is set; grep confirms no other write site.
- [ ] Manual human verification: in a fresh new game with default
      `LakeGenSettings`, lakes render with light water on the
      shallow ring and dark water in the deep interior.
- [ ] Manual human verification: chunk unload destroys the water
      layer (visual: walking out of and back into a chunk shows water
      reappearing without leaks; profiler shows no `TileMapLayer`
      leak across chunk lifecycle).
- [ ] Excavation acceptance: digging a `LAKE_BED_DEEP` tile removes
      the water cell at that coordinate within the next publish slice;
      the rest of the chunk's water is untouched.
- [ ] Determinism: water tile placement and variant choice are a
      pure function of the corresponding chunk packet output; replay
      with the same seed produces an identical visible water pattern.
- [ ] No regression at zero density: with `lake_density = 0.0`, no
      water layer is created for any chunk (lazy creation rule).
- [ ] Performance: chunk publish median time grows by `≤ 0.5 ms` on
      a reference seed with `lake_density > 0`; manual human
      verification acceptable, record numbers.
- [ ] Canonical doc check: `Water presentation layer` appears in
      `lake_generation.md` and `PROJECT_GLOSSARY.md`; record line
      numbers.

## Result format

Closure report per `WORKFLOW.md`. `not required` for any canonical doc
must be backed by grep evidence.
