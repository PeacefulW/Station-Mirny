shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D rock_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform vec2 rock_texture_size = vec2(1024.0, 1024.0);
uniform vec2 mask_texture_size = vec2(1.0, 1.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float sample_step_px = 8.0;
uniform float rock_texture_scale = 0.66;
uniform float patch_cell_px = 1450.0;
uniform float patch_density = 0.38;
uniform float patch_alpha = 0.34;
uniform float edge_clearance_px = 36.0;
uniform float terrain_threshold_low = 0.40;
uniform float terrain_threshold_high = 0.58;
uniform float chunk_uv_lo = 0.1;
uniform float chunk_uv_hi = 0.9;
uniform float normal_mix = 1.0;
uniform float normal_strength = 0.34;
uniform float light_angle_deg = 234.0;
uniform float light_ambient = 0.74;
uniform float light_diffuse = 0.20;
uniform vec3 ground_blend_tint = vec3(0.88, 0.82, 0.73);
uniform vec3 edge_shadow_tint = vec3(0.36, 0.27, 0.19);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
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
	for (int i = 0; i < 4; i++) {
		v += value_noise(p) * a;
		total += a;
		p = p * 2.03 + vec2(19.7, -11.2);
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

float terrain_mask(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return smoothstep(terrain_threshold_low, terrain_threshold_high, texture(mask_texture, uv).r);
}

float organic_rock_patch(vec2 world_px) {
	vec2 p = world_px / max(patch_cell_px, 1.0);
	vec2 broad_warp = vec2(
		fbm2(p * 0.56 + vec2(-18.0, 42.0)),
		fbm2(p * 0.61 + vec2(73.0, -15.0))
	) - vec2(0.5);
	vec2 local_warp = vec2(
		fbm2(p * 1.73 + vec2(9.0, 84.0)),
		fbm2(p * 1.58 + vec2(-61.0, 23.0))
	) - vec2(0.5);
	vec2 warped = p + broad_warp * 1.65 + local_warp * 0.50;

	float large_regions = fbm2(warped * 0.82 + vec2(14.0, -37.0));
	float medium_cut = fbm2(warped * 2.75 + vec2(-41.0, 18.0));
	float edge_breakup = fbm2(warped * 6.8 + vec2(87.0, 36.0));
	float field = large_regions * 0.76 + medium_cut * 0.16 + edge_breakup * 0.08;
	field += (edge_breakup - 0.5) * 0.13;

	float threshold = mix(0.82, 0.50, clamp(patch_density, 0.0, 1.0));
	float region = smoothstep(threshold - 0.055, threshold + 0.095, field);
	float erosion = fbm2(warped * 9.6 + vec2(51.0, -103.0));
	region = clamp(region + (erosion - 0.54) * 0.16, 0.0, 1.0);
	return smoothstep(0.20, 0.92, region);
}

void fragment() {
	if (UV.x < chunk_uv_lo || UV.x > chunk_uv_hi || UV.y < chunk_uv_lo || UV.y > chunk_uv_hi) {
		discard;
	}

	vec2 mask_size = max(mask_texture_size, vec2(1.0, 1.0));
	vec2 texel = 1.0 / max(mask_size, vec2(1.0, 1.0));
	vec2 world_px = world_origin_px + UV * mask_size * sample_step_px;

	float ground = terrain_mask(UV);
	if (ground <= 0.01) {
		discard;
	}

	float clearance_texels = max(edge_clearance_px / max(sample_step_px, 0.001), 1.0);
	float edge_safe = ground;
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(texel.x * clearance_texels, 0.0)));
	edge_safe = min(edge_safe, terrain_mask(UV - vec2(texel.x * clearance_texels, 0.0)));
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(0.0, texel.y * clearance_texels)));
	edge_safe = min(edge_safe, terrain_mask(UV - vec2(0.0, texel.y * clearance_texels)));
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(texel.x, texel.y) * clearance_texels * 0.72));
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(-texel.x, texel.y) * clearance_texels * 0.72));
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(texel.x, -texel.y) * clearance_texels * 0.72));
	edge_safe = min(edge_safe, terrain_mask(UV + vec2(-texel.x, -texel.y) * clearance_texels * 0.72));
	edge_safe = smoothstep(0.34, 0.94, edge_safe);

	float patch = organic_rock_patch(world_px);
	if (patch <= 0.01 || edge_safe <= 0.01) {
		discard;
	}

	vec2 rock_uv = world_px * rock_texture_scale / max(rock_texture_size, vec2(1.0, 1.0));
	vec2 warp = vec2(
		fbm2(world_px / 930.0 + vec2(12.0, 54.0)),
		fbm2(world_px / 890.0 + vec2(-39.0, -17.0))
	) - vec2(0.5);
	rock_uv += warp * 0.026;
	vec4 rock_sample = texture(rock_texture, rock_uv);

	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.70));
	vec3 normal = vec3(0.0, 0.0, 1.0);
	if (normal_mix > 0.001) {
		normal = normalize(mix(normal, unpack_normal(texture(rock_normal_texture, rock_uv).rgb), clamp(normal_mix, 0.0, 1.0)));
	}
	float light = light_ambient + light_diffuse * clamp(dot(normal, light_dir), 0.0, 1.0);

	float patch_edge = smoothstep(0.05, 0.35, patch) * (1.0 - smoothstep(0.58, 0.92, patch));
	float detail = smoothstep(0.28, 0.75, luma(rock_sample.rgb));
	vec3 color = rock_sample.rgb * light;
	color = mix(color, color * ground_blend_tint, 0.24);
	color = mix(color, color * edge_shadow_tint, patch_edge * 0.18);
	color *= 0.92 + detail * 0.12;

	float alpha = patch * edge_safe * patch_alpha * mix(0.62, 1.0, detail);
	alpha *= 0.86 + fbm2(world_px / 138.0 + vec2(-12.0, 44.0)) * 0.20;
	if (alpha <= 0.01) {
		discard;
	}

	COLOR = vec4(color, clamp(alpha, 0.0, 0.56) * rock_sample.a);
}
