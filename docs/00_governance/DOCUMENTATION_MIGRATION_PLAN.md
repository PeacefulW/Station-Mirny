---
title: Documentation Migration Plan
doc_type: governance
status: approved
owner: design+engineering
source_of_truth: true
version: 1.2
last_updated: 2026-03-26
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
1. governance — completed (includes AI Playbook, Engineering Standards, Performance Contracts, Document Precedence, Simulation and Threading Model, Project Glossary, Legacy Root Doc Audit)
2. product bible — completed (Game Vision GDD, Non-Negotiable Experience)
3. lore canon — completed (canon, open questions)
4. execution layer — completed (Master Roadmap, World Generation Rollout, Mountain Roof System Refactor Plan)
5. system specs — in progress; 21 baseline specs completed; additional 21 world-layer specs added (boot pipeline, streaming, chunk visual, native generation, hydrology, etc.) bringing world/ total to 28 files
6. content/resource split — completed (flora/resources, fauna catalog, art direction, audio direction)
7. ADRs — ADR-0001 (Runtime Work and Dirty Update Foundation) approved at v1.1; recommended ADRs for grid/camera, room engineering, wrap-world, z-levels still pending

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
- [AI_PLAYBOOK.md](AI_PLAYBOOK.md)
- [ENGINEERING_STANDARDS.md](ENGINEERING_STANDARDS.md)
- [PERFORMANCE_CONTRACTS.md](PERFORMANCE_CONTRACTS.md)
- [DOCUMENT_PRECEDENCE.md](DOCUMENT_PRECEDENCE.md)
- [SIMULATION_AND_THREADING_MODEL.md](SIMULATION_AND_THREADING_MODEL.md)
- [PROJECT_GLOSSARY.md](PROJECT_GLOSSARY.md)
- [LEGACY_ROOT_DOC_AUDIT.md](LEGACY_ROOT_DOC_AUDIT.md)

### Product
- [GAME_VISION_GDD.md](../01_product/GAME_VISION_GDD.md)
- [NON_NEGOTIABLE_EXPERIENCE.md](../01_product/NON_NEGOTIABLE_EXPERIENCE.md)

### System specs
- [world_generation_foundation.md](../02_system_specs/world/world_generation_foundation.md)
- [environment_runtime_foundation.md](../02_system_specs/world/environment_runtime_foundation.md)
- [lighting_visibility_and_darkness.md](../02_system_specs/world/lighting_visibility_and_darkness.md)
- [subsurface_and_verticality_foundation.md](../02_system_specs/world/subsurface_and_verticality_foundation.md)
- [engineering_networks.md](../02_system_specs/base/engineering_networks.md)
- [resource_progression.md](../02_system_specs/progression/resource_progression.md)
- [survival_core.md](../02_system_specs/survival/survival_core.md)
- [building_and_rooms.md](../02_system_specs/base/building_and_rooms.md)
- [automation_and_logistics.md](../02_system_specs/base/automation_and_logistics.md)
- [fauna_and_threats.md](../02_system_specs/combat/fauna_and_threats.md)
- [base_defense_and_noise.md](../02_system_specs/combat/base_defense_and_noise.md)
- [character_progression.md](../02_system_specs/progression/character_progression.md)
- [crafting_and_decryption.md](../02_system_specs/progression/crafting_and_decryption.md)
- [transport_and_outposts.md](../02_system_specs/world/transport_and_outposts.md)
- [events_and_precursor_complexes.md](../02_system_specs/world/events_and_precursor_complexes.md)
- [ui_ux_foundation.md](../02_system_specs/ui/ui_ux_foundation.md)
- [save_and_persistence.md](../02_system_specs/meta/save_and_persistence.md)
- [multiplayer_and_modding.md](../02_system_specs/meta/multiplayer_and_modding.md)
- [multiplayer_authority_and_replication.md](../02_system_specs/meta/multiplayer_authority_and_replication.md)
- [modding_extension_contracts.md](../02_system_specs/meta/modding_extension_contracts.md)
- [localization_pipeline.md](../02_system_specs/meta/localization_pipeline.md)

### Content bible
- [canon.md](../03_content_bible/lore/canon.md)
- [open_questions.md](../03_content_bible/lore/open_questions.md)
- [flora_and_resources.md](../03_content_bible/resources/flora_and_resources.md)
- [catalog.md](../03_content_bible/fauna/catalog.md)
- [art_direction.md](../03_content_bible/aesthetics/art_direction.md)
- [audio_direction.md](../03_content_bible/aesthetics/audio_direction.md)

### Execution
- [MASTER_ROADMAP.md](../04_execution/MASTER_ROADMAP.md)
- [world_generation_rollout.md](../04_execution/world_generation_rollout.md)
- [mountain_roof_system_refactor_plan.md](../04_execution/mountain_roof_system_refactor_plan.md)

### ADRs
- [ADR-0001 Runtime Work and Dirty Update Foundation](../05_adrs/0001-runtime-work-and-dirty-update-foundation.md)

## Immediate targets

### Current next targets

1. Add remaining recommended ADRs in `docs/05_adrs/`:
   - square grid + oblique camera
   - room-based engineering strategy
   - wrap-world strategy
   - 3 z-level model
   (Note: dirty queue + budget as runtime law is now covered by ADR-0001)

2. Add missing targeted specs only if new subsystems appear or current docs prove insufficient:
   - mountains / terrain specific visual spec
   - weather / seasons specific runtime spec

3. Populate `PROJECT_GLOSSARY.md` with key project terms currently used across docs without formal definition

## Important non-goals of this pass
- no broad content rewrite
- no automatic archival of legacy docs
- no attempt to settle every lore ambiguity immediately

## Known cleanup items

The old `_v1_2_` spelling should no longer be introduced in new docs or code comments.

Also note:
- future ADRs should capture the most important architecture decisions that were previously scattered across the deleted root docs
