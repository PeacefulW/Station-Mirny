# Mountain Contour Runtime V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> This plan is intentionally stricter than a normal visual-refactor plan. The goal is not to make mountains merely prettier. The goal is to replace visible square mountain cells with generator-authored continuous contour rendering and matching contour collision, without reintroducing the failed `perenos v.1` runtime SDF texture pipeline.

**Goal:** Implement Mountain Contour Runtime V2 for mountains first: generator-authored style, fast native contour geometry, generator-like top/face/rim/outline/normals, capsule collision against the visible lower footprint, instantaneous mining updates, and no square fallback around mountains.

**Architecture:** Keep logical world truth tile-based (`base + runtime diff`), but derive production contour visual/collision data from the effective mountain solid state. The generator exports style/material data. Runtime rebuilds only lightweight mesh/collision data on dirty updates, never per-chunk SDF mask/height/normal textures after mining.

**Tech Stack:** Godot 4.x GDScript, Godot GDExtension C++, Rust/Python `tools/rimworld-autotile-lab/desktop_app`, Godot headless smoke tests, Rust `cargo test`, Python `unittest`.

**Primary Docs To Land Before Code:**
- `docs/02_system_specs/world/mountain_contour_runtime_v2_design_brief.md`
- `docs/05_adrs/0008-generator-authored-contour-mesh-runtime.md`
- `docs/02_system_specs/world/mountain_contour_runtime_v2.md`

---

## Hard Constraints

These constraints are acceptance requirements, not preferences.

- [ ] Do not resurrect `perenos v.1` wholesale.
- [ ] Do not generate or update per-chunk `mask`, `height`, `normal`, or `collision_sdf` `ImageTexture` buffers after mining.
- [ ] Do not use half-resolution contour rendering or upscale a half-resolution chunk texture.
- [ ] Do not use square `walkable_flags` as a hidden fallback for movement near contour mountains.
- [ ] Do not render mountain wall/foot as visible square TileMap cells after the cutover milestone.
- [ ] Do not block mining on asynchronous “pretty contour ready later” state.
- [ ] Do not change save format for visual style or contour cache data.
- [ ] Do not change logical tile size, chunk size, or save sharding.
- [ ] Do not create binary/tool artifacts in the repository.
- [ ] Do not let invalid or missing style textures be discovered during live chunk publication; validate before runtime use.

---

## Success Definition

Mountain Contour Runtime V2 is considered successful only when all of these are true:

- [ ] Mountains no longer visibly render as 64 px square cells.
- [ ] The runtime mountain image is visually comparable to the generator reference preview for the same style and mask.
- [ ] Top, face, rim, bottom outline, material normals, and shape normals are present in-game.
- [ ] Collision uses the contour footprint, including the visible lower face/contact line, not square tile boundaries.
- [ ] Player and NPC movement use the same contour collision query.
- [ ] Mining one mountain tile updates terrain visual and collision immediately, with no stale square fallback.
- [ ] Seam tiles update their owning chunk plus required seam-neighbour chunks without cracks.
- [ ] Ordinary mining update target: `<= 33 ms`; seam mining target: `<= 50 ms`; absolute failure threshold: `> 100 ms`.
- [ ] Dense mountain chunk load does not show second-long contour readiness delays.
- [ ] Ground/water/shore migration remains out of first playable scope; mountains are first.

---

## Non-Goals For This Plan

- [ ] Do not implement ground, dug-ground, lake-bed, or shoreline contour runtime in this first plan.
- [ ] Do not implement biome-specific mountain materials yet; use one mountain style first.
- [ ] Do not redesign generator preview UI beyond fields required for export parity.
- [ ] Do not solve full navmesh/pathfinding if a point/capsule contour query is enough for current movement and placement tests.
- [ ] Do not make the old F10 overlay a player-facing feature.

---

## Task 0: Land Documentation And Indexes

**Goal:** Put the already-authored decision documents into canonical project paths before code starts.

**Files:**
- Add: `docs/02_system_specs/world/mountain_contour_runtime_v2_design_brief.md`
- Add: `docs/05_adrs/0008-generator-authored-contour-mesh-runtime.md`
- Add: `docs/02_system_specs/world/mountain_contour_runtime_v2.md`
- Modify: `docs/05_adrs/README.md`
- Modify: `docs/02_system_specs/README.md` if the world spec index exists and tracks world specs

**Steps:**
- [ ] Copy the design brief into `docs/02_system_specs/world/mountain_contour_runtime_v2_design_brief.md`.
- [ ] Copy the ADR into `docs/05_adrs/0008-generator-authored-contour-mesh-runtime.md`.
- [ ] Copy the system spec into `docs/02_system_specs/world/mountain_contour_runtime_v2.md`.
- [ ] Add ADR-0008 to `docs/05_adrs/README.md` as `Draft`.
- [ ] Add the new system spec to the system-spec index if the index is present.
- [ ] Keep all three new docs as `status: draft` / `source_of_truth: false` until reviewed.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] No code files changed in Task 0.
- [ ] New docs are linked from the relevant indexes.
- [ ] The docs explicitly reject runtime SDF texture rebuilds, square fallback collision, and half-res upscale.

---

## Task 1: Generator Style Export Contract

**Goal:** Add a lightweight style export path that preserves generator-authored appearance parameters without requiring the game to render full SDF chunk images at runtime.

**Files:**
- Modify: `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- Modify: `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/tests/test_app_payload.py`
- Modify: `tools/rimworld-autotile-lab/desktop_app/README.md`
- Test: Rust tests in `tools/rimworld-autotile-lab/desktop_app/core`
- Test: Python tests in `tools/rimworld-autotile-lab/desktop_app/shell/tests`

**New output target:**

```text
{asset_name}_contour_style.v1.json
{asset_name}_top_albedo.png
{asset_name}_face_albedo.png
{asset_name}_base_albedo.png
{asset_name}_top_modulation.png
{asset_name}_face_modulation.png
{asset_name}_top_normal.png
{asset_name}_face_normal.png
{asset_name}_edge_profile_lut.png
{asset_name}_height_profile_lut.png
{asset_name}_reference_preview.png
{asset_name}_reference_normal.png
```

**Required JSON fields:**

```text
schema_version
asset_name
preset
logical_tile_size_px
style_tile_size_px
south_height_px
north_height_px
side_height_px
corner_round_px
diagonal_smooth_px
contour_warp_px
roughness
corner_variation
rim_width_px
edge_debris
edge_color_strength
mountain_outline_enabled
mountain_outline_width_px
normal_strength
normal_detail_strength
top_world_scale_px
face_world_scale_px
macro_world_scale_px
texture_scale
colors
texture_paths
reference_preview_path
reference_normal_path
```

**Steps:**
- [ ] Add failing Rust tests that `ContourStyleV1` serializes all required fields.
- [ ] Add failing Rust tests that exported file paths use the authored `asset_name` prefix.
- [ ] Add failing Python tests that shell payloads carry every field needed by `ContourStyleV1`.
- [ ] Add export mode `ContourStyleV1` or add the style JSON/LUT output to the existing mountain runtime export mode without changing legacy output semantics.
- [ ] Export top/face/base albedo, top/face modulation, top/face normal exactly from generator material stacks.
- [ ] Export `edge_profile_lut` and `height_profile_lut` as small reusable style textures, not per-chunk runtime buffers.
- [ ] Export `reference_preview` and `reference_normal` for parity tests only; game runtime must not depend on them during gameplay.
- [ ] Document the new style export in `desktop_app/README.md`.
- [ ] Run `cargo test` in `tools/rimworld-autotile-lab/desktop_app/core`.
- [ ] Run `python -m unittest shell.tests.test_app_payload` from `tools/rimworld-autotile-lab/desktop_app/shell`.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] A mountain style can be exported without generating any per-game-chunk image.
- [ ] All visual tuning fields needed for top/face/rim/outline/normals are in JSON.
- [ ] Exported textures are reusable material/style assets.
- [ ] Reference images exist only for validation/parity.

---

## Task 2: Runtime Style Resource Loader

**Goal:** Let Godot validate and load generator-authored mountain style data before gameplay uses it.

**Files:**
- Add: `core/systems/world/mountain_contour_style.gd`
- Add: `core/systems/world/mountain_contour_style_registry.gd`
- Add: `assets/textures/terrain/mountains/<style_name>/*` after exporting one canonical style
- Modify: `core/systems/world/world_streamer.gd` only for bootstrap/init wiring if needed
- Test: `tools/mountain_contour_style_registry_smoke_test.gd`
- Modify docs if a public runtime API is introduced: `docs/02_system_specs/meta/system_api.md`

**Steps:**
- [ ] Add a failing Godot smoke test that loads a known exported style JSON.
- [ ] Add a `MountainContourStyle` resource/helper that validates required scalar fields.
- [ ] Validate every required texture path exists and loads as `Texture2D`.
- [ ] Validate `logical_tile_size_px == WorldRuntimeConstants.TILE_SIZE_PX`.
- [ ] Validate style fields stay within safe ranges: heights, rim width, outline width, normal strengths, texture scales.
- [ ] Add registry lookup by style id / asset name.
- [ ] Make missing style data a boot/validation failure, not a chunk-publication surprise.
- [ ] Do not instantiate per-tile or per-chunk materials in this task.
- [ ] Add debug snapshot method for validation, if helpful.
- [ ] Run the style registry smoke test headless.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Style data can be loaded and validated in isolation.
- [ ] Invalid/missing textures fail before live chunk publication.
- [ ] No gameplay rendering path consumes the style yet.
- [ ] No save data or chunk packet data stores style paths.

---

## Task 3: Native Production Contour Result

**Goal:** Replace the debug-only F10 result shape with a production contour result that can drive visuals and collision, while keeping the existing debug helper intact until cutover.

**Files:**
- Modify: `gdextension/src/mountain_contour.h`
- Modify: `gdextension/src/mountain_contour.cpp`
- Modify: `gdextension/src/world_core.h`
- Modify: `gdextension/src/world_core.cpp`
- Modify: `docs/02_system_specs/meta/packet_schemas.md` only if the new result shape is documented as a public native result
- Test: `tools/mountain_contour_runtime_l1_smoke_test.gd`

**New native method:**

```text
WorldCore.build_mountain_contour_runtime(
  solid_halo: PackedByteArray,
  chunk_size: int,
  tile_size_px: int,
  style_params: Dictionary
) -> Dictionary
```

**Required result fields:**

```text
ready: bool
chunk_size: int
tile_size_px: int
halo_side: int
solid_sample_count: int
visual_top_vertices: PackedVector2Array
visual_top_indices: PackedInt32Array
visual_top_attributes: PackedFloat32Array
visual_face_vertices: PackedVector2Array
visual_face_indices: PackedInt32Array
visual_face_attributes: PackedFloat32Array
visual_rim_vertices: PackedVector2Array
visual_rim_indices: PackedInt32Array
visual_rim_attributes: PackedFloat32Array
visual_outline_vertices: PackedVector2Array
visual_outline_indices: PackedInt32Array
visual_outline_attributes: PackedFloat32Array
collision_loops: Array[PackedVector2Array]
collision_aabbs: Array[Rect2]
boundary_edge_count: int
seam_touch_mask: int
compute_time_usec: int
```

**Steps:**
- [ ] Add failing smoke test for `build_mountain_contour_runtime()` existence and basic shape.
- [ ] Keep `build_mountain_contour_debug()` for compatibility until the cutover task.
- [ ] Implement runtime result using the same effective `solid_halo` input shape as F10.
- [ ] Generate top fill mesh from contour topology.
- [ ] Generate face mesh from visible south/diagonal/front-facing contour edges according to style heights.
- [ ] Generate rim mesh as a narrow band using `rim_width_px`.
- [ ] Generate bottom-outline mesh only along lower face contact edges when outline is enabled.
- [ ] Generate collision loops for the final blocked footprint: top contour plus facade extrusion down to the lower visible contact line.
- [ ] Include per-vertex attributes needed by shader: edge distance, face depth, edge kind, local noise coordinates, material zone.
- [ ] Detect seam touch mask so seam neighbour chunk invalidation can be precise.
- [ ] Return empty but valid arrays for all-empty chunks.
- [ ] Return full valid mesh/loops for all-solid chunks without excessive vertex explosion.
- [ ] Add test cases: single tile, 2x2 blob, diagonal contact, inner hole, seam-touch edge.
- [ ] Run native/Godot smoke test headless.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] No image buffers or texture bytes appear in the native runtime contour result.
- [ ] Diagonal-only contact remains separate where appropriate; it must not invent face-connected solid components.
- [ ] Result is deterministic for same `solid_halo` + style params.
- [ ] Result can be computed synchronously for one 16x16 chunk + halo within the mining latency budget.

---

## Task 4: Mountain Contour Visual Layer Probe

**Goal:** Render production contour mesh in Godot in a controlled probe scene without cutting over the live world yet.

**Files:**
- Add: `core/systems/world/mountain_contour_visual_layer.gd`
- Add: `assets/shaders/mountain_contour_runtime.gdshader`
- Add: `tools/mountain_contour_visual_probe.gd`
- Add/Modify: exported canonical mountain style under `assets/textures/terrain/mountains/<style_name>/`

**Steps:**
- [ ] Add a probe that builds a fixed `solid_halo`, calls `build_mountain_contour_runtime()`, and draws the result with `MountainContourVisualLayer`.
- [ ] Add shader uniforms for all style textures: top/face/base albedo, top/face modulation, top/face normal, edge LUT, height LUT.
- [ ] Add shader uniforms for style scalars: heights, rim width, outline width, normal strengths, UV scales, colors.
- [ ] Implement world-space UV sampling for top material.
- [ ] Implement face-space UV sampling for facade material.
- [ ] Blend material normal with generated shape normal; do not fake normals from color.
- [ ] Render top, face, rim, and bottom outline from mesh attributes and LUTs.
- [ ] Make the probe save a screenshot under `artifacts/mountain_contour_visual_probe/`.
- [ ] Add debug stats: vertex counts, triangle counts, material readiness, screenshot path.
- [ ] Run the probe headless.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Probe renders a continuous mountain, not square TileMap cells.
- [ ] Top/face materials and normals are visibly different.
- [ ] Bottom outline appears only along lower contact, not around the entire contour.
- [ ] No runtime-generated per-chunk mask/height/normal texture is created.
- [ ] Live world rendering remains unchanged in this task.

---

## Task 5: Contour Collision Query Probe

**Goal:** Validate contour collision independently before integrating movement/building code.

**Files:**
- Add: `core/systems/world/mountain_contour_collision_cache.gd`
- Add: `tools/mountain_contour_collision_probe.gd`
- Modify: `gdextension/src/mountain_contour.cpp` only if collision loop output needs correction

**Required API:**

```text
MountainContourCollisionCache.configure(chunk_coord, collision_loops, collision_aabbs)
MountainContourCollisionCache.is_point_blocked(local_pos: Vector2) -> bool
MountainContourCollisionCache.is_capsule_blocked(local_pos: Vector2, radius_px: float) -> bool
MountainContourCollisionCache.slide_capsule(local_pos, motion, radius_px) -> Dictionary
MountainContourCollisionCache.intersects_building_footprint(local_shape) -> bool
```

**Steps:**
- [ ] Add failing probe tests for point collision against single tile, blob, diagonal gap, and inner dug hole.
- [ ] Add failing probe tests for capsule collision near rounded/diagonal contour edges.
- [ ] Add broad-phase AABB rejection before loop checks.
- [ ] Implement point-in-loop and distance-to-segment checks.
- [ ] Implement capsule blocked query with radius.
- [ ] Implement simple slide result for movement integration.
- [ ] Treat missing cache as blocked in probe semantics.
- [ ] Run collision probe headless.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Collision follows lower visible footprint, not square tile centers.
- [ ] Diagonal visual openings can be passable when the capsule fits.
- [ ] Missing cache never silently falls back to square walkability.
- [ ] Collision cache is transient and not saved.

---

## Task 6: Live Chunk Integration Without Player Cutover

**Goal:** Attach contour visual/collision data to loaded `ChunkView` instances, but keep player movement cutover disabled until validation passes.

**Files:**
- Modify: `core/systems/world/chunk_view.gd`
- Modify: `core/systems/world/world_streamer.gd`
- Modify: `core/systems/world/world_runtime_constants.gd` only if constants for contour debug flags are needed; do not change tile/chunk sizes
- Add: `tools/mountain_contour_chunk_integration_smoke_test.gd`

**Steps:**
- [ ] Add chunk-local solid halo builder from effective loaded packet state (`base + diff`).
- [ ] Include one-tile halo from loaded seam neighbours where available.
- [ ] If required seam neighbour data is missing, mark contour cache not ready and blocked for collision semantics.
- [ ] Add `ChunkView.apply_mountain_contour_runtime_data(...)`.
- [ ] Add `MountainContourVisualLayer` as a child layer with stable z-order above ground and below roof/cover overlays as required.
- [ ] Do not remove square mountain TileMap rendering yet unless this task includes full cutover validation. Prefer probe/integration visibility toggle first.
- [ ] Store collision cache per chunk in `WorldStreamer` or a dedicated contour-collision owner.
- [ ] Add debug snapshot method: visual ready, collision ready, vertex counts, loop counts, style id, compute time.
- [ ] Run chunk integration smoke test.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Loaded chunks can produce contour visual/collision data from packet state.
- [ ] Seam halo use is explicit and observable in debug state.
- [ ] No movement or building behavior changes yet.
- [ ] No save format changes.

---

## Task 7: Mining Dirty Update Integration

**Goal:** Rebuild contour visual/collision synchronously after a mined mountain tile disappears.

**Files:**
- Modify: `core/systems/world/world_streamer.gd`
- Modify: `core/systems/world/chunk_view.gd`
- Modify: `core/systems/world/world_diff_store.gd` only if helper access to dirty locals is needed
- Test: `tools/mountain_contour_mining_dirty_smoke_test.gd`

**Steps:**
- [ ] Add failing test: mine a mountain tile and assert contour revision changes immediately.
- [ ] Add failing test: mined tile near chunk seam rebuilds owning chunk plus required seam neighbour chunks.
- [ ] Add failing test: visual and collision revisions match after mining.
- [ ] After `_apply_loaded_override(...)`, rebuild affected contour chunks synchronously when terrain changed from mountain wall/foot to dug ground.
- [ ] Rebuild only dirty chunk plus seam neighbours indicated by local tile edge/seam rules.
- [ ] Do not rebuild a 3x3 chunk area unless a test proves it is necessary.
- [ ] Do not queue contour rebuild behind long async worker readiness for mining.
- [ ] Add telemetry: `contour_rebuild_usec`, `visual_apply_usec`, `collision_apply_usec`, affected chunk count.
- [ ] Run mining dirty smoke test.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Mining update produces no stale mountain visual on the removed tile.
- [ ] Collision updates in the same logical mutation step.
- [ ] Seam cases produce no visible crack or stale collision.
- [ ] Worst-case mining update stays under the absolute 100 ms threshold.

---

## Task 8: Movement Cutover To Contour Collision

**Goal:** Make player/NPC walkability use contour collision around mountains, with no square fallback.

**Files:**
- Modify: `core/systems/world/world_streamer.gd`
- Modify movement authority/system files that call `WorldStreamer.is_walkable_at_world(...)`
- Add or modify movement tests/tools if present
- Test: `tools/mountain_contour_movement_smoke_test.gd`

**Steps:**
- [ ] Audit every call site of `is_walkable_at_world(...)`.
- [ ] Add new API if needed: `is_capsule_walkable_at_world(world_pos, radius_px)`.
- [ ] Add new API if needed: `move_capsule_with_contour_slide(start, motion, radius_px)`.
- [ ] Use contour collision cache for mountain blocking.
- [ ] Treat missing contour cache as blocked near mountain chunks.
- [ ] Preserve ordinary non-mountain walkability for non-contour terrain until later ground/water contour migration.
- [ ] Add diagonal gap test: capsule may pass only when contour geometry says it fits.
- [ ] Add rounded-corner slide test: capsule slides along contour instead of snagging on square corners.
- [ ] Run movement smoke test.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Player movement does not collide with invisible square mountain corners.
- [ ] Player cannot walk through the visible lower mountain footprint.
- [ ] NPC movement uses the same query or has a documented adapter to the same cache.
- [ ] Missing cache blocks instead of falling back to square flags.

---

## Task 9: Building Placement Cutover To Contour Footprint

**Goal:** Make building placement respect contour mountain collision so objects can align along diagonal/organic walls when their footprint fits.

**Files:**
- Modify building placement system files that currently rely on tile-only walkability
- Modify: `core/systems/world/world_streamer.gd` if a placement query API is added
- Test: `tools/mountain_contour_building_placement_smoke_test.gd`

**Required API:**

```text
WorldStreamer.is_placement_shape_clear(world_shape) -> bool
```

**Steps:**
- [ ] Add failing test: rectangular placement near diagonal mountain wall can succeed when footprint does not intersect contour collision.
- [ ] Add failing test: placement fails when footprint intersects visible lower mountain footprint.
- [ ] Keep grid anchoring rules separate from collision geometry rules.
- [ ] Add placement query using contour collision loops and ordinary tile occupancy/building checks.
- [ ] Treat missing contour cache as blocked.
- [ ] Run building placement smoke test.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Placement is no longer blocked solely because a square neighbour cell was historically mountain if the contour footprint leaves room.
- [ ] Placement never intersects visible mountain facade/outline footprint.
- [ ] Save format for buildings remains unchanged.

---

## Task 10: Visual Cutover For Mountain TileMap Cells

**Goal:** Stop rendering visible square mountain wall/foot cells in the live world once contour visual and collision are ready.

**Files:**
- Modify: `core/systems/world/chunk_view.gd`
- Modify: `core/systems/world/world_tile_set_factory.gd` only if mountain source wiring must be disabled or separated
- Modify tests that assert mountain TileMap cell counts if they exist
- Test: `tools/mountain_contour_cutover_smoke_test.gd`

**Steps:**
- [ ] Add failing test that visible mountain base/roof TileMap cells are not used as the live mountain surface after cutover.
- [ ] Keep logical `terrain_ids`, `mountain_flags`, and `mountain_id_per_tile` in packet state.
- [ ] Prevent `TERRAIN_MOUNTAIN_WALL` / `TERRAIN_MOUNTAIN_FOOT` from drawing as visible square base cells.
- [ ] Keep mountain cover/roof systems functional if they depend on mountain ids/flags.
- [ ] Ensure dug ground appears after mining where the mountain tile was removed.
- [ ] Ensure contour visual z-order does not hide ground incorrectly outside the visible facade footprint.
- [ ] Run cutover smoke test.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] No visible square mountain TileMap fallback remains.
- [ ] Mountain roof/cover logic still has the logical mountain data it needs.
- [ ] Mining reveals dug ground and updates contour visual/collision together.

---

## Task 11: Generator-vs-Godot Parity Harness

**Goal:** Prove that the runtime mountain appearance matches the generator reference closely enough for the generator to remain the authoritative art tool.

**Files:**
- Add: `tools/mountain_contour_parity_probe.gd`
- Add: `tools/rimworld-autotile-lab/desktop_app/...` helper or CLI option if needed for deterministic reference export
- Add: `artifacts/mountain_contour_parity/.gitkeep` only if artifact directory conventions allow it

**Test masks:**

```text
single tile
2x2 blob
large blob
thin diagonal opening
inner dug hole
straight south face
chunk seam edge
mined-tile notch
```

**Steps:**
- [ ] Add a deterministic generator reference export for every test mask.
- [ ] Render matching Godot runtime screenshots for every test mask.
- [ ] Compare silhouette coverage diff.
- [ ] Compare albedo visual diff with a documented tolerance.
- [ ] Compare normal-map diff with a documented tolerance.
- [ ] Save diff images under `artifacts/mountain_contour_parity/`.
- [ ] Fail the probe when seams, missing outline, missing face normals, or square edges are detected.
- [ ] Run parity probe.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Runtime output is not merely “pretty”; it is measurably close to generator reference.
- [ ] Differences are documented and bounded.
- [ ] A generator re-export changes the game style without code changes when the runtime shader contract already supports the fields.

---

## Task 12: Performance And No-Fallback Stress Probe

**Goal:** Validate dense mountain loading, repeated mining, and no-fallback behavior under worst practical conditions.

**Files:**
- Add: `tools/mountain_contour_runtime_perf_probe.gd`
- Modify: performance telemetry helpers if needed
- Add: `artifacts/mountain_contour_runtime_perf/` output path if artifact conventions allow it

**Scenarios:**

```text
9 loaded chunks, dense mountains
all-solid chunk
all-empty chunk
checker/diagonal stress mask
10 sequential mined mountain tiles
5 seam mined mountain tiles
movement along rounded contour for N frames
placement near diagonal contour
```

**Steps:**
- [ ] Measure initial contour build time per loaded chunk.
- [ ] Measure mining rebuild time per affected chunk.
- [ ] Measure visual apply time.
- [ ] Measure collision cache apply time.
- [ ] Measure movement query cost over many frames.
- [ ] Assert no `ImageTexture.create_from_image()` path is used for contour mining updates.
- [ ] Assert no square mountain TileMap fallback is visible after cutover.
- [ ] Assert missing contour cache blocks movement/placement instead of using square fallback.
- [ ] Produce JSON report under `artifacts/mountain_contour_runtime_perf/`.
- [ ] Run perf probe.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Ordinary mining contour update target: `<= 33 ms`.
- [ ] Seam mining contour update target: `<= 50 ms`.
- [ ] Absolute failure threshold: `> 100 ms`.
- [ ] No second-long contour readiness delays appear during chunk load.
- [ ] Dense mountain maps remain playable on GTX 1060 / Ryzen 2600 class hardware.

---

## Task 13: Documentation Closure And Approval Flip

**Goal:** Update docs to match implemented reality and flip draft docs only after tests pass.

**Files:**
- Modify: `docs/02_system_specs/world/mountain_contour_runtime_v2.md`
- Modify: `docs/05_adrs/0008-generator-authored-contour-mesh-runtime.md`
- Modify: `docs/05_adrs/README.md`
- Modify: `docs/02_system_specs/meta/packet_schemas.md` if native result shape is treated as documented public API
- Modify: `docs/02_system_specs/meta/system_api.md` if new public WorldStreamer/WorldCore APIs are introduced
- Modify: generator README if final export paths differ from Task 1

**Steps:**
- [ ] Update spec with final field names and API names from implementation.
- [ ] Update ADR status from `draft` to `approved` only after design decision is accepted.
- [ ] Update ADR index status to `Approved` only after approval.
- [ ] Update packet/system API docs for new public runtime/native methods.
- [ ] Add final performance numbers from stress probe.
- [ ] Add final known limitations and out-of-scope follow-ups.
- [ ] Run all relevant smoke tests and parity/perf probes.
- [ ] Run `git diff --check`.

**Acceptance:**
- [ ] Docs match code.
- [ ] Draft/approved statuses are truthful.
- [ ] All new runtime boundaries are documented.
- [ ] No temporary “probe-only” code is accidentally treated as production unless documented.

---

## Required Smoke Test Names

Use these names unless a better naming convention already exists:

```text
tools/mountain_contour_style_registry_smoke_test.gd
tools/mountain_contour_runtime_l1_smoke_test.gd
tools/mountain_contour_visual_probe.gd
tools/mountain_contour_collision_probe.gd
tools/mountain_contour_chunk_integration_smoke_test.gd
tools/mountain_contour_mining_dirty_smoke_test.gd
tools/mountain_contour_movement_smoke_test.gd
tools/mountain_contour_building_placement_smoke_test.gd
tools/mountain_contour_cutover_smoke_test.gd
tools/mountain_contour_parity_probe.gd
tools/mountain_contour_runtime_perf_probe.gd
```

---

## Suggested Validation Commands

Use the project-local Godot executable or a `GODOT4` environment variable. Do not commit downloaded Godot binaries.

```powershell
# Generator Rust tests
cd tools\rimworld-autotile-lab\desktop_app\core
cargo test

# Generator Python shell tests
cd ..\shell
python -m unittest shell.tests.test_app_payload

# Godot smoke test examples
$env:GODOT4 --headless --path . --script res://tools/mountain_contour_style_registry_smoke_test.gd
$env:GODOT4 --headless --path . --script res://tools/mountain_contour_runtime_l1_smoke_test.gd
$env:GODOT4 --headless --path . --script res://tools/mountain_contour_mining_dirty_smoke_test.gd
$env:GODOT4 --headless --path . --script res://tools/mountain_contour_runtime_perf_probe.gd

# Diff hygiene
git diff --check
```

---

## Cutover Rule

Do not cut over live mountain rendering until all of these are true:

- [ ] style loader passes
- [ ] native runtime contour result passes
- [ ] visual probe passes
- [ ] collision probe passes
- [ ] mining dirty update passes
- [ ] movement cutover passes
- [ ] building placement cutover passes or is explicitly deferred with mountain blocking still safe
- [ ] parity probe passes with documented tolerances
- [ ] perf probe passes latency limits

After cutover, square mountain TileMap rendering and square movement fallback are not allowed to remain hidden underneath the contour layer.

---

## Follow-Up Plans After Mountain V2

These are intentionally not part of the first implementation plan:

- `Ground Contour Runtime V1` for `PLAINS_GROUND` / `PLAINS_DUG`.
- `Shoreline Contour Runtime V1` for lake/river banks.
- Biome-specific mountain styles and rock strata.
- Multi-style runtime selection by biome/ore/mountain id.
- Full navigation/pathfinding over contour geometry if current movement needs it.
