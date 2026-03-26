---
title: Station Mirny Documentation Index
doc_type: docs_index
status: approved
owner: design+engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
related_docs:
  - 00_governance/DOCUMENT_PRECEDENCE.md
  - 00_governance/DOCUMENTATION_MIGRATION_PLAN.md
---

# Documentation Index

This folder is the new structured entrypoint for project documentation.

Current policy:
- new canonical navigation lives under `docs/`
- legacy source documents in project root remain in place during migration
- do not treat root markdown files as equal peers anymore; use the map below

## Layers

### `00_governance/`
Rules, standards, performance contracts, precedence, AI operating rules.

### `01_product/`
High-level vision, fantasy, pillars, product framing.

### `02_system_specs/`
System contracts and architecture by subsystem.

### `03_content_bible/`
Lore, canon, open questions, flora/fauna/resources catalogs.

### `04_execution/`
Roadmaps, iteration briefs, rollout plans.

### `05_adrs/`
Architecture Decision Records.

### `06_templates/`
Templates for future docs.

### `99_archive/`
Deprecated or migrated legacy versions.

## Current canonical map

### Governance
- [AI Playbook](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\AI_PLAYBOOK.md)
- [Engineering Standards](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\ENGINEERING_STANDARDS.md)
- [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)
- [Simulation and Threading Model](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\SIMULATION_AND_THREADING_MODEL.md)
- [Document Precedence](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENT_PRECEDENCE.md)
- [Documentation Migration Plan](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENTATION_MIGRATION_PLAN.md)

### Product
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)
- [Non-Negotiable Experience](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\NON_NEGOTIABLE_EXPERIENCE.md)

### System Specs
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)
- [Environment Runtime Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\environment_runtime_foundation.md)
- [Lighting, Visibility, and Darkness](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\lighting_visibility_and_darkness.md)
- [Subsurface and Verticality Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\subsurface_and_verticality_foundation.md)
- [Engineering Networks](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\engineering_networks.md)
- [Resource Progression](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\resource_progression.md)
- [Survival Core](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\survival\survival_core.md)
- [Building and Rooms](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\building_and_rooms.md)
- [Automation and Logistics](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\automation_and_logistics.md)
- [Fauna and Threat Gameplay](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\fauna_and_threats.md)
- [Base Defense and Noise](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\base_defense_and_noise.md)
- [Character Progression](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\character_progression.md)
- [Crafting and Decryption](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\crafting_and_decryption.md)
- [Transport and Outposts](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\transport_and_outposts.md)
- [Events and Precursor Complexes](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\events_and_precursor_complexes.md)
- [UI and UX Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\ui\ui_ux_foundation.md)
- [Save and Persistence](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\save_and_persistence.md)
- [Multiplayer and Modding Constraints](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_and_modding.md)
- [Multiplayer Authority and Replication](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_authority_and_replication.md)
- [Modding Extension Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\modding_extension_contracts.md)
- [Localization Pipeline](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\localization_pipeline.md)

### Content Bible
- [Canon](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\canon.md)
- [Open Questions](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\open_questions.md)
- [Flora and Resources](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\resources\flora_and_resources.md)
- [Fauna Catalog](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\fauna\catalog.md)
- [Art Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\art_direction.md)
- [Audio Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\audio_direction.md)

### Execution
- [Master Roadmap](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\MASTER_ROADMAP.md)
- [World Generation Rollout](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\world_generation_rollout.md)
- [Mountain Roof System Refactor Plan](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\mountain_roof_system_refactor_plan.md)

## Recommended entrypoints by topic

### "How should we build the world?"
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)
- [Environment Runtime Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\environment_runtime_foundation.md)

### "How do survival and base systems fit together?"
- [Survival Core](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\survival\survival_core.md)
- [Engineering Networks](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\engineering_networks.md)
- [Building and Rooms](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\building_and_rooms.md)

### "What is the non-negotiable player experience?"
- [Non-Negotiable Experience](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\NON_NEGOTIABLE_EXPERIENCE.md)
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)

### "In what order should world generation be implemented?"
- [World Generation Rollout](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\world_generation_rollout.md)

### "How should the current mountain roof system be refactored?"
- [Mountain Roof System Refactor Plan](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\mountain_roof_system_refactor_plan.md)

### "What is the game trying to feel like?"
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)
- [Non-Negotiable Experience](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\NON_NEGOTIABLE_EXPERIENCE.md)

### "What is locked lore truth?"
- [Canon](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\canon.md)

### "How should environment, weather, seasons, and wind behave at runtime?"
- [Environment Runtime Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\environment_runtime_foundation.md)

### "How should darkness, light, visibility, and underground readability work?"
- [Lighting, Visibility, and Darkness](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\lighting_visibility_and_darkness.md)

### "How should underground space, mining, and vertical traversal work?"
- [Subsurface and Verticality Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\subsurface_and_verticality_foundation.md)

### "What are the creatures / art / tone supposed to be?"
- [Fauna Catalog](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\fauna\catalog.md)
- [Art Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\art_direction.md)
- [Audio Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\audio_direction.md)

### "What are the runtime rules?"
- [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)
- [Simulation and Threading Model](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\SIMULATION_AND_THREADING_MODEL.md)

### "How should multiplayer authority and replication work?"
- [Multiplayer Authority and Replication](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_authority_and_replication.md)

### "How should modding, registries, and extension contracts work?"
- [Modding Extension Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\modding_extension_contracts.md)

### "How should localization workflow and translation pipeline work?"
- [Localization Pipeline](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\localization_pipeline.md)

## Migration rule

Until full migration is done:
- prefer the `docs/` entry document for navigation
- if a `docs/` file says that detailed truth still lives in a legacy root file, follow that pointer
- when updating a migrated area, update the `docs/` canonical file first and only then decide whether the legacy root file must also be patched or archived
