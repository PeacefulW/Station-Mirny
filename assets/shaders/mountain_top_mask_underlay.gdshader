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
uniform sampler2D face_texture : filter_linear, repeat_enable;
uniform sampler2D top_normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_normal_texture : filter_linear, repeat_enable;
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
uniform float light_angle_deg = 234.0;
uniform float normal_strength = 1.35;
uniform float material_normal_mix = 0.0;
uniform float material_normal_strength = 0.62;
uniform float light_ambient = 0.68;
uniform float light_diffuse = 0.34;
uniform float projected_shadow_angle_deg = 234.0;
uniform float projected_shadow_length_px = 72.0;
uniform float projected_shadow_opacity = 0.0;
uniform float projected_shadow_softness_px = 28.0;
// The construction ROOF pass keeps projected_shadow_opacity as the shared
// daylight gate for crest/rim shading but must not draw a second cast shadow.
uniform float projected_shadow_draw_enabled = 1.0;
uniform vec3 projected_shadow_color = vec3(0.030, 0.026, 0.018);
uniform float top_surface_alpha = 1.0;
uniform float wall_surface_alpha = 1.0;
// Construction roof mode (0 = live BASE pass, unchanged; 1 = visual-only ROOF
// copy of the immutable closed mask). In ROOF mode the sprite TEXTURE is the
// CLOSED pre-dig mask: the pass draws only top geometry (its own structural
// facade band and eave are suppressed so BASE(V)'s real mouth stays in
// charge), and the resolver-selected component fades this contribution out.
uniform float roof_overlay_mode = 0.0;
// Read-only live-mask reference for ROOF: locates the exact organic C-V
// excavation cutout and the internal BASE(V) structural facade owned by the
// displayed component. It never feeds roof colour, normals, or top geometry.
uniform sampler2D base_visual_mask_texture : filter_linear, repeat_disable;
// Displayed-component floor selector halo (32x32 L8, 255 = active floor).
// Ownership stays nearest/binary: the full-resolution C-V residual already
// carries the organic reveal border, so smoothing this tile field would leak
// into an adjacent foreign cavity.
uniform sampler2D active_floor_halo_texture : filter_nearest, repeat_disable;
// All excavated cells (any component). The nearest sampler is authoritative
// for foreign-cavity ownership; the second binding uses the same tiny texture
// with linear filtering only as a conservative 3x4 broad-phase accelerator.
uniform sampler2D any_cutout_halo_texture : filter_nearest, repeat_disable;
uniform sampler2D any_cutout_broad_texture : filter_linear, repeat_disable;
uniform float roof_component_reveal_enabled = 0.0;
uniform float component_reveal_blend = 0.0;
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
uniform float crest_light_strength = 0.0;   // albedo-derived sun-lit shoulder at the wall top
uniform float crest_height_frac = 0.16;     // crest band height as a fraction of wall height
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

float sample_component_exact_weight(vec2 uv) {
	if (roof_component_reveal_enabled < 0.5) {
		return 0.0;
	}
	float inside = uv_inside(uv);
	float selector_raw = texture(active_floor_halo_texture, uv).r;
	float selector_code = floor(selector_raw * 255.0 + 0.5);
	return step(127.5, selector_code) * inside;
}

float sample_any_cutout_exact_weight(vec2 uv) {
	float inside = uv_inside(uv);
	float cutout_raw = texture(any_cutout_halo_texture, uv).r;
	float cutout_code = floor(cutout_raw * 255.0 + 0.5);
	return step(127.5, cutout_code) * inside;
}

float sample_any_cutout_broad_weight(vec2 uv) {
	vec2 selector_size = vec2(textureSize(any_cutout_broad_texture, 0));
	vec2 selector_texel = 1.0 / selector_size;
	vec2 safe_uv = clamp(uv, vec2(0.0), vec2(1.0) - selector_texel * 0.001);
	vec2 cell_center = (floor(safe_uv * selector_size) + vec2(0.5)) * selector_texel;
	// Four bilinear samples at cell intersections conservatively cover the same
	// dx=-1..1, dy=-1..2 stencil as twelve nearest reads. False positives are
	// harmless because full-resolution C-V is still the visual proof.
	float broad = texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(-0.5, -0.5)
	).r;
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(0.5, -0.5)
	).r);
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(-0.5, 1.5)
	).r);
	broad = max(broad, texture(
		any_cutout_broad_texture,
		cell_center + selector_texel * vec2(0.5, 1.5)
	).r);
	return step(0.001, broad);
}

vec2 sample_active_foreign_exact_pair(vec2 uv) {
	float active = sample_component_exact_weight(uv);
	float any_cutout = sample_any_cutout_exact_weight(uv);
	return vec2(active, any_cutout * (1.0 - active));
}

vec2 sample_guarded_active_foreign_pair(vec2 uv) {
	vec2 center_owners = sample_active_foreign_exact_pair(uv);
	if (center_owners.x > 0.5 || center_owners.y > 0.5) {
		return center_owners;
	}
	vec2 selector_texel = 1.0 / vec2(textureSize(active_floor_halo_texture, 0));
	vec2 fringe_owners = vec2(0.0);
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv + vec2(selector_texel.x, 0.0)));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv - vec2(selector_texel.x, 0.0)));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv + vec2(0.0, selector_texel.y)));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv - vec2(0.0, selector_texel.y)));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv + selector_texel));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv - selector_texel));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv + vec2(selector_texel.x, -selector_texel.y)));
	fringe_owners = max(fringe_owners, sample_active_foreign_exact_pair(uv + vec2(-selector_texel.x, selector_texel.y)));
	return fringe_owners;
}

// Pixel-exact organic excavation delta (CLOSED - live V), owned by the exact
// selector tile or its guarded 3x3 fringe. Continuous movement can reach a
// curved corner in a diagonally adjacent tile, but a tile belonging to another
// excavated component must never inherit that ownership.
float sample_active_cutout_reveal_weight(
		float closed_top_here,
		float live_top_here,
		vec2 selector_uv
) {
	if (roof_component_reveal_enabled < 0.5) {
		return 0.0;
	}
	float excavation_cutout = smoothstep(
		0.001,
		0.08,
		max(closed_top_here - live_top_here, 0.0)
	);
	if (excavation_cutout <= 0.001) {
		return 0.0;
	}
	vec2 owners = sample_guarded_active_foreign_pair(selector_uv);
	// The residual alpha already carries the organic C-V antialiasing. The tile
	// owner is therefore binary, and any ambiguous neighbouring foreign source
	// conservatively keeps its roof closed.
	return owners.x * (1.0 - step(0.5, owners.y));
}

float find_base_visual_south_edge_distance(
		vec2 mask_uv,
		vec2 probe_step_uv,
		float solid_here,
		float max_probe_texels
) {
	if (solid_here < 0.5) {
		return -1.0;
	}
	float previous = solid_here;
	int steps = int(min(max_probe_texels + 2.0, 96.0));
	for (int distance_index = 1; distance_index <= 96; distance_index++) {
		if (distance_index > steps) {
			break;
		}
		float current = mask_to_top(texture(
			base_visual_mask_texture,
			mask_uv + probe_step_uv * float(distance_index)
		).r);
		if (current < 0.5 && previous >= 0.5) {
			float crossing = (previous - 0.5) / max(previous - current, 0.0001);
			return float(distance_index) - 1.0 + crossing;
		}
		previous = current;
	}
	return -1.0;
}

float structural_wall_band(
		float edge_distance,
		float solid_here,
		float wall_texels,
		float body_area
) {
	float valid = step(0.0, edge_distance);
	float solid_mask = smoothstep(0.38, 0.66, solid_here);
	float base_fade = smoothstep(-0.50, 0.15, edge_distance);
	float top_fade = 1.0 - smoothstep(wall_texels - 1.65, wall_texels + 1.65, edge_distance);
	return body_area * valid * solid_mask * base_fade * top_fade;
}

// Return (live SOUTH edge distance, guarded active owner, guarded foreign
// owner) for a BASE(V) wall close to a dug tile. The low-resolution dug halo is
// broad phase only; fragment() proves an internal wall from the exact organic
// C-V delta beyond the live edge before allowing ROOF to cover it.
vec3 sample_base_facade_state(
		vec2 visual_mask_uv,
		vec2 selector_uv,
		vec2 mask_texel,
		float wall_texels,
		float body_area,
		float visual_top_here,
		float nearby_cutout
) {
	if (nearby_cutout < 0.5) {
		return vec3(-1.0, 0.0, 0.0);
	}
	float visual_edge = find_base_visual_south_edge_distance(
		visual_mask_uv,
		vec2(0.0, mask_texel.y),
		visual_top_here,
		wall_texels
	);
	float visual_wall = structural_wall_band(
		visual_edge,
		visual_top_here,
		wall_texels,
		body_area
	);
	if (visual_wall <= 0.001 || visual_edge < 0.0) {
		return vec3(-1.0, 0.0, 0.0);
	}
	// Selector ownership follows the same warped coordinate as the C/V masks.
	// Multiple probes tolerate AA crossing, and the guarded fringe keeps an
	// adjacent foreign cavity closed.
	vec2 open_step = vec2(0.0, mask_texel.y);
	vec2 owners = vec2(0.0);
	// CLOSED is the steady state and has no displayed selector. Avoid the
	// guarded 3x3 ownership probes entirely until a component is opening/open.
	if (roof_component_reveal_enabled > 0.5) {
		owners = sample_guarded_active_foreign_pair(
			selector_uv + open_step * (visual_edge + 0.75)
		);
		owners = max(owners, sample_guarded_active_foreign_pair(
			selector_uv + open_step * (visual_edge + 1.50)
		));
		owners = max(owners, sample_guarded_active_foreign_pair(
			selector_uv + open_step * (visual_edge + 2.25)
		));
	}
	return vec3(visual_edge, owners.x, owners.y);
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

float roof_body_axis_owner_weight(
		float value,
		float body_min,
		float body_max,
		float core_min,
		float core_max
) {
	float left_width = max(core_min - body_min, 0.000001);
	float right_width = max(body_max - core_max, 0.000001);
	float left = smoothstep(core_min - left_width, core_min + left_width, value);
	float right = 1.0 - smoothstep(core_max - right_width, core_max + right_width, value);
	return min(left, right);
}

// ROOF sprites retain the same tiny body overlap as BASE so fractional camera
// motion cannot expose a crack. Complementary ownership converts that overlap
// into one alpha contribution globally: two edge weights (or four corner
// products) sum to 1, independent of chunk publication/sibling order.
float roof_body_owner_weight(vec2 uv) {
	float wx = roof_body_axis_owner_weight(
		uv.x,
		chunk_uv_min.x,
		chunk_uv_max.x,
		shadow_uv_min.x,
		shadow_uv_max.x
	);
	float wy = roof_body_axis_owner_weight(
		uv.y,
		chunk_uv_min.y,
		chunk_uv_max.y,
		shadow_uv_min.y,
		shadow_uv_max.y
	);
	return wx * wy;
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
	vec2 base_uv = visual_mask_uv(UV, texel, world_px);
	float top_here = mask_to_top(texture(TEXTURE, base_uv).r);
	float top_l = mask_to_top(texture(TEXTURE, base_uv - vec2(texel.x, 0.0)).r);
	float top_r = mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, 0.0)).r);
	float top_u = mask_to_top(texture(TEXTURE, base_uv - vec2(0.0, texel.y)).r);
	float top_d = mask_to_top(texture(TEXTURE, base_uv + vec2(0.0, texel.y)).r);
	vec2 mask_grad = vec2(top_l - top_r, top_u - top_d);
	float light_angle_rad = radians(light_angle_deg);
	vec2 side_shade_step = vec2(0.0);
	float closed_side_toward = top_here;
	float closed_side_away = top_here;
	float closed_side_signed = 0.0;
	if (side_shade_strength > 0.001 && top_here >= 0.5) {
		side_shade_step = vec2(cos(light_angle_rad), sin(light_angle_rad))
				* texel * (side_shade_reach_px / max(sample_step_px, 0.001));
		closed_side_toward = mask_to_top(texture(TEXTURE, base_uv + side_shade_step).r);
		closed_side_away = mask_to_top(texture(TEXTURE, base_uv - side_shade_step).r);
		closed_side_signed = (1.0 - closed_side_toward) - (1.0 - closed_side_away);
	}

	float wall_texels = max(1.0, facade_height_px / sample_step_px);
	float overhang_texels = max(1.0, overhang_px / sample_step_px);

	// SOLID pixel: continuous distance DOWN (south) to the open silhouette edge.
	float edge_below = -1.0;
	if (top_here >= 0.5) {
		float prev = top_here;
		int steps = int(min(wall_texels + 2.0, 96.0));
		for (int d = 1; d <= steps; d++) {
			float cur = mask_to_top(texture(TEXTURE, base_uv + vec2(0.0, texel.y * float(d))).r);
			if (cur < 0.5 && prev >= 0.5) {
				float t = (prev - 0.5) / max(prev - cur, 0.0001);
				edge_below = float(d) - 1.0 + t;
				break;
			}
			prev = cur;
		}
	}
	float structural_wall_mask = structural_wall_band(
		edge_below,
		top_here,
		wall_texels,
		body_area
	);
	float live_top_here = top_here;
	vec2 base_facade_cover_weights = vec2(0.0);
	float side_shade_cover_owner = 0.0;
	float side_shade_reveal_owner = 0.0;
	if (overlay_mode > 0.5) {
		live_top_here = mask_to_top(texture(base_visual_mask_texture, base_uv).r);
		float nearby_cutout = sample_any_cutout_broad_weight(base_uv);
		if (nearby_cutout > 0.5
				&& side_shade_strength > 0.001
				&& top_here >= 0.5
				&& live_top_here >= 0.5) {
			vec2 toward_uv = base_uv + side_shade_step;
			vec2 away_uv = base_uv - side_shade_step;
			float live_side_toward = mask_to_top(texture(base_visual_mask_texture, toward_uv).r);
			float live_side_away = mask_to_top(texture(base_visual_mask_texture, away_uv).r);
			float live_side_signed = (1.0 - live_side_toward) - (1.0 - live_side_away);
			side_shade_cover_owner = step(
				0.02,
				abs(closed_side_signed - live_side_signed)
			);
			if (roof_component_reveal_enabled > 0.5 && side_shade_cover_owner > 0.5) {
				vec2 side_owners = vec2(0.0);
				if (closed_side_toward - live_side_toward > 0.001) {
					side_owners = max(
						side_owners,
						sample_guarded_active_foreign_pair(toward_uv)
					);
				}
				if (closed_side_away - live_side_away > 0.001) {
					side_owners = max(
						side_owners,
						sample_guarded_active_foreign_pair(away_uv)
					);
				}
				side_shade_reveal_owner = side_owners.x
						* (1.0 - step(0.5, side_owners.y));
			}
		}
		vec3 base_facade_state = sample_base_facade_state(
			base_uv,
			base_uv,
			texel,
			wall_texels,
			body_area,
			live_top_here,
			nearby_cutout
		);
		if (base_facade_state.x >= 0.0) {
			vec2 open_step = vec2(0.0, texel.y);
			float organic_delta = 0.0;
			vec2 probe_uv = base_uv + open_step * (base_facade_state.x + 0.75);
			float probe_inside = uv_inside(probe_uv);
			organic_delta = max(organic_delta, max(
				mask_to_top(texture(TEXTURE, probe_uv).r)
						- mask_to_top(texture(base_visual_mask_texture, probe_uv).r),
				0.0
			) * probe_inside);
			probe_uv = base_uv + open_step * (base_facade_state.x + 1.50);
			probe_inside = uv_inside(probe_uv);
			organic_delta = max(organic_delta, max(
				mask_to_top(texture(TEXTURE, probe_uv).r)
						- mask_to_top(texture(base_visual_mask_texture, probe_uv).r),
				0.0
			) * probe_inside);
			probe_uv = base_uv + open_step * (base_facade_state.x + 2.25);
			probe_inside = uv_inside(probe_uv);
			organic_delta = max(organic_delta, max(
				mask_to_top(texture(TEXTURE, probe_uv).r)
						- mask_to_top(texture(base_visual_mask_texture, probe_uv).r),
				0.0
			) * probe_inside);
			float facade_cover_owner = step(0.02, organic_delta);
			float facade_reveal_owner = base_facade_state.y
					* (1.0 - step(0.5, base_facade_state.z));
			base_facade_cover_weights = vec2(
				facade_cover_owner,
				facade_cover_owner * facade_reveal_owner
			);
		}
	}
	// The construction ROOF never repaints a structural facade: removing its
	// own wall band exposes BASE(V)'s live break, so a dug entrance is never
	// re-covered by the pre-dig facade while the top geometry stays CLOSED.
	float closed_surface_mask = top_here * body_area * (1.0 - structural_wall_mask * overlay_mode);
	float live_surface_mask = live_top_here * body_area;
	float residual_surface_mask = 0.0;
	if (closed_surface_mask > live_surface_mask + 0.0001) {
		residual_surface_mask = clamp(
			(closed_surface_mask - live_surface_mask) / max(1.0 - live_surface_mask, 0.0001),
			0.0,
			1.0
		);
	}
	// Never replace C's original exterior facade with top texture. Even when a
	// dug entrance touches that band, the part that existed before digging must
	// remain the visible mouth; only genuinely internal V facade is roof-covered.
	float base_facade_cover_mask = closed_surface_mask * base_facade_cover_weights.x;
	// BASE(V)'s sun-facing bevel reaches into still-solid pixels around a new
	// excavation edge. Replace only that exact organic colour footprint with
	// C's bevel while closed; otherwise the live internal edge shines through
	// an alpha-correct roof as a curved/vertical line.
	float side_shade_cover_mask = closed_surface_mask
			* smoothstep(0.72, 0.98, live_top_here)
			* side_shade_cover_owner;
	float overlay_surface_mask = max(
		residual_surface_mask,
		max(base_facade_cover_mask, side_shade_cover_mask)
	);
	float cutout_reveal_owner = 0.0;
	float facade_reveal_owner = 0.0;
	if (overlay_mode > 0.5 && roof_component_reveal_enabled > 0.5) {
		cutout_reveal_owner = sample_active_cutout_reveal_weight(
			top_here,
			live_top_here,
			base_uv
		);
		facade_reveal_owner = base_facade_cover_weights.y;
		// Fully transparent revealed cave pixels should not pay the expensive
		// albedo/noise/terrace path below.
		float visible_overlay_hint = max(
			residual_surface_mask * (1.0 - clamp(cutout_reveal_owner * component_reveal_blend, 0.0, 1.0)),
			max(
				base_facade_cover_mask * (1.0 - clamp(facade_reveal_owner * component_reveal_blend, 0.0, 1.0)),
				side_shade_cover_mask * (1.0 - clamp(side_shade_reveal_owner * component_reveal_blend, 0.0, 1.0))
			)
		);
		if (visible_overlay_hint <= 0.0001) {
			discard;
		}
	}
	float roof_surface_mask = mix(top_here * body_area, overlay_surface_mask, overlay_mode);
	float wall_mask = structural_wall_mask * (1.0 - overlay_mode);
	bool is_wall = wall_mask > 0.02;

	// OPEN pixel: cosmetic roof eave just below the silhouette ("козырёк").
	// overhang_px <= 0.5 disables the eave entirely (mountains stand directly
	// on the foothill apron; the shoreline keeps its thin lip).
	float overhang = 0.0;
	if (top_here < 0.5 && overhang_px > 0.5) {
		int osteps = int(min(overhang_texels + 2.0, 24.0));
		for (int d = 1; d <= osteps; d++) {
			if (mask_to_top(texture(TEXTURE, base_uv - vec2(0.0, texel.y * float(d))).r) >= 0.5) {
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
			float center = mask_to_top(texture(TEXTURE, base_uv).r) * center_w;
			float left = mask_to_top(texture(TEXTURE, left_uv).r) * left_w;
			float right = mask_to_top(texture(TEXTURE, right_uv).r) * right_w;
			float wide_left = mask_to_top(texture(TEXTURE, wide_left_uv).r) * wide_left_w;
			float wide_right = mask_to_top(texture(TEXTURE, wide_right_uv).r) * wide_right_w;
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
	float a = light_angle_rad;
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
	vec4 top_col = texture(top_texture, top_uv);
	top_col.rgb *= top_variation;
	top_col.rgb = mix(top_col.rgb, top_col.rgb * top_dust_tint, smoothstep(0.68, 0.96, macro) * 0.20);
	vec3 top_n = vec3(0.0, 0.0, 1.0);
	if (!temporary_disable_terrain_normals) {
		float h_c = luma(top_col.rgb);
		float h_x = luma(texture(top_texture, top_uv_dx).rgb);
		float h_y = luma(texture(top_texture, top_uv_dy).rgb);
		top_n = normalize(vec3(
			mask_grad.x * 2.2 + (h_c - h_x) * normal_strength * 0.38,
			mask_grad.y * 2.2 + (h_c - h_y) * normal_strength * 0.38,
			1.0
		));
		if (material_normal_mix > 0.001) {
			vec3 top_detail_n = unpack_normal(texture(top_normal_texture, top_uv).rgb);
			top_n = normalize(mix(top_n, blend_normals(top_n, top_detail_n), clamp(material_normal_mix, 0.0, 1.0)));
		}
	}
	vec3 top_lit = top_col.rgb * (light_ambient + light_diffuse * clamp(dot(top_n, light_dir), 0.0, 1.0));
	if (terrace_strength > 0.001 && top_here >= 0.5) {
		// Concentric height terraces from distance-to-edge ring probes. The
		// noise-wobbled radii keep the step contours organic and parallel to
		// the warped silhouette (both feed off the same world-space mask).
		float terrace_wobble = (fbm2(world_px / 300.0 + vec2(-9.0, 37.0)) - 0.5) * 2.0 * terrace_wobble_px;
		float inner_texels = max((terrace_inner_px + terrace_wobble) / max(sample_step_px, 0.001), 1.0);
		float upper_texels = max((terrace_upper_px + terrace_wobble * 1.4) / max(sample_step_px, 0.001), 1.0);
		// Godot does not expose the built-in TEXTURE sampler from a helper
		// function. Keep these ring probes in fragment(): besides compiling on
		// every supported renderer, both BASE and ROOF still sample their own
		// organic mask without introducing an auxiliary texture/uniform.
		float inner_ring = 1.0;
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, 0.0) * inner_texels).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv - vec2(texel.x, 0.0) * inner_texels).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(0.0, texel.y) * inner_texels).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv - vec2(0.0, texel.y) * inner_texels).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, texel.y) * inner_texels * 0.7071).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(-texel.x, texel.y) * inner_texels * 0.7071).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, -texel.y) * inner_texels * 0.7071).r));
		inner_ring = min(inner_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(-texel.x, -texel.y) * inner_texels * 0.7071).r));
		float upper_ring = 1.0;
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, 0.0) * upper_texels).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv - vec2(texel.x, 0.0) * upper_texels).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(0.0, texel.y) * upper_texels).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv - vec2(0.0, texel.y) * upper_texels).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, texel.y) * upper_texels * 0.7071).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(-texel.x, texel.y) * upper_texels * 0.7071).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(texel.x, -texel.y) * upper_texels * 0.7071).r));
		upper_ring = min(upper_ring, mask_to_top(texture(TEXTURE, base_uv + vec2(-texel.x, -texel.y) * upper_texels * 0.7071).r));
		float inner_level = smoothstep(0.30, 0.72, inner_ring);
		float upper_level = smoothstep(0.30, 0.72, upper_ring);
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
		float rim_breakup = 0.72 + small_mottle * 0.56;
		top_lit *= 1.0
			+ max(closed_side_signed, 0.0) * side_shade_strength * 0.65 * rim_breakup
			- max(-closed_side_signed, 0.0) * side_shade_strength * rim_breakup;
	}

	// Wall -- controlled relief and sparse base chips. The face texture samples
	// vertically stretched world space (v_stretch > 1): ledge features elongate
	// downward, so the wall stops mirroring the isotropic roof gravel.
	vec2 face_world_px = vec2(world_px.x, world_px.y / max(wall_texture_v_stretch, 0.001));
	vec2 face_uv = face_world_px * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dx = (face_world_px + vec2(grad_px, 0.0)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dy = (face_world_px + vec2(0.0, grad_px)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec4 face_col = texture(face_texture, face_uv);
	face_col.rgb *= 0.86 + (macro - 0.5) * 0.10;
	vec3 face_n = vec3(0.0, 0.0, 1.0);
	if (!temporary_disable_terrain_normals) {
		float fh_c = luma(face_col.rgb);
		float fh_x = luma(texture(face_texture, face_uv_dx).rgb);
		float fh_y = luma(texture(face_texture, face_uv_dy).rgb);
		face_n = normalize(vec3(
			mask_grad.x * 1.55 + (fh_c - fh_x) * normal_strength * 0.62,
			mask_grad.y * 1.55 + (fh_c - fh_y) * normal_strength * 0.62,
			1.0
		));
		if (material_normal_mix > 0.001) {
			vec3 face_detail_n = unpack_normal(texture(face_normal_texture, face_uv).rgb);
			face_n = normalize(mix(face_n, blend_normals(face_n, face_detail_n), clamp(material_normal_mix, 0.0, 1.0)));
		}
	}
	vec3 facade_color = face_col.rgb * (light_ambient + light_diffuse * clamp(dot(face_n, light_dir), 0.0, 1.0));

	vec3 color = top_lit;
	// Gate the roof by body_area (the tiny chunk overlap) like walls/overhang/
	// coverage already are. Without this the roof's translucent silhouette edge
	// leaked into the WIDE projected-shadow overlap band (MASK_SHADOW_CHUNK_OVERLAP_PX,
	// 48 px), so two neighbouring chunk sprites double-composited their edges into a
	// brighter rectangular seam — very visible once the torch lit the rock at night.
	float top_alpha = top_col.a * top_surface_alpha;
	float closed_target_alpha = closed_surface_mask * top_alpha;
	float live_top_alpha = live_surface_mask * top_alpha;
	float roof_residual_alpha = 0.0;
	if (closed_target_alpha > live_top_alpha + 0.0001) {
		roof_residual_alpha = clamp(
			(closed_target_alpha - live_top_alpha) / max(1.0 - live_top_alpha, 0.0001),
			0.0,
			1.0
		);
	}
	float roof_facade_cover_alpha = closed_target_alpha * base_facade_cover_weights.x;
	float roof_side_shade_cover_alpha = closed_target_alpha
			* smoothstep(0.72, 0.98, live_top_here)
			* side_shade_cover_owner;
	float overlay_alpha = max(
		roof_residual_alpha,
		max(roof_facade_cover_alpha, roof_side_shade_cover_alpha)
	);
	float out_alpha = mix(top_here * body_area * top_alpha, overlay_alpha, overlay_mode);

	if (top_band_px > 0.5) {
		// Shoreline band: keep the top fill only near the open contour. The
		// nearest-open probe at a noise-wobbled radius gives an irregular,
		// packed-shore inner edge that dissolves into the ground material.
		float band_wobble = (fbm2(world_px / 240.0 + vec2(27.0, -53.0)) - 0.5) * 2.0 * top_band_feather_px;
		float band_texels = max((top_band_px + band_wobble) / max(sample_step_px, 0.001), 1.0);
		float interior = top_here;
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(texel.x, 0.0) * band_texels).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV - vec2(texel.x, 0.0) * band_texels).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(0.0, texel.y) * band_texels).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV - vec2(0.0, texel.y) * band_texels).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(texel.x, texel.y) * band_texels * 0.7071).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(-texel.x, texel.y) * band_texels * 0.7071).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(texel.x, -texel.y) * band_texels * 0.7071).r));
		interior = min(interior, mask_to_top(texture(TEXTURE, UV + vec2(-texel.x, -texel.y) * band_texels * 0.7071).r));
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
			float crack_base = fbm2(vec2(world_px.x / 92.0, world_px.y / 470.0) + vec2(-53.0, 29.0));
			float crack_line = smoothstep(0.465, 0.5, crack_base) * (1.0 - smoothstep(0.5, 0.535, crack_base));
			float crack_gate = smoothstep(0.42, 0.60, fbm2(vec2(world_px.x / 300.0, world_px.y / 900.0) + vec2(71.0, -11.0)));
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
			vec3 crest_warm = mix(vec3(1.0), vec3(1.16, 0.95, 0.78), (0.35 + crest_low_sun * 0.65) * crest_daylight);
			float crest_band = smoothstep(1.0 - crest_height_frac * 1.8, 1.0 - crest_height_frac * 0.35, wall_h);
			float crest_breakup = 0.62 + small_mottle * 0.76;
			vec3 crest_color = wall_color * mix(1.05, 1.38, crest_daylight) * crest_warm;
			wall_color = mix(wall_color, crest_color, crest_band * crest_light_strength * crest_breakup);
		}
		float base_outline = 1.0 - smoothstep(0.0, 1.0 / max(sample_step_px, 1.0), edge_below);
		wall_color = mix(wall_color, vec3(0.0, 0.0, 0.0), clamp(base_outline, 0.0, 1.0) * base_outline_strength);
		// Preserve the established BASE/facade composition. ROOF has wall_mask=0,
		// so construction coverage never changes the live mountain or shoreline
		// facade path.
		color = mix(color, wall_color, wall_mask);
		out_alpha = max(out_alpha, wall_mask * wall_surface_alpha);
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
	color = mix(color, vec3(0.03, 0.02, 0.012), silhouette * 0.64);
	// Тот же ночной гейт, что у верхней кромки стены (см. sun_daylight выше).
	float lip_daylight = smoothstep(0.05, 0.45, projected_shadow_opacity);
	float lip_low_sun = clamp((projected_shadow_length_px - 80.0) / 280.0, 0.0, 1.0);
	vec3 lip_warm_tint = mix(vec3(1.0), vec3(1.16, 0.93, 0.76), (0.35 + lip_low_sun * 0.65) * lip_daylight);
	vec3 inner_lip = top_col.rgb * mix(1.10, 1.32, lip_daylight) * lip_warm_tint;
	float lip_mix = 0.12;
	if (biofield_rim_strength > 0.001) {
		float lip_bio_field = fbm2(world_px / max(biofield_rim_scale_px, 1.0) + vec2(-27.3, 8.1));
		float lip_bio_gate = smoothstep(0.60, 0.72, lip_bio_field) * biofield_rim_strength;
		inner_lip = mix(inner_lip, biofield_rim_color * (0.82 + small_mottle * 0.36), lip_bio_gate);
		lip_mix += lip_bio_gate * 0.20;
	}
	color = mix(color, inner_lip, inner_rim * lip_mix * top_here);
	if (overlay_mode > 0.5 && roof_component_reveal_enabled > 0.5) {
		// Reveal each construction contribution through its own ownership proof.
		// This prevents an active facade from erasing a neighbouring cavity's
		// CLOSED residual in an overlap pixel.
		float visible_residual = roof_residual_alpha
			* (1.0 - clamp(cutout_reveal_owner * component_reveal_blend, 0.0, 1.0));
		float visible_facade = roof_facade_cover_alpha
			* (1.0 - clamp(facade_reveal_owner * component_reveal_blend, 0.0, 1.0));
		float visible_side_shade = roof_side_shade_cover_alpha
			* (1.0 - clamp(side_shade_reveal_owner * component_reveal_blend, 0.0, 1.0));
		out_alpha = max(visible_residual, max(visible_facade, visible_side_shade));
	}
	if (overlay_mode > 0.5) {
		float owner_weight = roof_body_owner_weight(UV);
		if (owner_weight <= 0.000001) {
			discard;
		}
		out_alpha = 1.0 - pow(max(1.0 - clamp(out_alpha, 0.0, 1.0), 0.0), owner_weight);
	}

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
