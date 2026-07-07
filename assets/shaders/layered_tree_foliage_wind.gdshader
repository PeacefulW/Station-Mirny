shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform sampler2D season_mask_texture : filter_linear, repeat_disable;
uniform float wind_strength_px = 2.4;
uniform float wind_speed = 0.72;
uniform float season_amount = 0.0;
uniform float leaf_drop_strength = 0.92;

void fragment() {
	vec4 mask = texture(wind_mask_texture, UV);
	float wind = clamp(mask.r * mask.a, 0.0, 1.0);
	float wave_a = sin(TIME * wind_speed * 2.1 + UV.y * 19.0 + UV.x * 5.0);
	float wave_b = sin(TIME * wind_speed * 1.3 + UV.y * 8.0 - UV.x * 3.0);
	float offset_px = (wave_a * 0.65 + wave_b * 0.35) * wind_strength_px * wind;
	vec2 sample_uv = UV - vec2(offset_px, 0.0) * TEXTURE_PIXEL_SIZE;
	vec4 albedo = texture(TEXTURE, sample_uv);
	vec4 season = texture(season_mask_texture, sample_uv);
	float winter = clamp(season_amount, 0.0, 1.0);
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_leaf = vec3(luma * 0.78 + 0.10, luma * 0.80 + 0.11, luma * 0.82 + 0.14);
	float pale = clamp(winter * (0.45 + season.b * 0.55), 0.0, 0.92);
	albedo.rgb = mix(albedo.rgb, cold_leaf, pale);
	float drop_order = clamp(season.g, 0.0, 1.0);
	float drop = smoothstep(drop_order * 0.90, drop_order * 0.90 + 0.12, winter);
	float late_winter = smoothstep(0.52, 1.0, winter);
	albedo.a *= 1.0 - drop * late_winter * leaf_drop_strength;
	COLOR = albedo * COLOR;
}
