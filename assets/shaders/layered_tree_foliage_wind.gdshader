shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform float wind_strength_px = 2.4;
uniform float wind_speed = 0.72;

void fragment() {
	vec4 mask = texture(wind_mask_texture, UV);
	float wind = clamp(mask.r * mask.a, 0.0, 1.0);
	float wave_a = sin(TIME * wind_speed * 2.1 + UV.y * 19.0 + UV.x * 5.0);
	float wave_b = sin(TIME * wind_speed * 1.3 + UV.y * 8.0 - UV.x * 3.0);
	float offset_px = (wave_a * 0.65 + wave_b * 0.35) * wind_strength_px * wind;
	vec2 sample_uv = UV - vec2(offset_px, 0.0) * TEXTURE_PIXEL_SIZE;
	vec4 albedo = texture(TEXTURE, sample_uv);
	COLOR = albedo * COLOR;
}
