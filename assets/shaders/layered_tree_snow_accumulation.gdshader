shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D snow_mask_texture : filter_linear, repeat_disable;
uniform float season_amount = 0.0;

void fragment() {
	vec4 snow = texture(TEXTURE, UV);
	float mask = clamp(texture(snow_mask_texture, UV).r, 0.0, 1.0);
	float winter = clamp(season_amount, 0.0, 1.0);
	float threshold = mix(0.96, 0.08, winter);
	float coverage = smoothstep(threshold - 0.10, threshold + 0.08, mask);
	float arrival = smoothstep(0.06, 0.28, winter);
	snow.a *= coverage * arrival;
	COLOR = snow * COLOR;
}
