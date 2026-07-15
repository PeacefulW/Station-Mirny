extends SceneTree

const FRAME_SIZE: Vector2i = Vector2i(768, 768)
const TREE_COLUMNS: int = 5
const TREE_ROWS: int = 1
const ROCK_COLUMNS: int = 5
const ROCK_ROWS: int = 2

const TREE_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_trees/tree_01",
	"res://assets/sprites/flora/layered_trees/tree_02",
	"res://assets/sprites/flora/layered_trees/tree_03",
	"res://assets/sprites/flora/layered_trees/tree_04",
	"res://assets/sprites/flora/layered_trees/tree_05",
]
const TREE_CHANNELS: Array[String] = [
	"trunk",
	"foliage",
	"shadow",
	"snow_overlay",
	"wind_mask",
	"snow_mask",
	"season_mask",
]
const TREE_OUTPUT_DIR: String = "res://assets/sprites/flora/atlases/layered_trees"

const ROCK_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_02",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_03",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_04",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_05",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_06",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_07",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_08",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_09",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_10",
]
const ROCK_CHANNELS: Array[String] = [
	"albedo",
	"shadow",
	"snow_overlay",
	"snow_mask",
]
const ROCK_OUTPUT_DIR: String = "res://assets/sprites/decor/atlases/layered_small_rocks"


func _initialize() -> void:
	var tree_error: Error = _build_family_atlases(
		TREE_SOURCE_DIRS,
		TREE_CHANNELS,
		TREE_OUTPUT_DIR,
		TREE_COLUMNS,
		TREE_ROWS,
	)
	var rock_error: Error = _build_family_atlases(
		ROCK_SOURCE_DIRS,
		ROCK_CHANNELS,
		ROCK_OUTPUT_DIR,
		ROCK_COLUMNS,
		ROCK_ROWS,
	)
	if tree_error != OK or rock_error != OK:
		push_error("Layered object atlas build failed: tree=%d rock=%d" % [tree_error, rock_error])
		quit(1)
		return
	print("Layered object channel atlases rebuilt without resampling.")
	quit(0)


func _build_family_atlases(
		source_dirs: Array[String],
		channels: Array[String],
		output_dir: String,
		columns: int,
		rows: int,
) -> Error:
	if source_dirs.size() > columns * rows:
		return ERR_INVALID_PARAMETER
	var absolute_output_dir: String = ProjectSettings.globalize_path(output_dir)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_output_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	for channel: String in channels:
		var atlas := Image.create_empty(
			FRAME_SIZE.x * columns,
			FRAME_SIZE.y * rows,
			false,
			Image.FORMAT_RGBA8,
		)
		atlas.fill(Color.TRANSPARENT)
		for variant_index: int in range(source_dirs.size()):
			var source := Image.new()
			var source_path: String = "%s/%s.png" % [source_dirs[variant_index], channel]
			var load_error: Error = source.load(ProjectSettings.globalize_path(source_path))
			if load_error != OK:
				push_error("Cannot read %s (err %d)" % [source_path, load_error])
				return load_error
			if source.get_size() != FRAME_SIZE:
				push_error("Unexpected frame size in %s: %s" % [source_path, source.get_size()])
				return ERR_INVALID_DATA
			if source.get_format() != Image.FORMAT_RGBA8:
				source.convert(Image.FORMAT_RGBA8)
			var destination := Vector2i(
				(variant_index % columns) * FRAME_SIZE.x,
				(variant_index / columns) * FRAME_SIZE.y,
			)
			atlas.blit_rect(source, Rect2i(Vector2i.ZERO, FRAME_SIZE), destination)
		var output_path: String = "%s/%s.png" % [output_dir, channel]
		var save_error: Error = atlas.save_png(ProjectSettings.globalize_path(output_path))
		if save_error != OK:
			push_error("Cannot write %s (err %d)" % [output_path, save_error])
			return save_error
	return OK
