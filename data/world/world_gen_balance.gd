class_name WorldGenBalance
extends Resource

## Параметры генерации мира.
## Для текущего этапа используются земля и горные массивы.

@export_group("Чанки")
@export var chunk_size_tiles: int = 64
@export var tile_size: int = 64
@export var load_radius: int = 2
@export var unload_radius: int = 4
@export_range(1, 8) var chunk_loads_per_frame: int = 1
@export_range(4, 64) var chunk_redraw_rows_per_frame: int = 8
@export_range(16, 1024) var chunk_redraw_tiles_per_step: int = 64

@export_group("Рельеф")
@export var height_frequency: float = 0.01
@export var height_octaves: int = 4
@export_range(0.05, 0.50) var mountain_density: float = 0.22
@export_range(1, 3) var mountain_area: int = 2
@export_range(0.0, 1.0) var mountain_chaininess: float = 0.45

@export_group("Шум гор")
@export var mountain_blob_frequency: float = 0.012
@export var mountain_chain_frequency: float = 0.016
@export var mountain_detail_frequency: float = 0.035

@export_group("Гора")
@export var rock_drop_item_id: StringName = &"base:stone"
@export_range(1, 10) var rock_drop_amount: int = 1
@export var rock_color: Color = Color(0.30, 0.26, 0.33)
@export var rock_shadow_color: Color = Color(0.17, 0.14, 0.20, 0.75)
@export var rock_top_color: Color = Color(0.55, 0.47, 0.63, 0.85)
@export var roof_color: Color = Color(0.24, 0.21, 0.28, 1.0)
@export var mountain_interior_fill_color: Color = Color(0.02, 0.02, 0.03, 0.96)
@export var mined_floor_color: Color = Color(0.37, 0.32, 0.26)
@export var entrance_color: Color = Color(0.42, 0.36, 0.29)
@export_range(1, 12) var mountain_visibility_radius: int = 6
@export_range(0.5, 16.0) var mountain_topology_build_budget_ms: float = 2.0
@export_range(16, 4096) var mountain_topology_scan_tiles_per_step: int = 64
@export_range(16, 4096) var mountain_topology_finalize_tiles_per_step: int = 64
@export var use_native_mountain_topology: bool = false
@export var mountain_debug_visualization: bool = false
@export var mountain_debug_collision_color: Color = Color(1.0, 0.12, 0.12, 0.85)
@export var mountain_debug_entrance_color: Color = Color(0.15, 0.95, 0.35, 0.75)
@export var mountain_debug_mined_color: Color = Color(0.15, 0.65, 1.0, 0.55)

@export_group("Тени гор")
@export_range(0.1, 0.8) var shadow_intensity: float = 0.45
@export_range(1, 12) var shadow_max_length: int = 8
@export_range(1, 5) var shadow_mountain_height: int = 3
@export var shadow_color: Color = Color(0.0, 0.0, 0.05)
@export_range(0.02, 0.2) var shadow_angle_threshold: float = 0.08
@export_range(16, 4096) var mountain_shadow_edge_cache_tiles_per_step: int = 128
@export_range(1, 64) var mountain_shadow_edges_per_step: int = 4

@export_group("Стартовая зона")
@export var safe_zone_radius: int = 12
@export var land_guarantee_radius: int = 24

func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size
