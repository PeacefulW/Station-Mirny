shader_type canvas_item;

// Live mountain presentation: coverage mask -> lit top ("roof") + a PROJECTED
// vertical facade ("wall"). Single cheap canvas shader fed by a per-chunk mask.
//   - the sprite covers chunk +/- halo, but only the chunk's OWN tiles are drawn
//     (chunk_uv_lo..chunk_uv_hi); the halo is still SAMPLED for the facade march
//     but never drawn -> neighbouring chunks never overdraw each other (no ghost
//     doubling / dark overlap seams);
//   - top/face textures use mipmaps (no minification shimmer when zoomed out);
//   - directional bump lighting (3D rock), lit roof rim, facade = the face texture
//     (no vertical gradient), thin black bottom outline.

uniform sampler2D top_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 top_texture_size = vec2(1024.0, 1024.0);
uniform vec2 face_texture_size = vec2(1024.0, 1024.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float top_texture_scale = 0.70;
uniform float face_texture_scale = 0.46;
uniform float texture_zoom = 0.5;
uniform float sample_step_px = 1.0;
uniform float facade_height_px = 72.0;
uniform float top_threshold_low = 0.40;
uniform float top_threshold_high = 0.58;
uniform float light_angle_deg = 234.0;
uniform float normal_strength = 3.2;
uniform float light_ambient = 0.62;
uniform float light_diffuse = 0.55;
// Draw only this chunk's own tiles; the rest of the sprite (halo) is read for the
// facade march but not drawn, so adjacent chunks never overdraw each other.
uniform float chunk_uv_lo = 0.1;
uniform float chunk_uv_hi = 0.9;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// Clip to this chunk's own area (halo is sampled below, just never drawn).
	if (UV.x < chunk_uv_lo || UV.x > chunk_uv_hi || UV.y < chunk_uv_lo || UV.y > chunk_uv_hi) {
		discard;
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = 1.0 / tex_size;
	float mask = texture(TEXTURE, UV).r;
	float top_here = smoothstep(top_threshold_low, top_threshold_high, mask);
	float exposure = clamp(1.0 - top_here * 1.2, 0.0, 1.0);

	// CONTINUOUS distance (texels) up to the silhouette edge above (sub-texel) ->
	// smooth facade, no stair-step bands.
	float facade_texels = max(1.0, facade_height_px / sample_step_px);
	int steps = int(min(facade_texels + 2.0, 96.0));
	float edge_dist = -1.0;
	float prev_top = top_here;
	for (int d = 1; d <= steps; d++) {
		float cur = smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV - vec2(0.0, texel.y * float(d))).r);
		if (cur >= 0.5 && prev_top < 0.5) {
			float t = (0.5 - prev_top) / max(cur - prev_top, 0.0001);
			edge_dist = float(d) - 1.0 + t;
			break;
		}
		prev_top = cur;
	}
	float face_cover = 0.0;
	float face_depth = 0.0;
	if (edge_dist >= 0.0) {
		face_depth = clamp(edge_dist / facade_texels, 0.0, 1.0);
		face_cover = exposure * (1.0 - smoothstep(facade_texels - 0.75, facade_texels + 0.25, edge_dist));
	}

	float coverage = max(top_here, face_cover);
	if (coverage <= 0.01) {
		discard;
	}

	vec2 world_px = world_origin_px + UV * tex_size * sample_step_px;
	float tz = max(texture_zoom, 0.01);

	// --- Directional bump lighting from the albedo luminance gradient ---
	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.62));
	float grad_px = 2.0;
	vec2 top_uv = world_px * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dx = (world_px + vec2(grad_px, 0.0)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dy = (world_px + vec2(0.0, grad_px)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec4 top_col = texture(top_texture, top_uv);
	float h_c = luma(top_col.rgb);
	float h_x = luma(texture(top_texture, top_uv_dx).rgb);
	float h_y = luma(texture(top_texture, top_uv_dy).rgb);
	vec3 top_normal = normalize(vec3((h_c - h_x) * normal_strength, (h_c - h_y) * normal_strength, 1.0));
	float top_light = light_ambient + light_diffuse * clamp(dot(top_normal, light_dir), 0.0, 1.0);
	vec3 top_lit = top_col.rgb * top_light;

	// --- Facade: the face texture itself, lit (NO vertical gradient) ---
	vec2 face_uv = world_px * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dx = (world_px + vec2(grad_px, 0.0)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dy = (world_px + vec2(0.0, grad_px)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec4 face_col = texture(face_texture, face_uv);
	float fh_c = luma(face_col.rgb);
	float fh_x = luma(texture(face_texture, face_uv_dx).rgb);
	float fh_y = luma(texture(face_texture, face_uv_dy).rgb);
	vec3 face_normal = normalize(vec3((fh_c - fh_x) * normal_strength, (fh_c - fh_y) * normal_strength, 1.0));
	float face_light = light_ambient + light_diffuse * clamp(dot(face_normal, light_dir), 0.0, 1.0);
	vec3 facade_color = face_col.rgb * face_light;

	vec3 color = mix(facade_color, top_lit, top_here);

	// Lit roof rim where the top meets the wall.
	float below_top = smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV + vec2(0.0, texel.y * 2.5)).r);
	float south_rim = top_here * (1.0 - below_top);
	color = mix(color, vec3(0.78, 0.38, 0.16), south_rim * 0.66);

	// Thin (~2px) crisp BLACK bottom outline at the wall base.
	float outline_depth = 2.0 / max(facade_height_px, 1.0);
	float bottom_outline = face_cover * smoothstep(1.0 - outline_depth * 1.5, 1.0 - outline_depth * 0.25, face_depth);
	color = mix(color, vec3(0.0, 0.0, 0.0), bottom_outline);

	// Dark outline along the rest of the silhouette (sides).
	float side_outline = smoothstep(0.08, 0.5, coverage) * (1.0 - smoothstep(0.5, 0.82, coverage));
	color = mix(color, vec3(0.02, 0.015, 0.01), side_outline * 0.7);

	float out_alpha = max(top_here * top_col.a, face_cover);
	COLOR = vec4(color, out_alpha);
}
