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
// Production construction roof. TEXTURE/closed_mask_texture are the immutable
// closed silhouette. BASE(V) is already underneath; the resolver-selected
// component therefore opens by fading this CLOSED contribution, never by
// morphing CLOSED into V or cutting a second procedural mouth in the roof.
uniform sampler2D closed_mask_texture : filter_linear;
// Read-only BASE(V) ownership reference: while inside, ROOF must yield both
// the exact internal vertical facade already drawn underneath and the C-V cut
// owned by the displayed component. It never feeds roof colour, normals,
// silhouette or top geometry.
uniform sampler2D base_visual_mask_texture : filter_linear, repeat_disable;
uniform sampler2D active_floor_halo_texture : filter_nearest;
uniform sampler2D active_floor_halo_soft_texture : filter_linear;
uniform sampler2D any_cutout_halo_texture : filter_nearest;
uniform float roof_component_reveal_enabled = 0.0;
uniform float component_reveal_blend = 0.0;
// Canonical full-resolution native mouth aperture. It never reveals ROOF; BASE
// uses a narrow dilation only to suppress its cosmetic crag warp at the exact
// physical facade cut, so digging farther inward cannot move the entrance.
uniform sampler2D physical_mouth_aperture_texture : filter_linear, repeat_disable;
uniform float physical_mouth_aperture_enabled = 0.0;
// Tiny N/E/S/W selector remains metadata only. It chooses which CLOSED edge
// belongs to the local vertical facade; it never defines aperture geometry and
// never enters the component reveal selector.
uniform sampler2D physical_mouth_direction_texture : filter_nearest, repeat_disable;
uniform float physical_mouth_direction_enabled = 0.0;
// Sun-shadow occluder override (BASE): the projected sun shadow samples the
// immutable CLOSED mask, so the massif casts one silhouette shadow even where
// V is excavated, and the roof lip over a physical mouth casts its own SE
// shadow across the threshold. The shadow RECEIVER is then limited to
// CLOSED-open exterior ground so revealed interior floors never collect a
// duplicate static sun stamp (interior light belongs to ADR-0005 systems).
// Disabled (0) keeps the classic own-mask occluder (shared shoreline material).
uniform sampler2D sun_occluder_mask_texture : filter_linear, repeat_disable;
uniform float sun_occluder_mask_enabled = 0.0;
// Physical mouth dressing. All cosmetic, all neutral by default:
//   - maw: the missing facade band beneath the CLOSED lip fills with a dark
//     translucent void gradient (deep at the lip, open at the threshold), so
//     the entrance reads as a hole into unlit rock instead of a bright path.
//     Geometry derives from CLOSED-solid over V-open under an M tile gate; the
//     ground floor stays visible through it (no black fill, no decals).
//   - jamb shade: wall pixels flanking the aperture darken toward the cut
//     (corner occlusion), asymmetrically against the NW sun for side volume.
//   - roof lip: ROOF brightens a thin sun-lit band just above its facade cut
//     at M-gated mouth columns. Shading only: alpha and geometry stay CLOSED.
uniform float mouth_maw_strength = 0.0;
uniform vec3 mouth_maw_color = vec3(0.045, 0.032, 0.022);
uniform float mouth_maw_depth_px = 84.0;
uniform float mouth_jamb_shade_strength = 0.0;
uniform float mouth_jamb_shade_px = 15.0;
uniform float mouth_roof_lip_strength = 0.0;
uniform float mouth_roof_lip_px = 8.0;
// Component reveal blend mirrored from ChunkView: standing inside softens the
// outside maw/jamb dressing so the faded roof leaves no stray dark bar.
uniform float mouth_reveal_fade = 0.0;
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

float sample_effective_mountain_mask(vec2 uv) {
	return texture(closed_mask_texture, uv).r;
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

float sample_component_reveal_weight(vec2 uv) {
	if (roof_component_reveal_enabled < 0.5) {
		return 0.0;
	}
	float inside = uv_inside(uv);
	float active_exact = sample_component_exact_weight(uv);
	float active_soft = smoothstep(0.25, 0.75, texture(active_floor_halo_soft_texture, uv).r) * inside;
	float foreign_cutout = step(0.5, texture(any_cutout_halo_texture, uv).r) * (1.0 - active_exact);
	return clamp(max(active_exact, active_soft * (1.0 - foreign_cutout)), 0.0, 1.0);
}

float sample_active_cutout_reveal_weight(vec2 visual_mask_uv, vec2 selector_uv) {
	if (roof_component_reveal_enabled < 0.5) {
		return 0.0;
	}
	float closed_here = texture(closed_mask_texture, visual_mask_uv).r;
	float visual_here = texture(base_visual_mask_texture, visual_mask_uv).r;
	float excavation_cutout = smoothstep(0.01, 0.08, max(closed_here - visual_here, 0.0));
	if (excavation_cutout <= 0.001) {
		return 0.0;
	}
	// The native cut may remove CLOSED spill in the first non-owned exterior
	// cell. Give that cell exact cardinal ownership from the active cavity, but
	// never accept diagonal-only or foreign-cavity selectors.
	vec2 selector_texel = 1.0 / vec2(textureSize(active_floor_halo_texture, 0));
	float active_owner = sample_component_exact_weight(selector_uv);
	active_owner = max(active_owner, sample_component_exact_weight(selector_uv + vec2(selector_texel.x, 0.0)));
	active_owner = max(active_owner, sample_component_exact_weight(selector_uv - vec2(selector_texel.x, 0.0)));
	active_owner = max(active_owner, sample_component_exact_weight(selector_uv + vec2(0.0, selector_texel.y)));
	active_owner = max(active_owner, sample_component_exact_weight(selector_uv - vec2(0.0, selector_texel.y)));
	return excavation_cutout * active_owner * uv_inside(visual_mask_uv);
}

float sample_physical_mouth_aperture_at(vec2 uv) {
	return texture(physical_mouth_aperture_texture, uv).r * uv_inside(uv);
}

float sample_physical_mouth_unwarp(vec2 uv) {
	if (physical_mouth_aperture_enabled < 0.5) {
		return 0.0;
	}
	// The full-resolution dilation is needed only inside the source/exterior
	// mouth cells. A coarse metadata gate avoids seventeen aperture reads over
	// the rest of an otherwise very large mountain mask sprite.
	float coarse_direction_code = physical_mouth_direction_enabled > 0.5
		? floor(texture(physical_mouth_direction_texture, uv).r * 255.0 + 0.5)
			* uv_inside(uv)
		: 0.0;
	if (mod(coarse_direction_code, 16.0) < 0.5) {
		return 0.0;
	}
	vec2 aperture_texel = 1.0 / vec2(textureSize(physical_mouth_aperture_texture, 0));
	vec2 immediate_diagonal = aperture_texel;
	vec2 cardinal = aperture_texel * 2.0;
	vec2 diagonal = aperture_texel * 1.4142;
	float aperture = sample_physical_mouth_aperture_at(uv);
	// Immediate 8-neighbour ring keeps thin antialiased tips attached to the
	// exact native cut; the second ring covers the maximum cosmetic crag warp.
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(aperture_texel.x, 0.0)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - vec2(aperture_texel.x, 0.0)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(0.0, aperture_texel.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - vec2(0.0, aperture_texel.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + immediate_diagonal));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - immediate_diagonal));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(immediate_diagonal.x, -immediate_diagonal.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(-immediate_diagonal.x, immediate_diagonal.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(cardinal.x, 0.0)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - vec2(cardinal.x, 0.0)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(0.0, cardinal.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - vec2(0.0, cardinal.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + diagonal));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv - diagonal));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(diagonal.x, -diagonal.y)));
	aperture = max(aperture, sample_physical_mouth_aperture_at(uv + vec2(-diagonal.x, diagonal.y)));
	return smoothstep(0.015, 0.42, aperture);
}

float selector_has_bit(float code, float bit_value) {
	return step(0.5, mod(floor(code / bit_value), 2.0));
}

float sample_physical_mouth_direction_code(vec2 uv) {
	if (physical_mouth_direction_enabled < 0.5) {
		return 0.0;
	}
	return floor(texture(physical_mouth_direction_texture, uv).r * 255.0 + 0.5)
		* uv_inside(uv);
}

float sample_sun_occluder_top(vec2 uv) {
	if (sun_occluder_mask_enabled < 0.5) {
		return mask_to_top(sample_effective_mountain_mask(uv));
	}
	return mask_to_top(texture(sun_occluder_mask_texture, uv).r * uv_inside(uv));
}

// First mouth direction code found at this pixel's tile or a half-tile
// cardinal offset. The offsets keep the organic AA fringe of a native cut
// (which may cross into the neighbouring retaining tile) inside the dressing.
float sample_mouth_direction_code_near(vec2 uv) {
	float code = sample_physical_mouth_direction_code(uv);
	if (mod(code, 16.0) >= 0.5) {
		return code;
	}
	if (physical_mouth_direction_enabled < 0.5) {
		return 0.0;
	}
	vec2 selector_texel = 1.0 / vec2(textureSize(physical_mouth_direction_texture, 0));
	vec2 near_offsets[4] = {
		vec2(selector_texel.x * 0.55, 0.0),
		vec2(-selector_texel.x * 0.55, 0.0),
		vec2(0.0, selector_texel.y * 0.55),
		vec2(0.0, -selector_texel.y * 0.55)
	};
	for (int offset_index = 0; offset_index < 4; offset_index++) {
		float neighbor_code = sample_physical_mouth_direction_code(uv + near_offsets[offset_index]);
		if (mod(neighbor_code, 16.0) >= 0.5) {
			return neighbor_code;
		}
	}
	return 0.0;
}

// find_outward_edge_distance twin that walks the sun-occluder (CLOSED) mask:
// distance from a maw pixel to the organic CLOSED contour along the mouth's
// outward direction = "how deep under the lip" for the maw gradient.
float find_occluder_edge_distance(
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
		float current = sample_sun_occluder_top(mask_uv + probe_step_uv * float(distance_index));
		if (current < 0.5 && previous >= 0.5) {
			float crossing = (previous - 0.5) / max(previous - current, 0.0001);
			return float(distance_index) - 1.0 + crossing;
		}
		previous = current;
	}
	return -1.0;
}

float find_outward_edge_distance(
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
		float current = mask_to_top(sample_effective_mountain_mask(
			mask_uv + probe_step_uv * float(distance_index)
		));
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

float sample_displayed_base_facade_reveal_weight(
		vec2 visual_mask_uv,
		vec2 selector_uv,
		vec2 mask_texel,
		float wall_texels,
		float body_area
) {
	// Internal structural facades are SOUTH-facing in this projection. A cheap
	// two-tile selector look-ahead avoids the V edge scan over the rest of the
	// mountain while still covering the 72 px wall band at 64 px/tile.
	vec2 selector_texel = 1.0 / vec2(textureSize(active_floor_halo_texture, 0));
	float nearby_active = sample_component_exact_weight(selector_uv);
	nearby_active = max(
		nearby_active,
		sample_component_exact_weight(selector_uv + vec2(0.0, selector_texel.y))
	);
	nearby_active = max(
		nearby_active,
		sample_component_exact_weight(selector_uv + vec2(0.0, selector_texel.y * 2.0))
	);
	if (nearby_active < 0.5) {
		return 0.0;
	}
	float visual_top_here = mask_to_top(texture(base_visual_mask_texture, visual_mask_uv).r);
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
		return 0.0;
	}
	// Ownership is sampled just beyond the organic V edge in RAW selector UV.
	// Multiple tiny probes tolerate AA/warp crossing without soft-selector leaks.
	vec2 open_step = vec2(0.0, mask_texel.y);
	float active_owner = sample_component_exact_weight(
		selector_uv + open_step * (visual_edge + 0.75)
	);
	active_owner = max(active_owner, sample_component_exact_weight(
		selector_uv + open_step * (visual_edge + 1.50)
	));
	active_owner = max(active_owner, sample_component_exact_weight(
		selector_uv + open_step * (visual_edge + 2.25)
	));
	return visual_wall * active_owner;
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
	// Preserve only the canonical native facade cut through the cosmetic warp.
	// ROOF deliberately ignores the aperture and stays the immutable CLOSED cap.
	float mouth_unwarp = sample_physical_mouth_unwarp(UV) * (1.0 - overlay_mode);
	vec2 base_uv = mix(warped_base_uv, UV, mouth_unwarp);
	float top_here = mask_to_top(sample_effective_mountain_mask(base_uv));
	float top_l = mask_to_top(sample_effective_mountain_mask(base_uv - vec2(texel.x, 0.0)));
	float top_r = mask_to_top(sample_effective_mountain_mask(base_uv + vec2(texel.x, 0.0)));
	float top_u = mask_to_top(sample_effective_mountain_mask(base_uv - vec2(0.0, texel.y)));
	float top_d = mask_to_top(sample_effective_mountain_mask(base_uv + vec2(0.0, texel.y)));
	vec2 mask_grad = vec2(top_l - top_r, top_u - top_d);
	float wall_texels = max(1.0, facade_height_px / sample_step_px);
	float overhang_texels = max(1.0, overhang_px / sample_step_px);

	// The general mountain facade remains SOUTH-facing. At a physical mouth the
	// tiny direction selector transfers facade ownership to the matching CLOSED
	// edge, so N/E/W entrances are real facade breaks too. The selector chooses
	// only orientation; native C-V remains the sole aperture geometry.
	float edge_below = find_outward_edge_distance(
		base_uv,
		vec2(0.0, texel.y),
		top_here,
		wall_texels
	);
	float structural_wall_mask = structural_wall_band(
		edge_below,
		top_here,
		wall_texels,
		body_area
	);
	float wall_edge_distance = edge_below;
	float mouth_direction_code = sample_physical_mouth_direction_code(UV);
	vec2 mouth_probe_steps[4] = {
		vec2(0.0, -texel.y),
		vec2(texel.x, 0.0),
		vec2(0.0, texel.y),
		vec2(-texel.x, 0.0)
	};
	float mouth_direction_bits[4] = {1.0, 2.0, 4.0, 8.0};
	for (int direction_index = 0; direction_index < 4; direction_index++) {
		float direction_gate = selector_has_bit(
			mouth_direction_code,
			mouth_direction_bits[direction_index]
		);
		if (direction_gate < 0.5) {
			continue;
		}
		float directional_edge = find_outward_edge_distance(
			base_uv,
			mouth_probe_steps[direction_index],
			top_here,
			wall_texels
		);
		float directional_wall = structural_wall_band(
			directional_edge,
			top_here,
			wall_texels,
			body_area
		) * direction_gate;
		if (directional_wall > structural_wall_mask) {
			wall_edge_distance = directional_edge;
		}
		structural_wall_mask = max(structural_wall_mask, directional_wall);
	}
	// A frozen roof copy never repaints a structural facade. Removing exactly
	// the direction-owned wall band exposes BASE(V)'s native break while all
	// actual top geometry remains immutable CLOSED.
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
	if (sun_occluder_mask_enabled > 0.5) {
		// Receive the sun shadow only on CLOSED-open exterior ground: pixels
		// still under the immutable roof (maw band, revealed interiors) get
		// their darkness from the maw dressing / ADR-0005 light systems instead
		// of a duplicated static stamp.
		shadow_open_space *= 1.0 - sample_sun_occluder_top(warped_base_uv);
	}
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
			float center = sample_sun_occluder_top(base_uv) * center_w;
			float left = sample_sun_occluder_top(left_uv) * left_w;
			float right = sample_sun_occluder_top(right_uv) * right_w;
			float wide_left = sample_sun_occluder_top(wide_left_uv) * wide_left_w;
			float wide_right = sample_sun_occluder_top(wide_right_uv) * wide_right_w;
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
	// ---- Physical mouth maw (BASE): the missing facade band beneath the
	// CLOSED lip reads as an unlit cavity. CLOSED-solid over V-open gives the
	// geometry, M gives the outward direction, so 1..N tile mouths on any of
	// the four sides share one code path. Translucent: the real ground floor
	// keeps showing through (no black fill, no entrance decals).
	float maw_w = 0.0;
	if (overlay_mode < 0.5
			&& sun_occluder_mask_enabled > 0.5
			&& mouth_maw_strength > 0.001
			&& top_here < 0.5
			&& body_area > 0.5) {
		float maw_direction_code = sample_mouth_direction_code_near(UV);
		if (mod(maw_direction_code, 16.0) >= 0.5) {
			float closed_top_here = sample_sun_occluder_top(warped_base_uv);
			if (closed_top_here > 0.04) {
				float maw_span_texels = max(mouth_maw_depth_px / max(sample_step_px, 0.001), 1.0);
				float exit_texels = -1.0;
				for (int direction_index = 0; direction_index < 4; direction_index++) {
					if (selector_has_bit(
							maw_direction_code,
							mouth_direction_bits[direction_index]
					) < 0.5) {
						continue;
					}
					float directional_exit = find_occluder_edge_distance(
						warped_base_uv,
						mouth_probe_steps[direction_index],
						max(closed_top_here, 0.5),
						maw_span_texels
					);
					if (directional_exit >= 0.0
							&& (exit_texels < 0.0 || directional_exit < exit_texels)) {
						exit_texels = directional_exit;
					}
				}
				float exit_px = exit_texels >= 0.0
					? exit_texels * sample_step_px
					: mouth_maw_depth_px;
				// Chip the light/dark boundary so the threshold is a broken rock
				// line, not a straight gradient edge.
				exit_px += (fbm2(world_px / 46.0 + vec2(31.0, -7.0)) - 0.5) * 12.0;
				float maw_depth = clamp(exit_px / max(mouth_maw_depth_px, 1.0), 0.0, 1.0);
				maw_w = mouth_maw_strength
					* smoothstep(0.02, 0.55, maw_depth)
					* smoothstep(0.04, 0.30, closed_top_here)
					* (1.0 - smoothstep(0.30, 0.62, top_here));
				maw_w *= 1.0 - mouth_reveal_fade * 0.65;
			}
		}
	}

	if (coverage <= 0.01 && projected_shadow <= 0.002 && maw_w <= 0.003) {
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
	if (overlay_mode > 0.5
			&& mouth_roof_lip_strength > 0.001
			&& physical_mouth_direction_enabled > 0.5
			&& top_here >= 0.5) {
		// Sun-lit upper lip over a physical mouth: the roof edge overhanging
		// the maw catches the low NW sun in a thin band just above the facade
		// cut. Gated by M sampled inside the cut band along each direction, so
		// only true mouth columns light up, never the whole massif rim. Albedo
		// -derived and daylight-gated like crest/rim lips; ROOF alpha and top
		// geometry stay immutable CLOSED (M never cuts the C surface).
		float lip_texels = max(mouth_roof_lip_px / max(sample_step_px, 0.001), 1.0);
		float lip_edge = -1.0;
		for (int direction_index = 0; direction_index < 4; direction_index++) {
			vec2 lip_probe_step = mouth_probe_steps[direction_index];
			float band_gate = max(
				selector_has_bit(
					sample_physical_mouth_direction_code(
						UV + lip_probe_step * (wall_texels * 0.70)
					),
					mouth_direction_bits[direction_index]
				),
				selector_has_bit(
					sample_physical_mouth_direction_code(
						UV + lip_probe_step * (wall_texels * 1.05)
					),
					mouth_direction_bits[direction_index]
				)
			);
			if (band_gate < 0.5) {
				continue;
			}
			float lip_directional_edge = find_outward_edge_distance(
				base_uv,
				lip_probe_step,
				top_here,
				wall_texels + lip_texels + 2.0
			);
			if (lip_directional_edge >= 0.0
					&& (lip_edge < 0.0 || lip_directional_edge < lip_edge)) {
				lip_edge = lip_directional_edge;
			}
		}
		if (lip_edge >= 0.0) {
			float lip_band = smoothstep(wall_texels - 0.9, wall_texels + 0.9, lip_edge)
				* (1.0 - smoothstep(
					wall_texels + lip_texels,
					wall_texels + lip_texels + 1.8,
					lip_edge
				));
			float lip_daylight_gate = smoothstep(0.05, 0.45, projected_shadow_opacity);
			float lip_breakup = 0.6 + small_mottle * 0.7;
			vec3 lip_lit = top_lit
				* mix(1.12, 1.42, lip_daylight_gate)
				* mix(vec3(1.0), vec3(1.14, 0.96, 0.80), lip_daylight_gate);
			top_lit = mix(
				top_lit,
				lip_lit,
				lip_band * mouth_roof_lip_strength * lip_breakup
			);
		}
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
		float wall_h = clamp(wall_edge_distance / max(wall_texels, 1.0), 0.0, 1.0);
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
		if (overlay_mode < 0.5
				&& physical_mouth_aperture_enabled > 0.5
				&& mouth_jamb_shade_strength > 0.001) {
			// Jamb corner shade: wall columns flanking a physical mouth darken
			// toward the cut so the opening gains side volume. Asymmetric against
			// the NW sun -- the jamb east of the opening falls into the deepest
			// corner shade, the sun-side jamb keeps a readable face.
			float jamb_reach_texels = max(mouth_jamb_shade_px / max(sample_step_px, 0.001), 1.0);
			vec2 jamb_step_x = vec2(texel.x, 0.0) * jamb_reach_texels;
			vec2 jamb_step_y = vec2(0.0, texel.y) * jamb_reach_texels;
			float maw_west = max(
				sample_physical_mouth_aperture_at(UV - jamb_step_x * 0.5),
				sample_physical_mouth_aperture_at(UV - jamb_step_x)
			);
			float maw_east = max(
				sample_physical_mouth_aperture_at(UV + jamb_step_x * 0.5),
				sample_physical_mouth_aperture_at(UV + jamb_step_x)
			);
			float maw_north = max(
				sample_physical_mouth_aperture_at(UV - jamb_step_y * 0.5),
				sample_physical_mouth_aperture_at(UV - jamb_step_y)
			);
			float maw_south = max(
				sample_physical_mouth_aperture_at(UV + jamb_step_y * 0.5),
				sample_physical_mouth_aperture_at(UV + jamb_step_y)
			);
			float jamb_shade = clamp(
				maw_west * 1.0 + maw_east * 0.5 + maw_north * 0.75 + maw_south * 0.55,
				0.0,
				1.0
			);
			float jamb_breakup = 0.72 + small_mottle * 0.5;
			wall_color *= 1.0 - jamb_shade
				* mouth_jamb_shade_strength
				* jamb_breakup
				* (1.0 - mouth_reveal_fade * 0.5);
		}
		float base_outline = 1.0 - smoothstep(0.0, 1.0 / max(sample_step_px, 1.0), wall_edge_distance);
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

	// Mouth maw darkness composes over whatever open-space contribution exists
	// (usually nothing or the projected shadow); ownership-weighted like the
	// wall mix so fractional maw edges never expose a bright contour.
	if (maw_w > 0.003) {
		float maw_alpha = max(out_alpha, maw_w);
		float maw_color_weight = maw_w / max(maw_alpha, 0.0001);
		color = mix(color, mouth_maw_color, clamp(maw_color_weight, 0.0, 1.0));
		out_alpha = maw_alpha;
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
	if (overlay_mode > 0.5 && roof_component_reveal_enabled > 0.5) {
		// Component ownership is tile/cavity metadata and must not inherit the
		// cosmetic crag warp. Besides the active floor, yield the exact C-V cut
		// and BASE(V) structural wall only when this component owns them.
		float displayed_weight = sample_component_reveal_weight(UV);
		float cutout_weight = sample_active_cutout_reveal_weight(warped_base_uv, UV);
		float base_facade_weight = sample_displayed_base_facade_reveal_weight(
			warped_base_uv,
			UV,
			texel,
			wall_texels,
			body_area
		);
		displayed_weight = max(displayed_weight, cutout_weight);
		displayed_weight = max(displayed_weight, base_facade_weight);
		out_alpha *= 1.0 - clamp(displayed_weight * component_reveal_blend, 0.0, 1.0);
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
