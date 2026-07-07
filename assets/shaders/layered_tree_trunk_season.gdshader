shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D snow_mask_texture : filter_linear, repeat_disable;
uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform float wind_strength_px = 2.4;
uniform float wind_speed = 1.18;
uniform float season_amount = 0.0;

void fragment() {
	vec4 wind_mask = texture(wind_mask_texture, UV);
	float wind = clamp(wind_mask.r * wind_mask.a, 0.0, 1.0);
	float trunk_wave = sin(TIME * wind_speed * 0.72 + UV.y * 4.3 + UV.x * 1.6);
	float branch_wave = sin(TIME * wind_speed * 1.25 + UV.y * 11.0 - UV.x * 2.2);
	float top_factor = smoothstep(0.18, 1.0, 1.0 - UV.y);
	float offset_px = (trunk_wave * 0.62 + branch_wave * 0.24) * wind_strength_px * 0.38 * wind * top_factor;
	vec2 sample_uv = UV - vec2(offset_px, 0.0) * TEXTURE_PIXEL_SIZE;
	vec4 albedo = texture(TEXTURE, sample_uv);
	float winter = clamp(season_amount, 0.0, 1.0);
	float frost = clamp(texture(snow_mask_texture, sample_uv).r, 0.0, 1.0);
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_bark = vec3(luma * 0.60 + 0.11, luma * 0.62 + 0.12, luma * 0.67 + 0.16);
	float bark_cool = smoothstep(0.10, 1.0, winter) * 0.56;
	albedo.rgb = mix(albedo.rgb, cold_bark, bark_cool);
	float frost_amount = smoothstep(0.12, 0.72, frost) * smoothstep(0.18, 1.0, winter) * 0.42;
	albedo.rgb = mix(albedo.rgb, vec3(0.78, 0.77, 0.72), frost_amount);
	COLOR = albedo * COLOR;
}
