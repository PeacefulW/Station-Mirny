---
title: Cloud Occlusion & Overcast Darkness
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.1
last_updated: 2026-07-11
related_docs:
  - weather_runtime.md
  - world_dynamic_lighting_2d.md
  - ../meta/system_api.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Cloud Occlusion & Overcast Darkness

## Purpose

Replace the screen-space cloud presentation (a darkening overlay +
`OvercastFlattenOverlay` + `SunRayOverlay`) with one physically honest model:
**cloud cover occludes the real sun** (`DirectionalLight2D`), producing real
drifting shadows and, at full cover, real overcast darkness — because the direct
light is genuinely blocked. One authoritative cloud-occlusion model feeds the
renderer now and reserves the future ADR-0005 gameplay visibility seam.

This supersedes the Iteration 2b cloud presentation in `weather_runtime.md`
(the `broken`/`deck`/`flatten`/`sun_ray` response curves and their three
overlays). The cloud-cover *state* and its owner (`WeatherRuntime`) are
unchanged; only how cover is turned into light changes.

## The physical model (one field, two engine knobs)

Sunlight reaching the ground is two components:

- **Direct beam** — the warm, hard light from the sun's disc; it casts shadows.
  In the engine this is the `DirectionalLight2D` sun (`world_dynamic_lighting_2d.md`).
- **Diffuse sky** — light scattered across the whole sky dome; cool, dim, flat,
  shadowless. In the engine this is the `CanvasModulate` ambient floor.

A cloud **blocks the direct beam**; that patch of ground is then lit by diffuse
sky only → cooler and dimmer. That patch *is* the shadow. "The sun dims and
cools" and "the sun is blocked by clouds" are the **same event**: removing the
warm direct beam leaves only the cool diffuse sky.

Cloud cover is therefore one question: **what fraction of the direct beam is
blocked at this point?**

- low coverage → blocked in patches → drifting shadows, warm direct sun between;
- 100% coverage → blocked everywhere → the whole surface on diffuse sky only →
  uniform cool, dim, flat overcast.

The global overcast darkness and the spatial moving shadows are the *same*
phenomenon at different coverage. `DirectionalLight2D` has **no spatial cookie**
in Godot, so this one process is realized with **two knobs**:

1. **Global** — cloud cover drives the sun's `DirectionalLight2D` energy down and
   nudges the ambient toward cool-grey as cover rises (overcast darkening).
2. **Spatial** — `CloudOccluderField` draws moving finite shadow patches with a
   world-space shader layer. The original `LightOccluder2D` plan is rejected for
   the live top-down renderer because prior local evidence showed Godot 2D
   occluder shadows project to screen-edge infinity; the subtractive
   `PointLight2D` blob fallback was also tried and proved not to darken this
   CanvasModulate/normal-mapped plains ground.

## Gameplay Goal

Plains weather reads as real sky over a real world. Scattered clouds throw cool,
drifting shadows across warm sunlit ground; as cover grows the shadows enlarge
and merge; at full overcast the sun is genuinely blocked and the open surface
goes cool and dark — while the campfire/torch stay warm islands of safety. A
stormy daytime outside is meaningfully darker and more dangerous (ADR-0005,
category "severe weather = darkness even in day").

## Scope

- A drifting **cloud-occlusion scalar/cover read**, owned by `WeatherRuntime`
  (extends the existing `cloud_cover` read, same slow state), plus a derived
  view-local visual placement field inside `CloudOccluderField`.
- A **global sun response** in `DaylightSystem`: cloud occlusion lowers the
  `DirectionalLight2D` energy and cools the ambient (surface only).
- A **`CloudOccluderField`**: one view-bounded world-space shader shadow layer;
  field patches grow/merge with cover.
- A reserved seam for a future **`EnvironmentVisibilityAuthority`**. It is not
  part of the approved active V0 implementation; see the deferred iteration.
- Retire the three old overlays.

## Approval Closure

Approved on 2026-06-29 for the active V0 slice: `WeatherRuntime`
`get_cloud_occlusion()`, `DaylightSystem` sun/ambient response,
`CloudOccluderField`, night fade, dev cover controls, and removal of the old
screen-space cloud overlays. `EnvironmentVisibilityAuthority` remains deferred
until a first gameplay consumer exists.

## Out of Scope

- Visible cloud *bodies* overhead (shadows on the ground only — chosen).
- Full ADR-0005 gameplay light authority (per-tile light grid, torches as
  gameplay light), including `EnvironmentVisibilityAuthority` and
  `get_open_surface_light_level()`. A larger authority graduates to its own ADR.
- Cloud shadow patches on anything other than the cloud field.
- New save state (cover already persists via weather Iteration 3) or
  `WORLD_VERSION` change.
- Precipitation, lightning, second biome.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical data, overlay, or visual only? | Cloud-occlusion model is environment-runtime state (derived from weather, ADR-0007 layers 2/3); sun response + shader shadow layer are presentation (layer 4). The gameplay visibility authority is reserved, not active in approved V0. No worldgen/terrain truth. |
| Save/load? | No new state. Cover persists via weather slow state; everything here derives. |
| Deterministic? | Field is a pure function of world/view pos + accumulated wind drift; cover changes threshold/softness/opacity, not the sampled coordinates. The global scalar is a pure function of cover. |
| Must it work on unloaded chunks? | Weather is global; shader layer/authority are view/position-local and need no chunk data. |
| C++ or main thread? | One world-space shader layer + a few scalar writes on the main thread. No native, no heavy loops. |
| Dirty unit | The global weather state (cover) + the current view shader uniforms. |
| Single owner | Scalar/cover: `WeatherRuntime`. Sun response: `DaylightSystem`. Spatial shader layer: `CloudOccluderField`. Future gameplay scalar: deferred `EnvironmentVisibilityAuthority`. |
| 10x/100x | Cost is independent of world size; the layer is one view-bounded pass. |
| Hidden fallback? | None. If the sun light or weather owner is missing, fail explicitly. |
| Gameplay coupling | Not active in approved V0. Future gameplay must read an authority, never the `Light2D` nodes (ADR-0005). |

## Data Model

### Cloud occlusion (owned by `WeatherRuntime`)

The existing `get_cloud_cover()` stays. Iteration 1 adds exactly one new public
read:

- `get_cloud_occlusion()` → `[0,1]`: global fraction of direct sun blocked,
  `O(cover)` — rises with cover, saturating toward `1` at full overcast. Pure
  function of cover (tuning anchors below).

The drifting visual field is a presentation function of view/world position +
accumulated wind drift. Cover changes the field threshold, edge softness, and
opacity so shadows enlarge and merge without resampling the underlying
coordinates. This avoids apparent reverse motion during clearing/cover changes.
It is read only by `CloudOccluderField`; it is not stored.
Iteration 3 does **not** add a public field sampler because the renderer derives
placement from `get_cloud_cover()`, `get_cloud_occlusion()`, and `WindRuntime`
presentation reads.

Field descriptor reads are **not** part of Iteration 1. If a later iteration
needs a cross-owner field descriptor or sampler for `CloudOccluderField`, that
iteration must add typed/read-only `WeatherRuntime` reads and document them in
`system_api.md` in the same change. Do not expose a raw `Dictionary` boundary
for this field.

Tuning anchors (finalized by render probe; aligned to regime cover bands clear
`[0,0.15]`, cloudy `[0.35,0.62]`, overcast `[0.72,1.0]`):

- `O(cover) ≈ smoothstep(0.10, 0.95, cover)` — near `0` at clear, near `1` at
  overcast; this is what dims the global sun.
- field coverage/softness ≈ rises across the same range so cloudy = scattered
  patches, overcast = merged sheet; the sampled cloud coordinates stay stable.

### No new persisted state

Cover persists via weather Iteration 3 (`weather.json`). Occlusion, spatial
shader state, and the visibility scalar all derive on load.

## Runtime Architecture

### Owners

| Concern | Owner |
|---|---|
| Cloud occlusion scalar + cover | `WeatherRuntime` (getters) |
| Sun energy/colour + ambient cool-shift response | `DaylightSystem` |
| Spatial moving shadows (shader layer) | `CloudOccluderField` (new) |
| Future open-surface darkness for gameplay | Deferred `EnvironmentVisibilityAuthority` |

### Global sun response (`DaylightSystem`)

`DaylightSystem` already owns the `DirectionalLight2D` sun (energy from the
day phase, fixed north-west azimuth from `WorldVisualLightingProfile`, off
underground). It reads `WeatherRuntime`
occlusion and, **only in the current open-sky context**:

- scales sun energy by `(1 − k · O(cover))` so overcast nearly extinguishes the
  direct key (the world falls to the ambient floor);
- shifts the ambient toward a cool desaturated grey as `O` rises (the diffuse
  overcast sky), reusing the existing cold-tint idea but now physically as "only
  diffuse sky remains".

Clear cover leaves the sun unchanged. Underground is already sunless. A roofed/
interior surface context is treated as no-open-sky (no cloud darkening). The
Iteration 2 implementation uses the existing coarse current-context reads
(`PlayerAuthority`, `BuildingSystem.is_cell_indoor()`, and
`WorldStreamer.get_mountain_cover_sample()`) because `CanvasModulate` is a
viewport-wide ambient floor; mixed inside/outside per-tile light authority is
still Iteration 4+ ADR-0005 work.

### Spatial moving shadows (`CloudOccluderField`)

One **view-bounded world-space shader layer** samples a drifting cloud density
field across the current view and blends dense patches toward a cold dark
diffuse-sky colour. This is the Iteration 3 renderer chosen after two failed
engine-light paths: Godot `LightOccluder2D` projects to screen-edge infinity in
top-down, and subtractive `PointLight2D` blobs do not darken this ground. Per
frame the layer updates only shader uniforms inherited from `WorldViewOverlay`
(LAW 1/ADR-0001: no per-frame full rebuilds). Drift uses the integrated
`WindRuntime.wind_gust_scroll_px` global so direction changes do not reproject
old `wind_time` along a new heading. Cover drives coverage, softness, and
strength; overlap/field density = merged shade.

- Empty/disabled near clear cover (`O ≈ 0`).
- As `O → 1` (overcast) the **global** sun-energy drop already darkens
  everything, so the shader layer fades out to avoid double-darkening
  (the two knobs hand off; never double-count to pure black unintentionally).
- No `LightOccluder2D` or subtractive `PointLight2D` cloud children are used in
  the live top-down path. The layer is open-sky gated like `DaylightSystem`
  (surface + not roofed + not mountain interior). Torch/lamp/campfire
  `PointLight2D` nodes are not used as cloud-shadow inputs. This is the
  sanctuary guarantee (below).

**Night fade (a shadow needs a sun).** A cloud shadow only exists while there is
a direct sun to block, so the shader layer opacity is multiplied by a
**sun-presence** factor (`0` at night .. `1` at midday) read from
`DaylightSystem.get_sun_day_factor()` (day-cycle brightness, independent of cloud
cover). At night the spatial shadows fade fully out; at dawn they fade back in.
The cloud **state** (cover) is unaffected, so an overnight-overcast sky reads as
overcast at sunrise: as the sun rises it is already dimmed by the persisting
cover (global response) while the shadows fade back in. Drift uses real-time
wind (`wind_gust_scroll_px`), so cloud *speed* does **not** depend on day length
or the game-clock rate.

### Future gameplay coupling — `EnvironmentVisibilityAuthority` (deferred)

ADR-0005: gameplay reads an **authority**, not the renderer. When a first
consumer exists, add a thin authority:

- `get_open_surface_light_level(world_pos) → [0 dark .. 1 bright]`
  `= day_phase_brightness × (1 − O(cover))` for open sky. The cloud multiplier
  is **gated to open sky**: roofed/interior and underground contexts are not
  reduced by cloud cover, and return their own non-cloud-adjusted context value.
  Underground may still be dark by its own light rules (ADR-0005/0006); the
  guarantee here is only "clouds do not darken it further."
- The renderer (sun response) and this authority read the **same** weather
  occlusion model → one truth, two readers. Gameplay does **not** query the
  `Light2D` nodes.
- Consumers (fauna boldness, player stress) read this scalar; their behaviour
  tuning is separate work. No authority, read surface, or stub consumer lands in
  the approved active V0 slice.
- This is the **first slice** of the deferred ADR-0005 gameplay light authority.
  If it grows (per-tile grid, torches-as-gameplay-light), it graduates to its own
  ADR; flagged here, not built here.

## Sanctuary Contract (NON_NEGOTIABLE / ADR-0005)

Overcast darkness must strengthen, never flatten, the inside-safe / outside-
hostile contrast:

- Clouds remove the **sun** contribution. Torch / lamp / campfire are
  `PointLight2D` and are **never** occluded by the cloud field — their warm pools
  persist as islands of safety in the storm-dark.
- **Underground**: the sun is already off → unaffected by cloud cover.
- **Roofed / interior open-surface**: no open sky → not darkened by clouds
  (open-sky context gate).
- Net: the storm darkens the open wilds; the lit/roofed base keeps its own warm
  context. The colder and darker it is outside, the more the fire/torch read as
  safety — exactly the ADR-0005 fantasy.

Guarded by render probes: overcast outside vs a lit interior/torch pool stay
distinct; underground/roofed visuals are unaffected by cover. The future
visibility scalar gets its own authority probe when it lands.

## Performance Class

- Cloud occlusion scalar + field params: `interactive`-frame O(1).
- Global sun response: a few scalar writes per frame on `DaylightSystem`.
- `CloudOccluderField`: one world-space shader layer; **view-bounded** by
  `WorldViewOverlay`, uniform-only per frame; empty at clear, faded at full
  overcast. `background`/visual cost class.
- Future `EnvironmentVisibilityAuthority`: O(1) scalar reads when implemented.
- No native code, no per-tile/per-chunk loops, no startup prepass, no
  `WORLD_VERSION` change.

## Acceptance Criteria

- **Clear**: sun at full warm energy; no cloud shadows; the open surface looks
  like today's clear (no regression).
- **Cloudy**: soft drifting shadow patches that genuinely lack the sun's direct
  key (cool), warm sunlit gaps between, high local contrast; patches move with
  wind and enlarge with cover.
- **Overcast**: the `DirectionalLight2D` sun energy is near-zero; the open
  surface is uniformly cool, dim, flat (direct beam blocked everywhere); a
  campfire/torch `PointLight2D` pool stays warm and bright (sanctuary).
- **Underground & roofed**: visuals are unaffected by cloud cover (probe).
- **Night**: spatial cloud shadows fade out with the sun (none at deep night),
  fade back in at dawn; cloud cover state persists so an overnight-overcast sky
  reads as overcast at sunrise. Cloud drift speed is real-time wind, independent
  of day length (`cloud_night_probe`).
- **Gameplay seam**: `EnvironmentVisibilityAuthority` /
  `get_open_surface_light_level()` is deferred until the first consumer; no
  gameplay system may read the `Light2D` nodes.
- **Cleanup**: the cloud screen-darkening overlay, `OvercastFlattenOverlay`, and
  `SunRayOverlay` are removed (static check); the look no longer uses additive
  "sun rays".
- **Perf**: shader layer is one view-limited pass; field/scalar O(1); no
  `WORLD_VERSION` bump.

## Failure Cases / Risks

- **Godot occluder mismatch**: `DirectionalLight2D + LightOccluder2D` is not
  accepted for the live top-down cloud path because local project evidence shows
  the shadows project to screen-edge infinity.
- **Subtractive light mismatch**: subtractive `PointLight2D` blobs were tested
  and proven not to darken the CanvasModulate/normal-mapped plains ground even
  at exaggerated energy. Iteration 3 therefore lands the world-space shader
  shadow layer while the global sun-energy drop stays. The model is unchanged;
  only the patch *renderer* differs.
- **Double-darkening**: global sun-energy drop × shader shadow could overshoot
  to black. Calibrate; fade the shader layer as `O → 1`.
- **Wrong light occluded**: the live cloud path must not use `LightOccluder2D`
  or subtractive `PointLight2D` children. The shader layer is weather/open-sky
  driven and remains separate from point-light gameplay sources.
- **Gameplay scope creep**: the visibility scalar is the seam into ADR-0005's
  deferred authority — keep it a single open-surface scalar; do not let it grow
  into the full light grid here.
- **Project-wide relight**: changing the sun-energy curve re-lights the whole
  surface; validate in a probe before promoting to `world_runtime_v0.tscn`.

## Implementation Iterations

### Iteration 1 — Cloud occlusion model in Weather

- `WeatherRuntime.get_cloud_occlusion()` (`O(cover)`) only.
- Keep the drifting field descriptor internal/private in this iteration; no
  `CloudOccluderField`, no public field sampler, no raw `Dictionary` getter.
- Update `system_api.md` for the new `WeatherRuntime` public read in the same
  implementation change.
- No visual change yet. Logic probe: `O` rises clear→overcast, `0` at clear.

### Iteration 2 — Global sun response + retire old overlays

- **Status: landed 2026-06-25.** `DaylightSystem` dims the
  `DirectionalLight2D` and cools the ambient by `O`, open-sky only. Removed
  `OvercastFlattenOverlay`, `SunRayOverlay`, and the cloud screen-darkening
  overlay (+ their `broken`/`flatten`/`sun_ray` curves). `PlayerSunShadow` now
  attenuates distinct body shadows through the same `get_cloud_occlusion()`
  scalar.
- Render probe: clear unchanged; overcast = real dim cool surface; torch pool
  still warm; underground/roofed unaffected. → "overcast = real dark" visible.

### Iteration 3 — Spatial cloud shadows (`CloudOccluderField`)

- **Status: landed 2026-06-25.** View-bounded `CloudOccluderField` world-space
  shader shadow layer; field patches grow/merge with cover and fade as `O → 1`.
  The live renderer intentionally does not use `LightOccluder2D` (infinite
  top-down projection) or subtractive `PointLight2D` blobs (render-proven not to
  darken the plains ground).
- Render probe: cloudy layer changes rendered pixels above threshold; overcast
  is darker than clear through global sun response; underground/roofed gates
  remove the shader layer.

### Iteration 4 — `EnvironmentVisibilityAuthority` (minimal) — DEFERRED

- **Deferred (no consumers yet).** The project has no fauna or stress systems, so
  an open-surface darkness scalar would feed nothing — building it now is a
  scalar into a vacuum. Revisit when the first consumer (fauna AI / player
  stress) lands: then add the authority + `get_open_surface_light_level()`
  reading the **same** occlusion model (not the renderer, ADR-0005), one consumer
  hook, and the `system_api.md` entry. Until then overcast/night darkness is
  presentation-only; the ADR-0005 gameplay light authority stays a future,
  separate contract.

### Iteration 5 — Tuning + dev controls + night fade — DONE

- **Status: landed 2026-06-25.** Tuned for large, sparse, slowly drifting cumulus
  shadow blobs that grow and merge into overcast (authored shader uniforms:
  `cloud_scale_px`, threshold `mix(A, B, coverage)`, `peak`, `edge`,
  `cloud_scroll_scale`, `shadow_color`; `A`/`B` set how rare clouds are at low
  cover and how total the overcast merge is).
- **Night fade**: shader opacity × `DaylightSystem.get_sun_day_factor()` → shadows
  gone at night, fade in at dawn; cover state persists (see Spatial section).
- **Dev controls (not a gameplay path)**: hold `+` / `-` to ramp `WeatherRuntime`
  cloud cover in real time (`nudge_debug_cloud_cover`) and watch clouds grow,
  drift, and merge live; `K` still cycles regimes.
- Probes: `cloud_occlusion_render_probe` (layer visible at a fixed cloudy cover,
  overcast darker, z/roof sanctuary gates), `cloud_night_probe` (fade by night,
  partial at dawn), `cloud_occluder_field_probe` + `cloud_occlusion_light_probe`
  (shader-layer + no Light2D children structure guards), `cloud_sweep_probe`
  (visual cover sweep, dev).

## Required Updates

Already required for spec landing:

- `docs/README.md` — index this spec in the root canonical map.
- `docs/02_system_specs/README.md` — index this spec (with spec landing).
- `weather_runtime.md` — mark the Iteration 2b cloud overlays superseded; link
  here as the cloud-presentation source of truth.

At implementation time:

- Iteration 1: `system_api.md` — add `WeatherRuntime.get_cloud_occlusion()` as a
  public read.
- Iteration 2: `world_dynamic_lighting_2d.md` — add/update note that cloud
  occlusion rides the `DirectionalLight2D` sun and does not make the visual
  lights into gameplay authority.
- Iteration 3: `system_api.md` — no update required in the landed slice because
  no new public `WeatherRuntime` field descriptor or sampler was introduced.
- Iteration 4: `system_api.md` — add the `EnvironmentVisibilityAuthority` read
  surface when it lands (deferred — no consumers yet).
- Iteration 5: `system_api.md` — `WeatherRuntime` dev cover override
  (`set_debug_cloud_cover` / `nudge_debug_cloud_cover` / `clear_debug_cloud_cover`);
  `DaylightSystem.get_sun_day_factor()` is documented in this spec (DaylightSystem
  has no `system_api` entry).
