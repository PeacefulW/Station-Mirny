shader_type canvas_item;

// Variant D rock visual shader — Phase 1: SDF-driven height + smooth zones.
//
// Architecture port of tools/rimworld-autotile-lab desktop_app/render.rs:
//   mask → SDF → per-pixel height field → height-based zone blending
//   → normals from SDF gradient.
//
// This is the first phase of the real port. Procedural noise material,
// PNG texture inputs, and authoring knobs come in later phases. Right
// now we recover the "smooth shape with mass" that the old generator had,
// which the previous Polygon2D-with-bbox-UV approach could not give.
//
// Source of truth (will be revised): docs/02_system_specs/world/biome_visual_authoring_variant_d.md.

uniform vec4 top_color : source_color = vec4(0.72, 0.70, 0.66, 1.0);
uniform vec4 face_color : source_color = vec4(0.45, 0.42, 0.40, 1.0);
uniform vec4 back_color : source_color = vec4(0.22, 0.20, 0.19, 1.0);

uniform float ledge_contrast : hint_range(0.0, 2.0) = 1.2;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// SDF texture: R8 encoded as (sdf + max_dist) / (2 * max_dist).
// Bound to Polygon2D.texture so canvas_item UV interpolation stays alive.
uniform vec2 mask_size = vec2(16.0, 16.0);
uniform float sdf_max_dist = 16.0;
// Polygon bbox in mask coordinates. UV 0..1 maps to this rectangle.
uniform vec2 bbox_min = vec2(0.0, 0.0);
uniform vec2 bbox_max = vec2(16.0, 16.0);

// Shape knobs (will move to RockVisualResource in Phase 2).
uniform float face_band_cells = 1.4;     // SDF distance over which face zone fades into back/exterior
uniform float plateau_band_cells = 2.2;  // SDF distance from face that becomes solid top plateau
uniform float ledge_width_cells = 0.6;   // Width of the highlight band at top→face seam

// Legacy uniforms kept so existing rock_biome_visual.tres still loads.
uniform float top_to_face_cutoff : hint_range(0.0, 1.0) = 0.62;
uniform float face_to_back_cutoff : hint_range(0.0, 1.0) = 0.28;
uniform float top_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float face_coverage : hint_range(0.0, 1.0) = 0.30;
uniform float back_coverage : hint_range(0.0, 1.0) = 0.15;

float decode_sdf_at(vec2 uv) {
	float t = texture(TEXTURE, uv).r;
	return (t * 2.0 - 1.0) * sdf_max_dist;
}

void fragment() {
	// UV (0..1 over polygon) → mask-space position → SDF sampling UV.
	vec2 mask_pos = mix(bbox_min, bbox_max, UV);
	vec2 sdf_uv = mask_pos / mask_size;

	float sdf = decode_sdf_at(sdf_uv);

	// Discard outside rock region (well outside the border).
	if (sdf < -0.5) {
		discard;
	}

	// Zone weights from SDF distance to boundary:
	//   sdf  ≈ 0           → face (right at the silhouette edge)
	//   sdf  ≈ face_band   → transition into top plateau
	//   sdf  ≥ plateau     → solid top (interior roof)
	//   sdf  < 0 (slightly) → soft fade into back/exterior color
	float face_to_top = smoothstep(face_band_cells, face_band_cells + plateau_band_cells, sdf);
	float face_fade   = smoothstep(-0.5, face_band_cells, sdf);

	// face_weight peaks near sdf == face_band_cells and fades both directions.
	float face_weight = face_fade * (1.0 - face_to_top);
	float top_weight  = face_to_top;
	float back_weight = 1.0 - face_fade;  // boundary fade → back tone

	vec3 color = top_color.rgb * top_weight
		+ face_color.rgb * face_weight
		+ back_color.rgb * back_weight;

	// Ledge highlight at the top→face seam — runs along the silhouette
	// boundary at the height where face transitions into plateau.
	float ledge = 1.0 - smoothstep(0.0, ledge_width_cells, abs(sdf - face_band_cells));
	color += vec3((ledge_contrast - 1.0) * 0.35 * ledge);

	// Normal from SDF gradient — gives the camera-facing relief that the
	// flat-color version lacked. Sample 4 SDF neighbors in normalized UV.
	vec2 step_uv = 1.0 / mask_size;
	float sdf_xp = decode_sdf_at(sdf_uv + vec2(step_uv.x, 0.0));
	float sdf_xn = decode_sdf_at(sdf_uv - vec2(step_uv.x, 0.0));
	float sdf_yp = decode_sdf_at(sdf_uv + vec2(0.0, step_uv.y));
	float sdf_yn = decode_sdf_at(sdf_uv - vec2(0.0, step_uv.y));
	vec3 normal = normalize(vec3(
		(sdf_xn - sdf_xp) * normal_strength,
		(sdf_yn - sdf_yp) * normal_strength,
		2.0
	));

	// Soft fade alpha near boundary so the silhouette doesn't read as a
	// hard pixel-aligned cutout (anti-aliasing approximation).
	float alpha = smoothstep(-0.5, 0.0, sdf);

	color = clamp(color, vec3(0.0), vec3(1.0));

	COLOR = vec4(color, top_color.a * alpha);
	NORMAL_MAP = normal * 0.5 + 0.5;
}
