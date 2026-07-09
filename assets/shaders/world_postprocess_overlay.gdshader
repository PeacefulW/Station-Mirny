shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform bool effect_enabled = true;
uniform float grade_strength = 0.14;
uniform float vignette_strength = 0.16;
uniform float edge_shadow_strength = 0.10;
uniform float warm_bloom_strength = 0.055;

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	if (!effect_enabled) {
		COLOR = source;
	} else {
		vec3 color = source.rgb;
		float lum = luminance(color);

		vec3 shadow_tint = vec3(0.92, 0.96, 1.05);
		vec3 warm_tint = vec3(1.05, 0.99, 0.90);
		float highlight_weight = smoothstep(0.34, 0.88, lum);
		vec3 graded = mix(color * shadow_tint, color * warm_tint, highlight_weight);
		color = mix(color, graded, grade_strength);

		float saturation = 1.0 + grade_strength * 0.28;
		color = mix(vec3(luminance(color)), color, saturation);
		float contrast = 1.0 + grade_strength * 0.42;
		color = (color - vec3(0.5)) * contrast + vec3(0.5);

		float warm_signal = max(max(color.r, color.g) - color.b * 0.55, 0.0);
		float warm_peak = smoothstep(0.68, 1.12, warm_signal) * smoothstep(0.45, 0.95, lum);
		color += vec3(1.0, 0.55, 0.18) * warm_peak * warm_bloom_strength;

		vec2 centered = SCREEN_UV * 2.0 - 1.0;
		float radial = dot(centered, centered);
		float vignette = smoothstep(0.34, 1.18, radial);
		color *= 1.0 - vignette * vignette_strength;

		float edge = max(abs(centered.x), abs(centered.y));
		float edge_shadow = smoothstep(0.70, 1.02, edge);
		color *= 1.0 - edge_shadow * edge_shadow_strength;

		COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
	}
}
