---
title: River Generation R1B-Fix - Acceptance Correction
doc_type: system_spec_amendment
status: approved
owner: engineering+design
source_of_truth: false
amends: river_generation.md V1.0
target_world_version: 15
last_updated: 2026-04-25
related_docs:
  - river_generation.md
  - world_foundation_v1.md
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - terrain_hybrid_presentation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../meta/system_api.md
---

# River Generation R1B-Fix - Acceptance Correction

## Status

Draft amendment to `river_generation.md` V1.0. Resolves R1B acceptance gaps
identified during the 2026-04-25 dry-preview tuning review. On approval, this
amendment becomes part of `river_generation.md`, bumps `WORLD_VERSION` from
`14` to `15`, and bumps `RIVER_GENERATION_VERSION` from `14` to `15`.

This amendment is binding for the implementer. Anything in this document that
contradicts the original spec wins for `world_version >= 15`. Anything not
covered here remains governed by the original `river_generation.md` V1.0.

This amendment is **not** R1D (split/rejoin). Side-channel islands stay out of
scope. This amendment is **not** R2 (water overlay). Beds remain dry.

## Why this exists

R1B at `world_version 14` satisfies the **architectural** acceptance of
`river_generation.md` (native rasterization, dry-first, immutable base,
deterministic, single packet boundary). It does **not** satisfy the **shape
acceptance** of the same spec, and it diverges from canonical contract in
several places:

1. `terminal_lake_polygon` is generated as a placeholder 3x3 coarse-cell square
   and is never read by the river rasterizer (rasterizer renders a circle of
   `5.5..14` tile radius around `is_terminal_lake_center`). The spec requires
   the rasterizer to use the polygon footprint.
2. The world-overview overlay renders lakes as a `0.42` coarse-cell circle
   (~27 tiles radius), the region/in-game rasterizer renders the same lake as
   a different `5.5..14` tile circle. Two visual sources of truth for one lake
   identity. Violates LAW 8 (one owner, one truth).
3. `target_lake_count` is hard-capped at `8` lakes for the entire world. For a
   typical mid-cylinder grid this gives 1..4 lakes. The reference target
   silhouette has tens of lakes per world.
4. Ocean band has no terrain content. Chunks inside `ocean_band_tiles` get
   `TERRAIN_PLAINS_GROUND`. The world-map overview shows ocean as blue, the
   region preview and the in-game world show grass. Player cannot read a
   coast.
5. River mouth widening near the ocean is `+0.75` tile shallow radius. The
   spec wording "wider channels and possible delta/braid widening" is not
   visibly satisfied.
6. River bed width curve clamps shallow radius at `3.75` tiles, deep at
   `~1.05` tiles. River trunks read as 2..7 tile cracks even at the ocean
   mouth. Reference target wants visible 10..20 tile mouths.
7. `NODE_SEARCH_HALO_TILES = COARSE * 2 = 128`. This halo is smaller than the
   target lake polygon radius required by this amendment. Out-of-region lakes
   that should reach into the previewed chunk get clipped.

## Identified contract gaps (R1B at V14) - reference index

| ID | Gap | Source |
|---|---|---|
| G1 | Lake rendered as circle, polygon ignored | `gdextension/src/river_rasterizer.cpp:260-284` |
| G2 | Lake polygon is a placeholder square | `gdextension/src/world_prepass.cpp:365-374` |
| G3 | Two lake size sources (overview vs rasterizer) | `gdextension/src/world_prepass.cpp:571-581` vs `gdextension/src/river_rasterizer.cpp:275-281` |
| G4 | Lake count capped at 8 | `gdextension/src/world_prepass.cpp:377-379` |
| G5 | Ocean band has no terrain content | `gdextension/src/world_core.cpp:564-590` |
| G6 | Mouth widening `+0.75` tile, invisible | `gdextension/src/river_rasterizer.cpp:218` |
| G7 | River shallow radius capped at `3.75`, deep at `~1.26` | `gdextension/src/river_rasterizer.cpp:188` |
| G8 | Halo too small for lake footprint | `gdextension/src/river_rasterizer.cpp:19` |

All eight gaps must be closed for R1B-Fix acceptance.

---

## Canonical Contract Updates

### C1. Lake footprint is a polygon, single source of truth

**Rule**: lake footprint is defined by a deterministic polygon stored on the
`WorldPrePass` snapshot. Both the world-overview image and the region
rasterizer read the same polygon and compute the same depth classification
from the same radial test. There is exactly one function that produces the
lake shape contract.

**Required**:
- A single native helper, namespaced under `lake_footprint`, with the
  following surface (final symbol naming is implementer's choice as long as
  both call sites use it):
  ```cpp
  namespace lake_footprint {
      struct LakeShape {
          double center_x_tiles;     // wrapped X already resolved against reference
          double center_y_tiles;
          float  shallow_radius_tiles; // base radius before vertex modulation
          float  deep_radius_tiles;    // base radius before vertex modulation
          uint64_t shape_signature;    // for vertex modulation noise
      };

      // Returns DEEP, SHALLOW, or NONE for one tile sample.
      uint8_t classify_tile(const LakeShape &shape, double world_x, double world_y, int64_t width_tiles);

      // Generates the polygon stored on the snapshot. Same vertex count and
      // same modulation rules as classify_tile so polygon and depth match.
      godot::PackedVector2Array build_polygon(const LakeShape &shape, int64_t width_tiles);
  }
  ```
- `world_prepass.cpp::mark_lake` calls `lake_footprint::build_polygon` and
  stores the resulting polygon in `terminal_lake_polygons`. The placeholder
  square is removed.
- `world_prepass.cpp::resolve_dry_overview_overlay` (the overview overlay
  loop) calls `lake_footprint::classify_tile` to decide shallow/deep for each
  overview pixel that touches a lake center node. The hard-coded `0.42` cell
  distance check is removed.
- `river_rasterizer.cpp::build_lake_candidates` returns `LakeShape` records.
  `rasterize_region` calls `lake_footprint::classify_tile` per tile sample.
  The hard-coded `apply_candidate_to_cell` circle path for lakes is removed.

**Determinism**: shape is a pure function of
`(seed, world_version, snapshot.signature, node_index, settings)`.

**Why**: closes G1, G2, G3.

### C2. Lake footprint geometry

**Rule**: lake shape is a deterministic deformed polygon, not a circle, not a
square.

**Required**:
- Vertex count: `16` (fixed for V15).
- Base shallow radius: `lake_footprint::shallow_radius_tiles`, computed as:
  ```
  base_radius = clamp(48.0 + flow_accumulation * 56.0 + valley * 24.0, 48.0, 144.0)
  shallow_radius_tiles = base_radius * worldgen_settings.rivers.lake_radius_scale
  ```
- Base deep radius:
  ```
  deep_radius_tiles = shallow_radius_tiles * (0.45 + valley * 0.20)
  ```
  Clamped to `[max(8.0, shallow * 0.20), shallow * 0.85]`.
- Per-vertex radial modulation:
  ```
  vertex_angle_i = (2 * pi * i) / 16
  vertex_noise_i = splitmix64(shape_signature ^ (i * 0x9e3779b185ebca87ULL))
  vertex_scale_i = 0.72 + (vertex_noise_i_low_16_bits / 65535.0) * 0.56     // [0.72, 1.28]
  vertex_radius_i = base_radius * vertex_scale_i
  ```
- `classify_tile` performs:
  ```
  for the two adjacent vertices i, i+1 enclosing the tile bearing:
      interpolated_radius = lerp(vertex_radius_i, vertex_radius_(i+1), t)
      if tile_distance > interpolated_radius * shallow_factor: NONE
      elif tile_distance > interpolated_radius * deep_factor: SHALLOW
      else: DEEP
  ```
  where `shallow_factor = 1.0`, `deep_factor = (deep_radius / shallow_radius)`.
- `build_polygon` emits the 16 vertices in tile-space, X-wrap-safe, in CCW
  order.

**Why**: closes G1 fully (real shape, not square or circle), gives the
"interesting form" the world map suggests, ensures overview and rasterizer
share the same geometry.

### C3. Lake-river connection

**Rule**: a primary river trunk that ends at a lake-center node must
visibly enter the lake polygon. No extra connection logic is required if the
lake polygon is large enough that the river endpoint sample lies inside the
shallow rim. Verify in acceptance.

**Required**:
- `river_rasterizer.cpp` river-segment endpoints already terminate at lake
  centers when `downstream_index` points at a lake center.
- After C2 with `shallow_radius_tiles >= 48`, the river endpoint at the lake
  center is always inside the deep zone. This is sufficient.
- Acceptance test must verify that for at least one accepted lake with at
  least one upstream trunk, the river bed and the lake bed are visibly
  joined in the dry preview (no grass gap).

**Why**: closes the visual disconnect between river stubs and lake bowls.

### C4. Lake count and spacing

**Rule**: lake density scales with grid size; the hard cap of 8 is removed.

**Required**:
- `target_lake_count = clamp(int(node_count / 24.0 * lake_density_scale + 2.0), 4, 64)`
- `is_lake_spacing_clear` minimum spacing reduced from `2` coarse-cells to
  `1` coarse-cell.
- Y-band exclusion stays: `node_y <= 1 || node_y >= grid_height - 2` rejects
  near-edge lakes.

**Why**: closes G4. With this contract a typical mid-cylinder grid (~256
nodes) yields 12..14 lakes by default, large grids yield up to 64.

### C5. Ocean band has dry seabed terrain

**Rule**: ocean band tiles get a dry-bed terrain id, not `TERRAIN_PLAINS_GROUND`.
This is consistent with R1's dry-first principle (water overlay is R2). The
preview palette renders these ids in distinctive blue tones so the player can
read the coast.

**Required**:
- New terrain ids in `core/systems/world/world_runtime_constants.gd`:
  ```
  TERRAIN_OCEAN_BED_SHALLOW = 9
  TERRAIN_OCEAN_BED_DEEP    = 10
  ```
- New terrain ids exported from `gdextension/src/world_core.cpp` (mirror
  constants):
  ```
  TERRAIN_OCEAN_BED_SHALLOW = 9
  TERRAIN_OCEAN_BED_DEEP    = 10
  ```
- Terrain priority inside `world_core.cpp` per-tile assignment, top wins:
  1. mountain wall / mountain foot (unchanged)
  2. ocean band: if `world_y < ocean_band_tiles` then
     - `TERRAIN_OCEAN_BED_SHALLOW` if `world_y >= ocean_band_tiles - 8`
     - else `TERRAIN_OCEAN_BED_DEEP`
  3. river / lake bed (unchanged)
  4. plains ground (unchanged)
- River mouth widening (C6) is allowed to overwrite ocean shallow rim with
  `TERRAIN_RIVERBED_*` only at the actual river-segment footprint inside the
  ocean band. Outside that footprint the shallow rim stays
  `TERRAIN_OCEAN_BED_SHALLOW`.
- Burning band is unaffected by this rule.
- Spawn safety patch is forbidden from being placed in the ocean band by
  existing logic; no change required.
- `is_ground_compatible_terrain` in `world_core.cpp` stays `false` for
  ocean ids (so the `47`-tile bank edge solve works against them).
- New preview palette colors in `core/systems/world/world_preview_palette.gd`:
  ```
  COLOR_OCEAN_BED_SHALLOW = Color(0.18, 0.36, 0.52, 1.0)   // matches world map shallow ring
  COLOR_OCEAN_BED_DEEP    = Color(0.06, 0.20, 0.38, 1.0)   // matches world map deep
  ```
  Wired into `_resolve_terrain_color`.

**Walkability**: ocean shallow stays walkable in V15 (dry preview, no water
overlay yet). Ocean deep stays walkable in V15 for the same reason. Future R2
water overlay will block both as filled. Movement query rule remains
`base_walkable && !water_overlay_blocks(world_tile)` per the original spec.

**Why**: closes G5. Player can finally read the coast in region preview and
in the playable world.

### C6. River mouth widening

**Rule**: river trunks visibly widen at the ocean mouth. The widening is
clearly readable in the dry preview.

**Required**:
- A river segment is "mouth-class" when:
  ```
  segment.b_world_y < ocean_band_tiles + COARSE * 2
  OR snapshot.ocean_band_mask[downstream_node] != 0
  ```
- For mouth-class segments:
  ```
  mouth_bonus = clamp(2.5 + flow * 6.5, 2.5, 8.0) * mouth_width_scale
  shallow_radius_tiles += mouth_bonus
  deep_radius_tiles    = max(deep_radius_tiles, shallow_radius_tiles * 0.45)
  flags |= FLAG_MOUTH_OR_DELTA
  ```
- The shallow radius after the mouth bonus is allowed to exceed the
  per-trunk clamp set by C7. Mouth width is the only legitimate way to
  exceed that clamp.

**Why**: closes G6. Mouth bonus is now `2.5..8.0` tiles, not `0.75`.

### C7. River bed width curve

**Rule**: trunk width grows visibly with flow and downstream distance, narrow
in headwaters, medium in mid-course, large at the mouth (with C6 bonus
applied on top).

**Required**:
- Replace the current curve in `river_rasterizer.cpp::resolve_shallow_radius`
  with:
  ```
  shallow_radius = clamp(
      0.50 + flow * 4.00 + order * 0.35 + downstream_to_ocean * 1.50 + valley * 0.40,
      0.75,
      7.50
  )
  shallow_radius *= 1.0 - min(0.35, wall_pressure * 0.45)
  shallow_radius *= bed_width_scale
  ```
- Replace the deep radius computation with:
  ```
  deep_radius = clamp(shallow_radius * 0.32, 0.45, shallow_radius - 0.65)
  ```
  When `shallow_radius < 1.5`, allow `deep_radius >= 0.45` and skip the
  shallow-minus-deep gap rule.

**Why**: closes G7. Maximum trunk width is now ~15 tiles (shallow radius
`7.5`, diameter `15`). With C6 mouth bonus, mouth diameter is up to `~31`
tiles. Upstream trunks remain ~1.5..3 tile cracks.

### C8. Node search halo

**Rule**: the per-region node search halo is at least `COARSE * 4` tiles, so
that the largest possible lake polygon (radius `144` tiles plus mountain
border halo from `world_core.cpp`) cannot be clipped at region edges.

**Required**:
- `river_rasterizer.cpp::NODE_SEARCH_HALO_TILES = COARSE * 4` (`= 256`).

**Why**: closes G8. Lake polygons that touch the region but whose center
node lies just outside the region now reach inside.

### C9. Settings: `worldgen_settings.rivers`

**Rule**: introduce a new `worldgen_settings.rivers` block.

**Required**:
- New resource `core/resources/river_gen_settings.gd` with fields:
  ```
  lake_density_scale: float = 1.0   # multiplier for target_lake_count
  lake_radius_scale:  float = 1.0   # multiplier for shallow/deep base radius
  mouth_width_scale:  float = 1.0   # multiplier for mouth_bonus
  bed_width_scale:    float = 1.0   # multiplier for trunk shallow radius
  ```
  All clamped to `[0.25, 4.0]` on load.
- `to_save_dict() / from_save_dict()` for save/load round-trip.
- `hard_coded_defaults()` static returning the values above.
- New top-level optional `data/balance/river_gen_settings.tres` may exist for
  designer tuning, but it must not be loaded as the default of last resort
  per spec rules. If `worldgen_settings.rivers` is missing in `world.json`,
  hard-coded loader defaults apply.
- `WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_*` extended with four new
  indices for the river settings, and `SETTINGS_PACKED_LAYOUT_FIELD_COUNT`
  bumped accordingly.
- `FoundationGenSettings.write_to_settings_packed` (or new sibling for
  `RiverGenSettings`) writes the four new floats into `settings_packed` so
  native code reads them via the existing settings_packed contract.
- Native `FoundationSettings` struct extended with a sibling `RiverSettings`
  struct (or appended fields). Native rasterizer reads them.
- All four scales feed the formulas in C2, C4, C6, C7 multiplicatively.

### C10. World version bump

**Rule**: every contract change above changes canonical generation, therefore
`WORLD_VERSION` must bump.

**Required**:
- `core/systems/world/world_runtime_constants.gd::WORLD_VERSION = 15`
- `core/systems/world/world_runtime_constants.gd::RIVER_GENERATION_VERSION = 15`
- `gdextension/src/river_rasterizer.h::RIVER_GENERATION_VERSION = 15`
- `gdextension/src/world_prepass.cpp::DRY_RIVER_OVERVIEW_VERSION = 15`
- Existing `world_version 14` saves continue to load with the V14 path
  unchanged. New worlds use V15.
- `make_signature` in `world_prepass.cpp` mixes the new river settings (this
  is automatic if you wire them into the signature mix).

---

## Performance Contract

R1B-Fix does not relax any performance rule of the original spec.

| Operation | Class | Dirty unit | Constraint |
|---|---|---|---|
| `lake_footprint::classify_tile` | background native, called per tile | `32x32` chunk plus halo | O(vertex_count) per tile = O(16); no allocations |
| `lake_footprint::build_polygon` | boot/load worker | one polygon per accepted lake | called once per snapshot, no per-frame work |
| Ocean-band terrain id assignment | background native | per tile in chunk packet generation | O(1) per tile |
| Lake count loop | snapshot build | one iteration over node grid | bounded by node_count, runs in `WorldPrePass` |
| Mouth widening | background native | per river segment | O(1) per segment |

Forbidden:
- Storing per-tile lake or ocean masks anywhere except inside the chunk
  packet that already exists.
- Allocating a polygon per region preview tile. `build_polygon` runs once per
  lake at snapshot build time and is cached on the snapshot.
- Adding a GDScript loop over chunk tiles for any of the new logic.
- Saving riverbed, lakebed, ocean-bed, or polygon arrays per chunk.

---

## Acceptance Criteria

### Lake footprint

- [ ] At `world_version 15`, every accepted lake renders the same polygon
      shape in the world overview and in the region preview. Visual sample
      check on at least 3 different seeds.
- [ ] Lake polygon stored in `WorldPrePass.terminal_lake_polygons` is the
      16-vertex deformed polygon described by C2. No 4-vertex squares.
- [ ] No code path renders a lake as a circle. `apply_candidate_to_cell`
      lake path is removed; both call sites use `lake_footprint::classify_tile`.
- [ ] At least one accepted lake on a sample seed visibly receives an
      incoming river trunk that terminates inside the lake polygon, with no
      grass gap between the trunk endpoint and the lake rim.

### Lake count

- [ ] On a mid-cylinder world (`grid_width * grid_height >= 256`) with default
      settings, the number of accepted lakes is at least `8` and at most `32`.
- [ ] On a large-cylinder world (`grid_width * grid_height >= 1024`) with
      default settings, the number is at least `32` and at most `64`.
- [ ] Setting `lake_density_scale = 0.5` halves the count (within +/- 1
      tolerance for spacing rejection).

### Ocean band

- [ ] Region preview at any chunk inside `world_y < ocean_band_tiles` shows
      blue ocean-bed colors, not grass.
- [ ] Region preview at any chunk crossing the ocean shoreline shows a
      visible boundary between `TERRAIN_OCEAN_BED_SHALLOW` and
      `TERRAIN_PLAINS_GROUND`, with the `47`-tile bank edge solving against
      the ocean shallow rim.
- [ ] In-game world (not just preview) shows ocean-bed terrain in the ocean
      band. Walkability is not blocked yet (R2 is later).
- [ ] Spawn point is never inside the ocean band.

### Mouth widening

- [ ] Every accepted ocean-directed river trunk has a visibly widened final
      segment as it enters the ocean band. Diameter at the mouth is at least
      `~10` tiles for trunks with `flow >= 0.5`.
- [ ] `FLAG_MOUTH_OR_DELTA` is set on at least one segment per accepted
      ocean-directed trunk.

### Width curve

- [ ] Headwater trunks (lowest `flow`, deepest `node_y`) render at shallow
      radius `<= 1.5` tiles.
- [ ] Mid-course trunks render at shallow radius in the `2..5` tile range.
- [ ] Pre-mouth trunks (high flow, near top) render at shallow radius
      `5..7.5` tiles. Mouth bonus may push diameter higher.

### Halo

- [ ] No region preview chunk shows a clipped half-lake near its edge that
      reappears whole in the adjacent chunk. Sample on 3 chunk-boundary
      cases per seed.

### Settings

- [ ] `worldgen_settings.rivers` is written to `world.json` for new worlds.
- [ ] Existing worlds with no `worldgen_settings.rivers` block load with
      hard-coded defaults applied.
- [ ] Changing any of the four scales bumps signature, invalidates preview
      cache, and produces a different deterministic output.

### Determinism and persistence

- [ ] Same `(seed, settings)` produces identical lake polygons across
      snapshot rebuilds.
- [ ] No riverbed, lakebed, ocean-bed, or polygon arrays appear in any
      `ChunkDiffFile` or `world.json` block.
- [ ] `world_version 14` saves continue to load with V14 generation
      unchanged.
- [ ] `make_signature` in `world_prepass.cpp` mixes all four new river
      settings.

### Performance

- [ ] Region preview rebuild for a `Большой цилиндр` world remains within
      the existing streaming budget. No new main-thread loop over chunk
      tiles in GDScript.
- [ ] `lake_footprint::classify_tile` does not allocate.
- [ ] `lake_footprint::build_polygon` runs at snapshot build time, not in
      `rasterize_region`.

---

## Files Allowed To Touch

Native:
- `gdextension/src/river_rasterizer.h`
- `gdextension/src/river_rasterizer.cpp`
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_utils.h` and `.cpp` (only if a new shared helper is needed)
- new file: `gdextension/src/lake_footprint.h`
- new file: `gdextension/src/lake_footprint.cpp`
- the GDExtension build manifest only to register the two new files

GDScript:
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_preview_palette.gd`
- `core/systems/world/world_foundation_palette.gd` (only if ocean color
  parity with world overview requires a constant change)
- new file: `core/resources/river_gen_settings.gd`
- `core/resources/foundation_gen_settings.gd` (only to chain the new river
  settings into `settings_packed` if that is the chosen wiring path)
- `core/systems/world/world_preview_controller.gd` (only if it must forward
  the new settings to the packet backend; no logic changes beyond plumbing)

Data (optional):
- new file: `data/balance/river_gen_settings.tres` (designer tuning copy
  only; not loaded as default)

Docs (mandatory if surfaces match the rule):
- `docs/02_system_specs/world/river_generation.md` (only the
  `## Status Rationale` block updated to point at this amendment and the new
  V15 acceptance correction)
- `docs/02_system_specs/meta/packet_schemas.md` (only if a new settings_packed
  layout slot or river field is added)
- `docs/02_system_specs/meta/save_and_persistence.md` (only the
  `worldgen_settings.rivers` block is added)
- `docs/02_system_specs/meta/system_api.md` (only if a new public read
  surface appears)
- `docs/00_governance/PROJECT_GLOSSARY.md` (only if the dry ocean bed needs
  a glossary term)

## Files Forbidden To Touch

- `BuildingSystem`, `PowerSystem`, `IndoorSolver`
- combat, fauna, progression, inventory, crafting, lore systems
- subsurface / Z-level runtime
- environment runtime (weather, season, wind, water overlay - that is R2)
- save chunk diff shape
- any deleted legacy world runtime files
- ADRs (no ADR change is required by this amendment)
- any currently-approved spec other than `river_generation.md` rationale
  block, and only as described above

## World Version

- `WORLD_VERSION`: `14` -> `15`
- `RIVER_GENERATION_VERSION`: `14` -> `15`
- `WORLD_FOUNDATION_VERSION`: unchanged
- Old saves (V14) continue to use V14 generation. New worlds use V15.

## Out of Scope

- Split / rejoin side channels (R1D)
- Water overlay (R2)
- Ocean tile art beyond `TERRAIN_OCEAN_BED_*` palette colors
- Lake outlet rivers (rivers leaving a lake to a downstream basin) - handled
  later, not by this amendment
- Erosion or post-load mutation
- Player-made canals
- Multiplayer water replication
- Subsurface rivers or aquifers
- Biome content
- Drought UI

## Required Canonical Doc Follow-Ups When Code Lands

Each entry below requires grep-backed confirmation in the closure report.

- `river_generation.md::Status Rationale` updated to point at this amendment.
- `packet_schemas.md` updated if `settings_packed` layout grows.
- `save_and_persistence.md` updated for `worldgen_settings.rivers`.
- `system_api.md` updated if a new public read surface is added.
- `PROJECT_GLOSSARY.md` updated for `Ocean bed (dry)` term if added.
- `terrain_hybrid_presentation.md` updated only if the ocean-bed terrain ids
  need a presentation profile (recommended: yes).

`not required` is valid only with grep proof against the relevant living doc.

## Risks

| Risk | Mitigation |
|---|---|
| Lake polygon allocation in hot path | Polygon built once at snapshot time, classify_tile uses inline math only |
| Ocean rim edge solve breaks atlas | Treat ocean ids as non-ground-compatible from the start, identical contract to riverbed |
| Mouth bonus pushes shallow into mountain wall | Mountain wall priority remains highest in terrain_id_grid, so mountains always win |
| Lake count explosion on largest worlds | Hard cap stays at 64 |
| Designers flip scales beyond reasonable | Scale clamp `[0.25, 4.0]` on load |
| Save round-trip with new settings | Default values applied if missing; signature mix updated |
| World map shows lake but region clips it | Halo bumped to `COARSE * 4`, polygon sized to fit halo |

## Open Questions

- Whether ocean-bed shallow rim should be tunable beyond the fixed `8` tiles
  in V15 (likely a later amendment).
- Whether the `16`-vertex polygon should grow to `24` for very large lakes
  (deferred; revisit if visual review demands it).
- Whether river outlet from a lake to a downstream basin should be a small
  subset of R1D, or part of a later amendment (deferred).
- Whether `data/balance/river_gen_settings.tres` should be the designer
  tuning surface, or whether tuning happens directly in the new-game UI
  (designer call; not blocking).

## Status Rationale

This amendment is the minimal correction that brings R1B's visual output in
line with the shape acceptance of `river_generation.md` V1.0 without crossing
into R1D (split/rejoin) or R2 (water overlay). It removes two architectural
violations (dual lake source, polygon ignored), introduces ocean dry-bed
terrain ids that the original spec already implied as eventual content, and
unlocks the missing tuning knobs. The implementation must follow this
amendment word-for-word; deviations require an updated amendment, not silent
drift.
