extends SceneTree

const WorldPrePassScript = preload("res://core/systems/world/world_pre_pass.gd")

class FakePlanetSampler extends PlanetSampler:
	var _height_by_pos: Dictionary = {}
	var _wrap_width_tiles: int = 192

	func setup(height_by_pos: Dictionary, wrap_width_tiles: int) -> FakePlanetSampler:
		_height_by_pos = height_by_pos.duplicate(true)
		_wrap_width_tiles = wrap_width_tiles
		return self

	func sample_height(world_pos: Vector2i) -> float:
		return float(_height_by_pos.get(world_pos, 1.0))

	func sample_world_channels(world_pos: Vector2i) -> WorldChannels:
		var channels := WorldChannels.new()
		channels.world_pos = world_pos
		channels.canonical_world_pos = world_pos
		channels.height = sample_height(world_pos)
		channels.temperature = 0.5
		channels.ruggedness = 0.2
		return channels

	func get_wrap_width_tiles() -> int:
		return _wrap_width_tiles

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var balance := WorldGenBalance.new()
	balance.prepass_grid_step = 32
	balance.world_wrap_width_tiles = 192
	balance.latitude_half_span_tiles = 96
	balance.equator_tile_y = 0
	balance.prepass_lake_min_area = 4
	balance.prepass_lake_min_depth = 0.05

	var heights: Dictionary = {}
	for grid_y: int in range(16):
		for grid_x: int in range(6):
			var world_pos := Vector2i(grid_x * 32, -256 + grid_y * 32)
			heights[world_pos] = 1.0

	for corridor_y: int in range(0, 7):
		heights[Vector2i(64, -256 + corridor_y * 32)] = 0.8

	heights[Vector2i(32, -32)] = 0.8
	heights[Vector2i(128, -32)] = 0.8
	heights[Vector2i(32, 0)] = 0.8
	heights[Vector2i(128, 0)] = 0.8
	heights[Vector2i(64, -32)] = 0.1
	heights[Vector2i(96, -32)] = 0.1
	heights[Vector2i(64, 0)] = 0.1
	heights[Vector2i(96, 0)] = 0.1

	var prepass = WorldPrePassScript.new().configure(balance, FakePlanetSampler.new().setup(heights, balance.world_wrap_width_tiles)).compute()
	var filled_height_grid: PackedFloat32Array = prepass._filled_height_grid
	var lake_mask: PackedByteArray = prepass._lake_mask
	var lake_records: Array = prepass._lake_records
	if not _assert(filled_height_grid.size() == 96, "filled height grid must keep full coarse-grid size"):
		return
	if not _assert(lake_mask.size() == filled_height_grid.size(), "lake mask must match filled height grid size"):
		return
	if not _assert(lake_records.size() == 1, "synthetic basin must produce exactly one lake"):
		return

	var basin_indices: Array[int] = [44, 45, 50, 51]
	for basin_index: int in basin_indices:
		if not _assert(absf(filled_height_grid[basin_index] - 0.8) <= 0.0001, "filled basin cells must rise to spill height 0.8"):
			return
		if not _assert(lake_mask[basin_index] == 1, "lake basin cells must be tagged with lake id 1"):
			return

	var first_record = lake_records[0]
	if not _assert(first_record != null, "lake record must be typed"):
		return
	if not _assert(first_record.area_grid_cells == 4, "lake area must match the four flooded center cells"):
		return
	if not _assert(absf(first_record.surface_height - 0.8) <= 0.0001, "lake record surface height must match spill height"):
		return
	if not _assert(absf(first_record.max_depth - 0.7) <= 0.0001, "lake record max depth must reflect the 0.8 -> 0.1 basin depth"):
		return
	if not _assert(first_record.lake_type == &"floodplain", "synthetic lowland basin must classify as floodplain under the fallback heuristics"):
		return

	print("[CodexWorldPrePassLakeValidation] OK lake_count=%d area=%d surface=%.3f" % [
		lake_records.size(),
		first_record.area_grid_cells,
		first_record.surface_height,
	])
	quit(0)

func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
