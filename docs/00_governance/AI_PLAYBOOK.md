---
title: AI Playbook
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.3
last_updated: 2026-04-02
depends_on:
  - DOCUMENT_PRECEDENCE.md
  - ENGINEERING_STANDARDS.md
  - PERFORMANCE_CONTRACTS.md
  - WORKFLOW.md
related_docs:
  - WORKFLOW.md
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
1. [AI Playbook](AI_PLAYBOOK.md)
2. [Workflow](WORKFLOW.md)
3. [Document Precedence](DOCUMENT_PRECEDENCE.md)
4. [Engineering Standards](ENGINEERING_STANDARDS.md)

### Tasks touching world, chunks, tiles, rendering, caches, streaming, native bridge
5. [Performance Contracts](PERFORMANCE_CONTRACTS.md)
6. [Simulation and Threading Model](SIMULATION_AND_THREADING_MODEL.md)

### Tasks touching the world / mining / topology / reveal / presentation stack
5. [Performance Contracts](PERFORMANCE_CONTRACTS.md)
6. [Simulation and Threading Model](SIMULATION_AND_THREADING_MODEL.md)
7. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md)

### Tasks touching mechanics, progression, lore, resources, product intent
5. [Game Vision GDD](../01_product/GAME_VISION_GDD.md)
6. [Non-Negotiable Experience](../01_product/NON_NEGOTIABLE_EXPERIENCE.md)
7. relevant system spec or content bible file

### Tasks touching roadmap or sequencing
5. [Master Roadmap](../04_execution/MASTER_ROADMAP.md)

### Tasks touching agent workflow, project skill authoring, or skill routing
5. [Agent Skill Pack](../02_system_specs/meta/agent_skill_pack.md)

### Required foundation reading by task area

- product intent / fantasy / pillars / non-negotiable experience:
  - [Non-Negotiable Experience](../01_product/NON_NEGOTIABLE_EXPERIENCE.md)
- environment / weather / season / wind / runtime world state:
  - [Environment Runtime Foundation](../02_system_specs/world/environment_runtime_foundation.md)
- light / darkness / visibility / night / underground readability:
  - [Lighting, Visibility, and Darkness](../02_system_specs/world/lighting_visibility_and_darkness.md)
- underground / mining / cellar / stairs / vertical traversal:
  - [Subsurface and Verticality Foundation](../02_system_specs/world/subsurface_and_verticality_foundation.md)
- multiplayer / co-op / authority / replication:
  - [Multiplayer Authority and Replication](../02_system_specs/meta/multiplayer_authority_and_replication.md)
- modding / extension / registries / content packs:
  - [Modding Extension Contracts](../02_system_specs/meta/modding_extension_contracts.md)
- localization pipeline / localization workflow / translation process:
  - [Localization Pipeline](../02_system_specs/meta/localization_pipeline.md)
- threading / simulation cadence / main-thread vs worker / runtime update model:
  - [Simulation and Threading Model](SIMULATION_AND_THREADING_MODEL.md)
- agent workflow / project skill pack / Station Mirny routing:
  - [Agent Skill Pack](../02_system_specs/meta/agent_skill_pack.md)

### Mandatory foundation-doc rule

If a task falls into one of the domains above, the AI must read the corresponding foundation document before proposing architecture, an implementation plan, or code.

Do not answer such tasks from memory or only from adjacent docs when a dedicated foundation doc exists.

Before any task, the AI must also read [Workflow](WORKFLOW.md) and follow it as mandatory operating procedure.

Before any iteration that touches the `world / mining / topology / reveal / presentation` stack, the AI must also read [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md).

The `draft` status of a required foundation document does not make it optional. If the playbook says the doc must be read, it must be read.

## Current project status

The project is no longer a Phase 0 toy prototype.

Treat the current state as:
- post-prototype foundation with active world/runtime architecture work
- systems already present in code: world generation, mining, buildings, power, O2, AI, save/load, localization, inventory/crafting foundations
- documentation still in migration from root markdown files into `docs/`

Do not rely on old phase labels from legacy root documents unless a canonical `docs/` file explicitly points to them for details.

## Hard operating rules

1. Treat `docs/` as the canonical navigation layer.
2. Follow [Document Precedence](DOCUMENT_PRECEDENCE.md) when documents disagree.
3. Do not invent mechanics or architecture when a relevant system spec or canonical governance file already exists.
4. Do not hardcode gameplay data, user text, IDs, or balance values into code.
5. Do not place heavy world work in the interactive path.
6. Prefer extending existing systems over creating parallel architecture.
7. When changing documentation architecture, preserve migration safety: add canonical docs first, archive legacy later.
8. Treat `.agents/skills/` as the canonical home for Station Mirny project skills; keep `.claude/skills/` only as a compatibility mirror.
9. For broad Station Mirny requests that span multiple domains, follow the router + specialist model from [Agent Skill Pack](../02_system_specs/meta/agent_skill_pack.md) instead of defaulting to generic single-skill advice.

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
