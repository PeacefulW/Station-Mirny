---
title: Weather Runtime V0
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-06-29
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/WORKFLOW.md
  - ../meta/system_api.md
  - ../meta/event_contracts.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - wind_and_grass_scatter_presentation.md
  - cloud_occlusion_lighting.md
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
- Cloud-cover presentation is no longer owned by this spec's old screen-space
  overlay model. `WeatherRuntime` remains the state owner (`cloud_cover` and
  derived `get_cloud_occlusion()`); the active presentation contract lives in
  [`cloud_occlusion_lighting.md`](cloud_occlusion_lighting.md).
- A hard sanctuary constraint still applies to weather presentation: cloud
  darkness is an open-sky effect only; underground/roofed context is not
  darkened by cloud cover, and artificial / fire light remains the warm safety
  read (ADR-0005, NON_NEGOTIABLE_EXPERIENCE).
- Save of slow weather state only; local instantaneous values reconstruct on
  load (ADR-0007).

## Approval Closure

Approved on 2026-06-29 for V0: `WeatherRuntime` owns weather state, live
`cloud_cover` / wind targets, `weather_changed`, the derived
`get_cloud_occlusion()` read, and slow-state persistence. Remaining weather
tuning items below are balance/presentation follow-ups, not blockers for the V0
contract.

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
- Active cloud presentation depends on `DaylightSystem` reading
  `WeatherRuntime.get_cloud_occlusion()`; the old `WorldViewOverlay` cloud
  shadow / flatten / sun-ray screen passes are historical only.

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
| Cloud-cover presentation | `cloud_occlusion_lighting.md` readers (`DaylightSystem` + `CloudOccluderField`) |

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

## Cloud Presentation Model

> **SUPERSEDED / REMOVED FROM ACTIVE RUNTIME (2026-06-25).** The Iteration 2b
> presentation below — the `broken`/`deck`/`flatten`/`sun_ray` curves and their
> `CloudShadowOverlay` (screen-darkening), `OvercastFlattenOverlay`, and
> `SunRayOverlay` — has been removed from the live world scene and replaced by
> real sun occlusion: cloud cover blocks the real `DirectionalLight2D` sun
> (global energy drop at overcast, plus the `CloudOccluderField` world-space
> shader shadow layer in the top-down fallback renderer).
> The cloud-cover *state* and its owner (`WeatherRuntime`) are unchanged; only how
> cover becomes light changed. Source of truth for cloud presentation is now
> [`cloud_occlusion_lighting.md`](cloud_occlusion_lighting.md). The text below is
> retained only as historical context; tool/probe names mentioned inside this
> historical section were removed with the superseded implementation.

Cloud presentation is **realistic and regime-distinct**, driven by `cloud_cover`
through two separable response curves rather than one monotonic "more cover =
more shadow" ramp. The physical basis is the light source:

- **Clear / cloudy** — the sun is a near-point source, so discrete clouds cast
  **large, defined, drifting shadows** on the ground.
- **Overcast** — a continuous deck lights the ground from the whole sky dome
  (diffuse light), so there are **no distinct ground shadows** — only a uniform,
  flatter, cooler, desaturated read.

Therefore distinct cloud shadows are a *partly-cloudy* phenomenon and must
**fade out** toward overcast, not intensify. This inverts the naive model.

### Two response curves (pure functions of `cloud_cover`)

| Curve | Shape | Drives |
|---|---|---|
| `deck(cover)` | monotonic rise, max at overcast | ambient dim + cold tone, and the overcast flatten pass |
| `broken(cover)` | hump: ~0 at clear, peak across the cloudy band, ~0 by overcast | opacity of the discrete drifting cloud-shadow overlay; gate for rare sun rays |

Tuning anchors (aligned to the authored regime bands clear `[0,0.15]`, cloudy
`[0.35,0.62]`, overcast `[0.72,1.0]`; finalized by render probe):

- `broken(cover) ≈ smoothstep(0.15, 0.40, cover) * (1 - smoothstep(0.62, 0.88, cover))`
  — full across the cloudy band, gone by overcast.
- `deck(cover) ≈ smoothstep(0.30, 0.95, cover)` for dim/cool; the desaturate +
  contrast-cut strength rides a later-biting
  `flatten(cover) ≈ smoothstep(0.62, 1.0, cover)` so it only bites at true
  overcast.

### Per-regime target look

| Regime | Ground | Light / tone |
|---|---|---|
| Clear | even sunlight, no shadows | warm, bright |
| Cloudy | **large defined soft cloud shadows drift**; sunlit gaps stay full sun; high contrast | warm in the gaps, mild dimming; rare sun rays through breaks |
| Overcast | flat, even, **no distinct shadows**; low contrast | cold, dim, desaturated ("leaden / overcast") |

### Four presentation levers

1. **Ambient** (folded into `Daylight`): dim + cold tone, scaled by
   `deck(cover)`, surface-only (sanctuary). In the **cloudy** regime the ambient
   stays near full brightness/warmth, so unshadowed gaps read as **direct sun** —
   the "bright gaps" effect is "don't dim the gaps + lay dark shadows", not an
   additive highlight (a multiply ambient cannot brighten above base).
2. **Broken cloud shadows** (`CloudShadowOverlay`): large, soft, world-locked
   drifting footprints from the seamless noise texture (precision-safe), opacity
   = `broken(cover)`, with a **large** feature scale (a cumulus footprint, not
   fine dapple). The footprint is a mask only: the shader reads the already
   rendered surface (`hint_screen_texture`) and darkens that image, so it reads
   like a normal object shadow rather than a colored paint layer. Opacity-led
   fade keeps transitions band-free even at large scale.
3. **Overcast flatten pass** (NEW surface layer): a screen-space pass that reads
   the already-rendered surface (screen texture), pulls it toward neutral grey
   and compresses contrast, strength = `flatten(cover)`. This is what makes
   overcast read as a flat leaden deck rather than merely "darker". Surface-only.
4. **Rare sun rays** (NEW surface layer): a subtle additive-ish world-space
   overlay in the **cloudy** band only, gated by `broken(cover)` and sparse
   noise so it appears as occasional warm streaks in direct-sun breaks. It is a
   presentation accent, not gameplay light: it does not define safety, does not
   affect visibility authority, and fades out before overcast.

### Sanctuary under the surface passes

All three surface presentation passes — cloud-shadow darkening, sun rays, and the
flatten pass — are full-screen and **gated by surface context**
(`_is_surface_context()`, `z == 0`, exactly like the ambient tone shift): they do
**nothing** underground or in roofed/interior context, so weather never intrudes
on the safe space. Every surface overlay MUST carry this gate; a missing gate on
any one of them is a sanctuary regression. Historical cloud-shadow probes
asserted `cloud_cover` is `0` underground. Within an open-surface scene a
pure screen pass has no light map, so it cannot yet spare a warm island around a
campfire / electric light. V0 accepts this coarse context-gate and **reserves**
a per-light warmth mask for when the ADR-0005 gameplay light map exists; the
pass is structured to multiply its strength by such a mask later. This is an
explicit, documented limitation with a reserved hook — not a silent fallback.
The warm-island guarantee for base/fire/electric is fully met underground and
under roofs in V0; on open surface it is approximate until the light map lands.

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
- Active cloud occlusion presentation is O(1) in this spec's owner: consumers
  pull one derived scalar. Rendering costs are owned by
  `cloud_occlusion_lighting.md`.
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
  presentation and wind change);
- `WindRuntime` is driven by the weather target while still publishing the same
  `wind_*` globals; grass, dust, and the HUD wind readout are unchanged;
- reserved axes exist in the contract with neutral values and no consumers;
- slow weather state round-trips through save/load; live values reconstruct;
- `weather_changed` fires on regime change and once on init;
- the per-frame cost is O(1) with no tile/chunk loops (static check);
- a clear sky renders with negligible cloud-presentation cost;
- cloud darkness affects open sky only: underground/roofed context is not
  reduced by cover, and base/campfire/electric light reads stay warm
  (sanctuary constraint), proven by the active cloud-occlusion probes/manual
  render checks.

## Failure Cases / Risks

This design is wrong if:

- weather gains a second writer or each effect keeps its own clock;
- regimes become hardcoded branches instead of data;
- reserved axes get half-wired consumers that read undefined values;
- the owner does per-frame work that scales with the world;
- save stores live values instead of slow state (breaks reconstruction).

## Open Questions

Remaining V0 tuning (not approval blockers):

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
- Active cloud presentation moved to
  [`cloud_occlusion_lighting.md`](cloud_occlusion_lighting.md): cloud cover now
  derives a real sun-occlusion scalar and a bounded `CloudOccluderField` shader
  layer. The old `broken` / `deck` / `flatten` / `sun_ray` screen-space overlay
  model below is retained only as superseded implementation history.

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
  a transition probe (horizontal luma spread stays flat across the
  `cloud_cover` ramp, with no mid-transition spike).
- Noise source: the field is sampled from a **seamless procedural noise texture**
  (`FastNoiseLite` → `NoiseTexture2D`, `repeat_enable` + mipmaps), not a
  hand-rolled `fract()` hash. Cloud shadows are world-locked, so `world_pos` is
  large; a hash-based noise loses low bits at large coordinates and quantizes
  into a rectangular grid (observed "blocky / cut-off clouds" artifact away from
  the origin). Hardware texture wrap keeps full precision within the tile.
  Guarded by a shader isolation probe (sharp-edge fraction at far world
  coordinates stays approximately the near-origin baseline).
- Cold desaturated ambient tone shift folded into the existing `Daylight`
  ambient (`COLOR_OVERCAST_TINT`, applied only when `_is_surface_context()`),
  with the sanctuary constraint (outside-ambient only; underground neutral;
  light sources stay warm / will override locally).
- Dev visibility helpers (requested while validating): `WeatherRuntime`
  `debug_cycle_regime()` smooth ping-pong (player hotkey **K**) and a
  `HudWeatherWidget` top-right readout (`UI_HUD_WEATHER`: regime name + cloud %).
- Historical weather/cloud probe: overcast darker + colder than clear;
  cloud shadows present at overcast and markedly stronger than clear-sky; clear
  near-cloudless; sanctuary holds (underground ambient stays neutral under
  overcast). All checks pass.

### Iteration 2b — Realistic, regime-distinct cloud presentation — DONE, SUPERSEDED

Reworked Iteration 2's "more cover = more dapple" into the **Cloud Presentation
Model** (two response curves). This implementation was later superseded and
removed from active runtime by
[`cloud_occlusion_lighting.md`](cloud_occlusion_lighting.md) Iteration 2, which
uses the real `DirectionalLight2D` sun instead of screen-space overlays.

- Split presentation into the two curves: `broken(cover)` (hump) drives
  `CloudShadowOverlay` opacity; `deck(cover)` (monotonic) drives the `Daylight`
  dim/cool and the new flatten pass. Curves are pure functions of `cloud_cover`
  (tuning anchors in the model section).
- `CloudShadowOverlay`: move to **large** soft cumulus-footprint scale; opacity
  = `broken(cover)` (so shadows peak in cloudy, fade by overcast). Keep the
  seamless-noise base (precision-safe) and opacity-led fade (band-free). The
  shader reads `hint_screen_texture` and darkens the rendered surface through
  the mask, rather than drawing a separate cloud-shadow color.
- `Daylight` ambient: dim/cool = `deck(cover)`, but **keep cloudy near full
  brightness** so unshadowed gaps read as direct sun (high lit-vs-shadow
  contrast).
- New `OvercastFlattenOverlay` (surface screen-space pass, `hint_screen_texture`):
  desaturate toward grey + compress contrast, strength = `flatten(cover)`;
  surface-context gated (sanctuary); reserved per-light warmth-mask hook.
- New `SunRayOverlay` (surface world-space presentation pass): sparse warm rays
  in cloudy gaps, strength gated by `broken(cover)`, fades to zero by overcast;
  presentation-only, not ADR-0005 gameplay light.
- Sanctuary: all three surface overlays (cloud shadows, sun rays, flatten) gate
  on surface context (`cloud_cover`/strength forced to `0` when `z != 0`), so the
  underground stays neutral. These checks are historical; the active runtime now
  uses the `cloud_occlusion_lighting.md` probe set.
- Probes:
  - historical weather/cloud render probe — **cloudy** has high *local* contrast (sunlit
    gaps + dark shadows); **overcast** has *low* local contrast and is
    desaturated; and the **inversion** holds: distinct-shadow strength at
    overcast < at cloudy. Sun rays are measurable in cloudy and gone by
    overcast.
  - transition and shader-isolation probes stayed flat/smooth at the new large
    scale and far coordinates.
  - `cloud_shadow_style_probe` locks the readable style: large footprint,
    screen-space darkening, no `cloud_shadow_color`, bounded peak darkening.
  - sanctuary: flatten pass leaves underground/roofed context neutral (warm
    open-surface island reserved for the light map).
- Doc updates: this section; `system_api.md` if a new overlay exposes a public
  surface; localization unaffected (no new user-facing strings).

### Iteration 3 — Save/load slow state — DONE

- Persist active/next regime + transition + duration timer; reconstruct live.
- Landed as `WeatherRuntime.export_save_dict()` / `restore_persisted_state()`,
  wired through `SaveCollectors.collect_weather()` /
  `SaveAppliers.apply_weather()` into a `weather.json` slot section. Live axes
  (`cloud_cover`, wind targets, reserved axes) are NOT saved — they reconstruct
  from the restored regime + clock. `_weather_time_hours` is persisted so cloud
  breathing and the heading meander stay continuous across load. On restore,
  `_last_hour` resets so the next `time_tick` re-syncs the delta without a jump;
  an unknown regime id or a missing `weather.json` falls back to `core:clear`.
- Additive section: no `WORLD_VERSION` bump, old saves stay load-compatible.
- Probe: `tools/weather_save_probe.gd` (headless) — evolved state survives
  export → reset → restore bit-for-bit, live axes reconstruct from a restored
  mid-transition, old-save/unknown-regime default to clear, and the
  collect/apply pair round-trips the same state.
- Doc updates: `packet_schemas.md` (`WeatherSaveData` + slot-layout row),
  `save_and_persistence.md` (weather slow-state section).

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

## Out-of-scope observations

Found while verifying Iteration 2b; not addressed here, tracked for follow-up:

- `DustWindOverlay` has no surface-context gate (predates this work), so dust
  would also render underground. The same one-line `z`-gate the weather overlays
  use should be applied; until then it is a latent sanctuary leak independent of
  weather.
- Both the cloud-shadow and flatten passes read `hint_screen_texture`, i.e. two
  full-screen back-buffer copies per frame on the surface. Bounded and within
  budget, but the cloud-shadow darkening could be a multiply blend without a
  screen read if the copy cost ever matters.
- Overcast keeps a residual large-scale shadow in the lower overcast band
  (`cover` ~0.72–0.88, `broken` up to ~0.34). If a deader-flat overcast is
  wanted, pull `broken`'s fade earlier or strengthen `flatten`. Tuning only.
