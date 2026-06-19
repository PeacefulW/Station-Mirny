---
title: Wind Runtime V0 and Grass Scatter Presentation
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.13
last_updated: 2026-06-13
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/event_contracts.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - world_object_placement_v0.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Wind Runtime V0 and Grass Scatter Presentation

## Purpose

Define two tightly coupled but separately owned systems:

1. **Wind runtime V0** — the first minimal slice of the environment runtime
   (ADR-0007 layer 3): a single owner of the current wind state, published to
   all visual consumers through Godot global shader uniforms.
2. **Grass scatter presentation** — a dense, visual-only tuft layer placed by
   native code exactly where the ground material already paints grass, densest
   inside orange biofield cores, and animated by the wind runtime.

This spec exists so wind does not get reimplemented per consumer (grass now,
trees/plants/particles later) and so dense grass does not enter the repo as a
GDScript scatter loop or a per-frame material broadcast.

## Gameplay Goal

The plains surface should read as alive: low dry grass sways under a wind that
visibly travels across the field in gusts. Grass grows only where the ground
visually has grass, thickens with the painted density ladder, and peaks inside
orange biofield cores. Wind strength is one shared truth: when later systems
(trees, plants, weather, audio) react to wind, they react to the same wind.

## Scope

- `WindRuntime` autoload: single writer of wind state and wind global shader
  uniforms; paused with the game; O(1) per-frame work.
- `WorldVisualWindProfile`: authored wind behaviour profile (base strength,
  gust drift, direction drift, gust field shape), code-profile in the
  `WorldVisualLightingProfile` style.
- Wind global shader uniforms consumed by the grass shader (and by future
  vegetation/decor shaders without architecture changes).
- Native (`WorldCore`) grass scatter buffer build per chunk: deterministic tuft
  placement sampled from the same aperiodic world fields the ground shader
  uses (`grass_density`, `orange_region`, `rock_region`).
- Output format: a ready interleaved `MultiMesh` 2D buffer (transform + color)
  applied on the main thread with a single `multimesh.buffer` assignment.
- A thin `ChunkView` grass scatter layer: low grass only, below the player and
  all object decor; no depth buckets, no collision, no save state.
- Grass tuft atlas exported as a PNG asset by the procedural tuft generator
  (tool path), preloaded at runtime.
- Wind vertex animation in one shared grass shader: per-instance random phase
  plus a scrolling world-position gust field (gradient noise) driven by the
  wind globals.
- Orange biofield emphasis through density and per-instance tint in V0.
- Additional wind consumers (no new wind owner): a full-screen drifting-dust
  overlay whose density, streak length, and opacity scale with
  `wind_strength` (a visual wind speedometer), and a HUD wind readout
  (`UI_HUD_WIND`) showing the strength percentage and direction arrow read
  from `WindRuntime`. Both are presentation-only and read the same wind
  state; the dust overlay lives in world space (under the Daylight modulate)
  so it tints with day/night. The world-space full-screen overlay
  infrastructure is shared via base class `WorldViewOverlay`.

## Out of Scope

- Gameplay wind effects (temperature, fire spread, projectiles, turbines).
- Weather, seasons, storms, or any EventBus wind events.
- Wind influence on existing decor/flora atlases (the seam is prepared; the
  cutover of `world_decor_atlas_batch.gdshader` to wind globals is a separate
  task).
- Tall grass, grass harvesting, grass items, grass collision, or pathing
  effects.
- A second biome. V0 is `plains` ground + orange biofield only.
- Multiplayer replication of wind (presentation is client-local; ADR-0007
  already reserves host-owned local runtime for later).
- Runtime atlas baking (`Image.set_pixel` painting at boot is forbidden here).
- Saving any wind or grass state.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Wind state is environment runtime local state (ADR-0007 layer 3), presentation-only consumers in V0. Grass scatter is visual only. Canonical terrain ids and walkability are untouched. |
| Save/load required? | No. Wind reconstructs on load (ADR-0007: only slow world state persists; V0 has none). Grass is derived. |
| Deterministic? | Grass placement: yes — pure function of seed, world version, chunk, and authored params. Wind animation: intentionally non-deterministic visual drift, never read by gameplay in V0. |
| Must it work on unloaded chunks? | Grass buffers exist only for loaded chunk views. Placement is derivable for any chunk on demand. |
| C++ compute or main-thread apply? | Tuft placement and buffer packing in C++; main thread only assigns the finished buffer; the shader animates. |
| Dirty unit | Wind: one global state struct. Grass: one chunk scatter buffer. |
| Single owner | Wind state: `WindRuntime`. Grass placement: `WorldCore` native build. Grass scene apply: chunk grass scatter layer. |
| 10x / 100x scale path | More tufts stay in one buffer per chunk (no per-instance calls); more wind consumers read the same globals (no per-consumer broadcast). |
| Main-thread blocking risk | Buffer assignment is one bounded copy per chunk through the existing decorative visual upload path. |
| Hidden fallback? | Forbidden. No GDScript placement fallback when native is unavailable; fail explicitly. |
| Could it become heavy later? | Yes (denser grass, more consumers) — which is why placement is native-first and wind is globals-first now. |
| Whole-world prepass or local compute only? | Local per-chunk compute only. |

## Design Intent

### One wind truth, broadcast once

The dev scene updated wind by `set_shader_parameter` per material per frame.
At runtime scale (many chunks x layers) that becomes hundreds of calls per
frame. Instead, `WindRuntime` writes a few **global shader uniforms** once per
frame and every wind-aware shader reads them. Adding a consumer costs zero
runtime work.

`wind_time` is accumulated by `WindRuntime` (pause-aware, scalable), not taken
from the shader built-in `TIME`, so wind can stop, gust, or be driven by future
gameplay.

The wind **target** (strength, heading, gustiness) is now owned by
`WeatherRuntime` (`weather_runtime.md`): wind is a derivative of weather.
`WindRuntime` smooths toward that target and still publishes the same `wind_*`
globals, so grass, dust, and the HUD wind readout are unchanged.

### Wind is a scrolling gust field, not a synchronized sway

Per-instance random phase alone reads as "wiggling fur": no visible gusts. A
pure sine wave front is rejected too: it is strictly periodic, so gust fronts
render as evenly spaced equal-strength stripes at far zoom — the same
periodicity artifact the ground composition already bans for textures. The
grass vertex shader combines:

- per-instance random phase (from instance color channel) for variety;
- a **scrolling aperiodic gust field**: gradient noise (the same noise family
  as the ground shader fields) sampled at world position, scrolled along
  `wind_direction` at gust speed. The field is anisotropic — compressed along
  the wind, stretched across it — so gusts read as irregular elongated fronts
  traveling with the wind, varying in strength, shape, and duration;
- a blade weight from `UV.y` squared, so roots stay planted and tips sway.

**Strength drives tempo, not stretch.** "Движение от силы ветра" means a
stronger wind makes grass move *faster*, never *longer*: `wind_strength`
scales the advance rate of `wind_time` (sway tempo) and the gust-front travel
speed inside `WindRuntime`, both as accumulated quantities so a strength
change never breaks animation phase. The sway amplitude itself is an authored
fraction of the tuft's own height (per-layer material param) and must not be
multiplied by wind strength — strength-scaled amplitude visibly stretches
tufts into hair-like streaks. Exactly two strength couplings are allowed:

- a narrow calm gate near zero strength, so a dead calm freezes sway entirely;
- a **bounded storm lean**: a downwind offset of the resting pose that grows
  with strength up to its own authored height-fraction cap, so a
  full-strength wind reads as a storm (grass pressed down, trembling fast).
  The lean may breathe — oscillate around the pressed pose within its own
  bounded fraction — so storm grass visibly rocks back and forth. Storm lean
  offsets the pose; it is never a multiplier on the gust oscillation
  amplitude, and all fractions stay small authored caps.

In the MultiMesh canvas vertex stage, `VERTEX` is in pre-instance-transform
quad space: a "pixel" offset would be multiplied by the tuft's size (the
stretch bug). The sway offset is therefore computed in world units from the
tuft height and mapped back through the inverse of the instance transform's
2x2 part.

The gust field is a presentation-time function of world position and the
accumulated scroll offset; it adds one gradient-noise sample per vertex,
which is bounded and cheap relative to the ground material's per-pixel fbm
work.

### Grass grows where the ground already says it does

The ground shader (`ground_hybrid_material.gdshader`) already defines
`grass_density`, `orange_region`, and `rock_region` as deterministic aperiodic
functions of world position. Native placement re-evaluates the same field
formulas with the same authored parameters, so tufts land exactly on visually
grassy ground:

- below the grass transition band: no tufts;
- across the grass ladder: density scales up;
- inside `orange_region`: maximum density plus an orange tint shift;
- inside `rock_region` and on water/non-plains tiles: no tufts.

**Field formula law:** the GLSL and C++ implementations of these fields are one
formula with two transcriptions. Any change to the field math or its authored
parameters must update both in the same task, verified by a render probe.

### Dense scatter must never be a script loop

Target densities are thousands of tufts per chunk. Both per-instance GDScript
generation and per-instance `set_instance_*` unpacking are forbidden (LAW 1,
LAW 2). Native returns the final interleaved `MultiMesh` buffer; the main
thread performs one assignment.

### Grounding and atmosphere layers

Four presentation-only treatments make the grass read as part of the surface
rather than stickered sprites. All are derived, never persisted, and tuned by
authored data:

- **Grounded tuft atlas.** The procedural blade painter draws a vertical
  colour gradient: a dark, desaturated, grounded-tone root (ambient occlusion
  + soft earth->grass transition) up to a lighter tip. Tufts are low and
  splayed (steppe clumps, not vertical flames). Frame variety is authored by
  in-bank frame type (bloom / sparse clump / dense / normal) so the field is
  not stamped from one silhouette. Roots stay anchored at the frame bottom
  (wind contract).
- **Grass-ladder ground backing.** The ground material's grass-texture
  thresholds are tuned so the density range where native places tufts is
  already a grass carpet — tufts grow out of grass, not bare soil. Same
  `grass_density` field feeds both, so they stay synchronized.
- **Contact-shadow blobs.** Native emits one flat shadow blob under larger
  tufts (`shadow_buffer`), rendered as a single layer below the whole grass
  ladder (`Z_GRASS_SHADOW`), pressing clumps onto the ground.
- **Biofield spores.** Native emits sparse motes above strong `orange_region`
  cores (`spore_buffer`), rendered above the grass (`Z_GRASS_SPORE`) with a
  cold bioluminescent additive glow that drifts on the same wind globals.
- **Macro field variation.** The grass shader tints tufts by large aperiodic
  fields (warm/rust shift, dry bleach) so the carpet breathes instead of
  reading as one flat colour.

## Data Model

### Wind global shader uniforms

Declared in project settings (`shader_globals`), written only by `WindRuntime`:

```text
wind_time: float           # accumulated wind ANIMATION time; advance rate
                           # scales with strength (pause-aware)
wind_direction: vec2       # normalized
wind_strength: float       # 0..1 normalized current strength
wind_gust_scroll_px: vec2  # accumulated gust-field scroll offset; advance
                           # speed scales with strength
```

`wind_gust_scroll_px` is the time integral of
`wind_direction * gust_scroll_speed`, accumulated by `WindRuntime`. Shaders
must subtract this offset from world position instead of computing
`wind_direction * wind_time * speed` themselves: the direct product is
discontinuous whenever the wind direction drifts, which would make gust
fronts slide sideways over time.

Per-layer response (max amplitude px, gust field scale/anisotropy/speed
multipliers, layer scale) stays in the consuming material's authored params,
so grass, trees, and particles can respond differently to the same wind.

### `WorldVisualWindProfile`

Code profile (RefCounted, statics) in the `WorldVisualLightingProfile` style:

```text
BASE_STRENGTH: float            # calm baseline 0..1
GUST_STRENGTH_SPAN: Vector2     # min/max strength during gust drift
GUST_DRIFT_PERIOD_S: float      # slow strength evolution period
DIRECTION_BASE_DEG: float
DIRECTION_DRIFT_DEG: float      # slow heading wander amplitude
DIRECTION_DRIFT_PERIOD_S: float # slow heading wander period
GUST_FIELD_SCALE_PX: float      # characteristic world-space gust size
GUST_FIELD_ANISOTROPY: float    # front elongation across the wind direction
GUST_SCROLL_SPEED_PX_PER_S: float  # base gust front travel speed
WIND_ANIM_RATE_SPAN: Vector2    # wind_time advance rate at strength 0..1
GUST_SCROLL_SPEED_STRENGTH_SPAN: Vector2  # scroll speed factor at strength 0..1
```

Pure functions map accumulated time to the current strength/direction; no
per-frame allocations.

### Grass scatter presentation data

Grass presentation rides the existing terrain presentation data model
(`terrain_hybrid_presentation.md`), as a presentation-only profile (empty
`terrain_ids`, like `lake:water_surface_profile`):

- `TerrainMaterialSet` `plains:grass_scatter_material`
  - `extra_textures`: `grass_tuft_atlas`
  - `sampling_params`: tuft size ranges, low/mid band split, per-band density,
    height scale (V0 target: low+mid only, height scale ~0.6-0.8), wind max
    amplitude px, gust field scale/anisotropy/speed multipliers, orange tint, instance cap
    per chunk, and the shared ground field params it must mirror
    (`grass_field_scale_px`, `grass_coverage`, `orange_field_scale_px`,
    `orange_coverage`, `rock_field_scale_px`, `rock_coverage`).
- `TerrainShaderFamily` `terrain.grass_scatter` with the shared grass shader.
- `TerrainPresentationProfile` `plains:grass_scatter_profile`
  (presentation-only, registry-addressable by id).

The shared ground field params must be authored once and fed to both the
ground material and the native grass build (single authored source; no second
hidden copy of the numbers).

### Native grass buffer result

New native build call (exact signature finalized in implementation, documented
in `packet_schemas.md` in the same task):

```text
WorldCore.build_grass_scatter_buffer(
  world_seed, world_version, chunk_coord,
  terrain_ids: PackedInt32Array,
  lake_flags: PackedByteArray,
  params: PackedFloat32Array      # packed authored sampling params
) -> Dictionary {
  "multimesh_buffer": PackedFloat32Array,  # 12 floats per instance:
                                           # 2D transform (8) + color (4)
  "instance_count": int,
}
```

Instance color packing follows the existing decor convention:
`r = frame_index/255`, `g = tint`, `b = phase`, `a = alpha`.

The call is deterministic from its inputs (LAW 3-compatible: no scene, player,
or runtime state reads). Tuft placement uses hash-based candidate slots plus
field sampling; `randf` is forbidden.

### Grass tuft atlas asset

The procedural tuft painter from the dev scene moves into a tool/export path
(generator-first authoring). Export target:

```text
assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png
```

Fixed frame grid (4 columns x 8 rows, frame 72x104): rows 0-3 are the dry
steppe palette (frames 0-15), rows 4-7 are the orange biofield palette
(frames 16-31). Native placement picks the biofield bank inside strong
`orange_region`; the dry bank elsewhere. Alpha background, tuft roots
anchored at the frame bottom. Runtime only preloads the PNG; runtime atlas
painting is forbidden.

## Runtime Architecture

### Owners

| Concern | Owner |
|---|---|
| Wind state + globals write | `WindRuntime` autoload |
| Wind behaviour curve | `WorldVisualWindProfile` |
| Grass placement compute | `WorldCore` (C++) |
| Grass buffer request/refresh scheduling | `WorldStreamer` decorative visual upload path |
| Grass scene apply + layer lifecycle | chunk grass scatter layer inside `ChunkView` |
| Grass look + wind response | shared grass shader family + authored material set |

### Flow

1. Chunk publishes through the normal packet path (grass never blocks reveal —
   LAW 10 "terrain now, cosmetics later").
2. `WorldStreamer` enqueues a grass build for the chunk on the same bounded
   decorative path used for shoreline/mountain mask work.
3. Native returns the finished buffer; the visual upload job assigns it to the
   chunk's grass `MultiMesh` (one bounded copy). Native placement rejects
   candidates inside local mountain-edge clearance, so decorative grass cannot
   peek from under the organic runtime mountain mask.
4. Every frame, `WindRuntime` advances wind state and writes the three global
   uniforms once.
5. The grass shader animates vertices from globals + per-instance data. No
   per-frame CPU work touches grass.

### Z-order and layering: the player-relative mid-layer depth ladder

Grass, object decor, and the player share one **player-relative depth
ladder**. The world is cut into absolute horizontal stripes
(`WorldRuntimeConstants.DEPTH_STRIPE_PX`, 64 per chunk); a stripe's z is
assigned relative to the player's feet stripe (the anchor), clamped to
±`DEPTH_LADDER_HALF_RANGE_STRIPES`: grass at `base + (rel+K)*2`, objects at
`+1`, the player constant at the ladder center. Southern stripes overdraw
northern ones with 16 px precision, so grass in front of a rock or the
player's boots covers them while everything behind stays behind.

A periodic (modulo) ladder is **forbidden**: class wrap-around at every
period boundary flips overlap order anywhere on screen (a rock slightly
north of a boundary draws over a player slightly south of it). The
player-relative anchor has no wrap; beyond the clamp range (±768 px, larger
than the screen at gameplay zooms) stripes pin to the ladder edges where
relative errors are no longer distinguishable.

`WorldStreamer` owns the anchor: when the player's feet stripe changes, it
re-assigns z on all chunk mid-layer stripe nodes (plain `z_index` writes on
existing nodes, no buffer rebuilds; layers cache the applied anchor and
reset it when their batches rebuild). Native returns the tuft buffer
pre-split per chunk-local stripe (`bucket_buffers`, sparse
`MultiMeshInstance2D` nodes per non-empty stripe). Mountain presentation
sits above the whole ladder (`Z_MOUNTAIN_TOP/PAGE`), ground/edge/blob layers
below it, contact shadows just below the ladder.

### Diff refresh

When a chunk's authoritative tiles change (mining/diff apply), the chunk's
grass buffer is rebuilt through the same decorative path. Dirty unit: the
chunk. The synchronous mutation call must not rebuild or upload grass.

### Failure policy

If native grass build is unavailable or returns malformed data, the layer
fails explicitly (error + no grass). No GDScript placement fallback, no silent
empty-buffer masking of a contract violation.

## Event Contracts

None in V0. `WindRuntime` emits no EventBus signals yet. If a future iteration
adds wind events or gameplay reads, `event_contracts.md` / `system_api.md`
must be updated in that task.

## Save / Persistence Contracts

None. Wind state and grass buffers are never serialized. Saves remain valid
with this feature on or off.

## Performance Class

- Wind update: `interactive`-frame work, O(1) (a few trig/noise evaluations +
  3 global uniform writes).
- Grass build: `background` native compute per chunk.
- Grass apply: bounded main-thread publish (one buffer assignment per chunk)
  on the decorative visual upload path.
- Target scale: thousands of tufts per dense chunk, dozens of loaded chunks;
  authored per-chunk instance cap bounds worst-case buffer size.
- Zoom LOD (Iteration 3): the native buffer is importance-ordered (large
  tufts first, small detail last), so far zoom trims the tail through one
  `visible_instance_count` write per chunk — no rebuild, no per-instance
  work. The zoom-to-fraction curve is authored data
  (`lod_full_zoom` / `lod_min_zoom` / `lod_min_fraction`);
  `lod_min_fraction = 1.0` disables trimming entirely (the current authored
  default after visual review: pop-out of small tufts read worse than the
  fill-rate cost).
- Escalation path: lower authored densities; band split tuning.

## Modding / Extension Points

- New vegetation responding to wind: read the same wind globals from any
  shader; no core changes.
- Grass look/density tuning: authored data in the material set
  (`sampling_params`), not code constants.
- A future biome adds its own presentation-only grass profile + material set;
  the native build must take its field params from authored data, not
  hardcoded plains numbers.

## Acceptance Criteria

V0 is acceptable when:

- a render probe shows tufts only on visually grassy ground, density rising
  along the painted ladder, peaking inside orange biofield cores, absent on
  rock patches, water, mountains, and bare soil (before/after panels);
- a probe at far/mid/near zoom shows no chunk-seam lines in tuft coverage;
- gust fronts visibly travel across the field along `wind_direction`, are
  aperiodic (no evenly spaced stripe pattern at far zoom), and vary in
  strength/shape; setting `wind_strength` to 0 freezes sway (tufts stand,
  roots planted);
- raising `wind_strength` speeds up sway tempo and gust travel and presses
  grass into a bounded downwind storm lean, but does not stretch tufts: the
  total tip offset stays within small authored height fractions
  (oscillation + storm lean cap) at any strength (side-by-side strength
  panel; the shader contains no `strength * oscillation` product);
- pausing the game stops grass motion;
- runtime contains no per-frame `set_shader_parameter` wind broadcast and no
  GDScript loop over tuft instances (static check);
- grass publish goes through the bounded decorative path and never blocks
  chunk reveal;
- the grass atlas is a checked-in PNG produced by the generator tool; no
  runtime atlas painting;
- placement is identical for identical seed/version/chunk/params (re-run
  probe);
- removing the grass layer entirely leaves gameplay, saves, and other systems
  untouched.

## Failure Cases / Risks

This design is wrong if:

- grass placement appears in a GDScript loop or object-packet records;
- wind state gets a second writer or per-consumer broadcast paths return;
- the C++ and GLSL field formulas drift (tufts visibly slide off painted
  grass) — must be caught by the acceptance render probe;
- grass buffers block first chunk reveal or rebuild during interactive input;
- the ground texture itself is animated (only tufts may move);
- VRAM/buffer growth: dense-chunk buffer is ~12 floats x cap; the authored cap
  plus density probes must keep worst case acceptable before densities are
  raised.

## Open Questions

- Does `WindRuntime` deserve gameplay-readable API now or only at the first
  gameplay consumer? (V0: defer; keep state private to presentation.)
- Orange biofield: is per-instance tint enough, or does the generator export a
  second orange tuft atlas in a later pass?
- Should mid-band tufts get a slightly stronger gust response than low-band
  (parallax feel), and is that authored per band?

## Implementation Iterations

### Iteration 0 — Spec landing

- This spec lands as draft; both doc indexes link it.
- No runtime changes.

### Iteration 1 — Wind runtime + globals + dev-scene proof

- Add `shader_globals` entries, `WindRuntime` autoload,
  `WorldVisualWindProfile`.
- Port the dev grass shader to read wind globals + the scrolling gust field;
  the dev scene becomes the first consumer (verifies pause, strength,
  direction, gust travel).
- Render probe: irregular gust fronts traveling across the dev field;
  strength 0 freeze.
- Doc updates: `system_api.md` only if a public read surface is added.

### Iteration 2 — Atlas export + native grass buffer + runtime layer

- Move tuft painting into the generator/export tool; commit the PNG atlas.
- Implement `WorldCore.build_grass_scatter_buffer` (fields mirrored from the
  ground shader; deterministic candidates; interleaved buffer output).
- Add the presentation-only profile/material/shader-family resources.
- Add the chunk grass layer + streamer scheduling on the decorative path.
- Render probes: ladder/biofield density match, seam check, zoom series.
- Doc updates in the same task: `packet_schemas.md` (buffer result shape),
  `terrain_hybrid_presentation.md` (cross-reference to this spec if its ground
  composition section needs the grass layer note).

### Iteration 3 — Tuning and optional LOD

- Density/size/tint tuning via authored data + probes.
- Optional: importance-ordered buffers + zoom-based `visible_instance_count`.
- Optional: orange biofield atlas variant via the generator.

## Required Updates

- `docs/README.md` and `docs/02_system_specs/README.md`: link this spec (done
  with spec landing).
- `packet_schemas.md`: required when the native buffer call lands
  (Iteration 2).
- `system_api.md`: required only if `WindRuntime` exposes a public read/API.
- `event_contracts.md`, `commands.md`: not required in V0 (no events, no
  mutations) — recheck at each iteration.
