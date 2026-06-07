shader_type canvas_item;

// Live mountain presentation (model: "facade IS the tile").
// The dark vertical wall is rendered ON the edge mountain tile's own cell -- the
// SOUTH strip of the solid region -- NOT projected down into open space. So the
// visible wall == the real solid tile == collision == mining (WYSIWYG): dig one
// tile, stand on it, the neighbouring mountain tile is the wall right there.
//   - roof (top texture, bump-lit) on interior solid;
//   - wall (face texture, bump-lit, layered strata) on the south strip of solid
//     up to facade_height_px, with separate top rim, dark cleft, and base line;
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
uniform float top_texture_scale = 0.70;
uniform float face_texture_scale = 0.46;
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
uniform vec3 projected_shadow_color = vec3(0.030, 0.026, 0.018);
uniform float top_surface_alpha = 1.0;
uniform float wall_surface_alpha = 1.0;
uniform vec3 top_dust_tint = vec3(0.90, 0.84, 0.76);
uniform vec3 rim_highlight_color = vec3(0.93, 0.49, 0.20);
uniform vec3 cut_highlight_color = vec3(0.82, 0.39, 0.16);
uniform vec3 cleft_color = vec3(0.12, 0.045, 0.018);
uniform vec3 crack_color = vec3(0.055, 0.026, 0.012);
uniform vec3 base_debris_color = vec3(0.18, 0.075, 0.032);
uniform vec3 eave_shadow_color = vec3(0.13, 0.052, 0.022);
uniform vec3 inner_rim_color = vec3(0.70, 0.30, 0.11);
uniform vec2 chunk_uv_min = vec2(0.1, 0.1);
uniform vec2 chunk_uv_max = vec2(0.9, 0.9);
uniform vec2 shadow_uv_min = vec2(0.1, 0.1);
uniform vec2 shadow_uv_max = vec2(0.9, 0.9);
uniform vec2 shadow_draw_uv_min = vec2(0.1, 0.1);
uniform vec2 shadow_draw_uv_max = vec2(0.9, 0.9);
uniform float shadow_blend_texels = 4.0;

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

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.56;
	float total = 0.0;
	for (int i = 0; i < 3; i++) {
		v += value_noise(p) * a;
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

float shadow_axis_owner_weight(float value, float min_value, float max_value, float texel_size, float blend_texels) {
	float blend_uv = max(texel_size * max(blend_texels, 1.0), 0.0001);
	float left = smoothstep(min_value - blend_uv, min_value + blend_uv, value);
	float right = 1.0 - smoothstep(max_value - blend_uv, max_value + blend_uv, value);
	return min(left, right);
}

float shadow_owner_weight(vec2 uv, vec2 min_uv, vec2 max_uv, vec2 texel, float blend_texels) {
	float wx = shadow_axis_owner_weight(uv.x, min_uv.x, max_uv.x, texel.x, blend_texels);
	float wy = shadow_axis_owner_weight(uv.y, min_uv.y, max_uv.y, texel.y, blend_texels);
	return min(wx, wy);
}

void fragment() {
	float body_area = uv_rect_inside(UV, chunk_uv_min, chunk_uv_max);
	float shadow_draw_area = uv_rect_inside(UV, shadow_draw_uv_min, shadow_draw_uv_max);
	// Body uses a tiny opaque overlap; projected shadow uses a wider blended overlap.
	if (max(body_area, shadow_draw_area) < 0.5) {
		discard;
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = 1.0 / tex_size;
	vec2 world_px = world_origin_px + UV * tex_size * sample_step_px;
	float top_here = mask_to_top(texture(TEXTURE, UV).r);
	float top_l = mask_to_top(texture(TEXTURE, UV - vec2(texel.x, 0.0)).r);
	float top_r = mask_to_top(texture(TEXTURE, UV + vec2(texel.x, 0.0)).r);
	float top_u = mask_to_top(texture(TEXTURE, UV - vec2(0.0, texel.y)).r);
	float top_d = mask_to_top(texture(TEXTURE, UV + vec2(0.0, texel.y)).r);
	vec2 mask_grad = vec2(top_l - top_r, top_u - top_d);

	float wall_texels = max(1.0, facade_height_px / sample_step_px);
	float overhang_texels = max(1.0, overhang_px / sample_step_px);

	// SOLID pixel: continuous distance DOWN (south) to the open silhouette edge.
	float edge_below = -1.0;
	if (top_here >= 0.5) {
		float prev = top_here;
		int steps = int(min(wall_texels + 2.0, 96.0));
		for (int d = 1; d <= steps; d++) {
			float cur = mask_to_top(texture(TEXTURE, UV + vec2(0.0, texel.y * float(d))).r);
			if (cur < 0.5 && prev >= 0.5) {
				float t = (prev - 0.5) / max(prev - cur, 0.0001);
				edge_below = float(d) - 1.0 + t;
				break;
			}
			prev = cur;
		}
	}
	bool is_wall = body_area > 0.5 && top_here >= 0.5 && edge_below >= 0.0 && edge_below <= wall_texels;

	// OPEN pixel: cosmetic roof eave just below the silhouette ("козырёк").
	float overhang = 0.0;
	if (top_here < 0.5) {
		int osteps = int(min(overhang_texels + 2.0, 24.0));
		for (int d = 1; d <= osteps; d++) {
			if (mask_to_top(texture(TEXTURE, UV - vec2(0.0, texel.y * float(d))).r) >= 0.5) {
				overhang = 1.0 - smoothstep(0.0, overhang_texels, float(d) - 1.0);
				break;
			}
		}
	}
	overhang *= body_area;

	float coverage = max(top_here * body_area, overhang);
	float projected_shadow = 0.0;
	float shadow_open_space = (1.0 - smoothstep(0.08, 0.56, top_here)) * (1.0 - clamp(overhang, 0.0, 1.0) * 0.92);
	if (projected_shadow_opacity > 0.001 && projected_shadow_length_px > 1.0 && shadow_open_space > 0.001) {
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
		projected_shadow *= shadow_draw_area * shadow_owner_weight(UV, shadow_uv_min, shadow_uv_max, texel, shadow_blend_texels);
		float shadow_breakup = 0.92 + fbm2(world_px / 460.0 + vec2(8.0, -19.0)) * 0.08;
		projected_shadow = clamp(projected_shadow * shadow_open_space * projected_shadow_opacity * shadow_breakup, 0.0, projected_shadow_opacity);
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

	// Roof (top) -- mask-shape normal plus restrained texture relief.
	vec2 top_uv = world_px * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dx = (world_px + vec2(grad_px, 0.0)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dy = (world_px + vec2(0.0, grad_px)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec4 top_col = texture(top_texture, top_uv);
	top_col.rgb *= top_variation;
	top_col.rgb = mix(top_col.rgb, top_col.rgb * top_dust_tint, smoothstep(0.68, 0.96, macro) * 0.20);
	float h_c = luma(top_col.rgb);
	float h_x = luma(texture(top_texture, top_uv_dx).rgb);
	float h_y = luma(texture(top_texture, top_uv_dy).rgb);
	vec3 top_n = normalize(vec3(
		mask_grad.x * 2.2 + (h_c - h_x) * normal_strength * 0.38,
		mask_grad.y * 2.2 + (h_c - h_y) * normal_strength * 0.38,
		1.0
	));
	if (material_normal_mix > 0.001) {
		vec3 top_detail_n = unpack_normal(texture(top_normal_texture, top_uv).rgb);
		top_n = normalize(mix(top_n, blend_normals(top_n, top_detail_n), clamp(material_normal_mix, 0.0, 1.0)));
	}
	vec3 top_lit = top_col.rgb * (light_ambient + light_diffuse * clamp(dot(top_n, light_dir), 0.0, 1.0));

	// Wall -- layered strata, controlled relief, and sparse base chips.
	vec2 face_uv = world_px * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dx = (world_px + vec2(grad_px, 0.0)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dy = (world_px + vec2(0.0, grad_px)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec4 face_col = texture(face_texture, face_uv);
	face_col.rgb *= 0.86 + (macro - 0.5) * 0.10;
	float fh_c = luma(face_col.rgb);
	float fh_x = luma(texture(face_texture, face_uv_dx).rgb);
	float fh_y = luma(texture(face_texture, face_uv_dy).rgb);
	vec3 face_n = normalize(vec3(
		mask_grad.x * 1.55 + (fh_c - fh_x) * normal_strength * 0.62,
		mask_grad.y * 1.55 + (fh_c - fh_y) * normal_strength * 0.62,
		1.0
	));
	if (material_normal_mix > 0.001) {
		vec3 face_detail_n = unpack_normal(texture(face_normal_texture, face_uv).rgb);
		face_n = normalize(mix(face_n, blend_normals(face_n, face_detail_n), clamp(material_normal_mix, 0.0, 1.0)));
	}
	vec3 facade_color = face_col.rgb * (light_ambient + light_diffuse * clamp(dot(face_n, light_dir), 0.0, 1.0));

	vec3 color = top_lit;
	float out_alpha = top_here * top_col.a * top_surface_alpha;

	if (is_wall) {
		float wall_depth = clamp(edge_below / wall_texels, 0.0, 1.0); // 0 = base (south), 1 = top (north)
		float strata_noise = fbm2(vec2(world_px.x / 260.0, world_px.y / 92.0));
		float strata_wave = 0.5 + 0.5 * sin(world_px.y * 0.135 + world_px.x * 0.010 + strata_noise * 4.5);
		float strata_line = smoothstep(0.57, 0.78, strata_wave) * (1.0 - smoothstep(0.90, 1.0, strata_wave));
		float broad_layer = fbm2(vec2(world_px.x / 520.0, world_px.y / 128.0) + vec2(41.0, -13.0));
		float vertical_mass = mix(0.58, 1.04, wall_depth);
		float cut_highlight = smoothstep(0.64, 1.0, wall_depth) * (0.70 + small_mottle * 0.30);
		float cleft = smoothstep(0.48, 0.67, wall_depth) * (1.0 - smoothstep(0.77, 0.92, wall_depth));
		float base_debris = (1.0 - smoothstep(0.00, 0.125, wall_depth)) * smoothstep(0.62, 0.92, fbm2(world_px / 32.0 + vec2(12.0, 71.0)));
		float crack = smoothstep(0.80, 0.94, fbm2(vec2(world_px.x / 46.0, world_px.y / 18.0) + vec2(5.0, -31.0))) * smoothstep(0.12, 0.82, wall_depth);
		color = facade_color * vertical_mass;
		color = mix(color, color * 0.72, strata_line * 0.42);
		color = mix(color, color * 0.84, smoothstep(0.58, 0.86, broad_layer) * 0.22);
		color = mix(color, cut_highlight_color, cut_highlight * 0.22);
		color = mix(color, cleft_color, cleft * 0.28);
		color = mix(color, crack_color, crack * 0.38);
		color = mix(color, base_debris_color, base_debris * 0.55);
		float top_rim = smoothstep(0.77, 1.0, wall_depth);
		float base_outline = 1.0 - smoothstep(0.0, 1.0 / max(sample_step_px, 1.0), edge_below);
		color = mix(color, rim_highlight_color, top_rim * 0.28);
		color = mix(color, vec3(0.0, 0.0, 0.0), clamp(base_outline, 0.0, 1.0) * 0.92);
		out_alpha = wall_surface_alpha;
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

	// Thin dark outline along the solid silhouette edge (sides / non-wall).
	float silhouette = body_area * smoothstep(0.08, 0.5, top_here) * (1.0 - smoothstep(0.5, 0.82, top_here));
	float inner_rim = body_area * smoothstep(0.42, 0.72, top_here) * (1.0 - smoothstep(0.76, 0.96, top_here));
	color = mix(color, vec3(0.03, 0.02, 0.012), silhouette * 0.64);
	color = mix(color, inner_rim_color, inner_rim * 0.10 * top_here);

	COLOR = vec4(color, out_alpha);
}
