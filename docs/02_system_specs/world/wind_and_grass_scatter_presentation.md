---
title: Wind Runtime V0 and Grass Scatter Presentation
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.2
last_updated: 2026-07-14
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
- Grass tuft atlas (albedo + directional shadow) baked as PNG assets by the
  Blender tool pipeline (`tools/grass_atlas`, since v1.1; previously the
  GDScript tuft painter), preloaded at runtime.
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

## Approval Closure

Approved on 2026-06-29 for V0: `WindRuntime` owns and publishes the wind globals,
`WeatherRuntime` drives wind targets, native grass scatter writes the bounded
presentation buffer, and the grass shader consumes the shared wind state.
Remaining open questions are visual tuning or future gameplay hooks, not
blockers for the V0 contract.

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

### Wind direction meanders; grass adds the local life

The complaint that grass "sways in sync" is a *direction* problem, not a timing
one: per-instance phase already decorrelates *when* each tuft moves, but every
tuft bends along the one global `wind_direction`, so the field reads as a single
coherent board. The fix keeps one dominant wind and adds variety in two places.

**Global heading meanders, it does not oscillate.** The heading target is no
longer two summed sines around a base; slow aperiodic noise sets a target
heading that `WindRuntime` steers toward with a bounded angular speed. The wind
slowly *turns* rather than rocking on a predictable period. V0 is deliberately a
**steppe-steady** flow: the dominant direction stays legible so dust, clouds,
sun rays, and grass all agree on "the wind blows this way". Drift amplitude is
small and scales with weather — roughly clear ±6°, cloudy ±14°, overcast ±24°.

**`wind_gustiness` becomes live.** It is authored per weather regime but had no
consumer; `WindRuntime` now smooths the `WeatherRuntime` gustiness target and
publishes it as a global. It drives the heading drift amplitude and turn rate,
the contrast/travel of the gust field, and the amplitude of the grass local
direction spread below. No second wind owner — one more global, read pull-model.

**Grass bends along a local direction, not the global one.** In the grass vertex
shader the bend axis becomes `local_dir = rotate(global_wind_dir, a)`, where `a`
is a **low-frequency aperiodic angle field** sampled at world position (the same
gradient-noise family already used for the gust field). Neighbouring tufts in
one patch lean together; a couple of metres away the patch leans slightly
differently — coherent, never per-tuft-random and never omnidirectional. The
local deviation is **amplified inside gust fronts** (scaled by the existing
`gust` value), so a passing front reads as a swirling eddy while the calm
between fronts settles back along the wind. Its amplitude scales with
`wind_gustiness` to the per-weather anchors above. The dominant lean — and all
of `storm_lean` — stays on the global wind, so a strong wind still reads as a
flow, not chaos.

**Intra-tuft flutter for "each blade lives".** Grass tufts are single billboard
quads (atlas frames); individual blades cannot be moved as geometry. The tip
motion today shears the whole quad rigidly (flutter varies with `UV.y` only). A
secondary high-frequency term that also varies across the quad width (`UV.x`)
plus a slight S-curve makes the tip *ripple* instead of tilting as a board — the
cheap, billboard-bounded way to read as individual blades catching the wind
differently.

**"Stronger wind" means more variety, not more amplitude.** The request for wind
to "affect grass more" is satisfied by the directional spread, gust-front swirl,
and intra-tuft flutter above — never by multiplying the sway amplitude by
strength, which is the banned hair-stretch coupling (see *Strength drives tempo,
not stretch*). Strength keeps driving tempo and the bounded storm lean only.

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

- **Grounded tuft atlas.** Since v1.1 the atlas is baked in Blender with the
  layered-tree camera family (ORTHO, ~28° elevation): blade roots scatter in
  depth on uneven soil, so the silhouette base is ragged instead of a
  ruler-flat cut, and far blades sink into darker shade tiers (the painted
  understory of the old generator, now geometric). Blade colour still ramps
  dark grounded root -> lighter tip. Frame variety is authored by in-bank
  frame type (standard+blooms / sparse / dense / tall-lean) so the field is
  not stamped from one silhouette. The root band sits in the lower quarter of
  the frame near the quad bottom (wind contract: sway weight at the root band
  stays negligible), leaving the band below it for the baked ground-shadow
  zone in the paired shadow atlas.
- **Grass-ladder ground backing.** The ground material's grass-texture
  thresholds are tuned so the density range where native places tufts is
  already a grass carpet — tufts grow out of grass, not bare soil. Same
  `grass_density` field feeds both, so they stay synchronized.
- **Directional baked shadows.** Each atlas frame has a paired frame in
  `grass_tuft_shadow_atlas` (Cycles shadow-catcher pass, shared fixed sun:
  azimuth 315°, elevation 42° — same screen north-east direction as the
  layered tree shadows). `ChunkView` draws them as per-stripe
  `MultiMeshInstance2D` layers that share the tuft multimesh buffers
  (`Z_GRASS_SHADOW + 1`, `overlay_exact` material with wind zeroed), so
  shadows stay glued to their tufts at zero extra buffer cost.
- **Contact-shadow blobs (fallback).** Native still emits flat shadow blobs
  under larger tufts (`shadow_buffer`); the blob layer at `Z_GRASS_SHADOW`
  renders them only when the material set has no shadow atlas wired
  (`shadow_alpha`/`shadow_size_scale` are zeroed while the baked directional
  shadows are active).
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
wind_direction: vec2       # normalized; the one dominant heading (meanders
                           # slowly via steering, Iteration 4)
wind_strength: float       # 0..1 normalized current strength
wind_gust_scroll_px: vec2  # accumulated gust-field scroll offset; advance
                           # speed scales with strength
wind_gustiness: float      # 0..1 gust character from WeatherRuntime; drives the
                           # grass local-direction spread, heading turn rate,
                           # and gust-field contrast (Iteration 4)
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
  - `extra_textures`: `grass_tuft_atlas`, `grass_tuft_shadow_atlas`
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

Since v1.1 the atlas is authored by the Blender bake pipeline in
`tools/grass_atlas` (generator-first authoring stays: sliders live in
`grass_tuft_bake_profile.json`, no hand-painted sprites). It follows the
layered tree bake contract family (`station_peaceful_layered_asset_bake_v1`):
shared fixed sun, angled ORTHO camera, Cycles shadow-catcher pass. Export
targets:

```text
assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png
assets/textures/world/biomes/plains/flora/grass_tuft_shadow_atlas.png
```

Regeneration (bake frames, pack atlases + derived wind/snow/season masks into
`artifacts/blender_grass_tufts`, then copy the albedo/shadow atlases onto the
export targets above — the bake never writes into `assets/` by itself):

```text
blender -b --factory-startup -P tools/grass_atlas/blender_grass_tuft_bake.py -- \
  --out-dir artifacts/blender_grass_tufts/frames
python tools/grass_atlas/postprocess_grass_tuft_atlas.py \
  --frames-dir artifacts/blender_grass_tufts/frames \
  --out-dir artifacts/blender_grass_tufts
```

Fixed frame grid (4 columns x 8 rows, frame 160x120): rows 0-3 are the dry
steppe palette (frames 0-15), rows 4-7 are the orange biofield palette
(frames 16-31). Native placement picks the biofield bank inside strong
`orange_region`; the dry bank elsewhere. Alpha background; the ragged tuft
root band sits in the lower quarter of the frame, the remaining lower band
belongs to the baked directional shadow (shadow atlas frames share the same
grid and camera, so both textures map one quad). Runtime only preloads the
PNGs; runtime atlas painting is forbidden. Contract checks:
`tools/grass_atlas/test_grass_tuft_bake_contract.py`.

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
   candidates inside mountain-edge clearance (`WorldCore.build_grass_scatter_buffer`
   takes the same cross-chunk `mountain_solid_halo` `WorldStreamer` already
   builds for the mountain mask, not just the chunk's own tiles — see
   `mountain_object_occlusion.md` and `packet_schemas.md`), so decorative grass
   cannot peek from under the organic runtime mountain mask.
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
`MultiMeshInstance2D` nodes per non-empty stripe). Mountain presentation sits
BELOW the whole ladder (`Z_MOUNTAIN_TOP/PAGE = 19`, construction-only
`Z_MOUNTAIN_ROOF = 20`, ladder base `21`; see
`mountain_object_occlusion.md`): trees/rocks/player always draw over the
mountain, which is geometrically correct because objects never stand on
mountain tiles and their sprites extend upward from their anchors. The
dedicated construction-roof z also guarantees that every chunk's live BASE is
drawn below every neighbouring chunk's ROOF.
Ground/edge/blob layers sit below the mountain, contact shadows just below
the ladder.

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
- the grass atlases (albedo + directional shadow) are checked-in PNGs
  produced by the Blender bake pipeline (`tools/grass_atlas`); no runtime
  atlas painting;
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

These are follow-ups, not approval blockers for V0:

- Does `WindRuntime` deserve gameplay-readable API now or only at the first
  gameplay consumer? (V0: defer; keep state private to presentation.)
- Orange biofield: is per-instance tint enough, or does the generator export a
  second orange tuft atlas in a later pass?
- Should mid-band tufts get a slightly stronger gust response than low-band
  (parallax feel), and is that authored per band?

Resolved:
- `wind_gustiness` wiring: Iteration 4 makes it a live published global (heading
  drift amplitude/rate, grass local-direction spread, gust-field contrast).
- Global wind character: V0 is steppe-steady (dominant direction stays legible
  for cross-layer agreement); naturalness comes from local grass turbulence, not
  from the global heading wandering.
- Local grass direction field: V0 uses a cheap low-frequency angle offset;
  divergence-free curl noise (truer eddies) is a reserved upgrade if the field
  reads too "sheet-like".
- "Each blade lives": intra-tuft flutter across `UV.x` is in scope for
  Iteration 4 (within the billboard-quad limit; no per-blade geometry).

## Implementation Iterations

### Iteration 0 — Spec landing — DONE

- This spec landed as draft; both doc indexes link it.
- No runtime changes.

### Iteration 1 — Wind runtime + globals + dev-scene proof — DONE

- Add `shader_globals` entries, `WindRuntime` autoload,
  `WorldVisualWindProfile`.
- Port the dev grass shader to read wind globals + the scrolling gust field;
  the dev scene becomes the first consumer (verifies pause, strength,
  direction, gust travel).
- Render probe: irregular gust fronts traveling across the dev field;
  strength 0 freeze.
- Doc updates: `system_api.md` only if a public read surface is added.

### Iteration 2 — Atlas export + native grass buffer + runtime layer — DONE

- Move tuft painting into the generator/export tool; commit the PNG atlas.
- Implement `WorldCore.build_grass_scatter_buffer` (fields mirrored from the
  ground shader; deterministic candidates; interleaved buffer output).
- Add the presentation-only profile/material/shader-family resources.
- Add the chunk grass layer + streamer scheduling on the decorative path.
- Render probes: ladder/biofield density match, seam check, zoom series.
- Doc updates in the same task: `packet_schemas.md` (buffer result shape),
  `terrain_hybrid_presentation.md` (cross-reference to this spec if its ground
  composition section needs the grass layer note).

### Iteration 3 — Tuning and optional LOD — RESERVED

- Density/size/tint tuning via authored data + probes.
- Optional: importance-ordered buffers + zoom-based `visible_instance_count`.
- Optional: orange biofield atlas variant via the generator.

### Iteration 4 — Directional meander + local grass turbulence — DONE

Addresses "grass sways in sync" (see *Wind direction meanders; grass adds the
local life*). Approved direction: steppe-steady global flow + local grass
turbulence + intra-tuft flutter; "stronger" via variety, not amplitude.

- `WindRuntime`: consume and smooth the `WeatherRuntime` gustiness target;
  publish a new `wind_gustiness` global. Replace the heading-drift source — slow
  aperiodic noise sets a target heading, `WindRuntime` steers toward it with a
  bounded angular speed (amplitude/rate scaled by gustiness). No new owner.
- `WeatherRuntime`: heading target becomes a noise-driven meander (drift
  amplitude per regime, small) instead of two summed sines; the season hook is
  untouched.
- Grass shader: bend along `local_dir = rotate(wind_direction, a)`, `a` from a
  low-frequency aperiodic angle field; amplify the deviation inside gust fronts;
  scale amplitude by `wind_gustiness` (per-weather anchors ~±6/±14/±24°). Add an
  intra-tuft flutter term across `UV.x` for blade-level ripple. Keep the dominant
  lean and `storm_lean` on the global wind. No `strength * amplitude` coupling.
- Authored params: the local-direction amplitude curve (gustiness → degrees) and
  the intra-tuft flutter shape live in the grass material `sampling_params`; the
  heading-meander params in `WorldVisualWindProfile` / regime data — single
  authored source, mirrored if a value is needed in two places.
- Probes:
  - directional-variety: across a grass field the local bend directions span a
    measurable spread (not one angle), but the mean stays near the global wind
    (coherent, not omnidirectional);
  - gust-swirl: direction deviation is larger inside active gust fronts than
    between them;
  - intra-tuft: tip displacement varies across blade width, not a rigid shear;
  - regression: `wind_strength = 0` still freezes all motion (calm = rest); no
    `strength * oscillation` product; pausing stops motion; dust/clouds/rays
    still agree on the dominant direction (steppe-steady legibility holds).
- Doc updates: `system_api.md` if `WindRuntime` exposes gustiness publicly; this
  spec's acceptance section; `weather_runtime.md` cross-ref for the
  heading-meander source.

Landed as:
- `wind_gustiness` is a new `shader_globals` float; `WindRuntime` smooths the
  `WeatherRuntime` gustiness target and publishes it, and exposes
  `get_wind_gustiness()` (public read) plus a dev `set_debug_gustiness_override`.
- Heading is steered toward the weather target with a bounded angular speed
  (`HEADING_TURN_RATE_DEG_PER_S`, scaled by gustiness); `WeatherRuntime` replaces
  the two heading sines with a slow value-noise meander (`_heading_meander`).
- Grass shader (`grass_scatter_batch.gdshader`): `local_dir` from a low-frequency
  angle field, gust-coupled swirl, `wind_gustiness`-scaled amplitude, intra-tuft
  flutter across `UV.x`; oscillation on `local_dir`, `storm_lean` on the global
  wind. New authored params live in the grass material `sampling_params`
  (`local_dir_min/max_deg`, `local_dir_field_scale_px`, `local_dir_gust_gain`,
  `intra_tuft_flutter`).
- Probes: `tools/grass_wind_style_probe.gd` (static structure guard:
  gustiness/local_dir/swirl/intra/osc-on-local/storm-on-global/no strength×amp)
  and `tools/grass_wind_dir_probe.gd` (windowed: grass moves under wind, calm
  freezes, close-up saved). Regression: weather/grass/dust/day-night/gdunit green.

### Iteration 5 — Cross-chunk mountain clearance fix — DONE

Bug (2026-07-04, reported after `mountain_object_occlusion.md`'s z-order flip
put the mountain below the grass ladder): grass tufts occasionally rendered
visibly on/inside solid mountain rock. Root cause: `has_grass_mountain_clearance`
only read the current chunk's own `terrain_ids` (out-of-bounds samples silently
read as "not mountain"), so a candidate near a chunk seam got zero clearance
whenever the nearest mountain tile sat in the *neighbouring* chunk — no
clearance-distance value could fix this, confirmed by an identical offending
tuft surviving both a 64px and a 128px clearance. A second, independent flaw
also surfaced while diagnosing this: the old clearance check sampled 8 fixed
points on a ring at `clearance_px`, which could jump clean over a mountain
feature thinner than the sampled radius — worse at *larger* radii, not better.

- Native clearance now reads `mountain_solid_halo` (per-tile solid bytes,
  `halo_side = chunk_size_tiles + 2*halo_radius_tiles`), the same cross-chunk
  halo `WorldStreamer._build_mountain_solid_halo` already builds from the 3x3
  neighbouring chunks for the mountain mask itself — no new computation, just
  reuse of an existing per-chunk-cached array.
- `has_grass_mountain_clearance` now scans every halo tile inside a filled
  disk of radius `GRASS_MOUNTAIN_CLEARANCE_PX` around the candidate instead of
  8 ring points, so a thin mountain feature cannot be skipped over.
- `build_grass_scatter_buffer` signature gained `mountain_halo` +
  `mountain_halo_radius_tiles` params (see `packet_schemas.md`); the
  `WorldStreamer` call site passes `_get_cached_mountain_solid_halo(chunk_coord)`
  (already computed for the mountain mask) straight through.
- Verified via `tools/tmp_grass_mountain_overlap_probe.gd` (windowed, deleted
  after use): sampled every rendered tuft's sprite span against the mountain's
  solid mask at multiple world locations/densities; overlap count went from a
  reproducible non-zero count to 0 across repeated runs and a different
  mountain layout. Regression test added:
  `tools/world_streamer_visual_patch_smoke_test.gd::_assert_grass_scatter_sees_cross_chunk_mountain_halo`
  (a pure-plains target chunk with a synthetic halo carrying a mountain in the
  simulated neighbour chunk; asserts every surviving tuft origin respects
  clearance against the halo, not the chunk's own empty `terrain_ids`).

## Required Updates

- `docs/README.md` and `docs/02_system_specs/README.md`: link this spec (done
  with spec landing).
- `packet_schemas.md`: required when the native buffer call lands
  (Iteration 2; done). Signature + clearance mechanism updated again for
  Iteration 5 (cross-chunk halo); done.
- `system_api.md`: required only if `WindRuntime` exposes a public read/API.
  `get_wind_gustiness()` and debug override entries are documented.
- `event_contracts.md`, `commands.md`: not required in V0 (no events, no
  mutations) — recheck at each iteration.
