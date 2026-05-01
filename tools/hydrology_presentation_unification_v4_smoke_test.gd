extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HYDROLOGY_LAKE_ID_OFFSET: int = 1000000
const HYDROLOGY_OCEAN_ID: int = 2000000

const EXPECTED_OCEAN_DEEP := [30, 75, 111, 255]
const EXPECTED_OCEAN_SHELF := [52, 118, 145, 255]
const EXPECTED_LAKE_SHALLOW := [63, 139, 159, 255]
const EXPECTED_RIVER_DEEP := [28, 82, 124, 255]
const EXPECTED_RIVER_SHALLOW := [56, 133, 163, 255]
const EXPECTED_RIVER_BANK := [88, 119, 105, 255]
const EXPECTED_FLOODPLAIN_FAR := [51, 79, 54, 255]
const EXPECTED_FLOODPLAIN_NEAR := [54, 94, 60, 255]

const DEBUG_WINNER_COLORS := {
	"ocean_shelf": [48, 142, 178, 255],
	"lake_shallow": [54, 150, 190, 255],
	"river_deep": [18, 82, 176, 255],
	"river_shallow": [44, 126, 210, 255],
	"river_bank": [156, 170, 98, 255],
	"floodplain": [68, 142, 74, 255],
}

var _failed: bool = false

func _init() -> void:
	_assert(
		WorldRuntimeConstants.WORLD_VERSION >= WorldRuntimeConstants.WORLD_LAKE_BASIN_CONTINUITY_V4_VERSION,
		"current WORLD_VERSION must include the V4-5 boundary used by V4-6 presentation unification"
	)

	var core := WorldCore.new()
	var image: Image = core.make_world_preview_patch_image(_make_packet(), &"terrain")
	_assert(image != null and not image.is_empty(), "V4-6 preview smoke should get a native preview image")
	_assert(image.get_width() == WorldRuntimeConstants.CHUNK_SIZE, "V4-6 preview image should preserve chunk width")
	_assert(image.get_height() == WorldRuntimeConstants.CHUNK_SIZE, "V4-6 preview image should preserve chunk height")

	var ocean_deep := _pixel_rgba(image, 0, 0)
	var ocean_shelf := _pixel_rgba(image, 1, 0)
	var lake_shallow := _pixel_rgba(image, 2, 0)
	var river_deep := _pixel_rgba(image, 3, 0)
	var river_shallow := _pixel_rgba(image, 4, 0)
	var river_bank := _pixel_rgba(image, 5, 0)
	var floodplain_far := _pixel_rgba(image, 6, 0)
	var floodplain_near := _pixel_rgba(image, 7, 0)

	_assert(ocean_deep == EXPECTED_OCEAN_DEEP, "ocean deep should use the V4-6 gameplay water palette")
	_assert(ocean_shelf == EXPECTED_OCEAN_SHELF, "ocean shelf should use the V4-6 gameplay water palette")
	_assert(lake_shallow == EXPECTED_LAKE_SHALLOW, "lake shallow should use the V4-6 gameplay water palette")
	_assert(river_deep == EXPECTED_RIVER_DEEP, "river deep should use the V4-6 gameplay water palette")
	_assert(river_shallow == EXPECTED_RIVER_SHALLOW, "river shallow should use the V4-6 gameplay water palette")
	_assert(river_bank == EXPECTED_RIVER_BANK, "river bank should render as a wet rim/underlay color, not a dry brown center")
	_assert(floodplain_far == EXPECTED_FLOODPLAIN_FAR, "far floodplain should render as a weak strength gradient")
	_assert(floodplain_near == EXPECTED_FLOODPLAIN_NEAR, "near floodplain should render as a stronger strength gradient")
	_assert(floodplain_near != floodplain_far, "floodplain preview should be strength-gradient based, not a hard terrain stripe")

	for debug_color: Array in DEBUG_WINNER_COLORS.values():
		_assert(ocean_shelf != debug_color, "gameplay water palette should stay separate from debug winner colors")
		_assert(lake_shallow != debug_color, "gameplay lake palette should stay separate from debug winner colors")
		_assert(river_shallow != debug_color, "gameplay river palette should stay separate from debug winner colors")
		_assert(river_bank != debug_color, "gameplay bank palette should stay separate from debug winner colors")
		_assert(floodplain_near != debug_color, "gameplay floodplain palette should stay separate from debug winner colors")

	_assert_shape_set_color(
		"res://data/terrain/shape_sets/hydrology_ocean_floor_shape_set.tres",
		EXPECTED_OCEAN_SHELF,
		"runtime ocean floor tile should use the unified gameplay water palette"
	)
	_assert_shape_set_color(
		"res://data/terrain/shape_sets/hydrology_lakebed_shape_set.tres",
		EXPECTED_LAKE_SHALLOW,
		"runtime lakebed tile should use the unified gameplay water palette"
	)
	_assert_shape_set_color(
		"res://data/terrain/shape_sets/hydrology_riverbed_deep_shape_set.tres",
		EXPECTED_RIVER_DEEP,
		"runtime deep riverbed tile should use the unified gameplay water palette"
	)
	_assert_shape_set_color(
		"res://data/terrain/shape_sets/hydrology_riverbed_shallow_shape_set.tres",
		EXPECTED_RIVER_SHALLOW,
		"runtime shallow riverbed tile should use the unified gameplay water palette"
	)
	_assert_shape_set_color(
		"res://data/terrain/shape_sets/hydrology_shore_shape_set.tres",
		EXPECTED_RIVER_BANK,
		"runtime shore/bank tile should use the wet rim presentation color"
	)

	_finish()

func _make_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var hydrology_ids := PackedInt32Array()
	var hydrology_flags := PackedInt32Array()
	var floodplain_strength := PackedByteArray()
	var water_class := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	hydrology_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	hydrology_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	floodplain_strength.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	water_class.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		hydrology_ids[index] = 0
		hydrology_flags[index] = 0
		floodplain_strength[index] = 0
		water_class[index] = WorldRuntimeConstants.WATER_CLASS_NONE
		mountain_ids[index] = 0
		mountain_flags[index] = 0

	terrain_ids[0] = WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR
	hydrology_ids[0] = HYDROLOGY_OCEAN_ID
	water_class[0] = WorldRuntimeConstants.WATER_CLASS_OCEAN

	terrain_ids[1] = WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR
	hydrology_ids[1] = HYDROLOGY_OCEAN_ID
	water_class[1] = WorldRuntimeConstants.WATER_CLASS_SHALLOW

	terrain_ids[2] = WorldRuntimeConstants.TERRAIN_LAKEBED
	hydrology_ids[2] = HYDROLOGY_LAKE_ID_OFFSET + 7
	hydrology_flags[2] = WorldRuntimeConstants.HYDROLOGY_FLAG_LAKEBED
	water_class[2] = WorldRuntimeConstants.WATER_CLASS_SHALLOW

	terrain_ids[3] = WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP
	hydrology_ids[3] = 11
	hydrology_flags[3] = WorldRuntimeConstants.HYDROLOGY_FLAG_RIVERBED
	water_class[3] = WorldRuntimeConstants.WATER_CLASS_DEEP

	terrain_ids[4] = WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW
	hydrology_ids[4] = 11
	hydrology_flags[4] = WorldRuntimeConstants.HYDROLOGY_FLAG_RIVERBED
	water_class[4] = WorldRuntimeConstants.WATER_CLASS_SHALLOW

	terrain_ids[5] = WorldRuntimeConstants.TERRAIN_SHORE
	hydrology_ids[5] = 11
	hydrology_flags[5] = WorldRuntimeConstants.HYDROLOGY_FLAG_SHORE | WorldRuntimeConstants.HYDROLOGY_FLAG_BANK

	hydrology_flags[6] = WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN | WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN_FAR
	floodplain_strength[6] = 128

	hydrology_flags[7] = WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN | WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN_NEAR
	floodplain_strength[7] = 224

	return {
		"terrain_ids": terrain_ids,
		"hydrology_id_per_tile": hydrology_ids,
		"hydrology_flags": hydrology_flags,
		"floodplain_strength": floodplain_strength,
		"water_class": water_class,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
	}

func _pixel_rgba(image: Image, x: int, y: int) -> Array:
	var color: Color = image.get_pixel(x, y)
	return _color_to_rgba(color)

func _assert_shape_set_color(path: String, expected: Array, message: String) -> void:
	var shape_set: Resource = ResourceLoader.load(path)
	_assert(shape_set != null, "shape set should load: %s" % [path])
	if shape_set == null:
		return
	var texture: Texture2D = shape_set.get("mask_atlas") as Texture2D
	_assert(texture != null, "shape set should expose mask_atlas texture: %s" % [path])
	if texture == null:
		return
	var image: Image = texture.get_image()
	_assert(image != null and not image.is_empty(), "shape set mask_atlas should expose readable image: %s" % [path])
	if image == null or image.is_empty():
		return
	_assert(_color_to_rgba(image.get_pixel(0, 0)) == expected, message)

func _color_to_rgba(color: Color) -> Array:
	return [
		int(round(color.r * 255.0)),
		int(round(color.g * 255.0)),
		int(round(color.b * 255.0)),
		int(round(color.a * 255.0)),
	]

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hydrology_presentation_unification_v4_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
