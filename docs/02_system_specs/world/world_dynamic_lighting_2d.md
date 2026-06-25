---
title: World Dynamic Lighting 2D — Sun, Torch, Ambient
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.0
last_updated: 2026-06-24
related_docs:
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - plains_ground_cosmetic_shading.md
  - ../progression/player_sun_shadow_v0.md
---

# World Dynamic Lighting 2D — Sun, Torch, Ambient

## Purpose

Introduce **real Godot 2D lighting** (`CanvasModulate` ambient + `DirectionalLight2D`
sun + `PointLight2D` torch/lamps) so that:
- terrain `NORMAL_MAP` finally produces volume (pebbles/pits relief) under a moving
  sun, and
- a player-carried torch lights the world dynamically (warm pool in the dark) — the
  core "inside-safe / outside-hostile" atmosphere.

This is the **visual** half of the ADR-0005 light system.

## ADR-0005 boundary (non-negotiable)

[ADR-0005](../../05_adrs/0005-light-is-gameplay-system.md): light is a **gameplay**
system; gameplay reads a light/visibility **authority**, not the renderer. This spec
builds only the **visual illumination** (light/normal shading + torch glow). The
gameplay visibility authority (fauna AI, stress, sanctuary truth) is **separate and
NOT derived from these Light2D nodes** — noted here, not built here. No system may
query the renderer/lights for gameplay visibility.

## Validation (done)

Dev probe `tools/ground_light_probe.gd` (not a runtime path) confirmed on the live
world scene: shaders are light-aware (not `unshaded`), the torch `PointLight2D` pool
reads in a dark ambient, and `DirectionalLight2D` lights the ground. Captures in
`artifacts/ground_light_probe/`.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical data, overlay, or visual only? | Visual illumination only. |
| Save/load? | No. |
| Deterministic? | Lighting is presentation; sun model from time-of-day, torch from player. |
| C++ or main thread? | Engine 2D lighting (GPU) + a few light nodes on the main thread. |
| Single owner | Sun/ambient driven by the daylight/`WorldVisualLightingProfile` model; torch owned by the player. |
| 10x/100x | Lights without shadows are cheap; occluder shadows (Iter 2) are bounded by proximity. |
| Hidden fallback? | No. |
| Gameplay coupling | NONE — visual only; gameplay visibility authority is a separate later contract. |

## Scope

### Iteration 1 — Lights + normal relief (no cast shadows)
- Rework the existing `DaylightSystem` `CanvasModulate` to be the **ambient floor**
  (lower values: bright-ish day, dark night) instead of a near-full tint.
- Add a `DirectionalLight2D` **sun**: angle/energy/colour driven by the same
  time-of-day model (`WorldVisualLightingProfile`), so terrain normals get relief
  that shifts with the day.
- Add a `PointLight2D` **torch** on the player (warm, ranged), `shadow_enabled=false`
  → moving pool of light + local normal relief at night.
- Reconcile with the existing in-shader cosmetic ground shade (reduce/disable the
  baked directional term once the real sun does directional shading — avoid
  double-darkening). Baked sprite shading (rocks/trees) stays as-is (they have no
  NORMAL_MAP; lights modulate them flatly).
- Depends on quality terrain normal maps (authored externally) for the relief payoff.

### Iteration 2 — Cast shadows (occluders)
- `LightOccluder2D` on **significant near-player objects** (trees, big rocks, walls),
  proximity-activated (LAW 13) — NOT on mass decor (grass/pebbles).
- `shadow_enabled` on sun (long day shadows) and torch (moving shadows as the player
  walks — the atmospheric goal). Bounded cost = lights × occluders in range.

## Out of Scope
- Gameplay visibility authority (fauna/stress/sanctuary) — separate ADR-0005 contract.
- Occluders on mass decor.
- Save/EventBus/packet/command changes.

## Performance Class
- Iter 1: a `DirectionalLight2D` + one `PointLight2D`, no shadows → cheap GPU.
- Iter 2: shadow maps scale with lights × in-range occluders; keep occluders
  proximity-bounded. Background/visual; no interactive CPU path.

## Integration Risks
- **Project-wide look change:** the `CanvasModulate` rebalance re-lights the entire
  world. Validate in the probe before promoting to `world_runtime_v0.tscn`.
- **Double-darkening:** the in-shader cosmetic ground shade + real sun can compound;
  reduce the shader term in Iter 1.
- **Relief depends on normals:** weak terrain normals = little volume; the payoff
  needs the authored Blender normal maps.
- **CanvasModulate × Light2D interplay:** ambient floor must be low enough that the
  sun/torch read, high enough that unlit areas aren't pure black (except intended night).

## Acceptance Criteria
- [ ] `DaylightSystem` drives an ambient floor; a `DirectionalLight2D` sun + player
      `PointLight2D` torch exist and follow the time-of-day / player.
- [ ] Render probe: terrain normal relief visible under sun (with good normals); torch
      pool + relief follows the player at night; day/night reads via ambient+sun
      (manual human verification).
- [ ] No double-darkening vs the cosmetic shade (static read + probe).
- [ ] No gameplay system reads the lights (static read); no save/packet/command/event
      change; no `WORLD_VERSION` bump.

## Implementation Iterations
1. Lights + ambient rebalance + normal relief. **Status: landed 2026-06-24.**
   `DaylightSystem` rebalanced to ambient floors + creates/drives a
   `DirectionalLight2D` sun (energy from ambient phase brightness, angle from
   `WorldVisualLightingProfile` by hour, off underground). Player gains a `Torch`
   `PointLight2D` (`player_torch.gd`, self-generated radial texture, no occluder
   shadows). In-shader cosmetic `shade_dir_strength` reduced 0.16→0.06 to avoid
   double-darkening. Verified via render probe (day in the live scene; night+torch
   via `tools/ground_light_probe.gd`). Relief payoff pending authored terrain normals.
   **Rebalanced after first feedback (over-bright):** day ambient stays familiar
   (~0.85) with a *gentle* sun key (`SUN_DAY_ENERGY` 1.25→0.45); **night is near-black**
   (`COLOR_NIGHT ≈ 0.03` — zero visibility without a light source, by design; additive
   spores/fireflies and the torch stay visible). Torch is **off by default with a dev
   on/off toggle (key F)**, lower energy/range (0.9 / 2.2) so it no longer washes the
   day. Probe captures: day-natural / night-pitch-black / night-torch-pool.
2. Occluder cast shadows (sun + torch), proximity-bounded. **Not started.**
3. (Later, separate) gameplay visibility authority per ADR-0005.

## Required Updates
- `docs/02_system_specs/README.md` — index entry (added with this draft).
- On promote: reconcile `plains_ground_cosmetic_shading.md` (the in-shader directional
  shade becomes redundant once the real sun lights normals).
- If a public light/visibility API appears later, update `system_api.md` (Iter 3).
