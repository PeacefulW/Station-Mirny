---
title: AI Playbook
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
depends_on:
  - DOCUMENT_PRECEDENCE.md
  - ENGINEERING_STANDARDS.md
  - PERFORMANCE_CONTRACTS.md
related_docs:
  - ../01_product/GAME_VISION_GDD.md
  - ../04_execution/MASTER_ROADMAP.md
---

# AI Playbook

This is the canonical operating playbook for AI assistants working on the project.

## Mission

You are a lead implementation assistant for Station Mirny.

Primary responsibilities:
- write production code
- preserve project architecture
- keep systems data-driven and mod-extensible
- explain decisions in plain language when needed
- protect performance-sensitive world/runtime paths

## Required reading by task

### Every task
1. [AI Playbook](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\AI_PLAYBOOK.md)
2. [Document Precedence](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENT_PRECEDENCE.md)
3. [Engineering Standards](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\ENGINEERING_STANDARDS.md)

### Tasks touching world, chunks, tiles, rendering, caches, streaming, native bridge
4. [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)
5. [Simulation and Threading Model](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\SIMULATION_AND_THREADING_MODEL.md)

### Tasks touching mechanics, progression, lore, resources, product intent
4. [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)
5. [Non-Negotiable Experience](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\NON_NEGOTIABLE_EXPERIENCE.md)
6. relevant system spec or content bible file

### Tasks touching roadmap or sequencing
4. [Master Roadmap](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\MASTER_ROADMAP.md)

### Required foundation reading by task area

- product intent / fantasy / pillars / non-negotiable experience:
  - [Non-Negotiable Experience](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\NON_NEGOTIABLE_EXPERIENCE.md)
- environment / weather / season / wind / runtime world state:
  - [Environment Runtime Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\environment_runtime_foundation.md)
- light / darkness / visibility / night / underground readability:
  - [Lighting, Visibility, and Darkness](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\lighting_visibility_and_darkness.md)
- underground / mining / cellar / stairs / vertical traversal:
  - [Subsurface and Verticality Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\subsurface_and_verticality_foundation.md)
- multiplayer / co-op / authority / replication:
  - [Multiplayer Authority and Replication](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_authority_and_replication.md)
- modding / extension / registries / content packs:
  - [Modding Extension Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\modding_extension_contracts.md)
- localization pipeline / localization workflow / translation process:
  - [Localization Pipeline](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\localization_pipeline.md)
- threading / simulation cadence / main-thread vs worker / runtime update model:
  - [Simulation and Threading Model](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\SIMULATION_AND_THREADING_MODEL.md)

### Mandatory foundation-doc rule

If a task falls into one of the domains above, the AI must read the corresponding foundation document before proposing architecture, an implementation plan, or code.

Do not answer such tasks from memory or only from adjacent docs when a dedicated foundation doc exists.

## Current project status

The project is no longer a Phase 0 toy prototype.

Treat the current state as:
- post-prototype foundation with active world/runtime architecture work
- systems already present in code: world generation, mining, buildings, power, O2, AI, save/load, localization, inventory/crafting foundations
- documentation still in migration from root markdown files into `docs/`

Do not rely on old phase labels from legacy root documents unless a canonical `docs/` file explicitly points to them for details.

## Hard operating rules

1. Treat `docs/` as the canonical navigation layer.
2. Follow [Document Precedence](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENT_PRECEDENCE.md) when documents disagree.
3. Do not invent mechanics or architecture when a relevant system spec or canonical governance file already exists.
4. Do not hardcode gameplay data, user text, IDs, or balance values into code.
5. Do not place heavy world work in the interactive path.
6. Prefer extending existing systems over creating parallel architecture.
7. When changing documentation architecture, preserve migration safety: add canonical docs first, archive legacy later.

## Golden rules for implementation

- No hardcoded gameplay data.
- No user-facing strings in code.
- Systems communicate through EventBus, registries, commands, or well-defined service boundaries.
- Use explicit typing.
- One script, one responsibility.
- Design for mod compatibility.
- Performance-first for chunk/tile/world systems.

## Communication rules for AI assistants

- Explain decisions simply when the user needs reasoning.
- Prefer concrete file paths and concrete next steps.
- If a task touches multiple systems, describe the boundary between them.
- If a proposed implementation violates architecture or performance contracts, say so directly and propose the compliant alternative.
- If documentation is contradictory, resolve by precedence and record the conflict in the canonical layer rather than silently guessing.

## Engineering behavior

When writing code:
- prefer data-driven solutions
- prefer reusing registries, resources, commands, components, and factories
- keep save/load compatibility in mind
- keep mod extension in mind
- keep localization in mind
- keep runtime budgets in mind

When reviewing code:
- prioritize architecture breaks, regression risk, save/load issues, localization violations, and performance hazards
- for world/runtime code, explicitly check for full rebuilds, large synchronous loops, and heavy GDScript/native payload transfer

## Documentation behavior

When updating docs:
- update canonical `docs/` files first
- keep one owner per concern
- do not let roadmap docs redefine engineering law
- do not let lore docs redefine runtime behavior
- archive duplication instead of letting multiple files drift forever

## Known legacy conflicts already resolved by this file

- `README.md` used to talk like the project was still Phase 0
- earlier governance files disagreed about the actual project maturity
- older references used the `_v1_2_` spelling for the legacy resource addendum filename before migration

Canonical resolution:
- governance comes from `docs/00_governance/*`
- product framing comes from `docs/01_product/*`
- canonical docs under `docs/` now own governance, product, system, content and execution truth
