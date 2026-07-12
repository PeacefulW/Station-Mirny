shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform sampler2D season_mask_texture : filter_linear, repeat_disable;
uniform float wind_strength_px = 2.4;
uniform float wind_speed = 1.18;
uniform float season_amount = 0.0;

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
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 frozen_leaf = vec3(luma * 0.40 + 0.09, luma * 0.44 + 0.11, luma * 0.50 + 0.15);
	float freeze = smoothstep(0.08, 0.92, winter) * (0.82 + season.b * 0.12);
	albedo.rgb = mix(albedo.rgb, frozen_leaf, clamp(freeze, 0.0, 0.94));
	COLOR = albedo;
}
