class_name WorldGenBalance
extends Resource

@export_group("Chunks")
@export var chunk_size_tiles: int = 64
@export var tile_size: int = 64
@export var load_radius: int = 2
@export var unload_radius: int = 4
@export_range(1, 8) var chunk_loads_per_frame: int = 1
@export_range(4, 64) var chunk_redraw_rows_per_frame: int = 8
@export_range(16, 1024) var chunk_redraw_tiles_per_step: int = 64

@export_group("Chunk Visual Scheduler")
@export_range(0.5, 16.0) var visual_scheduler_budget_ms: float = 4.0
@export_range(16, 4096) var visual_first_pass_tiles_per_step: int = 64
@export_range(16, 4096) var visual_full_redraw_tiles_per_step: int = 64
@export_range(16, 4096) var visual_border_fix_tiles_per_step: int = 64
@export_range(16, 4096) var visual_cosmetic_tiles_per_step: int = 32
@export_range(1, 8) var visual_first_pass_max_tasks_per_tick: int = 8
@export_range(1, 16) var visual_full_redraw_max_tasks_per_tick: int = 8

@export_group("Quality Zones")
@export_range(0, 8) var startup_bubble_chunk_radius: int = 1
@export_range(0, 8) var near_visible_chunk_radius: int = 1
@export_range(0, 16) var mid_visible_chunk_radius: int = 2
@export_range(0, 32) var far_visible_chunk_radius: int = 4

@export_group("World Topology")
@export_range(256, 262144) var world_wrap_width_tiles: int = 4096
@export_range(256, 262144) var latitude_half_span_tiles: int = 4096
@export var equator_tile_y: int = 0

@export_group("World Pre-pass")
@export_range(8, 512) var prepass_grid_step: int = 32

@export_group("Lakes")
@export_range(3, 100) var prepass_lake_min_area: int = 8
@export_range(0.01, 0.3) var prepass_lake_min_depth: float = 0.04
@export_range(0.0, 0.5) var prepass_frozen_lake_temperature: float = 0.15

@export_group("Latitude Hydrology")
@export_range(0.0, 0.5) var prepass_glacial_melt_temperature: float = 0.22
@export_range(0.0, 5.0) var prepass_glacial_melt_bonus: float = 2.5
@export_range(0.0, 0.3) var prepass_latitude_evaporation_rate: float = 0.08
@export_range(0.0, 0.3) var prepass_frozen_river_threshold: float = 0.18

@export_group("Rivers")
@export_range(50, 5000) var prepass_river_accumulation_threshold: int = 200
@export_range(1.0, 20.0) var prepass_river_base_width: float = 2.0
@export_range(1.0, 20.0) var prepass_river_width_scale: float = 6.0
@export_range(1.5, 8.0) var prepass_floodplain_multiplier: float = 3.0

@export_group("Ridge Skeleton")
@export_range(2, 12) var prepass_target_spine_count: int = 4
@export_range(20, 200) var prepass_min_spine_distance_grid: int = 80
@export_range(50, 500) var prepass_max_ridge_length_grid: int = 200
@export_range(10, 200) var prepass_max_branch_length_grid: int = 60
@export_range(0.0, 0.5) var prepass_branch_probability: float = 0.15
@export_range(0.1, 0.7) var prepass_ridge_min_height: float = 0.35
@export_range(0.3, 1.0) var prepass_ridge_continuation_inertia: float = 0.65

@export_group("Erosion Proxy")
@export_range(0.0, 0.5) var prepass_erosion_valley_strength: float = 0.12
@export_range(1, 10) var prepass_thermal_iterations: int = 3
@export_range(0.0, 0.3) var prepass_thermal_rate: float = 0.08
@export_range(0.0, 0.5) var prepass_deposit_rate: float = 0.15

@export_group("Rain Shadow")
@export var prepass_prevailing_wind_direction: Vector2 = Vector2(1.0, 0.0)
@export_range(0.0, 0.5) var prepass_precipitation_rate: float = 0.12
@export_range(0.5, 8.0) var prepass_orographic_lift_factor: float = 3.0
@export_range(0.0, 0.2) var prepass_evaporation_rate: float = 0.02

@export_group("Continentalness")
@export_range(0.0, 0.5) var prepass_sea_level_threshold: float = 0.15

@export_group("Cold Pole")
@export_range(0.0, 0.4) var cold_pole_temperature: float = 0.20
@export_range(0.05, 0.3) var cold_pole_transition_width: float = 0.12
@export_range(0.0, 0.3) var ice_cap_height_bonus: float = 0.10
@export_range(0.0, 0.8) var ice_cap_max_height: float = 0.55

@export_group("Hot Pole")
@export_range(0.6, 1.0) var hot_pole_temperature: float = 0.82
@export_range(0.05, 0.3) var hot_pole_transition_width: float = 0.15

@export_group("World Channels")
@export var height_frequency: float = 0.01
@export var height_octaves: int = 4
@export var temperature_frequency: float = 0.0035
@export_range(1, 8) var temperature_octaves: int = 3
@export_range(0.0, 0.5) var temperature_noise_amplitude: float = 0.18
@export_range(0.0, 1.0) var temperature_latitude_weight: float = 0.72
@export_range(0.5, 4.0) var latitude_temperature_curve: float = 1.35
@export var moisture_frequency: float = 0.0055
@export_range(1, 8) var moisture_octaves: int = 3
@export var ruggedness_frequency: float = 0.014
@export_range(1, 8) var ruggedness_octaves: int = 3
@export var flora_density_frequency: float = 0.020
@export_range(1, 8) var flora_density_octaves: int = 2

@export_group("Biome Causal Scoring")
@export_range(0.0, 1.0, 0.01) var biome_continental_drying_factor: float = 0.35
@export_range(0.0, 1.0, 0.01) var biome_drainage_moisture_bonus: float = 0.28

@export_group("Local Variation")
@export var local_variation_frequency: float = 0.018
@export_range(1, 8) var local_variation_octaves: int = 2
@export_range(0.0, 1.0, 0.01) var local_variation_min_score: float = 0.22

@export_group("Mountains")
@export_range(0.05, 0.50) var mountain_density: float = 0.30
@export_range(1, 3) var mountain_area: int = 2
@export_range(0.0, 1.0) var mountain_chaininess: float = 0.60

@export_group("Mountain Presentation")
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
@export var use_native_chunk_generation: bool = false
@export var mountain_debug_visualization: bool = false
@export var mountain_debug_collision_color: Color = Color(1.0, 0.12, 0.12, 0.85)
@export var mountain_debug_entrance_color: Color = Color(0.15, 0.95, 0.35, 0.75)
@export var mountain_debug_mined_color: Color = Color(0.15, 0.65, 1.0, 0.55)

@export_group("Mountain Shadows")
@export_range(0.1, 0.8) var shadow_intensity: float = 0.60
@export_range(1, 12) var shadow_max_length: int = 8
@export_range(1, 5) var shadow_mountain_height: int = 4
@export var shadow_color: Color = Color(0.01, 0.01, 0.06)
@export_range(0.02, 0.35) var shadow_angle_threshold: float = 0.20
@export_range(16, 4096) var mountain_shadow_edge_cache_tiles_per_step: int = 128
@export_range(1, 64) var mountain_shadow_edges_per_step: int = 8

@export_group("Terrain Classification")
@export_range(0.0, 1.0, 0.01) var river_min_strength: float = 0.34
@export_range(0.0, 1.0, 0.01) var river_ridge_exclusion: float = 0.70
@export_range(0.0, 1.0, 0.01) var river_max_height: float = 0.78
@export_range(0.0, 1.0, 0.01) var bank_min_floodplain: float = 0.28
@export_range(0.0, 1.0, 0.01) var bank_ridge_exclusion: float = 0.64
@export_range(0.0, 1.0, 0.01) var bank_min_river: float = 0.14
@export_range(0.0, 1.0, 0.01) var bank_min_moisture: float = 0.50
@export_range(0.0, 1.0, 0.01) var bank_max_height: float = 0.64
@export_range(0.0, 1.0, 0.01) var mountain_base_threshold: float = 0.68
@export_range(0.0, 1.0, 0.01) var mountain_threshold_min: float = 0.28
@export_range(0.0, 1.0, 0.01) var mountain_threshold_max: float = 0.74

@export_group("Start Zone")
@export var safe_zone_radius: int = 12
@export var land_guarantee_radius: int = 24

func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size

