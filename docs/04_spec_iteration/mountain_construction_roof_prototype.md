---
title: Mountain Construction Roof Visual Prototype
doc_type: iteration_brief
status: completed
owner: engineering+design
source_of_truth: true
version: 1.3
last_updated: 2026-07-11
related_docs:
  - ../02_system_specs/world/mountain_generation.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Mountain Construction Roof Visual Prototype

## Goal

Prove the construction model on the real organic runtime mountain before any
production roof rewrite:

- mountain presentation reads as `outer walls + separate roof + interior floor`
- one deterministic south-facing mouth is excavated into a T-shaped cavity
- `OUTSIDE` shows the original organic roof and only a shallow physical break
  through the front facade
- `INSIDE` shows the actual excavated T-shaped floor and its organic inner rock
  boundary
- switching `OUTSIDE -> INSIDE -> OUTSIDE` changes presentation only and never
  changes terrain, walkability, collision, diff, save data, or mountain identity

The prototype is an explicit visual experiment. It does not replace the
approved production roof contract in `mountain_generation.md`.

## Non-Goals

- automatic entrance crossing or player-driven roof state
- production `mountain_id` / cavity-component integration
- wide, side-facing, north-facing, multiple, or cross-chunk entrances
- fade animation, lighting changes, darkness ownership, collapse, or quarrying
- new authored entrance art, arches, doors, shells, or generated portals
- changes to native generation, packet schema, save/load, or gameplay mining

## Files Likely Involved

- `scenes/dev/mountain_runtime_dig_dev_scene.gd`
- `assets/shaders/mountain_top_mask_underlay.gdshader` only for a neutral,
  default-off `roof_overlay_mode` used by the dev-only frozen roof copy
- `tools/mountain_runtime_dig_dev_scene_smoke_test.gd`
- `tools/mountain_runtime_dig_dev_scene_render_probe.gd`
- `artifacts/mountain_runtime_dig_dev_scene/prototype_*.png`
- this iteration brief

Production owners such as `ChunkView`, `WorldStreamer`, native mask builders,
packet schemas, and canonical save paths are outside prototype scope. The
shared shader keeps byte-for-byte default behavior while the dev copy opts into
the prototype-only roof mode.

## Runtime Classification

- work class: `dev/boot`, never interactive production work
- authoritative state: existing packet + runtime diff terrain and walkability
- visual input: snapshots of the real native organic mask before and after the
  public excavation path, followed by a dev-only reapplication of the existing
  organic local-dig patch so reconcile cannot close source cells that are
  already `TERRAIN_PLAINS_DUG`
- dirty unit: the single target chunk selected with enough local margin for the
  complete T cavity
- scale path: none required for the dev-only proof; production integration must
  return to the canonical chunk/component dirty-unit contract

## Risks

- a dev-only texture snapshot can be overwritten by a later native-mask upload;
  the probe must wait until native work settles before capturing or toggling
- a target near a chunk seam would give false results; the deterministic scan
  must keep the complete prototype footprint inside one chunk
- opening too much of the closed mask recreates the rejected trench; the
  outside aperture must be limited to the authored facade-depth band
- a successful screenshot does not approve production ownership or invalidation;
  those require a follow-up spec amendment after human visual acceptance

## Implementation Steps

1. Select a south-facing mountain boundary with a walkable exterior tile and a
   fully solid, same-mountain T footprint inside one chunk.
2. Wait for the real native mountain mask and snapshot its closed organic bytes
   into a second dev-only sprite whose material renders roof surface/eave but
   excludes the structural vertical facade band.
3. Excavate the T footprint through `try_harvest_at_world` only.
4. Wait for native rebuild and record the resulting organic open-mask hash.
5. Reapply `ChunkView.apply_mountain_world_dig_patch` to the six real dug tiles
   in the dev scene and upload those bytes to the existing BASE texture. This
   previews the production invariant "a dug source tile remains open after
   organic reconcile" without changing native code or save/packet contracts.
6. Compose `OUTSIDE` as excavated BASE plus the frozen closed ROOF. The ROOF
   material excludes its structural south-facade band, so BASE supplies the
   real facade break while the deeper T stays covered.
7. Toggle only the frozen ROOF sprite visibility for `INSIDE`/`OUTSIDE`.
8. Capture `OUTSIDE`, `INSIDE`, and restored `OUTSIDE` evidence.

## Smoke Tests

- the target is south-facing and the whole T footprint belongs to one mountain
- every T tile is excavated by the public harvest path and becomes real
  `TERRAIN_PLAINS_DUG` walkable floor
- the closed native, reconciled native-open, and post-carve open hashes are
  recorded and differ where expected
- all six dug centers remain physically walkable after native reconcile plus
  the dev-only post-carve
- visual toggling leaves the scoped prototype state unchanged: BASE mask bytes,
  mountain identity, and terrain/walkability of all six T tiles; the toggle
  code path writes only `Sprite2D.visible`
- `OUTSIDE -> INSIDE -> OUTSIDE` reuses the exact same frozen ROOF texture
- the real Player nine-point occupancy footprint traverses the mouth, stem,
  junction, and both branches at 4 px sampling steps
- all eleven retaining-wall centers remain mountain terrain, blocked, and
  resource-bearing after the post-carve

## Definition of Done

- outside screenshot reads as one facade break under an intact organic roof,
  without a visible multi-tile trench
- inside screenshot reads as the complete T-shaped cavity with organic inner
  walls
- the exterior facade terminates at the two mouth corners and does not cross the
  excavated floor
- the restored outside screenshot uses the exact same frozen roof texture and
  the exact same excavated BASE bytes
- user reviews the screenshots before any production roof implementation starts

## Prototype Evidence

- `prototype_outside_closed.png`: original organic roof remains, the live
  facade ends at the two mouth corners, and only the shallow floor continuation
  is visible from outside
- `prototype_inside_open.png`: the frozen roof is hidden and the complete real
  six-tile T floor is visible
- `prototype_outside_restored.png`: the same roof texture is shown again
- smoke result: all six T tiles are `TERRAIN_PLAINS_DUG`, packet-walkable, and
  mask-walkable after reconcile plus the dev-only post-carve; the full Player
  footprint also traverses the T while all retaining walls remain blocked

The post-carve is intentionally a prototype finding, not a production fix. A
production follow-up must make the native/current-mask ownership preserve dug
source cells during generation instead of relying on a dev scene to reapply the
patch.

## Production Handoff (2026-07-11)

The visual hypothesis was accepted and promoted into canonical
`mountain_generation.md` version `1.8`:

- native worker emits immutable `closed_roof_mask` plus live
  `remaining_mass_mask` in one request
- excavation cutout runs after broad organic blur and hard-clears every pixel
  of each authoritative dug source tile
- production `ChunkView` owns independent BASE and ROOF sprites; no dev texture
  snapshot or CPU mask composer is used
- production roof reveal is the floor-only active orthogonal cavity selected by
  the existing `MountainResolver`; a bounded `C solid / S open` fallback keeps
  that component active in real organic corner space beside its source tile
- outside mouths carry cardinal direction bits and cut a rounded sub-tile
  aperture; they do not remove the complete first roof tile
- all paired masks and component ids remain transient and rebuild from immutable
  base + runtime diff

The original `prototype_*.png` files remain historical proof. The same dev
scenario is subsequently reused as a production runtime gate and writes
`production_*.png` evidence without the dev-only post-carve or visibility
toggle.
