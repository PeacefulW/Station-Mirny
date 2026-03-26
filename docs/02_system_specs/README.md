---
title: System Specs Index
doc_type: system_spec_index
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
---

# System Specs

This layer owns runtime/system contracts.

Each serious system should eventually define:
1. purpose
2. gameplay goal
3. scope
4. out of scope
5. dependencies
6. data model
7. runtime architecture
8. event contracts
9. save contracts
10. performance class
11. extension points
12. acceptance criteria
13. risks
14. open questions
15. implementation iterations

Current transition strategy:
- create canonical homes under `docs/02_system_specs/`
- point them to existing detailed source files until each spec is fully migrated

## Current canonical specs

### Base
- [Engineering Networks](base/engineering_networks.md)
- [Building and Rooms](base/building_and_rooms.md)
- [Automation and Logistics](base/automation_and_logistics.md)

### Combat / Threat
- [Fauna and Threat Gameplay](combat/fauna_and_threats.md)
- [Base Defense and Noise](combat/base_defense_and_noise.md)

### Progression
- [Resource Progression](progression/resource_progression.md)
- [Character Progression](progression/character_progression.md)
- [Crafting and Decryption](progression/crafting_and_decryption.md)

### Survival
- [Survival Core](survival/survival_core.md)

### UI
- [UI and UX Foundation](ui/ui_ux_foundation.md)

### World
- [World Generation Foundation](world/world_generation_foundation.md)
- [Environment Runtime Foundation](world/environment_runtime_foundation.md)
- [Lighting, Visibility, and Darkness](world/lighting_visibility_and_darkness.md)
- [Subsurface and Verticality Foundation](world/subsurface_and_verticality_foundation.md)
- [Transport and Outposts](world/transport_and_outposts.md)
- [Events and Precursor Complexes](world/events_and_precursor_complexes.md)

### Meta constraints
- [Multiplayer and Modding Constraints](meta/multiplayer_and_modding.md)
- [Multiplayer Authority and Replication](meta/multiplayer_authority_and_replication.md)
- [Modding Extension Contracts](meta/modding_extension_contracts.md)
- [Localization Pipeline](meta/localization_pipeline.md)
- [Save and Persistence](meta/save_and_persistence.md)
