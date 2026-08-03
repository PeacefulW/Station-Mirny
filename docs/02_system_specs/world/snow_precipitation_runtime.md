---
title: Weather Runtime V2 - Temperature-Resolved Snow
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-08-03
related_docs:
  - weather_runtime.md
  - humidity_and_rain_runtime.md
  - seasons_and_temperature_runtime.md
  - ../survival/player_wetness_and_cold_exposure.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Weather Runtime V2 - Temperature-Resolved Snow

## Purpose

Make authoritative precipitation *kind* depend on authoritative temperature, so
that falling precipitation below freezing is snow rather than rain, and present
that snow through one bounded layer that mirrors the landed rain pass.

This closes a correctness break introduced by
[`seasons_and_temperature_runtime.md`](seasons_and_temperature_runtime.md)
Iteration 5: the annual minimum is now `-40 C`, while
`WeatherRuntime.get_precipitation_kind()` still returns `RAIN` unconditionally.
Today the `core:cold` phase produces rain at `-40 C`, wet ground, puddles, and
liquid player wetting.

`WeatherRuntime` remains the single writer of all weather axes. This iteration
adds no new owner, clock, random stream, or save field.

## Gameplay Goal

Winter should look and behave like winter. The player should be able to read the
season change through the sky rather than through a HUD number: the same
overcast that brought rain in the warm phases now brings snow, the ground stops
turning wet and puddled, and staying out in it is a different kind of problem
from staying out in rain.

## Scope

- Authoritative resolution of `RAIN` versus `SNOW` from
  `WeatherRuntime.get_temperature_c()` once precipitation potential is already
  known.
- One data-authored global freezing threshold; no hardcoded Celsius constant in
  script.
- One view-bounded, open-sky-gated GPU snow layer mirroring the landed
  `RainOverlay` contract.
- A presentation cross-fade band around the threshold so a kind change is not a
  visual pop between two layers.
- Snow does not apply liquid wetness to the player.
- Snow does not drive the transient wet-ground mask, puddles, or impact rings.
- Probes for kind resolution, presentation gating, wetness behaviour, and
  deterministic reconstruction after load.

## Out of Scope

- **Snow accumulation, snow cover, drifts, and frozen puddles.** These are
  persistent per-tile state with save, streaming, digging, and building
  interactions, and require their own spec.
- Ice, freezing rain, hail, sleet as a distinct authoritative kind, ash, and
  spore precipitation.
- Snow audio.
- Thermal damage, hypothermia, movement penalties, and insulation.
- Visibility or light penalties from snowfall.
- Biome, altitude, or shelter temperature terms.
- Seasonal terrain/flora swaps and any worldgen change.
- Multiplayer transport and replication packets.
- A new save field or a `world_version` bump.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Precipitation kind is authoritative environment-runtime state. Snow rendering is derived presentation. No worldgen or terrain truth changes. |
| Save/load required? | No new field. Kind is a pure function of already-reconstructed temperature and rain potential. |
| Deterministic? | Yes. Kind is a stateless threshold read over deterministic temperature; no hysteresis state and no new RNG. |
| Must it work on unloaded chunks? | Yes by construction: all values are global and chunk-independent. |
| C++ compute or main-thread apply? | O(1) scalar GDScript plus one view-bounded GPU layer. No bulk compute. |
| Dirty unit | One global weather-state sample; one snow-layer uniform update. |
| Single owner | `WeatherRuntime` writes kind and intensity. Presentation, ground response, and player exposure read only. |
| 10x / 100x scale path | Cost is independent of map size, chunk count, tile count, and entity count. |
| Main-thread blocking risk | None beyond fixed scalar writes; no loops, no runtime `load()`. |
| Hidden fallback? | None. A missing or invalid threshold resource fails explicitly at bootstrap. |
| Could it become heavy later? | Snow *accumulation* could; it is explicitly a separate spec with per-tile state and its own budgeted path. |
| Whole-world prepass? | No. |

## Authority and Data Model

### Kind resolution

Rain potential is resolved exactly as today by
[`humidity_and_rain_runtime.md`](humidity_and_rain_runtime.md). Only the
published *kind* changes:

```text
intensity = <existing humidity/cloud/regime derivation>
if intensity <= 0:            kind = NONE
elif temperature_c <= freeze: kind = SNOW
else:                         kind = RAIN
```

Properties this preserves:

- Intensity derivation is untouched; snow is not a second precipitation model.
- The resolution is **stateless**. No hysteresis variable is introduced, so
  nothing new needs saving and load reconstruction stays exact.
- A regime that authors `precipitation_kind = NONE` stays dry at any
  temperature; freezing does not invent precipitation.

Deliberate consequence: while temperature sits near the threshold, the published
kind can alternate as the slow band noise crosses it. This is accepted rather
than suppressed with hidden state - the crossing is slow (hours), and the
presentation cross-fade below is what keeps it from reading as a defect.

### Authored threshold

Freezing is a global world constant, not per-regime tuning, so it does not
belong on `WeatherRegimeProfile`. This iteration adds one small authored
resource:

```text
WeatherBalance
{
  id: StringName,                       # core:weather
  freeze_temperature_c: float,          # default 0.0
  precipitation_crossfade_c: float,     # default 2.0, presentation only
}
```

`freeze_temperature_c` is authoritative. `precipitation_crossfade_c` is a
presentation width and must not influence the published kind.

This is a data resource, not a new manager or service. Later ice/frost tuning
has an obvious home here instead of accreting constants in script.

## Runtime Architecture

### Presentation

- One `SnowOverlay`, a `WorldViewOverlay` subclass, mirroring `RainOverlay`:
  view-bounded, prepared at scene load, driven by uniforms only.
- It uses the same `EnvironmentExposureResolver` open-sky read as
  `RainOverlay` and `PlayerExposureComponent`, so visual snow cannot disagree
  with gameplay.
- Snow drifts more slowly than rain and is affected more by wind laterally; it
  may read `WindRuntime` for slant/drift but never writes it.
- Client-local animation time wraps on an exact periodic interval, as
  `RainOverlay` already does, so wrapping cannot produce a visual jump.

### Cross-fade

Both layers derive a presentation weight from temperature:

```text
snow_weight = smoothstep(freeze + crossfade, freeze - crossfade, temperature_c)
rain_weight = 1 - snow_weight
```

Each layer multiplies its own opacity by its weight. Near the threshold both are
briefly partially visible, which reads as sleet without introducing a third
authoritative kind. Away from the band exactly one layer is active.

### Ground and player response

- `GroundWetnessPresenter` must gate its rain-derived input on `kind == RAIN`.
  Snow must not produce a wet mask, puddles, or impact rings. Existing dry-out
  behaviour handles the transition when rain turns to snow.
- `PlayerExposureComponent` already requires `kind == RAIN` to add wetness, so
  snow adds none without a logic change. The spec-level statement in
  [`player_wetness_and_cold_exposure.md`](../survival/player_wetness_and_cold_exposure.md)
  that snow does not reuse the liquid wetness rate becomes satisfied rather than
  merely reserved.

Snow therefore reduces one pressure (wetness) while the season it arrives in
raises another (cold). That is the intended trade, not an oversight.

## Event Contract

No new domain event. `weather_changed` continues to represent discrete regime
transitions only. Precipitation kind remains a pull-model read, consistent with
the landed rain contract.

A kind change is deliberately **not** promoted to an event in this iteration: no
consumer needs edge-triggering yet, and adding one would create traffic near the
threshold band.

## Save / Persistence Contract

- `WeatherSaveData` stays exactly its existing seven slow-state fields.
- Precipitation kind is derived from restored temperature and restored rain
  potential; it is not serialized.
- No `world_version` bump: worldgen output is unchanged.

## Performance Class

- Runtime class: `interactive-frame`, O(1).
- Authoritative compute: one comparison added to an existing scalar path.
- Presentation apply: one additional view-bounded layer with fixed uniform
  writes.
- Forbidden: per-tile snow state, per-chunk snow owners, drop/flake nodes,
  loaded-world scans, runtime `load()`, and material/shader rebuilds on kind
  change.
- Escalation path: snow accumulation requires the separate per-tile spec with
  bounded dirty publication, not an extension of this global owner.

## Modding / Extension Points

- `precipitation_kind` on `WeatherRegimeProfile` already enumerates
  `None/Rain/Snow/Ash/Spore`; this iteration activates the `Snow` result path
  without changing the enum.
- The freeze threshold is authored, so a mod can shift the planet's freezing
  point without touching script.
- Ash and spore precipitation remain future kinds resolved by the same seam.

## Files Allowed for This Iteration

- `docs/02_system_specs/world/snow_precipitation_runtime.md`
- `docs/02_system_specs/world/weather_runtime.md`
- `docs/02_system_specs/world/humidity_and_rain_runtime.md`
- `docs/02_system_specs/survival/player_wetness_and_cold_exposure.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/README.md`
- `docs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `core/autoloads/weather_runtime.gd`
- `core/systems/world/snow_overlay.gd`
- `core/systems/world/ground_wetness_presenter.gd`
- `data/balance/weather_balance.gd`
- `data/balance/weather_balance.tres`
- `assets/shaders/snow_overlay.gdshader`
- `scenes/world/world_runtime_v0_scene.gd`
- `scenes/world/world_runtime_v0.tscn`
- `tools/*snow*_probe.gd`
- `tools/rain_presentation_probe.gd`
- `tools/weather_runtime_probe.gd`

## Files Forbidden for This Iteration

- World generation, terrain ids, chunk packets, and `world_version`.
- Per-tile or per-chunk snow/ice state of any kind.
- `TimeManager` and season behaviour.
- Player health, oxygen, movement, and thermal damage.
- Building, room, power, farming, inventory, and machine systems.
- Save payload shapes.
- Multiplayer transport and packets.
- Audio assets.

## Acceptance Criteria

- `WeatherRuntime` remains the single writer of precipitation kind and
  intensity.
- Below the authored threshold with rain potential present, the published kind
  is `SNOW`; above it, `RAIN`; with no potential, `NONE` at any temperature.
- A `NONE` regime stays dry at `-40 C`.
- Intensity for a fixed humidity/cloud/regime input is unchanged by the kind
  resolution.
- Kind resolution is stateless: two reads at the same temperature and weather
  state return the same kind, and a save/load round-trip reproduces it without a
  new save field.
- Snow presentation is absent below the surface, inside a building, and inside a
  mountain, and visible in a forced freezing wet-overcast open-sky context.
- Snow and rain layers use the same open-sky resolver as player wetting.
- Within the cross-fade band neither layer pops; outside it exactly one layer is
  active.
- Falling snow adds no player wetness and produces no wet-ground mask, puddles,
  or impact rings.
- Runtime work stays O(1) with no tile/chunk/entity loops and no runtime loads.
- Existing weather, rain, save, cloud, season, and exposure probes stay green.

## Failure Cases / Risks

- A shader or HUD value becomes the source of precipitation truth.
- Snow gains its own clock, RNG stream, or intensity model separate from rain
  potential.
- Hidden hysteresis state is added and then disagrees with the restored weather
  clock after load.
- Snow accumulation, ground cover, or ice is smuggled into this iteration.
- The wet-ground mask keeps reacting to snow, leaving puddles at `-40 C`.
- Snow renders underground or in a roofed sanctuary context.

## Implementation Iterations

### Iteration 0 - Spec landing — DONE

- Land and index this contract. No runtime code before approval.

### Iteration 1 - Authoritative kind resolution — DONE

- Add the authored `WeatherBalance` threshold resource.
- Resolve `RAIN`/`SNOW` in `WeatherRuntime` from authoritative temperature.
- Extend probe coverage with kind-resolution and statelessness checks.

Correction found during implementation: this spec assumed
`GroundWetnessPresenter` still needed a `kind == RAIN` gate. It already had one,
in both `calculate_next_amount` and its shared-material publication, so snow
stops wetting the ground with no change to that file. The gate is now covered by
a probe rather than assumed.

### Iteration 2 - Bounded visual snow — DONE

- Add the `SnowOverlay` layer, shader, and cross-fade weighting.
- Add a presentation probe covering freezing open-sky, warm open-sky, and
  subsurface states.

Design detail settled during implementation: both layers gate on
`kind != NONE` and split the frame by `get_snow_presentation_weight()`, rather
than each gating on its own kind. Gating each layer on its own kind would zero
that layer abruptly exactly at the threshold crossing - reintroducing the pop the
cross-fade band exists to remove.

### Iteration 3 - Contract closure — DONE

- Update public read documentation, the rain and weather specs, and the wetness
  spec's reserved-snow wording.
- Run the full probe set and project validation.

## Implementation Closure

Landed on 2026-08-03:

- `WeatherRuntime` resolves `NONE`/`RAIN`/`SNOW` from authoritative temperature
  against the authored `WeatherBalance.freeze_temperature_c`, and exposes a
  presentation-only cross-fade weight. The resolution is stateless, so no save
  field, hysteresis variable, or second clock was added.
- `SnowOverlay` mirrors `RainOverlay`: one view-bounded `Sprite2D` shader pass,
  the same shared `EnvironmentExposureResolver` open-sky gate, no per-flake
  nodes, no runtime loads. Snow falls slower than rain, drifts further with
  wind, and uses round flakes rather than streaks.
- `GroundWetnessPresenter` and `PlayerExposureComponent` required no change:
  their existing `kind == RAIN` conditions mean snow neither wets the player nor
  puddles the ground.

Verified headless in this iteration:

- Same regime and humidity, different season: `+14.4 C` publishes `RAIN` and
  `-37.6 C` publishes `SNOW`, with intensity identical to four decimals
  (`0.2439` both), proving kind resolution does not perturb derivation.
- A dry `core:clear` regime stays `NONE` at `-40 C`; freezing does not invent
  precipitation.
- Cross-fade weight is bounded `0..1`, exactly `1.0` in deep cold and `0.0` in
  the warm phase, and strictly between the two across a 400-sample sweep of the
  band.
- Snow is hidden below the surface, inside a building, inside a mountain, and
  under unresolved mountain cover, and returns when the shared context reopens.
- Rain still wets the ground while snow dries it, through the same authored
  function.
- `snow_precipitation_probe`, `rain_presentation_probe`, `weather_runtime_probe`,
  `weather_save_probe`, `player_exposure_probe`, `season_runtime_probe`, and
  `weather_occlusion_probe` all pass, as does
  `tools/agent/Invoke-AgentValidation.ps1`.

Final look-and-feel of falling snow - flake size, density, drift, and how it
reads against the alien ground palette - remains a windowed human check rather
than an automated claim.

## Required Updates

- [DONE] `weather_runtime.md` - links this V2 extension and records that
  precipitation kind is temperature-resolved.
- [DONE] `humidity_and_rain_runtime.md` - the "does not resolve snow" wording is
  now scoped to that document's own iteration rather than the runtime.
- [DONE] `player_wetness_and_cold_exposure.md` - the snow-wetness reservation is
  marked satisfied, including the already-present ground gate.
- [DONE] `system_api.md` - `get_precipitation_kind()` documented as
  temperature-resolved; `get_snow_presentation_weight()` added as
  presentation-only.
- [DONE] `PROJECT_GLOSSARY.md` - not required. Grep for `Precipitation`, `Rain`,
  and `Snow` returns no glossary entry defining precipitation, so there is no
  definition to drift.
- [DONE] `event_contracts.md`, `packet_schemas.md`, `save_and_persistence.md`,
  `commands.md` - not required. No event, packet, save field, or command
  changed; kind is a derived pull-model read.
