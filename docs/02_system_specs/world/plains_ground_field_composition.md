---
title: Plains Ground Field Composition — Macro-Masses and Paths
doc_type: system_spec
status: approved
source_of_truth: true
owner: engineering+art
version: 1.1
last_updated: 2026-07-29
related_docs:
  - terrain_hybrid_presentation.md
  - wind_and_grass_scatter_presentation.md
  - plains_trees_presentation.md
  - ../meta/packet_schemas.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Plains Ground Field Composition — Macro-Masses and Paths

## Purpose

Extend the plains ground composition owned by
[`terrain_hybrid_presentation.md`](terrain_hybrid_presentation.md)
("Runtime 2D Terrain Ground Composition") with two new aperiodic world-position
fields that break the current uniform "orange soup" look:

1. a **macro-mass coverage field** (very long wavelength) that biases grass
   density up/down across large regions, producing bare/dirt clearings against
   dense grass pockets;
2. a **path channel** (sinuous, domain-warped) that carves meandering corridors
   of reduced coverage where soil/gravel shows through.

This spec does **not** introduce a new owner of the ground field. It refines the
existing field formula and its synchronization discipline.

## Gameplay Goal

The walkable plains read as a structured landscape with open clearings, dense
thickets, and natural trails — not a flat continuous lawn. Placed decor (grass
tufts, trees) must visibly respect this structure: it thins on clearings and
stays clear of paths, so visible ground and placed objects stay coherent.

## Scope

- two new aperiodic fields added to the **shared** plains ground field formula;
- the field-mirror discipline that keeps all transcriptions of that formula in
  sync (GLSL + C++);
- new authored `sampling_params` knobs and their packed-param wiring;
- the `WORLD_VERSION` and `packet_schemas.md` consequences of changing
  placement-affecting field math;
- a transition **scree** detail (Iteration 2): visual-only gravel/pebbles
  concentrated at the open↔grass seam, reusing the existing rock textures.
  Packet-backed raised pebble objects are owned by
  `world_object_placement_v0.md` (`object_kind == 6`), not by this ground
  shader composition spec.

## Out of Scope

- player-worn / dynamic trails (would require per-tile wear state, a runtime
  diff owner, and save payload — a separate spec, explicitly deferred);
- new gameplay object kinds, terrain-owned decals, contact shadows, or lighting
  (packet-backed decor object families are owned by
  `world_object_placement_v0.md`);
- any change to canonical terrain ids, walkability, collision, mining, or save
  contracts;
- new biomes.

## Dependencies

- Ground composition contract and field rules: `terrain_hybrid_presentation.md`.
- Grass scatter packed-param layout: `grass_scatter::ParamIndex`
  ([`grass_scatter.h`](../../../gdextension/src/grass_scatter.h)) and its schema
  in `packet_schemas.md` (`GrassScatterBufferResult`).
- Tree placement gating: `append_native_tree_placements` in
  [`world_core.cpp`](../../../gdextension/src/world_core.cpp).

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | Visual-only derived state. Both fields are pure functions of world position; they own no terrain ids, walkability, or save state. |
| Save/load required? | No. Authored `sampling_params` live in the material set resource; no runtime save payload. |
| Deterministic? | Yes. Output depends only on world position and authored params; no per-chunk input. |
| Must it work on unloaded chunks? | Yes. Derivable from world position alone; no chunk-local state. |
| C++ compute or main-thread apply? | Shader renders ground pixels; native batch (`background`) computes placement from the mirrored formula. No new main-thread work. |
| Dirty unit | None new. Placement stays a bounded per-chunk native batch; ground stays a stateless shader. |
| Single owner | The shared plains ground field formula stays the single authoritative definition; all transcriptions mirror it. |
| 10x / 100x scale path | Fields are O(1) per sample; placement keeps sampling on the coarse per-chunk grid. No per-tile script loop is added. |
| Main-thread blocking risk | None. No sync field bake; shader cost is bounded per-fragment GPU work. |
| Hidden fallback? | Forbidden. If a transcription is not updated, the build fails the parity acceptance check; no silent divergence. |
| Whole-world prepass? | No. Local/derived only. |

## Design Intent

### Two new aperiodic fields

Both fields are gradient-noise (Perlin) fbm of `world_pos`, never value-noise
(value-noise produces straight polygon edges with lattice corners — already a
documented failure in the ground shader) and never a repeat-sampled texture
(tiles as wallpaper at far zoom).

- **Macro-mass field** `M`: a single long-wavelength fbm (target characteristic
  scale on the order of several thousand px, distinct from the existing
  `macro_drift` which only modulates brightness/tint). `M` shifts the grass
  density field up toward dense pockets and down toward bare/dirt clearings,
  applied **before** the existing grass ladder so clearings expose the existing
  soil/gravel/rock chain naturally.
- **Path channel** `P` (resolved: **distance-to-warped iso-contour**): thin
  bands around iso-levels of a domain-warped low-frequency smooth field. This
  was chosen over ridged/worm-noise because it gives **explicit width control**
  (`path_width` is the band threshold), reads as deliberate, widely-spaced
  meandering trails (matching the reference) instead of a busy crack network,
  and is a cheap **pointwise** function (a few fbm) that is identical in GLSL
  and C++ — which is what makes per-candidate evaluation viable (see Performance).
  Inside a path, coverage is driven down and the soil/gravel side of the existing
  chain is favored. Paths are aperiodic terrain features (dry washes / animal
  trails), **not** player-worn.

`M` modulates the SAME `grass_density` the shader paints and placement reads.
Because the existing `orange_region` is already gated by `grass_density`
(`smoothstep(0.44, 0.80, grass_density)` in both transcriptions), biofield cores
**automatically** concentrate in dense pockets and vanish on clearings/paths
with no separate term — adding a second orange bias would double-count
(resolved open question 2). `P` is applied as a final multiplier driving density
down inside trails. Together they keep visible ground and placed decor coherent.

The existing visual-only `macro_drift` is contrast-shaped and weighted toward
open ground after the texture ladder. It creates broad dark-soil/light-dust
masses inside clearings without flattening dense grass into the same tint. It
does not feed `grass_density`, placement, packets, or save state, so it is not
part of the C++ field mirror and does not require a `WORLD_VERSION` bump.

### Field-Mirror Law (critical)

The plains ground field formula has multiple transcriptions of one authoritative
definition. Any change to the field math (including these two new fields) MUST
update all of them **in the same task**:

1. **GLSL** — `assets/shaders/ground_hybrid_material.gdshader` (paints ground).
2. **C++ tufts** — `grass_scatter::sample_fields`
   ([`grass_scatter.cpp`](../../../gdextension/src/grass_scatter.cpp)) (places
   grass tufts; already carries the "one formula, two transcriptions" comment).
3. **C++ tree gating** — `append_native_tree_placements` in `world_core.cpp`
   consumes the same formula via `grass_scatter::sample_grass_density` and
   mirrors authored values as `TREE_GRASS_*` constants; these must receive the
   new macro-mass/path inputs (preferably via the existing param-passing path,
   not a fourth ad-hoc copy).

Divergence between transcriptions is a contract violation, not a cosmetic bug:
it reintroduces trees/tufts floating on bare clearings or paths.

## Data Model

New authored knobs in the plains ground `TerrainMaterialSet.sampling_params`
([`plains_ground_material_set.tres`](../../../data/terrain/material_sets/plains_ground_material_set.tres)),
mirrored as shader uniforms and as new `grass_scatter::ParamIndex` entries:

- `macro_mass_scale_px` — wavelength of `M` (default `7000.0`);
- `macro_mass_strength` — how hard `M` pushes coverage up/down (default `0.34`);
- `path_scale_px` — spacing/wavelength of the path network (default `2600.0`);
- `path_width` — trail half-width in field-value units (default `0.06`);
- `path_warp_px` — domain warp amount for sinuosity (default `700.0`);
- `path_strength` — how hard a path drives coverage down (default `0.85`).

All are presentation/authoring data. They add no canonical terrain id and no
save payload. The defaults above are the Iteration 1 landing values; tune them in
[`plains_ground_material_set.tres`](../../../data/terrain/material_sets/plains_ground_material_set.tres).
The three field transcriptions mirror these defaults: the ground shader uniforms,
the `world_streamer.gd` packed-param fallbacks, and the `world_core.cpp`
`TREE_MACRO_MASS_*` / `TREE_PATH_*` constants — keep them in sync on any change.

## Runtime Architecture

- **Shader (GPU):** the ground fragment function applies `M` and `P` to the
  density field before the existing texture ladder. Added cost is a small fixed
  number of extra fbm evaluations per fragment.
- **Native placement (`background`):** `grass_scatter` samples the smooth fields
  on its existing coarse per-chunk grid
  ([`grass_scatter.cpp` `FIELD_GRID_NODES = 13`](../../../gdextension/src/grass_scatter.cpp))
  and bilinearly interpolates. `M` enters the **gridded** `sample_fields`
  (long-wavelength, smooth, grid-safe). `P` is a separate **pointwise** term
  evaluated **per-candidate** (NOT through the grid) and applied as a density
  multiplier, so thin trails cannot alias on the grid (see perf constraint). The
  same pointwise `P` term is reused by `world_core` tree gating, which is already
  per-candidate.
- **Param wiring:** the packed `params` array is assembled in GDScript
  (`core/systems/world/world_streamer.gd` / `core/systems/world/chunk_view.gd`)
  from the material `sampling_params`; new `PARAM_*` slots extend that array.
- **No new public API, command, or event.** Ground composition reuses existing
  native packet generation and bounded chunk publish.

## Performance Class

- Runtime class: ground = stateless shader (GPU); placement = `background`
  native batch. No new `interactive` or `boot` work.
- **Shader cost:** +1 fbm for `M` (cheap, long wavelength) and +1–2 for `P` on a
  full-screen ground pass. Must be measured; budget is GPU fragment work, not the
  CPU frame budget.
- **Path-vs-grid constraint (resolved):** the 13×13 placement grid spans a chunk
  (≈85 px/node at a 1024 px chunk), so a thin trail would alias if read through
  the grid. **Decision (correct, not cheapest): evaluate `P` pointwise
  per-candidate**, not via the grid, and not by forcing trails wider than the
  grid (that would produce ugly highways). `P` is kept to ≤2 fbm so the
  per-candidate cost stays small relative to the full gridded `sample_fields`
  (which was the ~7 ms/chunk debug hotspot the grid exists to avoid). Tree gating
  is already per-candidate, so it reuses the same `P` directly.
- **`WORLD_VERSION`:** these fields change deterministic placement output, so
  `WORLD_VERSION` MUST be bumped and the GDExtension DLL rebuilt (same discipline
  as prior placement-affecting changes).

## Save / Load Contract

No change. Ground composition and placement remain derived, never persisted.
`ChunkPacketV1` and chunk diffs are untouched.

## Event and Command Contract Impact

None. No new commands, no new EventBus signals.

## Extension Points

- New biome ground materials reuse the same field formula and the same
  `sampling_params` knob names; only values differ per material set.
- Future per-biome path styles are authored values, not new shader sources.

## Acceptance Criteria

All visual criteria are verified by a render probe (`.tscn` → image output,
before/after panels) per the project's visual-proof rule; they are honest
`manual human verification` items unless an explicit runtime run is assigned.

- [ ] The ground material exposes `macro_mass_*` and `path_*` uniforms, and
      `plains_ground_material_set.tres` carries matching `sampling_params`
      (static: grep shader + tres).
- [ ] `grass_scatter::sample_fields` applies the same `M` and `P` terms as the
      shader, and `world_core` tree gating receives the same inputs (static:
      read all three transcriptions; they compute `M`/`P` identically).
- [ ] Both fields are pure functions of `world_pos` with gradient-noise fbm only;
      no value-noise, no per-chunk input, no repeat-texture lookup (static read).
- [ ] Render probe shows large bare/dirt clearings and sinuous paths in the
      ground, with no chunk-boundary seams (manual human verification).
- [ ] Open clearings show broad dark-soil/light-dust masses while dense grass
      keeps its local color identity (manual human verification).
- [ ] On the same probe, grass tufts and trees are absent/thin on clearings and
      paths and dense in grass pockets — visible ground matches placement
      (manual human verification).
- [ ] `WORLD_VERSION` is bumped and the DLL rebuilt; `packet_schemas.md`
      `GrassScatterBufferResult` param notes list the new `PARAM_*` slots
      (static: grep).

## Risks

- **Mirror drift:** three transcriptions of one formula. Mitigation: the
  Field-Mirror Law above + the parity acceptance check; prefer passing the new
  inputs through the existing param path rather than re-deriving in `world_core`.
- **Path aliasing on the placement grid** (see perf constraint).
- **Shader fragment cost** on low-end GPUs; mitigate by keeping `P` to ≤2 fbm.
- **Over-strong masses** could starve the biome of grass; tune `*_strength`
  conservatively and validate with the probe.

## Resolved Decisions

- **Path representation → distance-to-warped iso-contour** (thin bands around
  iso-levels of a domain-warped low-frequency field). Chosen over ridged/worm
  noise for explicit width control, deliberate-trail semantics, and cheap
  pointwise evaluation. See Design Intent / Performance.
- **Macro-mass scope → coverage-only.** `M` modulates `grass_density` only.
  Biofield richness follows automatically through the existing
  `orange_region ← grass_density` gate, so no separate orange term is added
  (a second bias would double-count).
- **Path placement evaluation → pointwise per-candidate** (not gridded, not
  forced-wide). See Performance.

## Implementation Iterations

### Iteration 1 — Macro-masses + paths (single iteration, per product decision)

Deliver both fields together. Suggested internal ordering for safety:

1. Add `M` to all three transcriptions + tres + uniforms; probe the masses.
2. Add `P` with the chosen grid-safe approach; probe paths + placement coherence.
3. Bump `WORLD_VERSION`, rebuild DLL, update `packet_schemas.md`, record final
   param names/defaults back into this spec.

**Status: landed 2026-06-23** (defaults in Data Model; verified via render probe).

### Iteration 2 — Transition scree (gravel seam), visual-only

Gravel/pebbles concentrated at the open↔grass seam plus a faint scatter on open
dirt, painted in the ground shader from the existing rock textures.

- Owner: the ground shader composition only. It is applied AFTER the grass
  ladder, keyed off `grass_density` (peaks where density is mid = the seam) and
  broken into pebbles by a mid-frequency field and the rock-grain luma.
- **Does NOT** touch `grass_density`, the field formula, placement, or the
  packed-param contract → **no C++ mirror, no `WORLD_VERSION` bump** (LAW 4: a
  visual parameter that does not change tile type / walkability).
- Knobs (visual-only) in `plains_ground_material_set.tres`:
  `scree_field_scale_px` (default `640.0`), `scree_density` (`0.45`),
  `scree_strength` (`0.9`), `scree_open_amount` (`0.25`).
- Raised stone OBJECTS with contact shadows are NOT owned by this shader
  iteration; they later landed as packet-backed `object_kind == 6` in
  `world_object_placement_v0.md`, using an atlas + `MultiMeshInstance2D`
  presentation path instead of an AI/seamless texture.

**Status: landed 2026-06-23** (verified via render probe).

### Iteration 3 — Ecotone edge mottling (visual-only)

The grass↔bare boundary read as a smooth fade; the reference has a ragged,
interfingered edge (grass tongues, dirt bays, stranded clumps). A fine
high-frequency field perturbs the ground texture ladder (and scree) **only inside
the transition band**, through a separate `grass_density_visual`: the texture edge
interfingers while tuft/tree placement keeps the smooth `grass_density` (no
field-mirror change, no `WORLD_VERSION` bump). No new transition texture was
needed — the existing `dry_grass_transition` ladder step just lacked a ragged
edge. Knobs in the material set: `edge_mottle_strength` (0.22),
`edge_mottle_scale_px` (150).

**Status: landed 2026-06-24** (verified via render probe).

### Open-ground tonal-mass tuning (visual-only)

The existing soil field and `macro_drift` now form a three-scale hierarchy:
`soil_field_scale_px = 2400`, `macro_drift_scale_px = 4600`, and the longer
coverage `macro_mass_scale_px = 7000`. The drift uses a contrast-shaped field
with `macro_drift_strength = 0.16` and fades over dense grass, so bare clearings
gain readable dark-soil/light-dust structure without changing placement.

**Status: landed 2026-07-29; manual visual verification pending.**

## Required Updates

When this spec is implemented:

- `packet_schemas.md` — add the new `PARAM_*` slots to the
  `GrassScatterBufferResult` param notes (boundary schema change).
- `terrain_hybrid_presentation.md` — cross-reference this spec from the
  "Runtime 2D Terrain Ground Composition" section (the field gains macro-mass +
  path terms; no ownership change).
- `docs/02_system_specs/README.md` — index entry (added with this draft).
- This spec — approved by the human on 2026-06-23 (`status: approved`,
  `source_of_truth: true`). Fill in final param names/defaults after Iteration 1.
