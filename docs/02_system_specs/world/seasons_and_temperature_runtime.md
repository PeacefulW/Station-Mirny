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

> **Superseded by Iteration 5 (landed 2026-08-03).** The table above is
> historical. The live tuning is the deep-winter amplitude table in Iteration 5,
> and the above-freezing guarantee no longer holds: the annual minimum is
> `-40 C` inside `core:cold`.

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

### Iteration 5 - Deep-winter temperature amplitude — DONE

Design intent: the `core:cold` phase must bottom out near `-40 C` so winter is
a survival event rather than a mild dip, and so the future snow/freezing
resolver has a real sub-zero band to react to. This iteration is a tuning and
curve-shape pass. It does not add snow, damage, biome terms, or a new owner.

#### Blocking finding - the profile curve is boundary-anchored

The landed reader is:

```text
offset = lerp(profile[current].offset, profile[next].offset, smoothstep(progress))
```

The authored number is therefore the value at the **start** of its phase, and
each phase ramps toward the *next* phase's value. At the landed `+-5 C`
amplitude this is invisible. At `-40 C` it inverts the season:

| Phase | Landed curve start -> end (with `core:cold = -46`) |
|---|---|
| `core:spore` | `+1` -> `-46` (the freeze happens during spore) |
| `core:cold` | `-46` -> `-2` (winter thaws for its entire length) |

The coldest instant of the year would land on the last day of `core:spore`, and
`core:cold` would warm monotonically from day one. This must be fixed before
the amplitude change, not after.

#### Proposed curve shape - phase-centered keyframes

Treat each authored profile value as the value at the **center** of its phase
and interpolate across the nearest two keyframes:

```text
progress  in [0, 0.5) -> blend previous -> current, t = smoothstep(progress + 0.5)
progress  in [0.5, 1] -> blend current  -> next,    t = smoothstep(progress - 0.5)
```

Properties this preserves:

- Continuity across the phase boundary is unchanged (both sides evaluate the
  same previous/current pair at the seam).
- Cost stays O(1): one extra profile lookup and one branch, no RNG, no loops.
- `TimeManager` remains the single season writer; `WeatherRuntime` remains the
  single writer of final axes.
- Applies identically to `temperature_offset_c`, `humidity_offset`, and the
  regime weight multipliers, so the three reads keep one shared curve.

Required companion fix: `get_season_progress()` currently returns `0.0` while a
developer override is active. Under phase-centered sampling `0.0` is the
*boundary* blend, not the authored value, so a forced season would no longer
show its own profile. Under override the progress read must report `0.5` so
`J`-forcing displays the authored phase center.

#### Proposed tuning

Weather regime bands are unchanged (`clear 14..16`, `cloudy 10..13`,
`overcast 6..9`), so each phase keeps a ~10 C weather spread around its center.

| Phase | Landed offset | Proposed offset | Resulting phase-center range (overcast..clear) |
|---|---:|---:|---|
| `core:warm` | `+6 C` | `+6 C` (unchanged) | `+12 .. +22 C` |
| `core:spore` | `+1 C` | `+1 C` (unchanged) | `+7 .. +17 C` |
| `core:cold` | `-5 C` | **`-46 C`** | **`-40 .. -30 C`** |
| `core:storm` | `-2 C` | **`-8 C`** (decided) | **`-2 .. +8 C`** |

> **Superseded by Iteration 7.** The shoulder values above produced a year that
> sat almost still for its first 25 days and then plunged. Iteration 7 rebalances
> `core:spore` and `core:storm` and changes the curve shape; see that section for
> the live tuning.

Humidity offsets and regime weight multipliers are unchanged by this iteration.

`core:storm` is the fourth **season phase** in the fixed
`WARM -> SPORE -> COLD -> STORM` cycle - the wet, overcast-weighted phase that
follows deep winter - and is not the storm *weather regime*. Its offset moves
from `-2 C` to `-8 C` because a `-46 C` winter followed by a `-2 C` phase climbs
44 C across half a phase and leaves the post-winter phase warmer than
`core:spore`'s low end. At `-8 C` the thaw stays plausibly cold.

Naming note (recommendation, not in this iteration's scope): with storms
confirmed as a weather regime that also occurs in warm phases, the season id
`core:storm` is misleading - the phase is defined by wetness and overcast bias
(`humidity_offset +0.12`, `clear` weight `0.45`, `overcast` weight `1.65`), not
by storms. Season ids and weather regime ids occupy separate namespaces, so
there is no functional collision, but a `core:storm` season profile will carry a
multiplier keyed `core:storm` for the regime. A rename to a thaw/wet identity
would touch `CORE_SEASON_IDS`, the profile resource id, and the stable-id
validation; the persisted `current_season` int is unaffected as long as the enum
order is preserved.

Resulting annual swing: `+22 C` at midsummer clear sky to `-40 C` at midwinter
overcast, i.e. a 62 C amplitude.

#### Downstream consequence - exposure curve saturates

`player_exposure_balance.tres` authors `cold_safe_temperature_c = +8` and
`cold_severe_temperature_c = -14`, and the component derives
`cold_target = inverse_lerp(safe, severe, effective_temperature)`.

At `-40 C` air, effective temperature reaches `-60 C` once `wind_chill_max_c`
(`8`) and `wet_chill_max_c` (`12`) apply, so `cold_target` clamps to `1.0` for
the entire phase. The documented monotonicity guarantee still holds, but the
readable gradient does not: dry-and-sheltered and soaked-in-wind produce an
identical pinned readout for the whole of winter.

**Decision (delegated to the agent): set `cold_severe_temperature_c` to
`-30 C`, and accept saturation inside deep winter as intended design.**

The honest finding is that no single threshold value fixes this. A linear
`inverse_lerp` cannot serve both a `+8..-14 C` damp-discomfort band and a
`-40..-60 C` lethality band. Widening to `-60 C` would restore a winter gradient
but would flatten shoulder-season cold to nearly nothing. The chosen value is
therefore a partial fix with a clear rationale:

| Case (air, chill applied) | Effective | `severe=-14` | `severe=-30` |
|---|---:|---:|---:|
| `core:warm` `+22`, dry | `+22` | `0.00` | `0.00` |
| `core:spore` `+7`, dry | `+7` | `0.05` | `0.03` |
| `core:spore` `+7`, wet+windy | `-13` | `0.95` | `0.55` |
| `core:storm` `-2`, dry | `-2` | `0.45` | `0.26` |
| `core:storm` `-2`, wet+windy | `-22` | `1.00` (pinned) | `0.79` |
| `core:cold` edge `-6.5`, dry | `-6.5` | `0.66` | `0.38` |
| `core:cold` center `-40`, dry | `-40` | `1.00` (pinned) | `1.00` (pinned) |

At the landed `-14 C` the scale already pins during the *shoulder* seasons
whenever the player is wet and exposed, which is where the warning is actually
actionable. `-30 C` restores that gradient for most of the year, keeps the ramp
into winter readable (the cold-phase edge reads `0.38`, rising as the player
walks deeper into the phase), and lets the deep-winter centre pin at `1.0`.

Pinning at the winter centre is treated as correct signalling rather than a
defect: at `-40 C` "do not be out here unprotected" is true, and a gradient there
would be false comfort. Making wind and wetness matter *again* inside deep
winter requires a non-linear response curve plus insulation terms, which belong
to the cold-consequences iteration of
[`player_wetness_and_cold_exposure.md`](../survival/player_wetness_and_cold_exposure.md),
not to a tuning pass. This limitation is recorded rather than hidden.

#### Downstream consequence - precipitation kind is temperature-blind

The rain resolver is humidity-driven and does not read temperature; kind stays
`NONE/RAIN`. After this retune, `core:cold` will produce **rain at `-40 C`**,
wet ground, puddles, player wetness, and the resulting `wet_chill`. At the
landed `+1 C` floor this was merely implausible; at `-40 C` it is a visible
correctness break. Snow is consequently no longer an independent follow-up - it
is coupled to this iteration and should be scheduled immediately after it.

#### Reserved seam - biome temperature modifiers

Confirmed design direction: biomes will inherit this weather and modify
temperature and related axes locally. That makes the current global read a
**base**, not a per-player truth.

This iteration does not implement the biome layer. It records the seam so the
amplitude change does not harden the wrong contract:

- `WeatherRuntime.get_temperature_c()` stays the authoritative **global base**
  outside-air value and keeps its single writer.
- A future position-resolved read is the correct home for biome, altitude, and
  shelter terms; it belongs to a separate spec with its own bounded lookup and
  dirty publication, per the existing escalation path in this document.
- The two current direct consumers that will need to move to the resolved read
  are `core/entities/components/player_exposure_component.gd` and
  `scenes/ui/hud/hud_weather_widget.gd`. No other gameplay consumer exists.
- The proposed `-40 C` is the **global base** at midwinter. Biome deviations are
  expected to sit around it in both directions rather than starting from it.

#### Resolved decisions

1. **`core:storm` season offset: `-8 C`.** Decided by the human owner. Rationale
   and the accompanying naming recommendation are in "Proposed tuning".
2. **Exposure curve: `cold_severe_temperature_c = -30 C`, deep-winter saturation
   accepted.** Delegated to the agent by the human owner; full rationale, the
   comparison table, and the recorded limitation are in the exposure-saturation
   section above.
3. **`-70 C` storms are a weather regime, not a season phase.** Decided by the
   human owner. Storms are an event that also occurs in warm phases - lightning,
   squall-force wind, and torrential rain - so the extreme belongs to regime
   authoring, not to the seasonal baseline. This keeps `core:cold` the coldest
   *phase* while allowing a storm event to drive far below it.

#### Deferred to a separate spec - the storm weather regime

The storm regime is explicitly **not** part of this iteration. It is a new
`WeatherRegimeProfile` plus new behaviour that this contract does not cover:

- New authored regime with its own bands, successor weights, and duration, added
  to the `clear <-> cloudy <-> overcast` graph.
- A temperature band far below the seasonal baseline (target `-70 C` when it
  strikes during `core:cold`), which makes the regime, not the season, the
  source of the annual extreme.
- New presentation and likely new axes: lightning flashes, squall-force wind
  targets, and torrential precipitation intensity beyond the current rain band.
- Interaction with the sanctuary constraint and the existing open-sky gating.

Two properties of the landed design already accommodate it without owner
changes: seasonal `weather_regime_weight_multipliers` default to `1.0` for
unknown ids, so a new regime needs no edit to the four season profiles unless it
should be season-biased; and regimes are pure data, so the graph extends without
touching `WeatherRuntime`.

This iteration must not pre-build any of it.

#### Acceptance criteria

- The authored profile value is observed at the center of its own phase, within
  tolerance, for all four phases.
- Sampled temperature is continuous across every phase boundary (no step at the
  seam) and its annual minimum lands inside `core:cold`, not `core:spore`.
- Annual minimum sampled temperature reaches approximately `-40 C`.
- A developer-forced season reports its own authored center values.
- Runtime work stays O(1); no new clock, RNG stream, save field, or owner.
- `cold_load` is no longer pinned at `1.0` during `core:spore` and `core:storm`
  for a wet, wind-exposed player, and still reaches `1.0` at the `core:cold`
  centre.
- No storm weather regime, precipitation-kind resolution, or biome temperature
  term is introduced by this iteration.
- Existing season, weather, weather-save, and HUD probes stay green after the
  retune, with expectation values updated where they encode the old amplitude.

#### Files allowed for this iteration

- `docs/02_system_specs/world/seasons_and_temperature_runtime.md`
- `docs/02_system_specs/survival/player_wetness_and_cold_exposure.md`
- `docs/02_system_specs/meta/system_api.md` (the `get_season_progress()` debug
  anchor description only)
- `core/autoloads/time_manager.gd`
- `data/seasons/cold.tres`, `data/seasons/storm.tres`
- `data/balance/player_exposure_balance.tres`
- `tools/season_runtime_probe.gd`
- `tools/weather_runtime_probe.gd`
- `tools/player_exposure_probe.gd`

#### Files forbidden for this iteration

- Precipitation-kind resolution, snow, and ice presentation.
- Biome, altitude, or shelter temperature terms and any position-resolved read.
- `WeatherRuntime` axis-composition logic and the weather regime resources.
- Save payload shapes, `world_version`, and worldgen.
- HUD structure beyond values already displayed.

#### Iteration 5 closure

Landed on 2026-08-03:

- `TimeManager` samples one shared phase-centered season curve
  (`_sample_season_curve`) for temperature, humidity, and regime weights, so the
  three public reads cannot diverge in shape. `get_season_progress()` reports the
  centre anchor `0.5` under developer forcing.
- `core:cold` moved to `-46 C` and `core:storm` to `-8 C`;
  `cold_severe_temperature_c` moved to `-30 C`. No other authored value changed.
- `WeatherRuntime`, the weather regime resources, the save payloads, and the HUD
  were not modified.

Verified headless in this iteration:

- Each phase reads its authored profile exactly at its own centre
  (`+6 / +1 / -46 / -8`), and a phase seam reads the midpoint of its two
  neighbours.
- The annual temperature minimum through `WeatherRuntime` is `-40.0 C` on day 38,
  inside `core:cold`. The earlier `core:spore`-anchored inversion is gone.
- Modifier continuity holds on all four seams. The continuity probe now derives
  its tolerance from the sampling gap (`gap * 1.5 * profile span`) instead of a
  fixed epsilon, so it stays valid at any amplitude; every measured delta came in
  at exactly half its analytic bound.
- The exposure gradient is restored in the shoulder phases and saturates only
  inside `core:cold`; the measured table is recorded in
  [`player_wetness_and_cold_exposure.md`](../survival/player_wetness_and_cold_exposure.md).
- `season_runtime_probe`, `weather_runtime_probe`, `weather_save_probe`,
  `player_exposure_probe`, and `hud_weather_metrics_probe` pass, as does
  `tools/agent/Invoke-AgentValidation.ps1` (format, lint, GdUnit).

Known-and-accepted after this iteration: rain still falls at `-40 C` because the
precipitation resolver is temperature-blind. Snow is now the required next step,
not an optional one.

### Iteration 6 - Season legibility and time controls — DONE

Design intent: make the season readable in play and make a 2-hour planetary year
verifiable without waiting for it. Two small additions that the V0 contract
deliberately deferred: a season readout in the existing weather HUD, and a
developer time-scale control for the `set_time_scale()` surface that currently
has no caller.

This iteration adds no owner, no save field, and no gameplay consequence.

#### 6a - Season name and phase progress in the HUD

V0 listed a season HUD label under "Out of Scope". This iteration lifts exactly
that restriction and nothing else.

Content plan for the existing top-right weather widget:

1. Keep the localized weather-regime name as the orientation line.
2. Add the localized season name and phase progress as a second orientation
   line, above the existing compact metric row.
3. Progress renders as `day N/15` derived from the authoritative day, not from a
   new counter.

The metric row (cloud cover, temperature, humidity) is unchanged. No new panel,
card, alarm channel, or entrance animation is introduced; the inside-powered
dimming treatment is inherited as-is.

`SeasonProfile` gains one field, mirroring `WeatherRegimeProfile`:

```text
display_name_key: StringName
```

Season names are therefore authored data and localization keys, never literal
strings in script or HUD code.

Proposed names. The four phases are alien-biology phases rather than Earth
seasons, and the polar-station register is deliberate:

| Season id | Key | RU | EN |
|---|---|---|---|
| `core:warm` | `SEASON_WARM` | Цветение | Bloom |
| `core:spore` | `SEASON_SPORE` | Споропад | Sporefall |
| `core:cold` | `SEASON_COLD` | Стужа | Deep Cold |
| `core:storm` | `SEASON_STORM` | Распутица | Thaw |

This also resolves the `core:storm` naming problem recorded in Iteration 5 at
the player-facing level: the phase presents as the wet thaw it actually is,
while the internal id stays `core:storm`, so `CORE_SEASON_IDS`, the stable-id
validation, and the persisted `current_season` int are all untouched. Renaming
the id remains optional and purely cosmetic after this.

#### 6b - Developer time scale

`TimeManager.set_time_scale()` exists and is currently called by nothing outside
`reset_for_new_game()`. This iteration binds it to a debug-build-only key,
alongside the existing `J` season cycle that `TimeManager` already owns.

- `L` cycles the scale `x1 -> x10 -> x60 -> x300 -> x1`, grouping with `J`
  (season) and `K` (weather regime).
- Gated on `OS.is_debug_build()` exactly like the existing `J` handler.
- Not persisted. `reset_for_new_game()` already restores `x1`; restore must do
  the same so a loaded save never starts accelerated.
- While the scale is not `x1`, and only in a debug build, the weather widget
  shows the multiplier so an accelerated session cannot be mistaken for a
  balance problem. This indicator is absent from release builds.

Accelerating time must not change any authoritative result: seasons, weather
successor selection, and save contents depend on the world clock, and scaling
the clock is indistinguishable from playing longer.

#### Resolved decision

Season display names were approved as proposed on 2026-08-03.

#### Acceptance criteria

- The weather widget shows the localized season name and `day N/15` phase
  progress, sourced from `TimeManager` reads only.
- Season names resolve through `display_name_key` and exist in both `ru` and
  `en`; no raw player-facing season string appears in script, HUD, or data.
- The existing metric row, panel structure, and dimming behaviour are unchanged.
- `L` cycles the documented scale ladder in a debug build and does nothing in a
  release build.
- Time scale is absent from save data, and both new-game and restore leave it at
  `x1`.
- At `x300`, the natural cycle still produces `WARM -> SPORE -> COLD -> STORM`
  with the same day boundaries as at `x1`.
- Runtime work stays O(1); the HUD adds two cached strings refreshed on the
  existing update interval.
- Existing season, weather, save, HUD, and localization probes stay green.

#### Files allowed for this iteration

- `docs/02_system_specs/world/seasons_and_temperature_runtime.md`
- `docs/02_system_specs/ui/ui_ux_foundation.md`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/localization_pipeline.md`
- `core/autoloads/time_manager.gd`
- `core/systems/world/season_profile.gd`
- `data/seasons/*.tres`
- `locale/ru/messages.po`, `locale/en/messages.po`
- `scenes/ui/hud/hud_weather_widget.gd`
- `tools/season_runtime_probe.gd`
- `tools/hud_weather_metrics_probe.gd`

#### Files forbidden for this iteration

- Weather axis composition, regime resources, and precipitation resolution.
- Season cadence, profile curve shape, and authored temperature/humidity values.
- Save payload shapes, `world_version`, and worldgen.
- Player survival, exposure, and any gameplay consequence of season.
- Other HUD clusters and any new panel.

#### Iteration 6 closure

Landed on 2026-08-03:

- `SeasonProfile` gained `display_name_key`, validated as non-empty alongside the
  existing stable-id checks, and the four core profiles author `SEASON_WARM`,
  `SEASON_SPORE`, `SEASON_COLD`, and `SEASON_STORM`.
- Both locales carry the four approved names. No literal season string exists in
  script, HUD, or data.
- `TimeManager` gained `get_season_display_name_key()`, `get_day_in_season()`,
  and `get_season_length_days()`. Phase day derives from the authoritative day;
  no counter was added.
- The weather widget shows the season line between the weather name and the
  compact metric row. The metric row, panel structure, and inherited dimming are
  unchanged.
- `L` cycles `x1 -> x10 -> x60 -> x300` in debug builds, sharing the existing
  `_unhandled_key_input` handler with `J`. An unrecognised scale falls to `x1` by
  the ladder wrap rather than a special case.
- `restore_persisted_state()` now resets the scale to `x1`; previously only
  `reset_for_new_game()` did, so a save loaded mid-session could have stayed
  accelerated.

Verified headless:

- Each phase returns its authored key, and every key resolves in both `ru` and
  `en` locale files.
- `get_day_in_season()` returns `1, 15, 1, 8, 15` for days `1, 15, 16, 38, 60`.
- The ladder cycles `x10 -> x60 -> x300 -> x1`; both new-game and restore leave
  it at `x1`; `save_collectors.gd` contains no `time_scale`.
- The widget's season line sits between the weather name and the metric row, and
  the time-scale indicator is gated on `OS.is_debug_build()`.
- `season_runtime_probe`, `hud_weather_metrics_probe`, `hud_exposure_probe`, and
  the weather/rain/snow/save/exposure probes all pass, as does
  `tools/agent/Invoke-AgentValidation.ps1`.

Final placement, type scale, and locale fit of the season line at representative
resolutions remain a windowed human check.

### Iteration 7 - Gradual annual curve and exitable season forcing — DONE

Two defects reported from play on 2026-08-03.

#### 7a - Season forcing was a one-way door

Reported as "the day counter reaches 15/15 and starts over in the same season".
The natural cadence was correct - measured `day 15: WARM 15/15` ->
`day 16: SPORE 1/15` and a full `WARM -> SPORE -> COLD -> STORM -> WARM` year.

The actual cause was `debug_cycle_season()`. One `J` press set a developer
override that could only be cleared by a new game or a load. The phase-day
readout kept advancing from the authoritative day while the displayed phase
stayed frozen, so the season looked permanently stuck:

```text
day 15: shows SPORE 15/15, naturally WARM
day 16: shows SPORE  1/15, naturally SPORE
day 60: shows SPORE 15/15, naturally STORM
```

Fix: the cycle now closes through the natural state -
`natural -> next phase -> ... -> last phase -> natural` - so forcing is always
exitable. `is_debug_season_forced()` was added and the HUD season line appends a
`FORCED` marker in debug builds, so a frozen phase can never again be mistaken
for a broken calendar.

#### 7b - The annual curve was flat, then abrupt

Reported as "too sharp a transition from `-40` straight to nearly positive".
Measured on the landed tuning: annual swing `52 C`, which is `1.73 C/day` if
spread evenly, against an actual peak of **`4.69 C/day`**. The sampled offset
showed the shape directly:

```text
d1:-0  d7:+6  d13:+5  d19:+2  d25:-1  d31:-25  d37:-45  d43:-36  d49:-15  d55:-7
```

The year barely moved for 25 days and then dropped 44 C in 12. Two causes
compounded:

1. **Keyframe distribution.** `core:warm +6` and `core:spore +1` were nearly
   identical, so the first half of the year was flat and over 85% of the annual
   variation was forced into two of the four transitions.
2. **Curve shape.** `smoothstep` has zero derivative at the keyframes and `1.5x`
   the average slope at the midpoint between them, concentrating change exactly
   where it was already steepest - a plateau at each phase centre followed by a
   rush.

Both were fixed.

**Interpolation: periodic Catmull-Rom** across the four keyframes, replacing
per-segment `smoothstep`. Each keyframe's tangent becomes
`(next - previous) / 2` instead of zero, so change spreads across the phase
instead of piling up at the seam. Authored values are still hit exactly at phase
centres (`t=0` returns `p1`, `t=1` returns `p2`), value and derivative stay
continuous across seams, and cost remains O(1) - four profile reads and one
polynomial, no RNG, no state.

Because the shoulder offsets are symmetric, the tangent at `core:cold` is exactly
`(storm - spore) / 2 = 0`, so the annual minimum stays exactly on the authored
value at the phase centre with no spline overshoot. The same holds at
`core:warm` for the maximum.

Catmull-Rom can overshoot between keyframes, which is harmless for temperature
and humidity (humidity clamps downstream) but would corrupt the weather selector
if a regime weight went negative. `get_weather_regime_weight_multiplier()`
therefore clamps at zero, holding the documented non-negative contract.

**Tuning: symmetric shoulders.**

| Phase | Previous | Live | Resulting phase-centre range (overcast..clear) |
|---|---:|---:|---|
| `core:warm` | `+6 C` | `+6 C` | `+12 .. +22 C` |
| `core:spore` | `+1 C` | **`-14 C`** | **`-8 .. +2 C`** |
| `core:cold` | `-46 C` | `-46 C` | `-40 .. -30 C` |
| `core:storm` | `-8 C` | **`-14 C`** | **`-8 .. +2 C`** |

The two shoulder phases are now thermally identical, which is what autumn and
spring physically are; they stay distinct through humidity and regime weights.

Result: peak daily change fell from `4.69 C` to **`2.86 C`** against the `1.73 C`
even-distribution baseline, and the flat stretch is gone - the sampled offset now
runs `+6 -> +3 -> -7 -> -18 -> -35 -> -46 -> -40 -> -23 -> -10` continuously.

#### Gameplay consequence of the rebalance

Measured full-year envelopes after the change:

| Phase | clear | cloudy | overcast |
|---|---|---|---|
| `core:warm` | `+14 .. +22` | `+10 .. +19` | `+6 .. +15` |
| `core:spore` | `-18 .. +14` | `-22 .. +11` | `-26 .. +7` |
| `core:cold` | `-32 .. -19` | `-36 .. -22` | `-40 .. -26` |
| `core:storm` | `-18 .. +14` | `-22 .. +11` | `-26 .. +7` |

At midday under an average regime, **35 of 60 days are below freezing**, running
from day 21 to day 55. Snow is now the common precipitation and rain is largely a
`core:warm` phenomenon. The shoulder phases genuinely straddle the freezing
point, so the rain/snow cross-fade band is exercised in play rather than only in
probes. This is a deliberate consequence of an even year at a 52 C amplitude: at
this swing, a gradual curve and mild shoulders are mutually exclusive. Milder
shoulders (around `-8 C`) would cut freezing days at the cost of returning some
of the abruptness.

#### Verification

- Natural cadence and the closed `J` cycle `SPORE -> COLD -> STORM -> natural`,
  ending un-forced.
- Peak daily offset step `2.86 C`, bounded by a new probe ceiling of `3.0 C`,
  with at most 6 near-static days in the year.
- Authored values still read exactly at phase centres (`+6 / -14 / -46 / -14`);
  annual minimum still `-40.0 C` inside `core:cold`.
- Seam values verified against hand-computed Catmull-Rom rather than the
  implementation: temperature `-0.75`, humidity `0.021875`, `clear` weight
  `0.89375` at the `STORM -> WARM` seam. All three matched exactly.
- Modifier continuity holds on all four seams under the scale-derived tolerance.
- Full probe suite and `tools/agent/Invoke-AgentValidation.ps1` pass.

Two probe expectations were corrected rather than defects: the phase-seam
assertions encoded a `smoothstep`-era "midpoint of two neighbours" assumption
that a four-keyframe spline does not satisfy, and `weather_runtime_probe`
required a strict `spore > storm` ordering that symmetric shoulders deliberately
make an equality. The latter now asserts the equality explicitly.

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
