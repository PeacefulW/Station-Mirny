---
title: Agent Tooling
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-05-13
related_docs:
  - WORKFLOW.md
  - ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Agent Tooling

This document defines the local tooling that agents may use to shorten the
feedback loop without widening task scope.

## Installed Tooling

- GdUnit4 `6.1.3` is installed under `addons/gdUnit4/` and enabled in
  `project.godot`.
- GDQuest GDScript Formatter `0.19.0` is downloaded locally under
  `.tools/agent/gdscript-formatter/`. The `.tools/` directory is ignored and is
  not canonical project content.
- Godot headless validation uses the repository Godot console binary when
  present, then `GODOT_BIN`, then `godot`/`godot4` from `PATH`.
- GoPeak Godot MCP is not auto-enabled by the repository. A compact local-only
  example lives at `tools/agent/mcp/gopeak.codex.example.json`.

## Commands

Run the default agent validation loop:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent/Invoke-AgentValidation.ps1
```

Run only GdUnit4:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent/Invoke-GdUnit4.ps1
```

Run the GDScript formatter check on changed `.gd` files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent/Invoke-GDScriptFormatCheck.ps1
```

Update the GDExtension compile database for C++ editor tooling:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent/Update-GDExtensionCompileDatabase.ps1
```

## Scope Rules

- Default validation must stay narrow: changed GDScript format/lint plus
  `tests/unit` GdUnit4 tests.
- Full smoke scripts under `tools/` are explicit checks, not default checks.
- Formatter wrappers must not rewrite the whole repository by default.
- GDExtension compile database generation is a C++ tooling step, not proof that
  a runtime-sensitive feature is safe.
- MCP runtime inspection is optional evidence. It does not replace canonical
  specs, ADRs, or acceptance tests.

## Test Placement

- GdUnit4 unit and small integration tests live under `tests/unit/` unless a
  feature spec names a narrower path.
- Runtime or visual smoke scripts may remain under `tools/` when they are
  command-line probes rather than GdUnit4 suites.
- GdUnit4 reports are written under `test-results/gdunit4/` and ignored by git.

## C++ Hygiene

- `.clang-format` and `.clang-tidy` define the baseline C++ style and static
  analysis profile for `gdextension/src/`.
- `gdextension/compile_commands.json` is generated locally for clangd,
  clang-tidy, and IDE indexing.
- Heavy loops and scalable runtime paths still follow
  `ENGINEERING_STANDARDS.md` and ADR-0001; tooling must not justify moving
  unbounded work into GDScript or interactive paths.

## MCP Safety

- Use GoPeak with `GOPEAK_TOOL_PROFILE=compact` by default.
- Keep bridge/network bindings on loopback (`127.0.0.1`).
- Do not let MCP tools perform broad scene/resource rewrites unless the task
  explicitly allows that mutation path.
- Runtime inspection, screenshots, input injection, and debugger tools are
  allowed only when they are directly relevant to the requested verification.
