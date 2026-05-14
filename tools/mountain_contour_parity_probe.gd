extends SceneTree

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
const MountainContourVisualLayer = preload("res://core/systems/world/mountain_contour_visual_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_parity"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR
const VIEWPORT_SIZE: Vector2i = Vector2i(1024, 1024)
const COMPARE_STEP: int = 4

const SILHOUETTE_MISMATCH_RATIO_LIMIT: float = 0.005
const MEAN_RGB_DELTA_LIMIT: float = 0.02
const P95_RGB_DELTA_LIMIT: float = 0.08
const NORMAL_MEAN_ANGLE_DELTA_DEG_LIMIT: float = 5.0
const SEAM_GAP_PIXELS_LIMIT: int = 0

const PARITY_CASE_ORDER: Array[String] = [
	"single_tile",
	"two_by_two_blob",
	"large_blob",
	"large_cave_like_cut",
	"thin_diagonal_opening",
	"inner_dug_hole",
	"straight_south_face",
	"chunk_seam_edge",
	"mined_tile_notch",
]

const PARITY_CASE_ROWS: Dictionary = {
	"single_tile": [
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000100000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
	"two_by_two_blob": [
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000110000000",
		"0000000110000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
	"large_blob": [
		"0000000000000000",
		"0000000000000000",
		"0000001111000000",
		"0000111111110000",
		"0001111111111000",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0001111111111000",
		"0000111111110000",
		"0000001111000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
	"large_cave_like_cut": [
		"0000011100000000",
		"0000111110000000",
		"0001111111000000",
		"0011111111100000",
		"0111111111110000",
		"1111111111111000",
		"1111111111111100",
		"1111111001111100",
		"1111110000111100",
		"1111100000011100",
		"1111110000111110",
		"1111111001111110",
		"0111111111111110",
		"0011111111111100",
		"0001111111111000",
		"0000000000000000",
	],
	"thin_diagonal_opening": [
		"0000000000000000",
		"0000000000000000",
		"0011111111110000",
		"0011111111100000",
		"0011111111000000",
		"0011111110001100",
		"0011111100011100",
		"0011111000111100",
		"0011110001111100",
		"0011100011111100",
		"0011000111111100",
		"0000001111111100",
		"0000011111111100",
		"0000111111111100",
		"0000000000000000",
		"0000000000000000",
	],
	"inner_dug_hole": [
		"0000000000000000",
		"0000000000000000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111001111000",
		"0001111001111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0000000000000000",
		"0000000000000000",
	],
	"straight_south_face": [
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0011111111111100",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
	"chunk_seam_edge": [
		"0000000000000000",
		"0000000000000000",
		"0000000000011111",
		"0000000000111111",
		"0000000001111111",
		"0000000011111111",
		"0000000011111111",
		"0000000011111111",
		"0000000011111111",
		"0000000001111111",
		"0000000000111111",
		"0000000000011111",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
	"mined_tile_notch": [
		"0000000000000000",
		"0000000000000000",
		"0000111111110000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111111111000",
		"0001111101111000",
		"0001111000111000",
		"0001110000011000",
		"0001111111111000",
		"0001111111111000",
		"0000111111110000",
		"0000000000000000",
		"0000000000000000",
		"0000000000000000",
	],
}

const NORMAL_DEBUG_SHADER_CODE: String = """
shader_type canvas_item;

uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;
uniform sampler2D edge_profile_lut : repeat_disable, filter_linear;
uniform sampler2D height_profile_lut : repeat_disable, filter_linear;
uniform float surface_zone = 0.0;
uniform float top_world_scale_px = 224.0;
uniform float face_world_scale_px = 112.0;
uniform float macro_world_scale_px = 448.0;
uniform float texture_scale = 1.0;
uniform float south_height_px = 32.0;
uniform float side_height_px = 0.0;
uniform float rim_width_px = 8.0;
uniform float normal_strength = 8.0;
uniform float normal_detail_strength = 4.0;
uniform float edge_color_strength = 0.35;

varying vec2 world_pos;
varying vec4 contour_attr;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	contour_attr = COLOR;
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 shape_normal, vec3 material_normal) {
	return normalize(vec3(
		shape_normal.xy * 0.65 + material_normal.xy,
		max(0.001, shape_normal.z * material_normal.z)
	));
}

float safe_scale(float scale_px) {
	return max(1.0, scale_px * max(0.01, texture_scale));
}

vec3 sample_top_normal(vec2 top_uv, vec2 macro_uv) {
	vec3 primary = unpack_normal(texture(top_normal_tex, top_uv).rgb);
	vec3 detail = unpack_normal(texture(top_normal_tex, macro_uv + vec2(0.37, 0.19)).rgb);
	return normalize(mix(primary, detail, clamp(normal_detail_strength / 16.0, 0.0, 1.0) * 0.35));
}

vec3 sample_face_normal(vec2 face_uv, vec2 macro_uv) {
	vec3 primary = unpack_normal(texture(face_normal_tex, face_uv).rgb);
	vec3 detail = unpack_normal(texture(face_normal_tex, macro_uv + vec2(0.11, 0.47)).rgb);
	return normalize(mix(primary, detail, clamp(normal_detail_strength / 16.0, 0.0, 1.0) * 0.35));
}

void fragment() {
	float edge_distance = contour_attr.r;
	float face_depth = contour_attr.g;
	float material_zone = surface_zone;
	float edge_profile = texture(edge_profile_lut, vec2(clamp(edge_distance, 0.0, 1.0), 0.5)).r;
	float height_profile = texture(height_profile_lut, vec2(clamp(face_depth, 0.0, 1.0), 0.5)).r;

	vec2 top_uv = world_pos / safe_scale(top_world_scale_px);
	vec2 face_uv = vec2(world_pos.x, world_pos.y + face_depth * max(1.0, south_height_px)) / safe_scale(face_world_scale_px);
	vec2 macro_uv = world_pos / safe_scale(macro_world_scale_px);

	vec3 material_normal = sample_top_normal(top_uv, macro_uv);
	if (material_zone > 0.5) {
		material_normal = sample_face_normal(face_uv, macro_uv);
	}
	if (material_zone >= 1.5 && material_zone < 2.5) {
		material_normal = normalize(mix(sample_top_normal(top_uv, macro_uv), sample_face_normal(face_uv, macro_uv), 0.4));
	}

	vec3 shape_normal = normalize(vec3(
		(edge_profile - 0.5) * max(0.05, edge_color_strength),
		(height_profile - 0.5) * clamp((south_height_px + side_height_px + rim_width_px) / 256.0, 0.05, 0.7),
		1.0
	));
	vec3 final_normal = blend_normals(shape_normal, material_normal);
	final_normal = normalize(mix(vec3(0.0, 0.0, 1.0), final_normal, clamp(normal_strength / 16.0, 0.0, 1.0)));

	COLOR = vec4(final_normal * 0.5 + 0.5, 1.0);
}
"""

var _failed: bool = false
var _errors: Array[String] = []
var _case_reports: Array[Dictionary] = []
var _normal_debug_shader: Shader = null
var _renderer_name: String = "unknown"
var _visual_verification_mode: String = "agent_run_real_viewport"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_prepare_output_dir()
	_renderer_name = DisplayServer.get_name()
	_assert_static_contract()
	if _renderer_name == "headless":
		_visual_verification_mode = "manual_human_verification_required"
		_fail("Mountain contour parity requires a real renderer; headless mode cannot verify textures, normals, outline, or facade composition.")
		_write_report()
		print(JSON.stringify({
			"ok": false,
			"visual_verification_mode": _visual_verification_mode,
			"renderer_name": _renderer_name,
			"errors": _errors,
		}, "\t"))
		quit(1)
		return

	var registry := MountainContourStyleRegistry.new()
	_assert(registry.load_default_styles(), "Parity probe must load canonical mountain contour style.")
	var style: MountainContourStyle = registry.require_style(StringName("mountain"))
	_assert(style != null, "Parity probe requires the canonical mountain style.")
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for parity probe.")
	_assert(world_core != null and world_core.has_method("build_mountain_contour_runtime"), "WorldCore must expose build_mountain_contour_runtime().")

	if _failed or style == null or world_core == null:
		_write_report()
		quit(1)
		return

	_normal_debug_shader = Shader.new()
	_normal_debug_shader.code = NORMAL_DEBUG_SHADER_CODE

	for case_name: String in PARITY_CASE_ORDER:
		await _run_case(case_name, style, world_core)

	_write_report()
	print(JSON.stringify({
		"ok": not _failed,
		"case_count": _case_reports.size(),
		"tolerances": _tolerances(),
	}, "\t"))
	quit(1 if _failed else 0)

func _run_case(case_name: String, style: MountainContourStyle, world_core: Object) -> void:
	var case_error_count_start: int = _errors.size()
	var rows: Array = PARITY_CASE_ROWS.get(case_name, []) as Array
	var case_dir: String = "%s/%s" % [OUTPUT_DIR, case_name]
	_make_dir(case_dir)

	var reference_paths := _reference_paths(case_name)
	for field_name: String in reference_paths.keys():
		_assert(FileAccess.file_exists(reference_paths[field_name]), "%s missing generator reference %s: %s" % [case_name, field_name, reference_paths[field_name]])
	if _errors.size() > case_error_count_start:
		return

	var result: Dictionary = _build_runtime_result(world_core, _build_halo(rows), style)
	var runtime_ready: bool = bool(result.get("ready", false))
	var collision_ready: bool = _runtime_collision_ready(result)
	var face_ready: bool = (result.get("visual_face_vertices", PackedVector2Array()) as PackedVector2Array).size() > 0
	var outline_ready: bool = (result.get("visual_outline_vertices", PackedVector2Array()) as PackedVector2Array).size() > 0
	_assert(runtime_ready, "%s runtime contour result must be ready." % [case_name])
	_assert(collision_ready, "%s contour collision result must be ready." % [case_name])
	_assert(face_ready, "%s must emit face vertices." % [case_name])
	_assert(outline_ready, "%s must emit bottom outline vertices." % [case_name])
	_assert_no_square_only_vertices(case_name, result)
	_assert_outline_and_face_normals(case_name, result, style)
	if case_name == "chunk_seam_edge":
		_assert((int(result.get("seam_touch_mask", 0)) & 2) != 0, "chunk_seam_edge must touch east seam in runtime seam metadata.")

	var runtime_albedo: Image = await _render_runtime_image(style, result, false)
	var runtime_normal: Image = await _render_runtime_image(style, result, true)
	_assert(runtime_albedo != null and not runtime_albedo.is_empty(), "%s runtime albedo render must be readable." % [case_name])
	_assert(runtime_normal != null and not runtime_normal.is_empty(), "%s runtime normal render must be readable." % [case_name])
	if runtime_albedo == null or runtime_albedo.is_empty() or runtime_normal == null or runtime_normal.is_empty():
		return

	var runtime_albedo_path: String = "%s/runtime_albedo.png" % [case_dir]
	var runtime_normal_path: String = "%s/runtime_normal.png" % [case_dir]
	_save_image(runtime_albedo, runtime_albedo_path)
	_save_image(runtime_normal, runtime_normal_path)

	var reference_mask: Image = _load_reference_exact(reference_paths["mask"], runtime_albedo.get_size(), case_name, "mask")
	var reference_albedo: Image = _load_reference_exact(reference_paths["preview"], runtime_albedo.get_size(), case_name, "preview")
	var reference_normal: Image = _load_reference_exact(reference_paths["normal"], runtime_normal.get_size(), case_name, "normal")
	_assert(reference_mask != null, "%s reference mask must load." % [case_name])
	_assert(reference_albedo != null, "%s reference preview must load." % [case_name])
	_assert(reference_normal != null, "%s reference normal must load." % [case_name])
	if reference_mask == null or reference_albedo == null or reference_normal == null:
		return

	var silhouette: Dictionary = _compare_silhouette(case_name, reference_mask, runtime_albedo, "%s/diff_silhouette.png" % [case_dir])
	var albedo: Dictionary = _compare_rgb(reference_albedo, runtime_albedo, reference_mask, "%s/diff_albedo.png" % [case_dir])
	var normal: Dictionary = _compare_normal_angle(reference_normal, runtime_normal, reference_mask, "%s/diff_normal.png" % [case_dir])
	var seam_gap_pixels: int = 0
	if case_name == "chunk_seam_edge":
		seam_gap_pixels = _measure_seam_gap_pixels(reference_mask, runtime_albedo, "east")

	_assert(float(silhouette.get("mismatch_ratio", 1.0)) <= SILHOUETTE_MISMATCH_RATIO_LIMIT, "%s silhouette mismatch exceeds tolerance." % [case_name])
	_assert(float(albedo.get("mean_delta", 1.0)) <= MEAN_RGB_DELTA_LIMIT, "%s albedo mean delta exceeds tolerance." % [case_name])
	_assert(float(albedo.get("p95_delta", 1.0)) <= P95_RGB_DELTA_LIMIT, "%s albedo p95 delta exceeds tolerance." % [case_name])
	_assert(float(normal.get("mean_angle_delta_deg", 180.0)) <= NORMAL_MEAN_ANGLE_DELTA_DEG_LIMIT, "%s normal mean angle delta exceeds tolerance." % [case_name])
	if case_name == "chunk_seam_edge":
		_assert(seam_gap_pixels <= SEAM_GAP_PIXELS_LIMIT, "chunk_seam_edge must not leave any seam gap pixels.")

	_case_reports.append({
		"case": case_name,
		"runtime_ready": runtime_ready,
		"collision_ready": collision_ready,
		"face_ready": face_ready,
		"outline_ready": outline_ready,
		"runtime_albedo": runtime_albedo_path,
		"runtime_normal": runtime_normal_path,
		"diff_silhouette": "%s/diff_silhouette.png" % [case_dir],
		"diff_albedo": "%s/diff_albedo.png" % [case_dir],
		"diff_normal": "%s/diff_normal.png" % [case_dir],
		"result": {
			"solid_sample_count": int(result.get("solid_sample_count", 0)),
			"boundary_edge_count": int(result.get("boundary_edge_count", 0)),
			"seam_touch_mask": int(result.get("seam_touch_mask", 0)),
			"compute_time_usec": int(result.get("compute_time_usec", 0)),
		},
		"silhouette": silhouette,
		"albedo": albedo,
		"normal": normal,
		"seam_gap_pixels": seam_gap_pixels,
	})

func _assert_static_contract() -> void:
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/mountain_contour_runtime.gdshader")
	var layer_source: String = FileAccess.get_file_as_string("res://core/systems/world/mountain_contour_visual_layer.gd")
	var contour_source: String = FileAccess.get_file_as_string("res://gdextension/src/mountain_contour.cpp")
	_assert(shader_source.contains("face_normal_tex"), "Runtime shader must consume face normals for parity.")
	_assert(shader_source.contains("NORMAL_MAP"), "Runtime shader must write normals for lighting/parity.")
	_assert(not shader_source.contains("* top_tint.rgb"), "Runtime shader must not multiply final generator top albedo by top_tint.")
	_assert(not shader_source.contains("* face_tint.rgb"), "Runtime shader must not multiply final generator face albedo by face_tint.")
	_assert(layer_source.contains("MountainContourVisualLayer"), "Parity probe must target the production visual layer.")
	_assert(not layer_source.contains("TileMapLayer"), "MountainContourVisualLayer must not render square TileMap cells.")
	_assert(not contour_source.contains("mask_rgba8"), "Runtime contour result must not reintroduce mask image buffers.")
	_assert(not contour_source.contains("height_r16"), "Runtime contour result must not reintroduce height image buffers.")
	_assert(not contour_source.contains("normal_rgba8"), "Runtime contour result must not reintroduce normal image buffers.")

func _build_runtime_result(world_core: Object, solid_halo: PackedByteArray, style: MountainContourStyle) -> Dictionary:
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		style.to_runtime_geometry_params()
	)
	_assert(result_variant is Dictionary, "build_mountain_contour_runtime() must return Dictionary.")
	if result_variant is Dictionary:
		return result_variant as Dictionary
	return {"ready": false}

func _runtime_collision_ready(result: Dictionary) -> bool:
	return (result.get("collision_loops", []) as Array).size() > 0 \
		and (result.get("collision_aabbs", []) as Array).size() > 0

func _build_halo(rows: Array) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	for index: int in solid_halo.size():
		solid_halo[index] = 0
	for y: int in range(mini(rows.size(), WorldRuntimeConstants.CHUNK_SIZE)):
		var row: String = str(rows[y])
		for x: int in range(mini(row.length(), WorldRuntimeConstants.CHUNK_SIZE)):
			if row.substr(x, 1) == "1":
				solid_halo[(y + 1) * halo_side + x + 1] = 1
	return solid_halo

func _render_runtime_image(style: MountainContourStyle, result: Dictionary, normal_debug: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var scene_root := Node2D.new()
	scene_root.name = "MountainContourParityCase"
	viewport.add_child(scene_root)

	var layer := MountainContourVisualLayer.new()
	layer.name = "MountainContourVisualLayer"
	scene_root.add_child(layer)
	layer.configure(Vector2i.ZERO, style)
	_assert(layer.apply_runtime_result(result), "Visual layer must accept parity runtime result.")
	if normal_debug:
		_apply_normal_debug_materials(layer, style)

	await _settle_frames(4)
	if viewport.get_texture() == null:
		viewport.remove_child(scene_root)
		scene_root.free()
		viewport.free()
		_fail("Real viewport texture is unavailable; visual parity cannot be proven with a proxy render.")
		return null
	var image: Image = viewport.get_texture().get_image()
	viewport.remove_child(scene_root)
	scene_root.free()
	viewport.free()
	if image == null or image.is_empty():
		_fail("Real viewport image is empty; visual parity cannot be proven with a proxy render.")
		return null
	return image

func _apply_normal_debug_materials(layer: Node, style: MountainContourStyle) -> void:
	for child: Node in layer.get_children():
		if child is not MeshInstance2D:
			continue
		var mesh_node := child as MeshInstance2D
		var surface_zone: float = 0.0
		if mesh_node.name.begins_with("face"):
			surface_zone = 1.0
		elif mesh_node.name.begins_with("rim"):
			surface_zone = 2.0
		elif mesh_node.name.begins_with("outline"):
			surface_zone = 3.0
		mesh_node.material = _normal_debug_material(style, surface_zone)

func _normal_debug_material(style: MountainContourStyle, surface_zone: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _normal_debug_shader
	material.set_shader_parameter("surface_zone", surface_zone)
	var shader_params: Dictionary = style.to_shader_params()
	for parameter_name: String in shader_params.keys():
		material.set_shader_parameter(parameter_name, shader_params[parameter_name])
	return material

func _reference_paths(case_name: String) -> Dictionary:
	var prefix: String = "parity_%s" % [case_name]
	return {
		"mask": "%s/%s/generator/%s_reference_mask.png" % [OUTPUT_DIR, case_name, prefix],
		"preview": "%s/%s/generator/%s_reference_preview.png" % [OUTPUT_DIR, case_name, prefix],
		"normal": "%s/%s/generator/%s_reference_normal.png" % [OUTPUT_DIR, case_name, prefix],
	}

func _load_reference_exact(path: String, size: Vector2i, case_name: String, field_name: String) -> Image:
	var image := Image.new()
	var err: Error = image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		return null
	if image.get_size() != size:
		_fail("%s generator %s reference has size %s, expected exact runtime size %s. Regenerate references with exact_generator_runtime_scale." % [
			case_name,
			field_name,
			image.get_size(),
			size,
		])
		return null
	return image

func _compare_silhouette(case_name: String, reference_mask: Image, runtime_image: Image, diff_path: String) -> Dictionary:
	var diff := Image.create(reference_mask.get_width() / COMPARE_STEP, reference_mask.get_height() / COMPARE_STEP, false, Image.FORMAT_RGBA8)
	var samples: int = 0
	var mismatches: int = 0
	var reference_covered: int = 0
	var runtime_covered: int = 0
	var union_covered: int = 0
	for sy: int in diff.get_height():
		for sx: int in diff.get_width():
			var x: int = sx * COMPARE_STEP
			var y: int = sy * COMPARE_STEP
			var ref_on: bool = _reference_mask_on(reference_mask.get_pixel(x, y))
			var runtime_on: bool = runtime_image.get_pixel(x, y).a > 0.05
			samples += 1
			if ref_on:
				reference_covered += 1
			if runtime_on:
				runtime_covered += 1
			if ref_on or runtime_on:
				union_covered += 1
			if ref_on != runtime_on:
				mismatches += 1
				diff.set_pixel(sx, sy, Color(1.0, 0.0, 0.0, 1.0))
			elif ref_on:
				diff.set_pixel(sx, sy, Color(0.0, 0.8, 0.15, 1.0))
			else:
				diff.set_pixel(sx, sy, Color(0.0, 0.0, 0.0, 1.0))
	_save_image(diff, diff_path)
	return {
		"case": case_name,
		"samples": samples,
		"reference_covered": reference_covered,
		"runtime_covered": runtime_covered,
		"union_covered": union_covered,
		"mismatches": mismatches,
		"mismatch_ratio": float(mismatches) / float(maxi(1, union_covered)),
		"viewport_mismatch_ratio": float(mismatches) / float(maxi(1, samples)),
	}

func _compare_rgb(reference_image: Image, runtime_image: Image, reference_mask: Image, diff_path: String) -> Dictionary:
	var diff := Image.create(reference_image.get_width() / COMPARE_STEP, reference_image.get_height() / COMPARE_STEP, false, Image.FORMAT_RGBA8)
	var deltas: Array[float] = []
	for sy: int in diff.get_height():
		for sx: int in diff.get_width():
			var x: int = sx * COMPARE_STEP
			var y: int = sy * COMPARE_STEP
			if not _reference_mask_on(reference_mask.get_pixel(x, y)) and runtime_image.get_pixel(x, y).a <= 0.05:
				diff.set_pixel(sx, sy, Color(0.0, 0.0, 0.0, 1.0))
				continue
			var ref_color: Color = reference_image.get_pixel(x, y)
			var runtime_color: Color = runtime_image.get_pixel(x, y)
			var delta: float = (absf(ref_color.r - runtime_color.r) + absf(ref_color.g - runtime_color.g) + absf(ref_color.b - runtime_color.b)) / 3.0
			deltas.append(delta)
			diff.set_pixel(sx, sy, Color(delta, 0.0, 1.0 - delta, 1.0))
	_save_image(diff, diff_path)
	if deltas.is_empty():
		return {"samples": 0, "mean_delta": 1.0, "p95_delta": 1.0}
	deltas.sort()
	var total: float = 0.0
	for delta: float in deltas:
		total += delta
	var p95_index: int = clampi(int(floor(float(deltas.size() - 1) * 0.95)), 0, deltas.size() - 1)
	return {
		"samples": deltas.size(),
		"mean_delta": total / float(deltas.size()),
		"p95_delta": float(deltas[p95_index]),
	}

func _compare_normal_angle(reference_image: Image, runtime_image: Image, reference_mask: Image, diff_path: String) -> Dictionary:
	var diff := Image.create(reference_image.get_width() / COMPARE_STEP, reference_image.get_height() / COMPARE_STEP, false, Image.FORMAT_RGBA8)
	var angles: Array[float] = []
	for sy: int in diff.get_height():
		for sx: int in diff.get_width():
			var x: int = sx * COMPARE_STEP
			var y: int = sy * COMPARE_STEP
			if not _reference_mask_on(reference_mask.get_pixel(x, y)) and runtime_image.get_pixel(x, y).a <= 0.05:
				diff.set_pixel(sx, sy, Color(0.0, 0.0, 0.0, 1.0))
				continue
			var ref_normal: Vector3 = _normal_from_color(reference_image.get_pixel(x, y))
			var runtime_normal: Vector3 = _normal_from_color(runtime_image.get_pixel(x, y))
			var angle_deg: float = rad_to_deg(acos(clampf(ref_normal.dot(runtime_normal), -1.0, 1.0)))
			angles.append(angle_deg)
			var heat: float = clampf(angle_deg / 45.0, 0.0, 1.0)
			diff.set_pixel(sx, sy, Color(heat, 0.0, 1.0 - heat, 1.0))
	_save_image(diff, diff_path)
	if angles.is_empty():
		return {"samples": 0, "mean_angle_delta_deg": 180.0, "p95_angle_delta_deg": 180.0}
	angles.sort()
	var total: float = 0.0
	for angle: float in angles:
		total += angle
	var p95_index: int = clampi(int(floor(float(angles.size() - 1) * 0.95)), 0, angles.size() - 1)
	return {
		"samples": angles.size(),
		"mean_angle_delta_deg": total / float(angles.size()),
		"p95_angle_delta_deg": float(angles[p95_index]),
	}

func _normal_from_color(color: Color) -> Vector3:
	return Vector3(
		color.r * 2.0 - 1.0,
		color.g * 2.0 - 1.0,
		color.b * 2.0 - 1.0
	).normalized()

func _measure_seam_gap_pixels(reference_mask: Image, runtime_image: Image, edge: String) -> int:
	var gap_pixels: int = 0
	if edge == "east":
		var x: int = maxi(0, reference_mask.get_width() - COMPARE_STEP)
		for y: int in range(0, reference_mask.get_height(), COMPARE_STEP):
			var ref_on: bool = _reference_mask_on(reference_mask.get_pixel(x, y))
			var runtime_on: bool = runtime_image.get_pixel(x, y).a > 0.05
			if ref_on and not runtime_on:
				gap_pixels += 1
	return gap_pixels

func _reference_mask_on(color: Color) -> bool:
	return color.a > 0.05 and (color.r + color.g + color.b) / 3.0 > 0.08

func _assert_no_square_only_vertices(case_name: String, result: Dictionary) -> void:
	var vertices: PackedVector2Array = result.get("visual_top_vertices", PackedVector2Array()) as PackedVector2Array
	_assert(not vertices.is_empty(), "%s must emit runtime top vertices." % [case_name])
	var off_grid_count: int = 0
	for vertex: Vector2 in vertices:
		if not _is_on_tile_grid(vertex.x) or not _is_on_tile_grid(vertex.y):
			off_grid_count += 1
	_assert(off_grid_count > 0, "%s runtime contour must not be only square tile-grid vertices." % [case_name])

func _assert_outline_and_face_normals(case_name: String, result: Dictionary, style: MountainContourStyle) -> void:
	_assert((result.get("visual_face_vertices", PackedVector2Array()) as PackedVector2Array).size() > 0, "%s must emit face vertices." % [case_name])
	_assert((result.get("visual_outline_vertices", PackedVector2Array()) as PackedVector2Array).size() > 0, "%s must emit bottom outline vertices." % [case_name])
	_assert(style.face_normal is Texture2D, "%s style must load face normal texture." % [case_name])
	_assert(style.top_normal is Texture2D, "%s style must load top normal texture." % [case_name])
	_assert(style.face_normal != style.top_normal, "%s face and top normals must be distinct resources." % [case_name])

func _is_on_tile_grid(value: float) -> bool:
	var mod_value: float = fposmod(value, float(WorldRuntimeConstants.TILE_SIZE_PX))
	return is_equal_approx(mod_value, 0.0) or is_equal_approx(mod_value, float(WorldRuntimeConstants.TILE_SIZE_PX))

func _edge_has_runtime_coverage(image: Image, edge: String) -> bool:
	var hit_count: int = 0
	if edge == "east":
		var x: int = maxi(0, image.get_width() - COMPARE_STEP)
		for y: int in range(0, image.get_height(), COMPARE_STEP):
			if image.get_pixel(x, y).a > 0.05:
				hit_count += 1
	return hit_count > 0

func _save_image(image: Image, path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path).replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var err: Error = image.save_png(absolute_path)
	if err != OK:
		_fail("Failed to save image %s: %d" % [absolute_path, err])

func _prepare_output_dir() -> void:
	_make_dir(OUTPUT_DIR)

func _make_dir(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path).replace("\\", "/")
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if err != OK:
		_fail("Failed to create directory %s: %d" % [absolute_path, err])

func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame

func _tolerances() -> Dictionary:
	return {
		"silhouette_mismatch_ratio_limit": SILHOUETTE_MISMATCH_RATIO_LIMIT,
		"mean_rgb_delta_limit": MEAN_RGB_DELTA_LIMIT,
		"p95_rgb_delta_limit": P95_RGB_DELTA_LIMIT,
		"normal_mean_angle_delta_deg_limit": NORMAL_MEAN_ANGLE_DELTA_DEG_LIMIT,
		"seam_gap_pixels_limit": SEAM_GAP_PIXELS_LIMIT,
		"compare_step_px": COMPARE_STEP,
		"reference_scale_contract": "exact_generator_runtime_scale",
		"visual_evidence": "real renderer viewport only; headless mode is manual_human_verification_required",
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)

func _fail(message: String) -> void:
	push_error(message)
	_errors.append(message)
	_failed = true

func _write_report() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(REPORT_PATH).replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var report := {
		"ok": not _failed,
		"visual_verification_mode": _visual_verification_mode,
		"renderer_name": _renderer_name,
		"errors": _errors,
		"tolerances": _tolerances(),
		"cases": _case_reports,
	}
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write parity report %s: %d" % [absolute_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
