---
title: Cliff Forge 47 Iteration 9 Brief
doc_type: iteration_brief
status: completed
owner: engineering
source_of_truth: false
version: 1.0
last_updated: 2026-04-20
related_docs:
  - rimworld_autotile_generator_review.md
  - rimworld_autotile_generator_active_epic.md
  - ../../docs/README.md
  - ../../docs/00_governance/WORKFLOW.md
  - ../../docs/00_governance/ENGINEERING_STANDARDS.md
  - ../../docs/00_governance/PROJECT_GLOSSARY.md
  - ../../docs/02_system_specs/world/terrain_hybrid_presentation.md
---

# Iteration 9 - Material Layer Stack (v1)

## Goal

Introduce a first-class material layer stack for the editor so top and face
material maps are authored through ordered layers instead of one fixed shader
formula only.

This iteration is editor-only and visual-only.

## Runtime classification

- runtime work class: `interactive`
- authoritative source of truth: `state.materialLayers`
- derived state: material maps, material albedo canvases, normal canvases,
  atlases, gallery, preview, recipe/session/custom-preset payloads
- dirty unit: one layer card mutation or one reorder operation
- single write owner: the layer-stack UI handlers in
  `rimworld_autotile_generator_runtime_export.js`

## Non-Goals

- no Godot `.tres` export yet
- no PBR / ORM / emission / flow outputs yet
- no new runtime contracts outside the editor tool
- no 20+ module library from the long-term roadmap
- no deep per-layer custom parameter panels in this iteration

## Allowed Files

- `tools/rimworld-autotile-lab/rimworld_autotile_generator.html`
- `tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- `tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md`

## Forbidden Files

- files outside `tools/rimworld-autotile-lab/`
- canonical docs in `docs/` unless runtime/editor contract drift is proven

## Implementation Steps

1. Add `materialLayers` as editor state with stable ordering and preset-aware
   defaults.
2. Add a layer-stack UI with card ordering, enable toggle, strength, blend,
   mask, and height contribution controls.
3. Refactor material-map build into a layered pipeline that still preserves the
   current legacy base look as the starting layer.
4. Ship five starter layer modules:
   - `brick`
   - `plank`
   - `stoneCluster`
   - `snowDrift`
   - `cracks`
5. Fold layer-stack state into:
   - JSON recipe export/import
   - custom preset save/load
   - session restore

## Risks

- material rebuild cost can increase if layer passes force extra full rebuilds
- layer order bugs can silently change the visual result between preset,
  restore, and export paths
- UI reorder work can conflict with existing preview map pointer handling if not
  kept isolated

## Smoke Tests

- `node --check tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`
- `git diff --check -- tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js tools/rimworld-autotile-lab/rimworld_autotile_generator.html tools/rimworld-autotile-lab/rimworld_autotile_generator_active_epic.md tools/rimworld-autotile-lab/rimworld_autotile_generator_iteration_9_brief.md`
- grep for `materialLayers`, `renderMaterialLayerControls`, `buildLayeredMaterialMap`,
  `downloadBundleZip`, and `restoreSessionState`

## Definition of Done

- the editor shows a reorderable layer-stack panel
- material maps rebuild from the ordered stack with the five starter modules
- layer ordering and controls survive JSON import/export, custom presets, and
  session restore
- no canonical doc updates are required, or grep proof is recorded if they are
