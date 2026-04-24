---
title: System Specs Index
doc_type: system_spec_index
status: approved
owner: engineering+design
source_of_truth: true
version: 1.6
last_updated: 2026-04-24
---

# System Specs

This layer owns subsystem contracts that are still versioned in the repository.

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
- keep canonical homes under `docs/02_system_specs/`
- keep this index aligned only with files that are actually present in the repo

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

### Meta constraints
- [Agent Skill Pack](meta/agent_skill_pack.md)
- [System API](meta/system_api.md)
- [Event Contracts](meta/event_contracts.md)
- [Packet Schemas](meta/packet_schemas.md)
- [Commands](meta/commands.md)
- [Multiplayer and Modding Constraints](meta/multiplayer_and_modding.md)
- [Multiplayer Authority and Replication](meta/multiplayer_authority_and_replication.md)
- [Modding Extension Contracts](meta/modding_extension_contracts.md)
- [Localization Pipeline](meta/localization_pipeline.md)
- [Save and Persistence](meta/save_and_persistence.md)

### World / Runtime foundation
- [World Grid Rebuild Foundation](world/world_grid_rebuild_foundation.md)
- [World Runtime V0](world/world_runtime.md)
- [World Foundation V1](world/world_foundation_v1.md)
- [Mountain Generation V1](world/mountain_generation.md)
- [Terrain Hybrid Presentation](world/terrain_hybrid_presentation.md)

The removed pre-rebuild world stack now rebuilds from this living world-grid contract
plus the approved ADR stack:
- [ADR-0001 Runtime Work and Dirty Update Foundation](../05_adrs/0001-runtime-work-and-dirty-update-foundation.md)
- [ADR-0002 Wrap-World Is Cylindrical](../05_adrs/0002-wrap-world-is-cylindrical.md)
- [ADR-0003 Immutable Base + Runtime Diff](../05_adrs/0003-immutable-base-plus-runtime-diff.md)
- [ADR-0005 Light Is a Gameplay-Support System](../05_adrs/0005-light-is-gameplay-system.md)
- [ADR-0006 Surface and Subsurface Are Separate but Linked](../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md)
- [ADR-0007 Environment Runtime Is Layered and Distinct from Worldgen](../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md)
