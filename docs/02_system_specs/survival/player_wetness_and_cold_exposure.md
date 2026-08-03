---
title: Player Wetness, Cold Exposure, and Wet Ground V0
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.1
last_updated: 2026-08-03
related_docs:
  - survival_core.md
  - ../world/humidity_and_rain_runtime.md
  - ../world/seasons_and_temperature_runtime.md
  - ../world/terrain_hybrid_presentation.md
  - ../ui/ui_ux_foundation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Player Wetness, Cold Exposure, and Wet Ground V0

## Purpose

Turn authoritative rain, global air temperature, and wind into readable
expedition pressure without adding damage or movement penalties yet. The player
can become wet under open sky, dry under cover, and accumulate cold load from
air temperature, wind, and wet clothing. A cheap derived ground-material mask
makes the same rain legible through wet soil, sparse puddles, and analytic drop
impact rings.

## Gameplay Goal

Rain should stop being only a screen effect. The player should understand:

- exposure under open sky has a cost;
- a roof immediately stops further soaking;
- shelter provides recovery instead of merely hiding particles;
- cold air, wind, and wet clothing reinforce each other;
- the ground remembers rain briefly enough for the world to feel physically
  responsive.

V0 communicates pressure but does not punish with health damage, death, speed
loss, stamina loss, or equipment degradation.

## Scope

- Per-player authoritative `wetness` and `cold_load` values in `0..1`.
- Wetness gain from authoritative rain intensity only while the player is under
  authoritative open sky.
- Drying in dry exterior air, faster drying under cover, and fastest recovery
  in a powered indoor sanctuary.
- Cold-load target derived from authoritative global air temperature, current
  wind strength, wetness, open-sky exposure, and powered-shelter state.
- Bounded smoothing toward the cold target so warnings do not flicker with one
  weather sample.
- A shared O(1) open-sky query used by both player exposure and rain
  presentation; gameplay never reads shader visibility.
- Optional `exposure` data in `PlayerSaveData`, with old saves defaulting to dry
  and warm.
- One compact, threshold-revealed exposure row inside the existing top-left
  survival plate.
- A world-space wet-ground mask inside the existing shared ground material.
- Sparse shallow puddle regions derived from the same mask.
- Analytic rain-impact rings evaluated in the shader, with no per-drop nodes or
  CPU impact list.
- Data-authored tuning resources for player exposure and ground presentation.
- Static/headless probes for authority, persistence, HUD wiring, open-sky
  gating, and bounded presentation architecture.

## Out of Scope

- Health damage, death, hypothermia stages, overheating, movement/stamina
  penalties, animation changes, or audio.
- Snow, hail, freezing rain, ice, frozen puddles, or precipitation-kind changes.
- Clothing insulation, waterproof equipment, heaters, campfires, consumables,
  skills, or crafting content.
- Per-tile water volume, persistent puddle identities, flooding, rivers, mud
  movement cost, crop moisture, machine water ingress, or footprint decals.
- Biome, altitude, latitude, or time-of-day temperature terms.
- Per-room wet-ground exclusion masks. Building floors and world draw order may
  visually cover the shared ground response; true roof-local water accumulation
  requires a later bounded spatial-overlay spec.
- Multiplayer transport and prediction wiring.
- World generation, terrain ids, walkability, chunk packet changes, runtime
  diffs, or a `world_version` bump.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Player `wetness` and `cold_load` are authoritative survival state. Open-sky is a derived gameplay context. Ground wetness, puddles, and impact rings are visual-only presentation. |
| Save/load required? | Yes for the two per-player survival values through optional `PlayerSaveData.exposure`. Open-sky and all ground presentation reconstruct and are not saved. |
| Deterministic? | Player values use authoritative inputs and bounded cadence scalar rules with accumulated elapsed time. Ground pattern is deterministic in world space; impact animation is client-local presentation. |
| Must it work on unloaded chunks? | Player state is independent of chunks. Ground presentation exists only where the shared visible ground material renders; no unloaded-chunk state exists. |
| C++ compute or main-thread apply? | O(1) scalar GDScript per player plus fragment-shader presentation. There is no tile/object bulk compute. |
| Dirty unit | One player exposure sample; one shared ground-material uniform update. |
| Single owner | `PlayerExposureComponent` writes its player's wetness/cold load. `WeatherRuntime` and `WindRuntime` remain read-only inputs. `GroundWetnessPresenter` owns only a transient visual accumulation scalar. |
| 10x / 100x scale path | CPU cost is O(players), not O(world/chunks/tiles). Ground cost is one existing material pass, independent of map size and puddle count. |
| Main-thread blocking risk | None beyond fixed scalar reads/writes and shader-uniform publication. |
| Hidden fallback? | None. Missing balance/profile resources fail during scene/bootstrap validation; no runtime load or alternate simulation is added. |
| Could it become heavy later? | Local water accumulation/flooding could. It requires native chunk/subchunk overlay compute and budgeted dirty publication, and is forbidden in V0. |
| Whole-world prepass? | No. |

## Authority and Data Model

### `PlayerExposureComponent`

Each player owns one component:

```text
PlayerExposureState
{
  wetness: float,   # 0 dry .. 1 soaked
  cold_load: float, # 0 comfortable .. 1 severe exposure warning
}
```

Both fields are authoritative player survival state. They are clamped, changed
only by the component, and persisted. Later consequences may read them through
typed getters but may not write them directly.

### Open-sky context

A shared stateless resolver derives whether the player is exposed to rain:

```text
is_open_sky =
  current_z == 0
  and not BuildingSystem.is_cell_indoor(player_grid_cell)
  and not current_mountain_cover
```

- The resolver uses existing authoritative world/building reads.
- It caches stable service references and performs no per-tick scene-tree scan.
- `RainOverlay` and `PlayerExposureComponent` use the same resolver.
- Ground presentation remains global visual response and does not become the
  gameplay open-sky authority.

Current integration boundary: `world_runtime_v0.tscn` has no `BuildingSystem`,
`BaseLifeSupport`, or z-level owner. Mountain cover is therefore the currently
reachable shelter source. Built/powered shelter behavior and explicit z gating
are implemented and probe-covered, but remain unreachable in that shipping
scene until those existing systems receive a separate world-shell integration.
The resolver can refresh a later `BuildingSystem` from the authoritative
`rooms_recalculated` publication without adding a per-frame scene-tree scan.

### Authored player tuning

`PlayerExposureBalance` contains, at minimum:

```text
id: StringName
tick_interval_seconds: float
rain_wetness_rate_per_second: float
dry_open_rate_per_second: float
dry_covered_rate_per_second: float
dry_powered_indoor_rate_per_second: float
controlled_indoor_temperature_c: float
wind_chill_max_c: float
wet_chill_max_c: float
covered_wet_chill_multiplier: float
cold_safe_temperature_c: float
cold_severe_temperature_c: float
cold_accumulation_rate_per_second: float
warm_recovery_rate_per_second: float
wetness_visible_threshold: float
wetness_warning_threshold: float
wetness_critical_threshold: float
cold_visible_threshold: float
cold_warning_threshold: float
cold_critical_threshold: float
```

All values validate at boot. V0 tuning targets readable proof within roughly one
minute of heavy rain and visible recovery after entering shelter; final survival
balance remains a later playtest pass.

## Runtime Rules

### Wetness

At each bounded component tick:

```text
if open_sky and rain_intensity > 0:
  wetness += rain_intensity * rain_wetness_rate * dt
elif powered_indoor:
  wetness -= dry_powered_indoor_rate * dt
elif covered:
  wetness -= dry_covered_rate * dt
else:
  wetness -= dry_open_rate * dt
```

Rain kind must be `RAIN`; snow does not reuse the liquid wetness rate.

This reservation is now satisfied rather than pending. Since
[`snow_precipitation_runtime.md`](../world/snow_precipitation_runtime.md)
landed, `WeatherRuntime` publishes `SNOW` below the authored freezing threshold,
and the existing `kind == RAIN` condition above means falling snow adds no
wetness without any change to this component. The same holds for
`GroundWetnessPresenter`, which already gated accumulation and its shared-material
publication on `kind == RAIN`, so snow dries the ground instead of puddling it.

### Cold load

The component derives a target effective temperature:

```text
base_temperature = powered_indoor
  ? controlled_indoor_temperature_c
  : WeatherRuntime.get_temperature_c()
wind_chill = open_sky
  ? WindRuntime.current_strength * wind_chill_max_c
  : 0
wet_chill = wetness * wet_chill_max_c
wet_chill *= open_sky ? 1 : covered_wet_chill_multiplier
effective_temperature = base_temperature - wind_chill - wet_chill
cold_target = inverse_lerp(cold_safe_temperature_c,
                           cold_severe_temperature_c,
                           effective_temperature)
```

`cold_load` approaches `cold_target` through authored accumulation/recovery
rates. V0 only exposes the value and warning thresholds. It never mutates HP,
oxygen, movement, stamina, fatigue, or death state.

#### Deep-winter saturation (recorded limitation)

The seasonal amplitude pass in
[`seasons_and_temperature_runtime.md`](../world/seasons_and_temperature_runtime.md)
Iteration 5 moved the annual minimum outside-air temperature to `-40 C`. As part
of that pass `cold_severe_temperature_c` was retuned from `-14 C` to `-30 C`.

The linear `inverse_lerp` above cannot serve both the damp-discomfort band and a
`-40..-60 C` lethality band. The retune restores a readable gradient across the
phases where the warning is actionable, and deep winter deliberately saturates:

Measured against the live seasonal tuning, where the two shoulder phases span
`-8 .. +2 C` at their centre after the Iteration 7 rebalance:

| Case (converged) | `cold_load` |
|---|---:|
| `core:warm` `+14 C`, dry, calm | `0.000` |
| `core:warm` `+14 C`, soaked, full wind | `0.368` |
| shoulder `+2 C`, dry, calm | `0.158` |
| shoulder `+2 C`, soaked, full wind | `0.684` |
| shoulder `-8 C`, dry, calm | `0.421` |
| shoulder `-8 C`, soaked, full wind | `0.947` |
| `core:cold` `-30 C`, dry, calm | `1.000` |
| `core:cold` `-40 C`, soaked, full wind | `1.000` |

The colder shoulders spread the readout across the whole year rather than
compressing it: summer storms now register at all, and a shoulder phase climbs
from `0.16` to `0.95` purely through exposure before winter pins it.

Inside the cold phase, wind and wetness therefore stop being distinguishable.
This is accepted as correct signalling for a warning-only V0 - at `-40 C` the
message "do not be out here unprotected" is true - and is recorded rather than
hidden. Making exposure terms matter again inside deep winter requires a
non-linear response curve plus insulation/equipment terms, which belong to the
cold-consequences iteration of this spec, not to a tuning pass.

## Save / Persistence Contract

`PlayerSaveData` gains one optional additive section:

```text
"exposure"?: {
  "wetness": float,
  "cold_load": float,
}
```

- `SaveCollectors` calls the component's `save_state()` only when present.
- `SaveAppliers` calls `load_state()` only when both player and component exist.
- Missing/invalid data defaults to `0` for both values.
- Open-sky, current target temperature, warning presentation, ground wetness,
  puddle pattern, and impact animation are not saved.
- This is player-state evolution only and does not change `world_version` or
  chunk-diff schemas.

## HUD Presentation Contract

Visual thesis: quiet suit telemetry condenses only when the body begins to lose
comfort; a droplet and a cold glyph share the existing survival plate, while the
single critical alarm channel remains reserved for oxygen and failed shelter.

Content plan:

1. Keep the existing oxygen/health hierarchy dominant.
2. Reveal wetness or cold only above their authored visible thresholds.
3. Show one compact icon-plus-percent group per active axis; no new card and no
   permanent explanatory sentence.
4. Use existing palette tiers for normal/warning/severe values and code-drawn
   glyphs. No raw player-facing text or new localization key is required.

Interaction thesis:

- The row appears/disappears through a short restrained alpha transition.
- Values and color move at the component cadence; no pulse, shake, blink, or
  screen vignette is added.
- Powered shelter recovery quiets and eventually removes the row, reinforcing
  return-home relief.

## Wet Ground Presentation Contract

Visual thesis: rain lays a cold, thin skin over low soil—broad irregular dark
patches, sparse shallow puddle plates, and fine silver impact rings—without
turning the world blue, glossy everywhere, or visually noisy.

### Architecture

- The mask is evaluated inside the existing shared plains ground shader.
- One `GroundWetnessPresenter` reads global rain intensity, integrates one
  transient `ground_wetness` scalar, and updates shared material uniforms.
- The presenter receives a boot-prepared `GroundWetnessProfile`; it performs no
  runtime resource load.
- Existing world-space `soil_field`, `shade_a`, `top_macro`, and `path_open`
  fields define low basins and wet patches, so the mask adds no new FBM field
  and remains seamless across chunks and stable under camera movement.
- Puddles are a stricter threshold of the same basin field, not nodes, decals,
  tiles, or saved objects.
- Impact rings use an analytic jittered grid and shader time. Each fragment
  evaluates a fixed local cell; CPU code never spawns, moves, or frees drops.
- Wet color response darkens/desaturates the existing albedo and adds a narrow
  cool highlight. It never writes gameplay light or visibility truth.
- A uniform dry early-out keeps the extra shader work dormant once the retained
  ground-wetness scalar has fully dried, including throughout later clear
  weather.

### Authored ground profile

`GroundWetnessProfile` owns accumulation/drying rates and shader tuning:

```text
id: StringName
update_interval_seconds: float
accumulation_rate_per_second: float
drying_rate_per_second: float
basin_contrast: float
grass_wetness_floor: float
puddle_threshold: float
wet_darkening: float
wet_desaturation: float
puddle_tint: Color
puddle_opacity: float
impact_cell_size_px: float
impact_ring_width: float
impact_lifetime_seconds: float
impact_density: float
```

The defaults keep puddles sparse and impact rings legible only during rain.

## Performance Class

- Player runtime: `interactive-frame`; the authored default is a 4 Hz scalar
  update per player and validation caps cadence at 20 Hz.
- Ground CPU apply: one shared material and a fixed set of uniforms; the
  authored default is 10 Hz and validation caps cadence at 20 Hz.
- Ground GPU: extra math inside the existing ground pass; no extra screen copy,
  render target, texture allocation, draw pass, or node-per-drop/puddle.
- No tile, chunk, terrain, entity, room-set, or loaded-world loop.
- Escalation path: persistent spatial water requires a separate native
  subchunk-field design with dirty regions and budgeted visual uploads.

## Modding / Extension Points

- Player and ground tuning are resource-authored and validated.
- Later suit/gear modifiers consume the component through typed modifier seams;
  core V0 does not branch on item ids.
- Later precipitation kinds define explicit liquid-wetness contribution rather
  than assuming every kind is rain.
- Mods may tune visual response without changing terrain ids or save identity.

## Files Allowed for This Iteration

- `docs/02_system_specs/survival/player_wetness_and_cold_exposure.md`
- `docs/02_system_specs/survival/survival_core.md`
- `docs/02_system_specs/world/humidity_and_rain_runtime.md`
- `docs/02_system_specs/world/seasons_and_temperature_runtime.md`
- `docs/02_system_specs/world/terrain_hybrid_presentation.md`
- `docs/02_system_specs/ui/ui_ux_foundation.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/commands.md` for grep verification only
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`
- `core/entities/player/**/*exposure*.gd`
- `core/entities/components/**/*exposure*.gd`
- `core/systems/world/environment_exposure_resolver.gd`
- `core/systems/world/rain_overlay.gd`
- `core/systems/world/ground_wetness*.gd`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- the player scene only for component wiring
- `data/balance/*exposure*.gd`
- `data/balance/*exposure*.tres`
- `data/balance/ground_wetness*.gd`
- `data/balance/ground_wetness*.tres`
- `assets/shaders/ground_hybrid_material.gdshader`
- `scenes/world/world_runtime_v0.tscn`
- `scenes/ui/hud/hud_exposure_widget.gd`
- `scenes/ui/hud/hud_icons.gd`
- `scenes/ui/hud/hud_manager.gd`
- `tools/*exposure*_probe.gd`
- `tools/*wet_ground*_probe.gd`
- existing weather/rain/save/HUD probes where regression coverage changes
- matching Godot `.gd.uid` metadata for newly added scripts
- `artifacts/wet_ground_visual/**` for explicit A/B render proof

## Files Forbidden for This Iteration

- World generation, native generation, terrain ids, chunk packets,
  walkability, `WorldDiffStore`, and `world_version`.
- Health, damage, death, movement, stamina, fatigue, oxygen consumption, combat,
  inventory, equipment, crafting, building mutation, and power mutation logic.
- Snow/ice/flood simulation, persistent decals, per-tile water, and audio.
- Multiplayer transport/replication packets.
- New HUD panels, alarm vignette consumers, tutorial copy, or raw UI strings.

## Acceptance Criteria

- One player component is the only writer of `wetness` and `cold_load`.
- Dry/open-sky rain cannot increase wetness when precipitation kind is not
  `RAIN`; heavy rain under open sky increases it monotonically.
- Building interior and mountain cover prevent rain gain; explicit subsurface
  gating passes resolver probes, while current shipping gameplay remains
  surface-only because it has no z-level owner.
- Wetness decreases under cover and decreases faster in powered indoor shelter.
- With fixed air temperature, greater wind or wetness never lowers cold load.
- Powered indoor shelter drives the cold target toward comfort.
- V0 never mutates health, movement, oxygen, fatigue, stamina, or death.
- Save/load round-trips wetness/cold load; old saves default to dry/warm.
- HUD uses the existing survival plate, appears only above thresholds, and adds
  no raw visible strings or critical alarm animation.
- Wet ground uses the existing shared material and one scalar presenter; no
  per-tile, per-chunk, per-puddle, or per-impact scene objects exist.
- Mask and puddles are stable in world space, accumulate during rain, and fade
  after rain.
- Impact rings are visible only while raining and are analytic shader output.
- Runtime cost is independent of map size and loaded chunk count.
- Existing weather, rain, season, cloud, player-save, and HUD probes stay green.

## Failure Cases / Risks

- Exposure reads rain visibility or puddle opacity instead of weather truth.
- Rain overlay and gameplay compute different open-sky answers.
- Player values are stored on HUD nodes or duplicated in another manager.
- Cold load immediately damages the player despite V0 warning-only scope.
- Wetness silently resets on save/load.
- Puddles become tile/runtime-diff state or one node per visible mark.
- The wet mask repeats per chunk, swims with the camera, or creates a blue film
  over every surface.
- Wet highlights become a second gameplay-light authority.

## Implementation Iterations

### Iteration 0 - Spec landing - DONE

- Land and index this approved contract before code.

### Iteration 1 - Exposure authority and persistence - DONE

- Add validated data, shared open-sky resolution, player component, and
  additive save/load state.

### Iteration 2 - Quiet survival HUD - DONE

- Add threshold-revealed wet/cold telemetry to the existing survival plate.

### Iteration 3 - Shared wet-ground material response - DONE

- Add ground accumulation controller, procedural mask/puddles, and analytic
  impact rings without an extra pass.

### Iteration 4 - Contract closure - DONE

- Update canonical API/schema/save/UI/weather/glossary contracts and run scoped
  plus full regression checks.

## Required Updates

- [x] `survival_core.md` - add wetness/cold-load V0 semantics and warning-only
  boundary.
- [x] `humidity_and_rain_runtime.md` - replace the future-wetness note with the
  landed gameplay consumer and shared open-sky seam.
- [x] `seasons_and_temperature_runtime.md` - record temperature's first survival
  consumer while keeping damage/snow out of scope.
- [x] `terrain_hybrid_presentation.md` - record the derived shared-material mask and
  no-terrain/save boundary.
- [x] `ui_ux_foundation.md` - add the threshold-revealed exposure row.
- [x] `system_api.md` - add exposure component reads/state methods and the shared
  open-sky resolver.
- [x] `packet_schemas.md` and `save_and_persistence.md` - add optional
  `PlayerSaveData.exposure` and old-save defaults.
- [x] `event_contracts.md` and `commands.md` - grep verification completed; no new
  global event or gameplay command is expected.
- [x] `PROJECT_GLOSSARY.md` - define Player wetness, cold load, and wet-ground mask.

## Implementation Closure

Landed on 2026-08-03.

- `PlayerExposureComponent` is the sole writer of persisted per-player
  `wetness` and `cold_load`; all values clamp to finite `0..1` state and old or
  malformed saves reset safely.
- `EnvironmentExposureResolver` now owns the shared fail-closed mountain/building
  sky query used by both gameplay and rain presentation. Late room authority can
  refresh its building reference without a frame-loop scan.
- The existing survival plate contains a quiet, threshold-revealed droplet and
  cold-glyph row. V0 remains warning-only.
- `GroundWetnessPresenter` integrates one transient scalar at the authored 10 Hz
  default and publishes to the factory-owned shared material. Broad wet patches,
  sparse puddles, and drop rings add no texture, sampler, pass, tile state, impact
  list, or scene object. Rings reuse the existing far-zoom procedural-detail LOD.
- Scoped exposure/resolver/HUD/rain/ground probes plus weather, season, save, and
  HUD regressions passed under Godot 4.6.2. GDScript format/lint, GdUnit4 (3/3),
  headless editor import, 120-frame runtime boot, and `git diff --check` passed.
- Windowed D3D12 render proof was inspected at close and wide zoom; evidence is
  stored in `artifacts/wet_ground_visual/`.
- Integration limitation: the current shipping world shell does not instantiate
  `BuildingSystem`, `BaseLifeSupport`, or a z-level owner. Powered-indoor and
  explicit subsurface transitions are contract/probe-covered but require that
  separate existing-system wiring before they are reachable in normal play.
