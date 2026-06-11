extends SceneTree

# One-shot offline texture post-process: makes world ground material textures
# seamlessly tileable. These textures are sampled in world space with
# repeat_enable, so any mismatch between opposite PNG edges renders as a
# ruler-straight seam line every <texture_size / scale> world pixels.
#
# Method: blend the image with its half-size-offset copy near the borders.
# The offset copy is wrap-perfect at the borders (its border pixels are the
# original's interior); the original is kept untouched in the interior. The
# offset copy's own seam lands in the center, where its blend weight is zero.
# Deterministic; rerun after regenerating source textures in the generator.

const BLEND_BAND_PX: int = 128

const ALBEDO_PATHS: Array[String] = [
	"res://assets/textures/world/biomes/plains/ground/dirty.png",
	"res://assets/textures/world/biomes/plains/ground/dry_grass_transition_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_grass_sparse_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_grass_medium_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_grass_dense_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_ground_top_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_ground_face_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/dry_ground_top_modulation.png",
	"res://assets/textures/world/biomes/plains/ground/dry_ground_face_modulation.png",
	"res://assets/textures/world/biomes/plains/ground/orange_biofield_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/rock_top_albedo.png",
	"res://assets/textures/world/biomes/plains/ground/foothill_albedo.png",
]

const NORMAL_PATHS: Array[String] = [
	"res://assets/textures/world/biomes/plains/ground/dry_ground_top_normal.png",
	"res://assets/textures/world/biomes/plains/ground/dry_ground_face_normal.png",
	"res://assets/textures/world/biomes/plains/ground/orange_biofield_normal.png",
]

func _initialize() -> void:
	var failed: bool = false
	for path: String in ALBEDO_PATHS:
		if not _process_texture(path, false):
			failed = true
	for path: String in NORMAL_PATHS:
		if not _process_texture(path, true):
			failed = true
	quit(1 if failed else 0)

func _process_texture(path: String, is_normal_map: bool) -> bool:
	var global_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(global_path):
		print("make_textures_tileable: MISSING %s" % path)
		return false
	var img: Image = Image.load_from_file(global_path)
	if img == null or img.is_empty():
		print("make_textures_tileable: LOAD FAILED %s" % path)
		return false
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var width: int = img.get_width()
	var height: int = img.get_height()
	var band: int = mini(BLEND_BAND_PX, mini(width, height) / 4)
	var half_w: int = width / 2
	var half_h: int = height / 2
	var out: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y: int in range(height):
		var wy: float = _border_weight(y, height, band)
		for x: int in range(width):
			var weight: float = _border_weight(x, width, band) * wy
			var original: Color = img.get_pixel(x, y)
			if weight >= 1.0:
				out.set_pixel(x, y, original)
				continue
			var shifted: Color = img.get_pixel((x + half_w) % width, (y + half_h) % height)
			var blended: Color = shifted.lerp(original, weight)
			if is_normal_map:
				blended = _renormalize(blended)
			out.set_pixel(x, y, blended)
	var err: Error = out.save_png(global_path)
	if err != OK:
		print("make_textures_tileable: SAVE FAILED %s (%d)" % [path, err])
		return false
	var seam: Vector2 = _wrap_seam_metric(out)
	print("make_textures_tileable: OK %s %dx%d band=%d wrap_step_x=%.2f wrap_step_y=%.2f" % [
		path, width, height, band, seam.x, seam.y
	])
	return true

func _border_weight(coord: int, size: int, band: int) -> float:
	var distance: int = mini(coord, size - 1 - coord)
	var t: float = clampf(float(distance) / float(maxi(band, 1)), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _renormalize(color: Color) -> Color:
	var n: Vector3 = Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE
	if n.length_squared() < 0.0001:
		return Color(0.5, 0.5, 1.0, color.a)
	n = n.normalized() * 0.5 + Vector3(0.5, 0.5, 0.5)
	return Color(n.x, n.y, n.z, color.a)

func _wrap_seam_metric(img: Image) -> Vector2:
	var width: int = img.get_width()
	var height: int = img.get_height()
	var sum_x: float = 0.0
	var count_x: int = 0
	for y: int in range(0, height, 3):
		sum_x += absf(_luma(img.get_pixel(0, y)) - _luma(img.get_pixel(width - 1, y)))
		count_x += 1
	var sum_y: float = 0.0
	var count_y: int = 0
	for x: int in range(0, width, 3):
		sum_y += absf(_luma(img.get_pixel(x, 0)) - _luma(img.get_pixel(x, height - 1)))
		count_y += 1
	return Vector2(
		255.0 * sum_x / float(maxi(count_x, 1)),
		255.0 * sum_y / float(maxi(count_y, 1))
	)

func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114
