shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform sampler2D season_mask_texture : filter_linear, repeat_disable;
uniform float wind_strength_px = 2.4;
uniform float wind_speed = 1.18;
uniform float season_amount = 0.0;
uniform float leaf_drop_strength = 0.26;

void fragment() {
	vec4 mask = texture(wind_mask_texture, UV);
	float wind = clamp(mask.r * mask.a, 0.0, 1.0);
	float wave_a = sin(TIME * wind_speed * 2.1 + UV.y * 19.0 + UV.x * 5.0);
	float wave_b = sin(TIME * wind_speed * 1.3 + UV.y * 8.0 - UV.x * 3.0);
	float top_factor = smoothstep(0.24, 1.0, 1.0 - UV.y);
	float top_sway = sin(TIME * wind_speed * 0.82 + UV.y * 3.0 + UV.x * 1.7);
	float offset_px = (wave_a * 0.52 + wave_b * 0.28 + top_sway * top_factor * 1.08) * wind_strength_px * wind;
	vec2 sample_uv = UV - vec2(offset_px, 0.0) * TEXTURE_PIXEL_SIZE;
	vec4 albedo = texture(TEXTURE, sample_uv);
	vec4 season = texture(season_mask_texture, sample_uv);
	float winter = clamp(season_amount, 0.0, 1.0);
	float snow_cover = clamp(season.r, 0.0, 1.0);
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_leaf = vec3(luma * 0.48 + 0.13, luma * 0.49 + 0.14, luma * 0.53 + 0.17);
	vec3 buried_leaf = vec3(luma * 0.34 + 0.24, luma * 0.35 + 0.24, luma * 0.37 + 0.25);
	float full_winter = smoothstep(0.54, 1.0, winter);
	vec3 winter_leaf = mix(cold_leaf, buried_leaf, full_winter);
	float pale = clamp(winter * 0.90 + season.b * winter * 0.38 + snow_cover * winter * 0.62 + full_winter * 0.74, 0.0, 1.0);
	albedo.rgb = mix(albedo.rgb, winter_leaf, pale);
	float drop_order = clamp(season.g, 0.0, 1.0);
	float drop = smoothstep(drop_order * 0.90, drop_order * 0.90 + 0.12, winter);
	float late_winter = smoothstep(0.52, 1.0, winter);
	albedo.a *= 1.0 - drop * late_winter * leaf_drop_strength;
	albedo.a *= 1.0 - smoothstep(0.16, 0.82, snow_cover) * smoothstep(0.42, 1.0, winter) * 0.38;
	COLOR = albedo * COLOR;
}
