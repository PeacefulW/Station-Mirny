---
title: Cliff Forge 47 Iteration 10 Brief
doc_type: iteration_brief
status: completed
owner: engineering
source_of_truth: false
version: 1.0
last_updated: 2026-04-20
related_docs:
  - rimworld_autotile_generator_review.md
  - rimworld_autotile_generator_iteration_9_brief.md
  - rimworld_autotile_generator_active_epic.md
  - ../../docs/README.md
  - ../../docs/00_governance/WORKFLOW.md
  - ../../docs/00_governance/ENGINEERING_STANDARDS.md
  - ../../docs/00_governance/PROJECT_GLOSSARY.md
  - ../../docs/02_system_specs/world/terrain_hybrid_presentation.md
---

# Iteration 10 - Material Layer Stack (v2)

## Goal

Expand the editor-side material layer stack so the remaining roadmap layers are
available, the author can add/remove layers from the stack, biome palette and
texture-derived tint workflows exist, and directional weathering is exposed
through a global sun azimuth control.

This iteration remains editor-only and visual-only.

## Runtime classification

- runtime work class: `interactive`
- authoritative source of truth: `state.materialLayers` plus editor control
  values for palette/weathering inputs
- derived state: material maps, atlases, preview, gallery, exported recipes,
  session/custom-preset payloads
- dirty unit: one layer mutation, one palette apply, or one weathering control
  change
- single write owner: editor UI handlers in
  `rimworld_autotile_generator_runtime_export.js`

## Non-Goals

- no PBR / ORM / emission / flow outputs yet
- no Godot `.tres` export yet
- no per-layer nested parameter panels beyond the current generic controls
- no runtime-side contract changes outside the tool

## Allowed Files

- `tools/rimworld-autotile-lab/rimworld_autotile_generator.html`
- `tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- `tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md`

## Forbidden Files

- files outside `tools/rimworld-autotile-lab/`
- canonical docs in `docs/` unless editor/runtime contract drift is proven

## Implementation Steps

1. Add the remaining v2 layer modules:
   - `moss`
   - `rivets`
   - `runes`
   - `puddles`
   - `debris`
   - `rust`
   - `sand`
   - `concrete`
   - `mud`
   - `hex`
   - `cobblestone`
2. Add layer library controls for add/remove in the stack UI.
3. Add global authoring helpers:
   - noise preset apply
   - biome palette apply
   - texture-derived tint extraction
4. Add `sun azimuth` and feed it into directional weathering-aware layers.
5. Keep all new state compatible with recipe export/import, custom presets, and
   session restore.

## Risks

- the editor hot path can grow if layer count and layer sampling scale without
  preserving material-only invalidation
- palette extraction can produce poor colors on edge-case textures
- add/remove layer UI can make persisted payloads unstable if normalization is
  not explicit

## Smoke Tests

- `node --check tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- `git diff --check -- tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js tools/rimworld-autotile-lab/rimworld_autotile_generator.html tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md tools/rimworld-autotile-lab/rimworld_autotile_generator_iteration_10_brief.md`
- grep for `layerLibraryType`, `addMaterialLayer`, `removeMaterialLayer`,
  `extractPaletteFromTextures`, `applyNoisePreset`, and `sunAzimuth`

## Definition of Done

- the editor can add/remove the full v2 layer library from the stack
- directional weathering is controllable through `sun azimuth`
- biome palette and texture-derived tint helpers are available and wired
- no canonical doc updates are required, or grep proof is recorded if they are
