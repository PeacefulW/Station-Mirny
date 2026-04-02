---
name: world-perf-doctor
description: >
  Diagnose hitchy world interactions in Station Mirny. Use when the user reports
  mining hitch, building placement hitch, chunk seam redraw cost, topology churn,
  reveal churn, shadow churn, "лагает при копании", "фризит когда строю",
  "просадка при добыче", "дергается мир", "interactive world hitch",
  "mining hitch", "placement hitch", or "chunk seam redraw".
---

# World Perf Doctor

Use this skill for interactive world-performance problems.

This skill owns local gameplay hitches caused by world, mining, topology,
reveal, or presentation work landing in the player's immediate action path.

## Read first

- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

## What this skill does

1. Classify the complained-about work as interactive, background, or boot-time.
2. Find which world-layer contract is being violated: world, mining, topology,
   reveal, or presentation.
3. Look for the smallest valid fix that keeps interactive work local.
4. Preserve owner boundaries and safe entry points while removing hitchy work
   from the immediate action chain.

## Default workflow

1. Confirm the trigger is an in-play world hitch, not a long boot or load.
2. Map the symptom to the contract layer in `DATA_CONTRACTS.md`.
3. Check the safe entry point in `PUBLIC_API.md` before proposing or making a fix.
4. Reject fixes that solve the hitch by bypassing ownership, contracts, or save/runtime diff rules.
5. Prefer local dirty-region updates, queued follow-up work, and incremental rebuilds.
6. Verify that no full-chunk, all-loaded-chunk, or mass-visual rebuild remains in the interactive path.

## Typical smells

- one tile action triggers full chunk redraw
- mining or placement loops across loaded chunks
- local mutation forces topology, reveal, cover, cliff, or shadow rebuild everywhere
- presentation work leaks into canonical mutation timing
- a "small fix" secretly moves expensive work into the same input frame

## Compose with other skills

- Load `frame-budget-guardian` when the fix needs queue, dirty-unit, or per-frame budget discipline.
- Load `save-load-regression-guard` when the world hitch appears only after restore or touches runtime diff ownership.

## Boundaries

- Do not use this as the main skill for long boot, loading-screen drag, or streaming-first-playable issues. Use `loading-lag-hunter`.
- Do not use this to review generic persistence semantics unless save/load behavior is part of the symptom.
- Do not propose broad refactors when a narrow contract-preserving fix exists.
