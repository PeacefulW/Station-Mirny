# Mountain Bottom Outline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional width-controlled bottom contact outline for mountain generation.

**Architecture:** Extend the shared request contract with outline settings, expose them in the Python shell, and apply the visual effect as a Rust albedo post-process over rendered tile buffers. The post-process reads existing `SurfaceZone` and occupancy data so the outline is restricted to face pixels with base/empty terrain below.

**Tech Stack:** Rust core with `image`, `serde`, `schemars`; Python Tkinter shell; Rust unit tests and Python `unittest`.

---

### Task 1: Request Contract And Defaults

**Files:**
- Modify: `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- Test: `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- Test: `tools/rimworld-autotile-lab/desktop_app/shell/tests/test_app_payload.py`

- [ ] Add failing Rust assertions that the sanitized default mountain request has `mountain_outline_enabled == true`, `mountain_outline_width == 3`, and clamps an oversized width to `tile_size / 8`.
- [ ] Add failing Python assertions that the mountain preset includes the outline settings and `build_request()` serializes them.
- [ ] Add `mountain_outline_enabled` and `mountain_outline_width` to `AppRequest`, `Preset`, default request construction, sanitization, and Python preset/UI state.
- [ ] Run `cargo test` in `core`.
- [ ] Run `python -m unittest shell.tests.test_app_payload` from `shell`.

### Task 2: Bottom-Only Albedo Post-Process

**Files:**
- Modify: `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`

- [ ] Add a failing test where two otherwise identical SDF renders differ only when the outline is enabled.
- [ ] Add a failing test that checks a lower face contact pixel darkens while an upper lip/edge pixel remains unchanged.
- [ ] Implement an `apply_mountain_bottom_outline()` helper after base albedo rendering. It scans face pixels, looks down up to `mountain_outline_width`, and blends near-black when it sees empty/base terrain below.
- [ ] Keep the effect disabled for `mountain_outline_enabled == false` or `mountain_outline_width == 0`.
- [ ] Run `cargo test` in `core`.

### Task 3: UI Wiring And Recipe Round Trip

**Files:**
- Modify: `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- Test: `tools/rimworld-autotile-lab/desktop_app/shell/tests/test_app_payload.py`

- [ ] Add a checkbox labeled `Обводка низа горы` and an integer width slider labeled `Ширина обводки`.
- [ ] Include both fields in `build_request()`, `_apply_preset()`, and recipe loading.
- [ ] Add a shell test that applying the mountain preset sets the checkbox and width.
- [ ] Run `python -m unittest shell.tests.test_app_payload` from `shell`.

### Task 4: Final Verification

**Files:**
- Modify: `tools/rimworld-autotile-lab/desktop_app/README.md`

- [ ] Document the new outline control in the current feature list.
- [ ] Run `cargo test` in `core`.
- [ ] Run `python -m unittest shell.tests.test_app_payload` from `shell`.
- [ ] Run `git diff --check`.
