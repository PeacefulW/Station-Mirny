class_name GameEventBus
extends Node

## Глобальная шина событий. Все межсистемные коммуникации
## проходят через сигналы этого синглтона.

# --- Игрок ---
@warning_ignore("unused_signal")
signal player_health_changed(new_value: float, max_value: float)
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal player_entered_indoor()
@warning_ignore("unused_signal")
signal player_exited_indoor()

# --- Выживание ---
@warning_ignore("unused_signal")
signal oxygen_changed(current: float, maximum: float)
@warning_ignore("unused_signal")
signal oxygen_depleting(remaining_percent: float)

# --- Время суток ---
@warning_ignore("unused_signal")
signal time_tick(current_hour: float, day_progress: float)
@warning_ignore("unused_signal")
signal hour_changed(hour: int)
@warning_ignore("unused_signal")
signal time_of_day_changed(new_phase: int, old_phase: int)
@warning_ignore("unused_signal")
signal day_changed(day_number: int)
@warning_ignore("unused_signal")
signal season_changed(new_season: int, old_season: int)

# --- Электричество ---
@warning_ignore("unused_signal")
signal power_changed(total_supply: float, total_demand: float)
@warning_ignore("unused_signal")
signal power_deficit(deficit_amount: float)
@warning_ignore("unused_signal")
signal power_restored()
@warning_ignore("unused_signal")
signal life_support_power_changed(is_powered: bool)

# --- Строительство ---
@warning_ignore("unused_signal")
signal building_placed(position: Vector2i)
@warning_ignore("unused_signal")
signal building_removed(position: Vector2i)
@warning_ignore("unused_signal")
signal build_mode_changed(is_active: bool)
@warning_ignore("unused_signal")
signal rooms_recalculated(indoor_cells: Dictionary)

# --- Ресурсы ---
@warning_ignore("unused_signal")
signal scrap_collected(total_amount: int)
@warning_ignore("unused_signal")
signal scrap_spent(amount: int, remaining: int)

# --- Фауна ---
@warning_ignore("unused_signal")
signal enemy_spawned(enemy_node: Node2D)
@warning_ignore("unused_signal")
signal enemy_killed(position: Vector2)
@warning_ignore("unused_signal")
signal enemy_reached_wall(wall_position: Vector2i)
@warning_ignore("unused_signal")
signal noise_source_changed(noise_source: Node)

# --- Генерация мира ---
@warning_ignore("unused_signal")
signal world_initialized(seed_value: int)
@warning_ignore("unused_signal")
signal chunk_loaded(chunk_coord: Vector2i)
@warning_ignore("unused_signal")
signal chunk_unloaded(chunk_coord: Vector2i)
@warning_ignore("unused_signal")
signal mountain_revealed(mountain_id: int)
@warning_ignore("unused_signal")
signal mountain_concealed(mountain_id: int)
@warning_ignore("unused_signal")
signal resource_node_depleted(tile_pos: Vector2i, deposit_type: int)
@warning_ignore("unused_signal")
signal biome_entered(biome_id: StringName)
@warning_ignore("unused_signal")
signal mountain_tile_mined(tile_pos: Vector2i, old_type: int, new_type: int)

# --- Инвентарь и Предметы ---
## Вызывается, когда инвентарь (игрока или сундука) изменился.
@warning_ignore("unused_signal")
signal inventory_updated(inventory_node: Node)
## Вызывается, когда игрок скрафтил предмет.
@warning_ignore("unused_signal")
signal item_crafted(item_id: String, amount: int)
## Вызывается, когда игрок успешно подобрал предмет с земли.
@warning_ignore("unused_signal")
signal item_collected(item_id: String, amount: int)
## Вызывается, когда игрок выбросил предмет из инвентаря.
@warning_ignore("unused_signal")
signal item_dropped(item_id: String, amount: int, world_pos: Vector2)

# --- Сохранение / загрузка ---
## SaveManager начал сбор данных.
@warning_ignore("unused_signal")
signal save_requested()
## Сохранение завершено успешно.
@warning_ignore("unused_signal")
signal save_completed()
## Загрузка завершена, все системы восстановлены.
@warning_ignore("unused_signal")
signal load_completed()

@warning_ignore("unused_signal")
signal language_changed(locale_code: String)

# --- Z-уровни ---
@warning_ignore("unused_signal")
signal z_level_changed(new_z: int, old_z: int)

# --- Общее ---
@warning_ignore("unused_signal")
signal game_over()
