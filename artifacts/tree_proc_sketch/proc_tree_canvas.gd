extends Node2D

# Эскиз-разведка процедурных деревьев: рекурсивный генератор веток (2D),
# тейпер + фейковый цилиндрический шейдинг, крона из кластеров листьев.
# Холст-контактка: ряды демонстрируют (1) вариацию по сиду и (2) управление
# слайдерами — gnarl, плотность кроны, палитра, наклон/размер.
# НЕ продакшен: это оценка характера процедурного пути.

const CANVAS_W: int = 1800
const CANVAS_H: int = 1240
const COLS: int = 6
const ROWS: int = 5
const LIGHT_DIR: Vector2 = Vector2(-0.7, -0.72)

var _trees: Array = []        # [{shadow, branches:[{pts,cols}], leaves:[{pts,col}]}]
var _row_labels: Array = []   # [{text, pos}]
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var cw: float = float(CANVAS_W) / float(COLS)
	var ch: float = float(CANVAS_H) / float(ROWS)

	var base: Dictionary = {
		"trunk_len": 70.0,
		"trunk_w": 21.0,
		"depth": 5,
		"gnarl": 0.5,
		"taper_along": 0.60,
		"split_angle": 0.62,
		"split_jitter": 0.26,
		"len_ratio": 0.70,
		"w_ratio": 0.66,
		"min_width": 2.2,
		"children_min": 2,
		"children_max": 3,
		"canopy_count": 34,
		"canopy_radius": 38.0,
		"leaf_size": 8.0,
		"lean": 0.0,
		"palette": _palette("alien"),
		"bark": Color8(34, 26, 26),
	}

	# Ряд 0 — вариация по сиду (alien-red), один и тот же набор параметров.
	_row_labels.append({"text": "Случайные сиды — одна модель, разные деревья (alien-red)", "pos": Vector2(14, 8)})
	for col: int in range(COLS):
		_add_tree(_merge(base, { }), 1000 + col, _origin(col, 0, cw, ch))

	# Ряд 1 — слайдер gnarl: от прямого до сильно витого.
	_row_labels.append({"text": "Слайдер gnarl: прямой -> витой", "pos": Vector2(14, int(ch) + 8)})
	var gnarls: Array = [0.10, 0.30, 0.52, 0.78, 1.05, 1.32]
	for col: int in range(COLS):
		_add_tree(_merge(base, {"gnarl": gnarls[col]}), 2024, _origin(col, 1, cw, ch))

	# Ряд 2 — слайдер плотности кроны.
	_row_labels.append({"text": "Слайдер плотности кроны: голое -> густое", "pos": Vector2(14, int(ch) * 2 + 8)})
	var counts: Array = [5, 14, 26, 40, 58, 82]
	var radii: Array = [26.0, 30.0, 34.0, 38.0, 43.0, 48.0]
	for col: int in range(COLS):
		_add_tree(_merge(base, {"canopy_count": counts[col], "canopy_radius": radii[col]}), 777, _origin(col, 2, cw, ch))

	# Ряд 3 — палитра: alien / осень / пепел (по 2).
	_row_labels.append({"text": "Палитра (один параметр): alien-red / осень / пепел", "pos": Vector2(14, int(ch) * 3 + 8)})
	var pals: Array = ["alien", "alien", "autumn", "autumn", "ash", "ash"]
	var barks: Array = [
		Color8(34, 26, 26), Color8(34, 26, 26),
		Color8(40, 30, 18), Color8(40, 30, 18),
		Color8(42, 42, 48), Color8(42, 42, 48),
	]
	for col: int in range(COLS):
		_add_tree(_merge(base, {"palette": _palette(pals[col]), "bark": barks[col]}), 300 + col, _origin(col, 3, cw, ch))

	# Ряд 4 — наклон (ветер) и размер.
	_row_labels.append({"text": "Наклон (ветер) и размер ствола", "pos": Vector2(14, int(ch) * 4 + 8)})
	var leans: Array = [-0.30, -0.16, 0.0, 0.16, 0.30, 0.0]
	var lens: Array = [70.0, 70.0, 70.0, 70.0, 70.0, 96.0]
	var widths: Array = [21.0, 21.0, 21.0, 21.0, 21.0, 28.0]
	for col: int in range(COLS):
		_add_tree(_merge(base, {"lean": leans[col], "trunk_len": lens[col], "trunk_w": widths[col]}), 555 + col, _origin(col, 4, cw, ch))


func _origin(col: int, row: int, cw: float, ch: float) -> Vector2:
	return Vector2(col * cw + cw * 0.5, row * ch + ch - 16.0)


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for k: Variant in b.keys():
		out[k] = b[k]
	return out


func _add_tree(params: Dictionary, seed_value: int, origin: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var branches: Array = []
	var leaves: Array = []
	var counter: Array = [0]
	_branch(rng, origin, Vector2.UP, params["trunk_len"], params["trunk_w"], int(params["depth"]), params, branches, leaves, counter)
	# Контактная тень-эллипс под основанием.
	var shadow := _ellipse(origin + Vector2(2, 4), params["trunk_w"] * 1.7, params["trunk_w"] * 0.6)
	_trees.append({"shadow": shadow, "branches": branches, "leaves": leaves})


func _branch(rng: RandomNumberGenerator, start: Vector2, dir: Vector2, length: float, width: float, depth: int, params: Dictionary, branches: Array, leaves: Array, counter: Array) -> void:
	counter[0] += 1
	if counter[0] > 900:
		return
	var steps: int = 5
	var seg_len: float = length / float(steps)
	var p: Vector2 = start
	var d: Vector2 = dir
	var w: float = width
	var gnarl: float = params["gnarl"]
	var lean: float = params["lean"]
	for i: int in range(steps):
		var twist: float = rng.randf_range(-gnarl, gnarl) + lean
		d = d.rotated(twist).normalized()
		var t_end: float = float(i + 1) / float(steps)
		var w_end: float = lerpf(width, width * float(params["taper_along"]), t_end)
		var np: Vector2 = p + d * seg_len
		_add_segment(p, w, np, w_end, params["bark"], branches)
		p = np
		w = w_end
	if depth <= 0 or w < float(params["min_width"]):
		_canopy(rng, p, params, leaves)
		return
	# Иногда крона и на промежуточном узле — для объёма.
	if depth <= 2 and rng.randf() < 0.5:
		_canopy(rng, p, _merge(params, {"canopy_count": int(params["canopy_count"]) / 2}), leaves)
	var children: int = rng.randi_range(int(params["children_min"]), int(params["children_max"]))
	var sign: float = 1.0 if rng.randf() < 0.5 else -1.0
	for c: int in range(children):
		var ang: float = (float(params["split_angle"]) + rng.randf_range(-1.0, 1.0) * float(params["split_jitter"])) * sign
		sign = -sign
		var child_dir: Vector2 = d.rotated(ang).normalized()
		var child_len: float = length * float(params["len_ratio"]) * rng.randf_range(0.82, 1.12)
		var child_w: float = w * float(params["w_ratio"])
		_branch(rng, p, child_dir, child_len, child_w, depth - 1, params, branches, leaves, counter)


func _add_segment(a: Vector2, wa: float, b: Vector2, wb: float, bark: Color, branches: Array) -> void:
	var dir: Vector2 = (b - a)
	if dir.length() < 0.001:
		dir = Vector2.UP
	var n: Vector2 = dir.orthogonal().normalized()
	var pts := PackedVector2Array([
		a - n * wa * 0.5, a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5,
	])
	var f_plus: float = clampf(n.dot(LIGHT_DIR) * 0.45 + 0.78, 0.42, 1.18)
	var f_minus: float = clampf((-n).dot(LIGHT_DIR) * 0.45 + 0.78, 0.42, 1.18)
	var cols := PackedColorArray([
		_shade(bark, f_minus), _shade(bark, f_plus), _shade(bark, f_plus), _shade(bark, f_minus),
	])
	branches.append({"pts": pts, "cols": cols})


func _canopy(rng: RandomNumberGenerator, center: Vector2, params: Dictionary, leaves: Array) -> void:
	var count: int = int(params["canopy_count"])
	var radius: float = float(params["canopy_radius"])
	var leaf_size: float = float(params["leaf_size"])
	var palette: Array = params["palette"]
	for i: int in range(count):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.82 - radius * 0.15)
		var base_col: Color = palette[rng.randi_range(0, palette.size() - 1)]
		var jit: float = rng.randf_range(0.82, 1.16)
		var col := Color(base_col.r * jit, base_col.g * jit, base_col.b * jit, 0.92)
		var sz: float = leaf_size * rng.randf_range(0.7, 1.4)
		leaves.append({"pts": _blob(center + offset, sz, rng), "col": col})


func _blob(center: Vector2, size: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var verts: int = rng.randi_range(5, 7)
	var pts := PackedVector2Array()
	var start_ang: float = rng.randf() * TAU
	for i: int in range(verts):
		var a: float = start_ang + TAU * float(i) / float(verts)
		var r: float = size * rng.randf_range(0.7, 1.25)
		pts.append(center + Vector2(cos(a) * r, sin(a) * r))
	return pts


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


func _palette(name: String) -> Array:
	match name:
		"alien":
			return [Color8(28, 6, 6), Color8(58, 10, 10), Color8(96, 16, 16), Color8(140, 22, 22), Color8(178, 30, 28), Color8(15, 4, 4)]
		"autumn":
			return [Color8(120, 40, 12), Color8(150, 64, 16), Color8(176, 92, 24), Color8(196, 128, 36), Color8(96, 30, 12), Color8(70, 28, 10)]
		"ash":
			return [Color8(60, 58, 60), Color8(86, 84, 86), Color8(40, 40, 44), Color8(110, 104, 98), Color8(24, 22, 24), Color8(70, 66, 64)]
		_:
			return [Color8(96, 16, 16)]


func _draw() -> void:
	# Фон — приглушённый «земляной» тон + разделители рядов.
	draw_rect(Rect2(0, 0, CANVAS_W, CANVAS_H), Color8(110, 104, 92))
	var ch: float = float(CANVAS_H) / float(ROWS)
	for row: int in range(1, ROWS):
		draw_line(Vector2(0, row * ch), Vector2(CANVAS_W, row * ch), Color(0, 0, 0, 0.18), 2.0)
	for tree: Dictionary in _trees:
		draw_colored_polygon(tree["shadow"], Color(0, 0, 0, 0.16))
		for seg: Dictionary in tree["branches"]:
			draw_polygon(seg["pts"], seg["cols"])
		for leaf: Dictionary in tree["leaves"]:
			draw_colored_polygon(leaf["pts"], leaf["col"])
	if _font != null:
		for label: Dictionary in _row_labels:
			draw_string(_font, label["pos"] + Vector2(1, 14), label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.55))
			draw_string(_font, label["pos"] + Vector2(0, 13), label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.96, 0.95, 0.9))
