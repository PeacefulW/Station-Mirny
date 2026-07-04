---
title: World Dynamic Lighting 2D — Sun, Torch, Ambient
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.2
last_updated: 2026-07-05
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
correctly bounded radial occluder shadows here (Iteration 2, landed 2026-07-04),
which is why torch-vs-mountain occlusion does use `LightOccluder2D`. Cloud
occlusion still does not use subtractive `PointLight2D`
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
| 10x/100x | Lights without shadows are cheap; occluder shadows (Iter 2) are bounded by proximity. |
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

### Iteration 2 — Cast shadows (occluders)
- **Torch vs mountain geometry (landed 2026-07-04).** The player torch
  (`PointLight2D`) now sets `shadow_enabled=true` and is occluded on
  ground/open-terrain receivers by
  `LightOccluder2D` nodes that `ChunkView` builds from each chunk's mountain solid
  mask as facade-inset open contour polylines (proximity-bounded to the player's
  chunk ±1, LAW 13; rebuilt when the mask changes on digging). So torch light is blocked by
  mountain walls on the walkable/open world, does not bend around corners, and follows what the player has
  excavated — the "inside a dug pocket is lit, the rock beyond the walls stays
  dark" fantasy (ADR-0005 category 5, underground = earned light).
  - **Mountain sprite lighting = shader-gated point-light pass.**
    The large `mountain_top_mask_underlay.gdshader` sprite does **not** consume
    the engine occluder shadow texture as its final shape. Render feedback showed
    that even open contour occluders create visible line/square bands when their
    binary shadow map is applied over the mountain sprite. Instead, the shader's
    `light()` pass accepts point lights only through the smoothed wall/facade mask;
    roof/deep rock behind the contour receives no point-light contribution. The
    runtime mountain visual mask is kept at 8 samples/tile (`step_px = 8 px`);
    4 samples/tile (`step_px = 16 px`) exposed the mask texel grid as stair steps
    on uneven torch-lit facades. This keeps the torch pool smooth like the ground
    while still letting the facade catch warm light.
  - **Ground/open-terrain occluder geometry = open contour, facade-inset, not filled cells.**
    Occluders are open `OccluderPolygon2D` contour segments extracted from the
    facade-inset solid mask, then lightly smoothed so the torch shadow does not
    expose raw orthogonal mask-grid corners on uneven walls. The inset mirrors
    `facade_height_px` (72 px, material set), so the visible wall FACE/facade
    remains separate from the roof/deep rock blocker.
    Filled/horizontally run-merged mask-cell quads are explicitly rejected: they
    cast one rectangular shadow slab per mask row/cell run, which shows up as
    translucent square/step bands around the torch edge. PCF blur
    (`shadow_filter_smooth = 9`) is only final edge softening; it must not be
    relied on to hide rectangular occluder geometry.
    Structural smoke: `tools/mountain_torch_occluder_shape_smoke_test.gd` asserts
    that mountain torch occluders are open contour segments, not closed filled
    rect quads.
  - **Point light ≠ directional light (key finding).** The project earlier found
    `LightOccluder2D` shadows project to screen-edge infinity in this camera —
    but that is a **directional** (sun/cloud) artifact. A render-proof spike
    confirmed a **point** torch casts correctly bounded, radial occluder shadows
    here. Occluder/light layer separation keeps this scoped: mountain occluders
    use `occluder_light_mask = 1` and the torch uses that as its
    `shadow_item_cull_mask`; the sun's shadow cull is a separate reserved layer
    (`1<<8`), so the sun never casts (infinity-prone) shadows from these occluders.
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
- Iter 2: shadow maps scale with lights × in-range occluders; keep occluders
  proximity-bounded. Background/visual; no interactive CPU path.

## Integration Risks
- **Project-wide look change:** the `CanvasModulate` rebalance re-lights the entire
  world. Validate in the probe before promoting to `world_runtime_v0.tscn`.
- **Double-darkening:** the in-shader cosmetic ground shade + real sun can compound;
  reduce the shader term in Iter 1.
- **Relief depends on normals:** weak terrain normals = little volume; the payoff
  needs the authored Blender normal maps.
- **CanvasModulate × Light2D interplay:** ambient floor must be low enough that the
  sun/torch read, high enough that unlit areas aren't pure black (except intended night).

## Acceptance Criteria
- [ ] `DaylightSystem` drives an ambient floor; a `DirectionalLight2D` sun + player
      `PointLight2D` torch exist and follow the time-of-day / player.
- [ ] Render probe: terrain normal relief visible under sun (with good normals); torch
      pool + relief follows the player at night; day/night reads via ambient+sun
      (manual human verification).
- [ ] No double-darkening vs the cosmetic shade (static read + probe).
- [ ] No gameplay system reads the lights (static read); no save/packet/command/event
      change; no `WORLD_VERSION` bump.

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
2. Occluder cast shadows, proximity-bounded. **Torch vs mountain: landed
   2026-07-04.** `player_torch.gd` enables `shadow_enabled` + PCF13 and culls to
   the mountain occluder layer; `ChunkView` builds/rebuilds facade-inset open
   contour `LightOccluder2D` geometry from the mountain solid mask on the
   mask-upload and dig-patch paths; `WorldStreamer._update_mountain_light_occluders`
   enables occluders only for the player's chunk ±1 and syncs dirty chunks per
   tick. The mountain mask shader gates point-light contribution to facade pixels
   instead of consuming the engine shadow texture on the large mountain sprite.
   Filled/run-merged rect occluders and direct engine-shadow application on the
   mountain sprite were rejected after visual feedback: they block light but leave
   visible rectangular/linear torch-shadow bands. Object occluders (trees/rocks)
   and any sun occluder path remain unstarted.
3. (Later, separate) gameplay visibility authority per ADR-0005.

## Required Updates
- `docs/02_system_specs/README.md` — index entry (added with this draft).
- On promote: reconcile `plains_ground_cosmetic_shading.md` (the in-shader directional
  shade becomes redundant once the real sun lights normals).
- If a public light/visibility authority API appears later, update
  `system_api.md` in that authority iteration.
