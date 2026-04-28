---
title: Cliff Forge Desktop Material Layer Stack - Iteration Brief
doc_type: iteration_brief
status: approved
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-27
---

# Goal

Add a Russian-language material authoring tab to `Cliff Forge Desktop` so walls,
floors, and cliff faces can use procedural layer-stack materials instead of
requiring external image textures.

The first iteration must provide enough control for game-ready 32px visual work
without introducing a node editor.

# Scope

Add material controls for these slots:

- `Верх (Top)`
- `Лицевая (Face)`
- `Основа/пол (Base)`

Each slot supports:

- `Процедурный (Procedural)`
- `Файл (Image)`
- `Цвет (Flat)`

Procedural kinds:

- `Stone blocks / bricks`
- `Cracked dry earth`
- `Rough stone`
- `Metal worn`
- `Wood planks`
- `Packed dirt`
- `Concrete`
- `Ice / frost`
- `Ash / burnt ground`

Editable parameters:

- `Scale`
- `Contrast`
- `Crack amount`
- `Wear`
- `Grain`
- `Edge darkening`
- `Seed`
- `Color A`
- `Color B`
- `Highlight`

# Non-Goals

- Do not change Station Mirny runtime world generation.
- Do not add a node graph editor in this iteration.
- Do not remove existing image texture loading.
- Do not change canonical game save/load, packet, command, or event contracts.
- Do not add repo-wide tooling outside `tools/rimworld-autotile-lab`.

# Allowed Files

- `tools/rimworld-autotile-lab/desktop_material_layer_stack_iteration_brief.md`
- `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- `tools/rimworld-autotile-lab/desktop_app/README.md`

# Forbidden Files

- Station Mirny runtime/gameplay systems outside `tools/rimworld-autotile-lab`
- canonical `docs/` files unless this iteration changes a canonical contract
- legacy HTML generator files

# Design Notes

- `recipe.json` is the authoring source of truth for material choices.
- Rust core owns procedural material generation and exported pixels.
- Python shell only edits material parameters and sends them to the core.
- Procedural materials must be deterministic for the same recipe.
- Existing recipes without `materials` must still load through defaults.
- Layer stack is implemented as a fixed internal stack:
  base color ramp -> large structure -> cracks/cells/grain -> wear -> edge
  darkening -> contrast.

# Acceptance Tests

- Desktop shell still compiles with `python -m py_compile`.
- Rust core builds with `cargo build`.
- Release core builds through `build_core.cmd`.
- A draft render with procedural `stone_bricks`, `cracked_earth`, and
  `wood_planks` across the three slots completes and writes `preview.png`.
- A full render completes and writes material export PNGs and `recipe.json`.
- A saved recipe includes `materials.top`, `materials.face`, and
  `materials.base`.

# Required Updates

- Update `desktop_app/README.md` with the new material tab and procedural
  material support.
