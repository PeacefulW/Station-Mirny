---
title: Player Sun Shadow V0
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 0.4
last_updated: 2026-07-29
related_docs:
  - player_visual_animation_v0.md
  - ../world/weather_runtime.md
  - ../world/cloud_occlusion_lighting.md
  - ../meta/system_api.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
---

# Player Sun Shadow V0

## Purpose

Player Sun Shadow V0 defines the Engineer's visual-only silhouette shadow.

The shadow mirrors the current animated `Sprite2D` frame, darkens the sprite
alpha, and lays it down onto the ground in the direction opposite the sun —
projecting the figure's height as length on the ground plane (like the tree
shadows), not squashing it into a flat strip. A soft contact pool at the feet
roots the cast, because a laid-down humanoid silhouette (thin legs, high mass)
otherwise detaches its dense part from the feet. It is presentation only and
must not change movement, collision,
visibility gameplay, save/load, commands, EventBus payloads, or world packets.

Mixamo frames are centered with large transparent padding below the feet, and
the figure bobs vertically inside the frame across the animation. Pivoting the
projection at the frame bottom therefore detached the shadow and let it drift
per frame. V1 fixes this with a per-frame **feet contact line** (`frame_contact_uv`)
baked offline into the clip atlas metadata: the shader lays the silhouette down
from that contact line (projecting height along the sun-opposite direction),
then **re-grounds** every frame so the contact always lands on one fixed ground
line under the player. This removes both the detachment and the per-frame wander
while keeping the silhouette character shape.

## Scope

V0 includes:

- a `PlayerSunShadow` child component under the player scene;
- one local `Sprite2D` that mirrors the player's current atlas texture and
  `region_rect`;
- per-frame feet contact (`frame_contact_uv`) baked offline into each clip's
  atlas JSON metadata (`assemble_player_mixamo_clip_atlas.py`), read at load
  time and indexed `dir*16 + frame` from the mirrored `region_rect`;
- one canvas-item shader that projects the mirrored silhouette from the feet
  contact line and re-grounds it to a fixed ground line each frame;
- a procedural soft contact pool (`GradientTexture2D` radial) anchored at the
  feet and elongated along the sun-opposite direction, drawn behind the
  silhouette, that roots the cast so it does not read as detached;
- one fixed north-west sun azimuth from `WorldVisualLightingProfile`, so the
  shadow always projects screen south-east; dawn/day/dusk change only
  projection length and fade through the documented `TimeManager` progress;
- direct-sun attenuation from `WeatherRuntime.get_cloud_occlusion()`, so the
  body shadow follows the same direct-sun-blocked scalar as the real sun;
- coarse surface gating for building indoor cells and mountain interiors.

V0 does not include:

- real `Light2D` / occluder shadows;
- gameplay light authority or visibility gameplay changes;
- local artificial-light masks;
- any save/load, command, packet, or EventBus contract changes;
- runtime model loading, atlas generation, or image painting.

## Runtime Classification

| Question | Answer |
|---|---|
| Runtime class | interactive-frame presentation |
| Authoritative data | none; visual-only derived state |
| Single write owner | `PlayerSunShadow` owns only its local shadow sprite/material params |
| Save/load impact | none |
| Determinism impact | none for gameplay; shadow is client-local presentation |
| Dirty unit | one local `SunShadow` Sprite2D transform/material update |
| Target scale | one local player in V0; future co-op repeats O(1) per visible player |
| Escalation path | keep per-player shadow O(1); if many actors need the same effect, share a material/profile resource and keep per-actor frame mirroring local |

## Dependencies

- `Player Visual Animation V0` owns the animated atlas texture/region selection.
- The clip atlas pipeline (`assemble_player_mixamo_clip_atlas.py`) owns the
  baked `frame_contact_uv` metadata; the shadow reads it, never re-derives it
  from pixels at runtime.
- `TimeManager.get_sun_angle()` exposes the fixed north-west visual azimuth;
  `get_sun_progress()` exposes the time-varying elevation phase.
- `WorldVisualLightingProfile` owns shadow visibility, low-sun length, and
  dawn/dusk fade curves.
- `WeatherRuntime.get_cloud_occlusion()` attenuates direct-sun body shadows
  under overcast.
- `BuildingSystem.is_cell_indoor()` and `WorldStreamer.get_mountain_cover_sample()`
  provide coarse surface-context gates.

## Runtime Rules

- The shadow must mirror the current visual frame by copying the player's
  `Sprite2D.texture` and `Sprite2D.region_rect`.
- The shadow must lay the silhouette down from the per-frame baked feet contact
  line and re-ground that contact to one fixed ground line, so the shadow base
  neither detaches into the frame padding nor wanders with the per-frame body
  bob.
- The shadow direction must remain screen south-east at every hour. Time of day
  may change projection length, softness, visibility, and opacity only.
- The shadow must read the baked `frame_contact_uv` table (cached per clip
  texture); it must not read texture pixels or recompute contact at runtime.
- The shadow must update only one local sprite/material; it must not scan
  chunks, scene groups beyond cached owner lookup, inventory, save data, or
  world packets.
- The shadow must render on the ground below the player/decor depth ladder, not
  as a peer of the player's body layer.
- Distinct cast shadow opacity must fade to zero when the daylight profile says
  shadows are not visible, and must fade under high overcast cloud cover.
- Indoor/base and mountain-interior gates are visual gates only; they do not
  define gameplay visibility or sanctuary truth.

## Required Updates

- If this feature adds a public API, command, event, packet, or save shape,
  update the corresponding meta spec in the same task.
- V0 adds no public boundary; it uses documented `TimeManager`,
  `WeatherRuntime`, `BuildingSystem`, and `WorldStreamer` reads only.

## Acceptance Tests

- [ ] Player scene has a `SunShadow` Sprite2D using `PlayerSunShadow`.
- [ ] `PlayerSunShadow` mirrors the active `Visual` texture and `region_rect`
      instead of loading or generating runtime assets.
- [ ] Each clip atlas JSON carries a `frame_contact_uv` array of
      `directions * frames_per_direction` entries; the shadow indexes it by
      `region_rect → dir*16 + frame`.
- [ ] The shadow base stays on a fixed ground line under the player across all
      animation frames (no detachment into padding, no per-frame wander).
- [ ] A soft contact pool at the feet roots the cast so the laid-down silhouette
      does not read as detached from the feet.
- [ ] Shadow direction follows the fixed
      `TimeManager.get_sun_angle() + PI` south-east vector at every hour;
      projection length and opacity follow `WorldVisualLightingProfile`
      low-sun/daylight curves.
- [ ] Overcast and indoor/mountain-interior context can hide the distinct cast
      shadow without affecting gameplay systems.
- [ ] Runtime work remains O(1) local presentation and does not touch save/load,
      commands, EventBus contracts, or world packet schemas.
