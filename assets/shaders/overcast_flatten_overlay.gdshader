shader_type canvas_item;
render_mode blend_mix;

// Surface-only overcast flatten pass. Reads the already-rendered surface and
// pulls it toward a cold neutral grey with compressed contrast. This is
// presentation response (ADR-0007 layer 4), not gameplay light authority.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float flatten_strength = 0.0;
uniform vec3 overcast_gray = vec3(0.46, 0.48, 0.52);
uniform float desaturate_amount = 0.72;
uniform float contrast_cut = 0.58;
uniform float flatten_opacity = 0.88;

void fragment() {
	float strength = clamp(flatten_strength, 0.0, 1.0);
	if (strength < 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec3 src = texture(screen_texture, SCREEN_UV).rgb;
		float luma = dot(src, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(src, vec3(luma), desaturate_amount * strength);
		vec3 compressed = overcast_gray + (desaturated - overcast_gray) * (1.0 - contrast_cut * strength);
		COLOR = vec4(compressed, strength * flatten_opacity);
	}
}
