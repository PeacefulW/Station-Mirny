---
title: Documentation Migration Plan
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
related_docs:
  - ../README.md
  - AI_PLAYBOOK.md
  - DOCUMENT_PRECEDENCE.md
---

# Documentation Migration Plan

This file turns the high-level documentation architecture proposal into a practical transition plan for the current repository.

## Current state audit

### Real conflicts already present
- `README.md` used to present the project as a Phase 0 prototype, and has now been reduced to an entrypoint rather than a competing source
- the root previously contained multiple legacy markdown sources that could confuse contributors if not explicitly classified

## Migration strategy

### Stage 1: create canonical navigation
Completed:
- `docs/` index
- governance layer
- precedence
- migration map
- canonical entry files for product, system specs, content and execution

### Stage 2: canonicalize by reference, not by destructive move
Completed as policy:
- keep root documents in place
- create canonical `docs/` files that explicitly point to the current detailed sources
- avoid mass rename/move until links, habits and priorities are stable

Outcome:
- the project has now completed the first safe destructive cleanup wave after canonical docs were established

### Stage 3: migrate detailed content by domain
Current progress:
1. governance — completed at canonical layer
2. product bible — completed for high-level vision
3. lore canon — completed for high-level locked truth and open questions
4. execution layer — completed for master roadmap
5. system specs — substantially migrated for current legacy root content
6. content/resource split — substantially migrated
7. ADRs — not started meaningfully yet

### Stage 4: archive superseded root files
Only after a migrated area has:
- a canonical `docs/` home
- explicit precedence
- stable backlinks
- no unresolved contradictions

Current status:
- migrated legacy root docs have been removed
- the remaining root markdown is now intentionally minimal (`README.md` entrypoint only)

## What is already migrated

### Governance
- [AI_PLAYBOOK.md](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\AI_PLAYBOOK.md)
- [ENGINEERING_STANDARDS.md](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\ENGINEERING_STANDARDS.md)
- [PERFORMANCE_CONTRACTS.md](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)

### Product
- [GAME_VISION_GDD.md](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)

### System specs
- [world_generation_foundation.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)
- [engineering_networks.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\engineering_networks.md)
- [resource_progression.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\resource_progression.md)
- [survival_core.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\survival\survival_core.md)
- [building_and_rooms.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\building_and_rooms.md)
- [automation_and_logistics.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\automation_and_logistics.md)
- [fauna_and_threats.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\fauna_and_threats.md)
- [base_defense_and_noise.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\base_defense_and_noise.md)
- [character_progression.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\character_progression.md)
- [crafting_and_decryption.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\crafting_and_decryption.md)
- [transport_and_outposts.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\transport_and_outposts.md)
- [events_and_precursor_complexes.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\events_and_precursor_complexes.md)
- [ui_ux_foundation.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\ui\ui_ux_foundation.md)
- [save_and_persistence.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\save_and_persistence.md)
- [multiplayer_and_modding.md](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_and_modding.md)

### Content bible
- [canon.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\canon.md)
- [open_questions.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\lore\open_questions.md)
- [flora_and_resources.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\resources\flora_and_resources.md)
- [catalog.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\fauna\catalog.md)
- [art_direction.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\art_direction.md)
- [audio_direction.md](M:\dev\Station Peaceful\Station Peaceful\docs\03_content_bible\aesthetics\audio_direction.md)

### Execution
- [MASTER_ROADMAP.md](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\MASTER_ROADMAP.md)
- [world_generation_rollout.md](M:\dev\Station Peaceful\Station Peaceful\docs\04_execution\world_generation_rollout.md)

## Immediate targets

### Current next targets

1. Add first real ADRs in `docs/05_adrs/` for decisions already treated as foundational:
   - wrap world topology
   - room-vs-wall engineering distribution
   - dirty queue + budget as runtime law

2. Add missing targeted specs only if new subsystems appear or current docs prove insufficient:
   - mountains / terrain specific visual spec
   - weather / seasons specific runtime spec

## Important non-goals of this pass
- no broad content rewrite
- no automatic archival of legacy docs
- no attempt to settle every lore ambiguity immediately

## Known cleanup items

The old `_v1_2_` spelling should no longer be introduced in new docs or code comments.

Also note:
- future ADRs should capture the most important architecture decisions that were previously scattered across the deleted root docs
