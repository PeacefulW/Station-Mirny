---
title: Cliff Forge Desktop Rewrite - Iteration Brief
doc_type: iteration_brief
status: approved
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-20
---

# Goal

Build a new desktop autotile authoring tool under `tools/rimworld-autotile-lab`
with:

- a native generation core (`Rust`)
- a desktop shell (`Python`)
- a fresh rendering/export pipeline that does not clone the legacy HTML tool
- consistent notch handling so inner corner cuts do not visually pop compared to
  ordinary edges

# Non-Goals

- Do not rewrite Station Mirny runtime systems.
- Do not replace the existing legacy HTML tool in this iteration.
- Do not port every legacy experimental export and every authoring panel 1:1.
- Do not introduce repo-wide build tooling outside this tool area.

# Files Likely Involved

- `tools/rimworld-autotile-lab/desktop_rewrite_iteration_brief.md`
- `tools/rimworld-autotile-lab/desktop_app/**`
- legacy reference only:
  - `tools/rimworld-autotile-lab/rimworld_autotile_generator.html`
  - `tools/rimworld-autotile-lab/rimworld_autotile_generator_runtime_export.js`

# Risks

- Rust toolchain bootstrap on the current machine may fail or take time.
- PySide6 may be unavailable; if so, use a lighter desktop shell path.
- The biggest product risk is shipping a "desktop wrapper" while keeping the
  old heavy rebuild behavior. The new pipeline must have an actual cheap preview
  path.

# Implementation Steps

1. Create a new desktop app layout beside the legacy tool.
2. Implement a Rust core that:
   - enumerates the 47 canonical signatures
   - generates tile masks, height, normals, albedo, and preview atlases
   - uses unified edge math so notch cuts follow the same visual falloff as
     ordinary edges
3. Implement a Python desktop shell that:
   - edits parameters
   - previews one live map and one atlas
   - imports optional textures
   - exports core image assets and recipe JSON
4. Add a fast draft/preview path and keep export audit out of interactive edits.
5. Verify with smoke tests and manual launch instructions.

# Smoke Tests

- Launch desktop shell without crashing.
- Generate the 47-case atlas for the default preset.
- Change a shape slider and confirm preview refreshes.
- Export atlas PNG + preview PNG + recipe JSON.
- Load the saved recipe JSON and confirm parameters restore.
- Verify gallery variant selector is populated on cold start.

# Definition of Done

- A new desktop tool exists in a separate folder and runs without relying on the
  legacy HTML UI.
- Core preview/export loop is working.
- Notch rendering is not visually treated as a separate, highlighted artifact.
- Smoke checks are recorded in the closure report.
