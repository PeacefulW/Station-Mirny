extends SceneTree

# Tool-экспорт атласа равнинных деревьев (Iteration 1 спеки
# plains_trees_presentation): рендерит N процедурных вариантов в фиксированную
# сетку кадров, считает якорь ОСНОВАНИЯ каждого кадра и пишет:
#   assets/sprites/flora/atlases/plains_trees_atlas.png       (альфа-атлас)
#   assets/sprites/flora/atlases/plains_trees_atlas.json      (кадры + якоря)
#   assets/sprites/flora/atlases/plains_trees_atlas_preview.png (на нейтральной земле)
# Параметры — WorldVisualTreeProfile (данные, не magic numbers). Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/tree_atlas/tree_atlas_export.gd

const ProcTreeGeometry = preload("res://tools/tree_atlas/proc_tree_geometry.gd")
const TreeProfile = preload("res://core/systems/world/world_visual_tree_profile.gd")

const ATLAS_PNG: String = "res://assets/sprites/flora/atlases/plains_trees_atlas.png"
const ATLAS_JSON: String = "res://assets/sprites/flora/atlases/plains_trees_atlas.json"
const ATLAS_PREVIEW: String = "res://assets/sprites/flora/atlases/plains_trees_atlas_preview.png"
const BAKE_MARGIN: int = 8
const GROUND_TONE: Color = Color8(150, 120, 80)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("tree_atlas_export: must run windowed (SubViewport render)")
		quit(1)
		return

	var frame: Vector2i = TreeProfile.ATLAS_FRAME
	var cols: int = TreeProfile.ATLAS_COLUMNS
	var rows: int = TreeProfile.ATLAS_ROWS
	var count: int = TreeProfile.ATLAS_VARIANT_COUNT
	var margin: int = TreeProfile.ATLAS_MARGIN_PX
	var atlas_size := Vector2i(cols * frame.x, rows * frame.y)
	var atlas := Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	var palette: Array[Color] = TreeProfile.palette_autumn()
	var bark: Color = TreeProfile.bark_color()
	var light: Vector2 = TreeProfile.BAKE_LIGHT_DIR
	var frames: Array = []

	for i: int in range(count):
		var vp_data: Dictionary = TreeProfile.variant_params(i)
		var tree: Node2D = ProcTreeGeometry.new()
		tree.set("p_seed", int(vp_data["seed"]))
		tree.set("p_gnarl", float(vp_data["gnarl"]))
		tree.set("p_trunk_len", float(vp_data["trunk_len"]))
		tree.set("p_trunk_w", float(vp_data["trunk_w"]))
		tree.set("p_canopy_count", int(vp_data["canopy_count"]))
		tree.set("p_canopy_radius", float(vp_data["canopy_radius"]))
		tree.set("p_lean", float(vp_data["lean"]))
		tree.set("p_leaf_size", TreeProfile.LEAF_SIZE)
		tree.set("p_leaf_alpha", TreeProfile.LEAF_ALPHA)
		tree.set("p_bark", bark)
		tree.set("p_palette", palette)
		tree.set("p_canopy_tint", vp_data["tint"] as Color)
		tree.set("p_light_dir", light)
		tree.set("base_pos", Vector2.ZERO)
		tree.call("build")

		var bounds: Rect2 = tree.call("get_content_bounds")
		var canvas := Vector2i(int(ceil(bounds.size.x)) + BAKE_MARGIN * 2, int(ceil(bounds.size.y)) + BAKE_MARGIN * 2)
		tree.position = -bounds.position + Vector2(float(BAKE_MARGIN), float(BAKE_MARGIN))
		var sub := SubViewport.new()
		sub.size = canvas
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub.add_child(tree)
		root.add_child(sub)
		for _f: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var raw: Image = sub.get_texture().get_image()
		var used: Rect2i = raw.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			sub.queue_free()
			continue
		var cropped: Image = raw.get_region(used)
		if cropped.get_format() != Image.FORMAT_RGBA8:
			cropped.convert(Image.FORMAT_RGBA8)

		# Масштаб под кадр (только вниз), якорь основания у низа-центра кадра.
		var avail := Vector2(float(frame.x - margin * 2), float(frame.y - margin * 2))
		var scale: float = minf(minf(avail.x / float(cropped.get_width()), avail.y / float(cropped.get_height())), 1.0)
		var nw: int = maxi(int(float(cropped.get_width()) * scale), 1)
		var nh: int = maxi(int(float(cropped.get_height()) * scale), 1)
		cropped.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

		var base_in_crop := tree.position - Vector2(used.position)
		var frame_origin := Vector2i((i % cols) * frame.x, (i / cols) * frame.y)
		var anchor_target := Vector2(float(frame_origin.x) + float(frame.x) * 0.5, float(frame_origin.y) + float(frame.y - margin))
		var top_left := Vector2i(
			int(round(anchor_target.x - base_in_crop.x * scale)),
			int(round(anchor_target.y - base_in_crop.y * scale)),
		)
		# Держим кадр внутри его ячейки.
		top_left.x = clampi(top_left.x, frame_origin.x, frame_origin.x + frame.x - nw)
		top_left.y = clampi(top_left.y, frame_origin.y, frame_origin.y + frame.y - nh)
		atlas.blit_rect(cropped, Rect2i(0, 0, nw, nh), top_left)

		var anchor := Vector2(
			float(top_left.x) + base_in_crop.x * scale,
			float(top_left.y) + base_in_crop.y * scale,
		)
		frames.append({
			"index": i,
			"frame_rect": [frame_origin.x, frame_origin.y, frame.x, frame.y],
			"alpha_bbox": [top_left.x, top_left.y, nw, nh],
			"anchor_local": [int(round(anchor.x)) - frame_origin.x, int(round(anchor.y)) - frame_origin.y],
			"visible_height": nh,
		})
		sub.queue_free()
		await process_frame

	var err: int = atlas.save_png(ATLAS_PNG)
	if err != OK:
		push_error("tree_atlas_export: atlas save failed (err %d)" % err)
		quit(1)
		return

	# Превью на нейтральной «земле».
	var preview := Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	preview.fill(GROUND_TONE)
	preview.blend_rect(atlas, Rect2i(Vector2i.ZERO, atlas_size), Vector2i.ZERO)
	preview.save_png(ATLAS_PREVIEW)

	var meta := {
		"asset": "plains_trees",
		"atlas": "plains_trees_atlas.png",
		"generator": "procedural (tools/tree_atlas/proc_tree_geometry.gd) via WorldVisualTreeProfile",
		"columns": cols,
		"rows": rows,
		"frame_width": frame.x,
		"frame_height": frame.y,
		"frame_count": frames.size(),
		"anchor": "anchor_local is the trunk base point within the frame (px); offset = -anchor_local",
		"baked_grass_fringe": false,
		"baked_shadow": false,
		"spec": "docs/02_system_specs/world/plains_trees_presentation.md",
		"frames": frames,
	}
	var json_file := FileAccess.open(ATLAS_JSON, FileAccess.WRITE)
	json_file.store_string(JSON.stringify(meta, "\t"))
	json_file.close()

	print("tree_atlas_export: wrote %s (%dx%d, %d frames)" % [ProjectSettings.globalize_path(ATLAS_PNG), atlas_size.x, atlas_size.y, frames.size()])
	print("tree_atlas_export: wrote %s" % ProjectSettings.globalize_path(ATLAS_JSON))
	print("tree_atlas_export: wrote %s" % ProjectSettings.globalize_path(ATLAS_PREVIEW))
	print("tree_atlas_export: DONE")
	quit(0)
