---
title: Seasons and Global Temperature Runtime V0
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.2
last_updated: 2026-08-03
related_docs:
  - weather_runtime.md
  - humidity_and_rain_runtime.md
  - ../ui/ui_ux_foundation.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - ../survival/player_wetness_and_cold_exposure.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Seasons and Global Temperature Runtime V0

## Purpose

Activate the season state already owned and persisted by `TimeManager`, make
the existing authored weather temperature a live authoritative global read,
and let the current season bias temperature, humidity, and future weather
regime selection without creating a second weather or time owner.

This contract deliberately does not introduce a separate `SeasonRuntime`.
`TimeManager` remains the single writer of season phase/progress;
`WeatherRuntime` remains the single writer of final weather axes. Season data
is authored through resources and is read-only at runtime.

## Gameplay Goal

The player should be able to read a slow planetary cycle before seasonal
terrain, snow, or thermal damage exist. Temperature and humidity in the HUD
make the exterior state legible; `PlayerExposureComponent` is the first
survival consumer of the same authoritative outside-air value, while future
snow and damage systems still cannot inspect visuals or invent a parallel
clock.

## Scope

- Four global core phases in a fixed cycle: `WARM -> SPORE -> COLD -> STORM`.
- Fifteen in-game days per phase by default, preserving the existing authored
  `TimeBalance` cadence.
- Smooth interpolation from the active phase profile to the next profile over
  the phase, continuous across the day on which the phase changes.
- Data-driven `SeasonProfile` resources with stable ids, temperature offset,
  humidity offset, and weather-regime weight multipliers.
- `TimeManager` public pull reads for current effective season, progress, and
  interpolated seasonal modifiers.
- A discrete `season_changed(new_season, previous_season)` event on natural
  phase changes and initial state publication.
- Developer-only forcing/cycling of the effective season for probes and visual
  inspection; debug state is never saved.
- `WeatherRuntime.get_temperature_c()` promoted to an authoritative global
  outside-air temperature read.
- Seasonal humidity offset applied inside `WeatherRuntime`; rain continues to
  derive from the final authoritative humidity.
- Seasonal target-regime weight multipliers applied inside the existing
  deterministic weather selector; the season does not force an immediate
  regime reset.
- The existing top-right weather HUD adds temperature and humidity beside the
  existing cloud-cover readout.
- Save/load, runtime, and HUD probes for the new contract.

## Out of Scope

- Snow or changing precipitation kind from temperature.
- Body-temperature simulation, hypothermia/heat damage, status penalties, and
  equipment insulation. Warning-only wetness/cold load and a single controlled
  powered-indoor temperature are owned by the companion player-exposure spec.
- Biome, latitude, altitude, shelter, room, or time-of-day temperature terms.
- Seasonal terrain/flora swaps, snow cover, ice, tint, audio, fauna, spores,
  crops, resources, or lighting changes.
- A season-name HUD label, calendar/PDA screen, forecast, or tutorial copy.
- Per-tile, per-chunk, biome-local, or regional seasons/weather.
- Multiplayer transport/replication wiring.
- A new save section, a `world_version` bump, or any worldgen change.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Season is authoritative slow environment-runtime state. Final temperature/humidity are authoritative global runtime reads. HUD is derived presentation. No worldgen data changes. |
| Save/load required? | Yes, through the existing `TimeSaveData.current_day/current_season`. Progress reconstructs from day/time; live modifiers and weather axes are not saved. |
| Deterministic? | Yes. Phase progress is clock-derived; profile interpolation and weather weight multiplication add no RNG. Existing weather hashing remains the only successor roll. |
| Must it work on unloaded chunks? | Yes by construction: all V0 values are global and chunk-independent. |
| C++ compute or main-thread apply? | O(1) scalar GDScript state and UI reads. No bulk compute exists. |
| Dirty unit | One global season sample; one global weather sample; one HUD text/icon refresh. |
| Single owner | `TimeManager` writes season phase. `WeatherRuntime` writes final temperature, humidity, and regime evolution. HUD reads only. |
| 10x / 100x scale path | Cost is independent of world, chunk, tile, entity, and content-instance counts. Profile count is the fixed four-phase core cycle. |
| Main-thread blocking risk | None beyond fixed scalar interpolation and three compact HUD values. |
| Hidden fallback? | None. Missing/invalid core profiles fail at boot rather than silently hardcoding runtime values. |
| Could it become heavy later? | Regional temperature/season overlays could. They require a separate native/budgeted field spec and are forbidden here. |
| Whole-world prepass? | No. |

## Authority and Data Model

### Season state

`TimeManager` keeps its existing authoritative fields:

```text
current_day: int
current_hour: float
current_season: int  # WARM, SPORE, COLD, STORM
```

The normalized progress is derived, not separately stored:

```text
day_in_phase = fposmod(current_day - 1, days_per_season)
season_progress = (day_in_phase + day_progress) / days_per_season
season_blend = smoothstep(0, 1, season_progress)
```

At the boundary, the previous phase approaches the next profile at blend `1`;
after rollover the new phase starts on the same profile at blend `0`. The
modifier is therefore continuous.

### `SeasonProfile`

```text
SeasonProfile
{
  id: StringName,                         # core:warm/spore/cold/storm
  season_kind: int,                       # matches TimeManager phase enum
  temperature_offset_c: float,
  humidity_offset: float,                 # additive, final humidity clamps 0..1
  weather_regime_weight_multipliers: Dictionary,
}
```

The multiplier dictionary maps stable weather regime ids to non-negative
weights. Missing ids read as `1.0`, so a modded weather regime remains valid
without editing every core season profile.

V0 default tuning:

| Phase | Temperature | Humidity | clear | cloudy | overcast |
|---|---:|---:|---:|---:|---:|
| `core:warm` | `+6 C` | `-0.08` | `1.35` | `0.90` | `0.65` |
| `core:spore` | `+1 C` | `+0.04` | `0.90` | `1.15` | `1.05` |
| `core:cold` | `-5 C` | `-0.03` | `1.00` | `1.10` | `1.25` |
| `core:storm` | `-2 C` | `+0.12` | `0.45` | `1.20` | `1.65` |

These offsets keep the first cold pass above the snow resolver's future
freezing boundary for most authored weather values. Snow and final thermal
balance remain a separate approved iteration.

## Runtime Architecture

### Season cadence

- New game starts in `WARM` using the existing time reset path.
- `TimeManager` advances one phase after every `days_per_season` day rollovers.
- `get_season_progress()` is a pull read and does not emit per-frame events.
- Natural phase changes emit `season_changed` once.
- Restore validates the stored phase, clears developer overrides, and republishes
  the initial effective state without adding a new save field.

### Weather integration

`WeatherRuntime` applies the seasonal terms; `TimeManager` never writes weather:

```text
temperature_c = weather_temperature_band_sample + season_temperature_offset_c
humidity = clamp(weather_humidity_band_sample + season_humidity_offset, 0, 1)
effective_successor_weight = authored_weight * season_regime_multiplier
```

- Temperature and humidity use the same smooth seasonal profile blend.
- The existing debug humidity override still has final precedence for causal
  rain probes.
- Rain kind remains `NONE/RAIN`; temperature is not yet a precipitation-kind
  resolver.
- Regime weights are multiplied only when the existing selector chooses the
  next regime. A season boundary does not reset a live transition or consume a
  new random number.

## Event Contract

```text
season_changed(new_season: int, previous_season: int)
```

Emitter: `TimeManager` on natural phase change and once during initial state
publication (`new_season == previous_season`). Smooth progress/modifiers remain
pull-model reads.

## Save / Persistence Contract

- `TimeSaveData` remains exactly `{current_hour, current_day, current_season}`.
- `current_day + current_hour` reconstruct progress; `current_season` restores
  the phase identity.
- Seasonal modifiers, global temperature, and humidity are derived and are not
  serialized.
- Developer overrides are cleared on reset/restore and never enter save data.
- `WeatherSaveData` remains its existing seven-field slow-state payload.
- No `world_version` bump is required.

## HUD Presentation Contract

Visual thesis: a quiet expedition instrument strip on the existing translucent
environment plate; cloud cover, air temperature, and humidity share one calm
hierarchy, and only existing critical systems own alarm motion.

Content plan:

1. Keep the localized active weather name as the widget's orientation line.
2. Keep cloud cover first in the compact metric row.
3. Append signed whole-degree Celsius and whole-percent humidity in the same
   row, separated through spacing/icon rhythm rather than new cards.

Interaction thesis:

- Values update through the existing HUD refresh path and change smoothly with
  authoritative reads.
- No entrance animation, pulse, blinking, or new alarm channel is added; motion
  would compete with oxygen/shelter urgency.
- Inside-powered dimming remains owned by the existing environment-cluster
  treatment; the new values inherit it.

The widget uses code-drawn pictograms and numeric values. It introduces no raw
player-facing label strings and therefore no new localization key.

## First Survival Consumer

`PlayerExposureComponent` reads `WeatherRuntime.get_temperature_c()` as the
outside-air baseline. It then derives a player-local cold target from current
wind, persisted wetness, cover, and powered-indoor control. This does not make
the component a second temperature writer: the global Celsius value remains
owned by `WeatherRuntime`, while the normalized `cold_load` is owned by the
player component. V0 only drives threshold-revealed HUD telemetry and never
applies health, movement, oxygen, fatigue, or death consequences.

## Performance Class

- Runtime class: `interactive-frame`, O(1).
- Season advance: one bounded scalar mutation on a day boundary.
- Weather reads: fixed profile interpolation and dictionary lookups.
- HUD apply: one existing weather widget, three compact values.
- Forbidden: per-tile seasonal scans, loaded-chunk loops, scene rebuilds,
  runtime resource loads, or separate per-system season clocks.
- Escalation path: regional/terrain seasonal response requires a separate spec,
  native field compute where needed, and bounded dirty publication.

## Modding / Extension Points

- Core seasonal tuning is resource-authored.
- Missing weather regime multipliers default to neutral `1.0` so modded regimes
  remain compatible.
- The four phase identities and order are fixed for V0; adding arbitrary phase
  counts requires a future save/event compatibility spec.
- Gameplay consumers use typed public reads, never profile paths or HUD text.

## Files Allowed for This Iteration

- `docs/02_system_specs/world/seasons_and_temperature_runtime.md`
- `docs/02_system_specs/world/weather_runtime.md`
- `docs/02_system_specs/world/humidity_and_rain_runtime.md`
- `docs/02_system_specs/ui/ui_ux_foundation.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`
- `core/autoloads/time_manager.gd`
- `core/autoloads/event_bus.gd`
- `core/autoloads/weather_runtime.gd`
- `core/systems/world/season_profile.gd`
- `data/balance/time_balance.gd`
- `data/balance/time_balance.tres`
- `data/seasons/*.tres`
- `scenes/ui/hud/hud_weather_widget.gd`
- `scenes/ui/hud/hud_icons.gd`
- `tools/*season*_probe.gd`
- `tools/weather_runtime_probe.gd`
- `tools/weather_save_probe.gd`
- `tools/*hud*_probe.gd`

## Files Forbidden for This Iteration

- World generation, biome resolution, terrain ids, chunk packets, and
  `world_version`.
- Player survival/status, oxygen, health, room climate, building, power,
  farming, inventory, and machine systems.
- Rain shader/presentation changes and new snow presentation.
- Flora/fauna/terrain seasonal presentation.
- Multiplayer transport and replication packets.
- Other HUD clusters or a new environment panel.

## Acceptance Criteria

- `TimeManager` remains the only season-phase writer; no `SeasonRuntime` or
  second clock exists.
- The four profiles load and validate from data; each stable id is unique.
- Natural day progression follows `WARM -> SPORE -> COLD -> STORM -> WARM`.
- Seasonal modifier samples are continuous across a phase boundary.
- `get_temperature_c()` is live and changes by the authored season offset while
  weather input is fixed.
- Final humidity is bounded `0..1`, changes by season, and remains the causal
  input for rain.
- Seasonal regime multipliers alter effective weights without introducing a
  second RNG or forcing a current-regime reset.
- Existing time save payload stays three fields and weather save payload stays
  seven fields; save/restore reconstructs season progress, temperature, and
  humidity consistently.
- `season_changed` emits on natural phase changes and initial publication.
- The existing weather HUD shows cloud cover, signed Celsius temperature, and
  humidity together without a new panel or raw localized label string.
- Runtime work stays O(1), with no tile/chunk/entity loops or runtime loads.
- Existing weather, rain, time, save, and HUD probes remain green.
- The player exposure consumer reads the global temperature without mutating
  it and remains warning-only.

## Failure Cases / Risks

- A visual widget or `SeasonProfile` becomes a second writer of weather truth.
- A separate season clock drifts from `TimeManager.current_day`.
- Temperature/humidity are redundantly saved and disagree after restore.
- Phase change rescans loaded chunks or rebuilds presentation.
- Weather successor selection consumes a different random stream per client.
- HUD adds another card, alarm animation, or hardcoded player-facing labels.
- Snow, thermal damage, seasonal flora, or regional simulation enters this V0;
  the companion warning-only cold load is not thermal damage.

## Implementation Iterations

### Iteration 0 - Spec landing — DONE

- Land and index this approved contract before code.

### Iteration 1 - Season authority and data — DONE

- Add validated profiles, cadence/progress reads, debug forcing, and the
  discrete event to the existing `TimeManager` owner.

### Iteration 2 - Weather coupling and live temperature — DONE

- Apply blended offsets and successor multipliers inside `WeatherRuntime`.
- Extend deterministic runtime/save probes.

### Iteration 3 - Compact HUD instrumentation — DONE

- Extend the existing weather widget and icon vocabulary only.
- Add static/headless HUD proof; leave final visual balance to human review.

### Iteration 4 - Contract closure — DONE

- Update public API/event/persistence/glossary/UI/weather docs and run the full
  regression suite.

## Implementation Closure

Landed on 2026-08-03:

- `TimeManager` owns the fixed four-phase cycle, derived smooth progress,
  validated `SeasonProfile` data, debug forcing, and the dev-only `J` cycle
  shortcut.
- `WeatherRuntime` applies the smooth seasonal temperature/humidity offsets and
  successor-weight multipliers while preserving its existing deterministic
  clock and roll.
- The existing weather HUD presents cloud cover, signed Celsius temperature,
  and humidity in one compact metric row with code-drawn glyphs.
- Time and weather save payloads remain exactly three and seven slow-state
  fields; derived values reconstruct after restore.
- The scoped season, weather, weather-save, HUD, rain-presentation, and cloud
  authority probes pass headless. The project formatting/lint and GdUnit suite
  pass through `tools/agent/Invoke-AgentValidation.ps1`.

Final windowed checks remain human visual review rather than an automated
acceptance claim: verify the compact row at representative resolutions and
locales, its inherited indoor dimming, and season/weather cycling with `J`/`K`.

## Required Updates

- [DONE] `system_api.md` - promote temperature, add season progress/modifier/debug
  reads, and keep mutation ownership explicit.
- [DONE] `event_contracts.md` - add `season_changed` emitter/timing/listener status.
- [DONE] `packet_schemas.md` and `save_and_persistence.md` - confirm unchanged shapes
  and derived reconstruction semantics.
- [DONE] `weather_runtime.md` and `humidity_and_rain_runtime.md` - record the landed
  season-integration seam and temperature promotion.
- [DONE] `ui_ux_foundation.md` - record the compact environment metric row.
- [DONE] `PROJECT_GLOSSARY.md` - update Season and Temperature definitions/status.
- [DONE] `commands.md` - grep verification confirms no gameplay mutation command is
  expected for autonomous time/season evolution.
