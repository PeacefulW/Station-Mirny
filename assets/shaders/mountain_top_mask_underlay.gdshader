shader_type canvas_item;
// Shaded (не unshaded!): гора должна затемняться ночью через CanvasModulate.
// Она НЕ пишет NORMAL_MAP -> Light2D светит её плоско (без двойного рельефа),
// весь рельеф приходит из её собственного шейдинга (light_ambient/light_diffuse).

// Live mountain presentation (model: "facade IS the tile").
// The dark vertical wall is rendered ON the edge mountain tile's own cell -- the
// SOUTH strip of the solid region -- NOT projected down into open space. So the
// visible wall == the real solid tile == collision == mining (WYSIWYG): dig one
// tile, stand on it, the neighbouring mountain tile is the wall right there.
//   - roof (top texture, bump-lit) on interior solid;
//   - wall (face texture, bump-lit) on the south strip of solid
//     up to facade_height_px, without quantized depth bands;
//   - a small COSMETIC roof eave ("козырёк") drawn a few px below the silhouette;
//   - the chunk's own tiles are drawn from a halo mask, with a tiny opaque-underlay
//     clip overlap to cover subpixel seams while camera movement is fractional.

uniform sampler2D top_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D top_normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_normal_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 top_texture_size = vec2(1024.0, 1024.0);
uniform vec2 face_texture_size = vec2(1024.0, 1024.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform bool temporary_disable_terrain_normals = true;
uniform float top_texture_scale = 0.70;
uniform float face_texture_scale = 1.15;
uniform float texture_zoom = 0.7;
uniform float sample_step_px = 1.0;
uniform float facade_height_px = 72.0; // height of the south wall strip WITHIN the solid tile
uniform float overhang_px = 8.0;       // cosmetic roof eave projected below the silhouette
uniform float top_threshold_low = 0.40;
uniform float top_threshold_high = 0.58;
uniform float light_angle_deg = 225.0;
uniform float normal_strength = 1.35;
uniform float top_mask_normal_strength = 0.0;
uniform float material_normal_mix = 0.0;
uniform float material_normal_strength = 0.62;
uniform float light_ambient = 0.68;
uniform float light_diffuse = 0.34;
uniform float projected_shadow_angle_deg = 45.0;
uniform float projected_shadow_length_px = 72.0;
uniform float projected_shadow_opacity = 0.0;
uniform float projected_shadow_softness_px = 28.0;
uniform float projected_shadow_draw_enabled = 1.0;
uniform vec3 projected_shadow_color = vec3(0.030, 0.026, 0.018);
uniform float top_surface_alpha = 1.0;
uniform float wall_surface_alpha = 1.0;
// Neutral by default. The dev-only construction prototype opts a frozen copy
// of the native mask into roof-only composition: the current live mask keeps
// owning facade, floor reveal, collision, and mining.
uniform float roof_overlay_mode = 0.0;
// Production construction roof. TEXTURE is the immutable closed silhouette;
// the live remaining-mass texture is revealed only where the resolver-selected
// connected cavity owns the native C-S cutout. CPU expands tile ownership into
// a native-resolution selector, including a shallow directional mouth aperture;
// the shader samples it nearest + linear for an authored one-sample soft edge.
uniform sampler2D closed_mask_texture : filter_linear;
uniform sampler2D remaining_mask_texture : filter_linear;
uniform sampler2D active_floor_halo_texture : filter_nearest;
uniform sampler2D active_floor_halo_soft_texture : filter_linear;
// Physical mouth directions stay separate from the active-floor selector.
// Active cells become 255 and lose direction bits; this field keeps the
// modular jamb/header stable both outside and inside a cavity.
uniform sampler2D physical_mouth_halo_texture : filter_nearest;
// Uniform gate keeps the mouth SDF and its neighbour texture reads off the
// untouched-mountain / terrain-edge hot path. ChunkView enables it only when
// the tiny selector actually contains a physical surface mouth.
uniform float physical_mouth_enabled = 0.0;
uniform sampler2D any_cutout_halo_texture : filter_nearest;
uniform float roof_component_reveal_enabled = 0.0;
uniform float mouth_portal_half_width = 0.375;
uniform float mouth_portal_depth = 0.27;
uniform float mouth_portal_corner_chamfer = 0.0625;
uniform float mouth_portal_corner_depth = 0.0625;
uniform float mouth_portal_edge_softness = 0.018;
// Hard dark contact line at the wall base; 0 removes it (mountains), the
// shoreline keeps it for a crisp waterline.
uniform float base_outline_strength = 0.92;
// Shoreline band mode (0 = classic full top fill, used by mountains): the top
// surface renders only within ~top_band_px of the open contour, with a noisy
// feathered inner edge, so the world-space ground material keeps the interior.
uniform float top_band_px = 0.0;
uniform float top_band_feather_px = 48.0;
// Cosmetic silhouette warp: bends the visible contour with world-space noise
// so the blurred mask edge reads as crag instead of melt. Presentation-only:
// collision/resource/mining keep reading the raw mask bytes (within the same
// cosmetic margin as the roof eave). Shoreline materials keep 0 so the
// water-fill clip stays in sync with the shore band.
uniform float mask_warp_px = 0.0;
// Sun-relative rim shading: roof edges facing the sun lighten, edges facing
// away darken, so flanks read as volume at any sun angle.
uniform float side_shade_strength = 0.0;
uniform float side_shade_reach_px = 26.0;
// Aperiodic roof macro variation: large tone drift plus sparse vein cracks.
uniform float roof_drift_scale_px = 0.0;
uniform float roof_drift_strength = 0.0;
uniform float roof_vein_strength = 0.0;
// Art-directed roof grade. The source rock stays shared and tileable; the
// mountain material shifts it toward warmer, heavier plateau stone without
// baking biome lighting into the texture itself.
uniform vec3 top_grade_tint = vec3(1.0);
uniform float top_grade_saturation = 1.0;
uniform float top_grade_value = 1.0;
uniform float top_grade_contrast = 1.0;
uniform float top_detail_scale = 2.0;
uniform float top_detail_albedo_strength = 0.0;
uniform float top_detail_normal_mix = 0.0;
uniform float top_detail_normal_strength = 0.35;
uniform float top_cavity_strength = 0.0;
uniform float top_warmth_variation = 0.0;
uniform vec3 top_sun_tint = vec3(1.0);
uniform vec3 top_shadow_tint = vec3(1.0);
// Height terraces: concentric steps derived from the mask distance-to-edge
// (ring probes, like the shore band). Inner plateaus lift slightly, a thin
// dark step line separates the levels. Pure cosmetics: collision, mining, and
// light/visibility gameplay (ADR-0005) are untouched.
uniform float terrace_strength = 0.0;
uniform float terrace_inner_px = 96.0;
uniform float terrace_upper_px = 184.0;
uniform float terrace_wobble_px = 30.0;
uniform vec3 top_dust_tint = vec3(0.90, 0.84, 0.76);
uniform vec3 cleft_color = vec3(0.12, 0.045, 0.018);
uniform vec3 crack_color = vec3(0.055, 0.026, 0.012);
uniform vec3 base_debris_color = vec3(0.18, 0.075, 0.032);
uniform vec3 eave_shadow_color = vec3(0.13, 0.052, 0.022);
// Rim lips are DERIVED from the rock albedo (brightened, sun-warmed via the
// documented shadow-length parameter as the low-sun proxy), not painted with
// fixed colors: the old hardcoded orange rim palette read as glowing neon.
// Sparse orange biofield accents may creep onto lit rims; gated by the same
// world-space field family as the ground's orange patches so mountain accents
// cluster near orange ground regions.
uniform vec3 biofield_rim_color = vec3(0.88, 0.42, 0.12);
uniform float biofield_rim_strength = 0.0;
uniform float biofield_rim_scale_px = 1450.0;
// Wall verticality package: makes the facade read as a vertical cliff instead
// of blending into the roof gravel. All defaults are neutral (= old look) —
// the shared shoreline material must stay untouched; mountains opt in through
// sampling_params. Smooth ramps only: quantized wall-depth bands are forbidden
// (terrain_hybrid_presentation.md — они риббят под тёплым факелом).
uniform float wall_shade_top = 1.0;         // brightness at the roof junction
uniform float wall_shade_bottom = 1.0;      // brightness at the open base edge
uniform vec3 wall_shade_tint = vec3(1.0);   // shade tint creeping toward the base
uniform float wall_desaturate = 0.0;        // shade desaturation toward the base
uniform float wall_streak_strength = 0.0;   // vertical wash/streak tone drift
uniform float wall_crack_strength = 0.0;    // sparse thin vertical crack lines
uniform float wall_texture_v_stretch = 1.0; // >1 stretches face texture features vertically
uniform float face_height_normal_strength = 0.0;
uniform float face_mask_normal_strength = 0.0;
uniform float face_material_normal_mix = 0.0;
uniform float face_detail_scale = 1.0;
uniform float face_detail_albedo_strength = 0.0;
uniform float face_detail_normal_mix = 0.0;
uniform float face_detail_normal_strength = 0.25;
uniform float crest_light_strength = 0.0;   // albedo-derived sun-lit shoulder at the wall top
uniform float crest_height_frac = 0.16;     // crest band height as a fraction of wall height
uniform vec3 crest_warm_tint = vec3(1.16, 0.95, 0.78);
uniform float crest_day_brightness = 1.38;
uniform float silhouette_lit_strength = 0.64;
uniform float silhouette_shadow_strength = 0.64;
uniform float rim_lip_lit_strength = 0.12;
uniform float rim_lip_shadow_strength = 0.12;
uniform vec2 chunk_uv_min = vec2(0.1, 0.1);
uniform vec2 chunk_uv_max = vec2(0.9, 0.9);
uniform vec2 shadow_uv_min = vec2(0.1, 0.1);
uniform vec2 shadow_uv_max = vec2(0.9, 0.9);
uniform vec2 shadow_draw_uv_min = vec2(0.1, 0.1);
uniform vec2 shadow_draw_uv_max = vec2(0.9, 0.9);
uniform float shadow_blend_texels = 4.0;

// Fragment -> light pass gate. Godot's engine LightOccluder2D shadow map is
// binary geometry and showed visible rectangular/line bands on this large mask
// sprite. The mountain shader therefore accepts PointLight2D only on the visible
// wall facade; roof/deep rock behind the contour receives no point-light pass.
varying float point_light_facade_accept;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 base_normal, vec3 detail_normal) {
	return normalize(vec3(
		base_normal.xy + detail_normal.xy * material_normal_strength,
		max(0.001, base_normal.z * max(0.001, detail_normal.z))
	));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gradient (Perlin-style) noise, NOT value noise: value noise is near-linear
// inside each lattice cell, so thresholded features (veins, warped contours)
// grow straight lattice-aligned segments. Gradient noise keeps them curved.
vec2 random_gradient(vec2 p) {
	vec2 h = vec2(hash12(p), hash12(p + vec2(17.31, -41.77))) * 2.0 - 1.0;
	return normalize(h + vec2(0.001, -0.001));
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(random_gradient(i), f);
	float b = dot(random_gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(random_gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(random_gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	// 1.42: stretch raw gradient-noise spread to roughly value-noise spread so
	// the existing tuning (mottle/strata amplitudes) keeps its look.
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.42 * 0.5 + 0.5, 0.0, 1.0);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.56;
	float total = 0.0;
	for (int i = 0; i < 3; i++) {
		v += gradient_noise(p) * a;
		total += a;
		p = p * 2.07 + vec2(17.1, -9.4);
		a *= 0.48;
	}
	return v / max(total, 0.0001);
}

float mask_to_top(float mask_value) {
	return smoothstep(top_threshold_low, top_threshold_high, mask_value);
}

float uv_inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

float uv_rect_inside(vec2 uv, vec2 min_uv, vec2 max_uv) {
	return step(min_uv.x, uv.x) * step(min_uv.y, uv.y) * step(uv.x, max_uv.x) * step(uv.y, max_uv.y);
}

float selector_has_bit(float code, float bit_value) {
	return step(0.5, mod(floor(code / bit_value), 2.0));
}

float mouth_direction_signed_distance(
		float inward,
		float lateral,
		float negative_continues,
		float positive_continues
) {
	float negative_open = step(0.5, negative_continues);
	float positive_open = step(0.5, positive_continues);
	float half_width = clamp(mouth_portal_half_width, 0.12, 0.50);
	float left_edge = 0.5 - half_width;
	float right_edge = 0.5 + half_width;
	float chamfer = max(mouth_portal_corner_chamfer, 0.001);
	float left_loss = clamp(left_edge + chamfer - lateral, 0.0, chamfer)
		* (1.0 - negative_open);
	float right_loss = clamp(lateral - (right_edge - chamfer), 0.0, chamfer)
		* (1.0 - positive_open);
	float cap_loss = max(left_loss, right_loss)
		* (mouth_portal_corner_depth / chamfer);
	float header_sd = inward - (mouth_portal_depth - cap_loss);
	// Continuation removes the corresponding side constraint entirely. Moving
	// it merely to the tile seam would leave a post inside a multi-tile mouth.
	float left_sd = mix(left_edge - lateral, -2.0, negative_open);
	float right_sd = mix(lateral - right_edge, -2.0, positive_open);
	return max(header_sd, max(left_sd, right_sd));
}

float sample_physical_mouth_direction_code(vec2 selector_uv) {
	return floor(texture(physical_mouth_halo_texture, selector_uv).r * 255.0 + 0.5);
}

float sample_mouth_signed_distance_for_cell(
		float selector_code,
		vec2 source_selector_uv,
		vec2 cell_uv
) {
	// Codes 1/2/4/8 are N/E/S/W. Active component cells use 255 and skip
	// this path. fract() gives a stable sub-tile coordinate at any halo size.
	vec2 selector_size = vec2(textureSize(physical_mouth_halo_texture, 0));
	float negative_continues = selector_has_bit(selector_code, 16.0);
	float positive_continues = selector_has_bit(selector_code, 32.0);
	float north_bit = selector_has_bit(selector_code, 1.0);
	float east_bit = selector_has_bit(selector_code, 2.0);
	float south_bit = selector_has_bit(selector_code, 4.0);
	float west_bit = selector_has_bit(selector_code, 8.0);
	float direction_count = north_bit + east_bit + south_bit + west_bit;
	if (direction_count < 0.5) {
		return 2.0;
	}
	// Bit 64 marks the one exterior cell carrying a projected copy of the
	// source mouth. Subtracting one tile from inward distance extends the same
	// straight aperture through CLOSED's organic fringe without neighbour
	// searches in every effective-mask probe.
	float exterior_projection = selector_has_bit(selector_code, 64.0);
	float north_negative = negative_continues;
	float north_positive = positive_continues;
	float east_negative = negative_continues;
	float east_positive = positive_continues;
	float south_negative = negative_continues;
	float south_positive = positive_continues;
	float west_negative = negative_continues;
	float west_positive = positive_continues;
	if (direction_count > 1.5) {
		// Mixed organic corner: CPU intentionally stored no shared continuation
		// bits. Resolve lateral neighbours per direction only in this rare mouth
		// fragment, so SOUTH continuity cannot deepen EAST (or vice versa).
		vec2 selector_texel = 1.0 / selector_size;
		vec2 left_uv = source_selector_uv - vec2(selector_texel.x, 0.0);
		vec2 right_uv = source_selector_uv + vec2(selector_texel.x, 0.0);
		vec2 up_uv = source_selector_uv - vec2(0.0, selector_texel.y);
		vec2 down_uv = source_selector_uv + vec2(0.0, selector_texel.y);
		float left_code = sample_physical_mouth_direction_code(left_uv) * uv_inside(left_uv);
		float right_code = sample_physical_mouth_direction_code(right_uv) * uv_inside(right_uv);
		float up_code = sample_physical_mouth_direction_code(up_uv) * uv_inside(up_uv);
		float down_code = sample_physical_mouth_direction_code(down_uv) * uv_inside(down_uv);
		north_negative = selector_has_bit(left_code, 1.0);
		north_positive = selector_has_bit(right_code, 1.0);
		south_negative = selector_has_bit(left_code, 4.0);
		south_positive = selector_has_bit(right_code, 4.0);
		east_negative = selector_has_bit(up_code, 2.0);
		east_positive = selector_has_bit(down_code, 2.0);
		west_negative = selector_has_bit(up_code, 8.0);
		west_positive = selector_has_bit(down_code, 8.0);
	}
	float inactive_sd = 2.0;
	float north = mix(inactive_sd, mouth_direction_signed_distance(
		cell_uv.y - exterior_projection, cell_uv.x, north_negative, north_positive
	), north_bit);
	float east = mix(inactive_sd, mouth_direction_signed_distance(
		1.0 - cell_uv.x - exterior_projection, cell_uv.y, east_negative, east_positive
	), east_bit);
	float south = mix(inactive_sd, mouth_direction_signed_distance(
		1.0 - cell_uv.y - exterior_projection, cell_uv.x, south_negative, south_positive
	), south_bit);
	float west = mix(inactive_sd, mouth_direction_signed_distance(
		cell_uv.x - exterior_projection, cell_uv.y, west_negative, west_positive
	), west_bit);
	return min(min(north, east), min(south, west));
}

float sample_physical_mouth_signed_distance(vec2 selector_uv) {
	float inside = uv_inside(selector_uv);
	if (inside < 0.5) {
		return 2.0;
	}
	vec2 selector_size = vec2(textureSize(physical_mouth_halo_texture, 0));
	vec2 cell_uv = fract(selector_uv * selector_size);
	float selector_code = sample_physical_mouth_direction_code(selector_uv);
	return sample_mouth_signed_distance_for_cell(selector_code, selector_uv, cell_uv);
}

float sample_physical_mouth_shape(vec2 selector_uv) {
	float mouth_sd = sample_physical_mouth_signed_distance(selector_uv);
	float edge_soft = max(mouth_portal_edge_softness, 0.002);
	return 1.0 - smoothstep(-edge_soft, edge_soft, mouth_sd);
}

float sample_effective_mountain_mask(vec2 uv) {
	float closed_mask = texture(closed_mask_texture, uv).r;
	if (roof_component_reveal_enabled < 0.5) {
		return closed_mask;
	}
	float inside = uv_inside(uv);
	float selector_raw = texture(active_floor_halo_texture, uv).r;
	float selector_code = floor(selector_raw * 255.0 + 0.5);
	float active_exact = step(127.5, selector_code) * inside;
	// Direction codes are <= 63/255 and therefore cannot pollute this binary
	// component feather even though both fields share one tiny L8 texture.
	float active_soft = smoothstep(0.25, 0.75, texture(active_floor_halo_soft_texture, uv).r) * inside;
	float mouth_reveal = 0.0;
	if (physical_mouth_enabled > 0.5) {
		mouth_reveal = sample_physical_mouth_shape(uv);
	}
	float foreign_cutout = step(0.5, texture(any_cutout_halo_texture, uv).r) * (1.0 - active_exact);
	float reveal = max(max(active_exact, mouth_reveal), active_soft * (1.0 - foreign_cutout));
	float remaining_mask = texture(remaining_mask_texture, uv).r;
	return mix(closed_mask, remaining_mask, clamp(reveal, 0.0, 1.0));
}

float shadow_axis_owner_weight(float value, float min_value, float max_value, float texel_size, float blend_texels) {
	float blend_uv = max(texel_size * max(blend_texels, 1.0), 0.0001);
	float left = smoothstep(min_value - blend_uv, min_value + blend_uv, value);
	float right = 1.0 - smoothstep(max_value - blend_uv, max_value + blend_uv, value);
	return min(left, right);
}

float shadow_owner_weight(vec2 uv, vec2 min_uv, vec2 max_uv, vec2 texel, float blend_texels) {
	float wx = shadow_axis_owner_weight(uv.x, min_uv.x, max_uv.x, texel.x, blend_texels);
	float wy = shadow_axis_owner_weight(uv.y, min_uv.y, max_uv.y, texel.y, blend_texels);
	// Multiply (not min): the 2 edge / 4 corner chunks sharing a seam then hold
	// weights that sum to exactly 1, which the ownership alpha below relies on.
	return wx * wy;
}

// Minimum mask solidity over an 8-direction ring: 1.0 means "no open edge
// within this radius", i.e. the pixel sits deeper than radius_texels inside
// the massif. The smooth falloff of the minimum doubles as the step ramp.
float ring_interior(vec2 uv, vec2 texel, float radius_texels) {
	float interior = 1.0;
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(texel.x, 0.0) * radius_texels)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv - vec2(texel.x, 0.0) * radius_texels)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(0.0, texel.y) * radius_texels)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv - vec2(0.0, texel.y) * radius_texels)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(texel.x, texel.y) * radius_texels * 0.7071)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(-texel.x, texel.y) * radius_texels * 0.7071)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(texel.x, -texel.y) * radius_texels * 0.7071)));
	interior = min(interior, mask_to_top(sample_effective_mountain_mask(uv + vec2(-texel.x, -texel.y) * radius_texels * 0.7071)));
	return interior;
}

vec2 visual_mask_uv(vec2 uv, vec2 texel, vec2 wp) {
	if (mask_warp_px <= 0.001) {
		return uv;
	}
	// World-space, chunk-agnostic warp: broad swing bends the contour, fine
	// jitter chips it. Both sides of a chunk seam compute identical offsets.
	vec2 broad = vec2(
		fbm2(wp / 210.0 + vec2(-13.0, 71.0)),
		fbm2(wp / 190.0 + vec2(47.0, -29.0))
	) - vec2(0.5);
	vec2 fine = vec2(
		fbm2(wp / 64.0 + vec2(93.0, 8.0)),
		fbm2(wp / 58.0 + vec2(-35.0, 102.0))
	) - vec2(0.5);
	vec2 warp = broad * 0.72 + fine * 0.28;
	return clamp(
		uv + warp * 2.0 * texel * (mask_warp_px / max(sample_step_px, 0.001)),
		vec2(0.0),
		vec2(1.0)
	);
}

void fragment() {
	float body_area = uv_rect_inside(UV, chunk_uv_min, chunk_uv_max);
	float shadow_draw_area = uv_rect_inside(UV, shadow_draw_uv_min, shadow_draw_uv_max);
	float overlay_mode = clamp(roof_overlay_mode, 0.0, 1.0);
	// Body uses a tiny opaque overlap; projected shadow uses a wider blended overlap.
	if (max(body_area, shadow_draw_area) < 0.5) {
		discard;
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = 1.0 / tex_size;
	vec2 world_px = world_origin_px + UV * tex_size * sample_step_px;
	vec2 warped_base_uv = visual_mask_uv(UV, texel, world_px);
	// Preserve the authored straight portal through the global crag warp. The
	// blend is SDF-local (not tile-local), so it cannot expose a square seam in
	// the surrounding roof while the threshold/jambs stay geometrically flat.
	float raw_mouth_sd = 2.0;
	if (physical_mouth_enabled > 0.5) {
		raw_mouth_sd = sample_physical_mouth_signed_distance(UV);
	}
	float mouth_unwarp = 1.0 - smoothstep(0.30, 0.48, abs(raw_mouth_sd));
	vec2 base_uv = mix(warped_base_uv, UV, mouth_unwarp);
	float top_here = mask_to_top(sample_effective_mountain_mask(base_uv));
	float top_l = mask_to_top(sample_effective_mountain_mask(base_uv - vec2(texel.x, 0.0)));
	float top_r = mask_to_top(sample_effective_mountain_mask(base_uv + vec2(texel.x, 0.0)));
	float top_u = mask_to_top(sample_effective_mountain_mask(base_uv - vec2(0.0, texel.y)));
	float top_d = mask_to_top(sample_effective_mountain_mask(base_uv + vec2(0.0, texel.y)));
	vec2 mask_grad = vec2(top_l - top_r, top_u - top_d);
	float wall_texels = max(1.0, facade_height_px / sample_step_px);
	float overhang_texels = max(1.0, overhang_px / sample_step_px);

	// SOLID pixel: continuous distance DOWN (south) to the open silhouette edge.
	float edge_below = -1.0;
	if (top_here >= 0.5) {
		float prev = top_here;
		int steps = int(min(wall_texels + 2.0, 96.0));
		for (int d = 1; d <= steps; d++) {
			float cur = mask_to_top(sample_effective_mountain_mask(base_uv + vec2(0.0, texel.y * float(d))));
			if (cur < 0.5 && prev >= 0.5) {
				float t = (prev - 0.5) / max(prev - cur, 0.0001);
				edge_below = float(d) - 1.0 + t;
				break;
			}
			prev = cur;
		}
	}
	float wall_valid = step(0.0, edge_below);
	float wall_solid_mask = smoothstep(0.38, 0.66, top_here);
	float wall_base_fade = smoothstep(-0.50, 0.15, edge_below);
	float wall_top_fade = 1.0 - smoothstep(wall_texels - 1.65, wall_texels + 1.65, edge_below);
	float structural_wall_mask = body_area * wall_valid * wall_solid_mask * wall_base_fade * wall_top_fade;
	// A frozen roof copy must not repaint the structural south facade. Removing
	// the same band from its top surface lets the excavated live BASE show the
	// real mouth while the deeper cavity remains covered by the closed roof.
	float roof_surface_mask = top_here * body_area * (1.0 - structural_wall_mask * overlay_mode);
	float wall_mask = structural_wall_mask * (1.0 - overlay_mode);
	bool is_wall = wall_mask > 0.02;

	// OPEN pixel: cosmetic roof eave just below the silhouette ("козырёк").
	// overhang_px <= 0.5 disables the eave entirely (mountains stand directly
	// on the foothill apron; the shoreline keeps its thin lip).
	float overhang = 0.0;
	if (top_here < 0.5 && overhang_px > 0.5) {
		int osteps = int(min(overhang_texels + 2.0, 24.0));
		for (int d = 1; d <= osteps; d++) {
			if (mask_to_top(sample_effective_mountain_mask(base_uv - vec2(0.0, texel.y * float(d)))) >= 0.5) {
				overhang = 1.0 - smoothstep(0.0, overhang_texels, float(d) - 1.0);
				break;
			}
		}
	}
	// BASE owns the one physical eave. The construction ROOF is a cover-only
	// contribution and must not double the translucent rim.
	overhang *= body_area * (1.0 - overlay_mode);

	float coverage = max(roof_surface_mask, overhang);
	float projected_shadow = 0.0;
	float shadow_open_space = (1.0 - smoothstep(0.08, 0.56, top_here)) * (1.0 - clamp(overhang, 0.0, 1.0) * 0.92);
	if (projected_shadow_draw_enabled > 0.5 && projected_shadow_opacity > 0.001 && projected_shadow_length_px > 1.0 && shadow_open_space > 0.001) {
		float shadow_a = radians(projected_shadow_angle_deg);
		vec2 shadow_dir = normalize(vec2(cos(shadow_a), sin(shadow_a)));
		vec2 shadow_side = vec2(-shadow_dir.y, shadow_dir.x);
		float max_shadow_texels = max(projected_shadow_length_px / max(sample_step_px, 0.001), 1.0);
		float soft_shadow_texels = max(projected_shadow_softness_px / max(sample_step_px, 0.001), 1.0);
		float shadow_sum = 0.0;
		float shadow_weight_sum = 0.0;
		for (int i = 1; i <= 14; i++) {
			float t = (float(i) - 0.5) / 14.0;
			float dist_texels = max_shadow_texels * t;
			float side_texels = soft_shadow_texels * (0.28 + t * 1.10);
			vec2 base_uv = UV - shadow_dir * texel * dist_texels;
			vec2 left_uv = base_uv + shadow_side * texel * side_texels;
			vec2 right_uv = base_uv - shadow_side * texel * side_texels;
			vec2 wide_left_uv = base_uv + shadow_side * texel * side_texels * 1.85;
			vec2 wide_right_uv = base_uv - shadow_side * texel * side_texels * 1.85;
			float center_w = uv_inside(base_uv);
			float left_w = uv_inside(left_uv);
			float right_w = uv_inside(right_uv);
			float wide_left_w = uv_inside(wide_left_uv);
			float wide_right_w = uv_inside(wide_right_uv);
			float center = mask_to_top(sample_effective_mountain_mask(base_uv)) * center_w;
			float left = mask_to_top(sample_effective_mountain_mask(left_uv)) * left_w;
			float right = mask_to_top(sample_effective_mountain_mask(right_uv)) * right_w;
			float wide_left = mask_to_top(sample_effective_mountain_mask(wide_left_uv)) * wide_left_w;
			float wide_right = mask_to_top(sample_effective_mountain_mask(wide_right_uv)) * wide_right_w;
			float source = center * 0.42 + (left + right) * 0.20 + (wide_left + wide_right) * 0.09;
			float source_weight = center_w * 0.42 + (left_w + right_w) * 0.20 + (wide_left_w + wide_right_w) * 0.09;
			float distance_fade = pow(1.0 - t, 1.45);
			float weight = mix(1.18, 0.42, t) * distance_fade;
			shadow_sum += source * weight;
			shadow_weight_sum += source_weight * weight;
		}
		projected_shadow = smoothstep(0.045, 0.66, shadow_sum / max(shadow_weight_sum, 0.0001));
		float shadow_breakup = 0.92 + fbm2(world_px / 460.0 + vec2(8.0, -19.0)) * 0.08;
		float shadow_strength = clamp(projected_shadow * shadow_open_space * projected_shadow_opacity * shadow_breakup, 0.0, projected_shadow_opacity);
		float owner_weight = shadow_draw_area * shadow_owner_weight(UV, shadow_uv_min, shadow_uv_max, texel, shadow_blend_texels);
		// Split-ownership alpha: in the seam band the neighbouring chunks each
		// draw a weighted share of the SAME world-space shadow value. Plain
		// w * s shares alpha-composite to s - w*(1-w)*s^2 (a brighter band along
		// every chunk seam). 1 - (1 - s)^w composites to exactly s when the
		// participating weights sum to 1.
		projected_shadow = 1.0 - pow(max(1.0 - shadow_strength, 0.0001), owner_weight);
	}
	if (coverage <= 0.01 && projected_shadow <= 0.002) {
		discard;
	}

	float tz = max(texture_zoom, 0.01);
	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.62));
	float grad_px = 2.0;
	float macro = fbm2(world_px / 920.0);
	float mid_mottle = fbm2(world_px / 210.0 + vec2(3.7, 15.2));
	float small_mottle = fbm2(world_px / 86.0 + vec2(-21.0, 5.0));
	float top_variation = 0.94 + (macro - 0.5) * 0.18 + (mid_mottle - 0.5) * 0.08;
	if (roof_drift_strength > 0.001 && roof_drift_scale_px > 1.0) {
		// Large aperiodic tone drift so big massifs stop reading as one flat
		// slab from far away (same trick as the ground material).
		float roof_drift = fbm2(world_px / roof_drift_scale_px + vec2(7.3, -2.9));
		top_variation *= mix(1.0 - roof_drift_strength, 1.0 + roof_drift_strength, roof_drift);
	}

	// Roof (top) -- mask-shape normal plus restrained texture relief.
	vec2 top_uv = world_px * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dx = (world_px + vec2(grad_px, 0.0)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dy = (world_px + vec2(0.0, grad_px)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	// A rotated high-frequency copy restores close-up texel density without
	// shrinking the large plate layer that carries the mountain silhouette.
	vec2 top_detail_world_px = vec2(-world_px.y, world_px.x) + vec2(431.0, 217.0);
	vec2 top_detail_uv = top_detail_world_px * top_texture_scale * max(top_detail_scale, 1.0) / tz / max(top_texture_size, vec2(1.0));
	vec4 top_col = texture(top_texture, top_uv);
	vec4 top_detail_col = texture(top_texture, top_detail_uv);
	float top_height = luma(top_col.rgb);
	float top_detail_luma = luma(top_detail_col.rgb);
	top_col.rgb *= top_variation;
	top_col.rgb = mix(top_col.rgb, top_col.rgb * top_dust_tint, smoothstep(0.68, 0.96, macro) * 0.20);
	float detail_relief = smoothstep(0.24, 0.76, top_detail_luma);
	top_col.rgb *= mix(
		1.0 - top_detail_albedo_strength,
		1.0 + top_detail_albedo_strength,
		detail_relief
	);
	float warmth_field = clamp(macro * 0.62 + mid_mottle * 0.38, 0.0, 1.0);
	vec3 field_tint = mix(vec3(0.98, 1.0, 1.025), vec3(1.065, 1.0, 0.90), warmth_field);
	top_col.rgb *= mix(vec3(1.0), field_tint, top_warmth_variation);
	float cavity = 1.0 - smoothstep(0.21, 0.48, mix(top_height, top_detail_luma, 0.28));
	top_col.rgb *= 1.0 - cavity * top_cavity_strength;
	float graded_top_luma = luma(top_col.rgb);
	top_col.rgb = mix(vec3(graded_top_luma), top_col.rgb, clamp(top_grade_saturation, 0.0, 1.5));
	top_col.rgb = clamp(
		(top_col.rgb - vec3(0.5)) * max(top_grade_contrast, 0.0) + vec3(0.5),
		vec3(0.0),
		vec3(1.0)
	);
	top_col.rgb *= top_grade_tint * top_grade_value;
	vec3 top_n = vec3(0.0, 0.0, 1.0);
	if (!temporary_disable_terrain_normals) {
		// Height derivatives must come from the ungraded source. Comparing a
		// tinted center sample with raw neighbours created a false constant tilt
		// and was the reason mountain normals had to stay disabled.
		float h_c = top_height;
		float h_x = luma(texture(top_texture, top_uv_dx).rgb);
		float h_y = luma(texture(top_texture, top_uv_dy).rgb);
		top_n = normalize(vec3(
			mask_grad.x * top_mask_normal_strength + (h_c - h_x) * normal_strength * 0.38,
			mask_grad.y * top_mask_normal_strength + (h_c - h_y) * normal_strength * 0.38,
			1.0
		));
		if (material_normal_mix > 0.001) {
			vec3 top_detail_n = unpack_normal(texture(top_normal_texture, top_uv).rgb);
			top_n = normalize(mix(top_n, blend_normals(top_n, top_detail_n), clamp(material_normal_mix, 0.0, 1.0)));
		}
		if (top_detail_normal_mix > 0.001) {
			vec3 fine_n = unpack_normal(texture(top_normal_texture, top_detail_uv).rgb);
			// UV is rotated 90 degrees, so rotate the tangent-space XY response
			// back into world-screen axes before combining it with the broad form.
			fine_n = normalize(vec3(fine_n.y, -fine_n.x, fine_n.z));
			vec3 detailed_n = normalize(vec3(
				top_n.xy + fine_n.xy * top_detail_normal_strength,
				max(0.001, top_n.z * max(0.001, fine_n.z))
			));
			top_n = normalize(mix(top_n, detailed_n, clamp(top_detail_normal_mix, 0.0, 1.0)));
		}
	}
	float top_ndl = clamp(dot(top_n, light_dir), 0.0, 1.0);
	vec3 top_light_tint = mix(top_shadow_tint, top_sun_tint, smoothstep(0.08, 0.88, top_ndl));
	vec3 top_lit = top_col.rgb * (light_ambient + light_diffuse * top_ndl) * top_light_tint;
	if (terrace_strength > 0.001 && top_here >= 0.5) {
		// Concentric height terraces from distance-to-edge ring probes. The
		// noise-wobbled radii keep the step contours organic and parallel to
		// the warped silhouette (both feed off the same world-space mask).
		float terrace_wobble = (fbm2(world_px / 300.0 + vec2(-9.0, 37.0)) - 0.5) * 2.0 * terrace_wobble_px;
		float inner_texels = max((terrace_inner_px + terrace_wobble) / max(sample_step_px, 0.001), 1.0);
		float upper_texels = max((terrace_upper_px + terrace_wobble * 1.4) / max(sample_step_px, 0.001), 1.0);
		float inner_level = smoothstep(0.30, 0.72, ring_interior(base_uv, texel, inner_texels));
		float upper_level = smoothstep(0.30, 0.72, ring_interior(base_uv, texel, upper_texels));
		float plateau_lift = (inner_level * 0.075 + upper_level * 0.085) * terrace_strength;
		// Asymmetric ledge per level: a dark base shadow just below the step
		// and a lit lip just above it read as real relief, unlike a symmetric
		// dark line.
		float step_shadow = max(
			smoothstep(0.16, 0.46, inner_level) * (1.0 - smoothstep(0.46, 0.60, inner_level)),
			smoothstep(0.16, 0.46, upper_level) * (1.0 - smoothstep(0.46, 0.60, upper_level))
		);
		float step_lip = max(
			smoothstep(0.50, 0.64, inner_level) * (1.0 - smoothstep(0.72, 0.92, inner_level)),
			smoothstep(0.50, 0.64, upper_level) * (1.0 - smoothstep(0.72, 0.92, upper_level))
		);
		float step_breakup = 0.55 + 0.45 * small_mottle;
		top_lit *= (1.0 + plateau_lift)
			* (1.0 - step_shadow * 0.30 * terrace_strength * step_breakup)
			* (1.0 + step_lip * 0.14 * terrace_strength * step_breakup);
	}
	if (roof_vein_strength > 0.001) {
		// Sparse crack veins: a thin iso-band of gradient fbm, gated by a
		// second field so the lines break up instead of running forever.
		float vein_base = fbm2(world_px / 760.0 + vec2(-41.0, 23.0));
		float vein_line = smoothstep(0.475, 0.5, vein_base) * (1.0 - smoothstep(0.5, 0.525, vein_base));
		float vein_gate = smoothstep(0.42, 0.62, fbm2(world_px / 340.0 + vec2(19.0, 57.0)));
		top_lit *= 1.0 - vein_line * vein_gate * roof_vein_strength;
	}
	if (side_shade_strength > 0.001 && top_here >= 0.5) {
		// Sun-relative flank shading: probe the mask along the light direction.
		// A rim opening toward the sun is lit, a rim opening away falls into
		// shade, so east/west flanks gain volume and track the time of day.
		vec2 sun_step = vec2(cos(a), sin(a)) * texel * (side_shade_reach_px / max(sample_step_px, 0.001));
		float open_toward = 1.0 - mask_to_top(sample_effective_mountain_mask(base_uv + sun_step));
		float open_away = 1.0 - mask_to_top(sample_effective_mountain_mask(base_uv - sun_step));
		float side_signed = open_toward - open_away;
		float rim_breakup = 0.72 + small_mottle * 0.56;
		top_lit *= 1.0
			+ max(side_signed, 0.0) * side_shade_strength * 0.65 * rim_breakup
			- max(-side_signed, 0.0) * side_shade_strength * rim_breakup;
	}

	// Wall -- controlled relief and sparse base chips. The face texture samples
	// vertically stretched world space (v_stretch > 1): ledge features elongate
	// downward, so the wall stops mirroring the isotropic roof gravel.
	vec2 face_world_px = vec2(world_px.x, world_px.y / max(wall_texture_v_stretch, 0.001));
	vec2 face_uv = face_world_px * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dx = (face_world_px + vec2(grad_px, 0.0)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dy = (face_world_px + vec2(0.0, grad_px)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_detail_uv = (face_world_px + vec2(173.0, 619.0)) * face_texture_scale * max(face_detail_scale, 1.0) / tz / max(face_texture_size, vec2(1.0));
	vec4 face_col = texture(face_texture, face_uv);
	vec4 face_detail_col = texture(face_texture, face_detail_uv);
	float face_height = luma(face_col.rgb);
	float face_detail_luma = luma(face_detail_col.rgb);
	face_col.rgb *= 0.86 + (macro - 0.5) * 0.10;
	face_col.rgb *= mix(
		1.0 - face_detail_albedo_strength,
		1.0 + face_detail_albedo_strength,
		smoothstep(0.22, 0.78, face_detail_luma)
	);
	vec3 face_n = vec3(0.0, 0.0, 1.0);
	if (!temporary_disable_terrain_normals) {
		float fh_c = face_height;
		float fh_x = luma(texture(face_texture, face_uv_dx).rgb);
		float fh_y = luma(texture(face_texture, face_uv_dy).rgb);
		face_n = normalize(vec3(
			mask_grad.x * face_mask_normal_strength + (fh_c - fh_x) * face_height_normal_strength,
			mask_grad.y * face_mask_normal_strength + (fh_c - fh_y) * face_height_normal_strength,
			1.0
		));
		if (face_material_normal_mix > 0.001) {
			vec3 face_detail_n = unpack_normal(texture(face_normal_texture, face_uv).rgb);
			face_n = normalize(mix(face_n, blend_normals(face_n, face_detail_n), clamp(face_material_normal_mix, 0.0, 1.0)));
		}
		if (face_detail_normal_mix > 0.001) {
			vec3 fine_face_n = unpack_normal(texture(face_normal_texture, face_detail_uv).rgb);
			vec3 detailed_face_n = normalize(vec3(
				face_n.xy + fine_face_n.xy * face_detail_normal_strength,
				max(0.001, face_n.z * max(0.001, fine_face_n.z))
			));
			face_n = normalize(mix(face_n, detailed_face_n, clamp(face_detail_normal_mix, 0.0, 1.0)));
		}
	}
	float face_ndl = clamp(dot(face_n, light_dir), 0.0, 1.0);
	vec3 face_light_tint = mix(top_shadow_tint, top_sun_tint, smoothstep(0.08, 0.88, face_ndl));
	vec3 facade_color = face_col.rgb * (light_ambient + light_diffuse * face_ndl) * face_light_tint;

	vec3 color = top_lit;
	// Gate the roof by body_area (the tiny chunk overlap) like walls/overhang/
	// coverage already are. Without this the roof's translucent silhouette edge
	// leaked into the WIDE projected-shadow overlap band (MASK_SHADOW_CHUNK_OVERLAP_PX,
	// 48 px), so two neighbouring chunk sprites double-composited their edges into a
	// brighter rectangular seam — very visible once the torch lit the rock at night.
	float out_alpha = roof_surface_mask * top_col.a * top_surface_alpha;

	if (top_band_px > 0.5) {
		// Shoreline band: keep the top fill only near the open contour. The
		// nearest-open probe at a noise-wobbled radius gives an irregular,
		// packed-shore inner edge that dissolves into the ground material.
		float band_wobble = (fbm2(world_px / 240.0 + vec2(27.0, -53.0)) - 0.5) * 2.0 * top_band_feather_px;
		float band_texels = max((top_band_px + band_wobble) / max(sample_step_px, 0.001), 1.0);
		float interior = top_here;
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(texel.x, 0.0) * band_texels)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV - vec2(texel.x, 0.0) * band_texels)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(0.0, texel.y) * band_texels)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV - vec2(0.0, texel.y) * band_texels)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(texel.x, texel.y) * band_texels * 0.7071)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(-texel.x, texel.y) * band_texels * 0.7071)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(texel.x, -texel.y) * band_texels * 0.7071)));
		interior = min(interior, mask_to_top(sample_effective_mountain_mask(UV + vec2(-texel.x, -texel.y) * band_texels * 0.7071)));
		float band_alpha = 1.0 - smoothstep(0.35, 0.85, interior);
		out_alpha *= band_alpha;
	}

	if (wall_mask > 0.001) {
		float broad_layer = fbm2(vec2(world_px.x / 520.0, world_px.y / 128.0) + vec2(41.0, -13.0));
		float face_breakup = 0.96 + (broad_layer - 0.5) * 0.10 + (small_mottle - 0.5) * 0.05;
		vec3 wall_color = facade_color * face_breakup;
		// Vertical read: 0 at the crest (roof junction), 1 at the open base.
		float wall_h = clamp(edge_below / max(wall_texels, 1.0), 0.0, 1.0);
		float shade_depth = 1.0 - wall_h;
		if (wall_streak_strength > 0.001) {
			// Rain-wash streaks: fine across, long down -> vertical tone drift.
			float streak = fbm2(vec2(world_px.x / 42.0, world_px.y / 330.0) + vec2(11.0, -7.0));
			wall_color *= 1.0 + (streak - 0.5) * 2.0 * wall_streak_strength;
		}
		if (wall_crack_strength > 0.001) {
			// Sparse vertical cracks: thin iso-band of x-heavy gradient fbm,
			// gated by a second field so lines break up (same recipe as roof veins).
			float crack_base = fbm2(vec2(world_px.x / 150.0, world_px.y / 620.0) + vec2(-53.0, 29.0));
			float crack_line = smoothstep(0.465, 0.5, crack_base) * (1.0 - smoothstep(0.5, 0.535, crack_base));
			float crack_gate = smoothstep(0.42, 0.60, fbm2(vec2(world_px.x / 380.0, world_px.y / 1000.0) + vec2(71.0, -11.0)));
			wall_color *= 1.0 - crack_line * crack_gate * wall_crack_strength;
		}
		// Smooth crest->base value ramp (a single continuous gradient, NOT
		// quantized depth bands), with cooler/desaturated shade pooling at the
		// base: the sun hits the roof, the wall falls into ambient shade.
		wall_color *= mix(wall_shade_top, wall_shade_bottom, smoothstep(0.05, 0.95, shade_depth));
		if (wall_desaturate > 0.001) {
			wall_color = mix(wall_color, vec3(luma(wall_color)), wall_desaturate * shade_depth);
		}
		wall_color *= mix(vec3(1.0), wall_shade_tint, shade_depth);
		if (crest_light_strength > 0.001) {
			// Sun-lit shoulder where the roof breaks into the wall. Derived from
			// the wall albedo and gated by the documented daylight shadow
			// visibility (same gate as rim lips) -> dims to neutral at night.
			float crest_daylight = smoothstep(0.05, 0.45, projected_shadow_opacity);
			float crest_low_sun = clamp((projected_shadow_length_px - 80.0) / 280.0, 0.0, 1.0);
			vec3 crest_warm = mix(vec3(1.0), crest_warm_tint, (0.35 + crest_low_sun * 0.65) * crest_daylight);
			float crest_band = smoothstep(1.0 - crest_height_frac * 1.8, 1.0 - crest_height_frac * 0.35, wall_h);
			float crest_breakup = 0.62 + small_mottle * 0.76;
			vec3 crest_color = wall_color * mix(1.05, crest_day_brightness, crest_daylight) * crest_warm;
			wall_color = mix(wall_color, crest_color, crest_band * crest_light_strength * crest_breakup);
		}
		float base_outline = 1.0 - smoothstep(0.0, 1.0 / max(sample_step_px, 1.0), edge_below);
		wall_color = mix(wall_color, vec3(0.0, 0.0, 0.0), clamp(base_outline, 0.0, 1.0) * base_outline_strength);
		// Resolve RGB ownership with the same coverage that writes alpha. Using
		// wall_mask directly left the bright roof RGB inside a fractional wall
		// edge whose alpha came only from the facade; straight-alpha composition
		// then exposed it as a one-pixel light contour over the ground.
		float wall_alpha = wall_mask * wall_surface_alpha;
		float combined_alpha = max(out_alpha, wall_alpha);
		float wall_color_weight = wall_alpha / max(combined_alpha, 0.0001);
		color = mix(color, wall_color, clamp(wall_color_weight, 0.0, 1.0));
		out_alpha = combined_alpha;
	}

	// Cosmetic roof eave over the open space just below the silhouette.
	if (!is_wall && overhang > 0.0) {
		vec3 eave_color = mix(eave_shadow_color, top_lit * 0.48, 0.28);
		color = mix(color, eave_color, overhang);
		out_alpha = max(out_alpha, overhang * wall_surface_alpha);
	}

	if (!is_wall && top_here < 0.5 && overhang <= 0.01 && projected_shadow > 0.002) {
		color = projected_shadow_color;
		out_alpha = max(out_alpha, projected_shadow);
	}

	// Thin dark outline along the solid silhouette edge (sides / non-wall),
	// then a lit stone lip just inside it (derived from the roof albedo, with
	// optional sparse biofield creep matching the ground's orange field).
	float silhouette = body_area * smoothstep(0.08, 0.5, top_here) * (1.0 - smoothstep(0.5, 0.82, top_here));
	float inner_rim = body_area * smoothstep(0.42, 0.72, top_here) * (1.0 - smoothstep(0.76, 0.96, top_here));
	float rim_grad_length = length(mask_grad);
	vec2 rim_outward = rim_grad_length > 0.0001 ? mask_grad / rim_grad_length : vec2(0.0, 1.0);
	float rim_facing = clamp(dot(rim_outward, normalize(light_dir.xy)) * 0.5 + 0.5, 0.0, 1.0);
	float silhouette_strength = mix(silhouette_shadow_strength, silhouette_lit_strength, rim_facing);
	color = mix(color, vec3(0.03, 0.02, 0.012), silhouette * silhouette_strength);
	// Тот же ночной гейт, что у верхней кромки стены (см. sun_daylight выше).
	float lip_daylight = smoothstep(0.05, 0.45, projected_shadow_opacity);
	float lip_low_sun = clamp((projected_shadow_length_px - 80.0) / 280.0, 0.0, 1.0);
	vec3 lip_warm_tint = mix(vec3(1.0), vec3(1.16, 0.93, 0.76), (0.35 + lip_low_sun * 0.65) * lip_daylight);
	vec3 inner_lip = top_col.rgb * mix(1.10, 1.32, lip_daylight) * lip_warm_tint;
	float lip_mix = mix(rim_lip_shadow_strength, rim_lip_lit_strength, rim_facing);
	if (biofield_rim_strength > 0.001) {
		float lip_bio_field = fbm2(world_px / max(biofield_rim_scale_px, 1.0) + vec2(-27.3, 8.1));
		float lip_bio_gate = smoothstep(0.60, 0.72, lip_bio_field) * biofield_rim_strength;
		inner_lip = mix(inner_lip, biofield_rim_color * (0.82 + small_mottle * 0.36), lip_bio_gate);
		lip_mix += lip_bio_gate * 0.20;
	}
	color = mix(color, inner_lip, inner_rim * lip_mix * top_here);

	point_light_facade_accept = wall_mask;
	COLOR = vec4(color, out_alpha);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// Keep the existing directional-light behavior for the sun; the sun's
		// occluder cull layer is separate from mountain torch occluders.
		LIGHT = vec4(LIGHT_COLOR.rgb * COLOR.rgb * LIGHT_ENERGY, LIGHT_COLOR.a);
	} else {
		float accept = clamp(point_light_facade_accept, 0.0, 1.0);
		// Point lights are clipped by the shader mask, not by the engine shadow
		// texture on this sprite. This removes the line/square bands while still
		// letting the same torch light open ground through regular Light2D rules.
		SHADOW_MODULATE = vec4(1.0);
		LIGHT = vec4(LIGHT_COLOR.rgb * COLOR.rgb * LIGHT_ENERGY * accept, LIGHT_COLOR.a * accept);
	}
}
