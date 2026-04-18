---
title: Commands
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-18
related_docs:
  - ../README.md
  - system_api.md
  - event_contracts.md
  - packet_schemas.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
---

# Commands

## Purpose

This document lists the current command objects that are confirmed in code.

## Scope

This pass covers all current `GameCommand` subclasses present in
`core/systems/commands/`.

## Current Execution Model

### Base contract: `GameCommand`

Owner file: `core/systems/commands/game_command.gd`

Confirmed base method:

```text
execute() -> Dictionary
```

Base fallback result:

```text
{
  "success": false,
  "message_key": "SYSTEM_COMMAND_NOT_IMPLEMENTED",
}
```

### Executor: `CommandExecutor`

Owner file: `core/systems/commands/command_executor.gd`

Confirmed entrypoint:

```text
execute(command: GameCommand) -> Dictionary
```

Normalization confirmed in code:
- missing `success` becomes `false`
- missing `message_key` becomes `""`
- missing `message_args` becomes `{}`

### Current Preferred Mutation Path

Current code in `BuildingSystem` prefers:

```text
CommandExecutor.execute(GameCommand)
```

when a node in group `command_executor` exists.

If no executor is found, `BuildingSystem` currently falls back to direct calls
to `place_selected_building_at()` / `remove_building_at()`.

## Confirmed Commands

### `PlaceBuildingCommand`

Owner file: `core/systems/commands/place_building_command.gd`

Setup:

```text
setup(building_system: BuildingSystem, world_pos: Vector2) -> PlaceBuildingCommand
```

Execute target:
- `BuildingSystem.place_selected_building_at(world_pos)`

Success result keys:
- `success`
- `message_key`
- `message_args.building`
- `grid_pos`
- `building_id`

Confirmed failure message keys:
- `SYSTEM_BUILDING_SYSTEM_UNAVAILABLE`
- `SYSTEM_BUILD_NOT_SELECTED`
- `SYSTEM_BUILD_CANNOT_PLACE`
- `SYSTEM_PLAYER_NOT_FOUND`
- `SYSTEM_BUILD_NOT_ENOUGH_SCRAP`
- `SYSTEM_BUILD_CREATE_FAILED`

Confirmed side effects:
- spends scrap through `Player.spend_scrap()`
- emits `EventBus.scrap_spent`
- marks room regions dirty
- emits `EventBus.building_placed`

### `RemoveBuildingCommand`

Owner file: `core/systems/commands/remove_building_command.gd`

Setup:

```text
setup(building_system: BuildingSystem, world_pos: Vector2) -> RemoveBuildingCommand
```

Execute target:
- `BuildingSystem.remove_building_at(world_pos)`

Success result keys:
- `success`
- `message_key`
- `message_args.amount`
- `grid_pos`
- `refund_amount`

Confirmed failure message keys:
- `SYSTEM_BUILDING_SYSTEM_UNAVAILABLE`
- `SYSTEM_BUILD_NOT_FOUND`

Confirmed side effects:
- removes the building through `BuildingPlacementService.remove_at()`
- refunds scrap through `Player.collect_scrap()`
- marks room regions dirty
- emits `EventBus.building_removed`

### `PickupItemCommand`

Owner file: `core/systems/commands/pickup_item_command.gd`

Setup:

```text
setup(player: Player, item_id: String, amount: int, pickup_node: Node = null) -> PickupItemCommand
```

Execute target:
- `Player.collect_item(item_id, amount)`

Success result keys:
- `success`
- `message_key`
- `message_args.amount`
- `collected_amount`

Confirmed failure message keys:
- `SYSTEM_PLAYER_NOT_FOUND`
- `SYSTEM_PICKUP_INVALID`
- `SYSTEM_INVENTORY_FULL`

Confirmed side effects:
- successful collection triggers `EventBus.item_collected` inside `Player.collect_item()`
- valid `pickup_node` is freed with `queue_free()`

### `CraftRecipeCommand`

Owner file: `core/systems/commands/craft_recipe_command.gd`

Setup:

```text
setup(crafting_system: CraftingSystem, inventory: InventoryComponent, recipe: RecipeData) -> CraftRecipeCommand
```

Execute target:
- `CraftingSystem.execute_recipe(recipe, inventory)`

Success result keys:
- `success`
- `message_key`
- `message_args.item`
- `message_args.amount`

Confirmed failure message keys:
- `SYSTEM_CRAFT_UNAVAILABLE`
- `SYSTEM_CRAFT_RECIPE_OR_INVENTORY_MISSING`
- `SYSTEM_CRAFT_ITEMS_NOT_FOUND`
- `SYSTEM_CRAFT_NOT_ENOUGH_RESOURCES`
- `SYSTEM_CRAFT_INPUT_REMOVE_FAILED`
- `SYSTEM_CRAFT_NOT_ENOUGH_SPACE`

Confirmed side effects:
- removes recipe inputs from inventory
- adds recipe outputs to inventory
- emits `EventBus.item_crafted` once per output entry

## Not Currently Confirmed

No additional `GameCommand` subclasses are currently present in
`core/systems/commands/`.

