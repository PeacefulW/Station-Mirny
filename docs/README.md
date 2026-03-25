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
- [Document Precedence](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENT_PRECEDENCE.md)
- [Documentation Migration Plan](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\DOCUMENTATION_MIGRATION_PLAN.md)

### Product
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)

### System Specs
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)
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

## Recommended entrypoints by topic

### "How should we build the world?"
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)

### "How do survival and base systems fit together?"
- [Survival Core](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\survival\survival_core.md)
- [Engineering Networks](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\engineering_networks.md)
- [Building and Rooms](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\building_and_rooms.md)

### "In what order should world generation be implemented?"
- [World Generation Rollout](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\world_generation_rollout.md)

### "What is the game trying to feel like?"
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)

### "What is locked lore truth?"
- [Canon](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\canon.md)

### "What are the creatures / art / tone supposed to be?"
- [Fauna Catalog](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\fauna\catalog.md)
- [Art Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\art_direction.md)
- [Audio Direction](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\audio_direction.md)

### "What are the runtime rules?"
- [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)

## Migration rule

Until full migration is done:
- prefer the `docs/` entry document for navigation
- if a `docs/` file says that detailed truth still lives in a legacy root file, follow that pointer
- when updating a migrated area, update the `docs/` canonical file first and only then decide whether the legacy root file must also be patched or archived
