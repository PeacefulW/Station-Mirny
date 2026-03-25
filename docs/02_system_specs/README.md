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
- [Engineering Networks](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\engineering_networks.md)
- [Building and Rooms](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\building_and_rooms.md)
- [Automation and Logistics](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\base\automation_and_logistics.md)

### Combat / Threat
- [Fauna and Threat Gameplay](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\fauna_and_threats.md)
- [Base Defense and Noise](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\combat\base_defense_and_noise.md)

### Progression
- [Resource Progression](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\resource_progression.md)
- [Character Progression](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\character_progression.md)
- [Crafting and Decryption](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\progression\crafting_and_decryption.md)

### Survival
- [Survival Core](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\survival\survival_core.md)

### UI
- [UI and UX Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\ui\ui_ux_foundation.md)

### World
- [World Generation Foundation](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\world_generation_foundation.md)
- [Transport and Outposts](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\transport_and_outposts.md)
- [Events and Precursor Complexes](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\world\events_and_precursor_complexes.md)

### Meta constraints
- [Multiplayer and Modding Constraints](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\multiplayer_and_modding.md)
- [Save and Persistence](M:\dev\Station Peaceful\Station Peaceful\docs\02_system_specs\meta\save_and_persistence.md)
