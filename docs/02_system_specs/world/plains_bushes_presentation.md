---
title: Plains Alien Bushes Presentation V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.3
last_updated: 2026-08-17
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
  - ../../art/layered_asset_bake_contract.md
  - world_object_placement_v0.md
  - plains_trees_presentation.md
  - plains_bare_ground_stone_scatter.md
  - wind_and_grass_scatter_presentation.md
  - ../meta/packet_schemas.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Plains Alien Bushes Presentation V0

## Purpose

Ship the procedural alien bush (`tools/bush_atlas`, asset `alien_bush_01`) into
the `plains` surface as a **new layered world-object family**, placed only where
grass grows, at roughly half the size shown in the authoring proof sheet.

The bush is a **visual-only decor family**. It owns no terrain id, no
walkability, no save state, and no harvest contract in V0.

## Gameplay Goal

The plains floor gains a second scale of life between grass tufts and trees: a
low, dark, wine-purple plant with amber blade tips and turquoise capsules that

- appears **only in grass**, never on bare ground, paths, stone litter, lake or
  mountain tiles;
- reads at gameplay zoom as a compact silhouette with its own sun shadow;
- sways on the **same wind** as grass and trees;
- sorts on the **shared depth ladder** like every other mid-layer object.

## Scope (V0)

- `plains` biome, surface layer.
- New native object family value `object_kind == 8` (`OBJECT_KIND_BUSH`), placed
  deterministically in `WorldCore` from seed / version / chunk / settings.
- Placement gate is the **canonical grass field**, the same
  `grass_scatter::sample_grass_density × sample_path` product the tree family
  uses — one source of truth, no second grass model.
- One authored asset directory `assets/sprites/flora/layered_bushes/alien_bush_01`
  baked on `station_peaceful_layered_asset_bake_v1` rev. 4 (the tree contract),
  packed into a per-family channel atlas by
  `tools/build_layered_object_channel_atlases.gd`.
- Presentation rides the existing layered-object batch path: per-stripe
  `MultiMeshInstance2D` batches, z owned by `WorldStreamer`, sun shadow split
  into pinned root side and stretched far side.
- `WorldRuntimeConstants.WORLD_VERSION` advances (canonical placement output
  changes — LAW 4).

## Out of Scope (V0)

- Harvest / yield / runtime diff (separate contract, later iteration).
- Collision: the bush is **walk-through** decor; no collider is created.
- A second bush species, seasonal species swap, or biome beyond `plains`.
- Runtime atlas painting, per-object `z_index`, node-per-object presentation,
  baked grass fringe in the asset — all forbidden, as in
  `plains_trees_presentation.md`.
- GDScript placement fallback when native placement is unavailable (LAW 9).

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual-only decor; placement is immutable base output. |
| Save/load required? | No. Placement derives from seed + `world_version` + frozen settings. |
| Deterministic? | Yes — pure function of seed, version, chunk, settings. |
| Must it work on unloaded chunks? | Placement derivable on demand; no whole-world state. |
| C++ compute or main-thread apply? | Native placement and buffer packing; bounded main-thread apply on the existing visual upload path. |
| Dirty unit | One chunk's object presentation buffer. No new dirty unit. |
| Single owner | Placement: `WorldCore`. GPU buffers/lifecycle: `WorldRenderWorld` (sole GPU owner). Collision: `WorldObjectCollisionOwner`. Painter order: native `(feet_y, semantic_layer, stable_id)`. Wind: `WindRuntime`. Fixed sun azimuth: `WorldVisualLightingProfile`; time-varying shadow length: `TimeManager` progress. |
| 10x / 100x scale path | More bushes stay inside per-stripe batch buffers; cost is bounded by the authored per-chunk cap. |
| Main-thread blocking risk | None new; one more family in the existing bounded apply. |
| Hidden fallback? | Forbidden. A missing asset directory or an atlas that was not rebuilt fails loudly. |
| Whole-world prepass? | No. Local per-chunk compute only. |

## Design Intent

### 1. A family of its own, not a seventh tree and not a stone

The bush could be smuggled in as another tree atlas column or another small-rock
variant. Both are rejected:

- a tree carries trunk collision derived from `object_kind == 4`, so a bush
  entering that family would silently become a wall;
- a small rock is placed by the bare-ground / ecotone field, which is the exact
  opposite of "only where grass grows".

A separate `object_kind` keeps placement rules, size tiers, collision policy and
atlas layout readable per family, which is the stated scalability goal of
`world_object_placement_v0.md`.

### 2. Grass is the gate, and it is the same grass the trees read

The placement test is the product of the canonical grass density field and the
path field, exactly as `append_native_tree_placements` computes it. The bush
uses a **higher** minimum than trees: a tree may stand at the edge of a grass
mass, while a bush should sit inside it. No second noise model, no separate
"bush mask" field.

### 3. The bush is layered, so it keeps its baked shadow and gains wind

The asset is baked on the tree contract and therefore ships `trunk`, `foliage`,
`shadow`, `wind_mask`, `snow_mask`, `snow_overlay`, `season_mask`. Presentation
reuses the layered tree channel set so the bush gets:

- a fixed-azimuth shadow that stretches screen south-east away from a pinned
  root; dawn/dusk change length, never the shared `SHADOW_DIRECTION`;
- canopy wind from the shared wind globals, damped relative to trees;
- snow accumulation for free when the season system drives it.

### 4. Half the proof-sheet size

`object_size_px` is the **visible width** of the sprite, and a tree does not use
it at all: the tree family draws at a fixed frame scale of `0.64`, which puts a
shipped tree at `83 x 305 px` on screen. The proof sheet renders the bush at
`0.35` world units against `tree_01` at `1.07`, i.e. a third of the tree height
(~`99 px`), which is `128 px` of visible width at the bush aspect (`454x351`).
V0 authors **half that height** (~`50 px`), which is `55..76 px` of width.

Measured consequence, recorded here because it is a design cost and not a bug:
at that size a bush sits below the grass canopy and is largely occluded by the
grass tufts on its own and nearer stripes. Reading it in dense grass needs
either a larger authored size or shorter grass; the proof sheet
`artifacts/plains_bush_runtime/bush_size_compare.png` shows both.

## Data Model

- **Iteration 1 keeps bush tuning as native constants** (`BUSH_*` in
  `world_core.cpp`): scatter grid `8`, density `0.50`, per-chunk cap `10`,
  spacing `46 px`, edge padding `20 px`, size `55..76 px`, grass threshold
  `0.55`. No packed settings block and no save-shape change, so this iteration
  cannot regress `worldgen_settings` loading.
- The **grass field parameters** are read from the frozen
  `worldgen_settings.plains_trees` block: the field that decides where grass
  grows has one owner, and the bush family only supplies its own threshold.
- A `PlainsBushPlacementSettings` resource is deferred to Iteration 2, when
  tuning actually needs to be authored per world rather than per build.
- Asset directory contract: the twelve layered files plus `meta.json`, as in
  `docs/art/layered_asset_bake_contract.md`.

## Runtime Architecture

| Concern | Owner |
|---|---|
| Bush placement compute | `WorldCore` (`append_native_bush_placements`) |
| Object packet record (`object_kind == 8`) | `WorldCore` |
| Channel atlas | `tools/build_layered_object_channel_atlases.gd` (build step) |
| Global snapshot apply + GPU lifecycle | `WorldRenderWorld` (fixed passes; no per-family `MultiMesh`) |
| Tree/bush collision rectangles | `WorldObjectCollisionOwner` |
| Painter order | native `(feet_y, semantic_layer, stable_id)`; no per-family z |
| Wind | `WindRuntime` (read-only consumer) |
| Fixed sun azimuth | `WorldVisualLightingProfile` + layered bake contract |
| Time-varying shadow length | `TimeManager` progress read through `WorldVisualLightingProfile` |

Placement mirrors the tree scatter: grid cells with hashed jitter, plain-tile and
mountain-clearance tests, the grass gate, a minimum spacing pass, then a hashed
variant / size / tint / wind phase. No `randf`, no per-object boundary calls.

### Failure policy (LAW 9)

If the bush asset directory, its `meta.json`, or the channel atlas is missing or
malformed, the layer errors and draws nothing. No silent skip, no substitute
asset, no GDScript scatter fallback.

## Performance Class

- Placement: native `background` packet generation, bounded by the authored
  per-chunk cap.
- Apply: bounded main-thread publish of per-stripe buffers on the existing
  visual upload path; the bush family joins the same coherent chunk reveal.
- Depth rebase: shares the existing band roots; no new z walk.
- Wind: shader-side, no per-frame CPU work.

## Save / Persistence Contracts

Placement is immutable base output (LAW 5): recreated from seed +
`world_version` + `worldgen_settings.plains_bushes`. No diff entries in V0.
`WORLD_VERSION` advances because existing saves must not silently gain bushes
inside a version whose canonical output did not contain them.

## Acceptance Criteria

V0 is acceptable when:

- bushes appear **only** on grass: a render probe shows none on bare ground,
  paths, stone litter, lake or mountain tiles;
- placement is identical across two runs at the same seed / version / settings;
- bushes are emitted from the **native packet** (`object_kind == 8`) and drawn as
  per-stripe batches — no node-per-object, no per-object `z_index` (static check);
- the player walks **through** a bush (no collider) and sorts in front of / behind
  it by feet stripe;
- the bush shadow always runs screen south-east like trees and rocks; dawn/dusk
  lengthen only its far side while the root stays pinned;
- rendered size lands in the authored `26..42 px` range at default zoom;
- the bake contract test still passes and the new asset records the shared
  `bake_profile` block;
- `WORLD_VERSION` bumped and `packet_schemas.md` updated in the same change.

## Failure Cases / Risks

The design is wrong if: a bush appears off-grass; the family needs its own depth
code; placement lands in GDScript; the shadow direction disagrees with the bake;
the family ships without the channel atlas rebuild (invisible asset); or the
per-chunk cap is unbounded.

## Implementation Iterations

### Iteration 1 — Family in the world (delivered)

Native `object_kind == 8` + grass-gated placement (native constants), channel
atlas `assets/sprites/flora/atlases/layered_bushes`, `LayeredBushBatchLayer`,
the bush family in the then-current `WorldObjectPacketLayer`, streamer metric plumbing,
`WORLD_VERSION` 64 -> 65, contract-test extension, placement and render probes.

### Iteration 2 — Tuning and variety

Density / size / palette tuning from probes; additional bush variants baked from
the same generator (`alien_bush_02..0N`) as extra atlas columns.

### Iteration 3 — Harvest (separate contract)

Command-backed gathering, runtime diff, save/load, domain event; requires
`commands.md`, `event_contracts.md`, `save_and_persistence.md` updates.

## Required Updates

- `docs/README.md`, `docs/02_system_specs/README.md`: link this spec.
- `packet_schemas.md`: `object_kind == 8` and `worldgen_settings.plains_bushes`.
- `world_object_placement_v0.md`: cross-reference the bush family.
- `docs/art/layered_asset_bake_contract.md`: add the bush family row to the sun
  migration table once the asset ships in `assets/`.
- `WorldRuntimeConstants.WORLD_VERSION`: bumped with this iteration.
