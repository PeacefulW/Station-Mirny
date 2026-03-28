---
title: System Inventory
doc_type: governance
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-03-28
depends_on:
  - WORKFLOW.md
  - PUBLIC_API.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
related_docs:
  - WORKFLOW.md
  - PUBLIC_API.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
---

# System Inventory — Полный список систем проекта

> Этот файл — справочный. Он перечисляет ВСЕ системы проекта
> и объясняет, почему каждая включена или не включена в `DATA_CONTRACTS.md` / `PUBLIC_API.md`.

| # | System | Main files | Classification | Owns gameplay state? | In DATA_CONTRACTS? | In PUBLIC_API? | Reason if excluded |
|---|--------|-----------|----------------|---------------------|--------------------|----------------|-------------------|
| 1 | World generation / chunk streaming / mining / topology / reveal / wall presentation | `core/autoloads/world_generator.gd`<br>`core/systems/world/chunk_manager.gd`<br>`core/systems/world/chunk.gd`<br>`core/systems/world/mountain_roof_system.gd`<br>`core/systems/lighting/mountain_shadow_system.gd` | canonical | yes | yes (existing) | yes (existing) | — |
| 2 | Z-level switching / stairs | `core/systems/world/z_level_manager.gd`<br>`core/entities/structures/z_stairs.gd` | canonical | yes | yes (added) | yes (added) | — |
| 3 | Time / calendar / day-night | `core/autoloads/time_manager.gd`<br>`core/systems/daylight/daylight_system.gd` | canonical | yes | yes (added) | yes (added) | — |
| 4 | Save / load orchestration | `core/autoloads/save_manager.gd`<br>`core/autoloads/save_collectors.gd`<br>`core/autoloads/save_appliers.gd`<br>`core/autoloads/save_io.gd` | canonical | yes | yes (added) | yes (added) | — |
| 5 | Settings / app config | `core/autoloads/settings_manager.gd` | canonical | no | no | no | App-level settings, not gameplay/session/save state contract in this pass |
| 6 | Input mapping / bootstrap | `core/autoloads/game_manager.gd` | canonical | no | no | no | Input/bootstrap glue, not standalone gameplay truth layer |
| 7 | Player authority lookup | `core/autoloads/player_authority.gd` | derived | no | no | no | Cache/service only; no owned gameplay state |
| 8 | Global event bus | `core/autoloads/event_bus.gd` | derived | no | no | no | Transport layer, no owned gameplay state |
| 9 | Localization | `core/autoloads/localization_service.gd` | presentation-only | no | no | no | Presentation/service layer, no gameplay state |
| 10 | Runtime frame-budget scheduling | `core/autoloads/frame_budget_dispatcher.gd`<br>`core/runtime/runtime_budget_job.gd`<br>`core/runtime/runtime_dirty_queue.gd`<br>`core/runtime/runtime_work_types.gd` | derived | no | no | no | Infrastructure only |
| 11 | Performance monitoring / probe | `core/autoloads/world_perf_monitor.gd`<br>`core/systems/world/world_perf_probe.gd` | derived | no | no | no | Debug/perf infrastructure only |
| 12 | GameWorld boot / orchestration | `scenes/world/game_world.gd` | canonical | yes | no | no | Root scene glue/orchestration; not documented as отдельный domain contract in this pass |
| 13 | Spawn / pickup orchestration | `scenes/world/spawn_orchestrator.gd` | canonical | yes | yes (added) | yes (added) | — |
| 14 | Building placement / building runtime | `core/systems/building/building_system.gd`<br>`core/systems/building/building_placement_service.gd` | canonical | yes | yes (added) | yes (added) | — |
| 15 | Indoor room topology | `core/systems/building/building_indoor_solver.gd`<br>`core/systems/building/building_system.gd` | derived | yes | yes (added) | yes (added) | — |
| 16 | Building persistence helper | `core/systems/building/building_persistence.gd` | derived | no | no | no | Helper only; no owned gameplay state |
| 17 | Power network | `core/systems/power/power_system.gd`<br>`core/entities/components/power_source_component.gd`<br>`core/entities/components/power_consumer_component.gd` | canonical | yes | yes (added) | yes (added) | — |
| 18 | Base life support | `core/systems/survival/base_life_support.gd` | canonical | yes | yes (added) | yes (added) | — |
| 19 | Oxygen / survival | `core/systems/survival/oxygen_system.gd` | canonical | yes | yes (added) | yes (added) | — |
| 20 | Player actor / movement / combat / harvest | `core/entities/player/player.gd`<br>`core/entities/player/states/*.gd` | canonical | yes | yes (added) | yes (added) | — |
| 21 | Player camera / popup visuals | `core/entities/player/player_camera.gd`<br>`core/entities/player/player_popup.gd` | presentation-only | no | no | no | Presentation only |
| 22 | Inventory runtime | `core/entities/components/inventory_component.gd`<br>`core/entities/items/inventory_slot.gd` | canonical | yes | yes (added) | yes (added) | — |
| 23 | Equipment runtime | `core/entities/components/equipment_component.gd`<br>`core/entities/items/equipment_slot.gd` | canonical | yes | yes (added) | yes (added) | — |
| 24 | Health / damage | `core/entities/components/health_component.gd` | canonical | yes | yes (added) | yes (added) | — |
| 25 | Crafting service | `core/systems/crafting/crafting_system.gd`<br>`core/systems/commands/craft_recipe_command.gd` | derived | no | no | yes (added) | Mutates inventory but does not own canonical state |
| 26 | Command layer | `core/systems/commands/command_executor.gd`<br>`core/systems/commands/game_command.gd`<br>`core/systems/commands/*.gd` | derived | no | no | yes (added) | Orchestration envelope only; no owned gameplay state |
| 27 | Enemy AI / fauna runtime | `core/entities/fauna/basic_enemy.gd`<br>`core/entities/fauna/states/*.gd` | canonical | yes | yes (added) | yes (added) | — |
| 28 | Noise / hearing input | `core/entities/components/noise_component.gd` | canonical | yes | yes (added) | yes (added) | — |
| 29 | Generic state machine framework | `core/systems/state_machine/state_machine.gd`<br>`core/systems/state_machine/entity_state.gd` | derived | no | no | no | Framework/infrastructure only |
| 30 | Session / game stats | `core/systems/game_stats.gd` | derived | no | no | no | Session metrics only; does not drive gameplay behavior |
| 31 | Item / building / resource registry | `core/autoloads/item_registry.gd`<br>`core/entities/items/item_data.gd`<br>`data/buildings/building_data.gd`<br>`core/entities/resources/resource_node_data.gd` | canonical | no | no | yes (added, read-only) | Immutable content registry after boot; not mutable runtime gameplay state |
| 32 | Recipe content | `core/entities/recipes/recipe_data.gd`<br>`data/recipes/**/*.tres` | canonical | no | no | no | Immutable content resource; accessed through `ItemRegistry` |
| 33 | Biome registry / content | `core/autoloads/biome_registry.gd`<br>`data/biomes/biome_data.gd` | canonical | no | no | yes (added, read-only) | Immutable content registry after boot; not mutable runtime gameplay state |
| 34 | Flora / decor registry and content | `core/autoloads/flora_decor_registry.gd`<br>`data/flora/flora_set_data.gd`<br>`data/decor/decor_set_data.gd` | canonical | no | no | yes (added, read-only) | Immutable content registry after boot; not mutable runtime gameplay state |
| 35 | Balance / config resources | `data/balance/*.gd`<br>`data/world/world_gen_balance.gd` | canonical | no | no | no | Immutable config data, not runtime gameplay state layer |
| 36 | UI: build menu | `scenes/ui/build_menu.gd`<br>`scenes/ui/build/build_menu_panel.gd`<br>`scenes/ui/build/*.gd` | presentation-only | no | no | no | Presentation only |
| 37 | UI: inventory | `scenes/ui/inventory_ui.gd`<br>`scenes/ui/inventory/*.gd` | presentation-only | no | no | no | Presentation only; runtime inventory contract documented in `InventoryComponent` layer instead |
| 38 | UI: crafting | `scenes/ui/crafting_panel.gd`<br>`scenes/ui/crafting/*.gd` | presentation-only | no | no | no | Presentation only |
| 39 | UI: HUD / power readouts | `scenes/ui/hud/*.gd`<br>`scenes/ui/power_ui.gd` | presentation-only | no | no | no | Presentation only |
| 40 | UI: save/load / pause / loading / death / main menu / world creation | `scenes/ui/save_load_tab.gd`<br>`scenes/ui/pause_menu.gd`<br>`scenes/ui/loading_screen.gd`<br>`scenes/ui/death_screen.gd`<br>`scenes/ui/main_menu.gd`<br>`scenes/ui/world_creation_screen.gd` | presentation-only | no | no | no | Presentation only; save orchestration documented in `SaveManager` layer instead |
| 41 | Debug / dev tooling | `scenes/world/game_world_debug.gd`<br>`core/debug/runtime_validation_driver.gd`<br>`core/debug/world_preview_exporter.gd` | derived | no | no | no | Debug-only, not production gameplay contract |
| 42 | Temperature worldgen channel | `core/systems/world/planet_sampler.gd`<br>`core/systems/world/world_channels.gd`<br>`core/systems/world/tile_gen_data.gd` | derived | no | no | no | Not a standalone runtime system; already part of world-generation stack |
