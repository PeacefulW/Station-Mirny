shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D snow_mask_texture : filter_linear, repeat_disable;
uniform sampler2D season_mask_texture : filter_linear, repeat_disable;
uniform float season_amount = 0.0;

void fragment() {
	vec4 snow = texture(TEXTURE, UV);
	vec4 snow_mask = texture(snow_mask_texture, UV);
	vec4 season = texture(season_mask_texture, UV);
	float winter = clamp(season_amount, 0.0, 1.0);
	float threshold = mix(0.96, 0.08, winter);
	float coverage = smoothstep(threshold - 0.10, threshold + 0.08, snow_mask.r);
	float arrival = smoothstep(0.06, 0.28, winter);
	float foliage_membership = smoothstep(0.04, 0.22, season.a);
	float frost_variation = 0.72 + 0.28 * sin(UV.x * 193.0 + UV.y * 271.0);
	float frost_alpha = foliage_membership * arrival * (0.065 + season.b * frost_variation * 0.105);
	float snow_alpha = snow.a * coverage * arrival;
	float combined_alpha = frost_alpha + snow_alpha * (1.0 - frost_alpha);
	vec3 frost_color = vec3(0.72, 0.80, 0.88);
	vec3 combined_rgb = frost_color;
	if (combined_alpha > 0.0001) {
		combined_rgb = (
			frost_color * frost_alpha
			+ snow.rgb * snow_alpha * (1.0 - frost_alpha)
		) / combined_alpha;
	}
	COLOR = vec4(combined_rgb, combined_alpha);
}
