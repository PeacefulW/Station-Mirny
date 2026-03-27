---
title: World Layer Runtime Gap Closure Plan
doc_type: execution_plan
status: draft
owner: engineering+design
source_of_truth: false
version: 0.1
last_updated: 2026-03-27
related_docs:
  - MASTER_ROADMAP.md
  - ../00_governance/DOCUMENT_PRECEDENCE.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../05_adrs/0005-light-is-gameplay-system.md
  - ../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# World Layer Runtime Gap Closure Plan

This document sequences closure of the confirmed environment-runtime, lighting, z-layer, and persistence gaps found during the 2026-03-27 review pass.

It does not override:
- governance rules
- ADRs
- system specs

Those remain the source of truth.

## Documentation Compliance Rule

All work under this plan must be implemented strictly in accordance with the canonical documentation set.

Hard rule:
- execution work may sequence and decompose the fixes
- execution work may not override governance, ADRs, or system specs
- if implementation pressure conflicts with docs, higher-precedence docs win
- if the docs are wrong or stale, fix the docs in the same iteration instead of silently coding around them

## Why this plan exists

The 2026-03-27 review did not discover a new design direction.

It discovered that the current implementation still breaks already-approved contracts in a narrow but dangerous cluster:
- environment runtime leaks across new-game sessions
- surface daylight and sun/shadow presentation leak into underground space
- z-layer separation is not preserved consistently in save/load and background streaming
- startup shadow presentation misses the boot window and arrives visibly late

These are implementation gaps against the current docs, not new canonical rules.

## Confirmed gaps

### Gap A: new game does not reset authoritative time-of-day

Current problem:
- `TimeManager` is an autoload and keeps ticking while menu scenes are active
- the new-game path initializes world generation but does not reset environment runtime to the canonical starting state

Evidence:
- `project.godot`
- `core/autoloads/time_manager.gd`
- `scenes/ui/main_menu.gd`
- `scenes/ui/world_creation_screen.gd`
- `scenes/world/game_world.gd`

Risk:
- a new world can start at the previous session's evening or night state
- environment runtime leaks between sessions instead of starting from a clean morning baseline

### Gap B: startup mountain shadows are not part of the boot contract

Current problem:
- boot waits for chunk load and topology, but not for the first mountain shadow products
- initial shadow generation is deferred as a budgeted visual job after the loading screen is removed
- the first shadow build can also arrive before edge-cache readiness and do no useful work

Evidence:
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/autoloads/frame_budget_dispatcher.gd`
- `data/world/world_gen_balance.tres`

Risk:
- mountains visibly gain shadows seconds after gameplay starts
- boot violates the documented rule that first-view derived products may be prepared under the loading screen

### Gap C: underground inherits surface daylight tint

Current problem:
- `DaylightSystem` is a root-level `CanvasModulate`
- it consumes global time-of-day without any z-aware lighting context
- underground chunks are hidden or shown by z containers, but daylight tint remains global

Evidence:
- `scenes/world/game_world.tscn`
- `core/systems/daylight/daylight_system.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/z_level_manager.gd`

Risk:
- basements, cellars, and mines darken like outdoor evening
- underground loses its separate visual and gameplay identity

### Gap D: surface sun and shadow presentation is not z-scoped

Current problem:
- `MountainShadowSystem` owns a root-level `ShadowContainer`
- z switching hides chunk containers but does not scope this surface shadow presentation to the active layer

Evidence:
- `core/systems/lighting/mountain_shadow_system.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/chunk_manager.gd`

Risk:
- surface sun and shadow products can bleed into underground presentation
- lighting separation remains fragile even if underground fog and cover logic are correct

### Gap E: chunk diff persistence is not keyed by z-level

Current problem:
- runtime chunk modification storage is keyed by `Vector2i`
- diff filenames are also keyed only by `x/y`
- surface and subsurface versions of the same coordinate do not have separate persistence identities

Evidence:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_save_system.gd`

Risk:
- saving one layer can overwrite or collide with the other layer's diffs
- persistence breaks the "separate but linked" layer contract

### Gap F: player save and load do not persist current z-level

Current problem:
- player save payload stores `x/y` position only
- load restores position but not the current z-level
- runtime boot assumes surface `z = 0`

Evidence:
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/systems/world/z_level_manager.gd`
- `scenes/world/game_world.gd`

Risk:
- underground saves can reload into surface context at the same coordinates
- load becomes spatially invalid and can desync surrounding chunk state

### Gap G: load path is not idempotent around starter scrap and world pickups

Current problem:
- `GameWorld._ready()` spawns starter scrap before deferred pending-load application
- pickup world state is not fully modeled as deterministic save truth

Evidence:
- `scenes/world/game_world.gd`
- `scenes/world/spawn_orchestrator.gd`
- `core/autoloads/save_manager.gd`

Risk:
- repeated load can duplicate starter loot
- save and load fail the "same save, same world truth" expectation

### Gap H: saved time restore does not rebuild derived environment state

Current problem:
- save apply writes raw day, hour, and minute fields only
- derived state and related signals are not recomputed or replayed immediately after load

Evidence:
- `core/autoloads/save_appliers.gd`
- `core/autoloads/time_manager.gd`
- `scenes/ui/hud/hud_time_widget.gd`
- `core/entities/fauna/basic_enemy.gd`
- `core/systems/daylight/daylight_system.gd`

Risk:
- HUD phase labels, daylight consumers, and time-sensitive AI behavior can remain stale until a later natural tick

### Gap I: background streaming is not z-stable during floor transitions

Current problem:
- in-flight load, generation, and staging state do not carry z identity
- create and finalize logic branch on mutable current active z instead

Evidence:
- `core/systems/world/chunk_manager.gd`

Risk:
- a floor transition during background streaming can finalize work into the wrong layer or chunk type
- future multiplayer or deeper verticality work would inherit the same instability

## Explicit scope rule for this plan

This plan owns confirmed implementation gaps in:
- time and session reset
- startup shadow boot behavior
- surface versus underground lighting separation
- z-aware persistence and load truth
- z-stable streaming and finalization

It does not change the canonical behavior already defined in:
- `docs/02_system_specs/world/environment_runtime_foundation.md`
- `docs/02_system_specs/world/lighting_visibility_and_darkness.md`
- `docs/02_system_specs/world/subsurface_and_verticality_foundation.md`
- `docs/02_system_specs/meta/save_and_persistence.md`

## Suggested closure order

1. Reset authoritative environment runtime on new-game boot.
2. Establish a z-aware lighting context so underground does not inherit surface daylight or sun presentation.
3. Move first mountain shadow products into the boot contract or an equivalent pre-start cache path.
4. Make chunk diffs and player save/load fully z-aware.
5. Remove load-path non-idempotence around starter scrap and rebuild derived time state on load.
6. Stabilize in-flight streaming against active z changes.

## Stop conditions

Do not widen this plan into a general world-runtime rewrite if:
- a fix requires canonical spec changes first
- roof or reveal architecture starts getting mixed back into underground lighting separation
- save/load redesign broadens into unrelated slot or migration work not needed for these gaps

In those cases, stop, document the blocker, and create a narrower follow-up plan.
