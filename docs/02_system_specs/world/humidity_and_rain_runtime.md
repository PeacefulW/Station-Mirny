---
title: Weather Runtime V1 - Humidity and Visual Rain
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.4
last_updated: 2026-08-03
related_docs:
  - weather_runtime.md
  - wind_and_grass_scatter_presentation.md
  - cloud_occlusion_lighting.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0004-host-authoritative-multiplayer.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - seasons_and_temperature_runtime.md
  - ../survival/player_wetness_and_cold_exposure.md
---

# Weather Runtime V1 - Humidity and Visual Rain

## Purpose

Activate the humidity and precipitation axes reserved by Weather Runtime V0.
`WeatherRuntime` remains the single authoritative writer: humidity evolves as
part of the global weather state, rain intensity is derived from humidity and
cloud conditions, and presentation only reads that truth.

This iteration deliberately does not activate temperature as a gameplay input.
Temperature is needed when precipitation kind or survival consequences depend
on freezing; rain alone can be resolved from humidity and cloud cover while the
existing authored temperature read remains reserved and consumer-less for the
following seasons iteration.

Current extension: temperature and seasonal humidity bias are live under
[`seasons_and_temperature_runtime.md`](seasons_and_temperature_runtime.md), and
precipitation *kind* is now temperature-resolved under
[`snow_precipitation_runtime.md`](snow_precipitation_runtime.md).

This V1 contract remains authoritative for precipitation **potential and
intensity**: snow did not add a second precipitation model, it only reinterprets
the same derived intensity as `SNOW` below the authored freezing threshold. The
V1 sections below therefore stay accurate wherever they describe derivation, and
the historical statement that V1 "does not resolve snow" applies to this
document's own scope rather than to the current runtime.

## Gameplay Goal

Rain makes the exterior feel alive and exposed. The player can see weather
building through cloud cover and then read actual rain; the landed player
exposure component consumes the same authoritative kind/intensity while the
visual layer, wet-ground mask, and later agriculture/machine systems remain
read-only consumers rather than parallel weather owners.

## Scope

- One global authoritative humidity value in the `0..1` range.
- Humidity bands authored per `WeatherRegimeProfile` and blended through the
  existing deterministic regime transition.
- One authoritative precipitation kind for this iteration: `RAIN`; `NONE` is
  used below the rain threshold.
- Rain intensity derived from humidity, cloud cover, and authored regime
  precipitation tuning. It is not independently randomized.
- Smooth pull-model getters on `WeatherRuntime`; no per-frame domain event.
- One bounded view-sized GPU rain layer that reads authoritative rain intensity,
  follows the active view, and can use authoritative wind only for visual slant.
- Surface-context gating so rain presentation is absent below the surface and
  does not become a universal screen effect.
- Deterministic reconstruction after save/load from the already persisted
  weather regime, transition state, weather clock, and seed inputs.
- Static/runtime probes for humidity bounds, dependency of rain on humidity,
  dry clear weather, wet overcast rain, transition smoothness, bounded visual
  cost, and the surface-context gate.

## Out of Scope

- Live temperature or freezing rules.
- Snow, ash, spore precipitation, hail, and mixed precipitation.
- Seasons or seasonal bias of humidity/regime selection.
- Player damage/hypothermia consequences, visibility penalties, crop or machine
  effects, persistent water accumulation, and flooding.
- Player wetness/cold telemetry and transient puddle presentation are owned by
  the companion
  [`player_wetness_and_cold_exposure.md`](../survival/player_wetness_and_cold_exposure.md),
  not by the weather authority defined here.
- Rain audio, lightning, and thunder.
- Per-tile, per-chunk, biome-local, or regional weather.
- Multiplayer transport/replication wiring; host-authoritative ownership is
  preserved but network packets remain future work.
- A new save field for live humidity or rain intensity.

## Related Documents

- `docs/02_system_specs/world/weather_runtime.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/05_adrs/0004-host-authoritative-multiplayer.md`
- `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`

## Dependencies

- `WeatherRuntime` and the slow weather state from Weather Runtime V0.
- `WeatherRegimeProfile` resources for authored humidity and precipitation
  tuning.
- `WindRuntime` as an optional read-only presentation input for rain slant.
- The shared open-sky resolver's surface context. Its explicit z bridge is
  covered by probes, but the current shipping scene has no z-level owner.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Humidity and precipitation are authoritative environment-runtime state; rain rendering is derived presentation. It never mutates worldgen or terrain truth. |
| Save/load required? | Existing slow weather state remains persisted. Live humidity and rain reconstruct and are not saved independently. |
| Deterministic? | Yes. Authoritative values depend only on deterministic regime data, transition state, weather clock, and existing weather seed inputs. |
| Must it work on unloaded chunks? | Yes by construction: weather is one global state and has no chunk dependency. |
| C++ compute or main-thread apply? | O(1) scalar GDScript orchestration plus one view-bounded GPU shader layer. No bulk compute exists. |
| Dirty unit | One global weather-state sample. Presentation dirty unit is one rain-layer uniform update. |
| Single owner | `WeatherRuntime` writes humidity/kind/intensity. Rain presentation reads only. |
| 10x / 100x scale path | Cost is independent of map size, loaded chunk count, terrain count, and entity count. |
| Main-thread blocking risk | None beyond a fixed set of scalar writes; no object/tile/chunk loops or runtime loads. |
| Hidden fallback? | None. Presentation resources are prepared at scene load; no runtime loading path is added. |
| Could it become heavy later? | Regional simulation could; it requires a separate native/budgeted regional-weather spec and is forbidden in this iteration. |
| Whole-world prepass? | No. |

## Data Model

### Authoritative live axes

```text
humidity: float                    # 0 dry .. 1 saturated
precipitation_kind: int            # NONE or RAIN in V1
precipitation_intensity: float     # 0 none .. 1 maximum authored rain
```

`humidity` is sampled from the active regime's authored `humidity` band using
the same deterministic, slow weather-time model as the other live axes. During
a transition, current and next regime samples are blended by the authoritative
transition progress.

### Authored regime inputs

```text
humidity: Vector2                         # min/max live humidity band
precipitation_kind: int                   # NONE or RAIN in V1
precipitation_intensity: Vector2          # min/max rain-capacity band
precipitation_start_humidity: float       # data-driven condensation threshold
precipitation_start_cloud_cover: float    # data-driven cloud threshold
```

Ranges are validated when the profile is consumed; an invalid profile fails
explicitly at bootstrap instead of being silently normalized. A dry regime uses
`NONE` and a zero intensity band. Rain-capable regimes use `RAIN` and non-zero
tuning; adding such a regime remains a resource change rather than an owner-code
branch.

### Rain derivation

For each source profile:

```text
humidity_pressure = smoothstep(start_humidity, 1.0, humidity)
cloud_pressure = smoothstep(start_cloud_cover, 1.0, cloud_cover)
rain_capacity = lerp(intensity_min, intensity_max, humidity_pressure)
rain_intensity = clamp(rain_capacity * humidity_pressure * cloud_pressure, 0, 1)
```

Operational note: a HUD humidity value such as `80%` is not an unconditional
rain trigger. The active regime must support `RAIN`, cloud cover must exceed
that profile's cloud threshold, and the smooth pressures can still leave only
a barely visible drizzle near either threshold. `clear` always remains dry;
seasonal humidity offsets do not bypass these regime/cloud gates.

Current and next profile results blend through the existing transition. The
published kind is `RAIN` only while blended intensity is positive; otherwise
it is `NONE`. A separate visual cutoff may hide imperceptible values but cannot
change this authoritative result. Humidity is therefore causal: a
wet regime definition alone does not force rain below its condensation
threshold, and presentation never feeds back into the result.

## Runtime Architecture

### Authority

- `WeatherRuntime` is the only writer of humidity, precipitation kind, and
  precipitation intensity.
- Gameplay consumers call typed getters. They never inspect shader
  opacity or scene visibility.
- The host owns these axes when multiplayer transport lands. Clients may derive
  presentation but may not choose rain independently.

### Presentation

- Rain is rendered by one view-bounded GPU shader layer, not one node per drop.
- The shader/material is prepared at scene/boot time. Runtime intensity changes
  update visibility and uniforms only.
- The layer follows the active camera/view so its work is independent of map
  size and streaming radius.
- The visual layer may read wind direction/strength to angle drops, but cannot
  write weather or wind state.
- `EnvironmentExposureResolver` owns the shared open-sky derivation: surface
  level, not a building indoor cell, and not a mountain interior. Both
  `RainOverlay` and `PlayerExposureComponent` use this same read, so visual rain
  cannot disagree with gameplay wetting.
- `GroundWetnessPresenter` integrates one transient rain-derived scalar and
  updates the existing shared plains material. Its mask, puddles, and analytic
  impact rings are presentation only and never feed weather or player state.

## Event Contracts

No new domain event is added. `weather_changed` continues to represent discrete
regime transitions. Smooth humidity and precipitation values remain pull-model
reads; emitting them every frame would create unnecessary event traffic.

## Save / Persistence Contracts

- `WeatherSaveData` does not gain humidity or precipitation fields.
- Existing slow state (`active_regime`, transition state, timers,
  `weather_time_hours`, transition count) remains sufficient to reconstruct
  live humidity and rain deterministically.
- Legacy/modded `WeatherRegimeProfile` resources that omit the new rain fields
  receive dry defaults. Old saves remain valid because `WeatherSaveData` stays
  unchanged.
- No `world_version` bump is required because world generation output is
  unchanged.

## Performance Class

- Runtime class: `interactive-frame`, O(1).
- Authoritative compute: a fixed number of scalar samples and blends per frame.
- Presentation apply: one fixed rain-layer uniform update per frame.
- Forbidden: per-tile wetness state, per-chunk rain owners, loaded-world scans,
  drop nodes, runtime `load()`, or runtime shader/material/texture rebuilds when
  intensity changes.
- Escalation path: regional weather requires a separate spec with native
  region-field compute and bounded publication; it is not silently added to the
  global owner.

## Modding / Extension Points

- Regimes author humidity and rain tuning through resource fields.
- Seasons bias regime weights and final humidity through the documented seam in
  `seasons_and_temperature_runtime.md`; seasons do not become a second weather
  writer.
- Future temperature resolves `RAIN` versus `SNOW` from authoritative
  temperature after precipitation potential is known.
- Gameplay systems consume getters or a later edge-triggered domain
  event; they do not couple to the visual layer.

## Files Allowed for This Iteration

- `docs/02_system_specs/world/humidity_and_rain_runtime.md`
- `docs/02_system_specs/world/weather_runtime.md`
- `docs/02_system_specs/README.md`
- `docs/README.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `core/autoloads/weather_runtime.gd`
- `core/systems/world/weather_regime_profile.gd`
- `core/systems/world/*rain*.gd`
- `core/systems/world/*rain*.tscn`
- `data/weather/*.tres`
- `scenes/world/world_runtime_v0_scene.gd`
- `scenes/world/world_runtime_v0.tscn`
- `assets/shaders/*rain*.gdshader`
- `tools/weather_runtime_probe.gd`
- `tools/*rain*_probe.gd`

## Files Forbidden for This Iteration

- World generation, terrain ids, chunk packets, and `world_version`.
- Player survival/status components.
- Building, room, power, farming, inventory, and machine systems.
- `TimeManager` season behaviour.
- Multiplayer transport and packet implementation.
- Audio and localization assets.

## Acceptance Criteria

- `WeatherRuntime` remains the single writer of all weather axes.
- Humidity is live, bounded to `0..1`, deterministic, and smoothly blends
  between regime profiles.
- Clear/dry tuning produces no rain; sufficiently humid and cloudy tuning
  produces `RAIN` with intensity above zero.
- Lowering humidity while other inputs stay fixed never increases rain
  intensity.
- In this V1 iteration temperature remained reserved/consumer-less and was not
  used to resolve rain; the following seasons iteration promotes the read but
  still leaves snow resolution out of scope.
- Existing weather slow-state save round-trip still passes and live humidity /
  rain reconstruct from it without new save fields.
- Rain presentation uses one view-bounded GPU shader layer and performs no
  tile/chunk/entity loop.
- Rain is absent below the surface, inside a building, and inside a mountain;
  it is visible in a forced wet overcast open-sky context.
- Rain presentation and player wetting use one shared open-sky resolver.
- Transient wet-ground presentation uses one shared material and creates no
  tile, puddle, or impact nodes.
- Existing cloud, wind, weather, and save probes remain green.
- Public getter and persistence documentation no longer describes humidity or
  precipitation as reserved/neutral.

## Failure Cases / Risks

- A shader or HUD value becomes the source of rain truth.
- Authoritative rain kind/intensity is randomized separately from humidity or
  weather time; client-local shader variation remains allowed.
- Every chunk owns its own rain renderer or simulation state.
- Live humidity/intensity are redundantly saved and can disagree with the
  restored weather clock.
- A temperature or season implementation is smuggled into this iteration.
- Rain appears underground or presentation resources are rebuilt during play.

## Open Questions

None for this iteration. User decisions on 2026-08-02:

- first precipitation kind: rain;
- at the 2026-08-02 V1 landing, consequences were visual only; player exposure
  and transient wet-ground response were added on 2026-08-03;
- spatial scale: use the existing global weather owner; regional weather is a
  later separately specified extension.

## Implementation Iterations

### Iteration 0 - Spec landing - DONE

- Land this approved contract and index it.
- No runtime code before this step is complete.

### Iteration 1 - Authoritative humidity and rain axes - DONE

- Activate authored humidity bands and humidity-derived rain.
- Keep temperature reserved and consumer-less.
- Extend the weather runtime probe and save reconstruction proof.

### Iteration 2 - Bounded visual rain - DONE

- Add one surface-gated view-bounded GPU shader layer.
- Drive visibility/intensity and optional slant from authoritative reads.
- Add a presentation probe covering wet surface and dry/subsurface states.

### Iteration 3 - Contract closure - DONE

- Update public read and persistence documentation.
- Run static, headless, regression, and canonical-documentation checks.

## Implementation Closure

Landed on 2026-08-02 and integrated with player exposure/ground response on
2026-08-03. `WeatherRuntime` remains the single global authority for
humidity and precipitation; rain derives from humidity, cloud cover, and the
active regime without a second clock or random stream. Presentation is one
surface-gated `Sprite2D` shader pass with no per-drop nodes. One shared
open-sky resolver now gates both that pass and player wetting; one transient
shared-material ground response derives from the same rain truth. The seven-field
weather save payload is unchanged because all live values reconstruct from the
restored slow state. Headless runtime, save, presentation, and cloud-occlusion
regression probes pass.

## Required Updates

- `weather_runtime.md` - link this V1 extension and mark humidity/precipitation
  as live after implementation. - DONE
- `system_api.md` - mark humidity/precipitation getters as authoritative live
  reads and document any developer-only forcing surface. - DONE
- `save_and_persistence.md` and `packet_schemas.md` - keep the no-live-axis-save
  rule but remove stale `reserved` wording. - DONE
- `event_contracts.md` and `commands.md` - grep verification required; no change
  expected because this iteration adds neither an event nor a command. - DONE
