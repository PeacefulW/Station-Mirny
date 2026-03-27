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

@export_group("World Topology")
@export_range(256, 262144) var world_wrap_width_tiles: int = 4096
@export_range(256, 262144) var latitude_half_span_tiles: int = 4096
@export var equator_tile_y: int = 0

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

@export_group("Large Structures")
@export_range(128, 8192) var ridge_spacing_tiles: int = 640
@export_range(8.0, 512.0, 1.0) var ridge_core_width_tiles: float = 104.0
@export_range(8.0, 512.0, 1.0) var ridge_feather_tiles: float = 224.0
@export var ridge_warp_frequency: float = 0.0018
@export_range(0.0, 1024.0, 1.0) var ridge_warp_amplitude_tiles: float = 260.0
@export var ridge_cluster_frequency: float = 0.00075
@export_range(128, 8192) var river_spacing_tiles: int = 480
@export_range(4.0, 128.0, 1.0) var river_core_width_tiles: float = 42.0
@export_range(8.0, 512.0, 1.0) var river_floodplain_width_tiles: float = 224.0
@export var river_warp_frequency: float = 0.0016
@export_range(0.0, 1024.0, 1.0) var river_warp_amplitude_tiles: float = 300.0

@export_group("Local Variation")
@export var local_variation_frequency: float = 0.018
@export_range(1, 8) var local_variation_octaves: int = 2
@export_range(0.0, 1.0, 0.01) var local_variation_min_score: float = 0.22

@export_group("Mountains")
@export_range(0.05, 0.50) var mountain_density: float = 0.30
@export_range(1, 3) var mountain_area: int = 2
@export_range(0.0, 1.0) var mountain_chaininess: float = 0.60

@export_group("Mountain Noise")
@export var mountain_blob_frequency: float = 0.012
@export var mountain_chain_frequency: float = 0.016
@export var mountain_detail_frequency: float = 0.035

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
@export_range(0.0, 1.0, 0.01) var river_min_strength: float = 0.40
@export_range(0.0, 1.0, 0.01) var river_ridge_exclusion: float = 0.70
@export_range(0.0, 1.0, 0.01) var river_max_height: float = 0.74
@export_range(0.0, 1.0, 0.01) var bank_min_floodplain: float = 0.32
@export_range(0.0, 1.0, 0.01) var bank_ridge_exclusion: float = 0.64
@export_range(0.0, 1.0, 0.01) var bank_min_river: float = 0.16
@export_range(0.0, 1.0, 0.01) var bank_min_moisture: float = 0.54
@export_range(0.0, 1.0, 0.01) var bank_max_height: float = 0.60
@export_range(0.0, 1.0, 0.01) var mountain_base_threshold: float = 0.74
@export_range(0.0, 1.0, 0.01) var mountain_threshold_min: float = 0.32
@export_range(0.0, 1.0, 0.01) var mountain_threshold_max: float = 0.78

@export_group("Start Zone")
@export var safe_zone_radius: int = 12
@export var land_guarantee_radius: int = 24

func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size
