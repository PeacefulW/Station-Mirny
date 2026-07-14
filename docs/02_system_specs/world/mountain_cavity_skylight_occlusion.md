---
title: Mountain Cavity Skylight Occlusion V0
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.5
last_updated: 2026-07-14
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/event_contracts.md
  - ../meta/commands.md
  - ../meta/save_and_persistence.md
  - mountain_generation.md
  - world_dynamic_lighting_2d.md
  - world_runtime.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Mountain Cavity Skylight Occlusion V0

## Purpose

Define M8 natural-light behaviour for excavated surface mountain cavities.

The construction roof may fade for player readability, but the physical roof
continues to block open-sky ambient and the directional sun. Darkness therefore
comes from missing natural light, not from a flat final-frame black overlay.
Existing and future local `PointLight2D` sources such as the player torch and
powered lamps must dissolve that darkness without source-specific integration.

This spec owns:
- the derived `sky_exposure` field under an excavated mountain roof;
- bounded daylight ingress from real mountain openings;
- composition rules between skylight occlusion, roof reveal, ambient light,
  the directional sun, and local point lights;
- the runtime, worker, upload, and verification boundaries for M8.

## Gameplay Goal

The player should experience the following:
- opening the construction roof reveals the cavity but does not illuminate it;
- daylight enters softly through a real mouth and fades over roughly one tile;
- deep excavated space retains a weak cool ambient floor rather than a flat
  opaque black fill;
- widening a mouth or creating another real opening increases local daylight;
- turning on a torch or lamp restores colour, relief, and readability inside
  its light pool;
- turning the local light off restores the same natural cave darkness;
- day, night, and weather continue to matter at the mouth, while deep cavity
  light remains dominated by local artificial sources.

## Design Decision

M8 models **mountain skylight exposure**, not a roof contact shadow.

For each mountain-mask sample:

```text
C = immutable closed-roof mask from M7
V = live remaining-mass mask after excavation
E = excavated-under-roof domain = max(C - V, 0)
S = sky_exposure in 0..1
```

Rules:
- `S = 1` means natural light is fully accepted at that sample;
- `S = 0` means direct sun is rejected and open-sky ambient is reduced to the
  authored cave ambient floor;
- `S` is derived only from `C`, `V`, mask geometry, and fixed presentation
  tuning; it does not read roof reveal state;
- `component_reveal_blend b`, `target_component`, and
  `displayed_component` never enter the `S` compute;
- `S` affects natural light only; local point-light contribution is not
  multiplied by `S` and must remain capable of restoring the scene;
- the field is clipped to the visible excavated interior for presentation so
  it cannot darken the closed construction roof, but that visibility clip is
  not a source of skylight truth.

The intended composition is conceptually:

```text
cavity_ambient = min(open_sky_ambient, authored_cave_ambient_floor)
natural = sky_exposure * (open_sky_ambient + directional_sun)
base_world_light = (1 - sky_exposure) * cavity_ambient + natural
final_world_light = base_world_light + local_point_lights
```

The implementation may express this through the existing Godot canvas-light
pipeline rather than this literal formula, but the observable invariants are
binding:
- the roof suppresses natural light;
- no cavity pass darkens already-added local point light;
- no torch/lamp id list, node-name switch, or source-specific exception exists;
- the directional sun and point lights are distinguished through the renderer's
  existing light kind/layer contract, not through scene-tree discovery.

## Scope

M8 includes:
- `z = 0` excavated mountain cavities governed by `mountain_generation.md` M7;
- a derived L8 `sky_exposure` mask at the same sample geometry as `C` and `V`;
- organic mouth-source detection from the `C - V` domain touching open sky;
- bounded geodesic daylight propagation through excavated-under-roof samples;
- current daylight reach of `1.0` tile (`64 px`, `8` samples at the current
  `8 px` mountain-mask step);
- a weak cool deep-cavity ambient floor, initially tuned around `0.12` of the
  day open-sky reference but never allowed to brighten a darker exterior;
- multiple openings, where the strongest valid exposure wins locally;
- cross-chunk continuity through the existing radius-8 mountain halo;
- reuse of the existing mountain mask worker request, epoch, revision,
  inflight/cache key, and bounded visual-upload queue;
- a dedicated skylight presentation path, separate from both mountain/roof
  materials and the torch shadow field;
- numeric, static, visual, and performance probes.

## Out of Scope

M8 does not include:
- gameplay visibility authority, fauna perception, player stress, accuracy,
  stealth, or AI queries; those remain a later ADR-0005 authority iteration;
- any renderer-scraping gameplay API;
- `z < 0` subsurface lighting or underground fog changes;
- physically based global illumination, bounce simulation, ray tracing, or
  volumetric light shafts;
- sun-angle-driven beams entering a mouth;
- new lamp, torch, building, power, fuel, or item behaviour;
- changes to `PlayerTorch`, lamp scenes/components, or light registration;
- changes to M7 cavity connectivity, roof selector membership, reveal timing,
  collision, mining, or persistence;
- mouth dressing, roof lips, jamb art, entrance decals, or facade redesign;
- `LightOccluder2D` geometry;
- a whole-cavity flood fill, all-loaded-chunk rebuild, or per-step rescan;
- a `WORLD_VERSION` bump, canonical packet terrain changes, or new save data;
- global `CanvasModulate` retuning outside the cavity field;
- mod-facing skylight tuning resources in V0.

## Related Contract Boundaries

### Mountain ownership

`mountain_generation.md` M7 remains authoritative for:
- immutable closed roof `C`;
- live remaining mass `V`;
- excavation diff ownership;
- roof reveal selector and `component_reveal_blend b`;
- cavity/opening topology used for gameplay and reveal.

M8 consumes `C` and `V`. It must not write them or become a source for mining,
collision, walkability, roof ownership, or component membership.

### Lighting ownership

`world_dynamic_lighting_2d.md` remains authoritative for:
- `CanvasModulate` open-sky ambient;
- `DirectionalLight2D` sun;
- `PointLight2D` torch/lamps;
- the separate `MountainTorchShadowField` that decides whether rock blocks a
  point light along a line of sight.

M8 answers only: "how much natural sky/sun reaches this roofed excavation?"
It does not answer: "can this torch see around this wall?"

### Gameplay authority

ADR-0005 requires gameplay to read an explicit future light/visibility
authority rather than the renderer. M8 produces presentation-derived data only.
No gameplay system may query an `ImageTexture`, shader, or `ChunkView` material.
A future authority may reuse the same conceptual `sky_exposure` input, but that
requires a separate approved iteration and public API contract.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical, runtime overlay, or visual only? | `sky_exposure` is deterministic derived runtime/presentation data. It is not canonical terrain or gameplay truth in M8. |
| Save/load required? | No. Rebuild from immutable base + excavation diff through the existing M7 mask path. |
| Deterministic? | Native exposure output is deterministic for identical `C`, `V`, geometry, and tuning. Final rendering remains client-local presentation. |
| Must work on unloaded chunks? | No live texture is required for unloaded chunks. A published chunk reconstructs it from base + diff before visual readiness. |
| C++ compute or main-thread apply? | Exposure propagation is native worker compute. Texture/material installation is bounded main-thread apply. |
| Dirty unit | One mountain mask request for the mutated/published chunk plus existing direct seam-neighbour participants. The radius-8 halo bounds the current radius-1 daylight solve. |
| Single owner | `WorldCore` owns deterministic exposure compute; `WorldChunkPacketBackend` owns worker execution/result publication; each `ChunkView` owns only its live derived texture/material. |
| 10x / 100x scale path | Work depends on fixed mask dimensions and fixed reach, not cavity size, component size, or loaded-world size. Zero-dug chunks allocate nothing. |
| Main-thread blocking? | Forbidden. Digging only bumps the existing mask revision and queues worker/apply work. |
| Hidden GDScript fallback? | Forbidden. Native helper absence fails explicitly in the worker path. |
| Could it become heavy later? | Yes. Distance propagation and texture preparation therefore stay native/bounded; only upload and uniform apply stay on the main thread. |
| Whole-world prepass? | Forbidden. Compute is local to one existing mountain halo request. |

## Data Model

### `MountainSkylightExposureResult`

M8 adds one derived native result shape:

```text
{
  "sky_exposure_mask": PackedByteArray, # L8, width * height, 0 dark .. 255 open
  "width": int,
  "height": int,
  "step_px": float,
  "reach_samples": int,
  "source_sample_count": int,
}
```

The new native surface is conceptually:

```text
WorldCore.build_mountain_skylight_exposure(
    closed_roof_mask: PackedByteArray,
    live_mask: PackedByteArray,
    width: int,
    height: int,
    step_px: float,
    reach_samples: int
) -> Dictionary
```

Binding requirements:
- `closed_roof_mask.size() == live_mask.size() == width * height`;
- dimensions and `step_px` match the `MountainHaloMaskResult` that produced
  `C` and `V`;
- invalid input returns an explicit failed/empty result; it does not silently
  use GDScript compute;
- result bytes are derived, transient, never saved, and never appended to
  canonical `ChunkPacketV1`.

### Exposure topology

The native helper derives a binary traversable sample domain from organic
excavation `E = C - V` using a versioned threshold local to this presentation
helper. It then finds real skylight sources where `E` touches open sky
(`C` open) across a cardinal edge.

Propagation rules:
- multi-source bounded geodesic distance through `E` only;
- maximum distance is `reach_samples`;
- diagonal steps may smooth the presentation distance only when both adjacent
  cardinal samples are traversable; diagonal corner-cutting is forbidden;
- diagonal light smoothing never changes cavity gameplay connectivity;
- exposure uses a smooth monotonic falloff from the nearest/strongest source;
- remaining mass `V` blocks propagation;
- a sealed excavated pocket with no real open-sky source receives `S = 0`;
- source detection and propagation operate at mask-sample resolution so the
  visible edge follows the organic mask rather than square tiles.

### Presentation tuning

Current M8 tuning:
- `daylight_reach_tiles = 1.0` (visual trial, reduced from the initial `4.0`);
- `darkness_ramp_gamma = 1.35`, applied after the existing smoothstep so the
  entrance begins with a softer shadow while still reaching the same full
  darkness at the end of the one-tile exposure field;
- `deep_cave_ambient_floor = 0.12`;
- `opening_exposure = 1.0` before organic edge/falloff modulation;
- `edge_softness_samples` is bounded and must not widen exposure through rock.

These are presentation constants, not worldgen settings. Changing them does
not bump `WORLD_VERSION` and does not alter saves. Moving them into a mod-facing
resource is out of V0 scope.

## Runtime Architecture

### Compute path

M8 reuses the M7 mountain worker request:

```text
excavation/publish/load
  -> existing mountain mask revision bump
  -> queued worker request
  -> build V
  -> build optional C for dug halo
  -> build sky_exposure from C and V
  -> one generation-stamped result
  -> bounded texture/material apply
```

Rules:
- no separate worker pool, dispatcher category, or per-frame compute loop;
- `WorldChunkPacketBackend` invokes the native exposure helper only when a
  valid `closed_roof_mask` exists;
- the worker attaches `sky_exposure_mask` to the same mountain result and
  preserves the existing `epoch` / `revision` / supersession rules;
- zero-dug chunks keep the legacy single-mask path and allocate no skylight
  texture or material;
- superseded results cannot commit;
- an exposure result must not make a chunk gameplay-ready later than the
  existing mountain visual readiness gate without an explicit spec amendment.

### Seam contract

The existing mountain halo is radius `8` tiles. The current M8 daylight reach
is radius `1` tile, so every central-chunk sample has ample neighbour context.

Rules:
- publish/mutation refresh uses the same direct seam participants already
  invalidated for M7 masks;
- central output is cropped/applied consistently so adjacent chunks agree;
- no stitched all-view CPU sampling loop is introduced;
- increasing daylight reach beyond the available halo requires a spec
  amendment rather than silent edge leakage.

### Presentation and light composition

M8 uses a dedicated `MountainCavitySkylightField` / shader path.

It must:
- consume `sky_exposure_mask` plus the existing organic cavity/visibility
  inputs needed to avoid drawing on the closed roof;
- combine the displayed tile selector with the already-uploaded all-components
  dug halo as a guarded ownership proof: a 3x3 selector fringe may follow the
  full-resolution organic `C - V` cutout, but a tile owned by a foreign cavity
  must reject that borrowed ownership;
- cover visible cavity floor, internal facade, player, and world objects under
  the roof consistently, while excluding UI;
- suppress/reduce open-sky ambient and directional sun only;
- allow any correctly layered local `PointLight2D` to reduce the darkness;
- remain independent from torch identity, lamp identity, power system, and
  building type;
- hide behind the closed construction roof while remaining logically active;
- remain visible over the revealed cavity when `b = 1` rather than fading out
  with the roof;
- preserve mouth visibility from outside without drawing a rectangle over the
  roof or unrelated ground.

Closed-roof mouth continuity is spatial, not a global field toggle:
- every ready dug chunk keeps its one field sprite available even when the
  displayed-component selector is empty;
- at `b = 0`, coverage is limited to the organic `C - V` excavation that
  intersects the original SOUTH structural-facade band derived from `C`;
- the band height comes from the already-authored construction-roof material
  parameter, not from a mouth decal, fixed tile strip, player distance, or
  per-entrance metadata;
- as `b` opens, the displayed component's full floor/facade coverage is added
  over that persistent mouth coverage; the mouth itself does not pulse;
- the shared reveal scalar remains an O(1) parent presentation update. It must
  not loop over chunk sprites or upload another mask/texture.

Forbidden composition:
- an `unshaded` final dark layer above local lights;
- `blend_mul` with a globally tinted white no-op under `CanvasModulate`;
- screen-luminance heuristics that guess whether a lamp is present;
- enumerating torch/lamp positions and cutting manual radial holes;
- editing `mountain_top_mask_underlay.gdshader` or
  `mountain_cover_overlay.gdshader` to carry skylight state;
- reusing `MountainTorchShadowField` as the skylight owner.

The implementation must prove through a render probe that existing point
lights dissolve the cavity field. If the proposed Godot canvas composition
cannot satisfy that invariant without source-specific coupling, M8.2 is
blocked and the spec must be amended before landing a visual shortcut.

### Roof reveal independence

The roof reveal and skylight lifecycles are separate:
- entering/exiting a cavity changes `target_component`, displayed selector,
  and `b` only;
- those changes do not rebuild `sky_exposure`;
- digging or chunk publication changes `C`/`V` inputs and may rebuild exposure;
- presentation may use the current reveal/visibility mask only to prevent the
  darkness field from drawing over an opaque roof;
- opening the roof must reveal an already-dark cavity, not transition the
  cavity toward open-sky light.

## Event Contracts

M8 adds no `EventBus` signal.

It reuses existing world/mountain invalidation and worker publication paths.
Implementation must not add `mountain_skylight_changed` unless a later
cross-system consumer justifies it and updates `event_contracts.md` in the
same approved iteration.

## Save / Persistence Contracts

No new save field is allowed.

`sky_exposure_mask`, native result metadata, textures, dirty state, and shader
uniforms are transient. After load:
- immutable mountain base recreates `C`;
- excavation diff recreates `V`;
- the existing worker path recreates `sky_exposure`.

No `world.json`, `chunks/*.json`, save collector, save applier, or migration
change belongs to M8.

## Performance Class

| Operation | Class | Dirty unit | Budget / rule |
|---|---|---|---|
| Dig input | interactive | one tile + existing M7 invalidation | no exposure compute or texture upload in the input frame |
| Exposure propagation | background native worker | one fixed mountain halo request | bounded by mask dimensions and `reach_samples`; no cavity-size dependence |
| Exposure texture apply | background main-thread apply | one completed chunk result | reuse existing mountain visual-upload queue/budget |
| Roof enter/exit | interactive presentation | existing reveal uniforms only | zero exposure rebuilds |
| Per-frame rendering | GPU presentation | visible cavity pixels | bounded shader path; no CPU per-tile loop |
| Publish/load reconstruction | streaming/boot | published chunk + seam participants | existing mountain visual readiness path |

Target scale:
- a fully excavated cavity spanning many chunks;
- multiple mouths across different chunks;
- rapid one-tile mining at chunk seams;
- all currently loaded mountain chunks carrying excavation diffs.

The cost must scale with changed/published chunk masks, not total cavity area,
component membership count, or loaded-world chunk count.

Forbidden runtime paths:
- GDScript BFS/Dijkstra over mask samples;
- synchronous `Image`/`ImageTexture` creation in `try_harvest_at_world`;
- all-component or all-loaded-chunk exposure rebuild;
- per-player-step exposure recompute;
- per-light CPU holes or scene-tree light scans;
- `LightOccluder2D` creation/rebuild;
- a second unbudgeted worker/thread loop;
- whole-screen readback or renderer luminance sampling.

## Modding / Extension Points

M8 V0 introduces no mod-facing resource or registry entry.

Compatibility requirements:
- any future local light that follows the existing point-light layer contract
  must dissolve cave darkness automatically;
- no hardcoded list of base-game torch/lamp ids is permitted;
- a future tuning resource may expose reach/ambient/colour only through a
  separate approved extension iteration.

## Files Allowed For Implementation

### M8.1 — Derived exposure compute

New:
- `tools/mountain_cavity_skylight_mask_smoke_test.gd`

Modified:
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/bin/station_mirny.windows.template_debug.x86_64.dll`
- `gdextension/bin/station_mirny.windows.template_release.x86_64.dll`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/world/mountain_generation.md`
- `docs/02_system_specs/world/world_runtime.md`
- this spec

### M8.2 — Light-aware presentation

New:
- `core/systems/world/mountain_cavity_skylight_field.gd`
- `assets/shaders/mountain_cavity_skylight_field.gdshader`
- `tools/mountain_cavity_skylight_field_static_smoke_test.gd`
- `tools/mountain_cavity_skylight_field_probe.gd`
- `tools/mountain_cavity_skylight_field_perf_probe.gd`

Modified:
- `scenes/world/world_runtime_v0.tscn`
- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `docs/02_system_specs/world/world_dynamic_lighting_2d.md`
- this spec

### M8.3 — Closed-roof mouth continuity

Modified:
- `core/systems/world/mountain_cavity_skylight_field.gd`
- `assets/shaders/mountain_cavity_skylight_field.gdshader`
- `core/systems/world/chunk_view.gd`
- `tools/mountain_cavity_skylight_field_static_smoke_test.gd`
- `tools/mountain_cavity_skylight_field_probe.gd`
- `tools/mountain_cavity_skylight_field_perf_probe.gd`
- `docs/02_system_specs/world/mountain_generation.md`
- `docs/02_system_specs/world/world_dynamic_lighting_2d.md`
- this spec

### M8.4 — One-tile entrance ramp softness

Modified:
- `assets/shaders/mountain_cavity_skylight_field.gdshader`
- `tools/mountain_cavity_skylight_field_static_smoke_test.gd`
- `tools/mountain_cavity_skylight_field_probe.gd`
- `docs/02_system_specs/world/world_dynamic_lighting_2d.md`
- this spec

M8.4 may reshape only the presentation curve inside the existing exposure
field. It must not change `MOUNTAIN_SKYLIGHT_REACH_TILES`, native propagation,
mask geometry, coverage ownership, or roof-reveal composition.

Implementation may touch a listed file only in the current iteration's scope.
M8.1 must not pre-land M8.2 presentation code.

## Files Forbidden For Implementation

- `assets/shaders/mountain_top_mask_underlay.gdshader`
- `assets/shaders/mountain_cover_overlay.gdshader`
- `core/systems/world/mountain_torch_shadow_field.gd`
- `assets/shaders/mountain_torch_shadow_field.gdshader`
- `core/entities/player/player_torch.gd`
- `core/systems/building/**`
- `core/systems/power/**`
- `core/entities/components/power_source_component.gd`
- `core/entities/components/power_consumer_component.gd`
- `data/buildings/**`
- `data/balance/building_balance.gd`
- `data/balance/building_balance.tres`
- `data/balance/power_balance.gd`
- `data/balance/power_balance.tres`
- `core/autoloads/event_bus.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/autoloads/save_io.gd`
- `core/systems/world/world_diff_store.gd`
- `core/systems/world/world_runtime_constants.gd`
- any `z != 0` or underground-fog path
- combat, AI, UI, progression, localization, and lore files
- deleted legacy mountain-shadow files

If implementation proves that a forbidden file is genuinely required, stop
and amend/approve the spec before touching it.

## Acceptance Criteria

### Exposure compute

- [ ] identical `C`, `V`, dimensions, step, and tuning produce byte-identical
      `sky_exposure_mask` output;
- [ ] a sealed `C - V` pocket with no cardinal open-sky source has exposure
      `0` throughout its interior;
- [ ] a single mouth produces monotonic exposure falloff to `0` by the
      configured one-tile reach;
- [ ] widening a mouth never lowers exposure at an already reachable sample;
- [ ] adding a second mouth raises or preserves exposure in its local region;
- [ ] remaining mass blocks propagation and diagonal-only contact does not
      leak skylight through a corner;
- [ ] central-chunk output is identical when the same case is evaluated from
      either side of a chunk seam;
- [ ] zero-dug chunks do not request or allocate an exposure result;
- [ ] invalid input fails explicitly and no GDScript fallback runs.

### Roof independence

- [ ] changing `component_reveal_blend b` from `0` to `1` causes zero exposure
      worker requests and does not change exposure bytes;
- [ ] opening the construction roof reveals a cavity with the same natural
      darkness it had while hidden;
- [ ] closing the roof hides the field behind the roof and does not draw a
      rectangular dark layer over the roof surface;
- [ ] with the roof closed and the player outside, the real mouth/floor under
      the original facade remains naturally dark while deep covered pixels,
      the closed roof surface, and unrelated exterior ground remain unchanged;
- [ ] opening/closing the roof does not change mouth darkness; it only reveals
      or hides the rest of the same field;
- [ ] separate/foreign cavity reveal state cannot alter another cavity's
      exposure.

### Natural and artificial light

- [ ] daytime mouth region is measurably brighter than a sample beyond the
      configured reach with all local lights off;
- [ ] deep-cavity ambient remains above opaque black but below the daytime
      mouth sample;
- [ ] cave ambient never makes a sample brighter than the current exterior
      ambient at night or during severe overcast;
- [ ] the existing player torch measurably raises luma and restores colour in
      a deep-cavity sample;
- [ ] an existing stationary lamp/point light produces the same class of
      local restoration without M8 source-specific code;
- [ ] turning either point light off restores the same baseline cavity
      darkness;
- [ ] directional sun remains suppressed under the roof inside a point-light
      pool; the point light adds local illumination without reopening skylight;
- [ ] player, floor, internal facade, and representative world objects under
      the roof read consistently dark when unlit and consistently restored
      inside a local point-light pool;
- [ ] the closed roof and unrelated exterior ground remain unchanged.

### Visual quality

- [ ] no square-tile boundary, black rectangle, clear-colour hole, or chunk
      seam is visible;
- [ ] falloff follows the organic excavation/mouth contour;
- [ ] no multiply-pass whole-world darkening appears under `CanvasModulate`;
- [ ] roof reveal animation does not pulse cavity brightness;
- [ ] multiple mouths blend without a hard maximum ring or visible band.
- [ ] within the existing one-tile mouth ingress, unlit luma decreases
      monotonically from a soft entrance shadow through a middle sample to the
      unchanged full-dark endpoint, without moving that endpoint deeper;

### Performance

- [ ] mining input frame performs no exposure BFS, mask-wide GDScript loop,
      `ImageTexture` upload, or scene-tree light scan;
- [ ] one dig invalidates only the existing target/seam mountain mask work;
- [ ] exposure worker cost is reported separately and remains bounded for the
      fixed mask dimensions/reach;
- [ ] rapid seam mining introduces no `FrameBudget` hitch attributable to M8;
- [ ] roof enter/exit produces no exposure worker requests;
- [ ] no `LightOccluder2D`, node-per-edge geometry, or all-loaded-chunk rebuild
      exists in the landed path.

### Persistence and governance

- [ ] save payloads contain no skylight field, texture, tuning, or dirty state;
- [ ] loading the same base + diff reconstructs the same exposure bytes;
- [ ] no `WORLD_VERSION` bump is introduced;
- [ ] no gameplay system reads renderer/shader state;
- [ ] canonical docs named in Required Canonical Updates are updated or closed
      with grep evidence in the same implementation iteration.

## Failure Cases / Risks

- **Local lights remain dimmed.** A final dark overlay composited after point
  lights violates the core requirement. M8.2 must stop rather than ship manual
  torch/lamp holes.
- **Roof dark rectangle returns.** Mixing skylight state into the main mountain
  or roof-cover shader repeats the prior regression class. The dedicated field
  and explicit clipping boundary are mandatory.
- **Diagonal light leaks.** Unrestricted 8-neighbour propagation can bridge two
  diagonal void samples. Diagonal steps require cardinal clearance.
- **Chunk-edge discontinuity.** A solve without the radius-8 halo will disagree
  across seams. Central output must use the existing halo context.
- **GPU fill cost.** A world overlay above many world objects can become costly.
  M8.2 requires a dedicated fill/perf probe and must clip outside visible
  `C - V` regions.
- **Double darkness.** Existing torch shadow occlusion and new skylight
  occlusion answer different questions. They must not compound on open ground
  or suppress the same point-light contribution twice.
- **Future authority drift.** Presentation exposure must not quietly become
  gameplay truth. A gameplay consumer requires a separate explicit authority
  contract.

## Required Canonical Updates

### This spec task

- `docs/README.md` — add the approved spec to the canonical map.
- `docs/02_system_specs/README.md` — add the approved spec to the world/runtime list.

### M8.1 landing

- `docs/02_system_specs/meta/system_api.md` — document
  `WorldCore.build_mountain_skylight_exposure(...)`.
- `docs/02_system_specs/meta/packet_schemas.md` — document
  `MountainSkylightExposureResult` and the optional worker-result field.
- `docs/02_system_specs/world/mountain_generation.md` — add M8 consumption of
  `C` and `V`, keeping reveal independent.
- `docs/02_system_specs/world/world_runtime.md` — grep the mountain worker
  result wording and update it if it enumerates derived outputs.

### M8.2 landing

- `docs/02_system_specs/world/world_dynamic_lighting_2d.md` — add mountain
  cavity skylight ownership and light-composition invariants.
- this spec — record landed status and final proof artifacts.

### M8.4 landing

- `docs/02_system_specs/world/world_dynamic_lighting_2d.md` — record the
  presentation-only entrance-ramp invariant without changing light ownership.
- this spec — record the fixed one-tile reach, curve tuning, and proof
  artifacts.

### Required grep closure in both implementation iterations

- `event_contracts.md` for mountain/skylight events: expected no new event;
- `commands.md` for excavation mutation: expected unchanged;
- `save_and_persistence.md` and `packet_schemas.md` for skylight persistence:
  expected no save field;
- `system_api.md` for public exposure reads: expected no gameplay read surface
  in M8;
- missing legacy `docs/00_governance/PUBLIC_API.md` and
  `docs/02_system_specs/world/DATA_CONTRACTS.md` must not be recreated; use the
  living meta contracts indexed by `docs/README.md`.

`not required` without current-session grep evidence is invalid.

## Open Questions

No design-intent questions remain after the approved brainstorming brief.

The exact implementation file scope, native result shape, and two-iteration
boundary were approved for M8.1 implementation on 2026-07-14.

## Implementation Iterations

### M8.1 — Derived Skylight Exposure Mask

Goal: produce and publish deterministic, seam-correct `sky_exposure` from the
existing M7 `C` and `V` masks without changing visible lighting yet.

Deliverables:
- native bounded exposure helper;
- worker-result integration under existing epoch/revision rules;
- per-chunk derived texture/data apply path;
- numeric/seam/fallback/static tests;
- required `system_api.md`, `packet_schemas.md`, and mountain-spec updates.

Implementation evidence (2026-07-14):
- the native helper, existing-worker integration, bounded `ChunkView` data and
  texture ownership, diagnostics, and M8.1 smoke test are implemented;
- Windows `template_debug` and `template_release` native builds completed
  successfully;
- executing the headless Godot smoke test remains a manual handoff because no
  Godot executable is installed or available on `PATH` in the implementation
  environment;
- no M8.2 field, shader, scene wiring, or visible light composition landed.

Stop after M8.1 closure. Do not land the visual field in the same task.

### M8.2 — Light-Aware Cavity Presentation

Goal: suppress natural light under the roof while allowing all compatible
local point lights to restore illumination.

Deliverables:
- dedicated world overlay and shader;
- scene wiring and organic visibility clipping;
- torch and stationary-lamp render probes;
- day/night/overcast and roof-reveal checks;
- GPU/CPU performance probe;
- required lighting-spec update and final M8 proof record.

M8.2 may start only after M8.1 is closed and the light-composition probe design
still demonstrates that arbitrary point lights can dissolve the field without
source-specific coupling.

Implementation evidence (2026-07-14):
- `MountainCavitySkylightField` and its dedicated canvas shader are wired into
  the live world scene without modifying the mountain surface, construction
  roof, torch shadow, player torch, building, power, save, or event owners;
- the field reuses the ready `ChunkView` GPU textures for `C`, `V`, `S`, and the
  displayed selector, with one non-overlapping central-chunk sprite and no
  per-frame CPU loop or scene-tree light scan;
- source binding runs only after the existing budgeted mountain visual upload
  or atomic selector commit; reveal blend is an O(1) parent-modulate update and
  causes no exposure request or recompute;
- the custom light pass rejects `LIGHT_IS_DIRECTIONAL` and restores the
  pre-field screen contribution for generic non-directional point lights, with
  no torch/lamp identifiers;
- `tools/mountain_cavity_skylight_field_static_smoke_test.gd`,
  `tools/mountain_cavity_skylight_field_probe.gd`, and
  `tools/mountain_cavity_skylight_field_perf_probe.gd` cover static ownership,
  directional-vs-point composition, selector/roof clipping, and bounded CPU/GPU
  presentation cost;
- session-local static contract verification passed for scene/resource wiring,
  the two bounded sync points, O(1) field reveal, reused texture ownership, and
  absence of per-frame scans, `LightOccluder2D`, source identities, duplicate
  mask uploads, or forbidden-owner changes; `git diff --check` also passed;
- the first live Godot 4.7 run exposed an invalid early `return` in the canvas
  `light()` processor, which made the unit chunk sprite render as a white
  rectangle; the processor now uses a complete `if/else` branch and the static
  smoke test rejects future bare `return;` regressions;
- subsequent live screenshots exposed direct multiplication by the 64 px
  displayed-component selector as alternating bright/dark squares on the
  organic floor and facade. The field now reuses the existing tile dug-halo
  texture for guarded active/foreign ownership, while `C - V` remains the final
  8 px organic pixel proof. The facade finds and interpolates one south-edge
  crossing instead of taking the maximum of discrete foot samples, preventing
  repeated mask-step contour bands. This adds no texture upload, selector
  compute, scene-tree scan, or per-frame CPU path;
- `mountain_cavity_skylight_field_static_smoke_test.gd` passes in headless
  Godot 4.7; the windowed render probe passes with deep luma `0.04737` both with
  local lights off and with directional sun on, moving point-light restoration
  to `0.54108`, stationary point-light restoration `0.04737 -> 0.44268`, and no
  mouth/exterior/roof-closed regression;
- the Godot 4.7 performance probe passes: 15 chunk-source applies average
  `0.2628 ms` each, 10,000 O(1) reveal updates average `0.511 us`, and the
  synthetic frame averages are `2.612 ms` baseline, `2.805 ms` field-only, and
  `2.887 ms` with a generic point light.
- the targeted organic-clipping follow-up render probe passes with the selected
  organic fringe darkened `0.18917 -> 0.04737`, a separate foreign cavity held
  at `0.18917`, the internal facade darkened `0.18917 -> 0.04737`, and the roof
  held at `0.18917`; the final 15-chunk performance run passes at
  `0.3101 ms/chunk` apply, `0.455 us` O(1) reveal, `0.636 ms` field-only, and
  `0.678 ms` field plus generic point-light average.
- the current visual tuning trial reduces
  `MOUNTAIN_SKYLIGHT_REACH_TILES` from `4` to `1`, so exposure reaches the deep
  cave floor after `64 px / 8` mask samples instead of `256 px / 32`; this
  changes no native algorithm, packet shape, owner, save data, or world version.

### M8.3 — Closed-Roof Mouth Continuity

Goal: keep the same physical cavity darkness visible through the real mountain
mouth while the construction roof is closed, without adding an authored mouth
shadow, a second mask texture, or reveal-time CPU work.

Implementation contract:
- the ready per-chunk field sprite is not gated by displayed-selector sample
  count or by `b > 0`;
- closed coverage is derived in the field shader from `C - V` intersected with
  the original `C` structural-facade band;
- the facade height is read from the existing construction-roof material
  parameter;
- the existing parent-level reveal scalar blends from closed-mouth coverage to
  displayed-component coverage in O(1), with no per-sprite loop;
- generic `PointLight2D` restoration remains the same in both states.

Implementation evidence (2026-07-14):
- ready dug chunks now remain active with an empty displayed selector; the
  shared parent red-modulation channel carries `b` to every unit-white chunk
  sprite while alpha remains available for closed-mouth coverage;
- the shader derives the closed mouth from `C - V` plus the bounded SOUTH-edge
  search over `C`, and `ChunkView` forwards the facade height from the existing
  construction-roof material; no new mask texture, entrance metadata, player
  lookup, or per-frame CPU path was added;
- Godot 4.7 `--check-only` passes for `ChunkView`, the field owner, and both
  updated probes; the headless static smoke test passes;
- the windowed render probe passes: closed mouth luma changes
  `0.18917 -> 0.06107`, covered deep and roof samples remain unchanged, the
  same generic point light restores the closed mouth to `0.38007`, and opening
  holds mouth luma at `0.06107` while revealing deep darkness at `0.04737`;
- the 15-chunk performance probe passes with `0.4388 ms/chunk` source apply,
  `0.442 us` average for 10,000 O(1) reveal updates, and synthetic averages of
  `0.700 ms` closed-mouth, `0.637 ms` fully revealed, and `0.771 ms` revealed
  with a generic point light;
- final visual confirmation in the live authored mountain entrance remains a
  manual human handoff because the synthetic probe does not reproduce the
  complete production roof albedo/warp composition.

### M8.4 — One-Tile Entrance Ramp Softness

Goal: retain the exact one-tile natural-light reach while making its entrance
transition slightly more gradual: a light shadow at the lip, progressively
stronger darkness through the tile, and the same full cave darkness beyond it.

Implementation contract:
- `sky_exposure`, coverage masks, native propagation, and the configured
  `MOUNTAIN_SKYLIGHT_REACH_TILES = 1` remain unchanged;
- the shader applies a monotonic `darkness_ramp_gamma = 1.35` only after the
  existing normalized smoothstep darkness value;
- curve endpoints remain exact (`0 -> 0`, `1 -> 1`), so no light leaks into
  deep cave pixels and no shadow appears outside organic coverage;
- point-light restoration and closed/open roof composition remain unchanged;
- no new texture, mask sample, CPU loop, worker request, mutable cache, or
  source-specific light integration is allowed.

Acceptance evidence required:
- a windowed render probe samples at least three positions along the existing
  one-tile ingress and proves a strictly monotonic soft-to-dark luma ramp;
- the deep endpoint, roof, exterior, closed-mouth continuity, directional-sun
  rejection, and generic `PointLight2D` restoration retain their M8.3 class;
- the existing 15-chunk performance probe remains bounded with no new CPU
  presentation work.

Implementation evidence (2026-07-14):
- the shader now applies `pow(natural_darkness_linear, 1.35)` after the existing
  smoothstep; its `0` and `1` endpoints, all masks, coverage paths, and the
  native exposure result remain unchanged;
- Godot 4.7 `--check-only` passes for the updated static and render probes, the
  headless field static smoke test passes, and the native mask smoke test still
  passes with `MOUNTAIN_SKYLIGHT_REACH_TILES = 1`;
- the windowed render probe passes with unlit ingress luma decreasing
  monotonically from `0.17994` near the lip to `0.13323` mid-tile, `0.06835`
  near the tile endpoint, and the unchanged deep floor `0.04737`; the disabled
  field reference at both new ingress samples remains `0.18917`;
- closed and open roof states produce the same ingress samples, the generic
  mouth point light restores luma `0.06835 -> 0.38091`, directional sun leaves
  deep luma at `0.04737`, and roof/exterior guard samples remain unchanged;
- the 15-chunk performance probe passes with `0.3235 ms/chunk` source apply,
  `0.446 us` average for 10,000 O(1) reveal updates, `0.905 ms` closed-mouth,
  `0.967 ms` fully revealed, and `1.009 ms` revealed with a generic point light.
