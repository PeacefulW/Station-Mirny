---
name: frame-budget-guardian
description: >
  Enforce frame-budget discipline for Station Mirny proposals and fixes. Use
  when the user wants a performance fix, a new system, or a shortcut that risks
  full rebuilds, large loops, sync world work, "пересчитать всё сразу",
  "можно просто обновить весь чанк", "спайки кадра", "просадка фреймтайма",
  "frame spike", "budget violation", or "full rebuild".
---

# Frame Budget Guardian

Use this skill as the performance-law reviewer for Station Mirny.

This skill does not own a subsystem. It owns the budget discipline that decides
whether a proposed solution is architecturally safe for runtime.

## Read first

- `docs/00_governance/ENGINEERING_STANDARDS.md`
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- the relevant subsystem spec or ADR for the task

## What this skill does

1. Classify the work as boot, background, or interactive.
2. Check whether the proposed fix obeys dirty-queue and per-frame budget rules.
3. Reject synchronous designs that hide large work behind "it only happens sometimes".
4. Push the solution toward local dirty units, incremental processing, and honest degraded mode.

## Default workflow

1. Identify the trigger path and the exact frame where the work lands.
2. Compare the proposal against the runtime-work classes, dirty-unit limits, and forbidden synchronous work in the living governance docs.
3. Define the dirty unit: tile, chunk-edge patch, room, queue item, or another bounded unit.
4. Require a budgeted background path for everything bigger than the local action itself.
5. Require verification that heavy native/GDScript bridge payloads or mass scene operations are not hiding inside the proposed fix.

## Typical smells

- "just rebuild the whole thing once"
- "it is only one loop over loaded chunks"
- "the profiler says the function is fast, so the frame spike is fine"
- mass `set_cell`, `add_child`, `queue_free`, or `clear` in response to one local event
- no degraded mode or queue when work obviously exceeds a local patch

## Compose with other skills

- Load this together with the domain skill that owns the subsystem under discussion.
- For world-layer performance work, pair it with `world-perf-doctor` or `loading-lag-hunter`.

## Boundaries

- Do not use this alone as a replacement for subsystem-specific diagnosis.
- Do not treat average FPS as proof if the player-facing frame still hitches.
