---
title: Event Contracts
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-18
related_docs:
  - ../README.md
  - system_api.md
  - commands.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
---

# Event Contracts

## Purpose

This document lists a minimal set of domain events with code-confirmed emitters,
payloads, and listeners.

## Scope

This pass is intentionally narrow.

It includes only events where the current code confirms:

- the signal declaration
- at least one emitter
- at least one listener

The full raw signal list still lives in `core/autoloads/event_bus.gd`.

## Reading Rules

- Every contract below is backed by current code.
- If an `EventBus` signal is not listed here, it was not confirmed in this
  minimal pass.
- Payload fields are listed exactly as declared by the signal signature.

## Confirmed Event Contracts

### `time_tick(current_hour: float, day_progress: float)`

Emitter:
- `TimeManager._advance_time()`
- `TimeManager._emit_initial_state()`

When it fires:
- every runtime time-advance tick after time is advanced
- once when authoritative time state is emitted on initialization / restore

Confirmed listeners:
- `DaylightSystem._on_time_tick()`

Current listener use:
- smooth daylight color transitions within dawn and dusk ranges

### `time_of_day_changed(new_phase: int, old_phase: int)`

Emitter:
- `TimeManager._on_hour_changed()` when the phase changes
- `TimeManager._emit_initial_state()`

When it fires:
- on dawn/day/dusk/night boundary transitions
- once during initial state emission

Confirmed listeners:
- `DaylightSystem._on_time_of_day_changed()`
- `BasicEnemy._on_time_changed()`

Current listener use:
- updates daylight target color
- changes enemy hearing multiplier by phase

### `day_changed(day_number: int)`

Emitter:
- `TimeManager._on_new_day()`
- `TimeManager._emit_initial_state()`

When it fires:
- after day rollover
- once during initial state emission

Confirmed listeners:
- `GameStats._on_day_changed()`

Current listener use:
- updates `days_survived`

### `life_support_power_changed(is_powered: bool)`

Emitter:
- `BaseLifeSupport._on_powered_changed()`
- `BaseLifeSupport._emit_state()`

When it fires:
- when the life-support power consumer changes powered state
- once on life-support initialization

Confirmed listeners:
- `OxygenSystem._on_life_support_power_changed()`

Current listener use:
- updates whether indoor oxygen should refill or drain

### `building_placed(position: Vector2i)`

Emitter:
- `BuildingSystem.place_selected_building_at()`

When it fires:
- after successful placement, after scrap spend, and after the room-dirty mark

Confirmed listeners:
- `GameStats._on_building_placed()`

Current listener use:
- increments `buildings_placed`

### `rooms_recalculated(indoor_cells: Dictionary)`

Emitter:
- `BuildingSystem.load_state()`
- `BuildingSystem._room_recompute_tick()`
- `BuildingSystem._advance_full_room_rebuild()`

When it fires:
- after load-time rebuild
- after a successful local indoor patch
- after staged full-room rebuild completion

Confirmed listeners:
- `OxygenSystem._on_rooms_recalculated()`

Current listener use:
- refreshes whether the owner is currently indoors

### `item_crafted(item_id: String, amount: int)`

Emitter:
- `CraftingSystem.execute_recipe()`

When it fires:
- once per output entry after a successful craft result

Confirmed listeners:
- `GameStats._on_item_crafted()`

Current listener use:
- increments `items_crafted` by crafted amount

### `item_collected(item_id: String, amount: int)`

Emitter:
- `Player.collect_item()`

When it fires:
- after inventory add succeeds for a positive collected amount

Confirmed listeners:
- `GameStats._on_item_collected()`

Current listener use:
- increments `resources_gathered` by collected amount

## Not Included In This Minimal Pass

The following signals exist in `EventBus` but are not documented here yet
because this pass did not confirm both an emitter and a listener:

- `save_requested`
- `save_completed`
- `load_completed`
- `power_changed`
- `power_deficit`
- `power_restored`
- `building_removed`

