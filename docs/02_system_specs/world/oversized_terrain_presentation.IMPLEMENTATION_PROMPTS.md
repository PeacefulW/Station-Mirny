# Implementation Prompts — Oversized Terrain Presentation

These are ready-to-paste prompts for executing the iterations defined in
`docs/02_system_specs/world/oversized_terrain_presentation.md`.

Each prompt follows the WORKFLOW.md template. Run iterations one at a time.
Do not paste more than one prompt per agent invocation.

---

## Prompt for Iteration 1 — Spec land and contract clarification

```md
## Required reading before you start

- AGENTS.md
- docs/00_governance/WORKFLOW.md
- docs/00_governance/ENGINEERING_STANDARDS.md
- docs/00_governance/PROJECT_GLOSSARY.md
- docs/02_system_specs/world/oversized_terrain_presentation.md (the new
  draft spec; this task lands its sibling-doc updates and flips its status
  from `draft` to `approved` only after the listed sibling docs are
  updated)
- docs/02_system_specs/world/world_grid_rebuild_foundation.md
- docs/02_system_specs/world/terrain_hybrid_presentation.md
- docs/02_system_specs/world/mountain_generation.md
- docs/02_system_specs/world/lake_generation.md
- docs/02_system_specs/README.md

## Task

Land Iteration 1 of `oversized_terrain_presentation.md`. Edits are
documentation only. No code changes.

1. In `world_grid_rebuild_foundation.md`:
   - keep "logical world tile = 32 px" exactly as-is
   - rewrite the "presentation size of one world tile is 32 px" passage
     to clarify that *aligned* presentation is `32 px`; *oversized*
     presentation per shape set may be larger; presentation pixel size
     never enters logic, save, streaming, packets, or the building grid
   - keep the existing prohibition on mixing 32/64 conversions in
     **logic** paths; explicitly scope it to logic, not presentation
   - add a cross-link to `oversized_terrain_presentation.md`

2. In `terrain_hybrid_presentation.md`:
   - promote `TerrainShapeSet.tile_size_px` from "data-validation field"
     to "rendering-honored field"
   - add `TerrainOverhangPolicy` (canonical fields and constraints as
     listed in `oversized_terrain_presentation.md`)
   - add the validation entries listed in
     `oversized_terrain_presentation.md` Validation Model section
   - add a cross-link to `oversized_terrain_presentation.md`

3. In `mountain_generation.md`:
   - add a brief note that cliff/rim shape sets may opt into oversized
     presentation through `oversized_terrain_presentation.md`; logical
     mountain rules are unchanged

4. In `lake_generation.md`:
   - add a brief note confirming `water_surface` shape set stays aligned
     unless a future iteration explicitly opts into oversized banks

5. In `docs/00_governance/PROJECT_GLOSSARY.md`:
   - add `presentation tile pixel size` entry
   - add `oversized shape set` entry

6. In `docs/02_system_specs/README.md`:
   - index `oversized_terrain_presentation.md` next to the other world
     specs

7. In `oversized_terrain_presentation.md`:
   - flip `status: draft` to `status: approved`
   - flip `source_of_truth: false` to `source_of_truth: true`
   - bump `last_updated` to today's date

## Context

Logical world tiles stay at 32 px (Foundation contract). The new spec
allows per-shape-set presentation pixel size to exceed 32 px so cliffs,
mountain rims, and similar tall silhouettes can be authored with enough
pixels to read clearly. This iteration is documentation only — sibling
specs must be updated in the same task before the new spec is approved.

## Boundary contract check

- No new public API, command, event, or packet field is introduced by
  this iteration.
- `system_api.md`, `event_contracts.md`, `packet_schemas.md`, and
  `commands.md` do not need to change. Confirm with grep at closure.

## Performance / scalability guardrails

- Runtime class: not applicable (documentation only).
- Future-iteration target scale: VRAM grows ~quadratically with
  `tile_size_px`; the spec defines the validation surface but no ceiling
  is set in this iteration.

## Scope - what to do

- Edit the 6 sibling documents above as listed.
- Flip the new spec from `draft` to `approved`.
- Add cross-links between the new spec and its siblings.

## Scope - what NOT to do

- Do not touch any file outside `docs/`.
- Do not change `core/`, `data/`, `gdextension/`, `tools/`, `assets/`.
- Do not implement Iteration 2 or 3 in this task.
- Do not introduce a new public API, command, event, or packet field.
- Do not modify any meta boundary doc (`system_api.md`,
  `event_contracts.md`, `packet_schemas.md`, `commands.md`) — confirm
  with grep at closure that none was needed.

## Files that may be touched

- docs/02_system_specs/world/oversized_terrain_presentation.md
- docs/02_system_specs/world/world_grid_rebuild_foundation.md
- docs/02_system_specs/world/terrain_hybrid_presentation.md
- docs/02_system_specs/world/mountain_generation.md
- docs/02_system_specs/world/lake_generation.md
- docs/02_system_specs/README.md
- docs/00_governance/PROJECT_GLOSSARY.md

## Files that must NOT be touched

- everything outside `docs/`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/event_contracts.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/commands.md`
- any ADR file under `docs/05_adrs/`

## Acceptance tests

- [ ] grep `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
      for `presentation` shows the new logical-vs-presentation distinction
- [ ] grep `docs/02_system_specs/world/terrain_hybrid_presentation.md`
      for `TerrainOverhangPolicy` returns at least one match
- [ ] grep `docs/02_system_specs/world/terrain_hybrid_presentation.md`
      for `tile_size_px` shows the field promoted to rendering-honored
- [ ] grep `docs/00_governance/PROJECT_GLOSSARY.md` for
      `oversized shape set` returns one match
- [ ] grep `docs/02_system_specs/README.md` for
      `oversized_terrain_presentation` returns one index entry
- [ ] grep `docs/02_system_specs/meta/system_api.md`,
      `event_contracts.md`, `packet_schemas.md`, `commands.md` for
      `tile_size_px`, `oversize`, `overhang` returns zero matches (proof
      that no boundary doc was silently affected)
- [ ] `oversized_terrain_presentation.md` front matter is `status:
      approved`, `source_of_truth: true`, `last_updated` set to today

## Result format

Closure report following the format from WORKFLOW.md, in Russian with
canonical English terms in parentheses. Include grep evidence for each
acceptance test.
```

---

## Prompt for Iteration 2 — Generator export at chosen pixel size

```md
## Required reading before you start

- AGENTS.md
- docs/00_governance/WORKFLOW.md
- docs/00_governance/ENGINEERING_STANDARDS.md
- docs/02_system_specs/world/oversized_terrain_presentation.md (now
  approved)
- docs/02_system_specs/world/terrain_hybrid_presentation.md (Asset Layout
  Rule, Generator Contract section)
- tools/rimworld-autotile-lab/desktop_app/README.md
- tools/rimworld-autotile-lab/desktop_app/REVIEW_NOTES.md (context only;
  this task does not implement the broader review)

## Task

Make `Cliff Forge` reliably export a `64 px` oversized atlas suitable for
one cliff or mountain shape set, with the manifest fields the runtime
will consume in Iteration 3.

1. In the desktop generator UI (`shell/app.py`), expose `tile_size`
   selection that snaps to the first-wave canonical set `{32, 64}` on
   Full Generate. The slider may stay continuous, but the exported value
   must snap to one of these. Reserved values `{96, 128}` stay
   unselectable in this iteration; opening them is a separate
   data/policy task once a VRAM ceiling is defined.

2. In the Rust core (`core/src/render.rs` and friends), guarantee that
   atlases are exported at exactly the chosen `tile_size_px` with no
   internal resampling. If the user picked `64`, the atlas tile region
   must be `64x64` pixels exactly.

3. Extend the manifest (`OutputManifest` and the recipe written by the
   Rust core) with:
   - `tile_size_px: u32` (already present as `tile_size`; rename or alias
     to match the spec term, do not duplicate)
   - explicit `case_count: u32` and `variant_count: u32` (already
     `signature_count` and `variants` — alias or rename to match spec
     terms, no duplication)
   - `overhang_hint: { up_px, down_px, left_px, right_px }` reflecting
     what the generator drew (zero if aligned)

4. Author **one** new shape set + material set pair under
   `data/terrain/shape_sets/` and `data/terrain/material_sets/` that
   references the newly exported `64 px` atlas. Do **not** wire it into
   any presentation profile yet (Iteration 3 owns that). The pair exists
   only as data resources for downstream consumption.

## Context

The generator already supports `tile_size 32..128` in `model.rs` sanitize
clamps. The runtime does not yet honor `tile_size_px > 32`. This task
moves the generator forward independently so Iteration 3 has a real asset
to load when it lands runtime support.

## Boundary contract check

- No public API, command, event, or packet field changes.
- `system_api.md`, `event_contracts.md`, `packet_schemas.md`, and
  `commands.md` are not touched. Confirm with grep at closure.

## Performance / scalability guardrails

- Runtime class: not applicable (offline tool).
- Authoring time may grow with atlas size; that is acceptable for an
  offline tool.

## Scope - what to do

- generator UI snap-set
- atlas export at the chosen pixel size
- manifest fields per the spec
- one new shape set `.tres` and one new material set `.tres`, referencing
  the newly exported atlas

## Scope - what NOT to do

- do not touch `core/systems/world/world_tile_set_factory.gd`
- do not touch any `data/terrain/presentation_profiles/*.tres`
- do not change `chunk_view.gd`, `world_streamer.gd`, or any C++ in
  `gdextension/`
- do not implement Iteration 3
- do not change save/load behavior or packet schema

## Files that may be touched

- tools/rimworld-autotile-lab/desktop_app/shell/**
- tools/rimworld-autotile-lab/desktop_app/core/**
- assets/textures/terrain/** (only new exported textures for the new pair)
- data/terrain/shape_sets/<new>.tres
- data/terrain/material_sets/<new>.tres

## Files that must NOT be touched

- core/systems/world/**
- gdextension/**
- data/terrain/presentation_profiles/**
- data/terrain/shader_families/**
- docs/**
- save/persistence code

## Acceptance tests

- [ ] generator UI snaps `tile_size` to `{32, 64}` on Full Generate
      (manual human verification required for UI behavior); reserved
      values `{96, 128}` are not selectable in this iteration
- [ ] for a recipe with `tile_size_px = 64`, exported atlas tile region
      is exactly `64x64 px` (static verification: read PNG dimensions of
      one exported atlas tile)
- [ ] manifest JSON contains `tile_size_px`, `case_count`,
      `variant_count`, `overhang_hint` (static verification: parse
      `manifest.json` from a sample export)
- [ ] new shape set `.tres` references the new atlas paths and declares
      `tile_size_px = 64`
- [ ] new material set `.tres` references the new material atlas paths
- [ ] no presentation profile references the new pair yet (grep proof)
- [ ] no boundary meta-doc was modified (grep
      `system_api.md|event_contracts.md|packet_schemas.md|commands.md`
      for `tile_size_px`, `overhang` returns zero new matches)

## Result format

Closure report following the format from WORKFLOW.md, in Russian with
canonical English terms in parentheses. Include the manifest snippet from
a sample 64-px export as proof of acceptance test 3.
```

---

## Prompt for Iteration 3 — Runtime honor `tile_size_px`

```md
## Required reading before you start

- AGENTS.md
- docs/00_governance/WORKFLOW.md
- docs/00_governance/ENGINEERING_STANDARDS.md
- docs/00_governance/PROJECT_GLOSSARY.md
- docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md
- docs/05_adrs/0003-immutable-base-plus-runtime-diff.md
- docs/02_system_specs/world/oversized_terrain_presentation.md
- docs/02_system_specs/world/terrain_hybrid_presentation.md
- docs/02_system_specs/world/world_grid_rebuild_foundation.md
- docs/02_system_specs/world/world_runtime.md
- docs/02_system_specs/meta/system_api.md
- docs/02_system_specs/meta/packet_schemas.md
- core/systems/world/world_tile_set_factory.gd
- core/systems/world/chunk_view.gd
- core/systems/world/world_streamer.gd

## Task

Make the runtime honor `TerrainShapeSet.tile_size_px` and
`TerrainOverhangPolicy`. Aligned shape sets must keep rendering exactly
as today. One oversized shape set (the asset pair authored in Iteration
2) must render with declared overhang.

1. Add a new resource type `TerrainOverhangPolicy` with the canonical
   fields described in `oversized_terrain_presentation.md`.

2. Update `TerrainShapeSet` to carry a typed reference to a
   `TerrainOverhangPolicy` resource. Per the spec's locked decision,
   overhang policies live as shared `.tres` files under
   `data/terrain/overhang_policies/` and are referenced by id; do not
   inline overhang fields into the shape set.

3. In `WorldTileSetFactory`:
   - read `TerrainShapeSet.tile_size_px` per shape set
   - build the TileSet so per-source `texture_region_size` matches
     `tile_size_px`
   - compute per-tile `texture_origin` from the overhang policy
   - keep `cell_size = 32` for the consuming TileMap / chunk view layer

4. In `ChunkView`:
   - respect `z_order_bias` from overhang policy when assigning render
     order between aligned and oversized shape sets in the same chunk

5. In `TerrainPresentationRegistry` (or its bootstrap path):
   - validate that material set atlas dimensions correspond to the paired
     shape set's `tile_size_px`
   - validate that overhang policy sums equal `tile_size_px` on each axis
   - fail validation early; do not let chunk publish be the first place
     a mismatch is discovered

6. Author one `data/terrain/presentation_profiles/<oversized>.tres`
   binding the Iteration 2 shape+material pair to a shader family. Per
   the spec's locked decision, the canonical first oversized profile
   targets `mountain_rim`; bind the matching `terrain_id`.

7. Confirm and grep-prove that no GDScript file outside terrain
   presentation reads `tile_size_px` for logic, save, streaming, or
   building-grid purposes.

## Context

Logical tiles stay at 32 px. Presentation pixel size becomes per-shape-set.
The visual goal is a noticeably more detailed cliff or mountain rim at the
same camera zoom, while ground tiles stay aligned and unchanged.

## Boundary contract check

- Existing safe path to use: `TerrainPresentationRegistry` resolution from
  `terrain_id`. No new public API entry point.
- Packet contract: unchanged. `ChunkPacketV0` does not gain a field.
- Save contract: unchanged.
- Confirm at closure with grep that `system_api.md`,
  `packet_schemas.md`, `event_contracts.md`, `commands.md` are not
  touched.

## Performance / scalability guardrails

- Runtime class: presentation apply is `background` for chunk publish,
  `interactive` only for one-tile mutation visual patch.
- Target scale: per-loaded-chunk tile count is unchanged. The cost of one
  oversized shape set is constant per shape set, not per tile.
- Source of truth + write owner: native owns terrain classification and
  atlas indices; presentation owns pixel rendering.
- Dirty unit: unchanged from `terrain_hybrid_presentation.md`.
- Escalation path: if VRAM ceiling is approached, escalate to a
  documented asset-budget task; do not silently degrade.

## Scope - what to do

- one new resource type
- TileSet build path that honors `tile_size_px` and overhang
- one presentation profile bound to the oversized pair
- registry validation entries

## Scope - what NOT to do

- do not modify `gdextension/` C++ code
- do not change packet schema
- do not change save/persistence code
- do not adopt oversized presentation across multiple shape sets;
  Iteration 4 owns catalog adoption
- do not change camera zoom defaults
- do not change `TileMap` `cell_size` away from 32
- do not let `tile_size_px` leak into logic, save, streaming, or
  building-grid code

## Files that may be touched

- core/systems/world/world_tile_set_factory.gd
- core/systems/world/chunk_view.gd
- core/systems/world/world_streamer.gd
- new file(s) for `TerrainOverhangPolicy` resource and registry plumbing
  under `core/systems/world/`
- data/terrain/overhang_policies/<new>.tres
- data/terrain/presentation_profiles/<oversized>.tres

## Files that must NOT be touched

- gdextension/**
- save/persistence code
- docs/02_system_specs/meta/** (unless Boundary contract check shows a
  needed update; in that case, stop and ask before changing)
- docs/02_system_specs/world/oversized_terrain_presentation.md (already
  approved; do not silently mutate)

## Acceptance tests

- [ ] aligned shape sets render identically to baseline (manual human
      verification required: side-by-side screenshot of one chunk before
      and after the change)
- [ ] the Iteration 2 oversized shape set renders with declared overhang
      (manual human verification required: screenshot at default camera
      zoom)
- [ ] registry validation rejects an artificially broken overhang policy
      (static verification: temporary test resource with bad sums fails
      validation)
- [ ] grep `core/` excluding terrain presentation files for `tile_size_px`
      returns zero matches in logic/save/streaming code
- [ ] `ChunkPacketV0` byte layout is unchanged (compare a recorded packet
      hash before and after)
- [ ] save round-trip is unchanged (load a save written before this
      change; chunks render correctly)
- [ ] `system_api.md`, `event_contracts.md`, `packet_schemas.md`,
      `commands.md` are not modified (grep proof)

## Result format

Closure report following the format from WORKFLOW.md, in Russian with
canonical English terms in parentheses. Include screenshots referenced in
acceptance tests as separate file paths in the proof artifacts section.
```
