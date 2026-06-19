---
title: Weather Runtime V0
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.3
last_updated: 2026-06-13
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - wind_and_grass_scatter_presentation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0004-host-authoritative-multiplayer.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Weather Runtime V0

## Purpose

Define one authoritative owner of weather — `WeatherRuntime` — that drives wind,
cloud cover, precipitation, temperature, and humidity from a single evolving
weather state, instead of each effect (wind, dust, future rain) inventing its
own clock and curves.

The owner is designed for **all** weather axes from day one, but V0 only makes
**cloud cover** and **wind** live. The remaining axes (precipitation,
temperature, humidity) exist in the contract as neutral, stable, consumer-less
values so later work plugs them in without touching the owner. This keeps the
system extensible and cheap: one O(1)-per-frame owner, data-driven regimes,
and pull-model reads.

## Gameplay Goal

The outside should feel like a place with weather, not a static skybox: the sky
clouds over and clears across hours, wind rises and falls with the weather mood,
and (later) rain, cold, and damp press on the player. This reinforces the
non-negotiable inside-safe / outside-hostile contrast — bad weather makes the
sanctuary matter more.

V0 goal: visible slow transitions between **clear** and **overcast**, with wind
strength and gustiness tied to the current weather, so the player can read "the
weather is turning" before any survival mechanic exists.

## Scope

V0 includes:

- `WeatherRuntime` autoload: single writer of weather state; O(1) per-frame;
  paused with the game.
- A full weather-state contract with all axes present
  (`cloud_cover`, `wind_target`, `precipitation`, `temperature`, `humidity`)
  but only `cloud_cover` and `wind_target` evolving in V0.
- Data-driven **weather regimes** (`WeatherRegimeProfile` resources): clear,
  cloudy, and overcast in V0, with adjacent-only transitions
  (clear <-> cloudy <-> overcast — weather builds and eases through cloudy,
  it does not jump clear -> overcast). The resource shape is ready for
  `storm` and modded regimes.
- Deterministic slow evolution of the active regime from world seed + world
  clock (so it is reproducible and multiplayer-host-reproducible later).
- `WindRuntime` becomes a **subordinate** of `WeatherRuntime`: weather sets the
  target wind base (strength band, heading, gust character via the wind
  profile); `WindRuntime` stays the low-level publisher of the `wind_*` global
  shader uniforms. No new wind owner.
- A `weather_changed` domain event on regime change; smooth per-axis values are
  read pull-model (getters), not event-per-frame.
- One V0 presentation consumer: a cloud-cover overlay (world-space full-screen
  shader, same cheap pattern as dust) that, as `cloud_cover` rises, darkens
  the ground, drifts cloud shadows across it, and shifts the ambient tone
  cold and desaturated ("the weather turns"). The tone shift rides the
  existing `Daylight` ambient so it costs nearly nothing.
- A hard sanctuary constraint: weather ambient (darkening + cold tone shift)
  is an **outside-ambient** effect only. It must not cool or dull the warm
  read inside the base, at a campfire, or under electric lighting, nor the
  underground. Artificial / fire light defines safety (ADR-0005,
  NON_NEGOTIABLE_EXPERIENCE); the colder and bleaker the weather outside, the
  warmer those light islands must feel by contrast. Until the gameplay light
  system (ADR-0005) lands, weather ambient simply leaves the underground
  neutral (as day/night already does) and is structured so light sources will
  override it locally rather than be tinted by it.
- Save of slow weather state only; local instantaneous values reconstruct on
  load (ADR-0007).

## Out of Scope

V0 explicitly does not include:

- live precipitation, temperature, or humidity behaviour (fields exist, values
  are neutral and have no consumers yet);
- rain/snow particles or precipitation gameplay;
- temperature/humidity gameplay effects (survival, ice, fire spread);
- per-tile or per-chunk weather (weather is one global state in V0);
- regional/biome-varying weather maps;
- multiplayer replication wiring (the determinism + host-authoritative design
  is reserved, not implemented);
- a forecast UI beyond what already exists for wind.

## Related Documents

- `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`
- `docs/05_adrs/0004-host-authoritative-multiplayer.md`
- `docs/02_system_specs/world/wind_and_grass_scatter_presentation.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/system_api.md`

## Dependencies

- `TimeManager` for the world clock and season (weather reads time; time does
  not read weather).
- `WindRuntime` as the low-level wind publisher that weather drives.
- Registry/data-resource loading for `WeatherRegimeProfile`.
- The `WorldViewOverlay` base class for the cloud-cover presentation layer.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Environment runtime state (ADR-0007 layers 2 slow + 3 local). Authoritative for gameplay later; presentation is derived. Not worldgen, not terrain truth. |
| Save/load required? | Yes, slow state only (active regime + transition phase). Local values reconstruct. |
| Deterministic? | Regime evolution is deterministic from seed + world clock; per-frame smoothing is continuous and reproducible from that. |
| Must it work on unloaded chunks? | Weather is global, not chunk-bound; it has no per-chunk dependency. |
| C++ compute or main-thread apply? | Pure GDScript orchestration: a few scalar evaluations per frame. No native, no heavy loops. |
| Dirty unit | One global weather state struct. |
| Single owner | `WeatherRuntime`. Wind publication owner stays `WindRuntime` (subordinate). |
| 10x / 100x scale path | Cost is independent of world/object count by construction (one global state). |
| Main-thread blocking risk | None: O(1) per frame. |
| Hidden fallback? | None. If a regime resource is missing, fail explicitly at bootstrap. |
| Could it become heavy later? | Only if weather becomes per-region; that is a future spec, explicitly out of scope here. |
| Whole-world prepass? | No. No startup prepass; state evolves at runtime from the clock. |

## Data Model

### Weather state (runtime, owned by `WeatherRuntime`)

```text
WeatherState
{
  regime_id: StringName,        # active regime, e.g. "core:clear"
  transition: float,            # 0..1 blend toward the next regime
  next_regime_id: StringName,   # regime being blended toward
  # --- live axes (V0) ---
  cloud_cover: float,           # 0 clear .. 1 overcast
  wind_target_strength: float,  # 0..1 base wind strength for WindRuntime
  wind_target_heading_deg: float,
  wind_gustiness: float,        # 0..1 gust character for WindRuntime
  # --- reserved axes (V0: neutral, no consumers) ---
  precipitation_kind: int,      # 0 none (enum reserved: rain, snow, ash, spore)
  precipitation_intensity: float,
  temperature_c: float,         # neutral baseline in V0
  humidity: float,              # neutral baseline in V0
}
```

Reserved axes are part of the contract so consumers can be added later without
changing the owner. They hold neutral values in V0 and are documented as
"not authoritative yet".

### `WeatherRegimeProfile` (authored data resource)

```text
WeatherRegimeProfile
{
  id: StringName,                       # "core:clear", "core:overcast"
  display_name_key: StringName,
  cloud_cover: Vector2,                 # min/max band
  wind_strength: Vector2,               # min/max band fed to WindRuntime
  wind_gustiness: Vector2,
  heading_drift_deg: float,
  # reserved bands (V0 neutral)
  precipitation_kind: int,
  precipitation_intensity: Vector2,
  temperature_c: Vector2,
  humidity: Vector2,
  # transition weighting to other regimes (data-driven graph)
  successor_weights: Dictionary,        # regime_id -> weight
  min_duration_hours: float,
  max_duration_hours: float,
}
```

Regimes are data: adding `cloudy`, `storm`, or a modded regime is a new
resource plus successor weights, no owner code change.

### Regime evolution

- The owner holds the active regime, a remaining-duration timer, and a blend
  toward the next regime.
- When a regime's duration elapses, the next regime is chosen deterministically
  (seeded hash of world-day + regime) weighted by `successor_weights`, then
  blended over a transition window. `successor_weights` are adjacent-only in
  V0 (`clear`<->`cloudy`<->`overcast`); the graph can be any shape later.
- Regime selection is a single function `select_next_regime(current, clock,
  seed, season)`. In V0 `season` is accepted but does not bias the weights
  (the hook exists so a later iteration adds seasonal weather as a data
  multiplier without changing the owner).
- Live axis values are the regime band sampled by a slow continuous noise
  (so cloud cover and wind breathe within a regime), blended across transitions.
- A new game starts in `clear`.
- V0 ships three regimes (`clear`, `cloudy`, `overcast`) so transitions are
  visible; the graph and blending are the same code for any future regime
  count.

## Runtime Architecture

### Owners

| Concern | Owner |
|---|---|
| Weather state + regime evolution | `WeatherRuntime` |
| Regime behaviour data | `WeatherRegimeProfile` resources |
| Wind publication to shaders | `WindRuntime` (driven by weather target) |
| Cloud-cover presentation | cloud overlay (`WorldViewOverlay` subclass) |

### Wind subordination

`WeatherRuntime` writes the **target** wind (strength band, heading, gustiness)
that `WindRuntime` aims at. `WindRuntime` keeps its accumulators and the
`wind_*` global-uniform publication exactly as today; only the *source of its
target* moves from a hardcoded profile to the weather state. Wind **heading
drift** lives in the regime (`heading_drift_deg`): weather decides direction
behaviour (a storm swings, clear holds steady). `WorldVisualWindProfile`
keeps only the gust *shape* (per-instance flutter/gust math), not direction or
strength.

This is the minimum-change path: grass, dust, and the HUD wind readout keep
reading `WindRuntime` unchanged.

### Read model

- Smooth values (`cloud_cover`, wind targets, future temperature/humidity) are
  **pull-model**: consumers call `WeatherRuntime` getters each frame as needed.
- Only the discrete `weather_changed` event fires on regime change, for UI,
  audio, and mods that react to "the weather turned".

### Determinism & multiplayer reservation

Regime selection is a seeded function of the world clock, so it is reproducible
and, later, host-authoritative with presentation-only clients (ADR-0004/0007).
V0 is single-player; no replication is wired, but no design choice blocks it.

## Event Contracts

V0 adds one domain event (to be documented in `event_contracts.md` at
implementation time):

- `weather_changed(regime_id: StringName, previous_regime_id: StringName)` —
  emitted by `WeatherRuntime` on regime change and once on initial state.

Smooth values are not events; they are read through getters.

## Save / Persistence Contracts

- Persist **slow state only**: active `regime_id`, `next_regime_id`,
  `transition`, and the remaining-duration timer.
- Live axis values (`cloud_cover`, wind targets, reserved axes) are NOT saved;
  they reconstruct from the regime + clock on load.
- This adds a `WeatherSaveData` shape to `packet_schemas.md` and a field to the
  world/meta save payload at implementation time (ADR-0007: only slow world
  state is saved).

## Performance Class

- Runtime class: `interactive`-frame O(1) — a handful of scalar evaluations and
  getter reads per frame; no loops over tiles/objects/chunks.
- Cloud overlay: one full-screen world-space shader (same cost class as the
  dust overlay), gated so a clear sky is nearly free.
- No native code, no per-chunk work, no startup prepass.

## Modding / Extension Points

- New weather regimes are new `WeatherRegimeProfile` resources + successor
  weights; no owner change.
- New axes (e.g. lightning, fog density) are new state fields + consumers; the
  owner publishes, consumers pull.
- Mods subscribe to `weather_changed` instead of patching the owner.
- Localization: regime display names use `display_name_key` (RU+EN required
  when surfaced in UI).

## Acceptance Criteria

V0 is acceptable when:

- `WeatherRuntime` is the single owner of weather state; no other system writes
  it;
- regimes are data resources (clear + cloudy + overcast ship) with
  adjacent-only transitions, and adding a regime needs no owner code change;
- `cloud_cover` and wind targets evolve and transition visibly over time
  (render/log probe shows clear -> overcast -> clear with matching cloud
  overlay and wind change);
- `WindRuntime` is driven by the weather target while still publishing the same
  `wind_*` globals; grass, dust, and the HUD wind readout are unchanged;
- reserved axes exist in the contract with neutral values and no consumers;
- slow weather state round-trips through save/load; live values reconstruct;
- `weather_changed` fires on regime change and once on init;
- the per-frame cost is O(1) with no tile/chunk loops (static check);
- a clear sky renders with negligible cloud-overlay cost;
- the weather ambient tone shift affects outside ambient only: the
  underground stays neutral, and base/campfire/electric light reads stay warm
  (sanctuary constraint), proven by a render probe comparing an overcast
  outside vs a lit interior/light source.

## Failure Cases / Risks

This design is wrong if:

- weather gains a second writer or each effect keeps its own clock;
- regimes become hardcoded branches instead of data;
- reserved axes get half-wired consumers that read undefined values;
- the owner does per-frame work that scales with the world;
- save stores live values instead of slow state (breaks reconstruction).

## Open Questions

Remaining (tuning, not blockers for Iteration 1):

- Regime durations for V0 (`min/max_duration_hours` per regime) — how long
  weather lingers. A balance pass on the authored bands, decided when the
  transitions are visible in-game.
- Transition window length (how slowly one regime blends into the next).
- Default `cloud_cover` / wind bands per regime — authored numbers tuned by
  render probe in Iteration 2.

Resolved:
- Regime graph = `clear` <-> `cloudy` <-> `overcast` (three regimes,
  adjacent-only transitions); a new game starts in `clear`.
- Wind heading drift lives in the regime (`heading_drift_deg`);
  `WorldVisualWindProfile` keeps only gust shape.
- Season does NOT bias regime selection in V0; the selection function takes a
  `season` argument as a reserved hook for a later data-driven seasonal bias.
- Cloud presentation = darkening + drifting cloud shadows + a cold,
  desaturated ambient tone shift via `Daylight`, with the sanctuary
  constraint above (no effect on base/fire/electric/underground light).

## Implementation Iterations

### Iteration 0 — Spec landing — DONE

- Land this spec; link both doc indexes; no runtime code.

### Iteration 1 — Owner + wind subordination — DONE

- Add `WeatherRuntime` autoload and `WeatherRegimeProfile`
  (clear + cloudy + overcast, adjacent-only transitions, start in clear).
- Move `WindRuntime`'s target source to the weather state; keep its publication
  unchanged.
- `weather_changed` event; getters for live axes.
- Probe: regime transitions over accelerated time; wind responds; grass/dust/HUD
  unchanged.
- Doc updates: `event_contracts.md` (new event), `system_api.md`
  (`WeatherRuntime` reads + `WindRuntime` note).

### Iteration 2 — Cloud-cover presentation — DONE

- Cloud overlay (`CloudShadowOverlay`, a `WorldViewOverlay` subclass +
  `cloud_shadow_overlay.gdshader`) driven by `cloud_cover`: drifting fbm
  cloud-shadow field, density/coverage rising with cover, drift on `wind_*`
  globals, empty below `cloud_cover < 0.02`. Sits under `Daylight`.
- Transition behaviour: the shadow field is multi-scale and **small-scale-led**
  (no single screen-spanning blob), and fade-in is led by **opacity**
  (`cover_op`) with a deliberately narrow shape-threshold range. This avoids a
  low-frequency iso-contour sweeping across the view once as the threshold drops
  during a regime change (observed "vertical band" artifact). Guarded by
  `tools/cloud_transition_probe.gd` (horizontal luma spread stays flat across
  the `cloud_cover` ramp, with no mid-transition spike).
- Noise source: the field is sampled from a **seamless procedural noise texture**
  (`FastNoiseLite` → `NoiseTexture2D`, `repeat_enable` + mipmaps), not a
  hand-rolled `fract()` hash. Cloud shadows are world-locked, so `world_pos` is
  large; a hash-based noise loses low bits at large coordinates and quantizes
  into a rectangular grid (observed "blocky / cut-off clouds" artifact away from
  the origin). Hardware texture wrap keeps full precision within the tile.
  Guarded by `tools/cloud_shader_iso.gd` (sharp-edge fraction at far world
  coordinates stays ≈ the near-origin baseline).
- Cold desaturated ambient tone shift folded into the existing `Daylight`
  ambient (`COLOR_OVERCAST_TINT`, applied only when `_is_surface_context()`),
  with the sanctuary constraint (outside-ambient only; underground neutral;
  light sources stay warm / will override locally).
- Dev visibility helpers (requested while validating): `WeatherRuntime`
  `debug_cycle_regime()` smooth ping-pong (player hotkey **K**) and a
  `HudWeatherWidget` top-right readout (`UI_HUD_WEATHER`: regime name + cloud %).
- Probe (`tools/weather_cloud_probe.gd`): overcast darker + colder than clear;
  cloud shadows present at overcast and markedly stronger than clear-sky; clear
  near-cloudless; sanctuary holds (underground ambient stays neutral under
  overcast). All checks pass.

### Iteration 3 — Save/load slow state

- Persist active/next regime + transition + duration timer; reconstruct live.
- Doc updates: `packet_schemas.md` (`WeatherSaveData`),
  `save_and_persistence.md`.

### Later (out of V0)

- Precipitation axis + rain/snow presentation.
- Temperature/humidity gameplay (survival, ice, fire).
- Regional/biome weather; multiplayer replication.

## Required Updates

At implementation time (not in spec landing):

- `event_contracts.md` — add `weather_changed`.
- `system_api.md` — add `WeatherRuntime` public reads; note `WindRuntime` is
  weather-driven.
- `packet_schemas.md` — add `WeatherSaveData` when save lands.
- `save_and_persistence.md` — add slow weather state to the save payload.
- `wind_and_grass_scatter_presentation.md` — note that wind target now comes
  from `WeatherRuntime`.
