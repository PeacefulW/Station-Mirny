---
title: World Dynamic Lighting 2D — Sun, Torch, Ambient
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.5
last_updated: 2026-07-11
related_docs:
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - cloud_occlusion_lighting.md
  - plains_ground_cosmetic_shading.md
  - ../progression/player_sun_shadow_v0.md
---

# World Dynamic Lighting 2D — Sun, Torch, Ambient

## Purpose

Introduce **real Godot 2D lighting** (`CanvasModulate` ambient + `DirectionalLight2D`
sun + `PointLight2D` torch/lamps) so that:
- terrain `NORMAL_MAP` finally produces volume (pebbles/pits relief) under a moving
  sun, and
- a player-carried torch lights the world dynamically (warm pool in the dark) — the
  core "inside-safe / outside-hostile" atmosphere.

This is the **visual** half of the ADR-0005 light system.

## ADR-0005 boundary (non-negotiable)

[ADR-0005](../../05_adrs/0005-light-is-gameplay-system.md): light is a **gameplay**
system; gameplay reads a light/visibility **authority**, not the renderer. This spec
builds only the **visual illumination** (light/normal shading + torch glow). The
gameplay visibility authority (fauna AI, stress, sanctuary truth) is **separate and
NOT derived from these Light2D nodes** — noted here, not built here. No system may
query the renderer/lights for gameplay visibility.

## Cloud Occlusion Boundary

[`cloud_occlusion_lighting.md`](cloud_occlusion_lighting.md) now rides this
visual sun: `WeatherRuntime.get_cloud_occlusion()` lowers the `DirectionalLight2D`
direct-sun energy and cools the `CanvasModulate` ambient in open-sky context.
`CloudOccluderField` adds a bounded world-space shader cloud-shadow layer for
the top-down renderer; it intentionally does not use `LightOccluder2D` because
the project already proved Godot 2D occluder shadows project to screen-edge
infinity in this camera model **for a directional light** (clouds ride the sun).
That infinity artifact is directional-only: a **point** light (the torch) casts
correctly bounded radial occluder shadows here — the first landed torch-vs-mountain
occlusion (2026-07-04) used `LightOccluder2D` on that basis. That engine-occluder
path is now being **retired** (see Iteration 2 below): rebuilding the occluder
geometry from the solid mask on every dig spiked the main thread and left
tile-quantized square shadow bands. Its replacement is a world-space shader
ground-occlusion field, the same family of renderer this cloud field already is.
Cloud occlusion still does not use subtractive `PointLight2D`
blobs because render probes proved they do not darken this ground. This replaces
the old screen-space cloud darkening / flatten / sun-ray overlays. It is still
presentation-only: cloud response does **not** make `Light2D` nodes a gameplay
authority, and gameplay systems still must not read the renderer for visibility
(ADR-0005).

## Validation (done)

Dev probe `tools/ground_light_probe.gd` (not a runtime path) confirmed on the live
world scene: shaders are light-aware (not `unshaded`), the torch `PointLight2D` pool
reads in a dark ambient, and `DirectionalLight2D` lights the ground. Captures in
`artifacts/ground_light_probe/`.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical data, overlay, or visual only? | Visual illumination only. |
| Save/load? | No. |
| Deterministic? | Lighting is presentation; sun model from time-of-day, torch from player. |
| C++ or main thread? | Engine 2D lighting (GPU) + a few light nodes on the main thread. |
| Single owner | Sun/ambient driven by the daylight/`WorldVisualLightingProfile` model; torch owned by the player. |
| 10x/100x | Lights without shadows are cheap; the Iter 2 torch shadow is a GPU shader field bounded by the torch pool + a bounded per-dig mask-window blit — independent of world size. |
| Hidden fallback? | No. |
| Gameplay coupling | NONE — visual only; gameplay visibility authority is a separate later contract. |

## Scope

### Iteration 1 — Lights + normal relief (no cast shadows)
- Rework the existing `DaylightSystem` `CanvasModulate` to be the **ambient floor**
  (lower values: bright-ish day, dark night) instead of a near-full tint.
- Add a `DirectionalLight2D` **sun**: angle/energy/colour driven by the same
  time-of-day model (`WorldVisualLightingProfile`), so terrain normals get relief
  that shifts with the day.
- Add a `PointLight2D` **torch** on the player (warm, ranged), `shadow_enabled=false`
  → moving pool of light + local normal relief at night.
- Reconcile with the existing in-shader cosmetic ground shade (reduce/disable the
  baked directional term once the real sun does directional shading — avoid
  double-darkening). Baked sprite shading (rocks/trees) stays as-is (they have no
  NORMAL_MAP; lights modulate them flatly).
- Depends on quality terrain normal maps (authored externally) for the relief payoff.

### Iteration 2 — Cast shadows

Two owners, deliberately split:
- **Mountain SPRITE lighting = shader-gated point-light pass (kept, unchanged).**
  The large `mountain_top_mask_underlay.gdshader` sprite does **not** consume any
  engine occluder shadow texture as its final shape. Its `light()` pass accepts
  point lights only through the smoothed wall/facade mask (`point_light_facade_accept`
  = `wall_mask`); roof/deep rock behind the silhouette receives no point-light
  contribution, so the visible FACADE catches warm torch light while the top/roof
  stays dark. The runtime mountain visual mask is kept at 8 samples/tile
  (`step_px = 8 px`); 4 samples/tile exposed the mask texel grid as stair steps.
  Excavated BASE and construction-roof reveal sample visual remaining mass `V`,
  not gameplay `mask`/`S`: `V` preserves the organic room contour and its
  straight continuation-aware physical mouths while `S` may be fully clear over
  a mined source tile. A separate tiny physical-mouth selector keeps the same
  aperture SDF when active-floor value `255` replaces direction bits in the
  combined roof selector.
  This owner draws the facade-vs-roof look and base facade lighting; it is **not**
  changed by the redesign. It does **not** know occlusion, so a facade the torch cannot
  see (around a corner / behind a spur) is still drawn lit here — the field below
  composites the occlusion darkening over both ground and facade so that facade falls
  dark. The sprite lights, the field occludes.
- **Ground / facade occlusion = world-space shader field (mask-march). REDESIGN,
  supersedes the first landed engine-occluder path.**

  *First landed path (2026-07-04), now being retired.* The torch set
  `shadow_enabled=true` and was occluded on ground receivers by `LightOccluder2D`
  nodes that `ChunkView` rebuilt from the mountain solid mask (facade-inset open
  contour polylines, proximity-bounded, rebuilt on every dig). Two defects forced
  the redesign: (1) **main-thread spike on digging** — the per-dig rebuild scanned
  the whole chunk mask, traced contours with a superlinear string-keyed edge walk,
  Chaikin-smoothed, and churned dozens–hundreds of `LightOccluder2D` nodes, reaching
  tens–hundreds of ms with no frame budget (ADR-0001 violation on an interactive
  path); (2) **square/step artifacts** — the binary occluder geometry is orthogonal,
  so the ground shadow showed tile-quantized square bands above the facade that PCF
  blur could not hide.

  *Replacement (this spec).* A single view-bounded world-space shader field
  (`MountainTorchShadowField extends WorldViewOverlay`, shader
  `assets/shaders/mountain_torch_shadow_field.gdshader`, `blend_mix, unshaded`,
  `z_index = Z_MOUNTAIN_PAGE (19)` so it darkens ground but stays under the object
  ladder). For each ground fragment inside the torch pool it marches a straight line
  toward the torch through the **stitched mountain solid mask** and darkens the
  fragment (mixes toward night) when solid rock lies on that line — the dug pocket
  floor / corridor around a corner stays dark; a corner casts a shadow onto open
  ground. Key properties:
  - **No CPU geometry rebuild on digging.** The solid mask is already uploaded for
    the mountain sprite; the field only samples a texture on the GPU. Digging just
    changes the mask (existing path). This removes the whole occluder-rebuild spike.
  - **No square bands.** The march samples the **smoothed** mask (`mask_to_top`-style
    smoothstep), so the shadow edge follows the silhouette, not the mask grid.
  - **`blend_mix`, not `blend_mul`.** A multiply pass under the Daylight
    `CanvasModulate` would have its white "no-op" multiplier tinted dark by night and
    would darken all ground; with `blend_mix`, `alpha == 0` outside the shadow is a
    true no-op at any ambient. Mirrors `CloudOccluderField`.
  - **Darkens open ground AND occluded facade; roof left to the sprite.** Open ground
    is darkened by its own line of sight to the torch. A **facade** fragment (solid
    within `facade_height_px` of an open south foot) is darkened by the line of sight
    from its **foot** to the torch, so the floor shadow climbs the wall and a facade
    around a corner falls dark like the floor below it — the facade must not stay lit
    where the torch cannot see it (user render feedback 2026-07-05). Deep **roof** (no
    open foot within `facade_height_px`) is left alone: the sprite already draws it dark
    and the field only darkens, never lightens. The field must composite ABOVE the
    mountain sprite (same `z`, later in tree order) yet below the object ladder (≥20)
    so torch-lit objects standing in shadow are not dimmed.
  - **Facade material under torch.** The facade shader must not use quantized
    `wall_depth` tonal bands (`cut_highlight` / cleft / top-rim style layers): the
    runtime mask is 8 px/sample, so those bands read as ribbed contour stripes when
    the torch hits the wall. The live mountain material also keeps concentric
    `terrace_strength` disabled under torch-lit runtime presentation: those
    distance-to-edge terraces follow the same contour and read as facade ribs once a
    warm point light hits the wall. The live material keeps `face_texture_scale >= 1.0`
    so the face albedo is not stretched into a blurry smear.
  - **Facade foot search quality.** The shadow field ray-marches blockers at an
    8 px world step, but facade foot lookup uses a dedicated fine step with
    interpolated crossing and a small open-ground bias. Facade fragments first push
    their origin along the smoothed solid-mask contour normal, with the old southward
    foot search as fallback; this avoids near-wall "comb" teeth when the torch stands
    close to an irregular or vertical mountain edge.
  - **Stitched mask source.** The field texture around the player is composited from
    the cross-chunk `mountain_solid_halo` (`WorldStreamer._get_cached_mountain_solid_halo`,
    radius-8 halo, 512 px skirt); a torch straddling a chunk seam unions the 2×2
    (up to 3×3) block of overlapping halos, which agree tile-for-tile in the overlap.
    **Dirty unit:** the stitched field window around the torch, snapped to a 256 px
    world grid and rebuilt on mountain mask-revision bump (dig) or snapped-window
    movement — bounded and cached, not a per-frame geometry rebuild. The stitched
    window is composed by row-blitting each ready native-mask chunk rect into the
    field mask; do not return to per-sample `world_to_tile` / dictionary lookup in
    the compose loop, which caused movement hitches with the torch enabled.
  - **Construction-roof compatibility.** Outside a cavity the shadow field uses
    immutable closed mass `C`. Inside, raw binary component halo `R` (production
    bytes are `1`, not GPU-normalized `255`) selects visual remaining mass `V`
    plus its bounded torch-only support ring. Therefore torch blockers follow
    the same organic contour that is rendered, a retained solid island in
    the cave remains an occluder, while the dug mouth is open and lets the radial
    torch pool continue onto exterior ground. This selection is derived lighting
    data only: it does not alter gameplay `S`, excavation, collision, resolver,
    or roof reveal.
  - **Retire list (engine-occluder path) — completed 2026-07-05.**
    - `player_torch.gd`: `shadow_enabled` / `shadow_filter` / `shadow_filter_smooth` /
      `shadow_item_cull_mask` and the `MOUNTAIN_OCCLUDER_LIGHT_LAYER` constant.
    - `chunk_view.gd`: **all** `mountain_light_occluder`/`mountain_occluder` symbols —
      public **and** private. Public seam to the streamer:
      `set_mountain_light_occluders_enabled`, `sync_mountain_light_occluders`,
      `mark_mountain_light_occluders_dirty`, `get_mountain_light_occluder_debug_state`;
      private: `_rebuild_/_ensure_/_clear_mountain_light_occluders`, the
      `_trace_/_simplify_/_smooth_/_add_mountain_occluder_*` helpers, and the
      `_mountain_light_occluders_enabled` / `_mountain_light_occluders_dirty` state
      (plus the `mark_mountain_light_occluders_dirty()` call in the mask-upload path).
    - `world_streamer.gd`: `_update_mountain_light_occluders` and its call in
      `_update_player_chunk_coord`, plus the occluder center/radius state.
    - `tools/mountain_torch_occluder_shape_smoke_test.gd`: only the old
      occluder-shape assertions and `_build_debug_for_mask` helper were removed; the
      kept mountain-SPRITE checks (`_assert_mountain_shader_gates_point_lights`,
      `_assert_mountain_mask_runtime_resolution`) still guard facade point-light gate
      and 8 px/tile runtime masks.
  - **History (point vs directional).** The project found `LightOccluder2D` shadows
    project to screen-edge infinity here for a **directional** light; a point torch
    was bounded. That finding justified the first engine path; the redesign drops
    engine occluders entirely for the ground, so the sun's reserved shadow-cull layer
    (`1<<8`) is the only remaining engine-occluder concern.
- **Object occluders (trees, big rocks) — deferred.** Same engine mechanism can
  extend to significant near-player objects later; not built here.
- `shadow_enabled` on the sun (long day shadows) remains the directional path
  (its own projected-shadow shader), not these occluders.

## Out of Scope
- Gameplay visibility authority (fauna/stress/sanctuary) — separate ADR-0005 contract.
- Occluders on mass decor.
- Save/EventBus/packet/command changes.

## Performance Class
- Iter 1: a `DirectionalLight2D` + one `PointLight2D`, no shadows → cheap GPU.
- Iter 2 (redesign): the torch ground shadow is a GPU shader field — per-fragment
  mask-march bounded by the torch pool (× a small constant step count), plus a
  bounded main-thread blit of the stitched solid mask window on dig / snapped-window
  movement. The per-frame CPU path is a cached signature check; there is no per-dig
  geometry rebuild. The retired engine-occluder path
  had an unbounded interactive CPU rebuild (the defect this redesign removes).

## Integration Risks
- **Project-wide look change:** the `CanvasModulate` rebalance re-lights the entire
  world. Validate in the probe before promoting to `world_runtime_v0.tscn`.
- **Double-darkening:** the in-shader cosmetic ground shade + real sun can compound;
  reduce the shader term in Iter 1.
- **Relief depends on normals:** weak terrain normals = little volume; the payoff
  needs the authored Blender normal maps.
- **CanvasModulate × Light2D interplay:** ambient floor must be low enough that the
  sun/torch read, high enough that unlit areas aren't pure black (except intended night).
- **Torch field — stitched window must cover the torch pool.** The march treats any
  sample outside the loaded mask window as open, so a ray whose blocker sits just past
  the window edge leaks light. The stitched window around the player must exceed the
  torch pool radius with margin (one chunk's radius-8 halo skirt is 512 px vs a ~563 px
  pool, so the live field must union the neighbour halos, not rely on a single chunk).
- **Torch field — march step is a cost/reliability/edge knob.** The world-constant
  `march_step_px` must stay below the thinnest dug wall (1 tile = 64 px) or a thin rib
  leaks light; the live pass uses 8 px / 80 max samples so the pool remains covered.
  Segment-center sampling and a terminal `segment_weight` fade prevent new samples
  from appearing as hard concentric bands while the torch or fragment distance changes.
  Soft edge quality is a **penumbra** concern, tuned in the live pass — not a shape
  defect (the shadow already follows the silhouette, unlike the retired rectangular
  occluders).

## Acceptance Criteria
- [ ] `DaylightSystem` drives an ambient floor; a `DirectionalLight2D` sun + player
      `PointLight2D` torch exist and follow the time-of-day / player.
- [ ] Render probe: terrain normal relief visible under sun (with good normals); torch
      pool + relief follows the player at night; day/night reads via ambient+sun
      (manual human verification).
- [ ] No double-darkening vs the cosmetic shade (static read + probe).
- [ ] No gameplay system reads the lights (static read); no save/packet/command/event
      change; no `WORLD_VERSION` bump.
- [x] **Torch shadow field:** render probe shows the dug pocket / corridor lit where
      the torch has straight line-of-sight and dark around a corner / behind a wall,
      with an organic silhouette edge and **no tile-quantized square bands** (manual
      human verification of `tools/mountain_torch_shadow_field_probe.gd`; numeric:
      `occluded_luma` drops with the field on, `lit_luma` holds, `rock_luma` unchanged).
- [x] **Torch shadow field:** the mountain sprite facade stays torch-lit where the
      torch has line-of-sight, occluded facade darkens by testing line-of-sight from
      its south foot, and roof/top stays dark (unchanged sprite owner).
- [x] **Cave island and mouth:** a retained solid island casts onto open interior
      floor, clear interior LOS remains lit, the straight mouth passes torch light
      to exterior ground, and adjacent exterior ground behind the lip stays dark
      (`tools/mountain_torch_shadow_cave_island_probe.gd`).
- [x] **No dig spike:** the torch ground shadow adds no per-dig main-thread geometry
      rebuild; on retiring the engine path, `_rebuild_mountain_light_occluders` and the
      `_mountain_light_occluder_*` machinery are gone (static read).

## Implementation Iterations
1. Lights + ambient rebalance + normal relief. **Status: landed 2026-06-24.**
   `DaylightSystem` rebalanced to ambient floors + creates/drives a
   `DirectionalLight2D` sun (energy from ambient phase brightness, angle from
   `WorldVisualLightingProfile` by hour, off underground). Player gains a `Torch`
   `PointLight2D` (`player_torch.gd`, self-generated radial texture, no occluder
   shadows). In-shader cosmetic `shade_dir_strength` reduced 0.16→0.06 to avoid
   double-darkening. Verified via render probe (day in the live scene; night+torch
   via `tools/ground_light_probe.gd`). Relief payoff pending authored terrain normals.
   **Rebalanced after first feedback (over-bright):** day ambient stays familiar
   (~0.85) with a *gentle* sun key (`SUN_DAY_ENERGY` 1.25→0.45); **night is near-black**
   (`COLOR_NIGHT ≈ 0.03` — zero visibility without a light source, by design; additive
   spores/fireflies and the torch stay visible). Torch is **off by default with a dev
   on/off toggle (key F)**, lower energy/range (0.9 / 2.2) so it no longer washes the
   day. Probe captures: day-natural / night-pitch-black / night-torch-pool.
   **Cloud occlusion update landed 2026-06-25:** open-sky cloud occlusion now
   multiplies the real `SunLight2D` direct key and cools/dims the ambient floor;
   the old screen-space cloud darkening, flatten, and sun-ray overlays are no
   longer part of the live scene.
2. Torch vs mountain — engine `LightOccluder2D` path. **Landed 2026-07-04, retired
   2026-07-05.** `player_torch.gd` enabled `shadow_enabled` + PCF13
   culled to the occluder layer; `ChunkView` rebuilt facade-inset open contour
   `LightOccluder2D` geometry from the mountain solid mask on every mask-upload /
   dig; `WorldStreamer._update_mountain_light_occluders` enabled + synced it near the
   player. **Defects:** the per-dig rebuild spiked the main thread (whole-chunk mask
   scan + superlinear string-keyed contour trace + node churn, unbudgeted — ADR-0001
   violation) and the orthogonal occluder geometry left square/step shadow bands. The
   mountain SPRITE's shader-gated facade lighting (kept) is separate and correct.
2b. Torch vs mountain — **shader ground/facade occlusion field (REDESIGN, current).**
   `MountainTorchShadowField extends WorldViewOverlay` +
   `assets/shaders/mountain_torch_shadow_field.gdshader` (`blend_mix, unshaded`,
   `z = Z_MOUNTAIN_PAGE`), per-fragment mask-march toward the torch through the
   stitched native mountain mask; open ground uses its own line-of-sight, facade uses
   line-of-sight from its south foot, roof is skipped. Dirty unit = the snapped
   stitched mask window around the torch (dig / snapped-window movement).
   **Status: landed 2026-07-05.** Live node is wired into `world_runtime_v0.tscn`;
   `PlayerTorch` is back to `shadow_enabled=false`; `ChunkView`/`WorldStreamer`
   no longer own torch mountain `LightOccluder2D` geometry. Verified by:
   `tools/mountain_torch_shadow_field_static_smoke_test.gd`,
   `tools/mountain_torch_occluder_shape_smoke_test.gd`,
   `tools/mountain_torch_shadow_field_probe.gd` (windowed numeric proof:
   `facade_dark` 0.0899→0.0132, `floor_dark` 0.1056→0.0160, lit/roof samples held).
   **Perf follow-up 2026-07-05:** live movement probe found the original GDScript
   stitched-mask compose spiking to ~275 ms. The live path now row-blits chunk rects
   from ready native masks and snaps the window at 256 px; the same probe reduced
   shadow-mask CPU max to ~10-12 ms in an aggressive movement sweep, with most frames
   cache hits.
   **Construction-roof correction 2026-07-11:** component selection now accepts
   the real nonzero binary `R` bytes instead of looking specifically for `255`;
   focused CPU and windowed cave-island probes cover the regression.
   **Visual-contour correction 2026-07-11:** selected cave chunks now blit `V`,
   not gameplay `mask`/`S`, so torch shadows match the visible organic rooms and
   straight physical mouths while collision keeps its full dug-tile clearance.
   Object occluders (trees/rocks) and any sun occluder path remain unstarted.
3. (Later, separate) gameplay visibility authority per ADR-0005.

## Required Updates
- `docs/02_system_specs/README.md` — index entry (added with this draft).
- On promote: reconcile `plains_ground_cosmetic_shading.md` (the in-shader directional
  shade becomes redundant once the real sun lights normals).
- If a public light/visibility authority API appears later, update
  `system_api.md` in that authority iteration.
