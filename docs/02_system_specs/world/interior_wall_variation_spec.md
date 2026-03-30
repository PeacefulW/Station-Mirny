---
title: Interior Wall Variation
doc_type: system_spec
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-03-30
depends_on:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
related_docs:
  - ground_elevation_faces_spec.md
  - ../../../tools/sprite-forge/sprite_forge_v6.html
---

# Feature: Interior Wall Variation

## Design Intent

Reduce visible tiling on terrain and mountain visuals by introducing a special presentation-only selection path for `00_interior` / `WALL_INTERIOR`.

All non-interior wall forms stay exactly as they are today:
- only the base variants already authored/exported by the atlas generator
- no extra runtime flips, rotations, or transpose logic
- no semantic change to neighbor classification or wall-form selection

Only `00_interior` gets expanded presentation variability:
- 5 authored base interior versions
- 8 runtime transforms per base
- deterministic world-space selection
- local anti-repeat so adjacent tiles do not fall into obvious checkerboard or diagonal repetition

This is intended to make large uninterrupted terrain/mountain interiors feel more natural without changing the canonical world data or wall-form contracts.

## Visual Model

### Non-interior wall forms

- `NOTCH_*`, `CORNER_*`, `EDGE_*`, `PENINSULA_*`, `T_*`, `CROSS`, and all other non-interior forms keep current runtime behavior.
- Runtime must not add new transform logic for them.
- Runtime must not reinterpret their authored atlas layout.

### Interior wall form only

`00_interior` / `WALL_INTERIOR` uses:
- 5 authored base looks from atlas/export
- 8 transform states:
  - original
  - flip H
  - flip V
  - flip H+V
  - rotate 90
  - rotate 180
  - rotate 270
  - transpose / diagonal form

Effective state count for `00_interior`: up to `5 * 8 = 40`.

## Runtime Selection Rules

### Deterministic hash selection

`00_interior` must not use simple modulo selection from local coordinates.

Selection must be based on world coordinates and a stable seed:
- same `(world_x, world_y, seed)` always resolves to the same interior presentation
- different chunks must agree at seams because selection is world-space, not chunk-local
- selection remains presentation-only; terrain truth does not change

Reference logic:

```js
function hash32(x, y, seed = 12345) {
  let h = (x * 374761393 + y * 668265263 + seed * 1442695041) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 1274126177) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}

function pickInteriorVariant(wx, wy, seed, baseCount = 5) {
  const h = hash32(wx, wy, seed);
  const base = h % baseCount;
  const transform = (h >>> 8) & 7;
  return { base, transform };
}
```

### Anti-repeat

For `00_interior` only:
- if left neighbor resolves to the same `base + transform`, shift `transform`
- if top neighbor resolves to the same `base + transform`, shift `base`
- if both left and top still collide, re-hash with a deterministic salt

Anti-repeat must remain:
- deterministic
- seam-safe
- independent of chunk load order

That means the final rule must derive neighbor comparisons from world-space resolution, not from mutable redraw history.

## Future Visual Escalation

### Level 2 — Family selection

Before selecting micro-variation, select a larger-scale "family" in world space:
- family A: lighter / cleaner interior
- family B: rougher / noisier interior
- family C: patchier / spotted interior

Then choose the micro-variation inside that family.

This should create larger coherent regions so the result reads like natural material zones instead of pure noise.

### Level 3 — World-space macro overlay

Best visual result comes from layering a world-space macro detail only on `00_interior`:
- dirt patches
- darker grass zones
- sparse pebbles
- dust
- moss
- micro-cracks
- subtle micro-relief

This overlay must be computed in world coordinates, not tile-local coordinates, so the eye sees a continuous large-scale pattern across tile boundaries.

## Data Contracts

### Affected layer: Presentation / Wall Atlas Selection

- What changes:
  - runtime presentation selection for `WALL_INTERIOR`
  - optional atlas/export support for 5 authored interior bases
  - deterministic world-space transform selection for interior only
- New invariants:
  - non-interior wall forms keep current selection semantics
  - `WALL_INTERIOR` selection is deterministic from world coordinates and seed
  - anti-repeat logic must not depend on chunk load order
  - selection remains presentation-only and must not mutate terrain truth
  - world-space macro overlay, if added later, is presentation-only and interior-only
- Who adapts:
  - `Chunk`
  - `ChunkTilesetFactory`
  - `tools/sprite-forge/sprite_forge_v6.html` if atlas/export metadata must change
- What does NOT change:
  - terrain bytes
  - wall-form classification
  - mining/topology/reveal logic
  - public runtime APIs

## Iterations

### Iteration 1 — Interior-Only Hash + Transform Selection

Goal: make `00_interior` much less repetitive without changing any other wall form.

What is done:
- expose 5 authored `00_interior` base versions
- add 8 transform states for `00_interior` only
- select `base + transform` from deterministic hash of world coordinates
- add anti-repeat against left/up world-neighbor resolutions
- keep all non-interior wall forms on their current path

Acceptance tests:
- [ ] `WALL_INTERIOR` has access to 5 authored bases and up to 8 transforms each
- [ ] same world tile always resolves to the same interior presentation across reloads
- [ ] adjacent interior tiles no longer show obvious checkerboard / diagonal repetition in large fields
- [ ] non-interior wall forms resolve exactly as before
- [ ] chunk seams do not produce load-order-dependent interior mismatches

Files that may be touched:
- `core/systems/world/chunk.gd` — runtime selection for `WALL_INTERIOR`
- `core/systems/world/chunk_tileset_factory.gd` — atlas indexing / transform exposure for interior only
- `tools/sprite-forge/sprite_forge_v6.html` — only if export/layout support for 5 interior bases is needed

Files that must NOT be touched:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- C++ code

### Iteration 2 — Large-Scale Family Selection

Goal: avoid pure white-noise distribution by creating coherent material families in world space.

What is done:
- choose interior family on a larger spatial scale
- choose micro-variation inside that family
- keep determinism and seam safety

Acceptance tests:
- [ ] large interior areas show coherent visual families instead of fully uniform noise
- [ ] family choice remains deterministic by world coordinates
- [ ] anti-repeat still works inside each family

Files that may be touched:
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_tileset_factory.gd`
- `tools/sprite-forge/sprite_forge_v6.html` if family atlas content or metadata is needed

### Iteration 3 — World-Space Macro Overlay For Interior

Goal: break tile readability at large scale by adding continuous world-space detail over `00_interior`.

What is done:
- add one presentation-only macro overlay layer for interior tiles
- evaluate it in world coordinates, not tile-local coordinates
- restrict it to `00_interior`

Acceptance tests:
- [ ] macro detail visually continues across tile boundaries
- [ ] overlay does not affect non-interior wall forms
- [ ] overlay is deterministic and seam-safe
- [ ] tile grid becomes noticeably harder to read in large uninterrupted interior zones

Files that may be touched:
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_tileset_factory.gd`
- `tools/sprite-forge/sprite_forge_v6.html` if overlay art/export support is needed

## Out-of-scope

- Changing canonical terrain data to store variant ids
- Changing wall-form neighbor classification rules
- Adding transform logic to non-interior wall forms
- Reworking mining/topology/reveal systems
- General-purpose overlay system for every terrain type in the same iteration
