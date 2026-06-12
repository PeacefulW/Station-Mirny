class_name GrassAtlasPainter
extends RefCounted
## Процедурный генератор атласа пучков травы (authoring-инструмент).
## Единственный источник рисунка пучков: dev-сцена и экспорт в PNG используют
## его; рантайм потребляет только экспортированный PNG-ассет.
## Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const ATLAS_COLUMNS: int = 4
## Ряды 0-3 — сухая степная палитра (кадры 0-15); ряды 4-7 — палитра
## оранжевого биополя (кадры 16-31). Native выбирает банк по orange_region.
const ATLAS_ROWS: int = 8
const ATLAS_FRAME_COUNT: int = ATLAS_COLUMNS * ATLAS_ROWS
const DRY_FRAME_COUNT: int = 16
const BIOFIELD_FRAME_BASE: int = 16
const FRAME_SIZE: Vector2i = Vector2i(72, 104)
const DEFAULT_ATLAS_SEED: int = 612917 + 451


static func build_atlas_image(atlas_seed: int = DEFAULT_ATLAS_SEED) -> Image:
	var atlas_size := Vector2i(FRAME_SIZE.x * ATLAS_COLUMNS, FRAME_SIZE.y * ATLAS_ROWS)
	var image := Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var atlas_rng := RandomNumberGenerator.new()
	atlas_rng.seed = atlas_seed
	for frame_index: int in range(ATLAS_FRAME_COUNT):
		var frame_origin := Vector2i(
			(frame_index % ATLAS_COLUMNS) * FRAME_SIZE.x,
			(frame_index / ATLAS_COLUMNS) * FRAME_SIZE.y,
		)
		var is_biofield: bool = frame_index >= BIOFIELD_FRAME_BASE
		_paint_grass_frame(image, frame_origin, atlas_rng, frame_index, is_biofield)
	return image


static func _paint_grass_frame(
		image: Image,
		origin: Vector2i,
		atlas_rng: RandomNumberGenerator,
		frame_index: int,
		is_biofield: bool,
) -> void:
	var blade_count: int = atlas_rng.randi_range(11, 22)
	if is_biofield:
		blade_count += 4
	for i: int in range(blade_count):
		var root := Vector2(
			float(origin.x) + FRAME_SIZE.x * atlas_rng.randf_range(0.18, 0.82),
			float(origin.y) + FRAME_SIZE.y * atlas_rng.randf_range(0.80, 0.98),
		)
		var lean := atlas_rng.randf_range(-22.0, 22.0) + sin(float(frame_index) * 1.7 + float(i)) * 6.0
		var tip := Vector2(
			root.x + lean,
			float(origin.y) + FRAME_SIZE.y * atlas_rng.randf_range(0.04, 0.46),
		)
		var mid := root.lerp(tip, atlas_rng.randf_range(0.42, 0.64)) \
				+ Vector2(atlas_rng.randf_range(-8.0, 8.0), atlas_rng.randf_range(-4.0, 4.0))
		var width := atlas_rng.randf_range(2.0, 4.8)
		var hue := atlas_rng.randf_range(-0.020, 0.018)
		var color: Color
		if is_biofield:
			# Биополе: насыщенный красно-оранжевый, чуть плотнее и контрастнее.
			color = Color.from_hsv(
				0.047 + hue,
				atlas_rng.randf_range(0.86, 1.00),
				atlas_rng.randf_range(0.68, 1.00),
				atlas_rng.randf_range(0.76, 0.98),
			)
			if i % 5 == 0:
				color = Color.from_hsv(0.035 + hue, 0.95, 0.42, 0.74)
		else:
			color = Color.from_hsv(
				0.075 + hue,
				atlas_rng.randf_range(0.76, 0.96),
				atlas_rng.randf_range(0.72, 1.00),
				atlas_rng.randf_range(0.72, 0.96),
			)
			if i % 5 == 0:
				color = Color.from_hsv(0.060 + hue, 0.90, 0.52, 0.72)
		_paint_blade_segment(image, root, mid, width, color)
		_paint_blade_segment(image, mid, tip, width * 0.62, color.lightened(0.08))


static func _paint_blade_segment(
		image: Image,
		start: Vector2,
		finish: Vector2,
		width: float,
		color: Color,
) -> void:
	var min_x: int = clampi(floori(minf(start.x, finish.x) - width - 2.0), 0, image.get_width() - 1)
	var max_x: int = clampi(ceili(maxf(start.x, finish.x) + width + 2.0), 0, image.get_width() - 1)
	var min_y: int = clampi(floori(minf(start.y, finish.y) - width - 2.0), 0, image.get_height() - 1)
	var max_y: int = clampi(ceili(maxf(start.y, finish.y) + width + 2.0), 0, image.get_height() - 1)
	var segment := finish - start
	var segment_len_sq := maxf(segment.length_squared(), 0.0001)
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var t := clampf((p - start).dot(segment) / segment_len_sq, 0.0, 1.0)
			var closest := start + segment * t
			var radius := width * (1.0 - t) * (0.34 + 0.66 * sin(t * PI))
			var dist := p.distance_to(closest)
			var alpha := 1.0 - smoothstep(maxf(0.15, radius - 0.80), radius + 0.95, dist)
			if alpha <= 0.001:
				continue
			_blend_pixel(image, x, y, Color(color.r, color.g, color.b, color.a * alpha))


static func _blend_pixel(image: Image, x: int, y: int, src: Color) -> void:
	var dst := image.get_pixel(x, y)
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0001:
		return
	var out_rgb := (
		Vector3(src.r, src.g, src.b) * src.a
		+ Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)
	) / out_a
	image.set_pixel(x, y, Color(out_rgb.x, out_rgb.y, out_rgb.z, out_a))
