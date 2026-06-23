---
title: Player Visual Animation V0
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 0.2
last_updated: 2026-06-23
related_docs:
  - character_progression.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Player Visual Animation V0

## Purpose

Player Visual Animation V0 defines the first production-facing animation
contract for the Engineer's 2D presentation.

The player remains a `CharacterBody2D`; animation is visual-only and must not
change movement, collision, save/load, inventory, oxygen, health, or world
runtime semantics.

## Design Intent

The Engineer should read as a suited survivor at gameplay scale:
- standing still has subtle motion instead of a frozen run frame;
- running supports directional readability;
- movement relative to the current facing can show forward, backward, and
  left/right strafe variants when authored clips exist;
- the asset pipeline may use Mixamo and Blender as offline sources, but Godot
  consumes checked-in PNG atlases only.

## Runtime Classification

| Question | Answer |
|---|---|
| Runtime class | interactive-frame presentation |
| Authoritative data | none; visual-only derived state |
| Single write owner | `Player` owns its own visual frame selection |
| Save/load impact | none |
| Determinism impact | none for gameplay; animation time is presentation-only |
| Dirty unit | one local player `Sprite2D.region_rect` update |
| Target scale | one local player in V0; future co-op repeats O(1) per visible player |
| Escalation path | keep clip selection O(1); if players/entities scale up, move shared animation metadata into a Resource and keep per-entity frame selection local |

## Data Model

V0 uses one or more atlas textures under:

```text
assets/sprites/player/
```

Required atlas layout:

```text
columns = frames per animation direction
rows = direction count
frame_size_px = square frame size
row = direction index
column = frame index
```

The current compatible layout is:

```text
columns = 16
rows = 16
frame_size_px = 256
```

The first authored V0 atlases use Mixamo FBX clips rendered offline through
Blender into five checked-in textures: `idle`, `run_forward`, `run_backward`,
`strafe_left`, and `strafe_right`.

Optional metadata JSON may live next to each atlas and document source asset,
clip name, rows, columns, frame size, and proof counts.

## Direction Model

Direction rows use the existing player convention:
- `direction_index = 0` is screen north/up;
- rows advance clockwise;
- 16 rows use `22.5` degree steps.

If an 8-direction source is authored, the runtime must either:
- keep the 16-row contract by duplicating/interpolating nearest rows offline; or
- update this spec and the player constants in the same task.

## Clip Selection

V0 supports these clip ids:

| Clip id | Meaning |
|---|---|
| `idle` | standing in place |
| `run_forward` | movement mostly along current facing |
| `run_backward` | movement mostly opposite current facing |
| `strafe_left` | movement mostly left of current facing |
| `strafe_right` | movement mostly right of current facing |

Fallback rule:
- missing strafe/backward atlases may fall back to `run_forward` for V0, but the
  code must keep the clip selection seam explicit so authored clips can replace
  the fallback without changing movement semantics.

## Runtime Rules

- Frame selection must update only the player's local `Sprite2D.region_rect`.
- No runtime model loading, atlas generation, image painting, or Mixamo/Blender
  dependency is allowed.
- No `load()` on the gameplay path for these atlases; the scene owns texture
  references as preloaded/imported resources.
- Clip selection must not scan scene groups, chunks, world objects, inventory, or
  save data.
- The visual facing may read mouse direction and velocity already owned by
  `Player`.

## Files That May Be Touched In V0

- `docs/README.md`
- `docs/02_system_specs/progression/player_visual_animation_v0.md`
- `core/entities/player/player.gd`
- `scenes/player/player.tscn`
- `assets/sprites/player/*`
- `artifacts/player_run_retarget/*`

## Files That Must Not Be Touched In V0

- world generation or streaming code
- save/load code
- commands and command executor code
- EventBus contracts
- player movement/collision balance resources
- inventory, oxygen, health, or equipment gameplay systems

## Required Updates

- If V0 adds a new public API, command, event, packet, or save shape, update the
  corresponding meta spec in the same task.
- If V0 remains visual-only and only changes local `Player` frame selection and
  player sprite assets, no meta boundary spec update is required.

## Acceptance Tests

- [ ] `Player` still uses `Sprite2D.region_rect` for presentation and does not
      instantiate a 3D runtime model.
- [ ] Idle uses a dedicated clip path instead of hardcoding run frame `0` as the
      only standing visual.
- [ ] Running chooses a visual clip from current facing + movement vector with
      explicit forward/backward/strafe fallback behavior.
- [ ] Per-frame visual update remains O(1) local work and does not touch world,
      save/load, commands, or EventBus.
- [ ] Player scene references valid checked-in PNG atlas resources.
