extends Node2D

# Одиночное процедурное дерево. Ветки — непрерывные полигональные ленты (обводка
# по центральной линии), без щелей на изгибах. Палитра приглушена под траву
# (дусто-тановая, низкий контраст), ствол — тёплый коричневый, не чёрный.
# build() строит геометрию; get_content_bounds() — реальный габарит для запекания.

var p_seed: int = 1
var p_palette: String = "autumn"
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
var p_canopy_tint: Color = Color(1.0, 1.0, 1.0)
var p_light_dir: Vector2 = Vector2(-0.7, -0.72)
var p_fringe_count: int = 13
var base_pos: Vector2 = Vector2.ZERO

var _branches: Array = []
var _leaves: Array = []
var _fringe: Array = []
var _base_ao: PackedVector2Array = PackedVector2Array()
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	var params: Dictionary = {
		"trunk_len": p_trunk_len, "trunk_w": p_trunk_w, "depth": 5, "max_depth": 5,
		"gnarl": p_gnarl, "taper_along": p_taper_along,
		"split_angle": p_split_angle, "split_jitter": p_split_jitter,
		"len_ratio": p_len_ratio, "w_ratio": p_w_ratio, "min_width": p_min_width,
		"children_min": 2, "children_max": 3,
		"canopy_count": p_canopy_count, "canopy_radius": p_canopy_radius,
		"leaf_size": p_leaf_size, "lean": p_lean,
		"palette": _palette(p_palette), "bark": p_bark, "canopy_tint": p_canopy_tint,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_base_ao = _ellipse(base_pos + Vector2(0, -p_trunk_w * 0.28), p_trunk_w * 1.7, p_trunk_w * 0.6)
	var counter: Array = [0]
	_branch(rng, base_pos, Vector2.UP, params["trunk_len"], params["trunk_w"], int(params["depth"]), params, counter, true)
	_roots(rng, base_pos, p_trunk_w, p_bark, float(params["gnarl"]))
	_base_grass(rng, base_pos, p_trunk_w)


# Травяная бахрома у комля: лезвия сухой травы поверх низа ствола — «трава у
# основания», запечена в текстуру (стабильно, только низ, не зависит от игрока).
func _base_grass(rng: RandomNumberGenerator, base: Vector2, trunk_w: float) -> void:
	var lo := Color8(104, 80, 44)
	var hi := Color8(172, 136, 76)
	for i: int in range(p_fringe_count):
		var root := Vector2(base.x + rng.randf_range(-trunk_w * 1.15, trunk_w * 1.15), base.y + rng.randf_range(-1.0, 5.0))
		var hgt: float = trunk_w * rng.randf_range(0.5, 1.25)
		var tip := root + Vector2(rng.randf_range(-0.5, 0.5) * hgt, -hgt)
		var dir: Vector2 = (tip - root)
		if dir.length() < 0.001:
			dir = Vector2.UP
		var nrm: Vector2 = dir.orthogonal().normalized()
		var w: float = rng.randf_range(1.4, 2.8)
		var poly := PackedVector2Array([root - nrm * w * 0.5, root + nrm * w * 0.5, tip])
		var col: Color = lo.lerp(hi, rng.randf())
		col.a = 0.92
		_fringe.append({"pts": poly, "col": col})


func _roots(rng: RandomNumberGenerator, base: Vector2, trunk_w: float, bark: Color, gnarl: float) -> void:
	var dark := Color(bark.r * 0.72, bark.g * 0.72, bark.b * 0.72, 1.0)
	var n: int = rng.randi_range(3, 5)
	for i: int in range(n):
		var spread: float = lerpf(-1.0, 1.0, float(i) / float(maxi(n - 1, 1)))
		var d: Vector2 = Vector2.DOWN.rotated(spread * 1.05 + rng.randf_range(-0.15, 0.15))
		var pts: Array = [base]
		var widths: Array = [trunk_w * rng.randf_range(0.34, 0.52)]
		var p: Vector2 = base
		var seg: float = trunk_w * rng.randf_range(0.55, 0.95)
		for s: int in range(3):
			d = d.rotated(rng.randf_range(-gnarl, gnarl) * 0.7).normalized()
			p = p + d * seg
			pts.append(p)
			widths.append(float(widths[widths.size() - 1]) * 0.45)
			seg *= 0.7
		_stroke(pts, widths, dark, 0.78)


func _branch(rng: RandomNumberGenerator, start: Vector2, dir: Vector2, length: float, width: float, depth: int, params: Dictionary, counter: Array, is_trunk: bool) -> void:
	counter[0] += 1
	if counter[0] > 900:
		return
	var steps: int = 5
	var seg_len: float = length / float(steps)
	var max_depth: int = int(params["max_depth"])
	var tone: float = lerpf(0.84, 1.08, float(max_depth - depth) / float(max_depth))
	var gnarl: float = params["gnarl"]
	var lean: float = params["lean"]
	var p: Vector2 = start
	var d: Vector2 = dir
	var w: float = width
	var pts: Array = [p]
	# Раструб основания: первый узел ствола шире.
	var widths: Array = [width * 1.4 if is_trunk else width]
	for i: int in range(steps):
		var twist: float = rng.randf_range(-gnarl, gnarl) + lean
		d = d.rotated(twist).normalized()
		var t_end: float = float(i + 1) / float(steps)
		w = lerpf(width, width * float(params["taper_along"]), t_end)
		p = p + d * seg_len
		pts.append(p)
		widths.append(w)
	_stroke(pts, widths, params["bark"], tone)
	if depth <= 0 or w < float(params["min_width"]):
		_canopy(rng, p, params)
		return
	if depth <= 2 and rng.randf() < 0.55:
		var half: Dictionary = params.duplicate()
		half["canopy_count"] = int(params["canopy_count"]) / 2
		_canopy(rng, p, half)
	var children: int = rng.randi_range(int(params["children_min"]), int(params["children_max"]))
	var sign: float = 1.0 if rng.randf() < 0.5 else -1.0
	for c: int in range(children):
		var ang: float = (float(params["split_angle"]) + rng.randf_range(-1.0, 1.0) * float(params["split_jitter"])) * sign
		sign = -sign
		var child_dir: Vector2 = d.rotated(ang).normalized()
		var child_len: float = length * float(params["len_ratio"]) * rng.randf_range(0.82, 1.12)
		var child_w: float = w * float(params["w_ratio"])
		_branch(rng, p, child_dir, child_len, child_w, depth - 1, params, counter, false)


# Непрерывная лента по центральной линии: левый край вперёд, правый назад —
# один полигон, без щелей. Шейдинг: левая/правая сторона по свету.
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


func _canopy(rng: RandomNumberGenerator, center: Vector2, params: Dictionary) -> void:
	var count: int = int(params["canopy_count"])
	var radius: float = float(params["canopy_radius"])
	var leaf_size: float = float(params["leaf_size"])
	var palette: Array = params["palette"]
	var tint: Color = params["canopy_tint"]
	var dark: Color = palette[palette.size() - 1]

	# 1) масса-подложка — плотное ядро (светлее прежнего: меньше контраст).
	var mass_n: int = int(maxf(float(count) / 3.0, 4.0))
	for i: int in range(mass_n):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius * 0.80
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.80 - radius * 0.16)
		var c := Color(dark.r * 0.74 * tint.r, dark.g * 0.74 * tint.g, dark.b * 0.74 * tint.b, 0.85)
		_leaves.append({"pts": _blob(center + offset, leaf_size * rng.randf_range(1.4, 2.1), rng), "col": c})

	# 2) детальные листья — мягкий край, узкий диапазон света (низкий контраст).
	var detail: Array = []
	for i: int in range(count):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * radius
		var offset := Vector2(cos(ang) * rad, sin(ang) * rad * 0.82 - radius * 0.16)
		var ndir: Vector2 = offset.normalized() if offset.length() > 0.01 else Vector2.ZERO
		var lit: float = ndir.dot(p_light_dir)
		var shade: float = clampf(0.80 + lit * 0.26, 0.66, 1.14)
		var base_col: Color = palette[rng.randi_range(0, palette.size() - 1)]
		var jit: float = rng.randf_range(0.95, 1.05)
		var col := Color(base_col.r * shade * jit * tint.r, base_col.g * shade * jit * tint.g, base_col.b * shade * jit * tint.b, p_leaf_alpha)
		var sz: float = leaf_size * rng.randf_range(0.65, 1.25)
		detail.append({"pts": _blob(center + offset, sz, rng), "col": col, "k": lit})
	detail.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["k"]) < float(b["k"]))
	for leaf: Dictionary in detail:
		_leaves.append({"pts": leaf["pts"], "col": leaf["col"]})

	# 3) блики — мягкие, приглушённые (не белые), на солнечной стороне.
	var bright: Color = palette[palette.size() - 2]
	var hi_n: int = int(maxf(float(count) / 7.0, 2.0))
	for i: int in range(hi_n):
		var bias: Vector2 = p_light_dir.rotated(rng.randf_range(-0.5, 0.5))
		var rad: float = radius * rng.randf_range(0.25, 0.7)
		var offset := Vector2(bias.x * rad, bias.y * rad - radius * 0.16)
		var col := Color(
			clampf(bright.r * 1.06 * tint.r, 0.0, 1.0),
			clampf(bright.g * 1.06 * tint.g, 0.0, 1.0),
			clampf(bright.b * 1.06 * tint.b, 0.0, 1.0),
			0.88,
		)
		_leaves.append({"pts": _blob(center + offset, leaf_size * rng.randf_range(0.65, 1.0), rng), "col": col})


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
	for blade: Dictionary in _fringe:
		for pt: Vector2 in blade["pts"]:
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


func _palette(name: String) -> Array:
	match name:
		"alien":
			return [Color8(28, 6, 6), Color8(58, 10, 10), Color8(96, 16, 16), Color8(140, 22, 22), Color8(178, 30, 28), Color8(15, 4, 4)]
		"autumn":
			# Приглушённая дусто-тановая осень — низкая насыщенность, под траву.
			return [Color8(120, 74, 34), Color8(150, 94, 42), Color8(178, 120, 58), Color8(198, 150, 82), Color8(214, 176, 108), Color8(96, 60, 30)]
		"ash":
			return [Color8(60, 58, 60), Color8(86, 84, 86), Color8(40, 40, 44), Color8(110, 104, 98), Color8(24, 22, 24), Color8(70, 66, 64)]
		_:
			return [Color8(178, 120, 58)]


func _draw() -> void:
	if _base_ao.size() > 0:
		draw_colored_polygon(_base_ao, Color(0, 0, 0, 0.14))
	for seg: Dictionary in _branches:
		draw_polygon(seg["pts"], seg["cols"])
	for leaf: Dictionary in _leaves:
		draw_colored_polygon(leaf["pts"], leaf["col"])
	# Бахрома травы у комля — поверх низа ствола.
	for blade: Dictionary in _fringe:
		draw_colored_polygon(blade["pts"], blade["col"])
