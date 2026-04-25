---
title: World Foundation V1
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 0.4
last_updated: 2026-04-24
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - mountain_generation.md
  - WORLD_GENERATION_PREVIEW_ARCHITECTURE.md
---

# World Foundation V1

## Status and Supersession

V1 is a new canonical spec that does **not** supersede any existing
document. It sits under `world_runtime.md`,
`world_grid_rebuild_foundation.md`, and `mountain_generation.md` and
provides the shared substrate they already implicitly depend on.

V1 formalises three decisions that were previously informal or only
present in scrapped draft material:

1. The world is **finite and cylindrical**. X wraps, Y is bounded with
   canonical impassable-biome bands at both edges (ocean at one pole,
   burning lands at the other).
2. A single shared **`WorldPrePass` substrate** owns the coarse global
   fields consumed by mountains, future rivers, future biomes, spawn
   resolution, and the new-game overview preview. River skeleton fields
   (downstream graph, flow accumulation, visible trunks, terminal lake
   candidates, Strahler order) live **natively in the substrate from day
   one**. There is no separate river Tier 0 to migrate.
3. The new-game UI exposes **world size and topology** as explicit save
   state, and supports a **full-world preview** rendered directly from
   the substrate.

V1 is approved for staged implementation. V1-R1A lands the finite
world bounds/settings/save boundary and the spawn contract amendment;
native substrate compute, overview rendering, and biome resolver
wiring remain separate iterations below.

## Purpose

Define the canonical foundation layer beneath every other worldgen spec:

1. **Topology.** Pin the world as a finite cylinder (ADR-0002, with a
   hard-band refinement on Y) and make its bounds explicit, deterministic
   save state.
2. **Shared coarse substrate.** Pin `WorldPrePass` as the single native
   class that computes the coarse global fields used by mountains,
   future rivers, future biomes, spawn, and preview. Fix its inputs,
   outputs, budget, and lifecycle.
3. **Full-world preview.** Pin the rendering contract for a whole-world
   overview that is a pure read of the substrate — no chunk batch, no
   gameplay scene.
4. **Readability.** Make the world legible as a recognisable map (clear
   source-to-mouth river candidates, contained mountain ranges,
   recognisable biome belts) without breaking determinism, streaming, or
   the runtime work classification from ADR-0001.

V1 is the substrate. It does **not** itself implement river rasterization
into tiles, biome terrain content, or chunk runtime behaviour beyond what
those existing specs already own. River skeleton fields exist inside
the substrate; the mapping from skeleton to actual riverbed tiles,
riverbed terrain ids, water overlays, and curve quality contracts is
deferred to a future river spec that consumes the substrate from day
one.

## Gameplay Goal

The player must be able to:

- create a new world at a chosen **size preset**, see its actual
  generated shape in the new-game panel before committing, and know that
  walking far enough east returns them to the west;
- approach the **top-Y pole** and find an impassable ocean band, and
  approach the **bottom-Y pole** and find an impassable burning-lands
  band — both derived from the latitude gradient, not a literal code
  wall;
- trust that future rivers will have real sources and real mouths,
  because the coarse substrate resolves drainage globally at world load
  before any tile-level river work runs;
- see **mountain ranges** that read as coherent massifs rather than
  seed-noise splinters, because mountain structure consumes the same
  substrate for large-scale height context;
- recognise the world they are playing on from an **in-menu overview**
  that matches the world they will walk through, at the level of
  continents, hard bands, and broad mountain / elevation context
  (shape-true, not tileset-perfect). River skeletons are substrate
  truth for future river rasterization and dev diagnostics, but are not
  player-facing river art until a river spec makes them real output.

## Design Principles

**Finite is a gameplay feature, not a workaround.** A bounded cylinder
is what makes recognisable rivers, meaningful cartography, and
end-to-end biome belts possible. This spec treats world finiteness as a
first-class worldgen property, not a performance concession.

**One substrate, many consumers.** Mountains, future rivers, future
biomes, spawn, and preview must all read coarse global fields from a
single native `WorldPrePass`, keyed by `(seed, world_version,
world_bounds, settings_packed)`. Adding a new consumer must not require
a second global pass.

**The substrate is boot/load work only.** `WorldPrePass` runs once per
world load, off the main thread, behind the existing world-load progress
UI (or the new-game preview debounce — no gameplay world is active
there either). It never runs during interactive gameplay and never
during chunk streaming. Its output is RAM-only and seed-derived (never
persisted to disk). This is a deliberate, documented LAW 12 exception
under the same reasoning ADR-0001 already permits for initial topology
build.

**Packets stay local.** `WorldPrePass` does not change any existing
chunk packet field shape. Chunks still receive all they need through
the existing native batch boundary; the substrate is read internally on
the native side when a batch is generated.

**Preview is a substrate read, not a second world.** The full-world
overview preview is a bounded native read plus one image publish. It is
not a hidden gameplay world, not a second generator, and never writes
save files.

**Canonical skeleton, deferred rasterization.** The substrate freezes
the river-skeleton field set (downstream graph, flow accumulation,
visible trunks, Strahler order, terminal lake candidates). Turning
those fields into actual riverbed tiles, water overlays, or beauty
contracts is the job of a future river spec that must cite V1 as its
substrate source.

## Scope (In V1-R1)

- canonical finite cylindrical topology with explicit X-wrap width and Y
  bounds, backed by save state;
- three world-size presets (`small`, `medium`, `large`) and a dev-only
  `custom` path used by headless validation;
- hard-band Y boundaries realised as impassable-biome bands (ocean /
  burning), driven by the latitude gradient (ADR-0002-compatible);
- fixed pole orientation in V1: ocean at top Y, burning lands at bottom
  Y. `pole_orientation` exists in `settings_packed` as a technical flag
  for dev and modding but is **not** exposed in the shipped new-game UI;
- `WorldPrePass` native class owning the coarse substrate:
  `latitude_t`, `ocean_band_mask`, `burning_band_mask`, `continent_mask`,
  `hydro_height`, `coarse_wall_density`, `coarse_foot_density`,
  `coarse_valley_score`, `source_score`, `biome_region_id`,
  `downstream_index`, `flow_accumulation`, `visible_trunk_mask`,
  `strahler_order`, `is_terminal_lake_center`, `terminal_lake_polygon`;
- dev-only native debug API that exposes each substrate channel as a
  snapshot image, stripped in release builds;
- full-world overview preview renderer that converts the substrate into
  a single `ImageTexture` using a canonical-channels-only palette (no
  faux biome colours in V1);
- spawn-safety contract amendment to `world_runtime.md`: the spawn
  resolver must reject any spawn tile inside an ocean or burning band,
  inside a large mountain massif, or inside a visible river trunk
  corridor, and must prefer continent_mask tiles with moderate
  `hydro_height`;
- `worldgen_settings.world_bounds` and `worldgen_settings.foundation`
  in `world.json`;
- `WORLD_VERSION` bump for the canonical-output change introduced by
  the shared substrate and the finite topology.

## Out of Scope

- any fine-resolution terrain, tile, or decor work that already belongs
  to `world_runtime.md`, `mountain_generation.md`, or
  `terrain_hybrid_presentation.md`;
- actual riverbed tile rasterization, riverbed terrain ids, water
  overlays, curve quality contracts, island or split-rejoin logic,
  atlas index selection for rivers — all deferred to a future river
  spec that consumes the V1 substrate;
- new biome content (ocean biome, burning biome, latitude belts,
  continental biomes) — deferred to a future biome spec that consumes
  the V1 substrate;
- faux biome colours in the overview palette in V1; only canonical
  substrate channels are rendered;
- environment-runtime systems (weather, season, wind, temperature);
  those remain in ADR-0007's domain;
- progressive chunk-based preview around spawn from
  `WORLD_GENERATION_PREVIEW_ARCHITECTURE.md` — that pipeline stays
  intact and is reused for detail preview beside the new overview mode;
- migration of legacy `world_version` saves beyond recording the
  version boundary;
- multiplayer replication of substrate snapshots (substrate is
  regenerated from seed on every client load);
- subsurface / Z-level topology and connector logic;
- user-facing pole-orientation toggle in the shipped UI (dev-only flag
  in V1).

## Dependencies

- `world_runtime.md` for chunk packet boundary, `WorldCore` ownership,
  streaming discipline, and `WorldStreamer` role. V1 introduces one
  amendment to its spawn section (see Spawn Contract Amendment below).
- `world_grid_rebuild_foundation.md` for `32 px` tile / `32 × 32` chunk
  contract.
- `mountain_generation.md` for mountain field and `mountain_id`
  identity; V1 adds one consumer contract (`coarse_wall_density` /
  `coarse_foot_density` aggregation) and touches nothing inside
  mountain generation itself.
- ADR-0001 for runtime work classes and dirty-update limits.
- ADR-0002 for cylindrical X wrap; V1 appends a Consequences
  clarification that Y hardness is realised through impassable-biome
  bands derived from the latitude gradient.
- ADR-0003 for base / diff ownership; substrate is base-side and is not
  diffable.
- ADR-0007 for the worldgen / environment-runtime boundary; substrate
  belongs to worldgen and must not be mutated by environment runtime.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | **Canonical.** World bounds, topology, and substrate fields drive terrain classification, biome assignment, river routing (future), and spawn. Preview image is derived / visual only. |
| Save / load required? | Yes, for `worldgen_settings.world_bounds` and `worldgen_settings.foundation` in `world.json`. The substrate itself is **not** persisted — regenerated from seed on every load. |
| Deterministic? | Yes. `WorldPrePass` output is a pure function of `(seed, world_version, world_bounds, settings_packed)`. |
| Must work on unloaded chunks? | Yes. Substrate is world-global; chunk load state is irrelevant. |
| C++ compute or main-thread apply? | Native compute on a background worker. Main thread only applies the finished overview image and consumes cached substrate reads inside native batch generation. |
| Dirty unit | Whole world, once per world load (boot class). No runtime-interactive or background-tick dirty unit — substrate is immutable for the lifetime of a world session. |
| Single owner | `WorldCore` owns `WorldPrePass`. `world.json` owns the settings copy. UI preview owns only its image publish. No other system writes substrate data. |
| 10× / 100× scale path | Coarse grid is `ceil(width / coarse_cell) × ceil(height / coarse_cell)`. At `coarse_cell = 64 tiles`, a medium world (`4096 × 2048`) is `64 × 32 = 2048` nodes; a large world (`8192 × 4096`) is `128 × 64 = 8192` nodes. Sub-linear in world area and still not a chunk/tile map. |
| Main-thread blocking? | Forbidden during normal play. Substrate compute runs behind the world-load progress UI or new-game preview debounce. |
| Hidden GDScript fallback? | Forbidden. `WorldPrePass` requires the native world core. |
| Could it become heavy later? | Bounded by coarse cell size and the frozen field list. New consumers must read existing channels or justify a new channel via spec amendment. |
| Whole-world prepass? | **Permitted under an explicit LAW 12 exception.** Runs once at world load, off main thread, RAM-only, cache-keyed to `(seed, world_version, world_bounds, settings_packed)`. Never runs during interactive gameplay. |

## Architecture

### Topology

- X axis wraps at `world_bounds.width_tiles`. Moving east past
  `world_bounds.width_tiles - 1` returns to tile `0`.
- Y axis is bounded at `0` and `world_bounds.height_tiles - 1` and does
  **not** wrap.
- Y carries the latitude gradient `latitude_t(y) = y / (height - 1)`.
  `latitude_t = 0` is the top-Y pole; `latitude_t = 1` is the bottom-Y
  pole.
- Fixed pole orientation in V1:
  - top-Y pole → ocean (canonical impassable water biome)
  - bottom-Y pole → burning lands (canonical impassable volcanic biome)
- Hard-band Y edges:
  - `ocean_band_mask = 1` on the top-Y belt of thickness
    `ocean_band_height_tiles`.
  - `burning_band_mask = 1` on the bottom-Y belt of thickness
    `burning_band_height_tiles`.
- These bands are **biome masks**, not terrain-id overrides. The
  terrain ids and walkability follow the biome resolver consuming the
  masks, so ADR-0002's "soft boundary" language stays semantically
  valid: the impassability is emergent from biome content, not a
  literal wall-of-rock hardcoded into the runtime.

### `WorldPrePass` Substrate

**Purpose.** Resolve all coarse global fields any downstream worldgen
layer needs, once per world load, in a single cache.

**Inputs.**

- `seed: int`
- `world_version: int` (must be `>= 9`; V1 bumps world version)
- `world_bounds: (width_tiles: int, height_tiles: int)`
- `settings_packed: PackedFloat32Array` — existing layout extended with
  foundation and band thickness settings (see `settings_packed` layout
  below)
- mountain field + mountain identity from `mountain_generation.md`
  (already canonical)

**Grid.**

- coarse cell size: `foundation_coarse_cell_size_tiles = 64`
- grid dimensions: `ceil(width / 64) × ceil(height / 64)`
- X wraps; Y does not
- for `4096 × 2048` world: `64 × 32 = 2048` nodes
- for `8192 × 4096` world: `128 × 64 = 8192` nodes

Changing the coarse cell size requires a `WORLD_VERSION` bump.

**Per-node fields (V1 frozen set).**

| Field | Derivation | Consumed by |
|---|---|---|
| `latitude_t` | `y_center / (height - 1)` | biome resolver (future), climate bands |
| `ocean_band_mask` | `1` if the node's Y center lies within `ocean_band_height_tiles` of the top-Y edge, else `0` | biome resolver (future), preview |
| `burning_band_mask` | `1` if the node's Y center lies within `burning_band_height_tiles` of the bottom-Y edge, else `0` | biome resolver (future), preview |
| `continent_mask` | deterministic low-frequency noise thresholded for land vs. open-water; masked off inside ocean / burning bands | biome resolver (future), preview, spawn resolver |
| `hydro_height` | `mountain_elevation_avg + world_slope_noise + low_freq_relief`, with Y gradient optionally biased by `foundation_slope_bias` toward one band to produce dominant drainage direction | river skeleton, preview, spawn resolver |
| `coarse_wall_density` | fraction of tiles in cell with `mountain_wall` | river skeleton, preview, spawn resolver |
| `coarse_foot_density` | fraction of tiles in cell with `mountain_foot` | river skeleton, biome resolver (future) |
| `coarse_valley_score` | `1 - coarse_wall_density - 0.5 × coarse_foot_density`, clamped to `[0, 1]` | river skeleton |
| `source_score` | deterministic biased noise gated by `hydro_height > headwater_threshold` | river skeleton |
| `biome_region_id` | deterministic low-frequency Voronoi tag stable across noise scale | biome resolver (future) |
| `downstream_index` | D8 downstream pick on `hydro_height` after priority-flood depression filling, with wrap-safe X | future river spec, dev/debug preview |
| `flow_accumulation` | normalised accumulated flow along the downstream graph | future river spec, dev/debug preview |
| `visible_trunk_mask` | routing-eligible land node with `flow_accumulation >= flow_visible_threshold(amount)` | future river spec, dev/debug preview |
| `strahler_order` | tree order along the visible trunk graph | future river spec |
| `is_terminal_lake_center` | basin-outlet flag where `flow_accumulation >= flow_sea_threshold` | future river spec, dev/debug preview |
| `terminal_lake_polygon` | deterministic lake polygon clamped to a max tile area, clipped at world Y bounds | future river spec, dev/debug preview |

Adding a field to this set requires a spec amendment and a
`WORLD_VERSION` review.

**Graph construction.** All river-skeleton fields are computed inside
the substrate natively:

1. For each node, compute the D8 downstream neighbour by minimum
   `hydro_height`, with deterministic tie-breaking by fixed neighbour
   order `(E, SE, S, SW, W, NW, N, NE)` after X-wrap canonicalisation.
2. Nodes with `coarse_wall_density > wall_block_threshold = 0.5` are
   non-routing: they do not emit downstream edges and upstream
   neighbours skip them (treated as having infinite `hydro_height` for
   the purpose of neighbour selection).
3. Apply **priority-flood depression filling** (Barnes et al. 2014) to
   detect closed basins, raise their `hydro_height` to the spill
   elevation of the basin outlet, and re-resolve downstream edges
   inside the filled basin. Deterministic and `O(N log N)`.
4. Cycle detection: after priority-flood no cycles should remain.
   Assert in debug builds. If a cycle is found, break at the edge with
   the highest canonical wrapped coordinate pair.
5. Topologically sort nodes by descending `hydro_height`; accumulate
   flow: `flow[node] = source_score[node] + Σ flow[upstream]`.
6. Normalise flow against theoretical maximum.
7. Mark a routing-eligible land node as visible trunk where
   `flow_accumulation >= flow_visible_threshold(amount)`. Ocean-band,
   burning-band, open-water, and blocked mountain-wall nodes remain
   non-visible even if upstream flow reaches them. Tag connected visible
   chains with Strahler order.
8. Any basin outlet with `flow > flow_sea_threshold` becomes a
   terminal-lake center; fit a deterministic polygon to the filled
   depression shape and clamp to a maximum tile area and world Y
   bounds.

Hydrology pattern references: GIS D8 + flow accumulation, priority-flood
depression filling, Strahler stream order. No hydraulic erosion, no
particle simulation, no WFC.

**Output.** One in-RAM `WorldPrePassSnapshot` keyed by
`(seed, world_version, world_bounds, settings_packed_hash)`. Replaced
on world load; not persisted.

**Budget.** Target `≤ 900 ms` on native for the largest V1 preset
(`8192 × 4096`, `8192` nodes). Measured by debug counter. Breaching the
budget is a blocker for the high-resolution foundation overview pass.

### Full-World Overview Preview

**Shape.** The substrate-grid debug source dimensions are
`ceil(width / 64) × ceil(height / 64)`. The player-facing UI may request
a native presentation image at `overview_pixels_per_cell = 4`, producing
an overview at roughly one pixel per `16 × 16` world tiles. This is a
native image pass over the already-built substrate, not chunk generation
and not a second world generator. The native overview pass re-samples
player-facing ocean/burning bands and continent mask at overview pixel
centres, directly samples the mountain field at
`pixel_sample_steps × pixel_sample_steps = 16` points within each overview
pixel's tile window for `wall_density` (bypassing `coarse_wall_density`
interpolation), and bilinearly interpolates `hydro_height` from the
built substrate.

**Pipeline.**

```
new-game panel → seed / size / foundation settings change
  → debounce
  → epoch bump
  → request WorldPrePass on worker
  → worker publishes native overview Image from WorldPrePassSnapshot
  → main thread uploads ImageTexture
  → ImageTexture.update()
  → overview view redraws
```

**Player-facing canonical palette (V1).** `WorldFoundationPalette` maps
only substrate channels whose meaning is already player-truthful in the
current build:

- `ocean_band_mask = 1` → deep blue (distinct from inland water)
- `burning_band_mask = 1` → dark red / ember
- `continent_mask = 0` inside habitable Y band → open water blue
- `continent_mask = 1` → neutral land tone shaded by `hydro_height`
  (darker low, lighter high, snow-white above snowline threshold)
- overview `wall_density` high → grey mountain overlay

No faux biome colours in V1. Biome overlays are added only after a
future biome spec defines canonical biomes. River and terminal-lake
skeleton fields stay in `WorldPrePass` for future river/biome work and
dev diagnostics, but the default player-facing overview must not render
them as blue rivers/lakes until a river rasterization spec makes those
features real terrain / overlay output.

**Debug palette variants.** Heatmap palettes for individual channels
(raw `hydro_height`, raw `flow_accumulation`, raw `coarse_wall_density`,
Strahler order colouring, visible river trunk candidates, terminal-lake
candidates, etc.) live in dev builds only and are addressable via
`layer_mask`.

**Rules.**

- The preview image **is** a snapshot read; there is no chunk batch, no
  `ChunkView`, no tile rasterization.
- The player-facing overview may draw presentation-only overlays on top
  of the snapshot: the resolved spawn marker, the current detail-preview
  `33 × 33` chunk window, and X-wrap edge hints. These overlays are UI
  reads of existing preview/spawn state and must not mutate substrate,
  chunks, save data, or world runtime state.
- The overview must never trigger gameplay world boot, never emit
  world-runtime lifecycle events, never write save files, never mutate
  `WorldDiffStore`.
- The existing progressive chunk preview from
  `WORLD_GENERATION_PREVIEW_ARCHITECTURE.md` stays. It now reads the
  substrate internally through `WorldCore` instead of re-deriving
  coarse fields per batch, but exposes the same chunk-by-chunk UX.
- Overview and detail previews may be shown together (overview as small
  world map, detail as zoomed spawn area).

### Relation to Existing Specs

| Spec | V1 change |
|---|---|
| `world_runtime.md` | No packet-shape change. Internal: `WorldCore.generate_chunk_packets_batch` reads the substrate cache on demand; cache miss triggers substrate solve inside the same world-load phase. Plus a targeted Spawn Contract amendment (below). |
| `world_grid_rebuild_foundation.md` | Unchanged; V1 stays at `32 px` / `32 × 32`. |
| `mountain_generation.md` | Unchanged ownership. V1 adds the `coarse_wall_density` / `coarse_foot_density` aggregation as a read of the mountain field, owned by the substrate. Mountain identity and excavation rules are untouched. |
| `WORLD_GENERATION_PREVIEW_ARCHITECTURE.md` | Stays valid for progressive detail preview. V1 adds the overview mode and documents that progressive-preview chunks also benefit from the shared substrate cache. |

No existing river spec is referenced; river rasterization is the
subject of a future spec written on top of V1.

### Spawn Contract Amendment

V1 lands a small amendment to `world_runtime.md`'s spawn section in
V1-R1A. The spawn resolver must reject any candidate spawn tile whose
coarse node satisfies any of:

- `ocean_band_mask = 1`
- `burning_band_mask = 1`
- `coarse_wall_density >= spawn_max_wall_density = 0.4`
- `visible_trunk_mask = 1` (do not spawn inside a river corridor)
- `is_terminal_lake_center = 1` or the tile lies inside a
  `terminal_lake_polygon`
- `continent_mask = 0` (do not spawn on open water)

It must prefer tiles inside `continent_mask = 1` with
`coarse_valley_score` above a documented threshold and `hydro_height`
within a mid-band range. Exact numeric thresholds live in the amendment
and are a V1-R1A deliverable.

### Biome Resolver Substrate Wiring

V1-R1D is spec-only. It documents the seam for a future biome spec; it
does not add ocean, burning, latitude-belt, continental, river, lake, or
mountain biome content in V1.

`BiomeResolver` remains data-driven: adding a biome must be adding or
overriding `BiomeData` resources and resolver thresholds, not editing
native generator branches for each biome. The resolver consumes:

- continuous world channels from the existing channel sampler
  (`height`, `temperature`, `moisture`, `ruggedness`,
  `flora_density`, `latitude`);
- causal / derived channels exposed through biome data ranges where
  already present (`drainage`, `slope`, `rain_shadow`,
  `continentalness`);
- bounded structure context returned by
  `WorldComputeContext.sample_structure_context(world_tile)`.

`WorldComputeContext.sample_structure_context(world_tile)` is the only
script-facing read seam for substrate-derived biome structure context.
Its contract for future biome work:

- input is one world tile coordinate on `z = 0`;
- X is canonicalised through finite cylindrical world bounds before
  sampling;
- Y is clamped / rejected according to finite world bounds and never
  wraps;
- it samples the already-built `WorldPrePass` cache at the corresponding
  coarse node, with no script-side re-derivation of substrate channels;
- it returns a small value object / dictionary owned by worldgen, not a
  mutable cache and not save data;
- it is valid only after the substrate exists on the boot/load or
  preview worker path; interactive gameplay code must not trigger a
  substrate build through this seam.

The minimum V1 substrate reads required by the future biome spec are:

| Biome need | Substrate read | Notes |
|---|---|---|
| hard top-Y band | `ocean_band_mask` | Forces future ocean biome eligibility. |
| hard bottom-Y band | `burning_band_mask` | Forces future burning biome eligibility. |
| land / open water split | `continent_mask` | Prevents ordinary land biomes from claiming open water. |
| latitude belt context | `latitude_t` | Used with existing `latitude` ranges; not environment runtime temperature. |
| broad elevation / drainage | `hydro_height` | Future mapping to `height` / `drainage` must be documented by the biome spec. |
| ridge / massif pressure | `coarse_wall_density` | Maps to structure `ridge_strength` for biome scoring. |
| foothill pressure | `coarse_foot_density` | Maps to structure `ridge_strength` / `slope` as defined by the biome spec. |
| valley / pass preference | `coarse_valley_score` | Future valley and pass biomes may use this as positive structure context. |
| broad region identity | `biome_region_id` | Stable coarse tag for future large biome regions; not a biome id by itself. |
| river corridor pressure | `visible_trunk_mask` and `flow_accumulation` | Maps to structure `river_strength`; it is not riverbed tile rasterization. |
| floodplain / terminal basin pressure | `is_terminal_lake_center` and `terminal_lake_polygons` | Maps to structure `floodplain_strength` / lake context; not water terrain by itself. |

For the current `BiomeData` shape, the R1D bridge names are:

| `BiomeData` / context key | Source direction |
|---|---|
| `latitude` | `latitude_t` converted to the existing resolver latitude domain. |
| `height` | existing channel height, optionally biased by `hydro_height` only after a future biome spec approves the mapping. |
| `drainage` | future derived channel from `hydro_height`, `flow_accumulation`, and local slope. |
| `continentalness` | future derived channel from `continent_mask` plus distance / coarse-region rules defined by the biome spec. |
| `ridge_strength` | `coarse_wall_density` with optional `coarse_foot_density` contribution. |
| `river_strength` | `visible_trunk_mask` plus `flow_accumulation`. |
| `floodplain_strength` | terminal-lake / basin context and future river-adjacent flatness rules. |

Explicit non-goals for V1-R1D:

- no new `BiomeData` exported fields;
- no new biome resources;
- no terrain id, walkability, atlas, or chunk packet field changes;
- no riverbed, lake, ocean, burning, or latitude-belt tile
  rasterization;
- no environment-runtime temperature, weather, wind, spore, snow, or
  season coupling;
- no save/load changes.

## Core Contract

### World Bounds

```
world_bounds = {
    width_tiles:  int,   // > 0, chunk-aligned, coarse-cell-aligned
    height_tiles: int,   // > 0, chunk-aligned, coarse-cell-aligned
}
```

Rules:

- `width_tiles % 32 == 0` and `height_tiles % 32 == 0` (alignment with
  the rebuild chunk contract).
- `width_tiles % foundation_coarse_cell_size_tiles == 0` and
  `height_tiles % foundation_coarse_cell_size_tiles == 0`
  (substrate grid alignment; avoid fractional coarse cells at the
  seam).
- `width_tiles >= 1024` and `height_tiles >= 512` (below this the
  overview degenerates to unusable sizes and the substrate loses
  statistical stability).
- `width_tiles <= 16384` and `height_tiles <= 8192` for V1 (caps set
  by the substrate budget plus per-chunk generation cost on
  the largest world).

### Presets (V1-R1)

| Preset | `width_tiles` | `height_tiles` | Coarse grid | Approx. pedestrian crossing time (X) |
|---|---:|---:|---:|---:|
| `small`  | 2048 | 1024 | 32 × 16  | ~5 min  |
| `medium` | 4096 | 2048 | 64 × 32 | ~11 min |
| `large`  | 8192 | 4096 | 128 × 64 | ~22 min |

The `custom` path is reserved for dev and headless validation; the UI
shipped in V1-R1 offers only the three presets.

### Hard-Band Y Edges

- `ocean_band_height_tiles` defaults to `max(64, height_tiles / 16)`.
- `burning_band_height_tiles` defaults to `max(64, height_tiles / 16)`.
- Bands are non-overlapping: ocean at top-Y side, burning at bottom-Y
  side (fixed in V1).
- Inside a band, the biome resolver must emit the band's canonical
  biome (ocean or burning) and the terrain is impassable by that
  biome's definition, not by an independent wall override.
- Moving Y-ward across the band edge must therefore feel like walking
  into an open sea or a volcanic waste, not like hitting an invisible
  barrier.

### `settings_packed` Layout Extension

| Index | Constant name | Meaning |
|---:|---|---|
| `0–8`  | mountain settings | Existing, unchanged. |
| `9`    | `SETTINGS_WORLD_WIDTH_TILES` | Copy of `world_bounds.width_tiles`. |
| `10`   | `SETTINGS_WORLD_HEIGHT_TILES` | Copy of `world_bounds.height_tiles`. |
| `11`   | `SETTINGS_OCEAN_BAND_TILES` | `ocean_band_height_tiles`. |
| `12`   | `SETTINGS_BURNING_BAND_TILES` | `burning_band_height_tiles`. |
| `13`   | `SETTINGS_POLE_ORIENTATION` | `0` = ocean top / burning bottom (V1 default and only shipped value); `1` = reversed (dev-only, not exposed in UI). |
| `14`   | `SETTINGS_FOUNDATION_SLOPE_BIAS` | `[-1.0, 1.0]` Y-biased drainage. `0.0` = unbiased; positive = drainage tends toward burning band; negative = toward ocean band. |
| `15`   | `SETTINGS_RIVER_AMOUNT` | Controls `flow_visible_threshold(amount)` for substrate visible-trunk extraction. `0.0` = no visible trunks. |

Active V1 native path requires at least `16` packed values. Missing
indices for `world_version >= 9` are invalid after load migration and
must fail loudly. Legacy-version worlds keep their older settings
layout unchanged.

## Runtime Architecture

### Native Boundary

The gameplay chunk-packet surface stays unchanged:

```text
WorldCore.generate_chunk_packets_batch(
    seed: int,
    coords: PackedVector2Array,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Array
```

V1-R1B also exposes the worker-only spawn-resolution surface:

```text
WorldCore.resolve_world_foundation_spawn_tile(
    seed: int,
    world_version: int,
    settings_packed: PackedFloat32Array
) -> Dictionary
```

Rules:

- First batch call after a world load triggers substrate compute if no
  valid snapshot matches `(seed, world_version, world_bounds,
  settings_packed_hash)`. Subsequent batches within the same world
  session are free reads.
- Spawn resolution uses the same substrate cache and returns the
  `WorldFoundationSpawnResult` dictionary documented in
  `packet_schemas.md`.
- Substrate compute runs on the same native worker path that owns
  chunk generation; the batch call does not return until its
  dependencies are in cache, but the whole call remains off the main
  thread.
- No per-tile native worldgen API is introduced for gameplay.

### Dev-Only Substrate API

Compiled only in dev builds and stripped in release by a compile flag:

```text
WorldCore.get_world_foundation_snapshot(
    layer_mask: int,
    downscale_factor: int
) -> Dictionary

WorldCore.get_world_foundation_overview(
    layer_mask: int,
    pixels_per_cell: int
) -> Image
```

`get_world_foundation_snapshot` returns raw channel arrays keyed by
layer name; `get_world_foundation_overview` returns a pre-coloured
overview image for the UI consumer. `downscale_factor` and
`pixels_per_cell` must be `>= 1`; `downscale_factor = 1` returns the
native substrate grid (one debug pixel per substrate node), and
`pixels_per_cell = 4` returns the default player-facing high-resolution
overview. The overview image is presentation output only: it may
re-sample current player-facing masks at higher pixel density, but it
must not become a gameplay data source.

Addressable layers:

- latitude / ocean / burning / continent / hydro-height / coarse-wall /
  coarse-foot / coarse-valley / source-score / biome-region
- downstream arrows / flow accumulation / visible trunks / Strahler /
  terminal-lake centres / terminal-lake polygons

Acceptance rejects any build where the overview preview is visible but
any of the substrate debug layers cannot be inspected on a dev build.

### Script Ownership

| Role | Owner | Responsibility |
|---|---|---|
| Substrate compute | `WorldCore` (native) | All substrate fields; wrap-safe X math; priority-flood; flow accumulation; trunk extraction; Strahler order; terminal-lake polygons. |
| Substrate cache | `WorldCore` (native, RAM) | One snapshot per world session, keyed by inputs. |
| Bounds + settings persistence | `SaveManager` + `world.json` writer | `worldgen_settings.world_bounds`, `worldgen_settings.foundation`. |
| Overview preview | `WorldPreviewController` + new overview canvas | Debounce, epoch, request native overview image, publish one `ImageTexture`, redraw canvas. |
| Overview palette | `WorldPrePass` native overview pass + `WorldFoundationPalette` constants | Pure function from snapshot to colour image. GDScript palette remains a fallback/helper and does not run the default whole-world colour loop. |
| Progressive detail preview | Existing `WorldPreviewController` path | Unchanged UX; reads substrate on the native side. |
| Spawn resolver | Existing spawn resolver owner in `world_runtime.md` | Reads substrate fields through `WorldCore` and applies the amended rejection / preference rules. |
| Mountain runtime | Existing `mountain_generation.md` code | Unchanged; contributes input to the substrate via the mountain field. |
| Environment runtime | ADR-0007-scoped systems | May read substrate (e.g., to seed climate variation) but must not mutate it. |

No new autoload is introduced.

## Persistence

### `world.json` Extension

```json
{
  "world_seed": 131071,
  "world_version": 9,
  "worldgen_settings": {
    "world_bounds": {
      "width_tiles": 4096,
      "height_tiles": 2048
    },
    "foundation": {
      "ocean_band_tiles": 128,
      "burning_band_tiles": 128,
      "pole_orientation": 0,
      "slope_bias": 0.0,
      "river_amount": 0.35
    },
    "mountains": { "...": "..." }
  }
}
```

Rules:

- Exact values copied once on new world creation. Repository defaults
  are never re-read for an existing world.
- Loading `world_version <= 8` preserves the pre-foundation output
  path:
  - legacy worlds are treated as unbounded-wrap (X wraps, Y
    unbounded);
  - legacy saves do not get synthetic bounds injected;
  - legacy worlds do not participate in the overview preview.
- Loading `world_version >= 9` without `worldgen_settings.world_bounds`
  is invalid and must fail loudly.
- Loading `world_version >= 9` without `worldgen_settings.foundation`
  falls back to hard-coded V1 defaults in the loader.
- The substrate snapshot is **never** written to disk.

### `WORLD_VERSION`

V1 originally bumped `WORLD_VERSION` to `9` because canonical terrain
output changed for the same `(seed, coord)` under the finite-bounded topology
and the shared substrate.

The current V1 baseline may advance beyond `9` when another canonical
worldgen owner changes output. Mountain Generation M6 advances new worlds to
`world_version = 10` so finite-cylinder mountain sampling uses the saved
`worldgen_settings.world_bounds.width_tiles` instead of the legacy
`65536`-tile sample width. `world_version == 9` remains a compatibility
boundary for existing finite-foundation saves.

The high-resolution foundation overview pass advances new worlds to
`world_version = 11` because `foundation_coarse_cell_size_tiles` changes
from `128` to `64`, changing substrate-derived spawn and future
worldgen reads for the same seed/settings.

## Performance Class

| Operation | Class | Dirty unit | Budget |
|---|---|---|---|
| Substrate compute | one-time native worker at world load | whole world, coarse `64` grid | target ≤ 900 ms on the largest V1 preset |
| Substrate cache read by chunk batch | native, non-blocking | (no dirty unit; immutable) | free |
| Overview preview render | native worker + main-thread publish | whole snapshot, one native image, default `4` pixels per substrate cell; direct mountain field wall resampling is roughly `16×` the substrate's mountain sampling work compared with substrate-only overview shading | no synchronous UI wait |
| Progressive detail preview | existing chunk-batch path | existing batch unit | unchanged |
| Chunk packet generation | existing native worker | chunk batch | unchanged |

**Forbidden:**

- Running `WorldPrePass` outside world load (exception: new-game
  preview debounce, which is functionally equivalent because no
  gameplay world is active).
- Running `WorldPrePass` on the main thread.
- Persisting the substrate to disk.
- Mutating substrate fields after compute.
- Adding a gameplay interactive path that reads the substrate
  synchronously through a GDScript loop; gameplay reads must go
  through existing `WorldComputeContext` seams and be bounded.
- Using the substrate to rewrite `terrain_ids` or `walkable_flags`
  from a non-worldgen system.

**Verification targets:**

- Overview preview renders within one animation frame after the worker
  publishes its snapshot.
- Chunk batch path shows no regression in median batch time after the
  substrate lands (substrate read is cache-cheap).
- Seed / size changes in the new-game panel trigger one substrate
  recompute and one overview republish, with no hidden gameplay scene
  boot.
- No new hitch class (>22 ms frame) appears during exploration
  attributable to substrate reads.

## Acceptance Criteria

### Topology

- [ ] ADR-0002 remains canonical; the hard-band Y edges are
      expressible purely through biome masks emitted by the substrate
      and do not require a literal wall-of-rock terrain override.
- [ ] Walking past `world_bounds.width_tiles` on X returns to tile `0`
      without visible seam.
- [ ] Walking Y-ward into either band reaches a band of
      impassable-biome terrain whose appearance matches the fixed V1
      pole orientation (ocean top, burning bottom).

### Substrate

- [ ] `WorldPrePass` produces identical output for identical
      `(seed, world_version, world_bounds, settings_packed)`, across
      independent runs and hosts.
- [ ] The D8 + priority-flood + flow accumulation pipeline produces a
      cycle-free downstream graph for every substrate snapshot
      (assert in debug builds).
- [ ] `visible_trunk_mask` agrees with
      `routing_eligible_land_node && flow_accumulation >=
      flow_visible_threshold(amount)`.
- [ ] Terminal-lake polygons are clipped at the Y world edges and
      never cross the wrap seam on X in a self-overlapping way.
- [ ] Substrate budget holds: `small ≤ 120 ms`, `medium ≤ 300 ms`,
      `large ≤ 900 ms` on the reference hardware.

### Save / Load

- [ ] New worlds write `worldgen_settings.world_bounds` and
      `worldgen_settings.foundation` with every preset.
- [ ] Loading `world_version <= 8` preserves legacy behaviour without
      injecting synthetic bounds.
- [ ] Loading `world_version >= 9` without required fields fails with
      a clear error.
- [ ] `world_version = 9` lands in the same task as V1-R1 code; later
      canonical-output owners may advance the current new-world version while
      preserving `9` as the finite-foundation compatibility boundary.

### Preview

- [ ] New-game overview shows finite world with visible wrap hint on
      X and visible bands on Y.
- [ ] Overview matches the current gameplay world at the level of
      continents, hard bands, and broad mountain / elevation context
      (shape-true). River skeleton candidates remain hidden from the
      default player overview until river rasterization exists.
- [ ] Overview shows individual mountain ridges narrower than `32` tiles
      when they exist at tile level, because `wall_density` is sampled
      at pixel resolution rather than interpolated from the `64`-tile
      coarse grid.
- [ ] Overview palette uses only canonical substrate channels in V1;
      no faux biome colours are rendered.
- [ ] Seed / size / foundation slider changes rebuild overview
      without freezing the menu.
- [ ] Overview writes nothing to save files before `Start`.
- [ ] Overview never boots a `WorldRuntimeV0` scene or equivalent
      gameplay world under the hood.

### Spawn

- [ ] Across a sample of seeds in each preset, the spawn resolver
      never emits a spawn tile inside an ocean or burning band, a
      large mountain massif, a visible river corridor, or a terminal
      lake.
- [ ] The spawn resolver prefers `continent_mask = 1` tiles with
      moderate `hydro_height` and high `coarse_valley_score`.

### Performance

- [ ] No mountain-generation work regresses relative to pre-V1
      baseline.
- [ ] Streaming chunk publish remains within its existing budget
      after substrate cache reads are added to native batch
      generation.
- [ ] Preview slider interaction never synchronously blocks UI
      frames.

### Debug

- [ ] Dev builds expose every substrate layer listed in the Dev-Only
      Substrate API.
- [ ] Debug API is stripped from release builds by the compile-time
      flag.

## Implementation Iterations

### V1-R1A — Bounds, settings, spawn contract amendment

Goal: land finite-cylinder topology and the spawn-safety amendment to
`world_runtime.md` without yet introducing the `WorldPrePass` class.

- Introduce `worldgen_settings.world_bounds` +
  `worldgen_settings.foundation`.
- Add size presets (small / medium / large) and the foundation
  controls (ocean / burning band thickness) to the new-game UI. Do not
  expose `pole_orientation` in the shipped UI.
- Extend `settings_packed` layout
  (`SETTINGS_WORLD_WIDTH_TILES`…`SETTINGS_RIVER_AMOUNT`).
- Teach `WorldCore` to canonicalise chunk coordinates against the new
  width and to clip Y at the bounds.
- Amend `world_runtime.md` spawn section with the rejection /
  preference rules from this spec's Spawn Contract Amendment.
- Bump `WORLD_VERSION` to `9`.
- Acceptance: topology acceptance + save / load acceptance + spawn
  acceptance (the latter can be partially manual until V1-R1B wires
  actual substrate reads into the resolver).

### V1-R1B — `WorldPrePass` native substrate

Goal: add the native `WorldPrePass` class, its cache, and the
river-skeleton fields.

- Implement substrate compute with the frozen V1 field set, including
  D8 + priority-flood + flow accumulation + visible-trunk extraction +
  Strahler order + terminal-lake polygons.
- Expose `get_world_foundation_snapshot` dev-only API.
- Extend `WorldCore` batch path to read the substrate cache.
- Wire spawn resolver to read substrate fields and apply the amended
  rules.
- Implementation note (2026-04-24): current R1B code resolves preview
  spawn through the worker-side `WorldCore` surface before progressive
  chunk staging. It does not ship the R1C overview canvas.
- Profiling gate: the substrate budget must hold on the `large` preset on
  reference hardware; missing the budget blocks closure and forces
  either coarse-cell rework or field-set reduction.
- Acceptance: determinism + substrate acceptance + spawn acceptance +
  debug API acceptance.

### V1-R1C — Full-world overview preview

Goal: ship the new overview preview in the new-game panel.

- Add `WorldFoundationPalette` (canonical channels only).
- Add overview canvas inside the new-game panel (alongside the
  existing progressive detail canvas).
- Hook debounce / epoch / publish pipeline through the existing
  `WorldPreviewController`.
- Acceptance: preview acceptance.

### V1-R1D — Biome resolver substrate wiring (spec-only in V1)

Goal: document how `BiomeResolver` and `WorldComputeContext` consume
substrate fields. Implementation of new biomes (ocean, burning, any
latitude-driven belt) is owned by a future biome spec and is **not**
landed inside V1.

- Amend `WorldComputeContext.sample_structure_context()` documentation
  where it already lives.
- List required substrate reads for the future biome spec.
- Implementation note (2026-04-25): R1D is documented in this spec's
  "Biome Resolver Substrate Wiring" section. It defines the future
  `sample_structure_context(world_tile)` contract, required substrate
  reads, bridge names for current `BiomeData` scoring fields, and
  explicit non-goals. It lands no code and no new biome content.

## Files That May Be Touched

### New

- `core/resources/world_bounds_settings.gd`
- `core/resources/foundation_gen_settings.gd`
- `data/balance/foundation_gen_settings.tres`
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `core/systems/world/world_foundation_palette.gd`
- `scenes/ui/world_overview_canvas.gd`

### Modified

- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/register_types.cpp`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_preview_controller.gd`
- spawn resolver source file named by `world_runtime.md` once the
  amendment lands
- save / load files that own `worldgen_settings`
- `scenes/ui/new_game_panel.gd`

## Files That Must Not Be Touched

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`, room / power
  topology.
- Combat, fauna, progression, inventory, crafting, lore, unrelated UI.
- `z != 0` subsurface runtime, underground fog, cave / cellar
  generation, connector systems.
- Environment runtime for weather, season, wind, temperature, spores,
  snow, ice, or dynamic water.
- Chunk diff file shape outside the existing tile override contract.
- Legacy world runtime files from the pre-rebuild stack.
- Mountain V1 internal mountain-field code (only aggregation reads
  are added on the substrate side).
- `docs/02_system_specs/meta/*` until code confirms final names /
  payloads.

## Required Canonical Doc Follow-Ups When Code Lands

- `meta/packet_schemas.md`: no new packet fields in V1; document only
  `worldgen_settings.world_bounds` + `worldgen_settings.foundation`
  subsections and the `settings_packed` index additions.
- `meta/save_and_persistence.md`: `worldgen_settings.world_bounds`,
  `worldgen_settings.foundation`, `world_version = 9` finite-foundation
  compatibility boundary, and any later current `WORLD_VERSION` bump that
  changes canonical output.
- `meta/system_api.md`: `WorldBoundsSettings` and
  `FoundationGenSettings` entrypoints; dev-only
  `get_world_foundation_snapshot` /
  `get_world_foundation_overview`.
- `world/world_runtime.md`: spawn contract amendment (rejection /
  preference rules landed in V1-R1A).
- `world/WORLD_GENERATION_PREVIEW_ARCHITECTURE.md`: add overview-mode
  section and note the substrate read path for progressive preview.
- `05_adrs/0002-wrap-world-is-cylindrical.md`: append a short
  "Consequences" clarification that Y hardness is realised through
  canonical impassable-biome bands derived from the latitude
  gradient, not through a literal wall terrain override. This is a
  clarification, not a reversal of ADR-0002.
- `00_governance/ENGINEERING_STANDARDS.md`: add a LAW 12 exception
  note for `WorldPrePass` (bounded, one-time at world load,
  off-main-thread, RAM-only, cached).
- `00_governance/PROJECT_GLOSSARY.md`: add `World bounds`,
  `WorldPrePass substrate`, `Hard-band Y edge`, `Ocean band`,
  `Burning band`, `Visible trunk`, `Terminal lake`; update existing
  `World channel` / `Large structure` entries to reference the
  substrate as their coarse source.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Finite bounds conflict with pre-V1 exploration expectations | Size presets make the minimum world larger than any single-session exploration range; wrap on X keeps east-bound movement seamless. |
| Substrate budget breach on `large` preset | Coarse cell size and field list are versioned constants; profile pass is a V1-R1B closure gate. Raising coarse cell to `256` halves node count at the cost of coarser river topology. |
| ADR-0002 interpretation drift between "soft Y" and "hard band" | Spec names the bands as biome masks, not terrain overrides; ADR-0002 addition is a Consequences clarification, not a reversal. |
| Preview overview drifts from gameplay world | Overview is a pure substrate read, not a parallel generator; any drift is a substrate bug and must be caught by the determinism acceptance. |
| Hard-coded legacy defaults pollute new worlds | Loader defaults apply **only** to `world_version >= 9` without the foundation section; new worlds always write explicit values. |
| `WorldPrePass` leaks into interactive path | Compile-time flag on the dev-only API + code review; ADR-0001 class contract; substrate cache is keyed and read-only after publish. |
| Multiplayer clients see divergent overview | Substrate is a pure function of replicated settings; all clients generate identical snapshots. |
| Spawn resolver rules too strict → no spawn found | Fallback rule: expand search radius deterministically; if still no candidate found, relax `coarse_valley_score` floor; final fallback raises a clear error that the seed is unspawnable on the chosen preset. |

## Deferred

- A future river spec consuming the V1 substrate to rasterize riverbed
  tiles, water overlays, curve quality contracts, islands, and splits.
- A future biome spec consuming the V1 substrate for ocean, burning,
  latitude-belt, and continental biomes.
- Subsurface / Z-level substrate extensions.
- Climate / seasonal modulation on top of `latitude_t`.
- Dynamic world events that need to re-evaluate substrate fields (must
  justify a separate ADR; V1 assumes substrate is immutable per
  session).
- Migration of `world_version <= 8` saves into the finite topology
  (treated as legacy; not forcibly upgraded).
- `custom` world bounds path in the user-facing UI (remains dev-only
  in V1-R1).
- User-facing `pole_orientation` toggle.
- Multiple concurrent worlds in one process sharing substrate caches.

## Open Questions

- Exact numeric thresholds in the spawn contract amendment
  (`spawn_max_wall_density`, minimum `coarse_valley_score`,
  `hydro_height` mid-band range). To be fixed in V1-R1A with a short
  debug-layer review and locked in the same task.
- Final `flow_visible_threshold(amount)` and `flow_sea_threshold`
  numeric mappings. To be tuned during V1-R1B debug-layer review.
- Whether `river_amount` lives under `worldgen_settings.foundation` as
  shown, or under a dedicated `worldgen_settings.rivers` section once
  the future river spec is drafted. V1 keeps it inside `foundation`
  to avoid an empty rivers section; the future river spec may move it
  with a migration note.

## Status Rationale

This spec was approved for staged implementation after the V1-R1A scope
was split from the later native substrate / overview work. The remaining
points below are iteration gates, not blockers for R1A:

- The finite-cylinder shape implies content and spawn-safety decisions
  that touch biome specs not yet written.
- World-size presets and band thicknesses are provisional numbers that
  must be validated by a debug-layer review on at least the `small`
  and `medium` presets before V1-R1B closure.
- The overview palette and debug-layer list are new surfaces that need
  a build-owner sign-off on the compile-time stripping strategy.
- The ADR-0002 Consequences clarification is a governance change that
  needs to land in the ADR-0002 document itself.

Changes to the rules above require a new version of this document
with `last_updated` bumped and a short amendment note in the task
closure report.
