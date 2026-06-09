shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D grass_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_texture_2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_texture_3 : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform vec2 grass_texture_size = vec2(1024.0, 1024.0);
uniform vec2 grass_texture_size_2 = vec2(1024.0, 1024.0);
uniform vec2 grass_texture_size_3 = vec2(1024.0, 1024.0);
uniform vec2 mask_texture_size = vec2(1.0, 1.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float sample_step_px = 8.0;
uniform float grass_texture_scale = 0.78;
uniform float patch_cell_px = 1850.0;
uniform float patch_density = 0.50;
uniform float patch_alpha = 0.52;
uniform float edge_clearance_px = 22.0;
uniform float edge_feather_low = 0.10;
uniform float edge_feather_high = 0.68;
uniform float max_alpha = 0.94;
uniform float normal_mix = 0.0;
uniform float normal_strength = 0.18;
uniform float light_angle_deg = 234.0;
uniform float light_ambient = 0.76;
uniform float light_diffuse = 0.24;
uniform float terrain_threshold_low = 0.40;
uniform float terrain_threshold_high = 0.58;
uniform vec2 chunk_uv_min = vec2(0.1, 0.1);
uniform vec2 chunk_uv_max = vec2(0.9, 0.9);
uniform vec3 dry_grass_tint = vec3(1.0, 1.0, 1.0);
uniform vec3 contact_shadow_tint = vec3(0.34, 0.18, 0.08);

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
	for (int i = 0; i < 3; i++) {
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

float chunk_clip_alpha(vec2 uv) {
	if (uv.x < chunk_uv_min.x || uv.x > chunk_uv_max.x || uv.y < chunk_uv_min.y || uv.y > chunk_uv_max.y) {
		return 0.0;
	}
	return 1.0;
}

float organic_region_mask(vec2 world_px) {
	vec2 p = world_px / max(patch_cell_px, 1.0);
	vec2 broad_warp = vec2(
		fbm2(p * 0.72 + vec2(13.4, -8.9)),
		fbm2(p * 0.69 + vec2(-31.7, 24.1))
	) - vec2(0.5);
	vec2 local_warp = vec2(
		fbm2(p * 1.86 + vec2(71.0, 9.5)),
		fbm2(p * 1.61 + vec2(-44.6, 58.2))
	) - vec2(0.5);
	vec2 warped = p + broad_warp * 1.55 + local_warp * 0.42;

	float large_regions = fbm2(warped * 0.94 + vec2(5.1, 17.3));
	float medium_cut = fbm2(warped * 2.15 + vec2(-19.0, 41.0));
	float edge_breakup = fbm2(warped * 5.8 + vec2(62.0, -27.0));
	float field = large_regions * 0.70 + medium_cut * 0.22 + edge_breakup * 0.08;
	field += (edge_breakup - 0.5) * 0.10;

	float threshold = mix(0.76, 0.43, clamp(patch_density, 0.0, 1.0));
	float region = smoothstep(threshold - 0.065, threshold + 0.085, field);

	float erosion = fbm2(warped * 8.5 + vec2(-3.0, 103.0));
	region = clamp(region + (erosion - 0.52) * 0.18, 0.0, 1.0);
	return smoothstep(0.16, 0.86, region);
}

void fragment() {
	float clip_alpha = chunk_clip_alpha(UV);
	if (clip_alpha <= 0.001) {
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
	edge_safe = smoothstep(0.36, 0.92, edge_safe);

	float patch = organic_region_mask(world_px);
	float feather_noise = fbm2(world_px / 182.0 + vec2(18.0, -54.0)) - 0.5;
	float feather_low = clamp(edge_feather_low + feather_noise * 0.045, 0.0, 0.92);
	float feather_high = clamp(edge_feather_high + feather_noise * 0.060, feather_low + 0.04, 1.0);
	float patch_soft = smoothstep(feather_low, feather_high, patch);
	if (patch_soft <= 0.01 || edge_safe <= 0.01) {
		discard;
	}

	vec2 grass_uv = world_px * grass_texture_scale / max(grass_texture_size, vec2(1.0, 1.0));
	vec2 grass_uv_2 = world_px * grass_texture_scale / max(grass_texture_size_2, vec2(1.0, 1.0));
	vec2 grass_uv_3 = world_px * grass_texture_scale / max(grass_texture_size_3, vec2(1.0, 1.0));
	vec4 grass_sample_1 = texture(grass_texture, grass_uv);
	vec4 grass_sample_2 = texture(grass_texture_2, grass_uv_2 + vec2(0.137, -0.071));
	vec4 grass_sample_3 = texture(grass_texture_3, grass_uv_3 + vec2(-0.093, 0.119));

	float variant_field = fbm2(world_px / 1480.0 + vec2(42.0, -17.0));
	float dense_field = fbm2(world_px / 820.0 + vec2(-88.0, 36.0));
	float medium_mix = smoothstep(0.30, 0.68, variant_field);
	float dense_mix = smoothstep(0.58, 0.91, variant_field * 0.72 + dense_field * 0.28);
	vec4 grass_sample = mix(grass_sample_1, grass_sample_2, medium_mix);
	grass_sample = mix(grass_sample, grass_sample_3, dense_mix);
	float detail = smoothstep(0.32, 0.72, luma(grass_sample.rgb));
	float patch_edge = smoothstep(0.05, 0.30, patch_soft) * (1.0 - smoothstep(0.54, 0.92, patch_soft));
	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.70));
	vec3 normal = vec3(0.0, 0.0, 1.0);
	if (normal_mix > 0.001) {
		normal = normalize(mix(
			normal,
			unpack_normal(texture(grass_normal_texture, grass_uv).rgb),
			clamp(normal_mix, 0.0, 1.0)
		));
	}
	float light = light_ambient + light_diffuse * clamp(dot(normal, light_dir), 0.0, 1.0);

	vec3 color = grass_sample.rgb * dry_grass_tint * light;
	color = mix(color, color * contact_shadow_tint, patch_edge * 0.10);
	color *= 0.97 + fbm2(world_px / 390.0 + vec2(31.0, -7.0)) * 0.08;

	float alpha = patch_soft * edge_safe * patch_alpha * mix(0.88, 1.0, detail);
	alpha *= 0.94 + fbm2(world_px / 114.0 + vec2(3.0, 61.0)) * 0.10;
	alpha *= clip_alpha;
	if (alpha <= 0.01) {
		discard;
	}

	COLOR = vec4(color, clamp(alpha, 0.0, max_alpha));
}
