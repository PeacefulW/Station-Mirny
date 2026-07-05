extends Node2D

const TreeProfile = preload("res://core/systems/world/world_visual_tree_profile.gd")

# Геометрия одного процедурного дерева для tool-экспорта атласа равнинных
# деревьев. Ветки — непрерывные полигональные ленты (обводка по центральной
# линии), без щелей. Корни в землю, объёмная крона со светом p_light_dir.
# НЕТ травяной бахромы и baked contact-shadow у комля: трава/тени приходят из
# рантайма, не из PNG-атласа. Только compute+draw; данные —
# WorldVisualTreeProfile, передаются tool-экспортёром.
# Контракт: docs/02_system_specs/world/plains_trees_presentation.md

var p_seed: int = 1
var p_gnarl: float = 0.5
var p_trunk_len: float = 70.0
var p_trunk_w: float = 21.0
var p_taper_along: float = 0.68
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
var _bark_palette: Dictionary = {}
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
	_bark_palette = TreeProfile.bark_palette()
	p_bark = _palette_color("mid", p_bark)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var counter: Array = [0]
	_roots(rng, base_pos, p_trunk_w)
	_branch(rng, base_pos, Vector2.UP, p_trunk_len, p_trunk_w, 5, 5, counter, true)


func _roots(rng: RandomNumberGenerator, base: Vector2, _unused: float = 0.0) -> void:
	# Короткие buttress-root лапы дают вес у основания без baked grass fringe.
	var root_color: Color = _palette_color("dark", Color(p_bark.r * 0.84, p_bark.g * 0.84, p_bark.b * 0.84, 1.0)).lerp(_palette_color("mid", p_bark), 0.42)
	var root_defs: Array = [
		{"start": Vector2(-0.30, 0.08), "dir": Vector2(-0.92, 0.40), "len": 1.08, "width": 0.44},
		{"start": Vector2(0.30, 0.08), "dir": Vector2(0.90, 0.42), "len": 1.00, "width": 0.40},
		{"start": Vector2(-0.02, 0.20), "dir": Vector2(-0.12, 1.00), "len": 0.76, "width": 0.34},
	]
	if rng.randf() < 0.38:
		root_defs.append({"start": Vector2(0.12, 0.18), "dir": Vector2(0.34, 0.94), "len": 0.66, "width": 0.28})
	for i: int in range(root_defs.size()):
		var root_def: Dictionary = root_defs[i] as Dictionary
		var d: Vector2 = (root_def["dir"] as Vector2).rotated(rng.randf_range(-0.08, 0.08)).normalized()
		var p: Vector2 = base + (root_def["start"] as Vector2) * p_trunk_w
		var pts: Array = [p]
		var start_width: float = p_trunk_w * float(root_def["width"]) * rng.randf_range(0.90, 1.08)
		var widths: Array = [start_width]
		var seg: float = p_trunk_w * float(root_def["len"]) * rng.randf_range(0.86, 1.10)
		p = p + d * seg
		pts.append(p)
		widths.append(start_width * 0.32)
		_stroke(pts, widths, root_color, 1.02, false, 0, _detail_seed(i, 9), true)


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
	var pts: Array = []
	var widths: Array = []
	if is_trunk:
		var lower_base := start + Vector2(0.0, width * 0.24)
		var upper_base := start + Vector2(0.0, width * 0.02)
		pts.append(lower_base)
		widths.append(width * 1.20)
		pts.append(upper_base)
		widths.append(width * 1.12)
		p = upper_base
	else:
		pts.append(p)
		widths.append(width)
	# Наклон ветром сильнее в кроне (ветки), слабее в стволе → ствол стоит, а не «падает».
	var lean_here: float = p_lean * (0.4 if is_trunk else 1.0)
	for i: int in range(steps):
		var twist: float = rng.randf_range(-p_gnarl, p_gnarl) + lean_here
		d = d.rotated(twist).normalized()
		if is_trunk:
			d = Vector2(clampf(d.x, -0.34, 0.34), minf(d.y, -0.72)).normalized()
		var t_end: float = float(i + 1) / float(steps)
		w = lerpf(width, width * p_taper_along, t_end)
		if is_trunk and i <= 1:
			w = maxf(w, lerpf(width * 1.24, width * 1.08, t_end * 2.0))
		p = p + d * seg_len
		pts.append(p)
		widths.append(w)
	_stroke(pts, widths, p_bark, tone, is_trunk, depth, _detail_seed(counter[0], depth))
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
func _stroke(pts: Array, widths: Array, bark: Color, tone: float, is_trunk: bool = false, depth: int = 0, detail_seed: int = 0, is_root: bool = false) -> void:
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
		var rough_left: float = 1.0 + sin(float(i) * 2.17 + float(detail_seed % 97) * 0.13) * (0.055 if hw > 5.0 else 0.02)
		var rough_right: float = 1.0 + cos(float(i) * 1.91 + float(detail_seed % 113) * 0.11) * (0.055 if hw > 5.0 else 0.02)
		left.append(pts[i] - nrm * hw * rough_left)
		right.append(pts[i] + nrm * hw * rough_right)
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
	_branches.append({
		"pts": poly,
		"cols": cols,
		"center": pts.duplicate(),
		"widths": widths.duplicate(),
		"is_trunk": is_trunk,
		"is_root": is_root,
		"depth": depth,
		"detail_seed": detail_seed,
	})


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


func _detail_seed(index: int, salt: int) -> int:
	return int(abs((p_seed * 928371 + index * 5237 + salt * 193) % 2147483647))


func _palette_color(name: String, fallback: Color) -> Color:
	var value: Variant = _bark_palette.get(name, fallback)
	if value is Color:
		return value as Color
	return fallback


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _draw_bark_details(branch: Dictionary) -> void:
	var centers: Array = branch.get("center", []) as Array
	var widths: Array = branch.get("widths", []) as Array
	if centers.size() < 2 or widths.size() < 2:
		return
	if bool(branch.get("is_root", false)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(branch.get("detail_seed", p_seed))
	var is_trunk: bool = bool(branch.get("is_trunk", false))
	_draw_branch_edge_shadow(branch)
	var knot_budget: int = 3 if is_trunk else 1
	var knots_drawn: int = 0
	for i: int in range(centers.size() - 1):
		var a: Vector2 = centers[i]
		var b: Vector2 = centers[i + 1]
		var tangent: Vector2 = b - a
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()
		var normal: Vector2 = tangent.orthogonal().normalized()
		var w: float = float(widths[min(i, widths.size() - 1)])
		if w < 5.0:
			continue
		var crack_count: int = clampi(int(round(w / 5.2)), 1, 5)
		for _c: int in range(crack_count):
			var offset: float = rng.randf_range(-w * 0.28, w * 0.28)
			var t0: float = rng.randf_range(0.05, 0.58)
			var t1: float = minf(t0 + rng.randf_range(0.18, 0.44), 0.96)
			var p0: Vector2 = a.lerp(b, t0) + normal * offset
			var p1: Vector2 = a.lerp(b, t1) + normal * (offset + rng.randf_range(-w * 0.08, w * 0.08))
			var mid: Vector2 = (p0 + p1) * 0.5 + normal * rng.randf_range(-1.8, 1.8)
			draw_polyline(
				PackedVector2Array([p0, mid, p1]),
				_with_alpha(_palette_color("shadow", Color(0.16, 0.10, 0.06)), rng.randf_range(0.26, 0.56)),
				maxf(1.8, w * 0.055),
				true,
			)
		if w > 8.5 and rng.randf() < (0.62 if is_trunk else 0.28):
			var light_normal: Vector2 = normal if normal.dot(p_light_dir) > (-normal).dot(p_light_dir) else -normal
			var t_start: float = rng.randf_range(0.08, 0.50)
			var t_end: float = minf(t_start + rng.randf_range(0.22, 0.50), 0.95)
			var ridge0: Vector2 = a.lerp(b, t_start) + light_normal * rng.randf_range(w * 0.08, w * 0.26)
			var ridge1: Vector2 = a.lerp(b, t_end) + light_normal * rng.randf_range(w * 0.08, w * 0.26)
			draw_polyline(
				PackedVector2Array([ridge0, (ridge0 + ridge1) * 0.5, ridge1]),
				_with_alpha(_palette_color("highlight", Color(0.62, 0.42, 0.24)), rng.randf_range(0.18, 0.36)),
				maxf(1.5, w * 0.038),
				true,
			)
		if w > 11.0 and knots_drawn < knot_budget and rng.randf() < (0.44 if is_trunk else 0.16):
			_draw_knot(a.lerp(b, rng.randf_range(0.25, 0.72)), tangent, normal, w, rng)
			knots_drawn += 1
		if w > 13.0 and rng.randf() < 0.055:
			var moss_center: Vector2 = a.lerp(b, rng.randf_range(0.18, 0.82)) + normal * rng.randf_range(-w * 0.22, w * 0.22)
			draw_colored_polygon(
				_oriented_ellipse(moss_center, tangent, normal, w * 0.12, w * 0.045, 9),
				_with_alpha(_palette_color("moss", Color(0.28, 0.33, 0.18)), 0.24),
			)


func _draw_branch_edge_shadow(branch: Dictionary) -> void:
	var centers: Array = branch.get("center", []) as Array
	var widths: Array = branch.get("widths", []) as Array
	if centers.size() < 2 or widths.size() < 2:
		return
	var shadow_pts := PackedVector2Array()
	var width_sum: float = 0.0
	for i: int in range(centers.size()):
		var dir: Vector2 = _dir_at(centers, i)
		var normal: Vector2 = dir.orthogonal().normalized()
		var shadow_normal: Vector2 = normal if normal.dot(p_light_dir) < (-normal).dot(p_light_dir) else -normal
		var w: float = float(widths[min(i, widths.size() - 1)])
		width_sum += w
		shadow_pts.append((centers[i] as Vector2) + shadow_normal * w * 0.38)
	draw_polyline(
		shadow_pts,
		_with_alpha(_palette_color("dark", Color(0.24, 0.15, 0.09)), 0.34),
		maxf(2.0, (width_sum / float(widths.size())) * 0.11),
		true,
	)


func _draw_knot(center: Vector2, tangent: Vector2, normal: Vector2, width: float, rng: RandomNumberGenerator) -> void:
	var pos: Vector2 = center + normal * rng.randf_range(-width * 0.18, width * 0.18)
	var rx: float = maxf(3.0, width * rng.randf_range(0.14, 0.22))
	var ry: float = maxf(1.8, width * rng.randf_range(0.065, 0.11))
	draw_colored_polygon(
		_oriented_ellipse(pos, tangent, normal, rx * 1.35, ry * 1.28, 14),
		_with_alpha(_palette_color("warm", Color(0.48, 0.32, 0.19)), 0.46),
	)
	draw_colored_polygon(
		_oriented_ellipse(pos, tangent, normal, rx, ry, 14),
		_with_alpha(_palette_color("shadow", Color(0.18, 0.11, 0.07)), 0.64),
	)
	var hi_pos: Vector2 = pos - normal * ry * 0.22 + tangent * rx * 0.20
	draw_colored_polygon(
		_oriented_ellipse(hi_pos, tangent, normal, rx * 0.48, ry * 0.34, 10),
		_with_alpha(_palette_color("highlight", Color(0.60, 0.42, 0.24)), 0.34),
	)


func _canopy(rng: RandomNumberGenerator, center: Vector2, count: int) -> void:
	var radius: float = p_canopy_radius
	var dark: Color = p_palette[p_palette.size() - 1]

	# 1) масса-силуэт: плотное ядро; тон по вертикали (низ темнее) → объём.
	var mass_n: int = int(maxf(float(count) / 2.6, 6.0))
	for i: int in range(mass_n):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius * 0.86
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.84 - radius * 0.14)
		var vfac: float = clampf(0.66 - offset.y / (radius * 1.9), 0.5, 0.94)
		var c := Color(dark.r * vfac * 1.04 * p_canopy_tint.r, dark.g * vfac * 1.04 * p_canopy_tint.g, dark.b * vfac * 1.04 * p_canopy_tint.b, 0.9)
		_leaves.append({"pts": _blob(center + offset, p_leaf_size * rng.randf_range(1.5, 2.2), rng), "col": c})

	# 2) детальные листья: мельче и больше; свет по НАПРАВЛЕНИЮ + ВЕРТИКАЛИ (объём).
	var detail: Array = []
	for i: int in range(count):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.84 - radius * 0.14)
		var ndir: Vector2 = offset.normalized() if offset.length() > 0.01 else Vector2.ZERO
		var lit: float = ndir.dot(p_light_dir)
		var vert: float = clampf(-offset.y / radius, -1.0, 1.0)
		var shade: float = clampf(0.74 + lit * 0.20 + vert * 0.16, 0.56, 1.2)
		var base_col: Color = p_palette[rng.randi_range(0, p_palette.size() - 1)]
		var jit: float = rng.randf_range(0.96, 1.04)
		var col := Color(base_col.r * shade * jit * p_canopy_tint.r, base_col.g * shade * jit * p_canopy_tint.g, base_col.b * shade * jit * p_canopy_tint.b, p_leaf_alpha)
		var sz: float = p_leaf_size * rng.randf_range(0.6, 1.12)
		detail.append({"pts": _blob(center + offset, sz, rng), "col": col, "k": lit + vert * 0.5})
	detail.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["k"]) < float(b["k"]))
	for leaf: Dictionary in detail:
		_leaves.append({"pts": leaf["pts"], "col": leaf["col"]})

	# 3) блики — на солнечной верхней стороне кроны.
	var bright: Color = p_palette[p_palette.size() - 2]
	var hi_n: int = int(maxf(float(count) / 8.0, 2.0))
	for i: int in range(hi_n):
		var bias: Vector2 = p_light_dir.rotated(rng.randf_range(-0.4, 0.4))
		var rad: float = radius * rng.randf_range(0.2, 0.6)
		var offset := Vector2(bias.x * rad, bias.y * rad - radius * 0.18)
		var col := Color(
			clampf(bright.r * 1.08 * p_canopy_tint.r, 0.0, 1.0),
			clampf(bright.g * 1.08 * p_canopy_tint.g, 0.0, 1.0),
			clampf(bright.b * 1.08 * p_canopy_tint.b, 0.0, 1.0),
			0.85,
		)
		_leaves.append({"pts": _blob(center + offset, p_leaf_size * rng.randf_range(0.6, 0.95), rng), "col": col})

	# 4) мягкий край — редкие мелкие полупрозрачные листья по кромке силуэта,
	# чтобы крона не читалась «попкорном» с жёстким контуром.
	var edge_n: int = int(maxf(float(count) / 4.0, 5.0))
	for i: int in range(edge_n):
		var ang: float = rng.randf() * TAU
		var rad: float = radius * rng.randf_range(0.82, 1.05)
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.84 - radius * 0.14)
		var base_col: Color = p_palette[rng.randi_range(1, p_palette.size() - 2)]
		var col := Color(base_col.r * 0.96 * p_canopy_tint.r, base_col.g * 0.96 * p_canopy_tint.g, base_col.b * 0.96 * p_canopy_tint.b, 0.4)
		_leaves.append({"pts": _blob(center + offset, p_leaf_size * rng.randf_range(0.5, 0.85), rng), "col": col})


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
	if mn.x > mx.x:
		return Rect2(base_pos, Vector2.ZERO)
	return Rect2(mn, mx - mn)


func _blob(center: Vector2, size: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var verts: int = rng.randi_range(7, 9)
	var pts := PackedVector2Array()
	var start_ang: float = rng.randf() * TAU
	for i: int in range(verts):
		var a: float = start_ang + TAU * float(i) / float(verts)
		var r: float = size * rng.randf_range(0.84, 1.12)
		pts.append(center + Vector2(cos(a) * r, sin(a) * r))
	return pts


func _oriented_ellipse(center: Vector2, tangent: Vector2, normal: Vector2, rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var safe_steps: int = maxi(steps, 6)
	for i: int in range(safe_steps):
		var a: float = TAU * float(i) / float(safe_steps)
		pts.append(center + tangent * cos(a) * rx + normal * sin(a) * ry)
	return pts


func _shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


func _draw() -> void:
	for seg: Dictionary in _branches:
		draw_polygon(seg["pts"], seg["cols"])
	for seg: Dictionary in _branches:
		_draw_bark_details(seg)
	for leaf: Dictionary in _leaves:
		draw_colored_polygon(leaf["pts"], leaf["col"])
