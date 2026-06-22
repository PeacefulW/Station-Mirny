extends Node2D

const TreeProfile = preload("res://core/systems/world/world_visual_tree_profile.gd")

# Геометрия одного процедурного дерева для tool-экспорта атласа равнинных
# деревьев. Ветки — непрерывные полигональные ленты (обводка по центральной
# линии), без щелей. Корни в землю, объёмная крона со светом p_light_dir.
# НЕТ травяной бахромы у комля (запрещено спекой — трава у комля приходит от
# depth-лесенки в рантайме, не запекается). Только compute+draw; данные —
# WorldVisualTreeProfile, передаются tool-экспортёром.
# Контракт: docs/02_system_specs/world/plains_trees_presentation.md

var p_seed: int = 1
var p_gnarl: float = 0.5
var p_trunk_len: float = 70.0
var p_trunk_w: float = 21.0
var p_taper_along: float = 0.60
var p_split_angle: float = 0.62
var p_split_jitter: float = 0.26
var p_len_ratio: float = 0.70
var p_w_ratio: float = 0.66
var p_min_width: float = 2.4
var p_canopy_count: int = 60
var p_canopy_radius: float = 40.0
var p_leaf_size: float = 4.5
var p_leaf_alpha: float = 0.82
var p_lean: float = 0.0
var p_bark: Color = Color8(86, 62, 40)
var p_palette: Array[Color] = []
var p_canopy_tint: Color = Color(1.0, 1.0, 1.0)
var p_light_dir: Vector2 = Vector2(-0.7, -0.72)
var base_pos: Vector2 = Vector2.ZERO

var _branches: Array = []
var _leaves: Array = []
var _base_ao: PackedVector2Array = PackedVector2Array()
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	if p_palette.is_empty():
		p_palette = TreeProfile.palette_autumn()
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_base_ao = _ellipse(base_pos + Vector2(0, -p_trunk_w * 0.28), p_trunk_w * 1.7, p_trunk_w * 0.6)
	var counter: Array = [0]
	_branch(rng, base_pos, Vector2.UP, p_trunk_len, p_trunk_w, 5, 5, counter, true)
	_roots(rng, base_pos, p_trunk_w)


func _roots(rng: RandomNumberGenerator, base: Vector2, _unused: float = 0.0) -> void:
	var dark := Color(p_bark.r * 0.72, p_bark.g * 0.72, p_bark.b * 0.72, 1.0)
	var n: int = rng.randi_range(3, 5)
	for i: int in range(n):
		var spread: float = lerpf(-1.0, 1.0, float(i) / float(maxi(n - 1, 1)))
		var d: Vector2 = Vector2.DOWN.rotated(spread * 1.05 + rng.randf_range(-0.15, 0.15))
		var pts: Array = [base]
		var widths: Array = [p_trunk_w * rng.randf_range(0.34, 0.52)]
		var p: Vector2 = base
		var seg: float = p_trunk_w * rng.randf_range(0.55, 0.95)
		for s: int in range(3):
			d = d.rotated(rng.randf_range(-p_gnarl, p_gnarl) * 0.7).normalized()
			p = p + d * seg
			pts.append(p)
			widths.append(float(widths[widths.size() - 1]) * 0.45)
			seg *= 0.7
		_stroke(pts, widths, dark, 0.78)


func _branch(rng: RandomNumberGenerator, start: Vector2, dir: Vector2, length: float, width: float, depth: int, max_depth: int, counter: Array, is_trunk: bool) -> void:
	counter[0] += 1
	if counter[0] > 900:
		return
	var steps: int = 5
	var seg_len: float = length / float(steps)
	var tone: float = lerpf(0.84, 1.08, float(max_depth - depth) / float(max_depth))
	var p: Vector2 = start
	var d: Vector2 = dir
	var w: float = width
	var pts: Array = [p]
	var widths: Array = [width * 1.4 if is_trunk else width]
	for i: int in range(steps):
		var twist: float = rng.randf_range(-p_gnarl, p_gnarl) + p_lean
		d = d.rotated(twist).normalized()
		var t_end: float = float(i + 1) / float(steps)
		w = lerpf(width, width * p_taper_along, t_end)
		p = p + d * seg_len
		pts.append(p)
		widths.append(w)
	_stroke(pts, widths, p_bark, tone)
	if depth <= 0 or w < p_min_width:
		_canopy(rng, p, p_canopy_count)
		return
	if depth <= 2 and rng.randf() < 0.55:
		_canopy(rng, p, int(p_canopy_count) / 2)
	var children: int = rng.randi_range(2, 3)
	var sign: float = 1.0 if rng.randf() < 0.5 else -1.0
	for c: int in range(children):
		var ang: float = (p_split_angle + rng.randf_range(-1.0, 1.0) * p_split_jitter) * sign
		sign = -sign
		var child_dir: Vector2 = d.rotated(ang).normalized()
		var child_len: float = length * p_len_ratio * rng.randf_range(0.82, 1.12)
		var child_w: float = w * p_w_ratio
		_branch(rng, p, child_dir, child_len, child_w, depth - 1, max_depth, counter, false)


# Непрерывная лента по центральной линии: левый край вперёд, правый назад —
# один полигон, без щелей на изгибах. Шейдинг: левая/правая сторона по свету.
func _stroke(pts: Array, widths: Array, bark: Color, tone: float) -> void:
	var count: int = pts.size()
	if count < 2:
		return
	var poly := PackedVector2Array()
	var cols := PackedColorArray()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var lcol := PackedColorArray()
	var rcol := PackedColorArray()
	for i: int in range(count):
		var dir: Vector2 = _dir_at(pts, i)
		var nrm: Vector2 = dir.orthogonal().normalized()
		var hw: float = float(widths[i]) * 0.5
		left.append(pts[i] - nrm * hw)
		right.append(pts[i] + nrm * hw)
		var f_l: float = clampf((-nrm).dot(p_light_dir) * 0.34 + 0.82, 0.58, 1.12) * tone
		var f_r: float = clampf(nrm.dot(p_light_dir) * 0.34 + 0.82, 0.58, 1.12) * tone
		lcol.append(_shade(bark, f_l))
		rcol.append(_shade(bark, f_r))
	for i: int in range(count):
		poly.append(left[i])
		cols.append(lcol[i])
	for i: int in range(count - 1, -1, -1):
		poly.append(right[i])
		cols.append(rcol[i])
	_branches.append({"pts": poly, "cols": cols})


func _dir_at(pts: Array, i: int) -> Vector2:
	var d: Vector2
	if i == 0:
		d = (pts[1] - pts[0])
	elif i == pts.size() - 1:
		d = (pts[i] - pts[i - 1])
	else:
		d = (pts[i + 1] - pts[i - 1])
	if d.length() < 0.001:
		return Vector2.UP
	return d.normalized()


func _canopy(rng: RandomNumberGenerator, center: Vector2, count: int) -> void:
	var radius: float = p_canopy_radius
	var dark: Color = p_palette[p_palette.size() - 1]

	var mass_n: int = int(maxf(float(count) / 3.0, 4.0))
	for i: int in range(mass_n):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius * 0.80
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.80 - radius * 0.16)
		var c := Color(dark.r * 0.74 * p_canopy_tint.r, dark.g * 0.74 * p_canopy_tint.g, dark.b * 0.74 * p_canopy_tint.b, 0.85)
		_leaves.append({"pts": _blob(center + offset, p_leaf_size * rng.randf_range(1.4, 2.1), rng), "col": c})

	var detail: Array = []
	for i: int in range(count):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.82 - radius * 0.16)
		var ndir: Vector2 = offset.normalized() if offset.length() > 0.01 else Vector2.ZERO
		var lit: float = ndir.dot(p_light_dir)
		var shade: float = clampf(0.80 + lit * 0.26, 0.66, 1.14)
		var base_col: Color = p_palette[rng.randi_range(0, p_palette.size() - 1)]
		var jit: float = rng.randf_range(0.95, 1.05)
		var col := Color(base_col.r * shade * jit * p_canopy_tint.r, base_col.g * shade * jit * p_canopy_tint.g, base_col.b * shade * jit * p_canopy_tint.b, p_leaf_alpha)
		var sz: float = p_leaf_size * rng.randf_range(0.65, 1.25)
		detail.append({"pts": _blob(center + offset, sz, rng), "col": col, "k": lit})
	detail.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["k"]) < float(b["k"]))
	for leaf: Dictionary in detail:
		_leaves.append({"pts": leaf["pts"], "col": leaf["col"]})

	var bright: Color = p_palette[p_palette.size() - 2]
	var hi_n: int = int(maxf(float(count) / 7.0, 2.0))
	for i: int in range(hi_n):
		var bias: Vector2 = p_light_dir.rotated(rng.randf_range(-0.5, 0.5))
		var rad: float = radius * rng.randf_range(0.25, 0.7)
		var offset := Vector2(bias.x * rad, bias.y * rad - radius * 0.16)
		var col := Color(
			clampf(bright.r * 1.06 * p_canopy_tint.r, 0.0, 1.0),
			clampf(bright.g * 1.06 * p_canopy_tint.g, 0.0, 1.0),
			clampf(bright.b * 1.06 * p_canopy_tint.b, 0.0, 1.0),
			0.88,
		)
		_leaves.append({"pts": _blob(center + offset, p_leaf_size * rng.randf_range(0.65, 1.0), rng), "col": col})


func get_content_bounds() -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for seg: Dictionary in _branches:
		for pt: Vector2 in seg["pts"]:
			mn = mn.min(pt)
			mx = mx.max(pt)
	for leaf: Dictionary in _leaves:
		for pt: Vector2 in leaf["pts"]:
			mn = mn.min(pt)
			mx = mx.max(pt)
	for pt: Vector2 in _base_ao:
		mn = mn.min(pt)
		mx = mx.max(pt)
	if mn.x > mx.x:
		return Rect2(base_pos, Vector2.ZERO)
	return Rect2(mn, mx - mn)


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


func _draw() -> void:
	if _base_ao.size() > 0:
		draw_colored_polygon(_base_ao, Color(0, 0, 0, 0.14))
	for seg: Dictionary in _branches:
		draw_polygon(seg["pts"], seg["cols"])
	for leaf: Dictionary in _leaves:
		draw_colored_polygon(leaf["pts"], leaf["col"])
