---
title: Plains Ground Cosmetic Shading — Large-Scale Form and Contact Weight
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.1
last_updated: 2026-07-29
related_docs:
  - terrain_hybrid_presentation.md
  - plains_ground_field_composition.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../progression/player_sun_shadow_v0.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Plains Ground Cosmetic Shading — Large-Scale Form and Contact Weight

## Purpose

Give the plains ground plane **visual depth** (large soft light/dark masses that
read as form) and ground objects **weight** (contact occlusion), so the new
ground macro-masses ([`plains_ground_field_composition.md`](plains_ground_field_composition.md))
stop reading as a flat lit plane. Step 2 of the plains visual roadmap.

## ADR-0005 guardrail (non-negotiable)

[`ADR-0005`](../../05_adrs/0005-light-is-gameplay-system.md): **light is a
gameplay system** (safety/visibility/sanctuary contrast); gameplay reads a
light/visibility *authority*, not the renderer. Everything in this spec is
**strictly cosmetic**:

- it only modulates ground/object **albedo brightness**;
- **no** gameplay system (fauna AI, visibility, stress, sanctuary truth) may read
  it; it is not a light authority and must not become one;
- it derives its sun model from the existing cosmetic
  [`WorldVisualLightingProfile`](../../../core/systems/world/world_visual_lighting_profile.gd)
  — the single sun source already used by tree/grass/edge/mountain/player
  shadows. **No second lighting curve** (forbidden by `terrain_hybrid_presentation.md`).

The micro-scale counterpart of this model is the gravel relief term
([`plains_ground_gravel_relief.md`](plains_ground_gravel_relief.md), landed
2026-07-31). It lights individual stones with the same hybrid split this spec
established — a constant ambient form plus a `ground_sun_day`-faded directional
component — reading the same `ground_sun_angle_deg` uniform. It introduces no
sun of its own; if the sun model here changes, gravel follows automatically.

## Scope

- **Iteration 1 (this landing):** large-scale cosmetic shading of the plains
  ground, hybrid model — a constant ambient-AO "form" field (present day and
  night) plus a sun-directional component that fades with daylight; the shared
  ground material starts receiving the sun model.
- **Iteration 2 (later):** contact AO / "weight" under scatter objects (trees
  now; reusable by the rock objects of the `scatter + litter` step).

## Out of Scope

- real `Light2D` / occluders / gameplay visibility;
- any artificial-light masks;
- canonical terrain ids, walkability, collision, mining, save/load, packets,
  commands, EventBus;
- `WORLD_VERSION` (no canonical/deterministic output change).

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical data, overlay, or visual only? | Visual-only derived state (albedo brightness). |
| Save/load required? | No. Authored knobs live in the material set; sun model is live-derived. |
| Deterministic? | Visually deterministic for a given world position + time of day; not gameplay state. |
| Must it work on unloaded chunks? | Ground shade derives from world position + the global sun model; no chunk-local state. |
| C++ or main thread? | Shader renders pixels; one shared material's sun uniforms updated on the main thread on sun change (O(1)). |
| Dirty unit | None new. One shared ground material uniform update per sun change. |
| Single owner | `WorldVisualLightingProfile` owns the sun model; the ground shader owns only the cosmetic shade math. |
| 10x/100x scale | O(1): one shared ground material, fragment-only shading. No per-tile/per-object loop. |
| Hidden fallback? | Forbidden. Sun model comes only from `WorldVisualLightingProfile`. |
| Whole-world prepass? | No. |

## Design Intent — Iteration 1 (hybrid)

Applied in [`ground_hybrid_material.gdshader`](../../../assets/shaders/ground_hybrid_material.gdshader)
to the composited ground color:

- **Ambient AO form (always on):** a very-low-frequency `fbm` of world position,
  treated as a soft height/occlusion field, darkens "valleys" — big soft masses
  that give form even at night. Aperiodic, no per-chunk state, gradient-noise only
  (same field rules as the rest of the ground).
- **Sun-directional component (day, fades at night):** the same field sampled
  with a small offset along the fixed north-west sun direction yields a slope;
  sun-facing slopes brighten, away-facing darken. Scaled by a daylight factor from
  `WorldVisualLightingProfile` so it disappears at night (leaving the ambient
  form). This unifies the ground with the objects' sun-driven shadows.

This was chosen (hybrid) over pure-ambient (does not live with time of day) and
pure-directional (form collapses at night).

## Data Model

Authored knobs in the plains ground `TerrainMaterialSet.sampling_params`
([`plains_ground_material_set.tres`](../../../data/terrain/material_sets/plains_ground_material_set.tres)),
wired generically to shader uniforms:

- `shade_scale_px` (default `3500.0`) — wavelength of the form field;
- `shade_ambient_strength` (`0.13`) — ambient AO depth;
- `shade_relief_px` (`520.0`) — sun-offset distance for the slope sample;
- `shade_directional_gain` (`3.2`) — slope→light sensitivity;
- `shade_dir_strength` (`0.16`) — daytime directional shade depth.

Runtime-driven uniforms (NOT in tres; set from the sun model, sensible defaults
for a static daytime look): `ground_sun_angle_deg` (fixed north-west fallback
`-152.525483`, matching `WorldVisualLightingProfile`),
`ground_sun_day` (default `1.0`).

## Runtime Architecture

- The shared plains ground material (`base:plains_ground_material`, cached in
  `WorldTileSetFactory`) gains two sun uniforms. `WorldStreamer`, inside its
  existing `_sync_sun_lighting_from_time` path, updates them **once per sun
  change** on the single shared material (new safe accessor
  `WorldTileSetFactory.get_built_material_for_terrain`). This is the same single
  sun source already fanned out to per-chunk materials — no new curve.
- Defaults give a correct daytime look before the first post-load sun sync; the
  live sync refines day/dusk/night.
- No new public API, command, event, or packet.

## Performance Class

- Ground shade: +2 `fbm` per fragment (GPU), bounded full-screen ground work.
- Sun uniform update: O(1) per sun change on one shared material (`background`/
  event-driven), no per-chunk or per-tile loop.
- Save/Signals/Commands: none.

## Acceptance Criteria

Visual criteria via render probe (before/after), honest `manual human
verification`.

- [ ] Ground shows large soft light/dark masses (form), not a flat plane
      (render probe).
- [ ] Form persists at night (ambient) while the directional component fades by
      night (probe at two hours).
- [ ] Sun model comes only from `WorldVisualLightingProfile` (static read: the
      ground uniforms are fed from the same `_sync_sun_lighting_from_time` path;
      no second curve).
- [ ] No seams; shade is a pure world-position + sun function (static read).
- [ ] No `WORLD_VERSION` bump, no save/packet/command/event change (static read).
- [ ] No gameplay system reads the cosmetic shade (static read).

## Risks

- **ADR-0005 leakage** — keep strictly cosmetic; never queried by gameplay.
- **Double-darkening** vs `macro_drift` / macro-masses — pick `shade_scale_px`
  distinct from those and tune strengths to complement.
- **Timing** — the shared material may not exist at the very first sun sync;
  handled by null-safe accessor + correct daytime defaults.

## Implementation Iterations

### Iteration 1 — Large-scale hybrid ground shading

Shader hybrid shade + sun-model plumbing to the shared ground material.
**Status: landed 2026-06-24** (defaults above; verified via render probe).

### Iteration 2 — Contact AO / object weight

Per-object contact occlusion under scatter objects. Rocks/flora still use the
shared `WorldDecorBatchLayer` flat contact ellipse: projected length forced to 0,
opacity `CONTACT_SHADOW_BASE_OPACITY + sun*scale`, so it is sun-gated by
construction and automatically reused by future rock objects.

Tree contact ellipses are disabled (`TREE_CONTACT_SHADOW_ENABLED=false`) because
the flat oval reads as a baked spot under the trunk. Tree PNG frames are exported
without baked base AO/root grounding, and tree shadowing comes from the separate
sun silhouette layer plus future directional light shadows.

**Status: adjusted 2026-07-05** after the tree atlas was regenerated without
baked oval base shadows.

## Required Updates

- `docs/02_system_specs/README.md` — index entry (added with this spec).
- No boundary meta-docs (`packet_schemas`, `system_api`, `commands`,
  `event_contracts`) change: no new public surface.
