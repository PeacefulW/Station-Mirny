---
title: Cloud Occlusion & Overcast Darkness
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.2
last_updated: 2026-06-25
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
light is genuinely blocked. One authoritative cloud-occlusion model feeds both
the renderer and a minimal gameplay visibility scalar (ADR-0005).

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
2. **Spatial** — a `LightOccluder2D` "cloud-blob" pool casts the moving shadow
   patches that genuinely block the sun.

## Gameplay Goal

Plains weather reads as real sky over a real world. Scattered clouds throw cool,
drifting shadows across warm sunlit ground; as cover grows the shadows enlarge
and merge; at full overcast the sun is genuinely blocked and the open surface
goes cool and dark — while the campfire/torch stay warm islands of safety. A
stormy daytime outside is meaningfully darker and more dangerous (ADR-0005,
category "severe weather = darkness even in day").

## Scope

- A drifting **cloud-occlusion field** + a **global occlusion scalar**, owned by
  `WeatherRuntime` (extends the existing `cloud_cover` read, same slow state).
- A **global sun response** in `DaylightSystem`: cloud occlusion lowers the
  `DirectionalLight2D` energy and cools the ambient (surface only).
- A **`CloudOccluderField`**: a view-bounded pool of `LightOccluder2D` cloud
  blobs casting the sun's moving shadows; blobs grow/merge with cover.
- A minimal **`EnvironmentVisibilityAuthority`**: `get_open_surface_light_level()`
  in `[0 dark .. 1 bright]` for gameplay, read from the same occlusion model
  (NOT scraped from the renderer).
- Retire the three old overlays.

## Out of Scope

- Visible cloud *bodies* overhead (shadows on the ground only — chosen).
- Full ADR-0005 gameplay light authority (per-tile light grid, torches as
  gameplay light): this builds only the open-surface darkness scalar; a larger
  authority graduates to its own ADR.
- Cloud occluders on anything other than the cloud pool.
- New save state (cover already persists via weather Iteration 3) or
  `WORLD_VERSION` change.
- Precipitation, lightning, second biome.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical data, overlay, or visual only? | Cloud-occlusion model is environment-runtime state (derived from weather, ADR-0007 layers 2/3); sun response + occluders are presentation (layer 4); the visibility scalar is a gameplay-authority read. No worldgen/terrain truth. |
| Save/load? | No new state. Cover persists via weather slow state; everything here derives. |
| Deterministic? | Field is a pure function of world pos + drift + cover; the global scalar is a pure function of cover. Occluder placement samples the field deterministically. |
| Must it work on unloaded chunks? | Weather is global; occluders/authority are view/position-local and need no chunk data. |
| C++ or main thread? | Engine 2D lighting (GPU) + a bounded pool of light nodes + a few scalars on the main thread. No native, no heavy loops. |
| Dirty unit | The global weather state (cover) + the on-screen occluder set. |
| Single owner | Field/scalar: `WeatherRuntime`. Sun response: `DaylightSystem`. Occluders: `CloudOccluderField`. Gameplay scalar: `EnvironmentVisibilityAuthority`. |
| 10x/100x | Cost is independent of world size; occluders are view-bounded and count-capped. |
| Hidden fallback? | None. If the sun light or weather owner is missing, fail explicitly. |
| Gameplay coupling | Yes, minimal: one authoritative open-surface darkness scalar. Gameplay reads the authority, never the lights (ADR-0005). |

## Data Model

### Cloud occlusion (owned by `WeatherRuntime`)

The existing `get_cloud_cover()` stays. Iteration 1 adds exactly one new public
read:

- `get_cloud_occlusion()` → `[0,1]`: global fraction of direct sun blocked,
  `O(cover)` — rises with cover, saturating toward `1` at full overcast. Pure
  function of cover (tuning anchors below).

The drifting field itself is a presentation function of world position +
accumulated wind drift + cover (seamless tiling-texture noise, the
precision-safe base already proven in `tools/cloud_shader_iso.gd`). Coverage
(area above a threshold) and blob size grow with cover so blobs enlarge and
merge. The field is read by the occluder placement and by the shadow visual; it
is not stored.

Field descriptor reads are **not** part of Iteration 1. If Iteration 3 needs a
cross-owner field descriptor or sampler for `CloudOccluderField`, that later
iteration must add typed/read-only `WeatherRuntime` reads and document them in
`system_api.md` in the same change. Do not expose a raw `Dictionary` boundary
for this field.

Tuning anchors (finalized by render probe; aligned to regime cover bands clear
`[0,0.15]`, cloudy `[0.35,0.62]`, overcast `[0.72,1.0]`):

- `O(cover) ≈ smoothstep(0.10, 0.95, cover)` — near `0` at clear, near `1` at
  overcast; this is what dims the global sun.
- field coverage/scale ≈ rises across the same range so cloudy = scattered
  blobs, overcast = merged sheet.

### No new persisted state

Cover persists via weather Iteration 3 (`weather.json`). Occlusion, occluders,
and the visibility scalar all derive on load.

## Runtime Architecture

### Owners

| Concern | Owner |
|---|---|
| Cloud occlusion scalar + field params | `WeatherRuntime` (getters) |
| Sun energy/colour + ambient cool-shift response | `DaylightSystem` |
| Spatial moving shadows (occluders) | `CloudOccluderField` (new) |
| Open-surface darkness for gameplay | `EnvironmentVisibilityAuthority` (new) |

### Global sun response (`DaylightSystem`)

`DaylightSystem` already owns the `DirectionalLight2D` sun (energy from the
day phase, angle by hour, off underground). It reads `WeatherRuntime`
occlusion and, **on the surface only**:

- scales sun energy by `(1 − k · O(cover))` so overcast nearly extinguishes the
  direct key (the world falls to the ambient floor);
- shifts the ambient toward a cool desaturated grey as `O` rises (the diffuse
  overcast sky), reusing the existing cold-tint idea but now physically as "only
  diffuse sky remains".

Clear cover leaves the sun unchanged. Underground is already sunless. A roofed/
interior surface context is treated as no-open-sky (no cloud darkening).

### Spatial moving shadows (`CloudOccluderField`)

A **view-bounded pool of `LightOccluder2D` cloud blobs** (each a soft polygon),
placed/scaled/drifted by sampling the cloud field across the current view (the
same proximity/view-bounded discipline as `world_dynamic_lighting_2d.md`
Iteration 2 occluders). Per frame the blobs **translate/scale only — no polygon
rebuild** (LAW 1/ADR-0001: no per-frame full rebuilds). Cover drives active blob
count + scale; overlap = merged shadow. The sun runs `shadow_enabled` with
`shadow_filter` for soft edges.

- Empty/disabled near clear cover (`O ≈ 0`).
- As `O → 1` (overcast) the **global** sun-energy drop already darkens
  everything, so the blob pool can fade out to avoid full-screen occluder thrash
  (the two knobs hand off; never double-count to pure black unintentionally).
- **Cull/layer so cloud occluders block ONLY the sun**, never the torch/lamp/
  campfire `PointLight2D` (Godot per-light occluder `light_mask` / cull). This is
  the sanctuary guarantee (below).

### Gameplay coupling — `EnvironmentVisibilityAuthority` (minimal slice)

ADR-0005: gameplay reads an **authority**, not the renderer. New thin authority:

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
  tuning is separate work. This iteration lands the authority + read surface and
  one stub consumer hook.
- This is the **first slice** of the deferred ADR-0005 gameplay light authority.
  If it grows (per-tile grid, torches-as-gameplay-light), it graduates to its own
  ADR; flagged here, not built here.

## Sanctuary Contract (NON_NEGOTIABLE / ADR-0005)

Overcast darkness must strengthen, never flatten, the inside-safe / outside-
hostile contrast:

- Clouds occlude **only the sun** (`DirectionalLight2D`). Torch / lamp /
  campfire are `PointLight2D` and are **never** occluded by cloud blobs — their
  warm pools persist as islands of safety in the storm-dark.
- **Underground**: the sun is already off → unaffected by cloud cover.
- **Roofed / interior open-surface**: no open sky → not darkened by clouds
  (open-sky context gate).
- Net: the storm darkens the open wilds; the lit/roofed base keeps its own warm
  context. The colder and darker it is outside, the more the fire/torch read as
  safety — exactly the ADR-0005 fantasy.

Guarded by a render + authority probe: overcast outside vs a lit interior/torch
pool stay distinct; underground/roofed visibility scalar is unaffected by cover.

## Performance Class

- Cloud occlusion scalar + field params: `interactive`-frame O(1).
- Global sun response: a few scalar writes per frame on `DaylightSystem`.
- `CloudOccluderField`: N on-screen blobs × the sun's shadow; **N capped and
  view-bounded**, transforms-only per frame (no rebuild); empty at clear, faded
  at full overcast. `background`/visual cost class.
- `EnvironmentVisibilityAuthority`: O(1) scalar reads.
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
- **Underground & roofed**: visuals and the visibility scalar are unaffected by
  cloud cover (probe).
- **Gameplay**: `get_open_surface_light_level()` falls with cover on open sky;
  roofed/underground contexts are not reduced by cloud cover and remain governed
  by their own light rules; no gameplay system reads the `Light2D` nodes
  (static check).
- **Cleanup**: the cloud screen-darkening overlay, `OvercastFlattenOverlay`, and
  `SunRayOverlay` are removed (static check); the look no longer uses additive
  "sun rays".
- **Perf**: occluder count is bounded and view-limited; field/scalar O(1); no
  `WORLD_VERSION` bump.

## Failure Cases / Risks

- **Occluder edge hardness vs soft clouds**: `DirectionalLight2D` shadows can be
  hard. Mitigate with `shadow_filter` + soft blob polygons; decision point — if
  still too hard, the spatial patches fall back to a soft shader shadow (cool
  "ambient-only" tint where the field is dense) while the global sun-energy drop
  stays. The model is unchanged; only the patch *renderer* differs.
- **Double-darkening**: global sun-energy drop × occluder shadow could overshoot
  to black. Calibrate; fade the blob pool as `O → 1`.
- **Wrong light occluded**: cloud occluders must cull so they block the sun but
  not point lights — verify the per-light mask, or the torch goes dark under
  clouds (sanctuary break).
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

- `DaylightSystem` dims the `DirectionalLight2D` and cools the ambient by `O`,
  surface-only. Remove `OvercastFlattenOverlay`, `SunRayOverlay`, and the cloud
  screen-darkening overlay (+ their `broken`/`flatten`/`sun_ray` curves).
- Render probe: clear unchanged; overcast = real dim cool surface; torch pool
  still warm; underground/roofed unaffected. → "overcast = real dark" visible.

### Iteration 3 — Spatial cloud shadows (`CloudOccluderField`)

- View-bounded `LightOccluder2D` blob pool sampling the cloud field; sun
  `shadow_enabled`; blobs grow/merge with cover; cull mask so point lights are
  unaffected; fade as `O → 1`.
- Render probe: drifting soft shadows in cloudy; merge toward overcast; torch
  unaffected; occluder count bounded/view-limited.

### Iteration 4 — `EnvironmentVisibilityAuthority` (minimal)

- Authority + `get_open_surface_light_level()`; one stub consumer hook
  (fauna/stress) reading it. Probe: scalar drops with cover on open sky, stays
  unaffected by cover under roof/underground; static check that no system reads
  the lights.

### Iteration 5 — Tuning + probes

- Calibrate `O` curve, occluder count/softness, ambient cool-shift; sanctuary +
  contrast + perf probes.

## Required Updates

Already required for spec landing:

- `docs/README.md` — index this spec in the root canonical map.
- `docs/02_system_specs/README.md` — index this spec (with spec landing).
- `weather_runtime.md` — mark the Iteration 2b cloud overlays superseded; link
  here as the cloud-presentation source of truth.

At implementation time:

- Iteration 1: `system_api.md` — add `WeatherRuntime.get_cloud_occlusion()` as a
  public read.
- Iteration 2: `world_dynamic_lighting_2d.md` — note cloud occlusion rides the
  `DirectionalLight2D` sun and does not make the visual lights into gameplay
  authority.
- Iteration 3: `system_api.md` — add any typed/read-only `WeatherRuntime` field
  descriptor or sampler needed by `CloudOccluderField`, if such a public
  boundary is introduced.
- Iteration 4: `system_api.md` — add the `EnvironmentVisibilityAuthority` read
  surface when it lands.
