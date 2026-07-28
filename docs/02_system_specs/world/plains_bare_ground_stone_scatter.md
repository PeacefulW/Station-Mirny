---
title: Plains Bare-Ground Stone Scatter - Procedural Rock Variations
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.2
last_updated: 2026-07-28
related_docs:
  - world_object_placement_v0.md
  - plains_ground_field_composition.md
  - plains_trees_presentation.md
  - ../../art/layered_asset_bake_contract.md
  - ../meta/packet_schemas.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Plains Bare-Ground Stone Scatter - Procedural Rock Variations

**The feature direction was approved on 2026-07-28 and all three implementation
iterations have landed. The later contour/readability and load-cost refinement
is a new candidate awaiting manual owner acceptance.**

## Purpose

Turn the grass↔bare-ground contour of the plains biome into a readable ecotone:
irregular tangent-aligned stone accumulations bridge the soft shader transition
without filling the open soil or drawing a uniform decorative outline.

Three existing systems already touch stone, and none of them delivers this:

1. **Shader scree** ([`ground_hybrid_material.gdshader`](../../../assets/shaders/ground_hybrid_material.gdshader))
   modulates ground colour with noise on the grass↔bare seam. It has no
   silhouette, so it reads as dirt grain, not as stones.
2. **Layered small rocks** (`object_kind == 7`) are real baked assets with
   separate shadow layers, but their placement set forbids bare ground and
   offers one calibre from ten source models.
3. **Terrain decals** (`_decal_layer` / `decal_instances`) are a removed
   generation. Only the orphaned smoke test
   [`terrain_decal_layer_smoke_test.gd`](../../../tools/terrain_decal_layer_smoke_test.gd)
   survives. This spec does **not** revive it.

The gap is therefore not "we need a decal system". The gap is variation and
placement inside the family that already works.

## Gameplay Goal

Grass does not dissolve straight into texture-only dirt. Broken groups of flat
slabs, gravel and occasional larger stones sit on the contour, leaving long
breathing gaps and denser authored-looking nodes. Open soil remains visually
quiet, while each clearing gets a distinct, readable boundary.

## Scope

- a procedural rock geometry generator in Blender, producing deterministic
  silhouette families (slab / boulder / shard) from seeded parameters, with no
  per-asset hand modelling and no new source GLB required;
- migration of the small-rock family onto bake profile revision `4` so its
  baked sun matches trees;
- a rock-family `0.30` ground-bounce multiplier so the shaded side keeps its
  own form while trees retain the full revision-4 bounce;
- a second contour placement set for the grass↔bare-ground ecotone, reusing
  `object_kind == 7`;
- calibre spread (larger flat slabs and finer gravel) via existing
  `visual_size_*` and new variation entries.

## Out of Scope

- reviving the removed terrain decal layer;
- a new `object_kind` family, packet field, or schema change;
- collision, harvesting, resource yield, or ore for stones;
- wind masks (rocks are static by contract);
- non-`plains` biomes;
- changes to the shader scree formula beyond a possible
  `scree_open_amount` retune to avoid double-littering;
- dynamic (torch/light) shadows for stones.

## Dependencies

- Bake contract and profile: [`layered_asset_bake_contract.md`](../../art/layered_asset_bake_contract.md),
  [`layered_asset_bake_profile.json`](../../../tools/tree_atlas/layered_asset_bake_profile.json).
- Existing rock bake: [`blender_layered_rock_asset_bake.py`](../../../tools/tree_atlas/blender_layered_rock_asset_bake.py),
  [`postprocess_layered_rock_asset.py`](../../../tools/tree_atlas/postprocess_layered_rock_asset.py).
- Variation precedent for trees: [`make_tree_variations.py`](../../../tools/tree_atlas/make_tree_variations.py),
  `tree_variation_profiles.json`.
- Placement owner: [`world_object_placement_v0.md`](world_object_placement_v0.md)
  (`object_kind == 7`), settings in
  [`plains_small_rocks.tres`](../../../data/world_objects/placement_groups/plains_small_rocks.tres).
- Ground field terms `M` / `P` shared with
  [`plains_ground_field_composition.md`](plains_ground_field_composition.md).

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual-only decor. Owns no terrain id, walkability, or save state. |
| Save/load required? | No. Placement is immutable generated output; assets are authored data. |
| Deterministic? | Yes. Placement from seed/chunk/version; geometry from seeded generator parameters. |
| Must it work on unloaded chunks? | Yes, placement derives from world position and existing fields. |
| C++ compute or main-thread apply? | Native `background` placement + worker buffer packing, bounded main-thread apply. Unchanged path. |
| Dirty unit | One chunk object placement packet. No new dirty unit. |
| Single owner | `world_object_placement_v0.md` stays the placement owner; the bake contract stays the asset owner. |
| 10x / 100x scale path | Instances go through the existing `MultiMeshInstance2D` batch. Cost scales with `max_per_chunk`, which is authored and capped. |
| Main-thread blocking risk | None new; assets are preloaded into channel atlases at boot. |
| Hidden fallback? | Forbidden. A missing variation directory or an atlas that was not rebuilt must fail loudly, not silently skip stones. |
| Whole-world prepass? | No. |

## Design Intent

### 1. Procedural geometry, not sourced models

The current ten rocks are one-to-one bakes of downloaded GLBs
(`meta.json.source_glb`), so variation is bounded by what was found. Replace the
source step with a seeded generator, keeping every downstream stage identical —
the same camera, sun, layer passes, and postprocess still come from the shared
bake contract.

Proposed generator: `tools/tree_atlas/make_rock_variations.py`, driven by
`tools/tree_atlas/rock_variation_profiles.json`
(`station_peaceful_rock_variation_v1`), alongside the tree equivalents.

Parameter direction (each entry is one deterministic `seed` plus):

| key | what it changes |
|---|---|
| `family` | `slab`, `boulder`, or `shard` — the silhouette class |
| `flatten` | vertical squash; a slab is a boulder with high flatten |
| `elongation`, `yaw_degrees` | plan-view proportions and which side faces camera |
| `facet_count`, `facet_sharpness` | planar cuts, giving angular vs rounded stone |
| `chip_count`, `chip_depth` | broken corners, so silhouettes are not convex blobs |
| `erosion_scale`, `erosion_strength` | surface noise displacement |
| `embed_fraction` | how deep the stone sits in the ground plane |

A slab is not a separate code path — it is a boulder with `flatten` high and
`embed_fraction` raised so it sits flush. That keeps one generator instead of
three.

**Alien, not Earth-quarry.** Stone colour and grain stay inside the biome's
established palette; this spec adds silhouette variety, not a new rock material
identity.

### 2. The sun migration is mandatory, not optional

**Resolved by Iteration 2 on 2026-07-28.** Recorded here because it constrains
anything that adds stones later.

When this spec was written the bake contract's migration table read:

| family | profile revision | baked shadow |
|---|---|---|
| layered trees | 4 | screen south-east |
| layered small rocks | 1 | screen **north-east** |

Rocks were one revision behind, pinned by a dedicated test. New stones baked on
the current profile would have cast south-east while the existing ten cast
north-east — two sun directions in one frame, which is a visible defect, not a
nuance.

The whole family therefore moved at once: ten re-bakes, both runtime
`SHADOW_*` framing copies flipped, migration row moved, pinning test replaced.
Both families now sit on revision `4`. Any future stone must be baked on the
current profile — never promoted beside assets from an older one.

### 3. The ecotone is a second placement set, not a loosened first one

[`plains_small_rocks.tres`](../../../data/world_objects/placement_groups/plains_small_rocks.tres)
owns the sparse anchor calibre; the second
`plains_bare_ground_stones.tres` profile owns the fine connective litter.
Both now use `placement_mask = grass_to_bare_transition`: anchor candidates
walk a sparse 4×4 grid, fine litter walks 6×6, and accepted centres from both
sets are projected just onto the bare side of the local grass-density
iso-contour. Their narrow cluster ellipses follow the contour tangent. This
produces readable broken lines rather than random interior litter or a regular
bead outline. Both sets emit `object_kind == 7`; the packet, runtime and batch
path are untouched.

`min_distance_px` must be enforced **across both sets**, or edge clusters and
bare-ground clusters will overlap where the two masks meet.

### 4. Relationship to shader scree

Shader scree already litters the seam and, at `scree_open_amount = 0.25`, faintly
litters open ground. Object stones now own the readable contour-scale accents;
scree stays the sub-object grain underneath. Retune `scree_open_amount` only if
the render probe shows mud. This is a visual tuning decision for the probe, not
a formula change — it touches no field math and needs no `WORLD_VERSION` bump
on its own.

## Data Model

New authored data only:

- `rock_variation_profiles.json` — generator entries (tool-side, not shipped);
- new asset directories `assets/sprites/decor/plains/layered_small_rocks/small_rock_NN`
  following the existing required-output list (`albedo`, `shadow`, `snow_mask`,
  `snow_overlay`, `height`, `normal`, `meta.json`, `preview_panel.png`);
- `plains_bare_ground_stones.tres` — a second `PlainsSmallRockPlacementSettings`.

Registration mirrors the tree rule: a new asset directory is invisible until the
channel atlases are rebuilt, and the directory list must stay in sync across
its registration points
([`build_layered_object_channel_atlases.gd`](../../../tools/build_layered_object_channel_atlases.gd),
the asset catalog, and `world_streamer.gd`).

## Runtime Architecture

No change. Placement is native `background`; presentation is the existing
layered-rock `MultiMeshInstance2D` batch with baked shadow stretch; assets are
boot-prepared into channel atlases.

The only runtime-facing edits are the second settings resource packed into
native settings indices, and the `SHADOW_*` framing constants flipped by the sun
migration.

## Performance Class

- Runtime class: `background` placement, bounded main-thread apply. No new
  `interactive` work.
- Cost scales with the two contour candidate grids plus total `max_per_chunk`
  across both sets. The anchor/fine grids are 4×4 and 6×6 respectively; their
  caps are `8` and `28`. Gradient projection runs only after the cheap
  candidate acceptance roll and reuses the centre field through two forward
  differences instead of four central-difference reads.
- Historical evidence for the rejected 16×16 random-scatter profile remains
  `40575 ms`; the earlier contour candidate recorded `22796 ms`, but those
  cross-session values are not treated as a strict A/B comparison. The
  session-local authoritative 121-chunk gate for this refinement measured
  `27079 ms` before and `23960 ms` after (`-3119 ms`, about `-11.5%`).
  Visual/windowed readiness remains a separate manual acceptance item.
- The four boot-preloaded rock atlas channels are now `480×480` (`96 px` per
  frame) rather than `960×960` (`192 px` per frame). Raw RGBA payload falls
  from about `14.1 MiB` to `3.5 MiB`; the checked-in PNG payload falls from
  `735190` to `269432` bytes.
- `WORLD_VERSION` MUST be bumped and the GDExtension DLL rebuilt: placement
  output changes deterministically.

## Save / Load Contract

No change. Stones are immutable generated output and are never persisted.

## Event and Command Contract Impact

None.

## Acceptance Criteria

Visual criteria are verified by render probe per the project's visual-proof rule
and are honest `manual human verification` items.

- [x] `make_rock_variations.py` produces N deterministic variants from seeds
      alone, with no source GLB required — **passed**: 12 variants, and a repeat
      run of `boulder_02` / `pebble_02` differs by 0 pixels on albedo, shadow,
      normal, height and snow overlay.
- [ ] A world-scale proof sheet shows a genuine spread of silhouettes — flat
      slabs, angular shards, rounded boulders — not near-copies
      (manual human verification — sheet rendered, awaiting the owner's read).
- [ ] Every new asset directory contains the full required-output set and a
      `meta.json` `bake_profile` block recording profile revision `4`
      (static: grep).
- [x] All rocks, old and new, cast shadows in the same screen direction as
      trees; the migration table row and the runtime `SHADOW_*` constants agree
      — **passed** (`test_runtime_shadow_stretch_matches_the_baked_sun` plus
      `test_small_rock_assets_record_the_shared_profile`; before/after sheet in
      `artifacts/small_rock_sun_migration/comparison_sun_migration.png`).
- [x] All 22 rocks record and use the `0.30` family bounce multiplier
      (`energy: 45`) — **passed**:
      `test_small_rock_assets_record_the_shared_profile` checks the full family
      and the promoted bakes measure an average lower-third luma change of
      `-41.9` against the previous full-bounce renders.
- [ ] The sun-opposite lower side reads as self-shadow rather than a second
      light (manual human verification — refreshed proof sheets and runtime
      captures await the owner's read).
- [x] `plains_bare_ground_stones.tres` exists, emits `object_kind == 7`, and
      creates no collision - **passed** (`small_rock_dev_scene_smoke_test`,
      `bare_ground_stone_placement_probe`).
- [x] `min_distance_px` is respected across both placement sets — no overlapping
      clusters at the mask boundary — **passed**: the native-packet probe checks
      every same-chunk stone pair after q4 packing and reports a minimum
      distance of `8.0 px`, the quantized form of the authored `10 px` floor.
- [ ] Render probe shows bare ground with varied stone litter and no visible
      chunk-boundary seam in stone density (manual human verification -
      `artifacts/bare_ground_stones/` rendered, awaiting the owner's read).
- [x] Initial chunk-readiness and instance-count comparison before/after —
      **passed**: session-local authoritative 121-chunk gate
      `27079 ms -> 23960 ms`; placement probe `759` stones / 36 chunks
      (`21.1` mean, `0/23/36` min/median/max; zero means no contour crossed that
      sampled chunk).
- [x] `WORLD_VERSION` bumped to 64, DLL rebuilt, channel atlases rebuilt -
      **passed**.
- [x] Every stone variant is reachable - **passed**: across 36 chunks the
      probe counts 759 stones (mean 21.1/chunk, min/median/max 0/23/36) using
      all 22 variants, sized 7-26 px before byte histogram bucketing.

## Risks

- **Mixed sun directions** if the migration is done partially. Mitigation: the
  contract's own rule — migrate the whole family in one change.
- **Instance-count inflation** along long contours. Mitigation: authored
  per-set caps `8 + 28`, sparse 4×4 / 6×6 candidates, and measured
  placement/readiness probes before acceptance.
- **Double-litter with shader scree** producing mud. Mitigation: probe first,
  retune `scree_open_amount` second.
- **Near-copy variations** — the failure mode already documented for trees
  ("keep a spread of characters rather than six near-copies"). Mitigation: the
  proof sheet is the gate, not the parameter table.
- **Registration drift** — a new asset directory registered in two of three
  places renders nothing. Mitigation: the sync list above, checked by test.

## Implementation Iterations

### Iteration 1 — Procedural generator + proof sheet (tools only)

Build `make_rock_variations.py` + `rock_variation_profiles.json`, bake a
candidate set into `artifacts/`, and produce a world-scale comparison sheet.

Touches `tools/` and `artifacts/` only. **Zero game changes**, so the silhouette
spread can be approved before anything reaches the world.

**Status: landed 2026-07-28.** Twelve variants across four families (slab,
boulder, shard, pebble) in `artifacts/layered_rock_v1_variations/`.

Three findings from the run, recorded because they change later iterations:

- `blender_layered_rock_asset_bake.py` could not run against the current profile
  at all: it read `lighting.fill_energy`, removed in revision 4. The rig is now
  migrated (ground bounce, bounce excluded from the shadow pass), which means
  **the bake script is on revision 4 while the ten shipped assets are still
  revision 1** — see the bake contract's migration note.
- Surface tone had been hidden by a bug: the crack ramp ran backwards and
  multiplied the entire surface down, so the authored base colour was never the
  surface colour. With the ramp corrected, `base_color_srgb` was re-measured
  against the shipped rocks (`boulder_02` mean RGB `123/93/69` vs `small_rock_03`
  `126/96/69`).
- The bake is bit-for-bit reproducible from seeds across runs, including the
  Cycles shadow pass — verified by re-running two variants and differencing every
  layer.

### Iteration 2 — Sun migration of the small-rock family

Re-bake the existing ten rocks on profile revision `4`, flip runtime `SHADOW_*`
framing, update the migration table, replace
`test_small_rock_assets_still_await_the_current_sun`, rebuild atlases. Visual
result: existing rocks change shadow direction to match trees. No placement
change, no `WORLD_VERSION` bump.

**Status: landed 2026-07-28.** All ten rocks re-baked from their source GLBs via
the new `rebake_small_rock_assets.py` + `small_rock_source_manifest.json`, then
promoted; channel atlases rebuilt.

Two details worth carrying forward:

- The stretch direction lives in **two** places, not one: `SHADOW_DIRECTION` in
  `world_layered_object_asset_catalog.gd` *and* a second copy in
  `layered_rock_object_layer.gd`. Flipping only the catalog would leave the
  runtime stretching a shadow away from where it was rasterised. Both are now
  pinned by `test_runtime_shadow_stretch_matches_the_baked_sun`.
- Tone survived the rig change: per-asset mean luma moved between `-2` and `+12`
  against the revision 1 bakes, with essentially no pixels above 200.

### Iteration 3 — Bare-ground placement set

Promote approved variations into `assets/`, register them, add
`plains_bare_ground_stones.tres`, wire its native settings indices, bump
`WORLD_VERSION`, rebuild the DLL, probe, tune density and the scree relationship.

**Status: landed 2026-07-28** at `WORLD_VERSION == 64`.

What the implementation had to resolve beyond the plan:

- **The atlas, not the instance count, was the real asset-side cost.** Rock
  atlas frames are boot-preloaded RGBA channels, so 22 assets at the baked
  `768 px` frame would have taken about `236 MiB`. The first candidate packed
  them at `192 px` (`14.1 MiB` across four channels), but close gameplay still
  showed unnecessary surface chatter. The accepted atlas packs at `96 px`
  (`3.5 MiB`), while stones draw at `7..26 px`. Runtime needed no change:
  instance scale comes from `meta.json` and `frame_texel_size` derives from the
  actual atlas size.
- **Spacing had to be shared, the cap had not.** Both sets write into one
  per-chunk position/cluster state so `min_distance_px` holds across sets,
  while `max_per_chunk` counts per set. Each set also carries a distinct hash
  salt; without it both would drop cluster centres on identical cells.
- **`resize()` truncates.** The settings writer sized the packed array to the
  first block's field count, which would have dropped the second block. It now
  only grows.
- **Dense random scatter was both ugly and slow.** The first rejected profile
  walked 16×16 candidate centres, repeatedly sampling the expensive ground
  fields, yet read as isolated pale beads inside dirt. A later candidate
  projected only the fine set and still left the visible anchor rocks random.
  The accepted profile projects both 4×4/6×6 sets, moves their target to the
  visible transition midpoint, uses two forward gradient reads, and narrows
  their tangent ellipses. The same-session authoritative gate improved by
  `11.5%` while the contour became more explicit.

### Post-landing lighting refinement — 30% rock bounce

The revision-4 ground bounce was authored for trees. Applying its full
`energy: 150` to compact rocks lit the sun-opposite lower face strongly enough
to erase self-shadowing and read as a second lamp under the stone. The rock
bake now applies a family multiplier of `0.30` (`energy: 45`) while trees remain
unchanged at `150`.

All ten source-GLB rocks and all twelve procedural rocks were re-baked and
promoted together. Their `meta.json` records
`rock_bounce_energy_scale: 0.3` and `rock_bounce_energy: 45.0`; the 96 px
channel atlases were rebuilt afterwards. Against the previous full-bounce
bakes, masked mean albedo luma changed by `-21.3` on average and lower-third
luma by `-41.9`, which is the intended restoration of the shaded face rather
than a recolour or exposure adjustment.

## Open Questions

- The fine contour set is capped at 28 local instances per chunk; the anchor
  set is capped at 8. The combined placement probe currently averages 21.1
  small rocks per chunk across both sets.
- Whether the largest slabs deserve their own calibre band with a lower cap, or
  fall out of the existing `visual_size_*` range.
- Whether the generator lives in `tools/tree_atlas/` beside the existing rock
  scripts (proposed, minimal surprise) or moves to `tools/rock_atlas/`.

## Required Updates

When this spec is implemented:

- [`world_object_placement_v0.md`](world_object_placement_v0.md) — record the
  second `object_kind == 7` placement set and the new `world_version`.
- [`layered_asset_bake_contract.md`](../../art/layered_asset_bake_contract.md) —
  move the small-rock migration row to revision `4`; document the rock variation
  generator in a section parallel to "Silhouette Variations From One Source GLB".
- [`packet_schemas.md`](../meta/packet_schemas.md) — no shape change expected;
  confirm with grep and record the result.
- `docs/02_system_specs/README.md` — index entry.
