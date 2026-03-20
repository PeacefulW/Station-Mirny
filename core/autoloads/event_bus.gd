class_name GameEventBus
extends Node

## Глобальная шина событий. Все межсистемные коммуникации
## проходят через сигналы этого синглтона.

# --- Игрок ---
signal player_health_changed(new_value: float, max_value: float)
signal player_died()
signal player_entered_indoor()
signal player_exited_indoor()

# --- Выживание ---
signal oxygen_changed(current: float, maximum: float)
signal oxygen_depleting(remaining_percent: float)

# --- Время суток ---
signal time_tick(current_hour: float, day_progress: float)
signal hour_changed(hour: int)
signal time_of_day_changed(new_phase: int, old_phase: int)
signal day_changed(day_number: int)
signal season_changed(new_season: int, old_season: int)

# --- Электричество ---
signal power_changed(total_supply: float, total_demand: float)
signal power_deficit(deficit_amount: float)
signal power_restored()
signal life_support_power_changed(is_powered: bool)

# --- Строительство ---
signal building_placed(position: Vector2i)
signal building_removed(position: Vector2i)
signal build_mode_changed(is_active: bool)
signal rooms_recalculated(indoor_cells: Dictionary)

# --- Ресурсы ---
signal scrap_collected(total_amount: int)
signal scrap_spent(amount: int, remaining: int)

# --- Фауна ---
signal enemy_spawned(enemy_node: Node2D)
signal enemy_killed(position: Vector2)
signal enemy_reached_wall(wall_position: Vector2i)

# --- Генерация мира ---
signal world_seed_set(seed_value: int)
signal chunk_loaded(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)
signal resource_node_depleted(tile_pos: Vector2i, deposit_type: int)
signal poi_discovered(poi_type: StringName, world_pos: Vector2)
signal biome_entered(biome_id: StringName)

# --- Инвентарь и Предметы ---
## Вызывается, когда инвентарь (игрока или сундука) изменился.
signal inventory_updated(inventory_node: Node)
## Вызывается, когда игрок успешно подобрал предмет с земли.
signal item_collected(item_id: String, amount: int)

# --- Сохранение / загрузка ---
## SaveManager начал сбор данных.
signal save_requested()
## Сохранение завершено успешно.
signal save_completed()
## Загрузка завершена, все системы восстановлены.
signal load_completed()

signal language_changed(locale_code: String)
# --- Общее ---
signal game_over()
