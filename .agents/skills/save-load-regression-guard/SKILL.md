---
name: save-load-regression-guard
description: >
  Guard save/load boundaries and runtime diff ownership in Station Mirny. Use
  when the user reports "после загрузки сломалось", "после сейва пропадает",
  "ломается после restore", "не восстанавливается состояние", "save/load regression",
  "restore bug", "state missing after load", or when a change adds new runtime
  state that must survive save and load.
---

# Save Load Regression Guard

Use this skill when persistence boundaries are part of the risk.

This skill owns save/load correctness, runtime diff ownership, and restore-path
regressions. It protects stability first and performance second.

## Read first

- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

## What this skill does

1. Identify whether the task introduces or changes authoritative runtime state.
2. Check whether that state belongs in immutable base data, runtime diff, or save payload.
3. Verify that save and restore flow through sanctioned owner paths.
4. Catch regressions where a feature works live but breaks after save/load.

## Default workflow

1. Find the owner of the affected state in the relevant contract document.
2. Confirm the sanctioned save/load entry points in `PUBLIC_API.md`, especially `SaveManager` and any owner-specific restore helpers.
3. Check whether the change adds new runtime state that must be collected, serialized, applied, or explicitly reconstructed.
4. Prefer diff-based persistence over redundant full-state snapshots when the contracts already define base + diff ownership.
5. Flag any direct field writes or side-channel restore logic that bypass canonical load orchestration.

## Typical smells

- feature works until save/load cycle
- restored runtime misses signals, invalidation, or owner-side initialization
- new mutable state has no collector/apply path
- UI or scene code bypasses `SaveManager`
- a "performance optimization" quietly duplicates canonical state instead of preserving base + diff

## Compose with other skills

- Load `loading-lag-hunter` if restore time itself is too slow.
- Load `world-perf-doctor` if the regression shows up in world runtime after reload.

## Boundaries

- Do not use this as the primary skill for pure boot or streaming performance unless persistence behavior is involved.
- Do not redesign the save system if the bug is a narrow owner-boundary violation.
