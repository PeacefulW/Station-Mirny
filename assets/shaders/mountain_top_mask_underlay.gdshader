shader_type canvas_item;

// Live mountain presentation: coverage mask -> lit top ("roof") + a PROJECTED
// vertical facade ("wall"). The facade is found by marching upward in the mask
// to the nearest top edge above (south-facing wall), so the silhouette reads as
// "wall with roof" without baking per-chunk textures. Collision stays on the top
// silhouette (the mask hit test); the facade is visual-only overhang.
// Tunable via uniforms below (height, gradient tone, rim, texture, thresholds).

uniform sampler2D top_texture : filter_linear, repeat_enable;
uniform sampler2D face_texture : filter_linear, repeat_enable;
uniform vec2 top_texture_size = vec2(1024.0, 1024.0);
uniform vec2 face_texture_size = vec2(1024.0, 1024.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float top_texture_scale = 0.70;
uniform float face_texture_scale = 0.46;
uniform float sample_step_px = 1.0;
uniform float facade_height_px = 72.0;
uniform float top_threshold_low = 0.40;
uniform float top_threshold_high = 0.58;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = 1.0 / tex_size;
	float mask = texture(TEXTURE, UV).r;
	float top_here = smoothstep(top_threshold_low, top_threshold_high, mask);
	float exposure = clamp(1.0 - top_here * 1.2, 0.0, 1.0);

	// Project the facade: find the nearest top coverage above this pixel within
	// facade_height. found_texels grows downward, so the wall is lit at the top
	// and dark at the bottom.
	float facade_texels = max(1.0, facade_height_px / sample_step_px);
	int steps = int(min(facade_texels + 2.0, 96.0));
	float face_cover = 0.0;
	float found_texels = 0.0;
	for (int d = 1; d <= steps; d++) {
		float fd = float(d);
		float above = texture(TEXTURE, UV - vec2(0.0, texel.y * fd)).r;
		float above_top = smoothstep(top_threshold_low, top_threshold_high, above);
		float candidate = above_top * exposure;
		if (candidate > face_cover) {
			face_cover = candidate;
			found_texels = fd;
		}
	}
	float face_depth = clamp(found_texels / facade_texels, 0.0, 1.0);
	// Anti-alias the wall base instead of a hard horizontal cut.
	float bottom_feather = 1.0 - smoothstep(facade_texels - 2.5, facade_texels + 0.5, found_texels);
	face_cover *= bottom_feather;

	float coverage = max(top_here, face_cover);
	if (coverage <= 0.01) {
		discard;
	}

	vec2 world_px = world_origin_px + UV * tex_size * sample_step_px;
	vec4 top_col = texture(top_texture, world_px * top_texture_scale / max(top_texture_size, vec2(1.0, 1.0)));
	vec4 face_col = texture(face_texture, world_px * face_texture_scale / max(face_texture_size, vec2(1.0, 1.0)));

	// Facade shading: top-lit -> bottom-dark gradient, lightly textured by the
	// face texture (modulated by the gradient so the tone stays controlled).
	vec3 face_top_color = vec3(0.52, 0.21, 0.075);
	vec3 face_bottom_color = vec3(0.13, 0.04, 0.016);
	vec3 face_base = mix(face_top_color, face_bottom_color, smoothstep(0.0, 1.0, face_depth));
	vec3 facade_color = mix(face_base, face_col.rgb * face_base * 2.0, 0.30);
	facade_color = mix(facade_color, face_bottom_color, face_depth * 0.22);

	vec3 color = mix(facade_color, top_col.rgb, top_here);

	// Lit rim where the roof meets the wall (top with non-top just below).
	float below_top = smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV + vec2(0.0, texel.y * 2.5)).r);
	float south_rim = top_here * (1.0 - below_top);
	color = mix(color, vec3(0.74, 0.34, 0.13), south_rim * 0.62);

	// Soft contact shadow on the wall just under the roof rim, for depth.
	float wall_top = face_cover * (1.0 - smoothstep(0.0, 0.18, face_depth));
	color = mix(color, face_bottom_color, wall_top * 0.20);

	// Dark outline along the whole silhouette (sides + feathered facade base).
	float outline = smoothstep(0.08, 0.5, coverage) * (1.0 - smoothstep(0.5, 0.82, coverage));
	color = mix(color, vec3(0.05, 0.03, 0.02), outline * 0.8);

	float out_alpha = max(top_here * top_col.a, face_cover);
	COLOR = vec4(color, out_alpha);
}
