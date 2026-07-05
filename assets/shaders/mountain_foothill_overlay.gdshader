shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D foothill_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D foothill_normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform vec2 foothill_texture_size = vec2(1024.0, 1024.0);
uniform vec2 mask_texture_size = vec2(1.0, 1.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float sample_step_px = 8.0;
uniform float texture_scale = 0.62;
uniform float outer_width_px = 116.0;
uniform float outer_width_variation_px = 0.0;
uniform float inner_width_px = 36.0;
uniform float foothill_alpha = 0.62;
uniform float footprint_fill_strength = 0.0;
// Scree debris: sparse large rock-rubble patches on the OUTER fringe of the
// apron, crumbling into individual stones via the rock texture's own luma
// (same dissolve trick as the ground material's rock patches).
uniform sampler2D scree_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 scree_texture_size = vec2(1024.0, 1024.0);
uniform float scree_strength = 0.0;
uniform float scree_texture_scale = 1.0;
uniform float scree_patch_scale_px = 760.0;
uniform float scree_coverage = 0.38;
uniform float top_threshold_low = 0.40;
uniform float top_threshold_high = 0.58;
uniform vec2 chunk_uv_min = vec2(0.1, 0.1);
uniform vec2 chunk_uv_max = vec2(0.9, 0.9);
uniform float light_angle_deg = 234.0;
uniform float light_ambient = 0.70;
uniform float light_diffuse = 0.26;
uniform bool temporary_disable_terrain_normals = true;
uniform float normal_mix = 1.0;
uniform float normal_strength = 0.42;
uniform vec3 dust_tint = vec3(0.88, 0.80, 0.70);
uniform vec3 contact_tint = vec3(0.28, 0.18, 0.10);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gradient noise (not value noise): the scree gate thresholds this field, and
// thresholded value noise grows straight lattice-aligned polygon edges.
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
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.42 * 0.5 + 0.5, 0.0, 1.0);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.56;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		v += gradient_noise(p) * a;
		total += a;
		p = p * 2.04 + vec2(17.9, -23.1);
		a *= 0.48;
	}
	return v / max(total, 0.0001);
}

vec3 unpack_normal(vec3 packed_normal) {
	vec3 n = packed_normal * 2.0 - 1.0;
	n.xy *= normal_strength;
	n.z = mix(1.0, n.z, clamp(normal_strength, 0.0, 1.0));
	return normalize(n);
}

float mountain_mask(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return smoothstep(top_threshold_low, top_threshold_high, texture(mask_texture, uv).r);
}

float chunk_clip_alpha(vec2 uv) {
	if (uv.x < chunk_uv_min.x || uv.x > chunk_uv_max.x || uv.y < chunk_uv_min.y || uv.y > chunk_uv_max.y) {
		return 0.0;
	}
	return 1.0;
}

float eight_dir_score(vec2 uv, vec2 texel, float radius_texels) {
	float score = 0.0;
	score = max(score, mountain_mask(uv + vec2(1.0, 0.0) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(-1.0, 0.0) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(0.0, 1.0) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(0.0, -1.0) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(0.7071, 0.7071) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(-0.7071, 0.7071) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(0.7071, -0.7071) * texel * radius_texels));
	score = max(score, mountain_mask(uv + vec2(-0.7071, -0.7071) * texel * radius_texels));
	return score;
}

float eight_dir_open_score(vec2 uv, vec2 texel, float radius_texels) {
	float score = 0.0;
	score = max(score, 1.0 - mountain_mask(uv + vec2(1.0, 0.0) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(-1.0, 0.0) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(0.0, 1.0) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(0.0, -1.0) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(0.7071, 0.7071) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(-0.7071, 0.7071) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(0.7071, -0.7071) * texel * radius_texels));
	score = max(score, 1.0 - mountain_mask(uv + vec2(-0.7071, -0.7071) * texel * radius_texels));
	return score;
}

void fragment() {
	float clip_alpha = chunk_clip_alpha(UV);
	if (clip_alpha <= 0.001) {
		discard;
	}

	vec2 mask_size = max(mask_texture_size, vec2(1.0, 1.0));
	vec2 texel = 1.0 / mask_size;
	vec2 world_px = world_origin_px + UV * mask_size * sample_step_px;
	float solid = mountain_mask(UV);

	float width_field = fbm2(world_px / 840.0 + vec2(-51.0, 74.0));
	float width_lobes = smoothstep(0.46, 0.86, width_field);
	float width_breakup = fbm2(world_px / 310.0 + vec2(103.0, -9.0));
	float organic_outer_width_px = outer_width_px + outer_width_variation_px * width_lobes * mix(0.68, 1.0, width_breakup);
	float outer_texels = max(organic_outer_width_px / max(sample_step_px, 0.001), 1.0);
	float inner_texels = max(inner_width_px / max(sample_step_px, 0.001), 1.0);
	float outer_score = 0.0;
	float inner_score = 0.0;
	for (int i = 1; i <= 5; i++) {
		float t = float(i) / 5.0;
		float w = pow(1.0 - t * 0.82, 1.16);
		outer_score = max(outer_score, eight_dir_score(UV, texel, outer_texels * t) * w);
		inner_score = max(inner_score, eight_dir_open_score(UV, texel, inner_texels * t) * w);
	}

	float outside_band = (1.0 - solid) * outer_score;
	float inside_band = solid * inner_score * 0.42;
	float edge_band = max(outside_band, inside_band);
	float footprint_fill = solid
		* clamp(footprint_fill_strength, 0.0, 1.0)
		* mix(0.46, 0.62, fbm2(world_px / 1180.0 + vec2(67.0, -42.0)));
	float band = max(edge_band, footprint_fill);
	if (band <= 0.01) {
		discard;
	}

	float broad = fbm2(world_px / 520.0 + vec2(23.0, -11.0));
	float gravel_break = fbm2(world_px / 150.0 + vec2(-7.0, 39.0));
	float feather = max(smoothstep(0.06, 0.82, edge_band), footprint_fill * 0.78);
	float organic_alpha = 0.76 + (broad - 0.5) * 0.30 + (gravel_break - 0.5) * 0.18;
	float alpha = clamp(feather * foothill_alpha * organic_alpha, 0.0, 0.78);
	alpha *= clip_alpha;
	// Scree fringe: the outer tail of the apron ring, where the apron itself
	// is already fading out.
	float scree_fringe = smoothstep(0.02, 0.10, outside_band) * (1.0 - smoothstep(0.34, 0.60, outside_band));
	if (alpha <= 0.01 && scree_fringe * scree_strength <= 0.01) {
		discard;
	}

	vec2 tex_uv = world_px * texture_scale / max(foothill_texture_size, vec2(1.0));
	vec2 warped_uv = tex_uv + (vec2(
		fbm2(world_px / 740.0 + vec2(5.0, 83.0)),
		fbm2(world_px / 690.0 + vec2(-31.0, 17.0))
	) - vec2(0.5)) * 0.035;
	vec4 sample_col = texture(foothill_texture, warped_uv);
	float detail = smoothstep(0.24, 0.78, luma(sample_col.rgb));

	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.72));
	vec3 normal = vec3(0.0, 0.0, 1.0);
	if (!temporary_disable_terrain_normals && normal_mix > 0.001) {
		normal = normalize(mix(normal, unpack_normal(texture(foothill_normal_texture, warped_uv).rgb), clamp(normal_mix, 0.0, 1.0)));
	}
	float light = light_ambient + light_diffuse * clamp(dot(normal, light_dir), 0.0, 1.0);

	vec3 color = sample_col.rgb * light;
	color = mix(color, color * dust_tint, smoothstep(0.58, 0.96, broad) * 0.20);
	color = mix(color, color * contact_tint, smoothstep(0.30, 0.86, edge_band) * 0.18);
	color *= 0.90 + detail * 0.16;

	float scree = 0.0;
	if (scree_strength > 0.001 && scree_fringe > 0.001) {
		vec4 rock_sample = texture(scree_texture, world_px * scree_texture_scale / max(scree_texture_size, vec2(1.0, 1.0)));
		float rock_detail = smoothstep(0.30, 0.70, luma(rock_sample.rgb)) - 0.5;
		float scree_field = fbm2(world_px / max(scree_patch_scale_px, 1.0) + vec2(43.0, -11.0));
		float scree_threshold = mix(0.86, 0.52, clamp(scree_coverage, 0.0, 1.0));
		// Luma dissolve: the patch boundary crumbles into individual stones
		// instead of a soft airbrushed blob.
		float gate = smoothstep(scree_threshold - 0.09, scree_threshold + 0.09, scree_field + rock_detail * 0.26);
		scree = gate * scree_fringe * scree_strength;
		vec3 scree_color = rock_sample.rgb * light * (0.90 + rock_detail * 0.34);
		color = mix(color, scree_color, clamp(scree * 1.6, 0.0, 1.0));
	}

	float final_alpha = max(alpha, clamp(scree, 0.0, 1.0) * 0.92 * clip_alpha);
	COLOR = vec4(color, final_alpha * sample_col.a);
}
