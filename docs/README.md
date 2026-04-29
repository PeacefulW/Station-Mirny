---
title: Station Mirny Documentation Index
doc_type: docs_index
status: approved
owner: design+engineering
source_of_truth: true
version: 1.9
last_updated: 2026-04-29
related_docs:
  - 00_governance/WORKFLOW.md
  - 00_governance/ENGINEERING_STANDARDS.md
  - 02_system_specs/README.md
  - 05_adrs/README.md
---

# Documentation Index

This file is the canonical entrypoint for the documentation that is currently
checked into the repository.

Current policy:
- canonical navigation lives under `docs/`
- only link to documents that are present in the repository now
- if an older note mentions removed legacy docs or deleted execution/world
  paths, treat that as legacy wording and use the living docs listed below
  instead

## Layers

### `00_governance/`
Workflow rules, engineering standards, and shared terminology.

### `01_product/`
High-level vision, fantasy, pillars, and product framing.

### `02_system_specs/`
System contracts and subsystem architecture that still live in the repo.

### `03_content_bible/`
Lore, canon, open questions, flora/fauna/resources catalogs.

### `05_adrs/`
Architecture Decision Records.

### `06_templates/`
Templates for future docs.

## Current canonical map

### Governance
- [Workflow](00_governance/WORKFLOW.md)
- [Engineering Standards](00_governance/ENGINEERING_STANDARDS.md)
- [Project Glossary](00_governance/PROJECT_GLOSSARY.md)

### Product
- [Game Vision GDD](01_product/GAME_VISION_GDD.md)
- [Non-Negotiable Experience](01_product/NON_NEGOTIABLE_EXPERIENCE.md)

### System Specs
- [System Specs Index](02_system_specs/README.md)
- [World Grid Rebuild Foundation](02_system_specs/world/world_grid_rebuild_foundation.md)
- [World Runtime V0](02_system_specs/world/world_runtime.md)
- [World Foundation V1](02_system_specs/world/world_foundation_v1.md)
- [River Generation V1](02_system_specs/world/river_generation_v1.md)
- [Terrain Hybrid Presentation](02_system_specs/world/terrain_hybrid_presentation.md)
- [Engineering Networks](02_system_specs/base/engineering_networks.md)
- [Building and Rooms](02_system_specs/base/building_and_rooms.md)
- [Automation and Logistics](02_system_specs/base/automation_and_logistics.md)
- [Fauna and Threat Gameplay](02_system_specs/combat/fauna_and_threats.md)
- [Base Defense and Noise](02_system_specs/combat/base_defense_and_noise.md)
- [Resource Progression](02_system_specs/progression/resource_progression.md)
- [Character Progression](02_system_specs/progression/character_progression.md)
- [Crafting and Decryption](02_system_specs/progression/crafting_and_decryption.md)
- [Survival Core](02_system_specs/survival/survival_core.md)
- [UI and UX Foundation](02_system_specs/ui/ui_ux_foundation.md)
- [Agent Skill Pack](02_system_specs/meta/agent_skill_pack.md)
- [System API](02_system_specs/meta/system_api.md)
- [Event Contracts](02_system_specs/meta/event_contracts.md)
- [Packet Schemas](02_system_specs/meta/packet_schemas.md)
- [Commands](02_system_specs/meta/commands.md)
- [Localization Pipeline](02_system_specs/meta/localization_pipeline.md)
- [Modding Extension Contracts](02_system_specs/meta/modding_extension_contracts.md)
- [Multiplayer and Modding Constraints](02_system_specs/meta/multiplayer_and_modding.md)
- [Multiplayer Authority and Replication](02_system_specs/meta/multiplayer_authority_and_replication.md)
- [Save and Persistence](02_system_specs/meta/save_and_persistence.md)

### Content Bible
- [Content Bible Index](03_content_bible/README.md)
- [Canon](03_content_bible/lore/canon.md)
- [Open Questions](03_content_bible/lore/open_questions.md)
- [Flora and Resources](03_content_bible/resources/flora_and_resources.md)
- [Fauna Catalog](03_content_bible/fauna/catalog.md)
- [Art Direction](03_content_bible/aesthetics/art_direction.md)
- [Audio Direction](03_content_bible/aesthetics/audio_direction.md)

### ADRs
- [ADR Index](05_adrs/README.md)
- [ADR-0001 Runtime Work and Dirty Update Foundation](05_adrs/0001-runtime-work-and-dirty-update-foundation.md)
- [ADR-0002 Wrap-World Is Cylindrical](05_adrs/0002-wrap-world-is-cylindrical.md)
- [ADR-0003 Immutable Base + Runtime Diff](05_adrs/0003-immutable-base-plus-runtime-diff.md)
- [ADR-0004 Host-Authoritative Multiplayer](05_adrs/0004-host-authoritative-multiplayer.md)
- [ADR-0005 Light Is a Gameplay-Support System](05_adrs/0005-light-is-gameplay-system.md)
- [ADR-0006 Surface and Subsurface Are Separate but Linked](05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md)
- [ADR-0007 Environment Runtime Is Layered and Distinct from Worldgen](05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md)

### Templates
- [ADR Template](06_templates/template_adr.md)
- [Content Entry Template](06_templates/template_content_entry.md)
- [Iteration Brief Template](06_templates/template_iteration_brief.md)
- [System Spec Template](06_templates/template_system_spec.md)

## Recommended entrypoints by topic

### "How should we work in this repository?"
- [Workflow](00_governance/WORKFLOW.md)
- [Engineering Standards](00_governance/ENGINEERING_STANDARDS.md)
- [Project Glossary](00_governance/PROJECT_GLOSSARY.md)

### "How do survival and base systems fit together?"
- [Survival Core](02_system_specs/survival/survival_core.md)
- [Engineering Networks](02_system_specs/base/engineering_networks.md)
- [Building and Rooms](02_system_specs/base/building_and_rooms.md)
- [Automation and Logistics](02_system_specs/base/automation_and_logistics.md)

### "What is the non-negotiable player experience?"
- [Non-Negotiable Experience](01_product/NON_NEGOTIABLE_EXPERIENCE.md)
- [Game Vision GDD](01_product/GAME_VISION_GDD.md)

### "What are the current runtime and performance rules?"
- [Engineering Standards](00_governance/ENGINEERING_STANDARDS.md)
- [Project Glossary](00_governance/PROJECT_GLOSSARY.md)
- [ADR-0001 Runtime Work and Dirty Update Foundation](05_adrs/0001-runtime-work-and-dirty-update-foundation.md)

### "How does persistence work?"
- [Save and Persistence](02_system_specs/meta/save_and_persistence.md)
- [ADR-0003 Immutable Base + Runtime Diff](05_adrs/0003-immutable-base-plus-runtime-diff.md)

### "How should multiplayer authority and replication work?"
- [Multiplayer Authority and Replication](02_system_specs/meta/multiplayer_authority_and_replication.md)
- [ADR-0004 Host-Authoritative Multiplayer](05_adrs/0004-host-authoritative-multiplayer.md)

### "How should modding, registries, and extension contracts work?"
- [Modding Extension Contracts](02_system_specs/meta/modding_extension_contracts.md)
- [Localization Pipeline](02_system_specs/meta/localization_pipeline.md)

### "What is locked lore truth?"
- [Canon](03_content_bible/lore/canon.md)

### "Where did the old world/runtime docs go?"
- [World Grid Rebuild Foundation](02_system_specs/world/world_grid_rebuild_foundation.md)
- [World Runtime V0](02_system_specs/world/world_runtime.md)
- [ADR-0001 Runtime Work and Dirty Update Foundation](05_adrs/0001-runtime-work-and-dirty-update-foundation.md)
- [ADR-0002 Wrap-World Is Cylindrical](05_adrs/0002-wrap-world-is-cylindrical.md)
- [ADR-0003 Immutable Base + Runtime Diff](05_adrs/0003-immutable-base-plus-runtime-diff.md)
- [ADR-0005 Light Is a Gameplay-Support System](05_adrs/0005-light-is-gameplay-system.md)
- [ADR-0006 Surface and Subsurface Are Separate but Linked](05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md)
- [ADR-0007 Environment Runtime Is Layered and Distinct from Worldgen](05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md)

## Migration rule

Until new world-spec or execution-doc sets are reintroduced:
- prefer the `docs/` entry document for navigation
- prefer living docs and ADRs over historical filenames removed from the repo
- do not recreate deleted files just to satisfy old references; update links and
  wording to the current canonical set instead
