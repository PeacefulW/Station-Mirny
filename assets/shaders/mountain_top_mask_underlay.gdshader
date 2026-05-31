shader_type canvas_item;

// Live mountain presentation (model: "facade IS the tile").
// The dark vertical wall is rendered ON the edge mountain tile's own cell -- the
// SOUTH strip of the solid region -- NOT projected down into open space. So the
// visible wall == the real solid tile == collision == mining (WYSIWYG): dig one
// tile, stand on it, the neighbouring mountain tile is the wall right there.
//   - roof (top texture, bump-lit) on interior solid;
//   - wall (face texture, bump-lit, no vertical gradient) on the south strip of
//     solid up to facade_height_px, with a lit top rim + thin black base line;
//   - a small COSMETIC roof eave ("козырёк") drawn a few px below the silhouette;
//   - only the chunk's own tiles are drawn (halo is sampled, not drawn) -> no
//     neighbour overdraw; top/face textures use mipmaps (no minification shimmer).

uniform sampler2D top_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 top_texture_size = vec2(1024.0, 1024.0);
uniform vec2 face_texture_size = vec2(1024.0, 1024.0);
uniform vec2 world_origin_px = vec2(0.0, 0.0);
uniform float top_texture_scale = 0.70;
uniform float face_texture_scale = 0.46;
uniform float texture_zoom = 0.5;
uniform float sample_step_px = 1.0;
uniform float facade_height_px = 72.0; // height of the south wall strip WITHIN the solid tile
uniform float overhang_px = 8.0;       // cosmetic roof eave projected below the silhouette
uniform float top_threshold_low = 0.40;
uniform float top_threshold_high = 0.58;
uniform float light_angle_deg = 234.0;
uniform float normal_strength = 3.2;
uniform float light_ambient = 0.62;
uniform float light_diffuse = 0.55;
uniform float chunk_uv_lo = 0.1;
uniform float chunk_uv_hi = 0.9;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// Draw only this chunk's own tiles (halo is sampled below, never drawn).
	if (UV.x < chunk_uv_lo || UV.x > chunk_uv_hi || UV.y < chunk_uv_lo || UV.y > chunk_uv_hi) {
		discard;
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = 1.0 / tex_size;
	float top_here = smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV).r);

	float wall_texels = max(1.0, facade_height_px / sample_step_px);
	float overhang_texels = max(1.0, overhang_px / sample_step_px);

	// SOLID pixel: continuous distance DOWN (south) to the open silhouette edge.
	float edge_below = -1.0;
	if (top_here >= 0.5) {
		float prev = top_here;
		int steps = int(min(wall_texels + 2.0, 96.0));
		for (int d = 1; d <= steps; d++) {
			float cur = smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV + vec2(0.0, texel.y * float(d))).r);
			if (cur < 0.5 && prev >= 0.5) {
				float t = (prev - 0.5) / max(prev - cur, 0.0001);
				edge_below = float(d) - 1.0 + t;
				break;
			}
			prev = cur;
		}
	}
	bool is_wall = top_here >= 0.5 && edge_below >= 0.0 && edge_below <= wall_texels;

	// OPEN pixel: cosmetic roof eave just below the silhouette ("козырёк").
	float overhang = 0.0;
	if (top_here < 0.5) {
		int osteps = int(min(overhang_texels + 2.0, 24.0));
		for (int d = 1; d <= osteps; d++) {
			if (smoothstep(top_threshold_low, top_threshold_high, texture(TEXTURE, UV - vec2(0.0, texel.y * float(d))).r) >= 0.5) {
				overhang = 1.0 - smoothstep(0.0, overhang_texels, float(d) - 1.0);
				break;
			}
		}
	}

	float coverage = max(top_here, overhang);
	if (coverage <= 0.01) {
		discard;
	}

	vec2 world_px = world_origin_px + UV * tex_size * sample_step_px;
	float tz = max(texture_zoom, 0.01);
	float a = radians(light_angle_deg);
	vec3 light_dir = normalize(vec3(cos(a), sin(a), 0.62));
	float grad_px = 2.0;

	// Roof (top) -- bump-lit top texture.
	vec2 top_uv = world_px * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dx = (world_px + vec2(grad_px, 0.0)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec2 top_uv_dy = (world_px + vec2(0.0, grad_px)) * top_texture_scale / tz / max(top_texture_size, vec2(1.0));
	vec4 top_col = texture(top_texture, top_uv);
	float h_c = luma(top_col.rgb);
	float h_x = luma(texture(top_texture, top_uv_dx).rgb);
	float h_y = luma(texture(top_texture, top_uv_dy).rgb);
	vec3 top_n = normalize(vec3((h_c - h_x) * normal_strength, (h_c - h_y) * normal_strength, 1.0));
	vec3 top_lit = top_col.rgb * (light_ambient + light_diffuse * clamp(dot(top_n, light_dir), 0.0, 1.0));

	// Wall -- bump-lit face texture (no vertical gradient).
	vec2 face_uv = world_px * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dx = (world_px + vec2(grad_px, 0.0)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec2 face_uv_dy = (world_px + vec2(0.0, grad_px)) * face_texture_scale / tz / max(face_texture_size, vec2(1.0));
	vec4 face_col = texture(face_texture, face_uv);
	float fh_c = luma(face_col.rgb);
	float fh_x = luma(texture(face_texture, face_uv_dx).rgb);
	float fh_y = luma(texture(face_texture, face_uv_dy).rgb);
	vec3 face_n = normalize(vec3((fh_c - fh_x) * normal_strength, (fh_c - fh_y) * normal_strength, 1.0));
	vec3 facade_color = face_col.rgb * (light_ambient + light_diffuse * clamp(dot(face_n, light_dir), 0.0, 1.0));

	vec3 color = top_lit;
	float out_alpha = top_here * top_col.a;

	if (is_wall) {
		float wall_depth = clamp(edge_below / wall_texels, 0.0, 1.0); // 0 = base (south), 1 = top (north)
		color = facade_color;
		// Lit rim where the wall meets the roof (top of the strip).
		float rim = smoothstep(0.74, 1.0, wall_depth);
		color = mix(color, vec3(0.78, 0.38, 0.16), rim * 0.5);
		// Thin (~2px) black line at the wall base (south edge).
		float base_outline = 1.0 - smoothstep(0.0, 2.0 / max(sample_step_px, 1.0), edge_below);
		color = mix(color, vec3(0.0, 0.0, 0.0), clamp(base_outline, 0.0, 1.0));
		out_alpha = 1.0;
	}

	// Cosmetic roof eave over the open space just below the silhouette.
	if (!is_wall && overhang > 0.0) {
		color = mix(color, top_lit * 0.42, overhang);
		out_alpha = max(out_alpha, overhang);
	}

	// Thin dark outline along the solid silhouette edge (sides / non-wall).
	float silhouette = smoothstep(0.08, 0.5, top_here) * (1.0 - smoothstep(0.5, 0.82, top_here));
	color = mix(color, vec3(0.03, 0.02, 0.012), silhouette * 0.6);

	COLOR = vec4(color, out_alpha);
}
