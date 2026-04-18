---
name: loading-lag-hunter
description: >
  Diagnose long boot, loading-screen drag, streaming spikes, and first-playable
  delays in Station Mirny. Use when the user reports "долгая загрузка",
  "долго стартует", "долго загружается мир", "тянется экран загрузки",
  "подлагивает при подгрузке", "boot too slow", "loading screen hangs",
  "first playable too late", or "streaming hitch".
---

# Loading Lag Hunter

Use this skill for startup, load, restore, and streaming-latency problems.

This skill owns performance issues where the player waits for the world to
become ready, rather than interactive hitches inside an already-playable frame.

## Read first

- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- the relevant world/runtime ADRs from `docs/05_adrs/`

## What this skill does

1. Separate boot-time, restore-time, and runtime-streaming delays.
2. Check whether the system honors staged loading, degraded mode, and honest
   first-playable readiness.
3. Look for monolithic waits, sync rebuilds, or overscoped payload application.
4. Keep load improvements aligned with canonical boot and world-readiness rules.

## Default workflow

1. Confirm the complaint is about loading, startup, restore, or streaming readiness.
2. Read the boot/readiness and world-lifecycle sections in the relevant current spec or ADR.
3. Use the living canonical docs to confirm sanctioned boot/readiness probes rather than inventing new ones.
4. Check whether work that should be staged or budgeted is still happening as one blocking step.
5. Prefer honest first-playable earlier, with noncritical work deferred behind budgets.
6. Treat temporary degraded visuals as acceptable if they reduce blocking wait and preserve correctness.

## Typical smells

- boot waits for full visual completion when terrain-ready would be enough
- load/restore forces synchronous rebuilds that could be staged
- streaming performs large scene or TileMap work in one frame
- readiness is reported too early or too late relative to actual playable state
- restore paths re-run heavy work that should stay cached, diff-based, or budgeted

## Compose with other skills

- Load `frame-budget-guardian` when the solution depends on queue shaping or per-frame workload envelopes.
- Load `save-load-regression-guard` when the slowdown is tied to restore semantics or save-state application.

## Boundaries

- Do not use this as the main skill for a mining, building, or single-action hitch after gameplay is already responsive. Use `world-perf-doctor`.
- Do not turn a boot issue into a generic world refactor if the real fix is a smaller staged-loading change.
