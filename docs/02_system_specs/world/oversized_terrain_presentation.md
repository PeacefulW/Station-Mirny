---
title: Oversized Terrain Presentation
doc_type: system_spec
status: superseded
owner: engineering+art
source_of_truth: false
version: 0.3
last_updated: 2026-05-05
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../meta/save_and_persistence.md
  - ../meta/packet_schemas.md
  - world_grid_rebuild_foundation.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - lake_generation.md
---

# Oversized Terrain Presentation

> Superseded by `world_grid_rebuild_foundation.md` version 2.0.
> The active contract now uses `64 px` logical world tiles directly, so this
> draft's "64 px presentation over 32 px logical tiles" approach is historical
> design context only.

## Purpose

Resolve the readability problem at `32 px` logical world tiles by allowing
presentation-side shape and material assets to be authored and rendered at a
larger pixel size per shape set, **without** changing the logical world tile
contract, the chunk contract, or the save contract.

This spec exists because authoring high-fidelity terrain art (notch detail,
outline, plinth, normals) at `32 px` runs out of pixels long before the visual
language matures. The current rebuild Foundation locks logical tiles at
`32 px`, which must remain. The fix lives at the presentation seam already
described in `terrain_hybrid_presentation.md`: per-shape-set `tile_size_px`.

## Gameplay Goal

Cliffs, mountain rims, and similar tall-silhouette terrain must read as
massive without making the player camera zoom in or shrinking the visible
playfield. Ground biomes that should remain spatially neutral keep their
current `32 px` presentation. Players never observe a logical tile change;
only visual fidelity changes.

## Scope

This spec owns:

- the rule that `TerrainShapeSet.tile_size_px` may exceed the logical world
  tile size of `32 px`
- the meaning of "oversized" vs "aligned" shape sets
- the rule that oversized shape sets render through `WorldTileSetFactory`
  using a presentation pixel size larger than `cell_size`
- bleed/overhang policy: which shape kinds may overhang into neighbor cells
  and which must clip
- coexistence rules with `aligned` shape sets so multiple shape sets can be
  visible in the same chunk
- generator (`Cliff Forge`) export expectations for an oversized atlas
- validation rules for oversized shape sets

## Out of Scope

This spec does **not**:

- change `world_grid_rebuild_foundation.md`'s **logical** tile contract; one
  world tile remains `32 px` for streaming, save, building grid, packet
  schemas, and command paths
- change `ChunkPacketV0` or any save payload
- introduce a new tile-coordinate system, a new chunk size, or a new world
  conversion factor
- redefine `cell_size` in `TileMap` away from `32 px`
- introduce per-cell physics or per-cell logical scaling
- mandate that any specific shape set must move to oversized presentation;
  the choice is per shape set, opt-in, and reversible

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual only. Logical world data is unchanged. |
| Save/load required? | No. Presentation only. |
| Deterministic? | Yes for visible output at a given world position, shape set, and material set. |
| Must it work on unloaded chunks? | Yes. Profile resolution stays registry-driven. |
| C++ compute or main-thread apply? | Native topology stays unchanged. Scene apply stays main-thread bounded. Shader renders pixels. |
| Dirty unit | Same as `terrain_hybrid_presentation`: one authoritative tile mutation plus bounded local visual patch. Oversize does not enlarge the dirty unit. |
| Single owner | Native owns terrain classification. Presentation owns shape/material rendering. `WorldTileSetFactory` owns the per-shape-set `tile_size_px`-aware TileSet build. |
| 10x / 100x scale path | Adding a new oversized shape set must not add native generation branches or per-tile script compute loops. |
| Main-thread blocking risk | Bounded. Atlas decoding stays in the regular preload phase. |
| Hidden fallback? | Forbidden. If a shape set declares `tile_size_px > 32`, presentation must treat it as oversized; it must not silently downsample to `32 px`. |
| Could it become heavy later? | VRAM cost grows ~quadratically with `tile_size_px`. Therefore validation must report VRAM budget against a documented ceiling. |
| Whole-world prepass? | No. No per-world bake at startup. |

## Core Terms

### `logical world tile`

The authoritative gameplay unit. Always `32 px` per
`world_grid_rebuild_foundation.md`. Streaming, save, packets, building grid,
and command paths key off this size only. **Unchanged by this spec.**

### `presentation tile pixel size`

Per `TerrainShapeSet.tile_size_px`. The pixel size at which shape and
material atlases for that shape set are authored and rendered.

It may be:

- `32` — *aligned* shape set; one logical tile = one `32x32` rendered
  region; no overhang
- `64` — *oversized* shape set; the only oversized value enabled in the
  first adoption wave
- `96`, `128` — reserved oversized values, allowed by architecture but
  not enabled by default; opt-in for later experimentation once VRAM
  ceilings exist

### `aligned shape set`

A shape set with `tile_size_px == 32`. Behaves exactly as today.

### `oversized shape set`

A shape set with `tile_size_px > 32`. Rendered through a TileSet whose
per-source `texture_region_size` matches the shape set's pixel size,
positioned over a `32 px` cell, with `texture_origin` chosen so the visible
silhouette extends predictably into adjacent cells.

### `overhang`

The portion of an oversized tile that visually extends past its own logical
cell. Constrained by overhang policy below.

### `overhang policy`

The shape set's authoring decision about which neighbor cells the silhouette
is allowed to overlap and on which axes. Recorded in the shape set resource.

## Architectural Principles

### 1. Logical truth stays at 32 px

Logical world tile size, chunk size, save sharding, packet content, and
building grid are unchanged. Anything that asks "what tile is here" still
gets a `32 px` answer.

### 2. Presentation pixel size is per shape set, not per project

`tile_size_px` already lives on `TerrainShapeSet`
(`terrain_hybrid_presentation.md` line `239`). This spec promotes it from
"data-validation field" to a **rendering-honored field**. Different shape
sets may render at different presentation pixel sizes within the same world.

### 3. Aligned and oversized may coexist in one chunk

`ground` shape sets typically stay aligned (`32 px`) so neighbor ground
tiles do not blend over each other. `cliff`, `mountain rim`, and similar
tall-silhouette shape sets may be oversized. The runtime must render both
correctly in the same chunk view.

### 4. No mixing of conversions in logic paths

`world_grid_rebuild_foundation.md` already forbids "mixing 32 and 64
conversions in parallel" (`world_grid_rebuild_foundation.md:117`). That
rule remains. **Presentation pixel size is a render-time concept that must
not leak into logical, save, packet, or command paths.** No file may use
`tile_size_px` from a shape set to compute tile coordinates, walkability,
visibility, or save sharding.

### 5. Overhang is authored, not inferred

Whether a tile overhangs north, south, east, west, or only "up" is a
property of the shape set, declared in its resource. The runtime applies
overhang exactly as authored; it does not infer overhang from texture
content or shape kind.

### 6. Generator owns oversized atlas authoring

`Cliff Forge` (the desktop generator at `tools/rimworld-autotile-lab`)
exports atlases at the chosen `tile_size_px`. The runtime never resamples
the atlas to a different pixel size. If a shape set says `tile_size_px =
64`, the runtime renders at `64 px`. Down-/up-sampling to fit a target tile
size is a generator-time decision.

### 7. Material set pixel size follows the shape set it pairs with

A `TerrainMaterialSet` is implicitly authored at the same pixel size as the
`TerrainShapeSet` it pairs with through a `TerrainPresentationProfile`.
Validation must reject pairs where the material atlas resolution does not
match the shape set's `tile_size_px`.

## Canonical Data Model Changes

### `TerrainShapeSet`

Existing canonical field used:

- `tile_size_px: int`

This spec promotes the field semantics:

- valid values for the first adoption wave: `{32, 64}`
- reserved future values, allowed by architecture but not enabled by
  default: `{96, 128}` — opening them is a data/policy change, not a
  spec/contract change
- `32` = aligned; legacy default
- `> 32` = oversized; subject to overhang policy

New canonical fields:

- `overhang_policy: TerrainOverhangPolicy` — see below

### New: `TerrainOverhangPolicy`

A small data resource (or inline struct field) describing how an oversized
shape set may extend past its `32 px` cell.

Canonical fields:

- `id: StringName` (optional; for reuse across shape sets)
- `up_px: int` — vertical overhang into the cell above (0 if none)
- `down_px: int` — vertical overhang into the cell below
- `left_px: int` — horizontal overhang into the cell to the left
- `right_px: int` — horizontal overhang into the cell to the right
- `z_order_bias: int` — render-order hint within the chunk view layer

Constraints:

- the sum of `up_px + down_px + 32` must equal `tile_size_px`
- the sum of `left_px + right_px + 32` must equal `tile_size_px`
- overhang values must be non-negative
- `aligned` shape sets must declare zero overhang

Example: `tile_size_px = 64`, `up_px = 32`, `down_px = 0`, `left_px = 16`,
`right_px = 16` — describes a tall mountain silhouette whose head extends
one cell up, balanced horizontally.

### `TerrainPresentationProfile`

No new fields. The profile continues to bind shape set + material set +
shader family. Validation must additionally check pixel-size pairing
(material set pixel size matches shape set `tile_size_px`).

### Packet contract

Unchanged. `ChunkPacketV0` carries `terrain_ids`, `terrain_atlas_indices`,
`walkable_flags`. None of these gain any pixel-size field.

### Save contract

Unchanged. `tile_size_px` is authored data, not save state.

## Runtime Architecture

### Native / C++ responsibilities

Unchanged. Native owns terrain classification, atlas-case decisions, packet
preparation. Native does not learn about `tile_size_px`.

### GDScript responsibilities

`WorldTileSetFactory` builds a TileSet whose per-source `texture_region_size`
matches the shape set's `tile_size_px`. `cell_size` of the consuming
`TileMap` (or chunk view layer) remains `32`. The TileSet's `texture_origin`
per atlas tile is computed from `overhang_policy` so the silhouette extends
predictably into neighbor cells.

`ChunkView` consumes the resolved presentation profile and applies tiles by
their authoritative `terrain_atlas_indices`. It does not compute pixel
offsets per tile.

`TerrainPresentationRegistry` (or its bootstrap path) validates pixel-size
pairing and overhang sum constraints before any chunk is published.

### Shader responsibilities

Shared shader family is unchanged. Sampling continues to use the
shape/material atlases. The shader does not know whether the shape set is
aligned or oversized.

## Render Order Rules

Within one chunk view, when an aligned ground shape set and an oversized
cliff shape set overlap visually because of overhang:

- aligned ground renders first (lower z-order)
- oversized cliff renders second (higher z-order, by `z_order_bias`)
- the overhanging cliff silhouette draws over the neighbor ground tile
- the overhanging cliff silhouette **does not** affect logical walkability
  or topology of the neighbor cell

Cross-chunk overhang at chunk seams is handled by the chunk view layer
already responsible for seam patching; oversized shape sets must not
introduce seam-patch logic that re-derives topology.

## Validation Model

In addition to the validations defined in `terrain_hybrid_presentation.md`:

- `tile_size_px` is one of the allowed values
- `overhang_policy` sums equal `tile_size_px` on each axis
- material set atlas dimensions correspond to the shape set's `tile_size_px`
  multiplied by the canonical case grid (e.g. 8 columns × ceil(case_count *
  variant_count / 8) rows)
- shader family `material_texture_params` declared sample size matches the
  material set pixel size
- VRAM ceiling: total atlas memory across all loaded shape+material sets
  must not exceed a documented ceiling defined alongside the project's
  asset budget; the validation is advisory in development and a load-time
  warning at minimum

Failure policy is unchanged: presentation hot paths must not be the first
place where mismatches are discovered.

## Performance Class

### Offline / authoring

Oversized atlases are authored offline by `Cliff Forge`. No runtime impact
from authoring time.

### Runtime memory

VRAM grows ~quadratically with `tile_size_px`:

- `tile_size_px = 32` — baseline
- `tile_size_px = 64` — 4x baseline
- `tile_size_px = 128` — 16x baseline

Per-shape-set, not per-tile. The number of unique shape sets does not
explode; oversized presentation is a property of one shape set, not of
each chunk or each tile.

### Runtime apply

Unchanged. Tile assignment cost in `ChunkView` is per-tile-changed and
indifferent to `tile_size_px`. Overhanging tiles do not require extra
per-tile compute.

### Shader cost

Unchanged. The shader samples the same texture slots whether the atlas is
authored at `32` or `64`. Larger atlases may marginally affect sampler
cache behavior; not expected to be hot.

### Boot / preload

Larger atlases extend asset decode time linearly with byte count. This is
boot work, not interactive, and stays inside the documented preload phase.

## Generator (`Cliff Forge`) Contract

The desktop generator at `tools/rimworld-autotile-lab/desktop_app` owns the
oversized atlas authoring path.

Required generator behavior:

- expose `tile_size` selection in the UI with the canonical set `{32, 64,
  96, 128}` (current `48..128` slider may be retained as long as the export
  step snaps to canonical sizes)
- export atlases at the selected pixel size with no internal resampling
- emit a manifest that records `tile_size_px`, `case_count`,
  `variant_count`, and an explicit overhang authoring hint (the runtime
  resource still defines policy, but the manifest must surface what the
  generator drew)
- export `mask atlas`, `shape normal atlas`, `albedo`, `modulation`, and
  `normal` atlases in the same pixel grid for each shape+material set

The generator does **not** own:

- the `TerrainShapeSet`, `TerrainMaterialSet`,
  `TerrainPresentationProfile`, or `TerrainOverhangPolicy` resource files —
  those are authored as `.tres` resources by the project; the generator
  produces the texture atlases consumed by them
- runtime registry registration

## Required Updates

This spec, when implementation begins, requires:

- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
  - clarify that `presentation tile pixel size` is authored per shape set
    and may exceed `32 px`
  - keep the existing rule that **logical** tile stays `32 px` and that
    32/64 mixing in logic/save/stream is forbidden
  - explicit cross-link to this spec
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`
  - promote `TerrainShapeSet.tile_size_px` from data-validation to a
    rendering-honored field
  - add `TerrainOverhangPolicy`
  - add the validation entries listed above
- `docs/02_system_specs/world/mountain_generation.md`
  - reference oversized presentation as the optional rendering target for
    cliff and rim shape sets, without changing logical mountain rules
- `docs/02_system_specs/world/lake_generation.md`
  - confirm that `water_surface` shape set remains aligned (`32 px`) unless
    a future iteration explicitly opts into oversized banks
- `docs/00_governance/PROJECT_GLOSSARY.md`
  - add `presentation tile pixel size` and `oversized shape set` glossary
    entries
- `docs/02_system_specs/README.md`
  - index this spec
- meta boundary docs are **not** required to change unless the
  implementation introduces a new public API entry point, command, event,
  or packet field. None are anticipated.

## Acceptance Criteria

The architecture is correct when:

- `TerrainShapeSet.tile_size_px` is honored by `WorldTileSetFactory`; the
  generated TileSet uses that pixel size as its `texture_region_size`
- `TileMap` `cell_size` remains `32`
- aligned shape sets (`tile_size_px = 32`) render identically to current
  baseline
- at least one oversized shape set (default candidate: a `cliff` or
  `mountain_rim` family) renders with a documented overhang policy and is
  visibly more detailed at the same camera zoom
- packet contract is unchanged; no new save fields appear
- logic, save, streaming, and command paths still see only `32 px` tiles
- validation reports an error when an oversized shape set's overhang sum
  does not match its `tile_size_px`
- validation reports an error when material set resolution does not match
  the paired shape set
- no GDScript file uses `tile_size_px` to compute logical tile coordinates,
  walkability, visibility, or save sharding (grep proof required at
  closure)
- `Cliff Forge` exports an oversized atlas at the chosen size with no
  internal resampling

## Risks

- **Doc drift risk.** The Foundation spec contains a strong "no 32/64
  mixing" line. Implementations may misread this and block oversized
  presentation. Required Updates above explicitly add the
  logical-vs-presentation distinction.
- **VRAM creep.** Multiple oversized shape sets at `128 px` with many
  biome materials can exhaust VRAM on weaker hardware. Validation surfaces
  the budget; the project must define the ceiling.
- **Camera zoom expectation.** Oversized presentation makes the visible
  playfield denser at the same screen size. Game-design must agree this is
  the intended look before catalog-wide adoption.
- **Overhang z-order interactions.** If an oversized cliff overhangs onto
  a buildable ground cell and a building is placed there, the cliff
  silhouette will draw over the building. Building presentation and
  oversized terrain presentation must agree on render order.
- **Cross-chunk overhang at seams.** Visual-only seam fixups exist already;
  oversize must not regress them.
- **Mod compatibility.** Mods that author shape sets must declare
  `tile_size_px` and overhang policy explicitly; the registry must reject
  mod resources that omit them.

## Decisions Locked

These open questions are resolved for the first adoption wave. Reopening
any of them is a spec edit, not a silent code change.

- **Allowed `tile_size_px` values.** First wave: `{32, 64}`. Reserved
  future values `{96, 128}` are architecturally permitted but require a
  follow-up data/policy decision (notably a VRAM ceiling) before they
  are enabled.
- **First canonical oversized shape set.** `mountain_rim`. Iteration 2
  authors its asset pair; Iteration 3 binds it through a presentation
  profile.
- **`TerrainOverhangPolicy` storage.** Shared resource family at
  `data/terrain/overhang_policies/*.tres`. A shape set references one
  policy by id, and several shape sets may share one policy. This
  follows the same data-driven pattern already used for
  `material_sets/`, `shader_families/`, and `presentation_profiles/`.
- **VRAM ceiling.** Defined in a future separate `asset_budget` spec,
  not here. This spec only declares the validation surface (load-time
  warning when a documented ceiling is exceeded). Until that spec
  exists, the warning is advisory only.

## Open Questions

- **Building placement vs oversized overhang.** Should oversized terrain
  be allowed to overhang a buildable cell, with z-order rules so a
  placed building still draws correctly? Or should oversized shape sets
  be forbidden from overhanging onto cells the player can build on?
  This is a game-design and presentation-z-order question; it can be
  answered before or during Iteration 3, but it must be answered before
  Iteration 4 catalog adoption.

## Implementation Iterations

### Iteration 1 — Spec land and contract clarification

Goal: land this spec and the textual updates to dependent specs so future
work has firm ground.

What changes:
- this spec lands as `draft -> approved` after review
- `terrain_hybrid_presentation.md` updated as listed in `Required Updates`
- `world_grid_rebuild_foundation.md` updated to add the
  logical-vs-presentation distinction
- `mountain_generation.md`, `lake_generation.md`, `PROJECT_GLOSSARY.md`,
  `system_specs/README.md` updated as listed
- no code changes

Acceptance tests:
- [ ] all listed canonical docs updated and cross-linked
- [ ] grep `world_grid_rebuild_foundation.md` for "32/64" — passage now
      reads as logical-only forbidden mixing, not presentation
- [ ] grep `terrain_hybrid_presentation.md` for `tile_size_px` —
      promoted to rendering-honored
- [ ] glossary entries `presentation tile pixel size` and
      `oversized shape set` exist

Files that may be touched:
- `docs/02_system_specs/world/oversized_terrain_presentation.md`
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`
- `docs/02_system_specs/world/mountain_generation.md`
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`

Files that must not be touched:
- any code under `core/`
- any data resource under `data/`
- any C++ code under `gdextension/`

### Iteration 2 — Generator export at chosen pixel size

Goal: generator (`Cliff Forge`) reliably exports a `64 px` oversized atlas
suitable for one cliff or mountain shape set, with manifest fields needed
by the runtime.

What changes:
- `Cliff Forge` UI snap-set for canonical pixel sizes
- atlas export at chosen pixel size with no resampling
- manifest extended with `tile_size_px`, `case_count`, `variant_count`,
  overhang authoring hint
- one new `data/terrain/shape_sets/<name>.tres` and
  `data/terrain/material_sets/<name>.tres` declared but **not yet wired**
  to a presentation profile

Acceptance tests:
- [ ] generator UI offers `{32, 64, 96, 128}` selections (or canonical
      snap)
- [ ] exported atlas dimensions match the chosen pixel size exactly
- [ ] manifest contains `tile_size_px`, `case_count`, `variant_count`,
      overhang hint
- [ ] one shape set `.tres` exists for the new export and references the
      exported atlas paths
- [ ] no `core/` or `gdextension/` files changed in this iteration

Files that may be touched:
- `tools/rimworld-autotile-lab/desktop_app/**`
- `data/terrain/shape_sets/<new>.tres`
- `data/terrain/material_sets/<new>.tres`
- `assets/textures/terrain/**` (new exported textures only)

Files that must not be touched:
- any approved spec (Iteration 1 owned that)
- any runtime presentation code

### Iteration 3 — Runtime honor `tile_size_px` in `WorldTileSetFactory`

Goal: aligned shape sets keep working unchanged. One oversized shape set
renders correctly with declared overhang.

What changes:
- `WorldTileSetFactory` builds a TileSet whose per-source
  `texture_region_size` matches `TerrainShapeSet.tile_size_px`
- `texture_origin` per tile is derived from `TerrainOverhangPolicy`
- `ChunkView` render-order respects `z_order_bias`
- new `TerrainOverhangPolicy` resource type added
- `TerrainPresentationRegistry` validates pixel-size pairing and overhang
  sum constraints at registry bootstrap
- one presentation profile bound to the oversized shape set so a chunk
  containing it renders the new visual

Acceptance tests:
- [ ] aligned baseline shape sets render identically to before
      (visual diff acceptable as `manual human verification required`)
- [ ] one oversized shape set renders with declared overhang
- [ ] validation rejects an artificially broken overhang policy
- [ ] no GDScript file outside presentation reads `tile_size_px`
      (grep proof of absence required)
- [ ] `ChunkPacketV0` byte layout is unchanged
- [ ] save round-trip is unchanged

Files that may be touched (by name from current repo):
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_streamer.gd`
- new presentation registry / overhang resource files under
  `core/systems/world/` and `data/terrain/overhang_policies/`
- one new `data/terrain/presentation_profiles/<oversized>.tres`

Files that must not be touched:
- any C++ in `gdextension/`
- save/persistence subsystem
- packet schema files

### Iteration 4 — Catalog adoption

Goal: identify and migrate the shape sets that genuinely benefit from
oversized presentation; leave the rest aligned.

This iteration is intentionally deferred. It depends on visual playtest
of Iteration 3 and on a documented VRAM budget ceiling.

## Out-of-Scope Notes

- Pixel-art-style procedural generation in `Cliff Forge` is a separate
  concern (see generator review notes). It can stack on top of this spec
  but is not required by it.
- Black outline, plinth, and improved normals in `Cliff Forge` are also
  separate generator-side concerns and not gated by this spec.
- Camera zoom levels in the game are not changed by this spec. If
  oversized presentation reveals a camera-feel issue, that becomes a
  product/UX task, not a foundation change.
