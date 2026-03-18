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
## Каждый кадр: текущий час (float) и прогресс дня (0.0–1.0).
signal time_tick(current_hour: float, day_progress: float)
## Целый час изменился (0–23).
signal hour_changed(hour: int)
## Фаза дня изменилась (DAWN, DAY, DUSK, NIGHT).
signal time_of_day_changed(new_phase: int, old_phase: int)
## Наступил новый игровой день.
signal day_changed(day_number: int)
## Сменился сезон.
signal season_changed(new_season: int, old_season: int)

# --- Электричество ---
## Энергобаланс изменился.
signal power_changed(total_supply: float, total_demand: float)
## Дефицит энергии — потребители отключаются.
signal power_deficit(deficit_amount: float)
## Энергия восстановлена после дефицита.
signal power_restored()

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

# --- Общее ---
signal game_over()
