shader_type canvas_item;

uniform sampler2D mask_texture : filter_linear;
uniform sampler2D height_texture : filter_linear;
uniform sampler2D normal_texture : filter_linear;
uniform vec2 chunk_origin_px = vec2(0.0, 0.0);
uniform float tile_size_px = 64.0;

uniform sampler2D top_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D base_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D top_modulation : repeat_enable, filter_linear;
uniform sampler2D face_modulation : repeat_enable, filter_linear;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;

uniform float base_world_scale_px = 512.0;
uniform float top_world_scale_px = 512.0;
uniform float face_world_scale_px = 512.0;
uniform float face_height_px = 10.0;
uniform float face_power = 2.5;
uniform float detail_normal_strength = 1.0;
uniform vec4 edge_color : source_color = vec4(0.286, 0.220, 0.173, 1.0);
uniform float edge_color_strength = 0.35;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

vec3 blend_normals(vec3 base_normal, vec3 detail_normal) {
	return normalize(vec3(
		base_normal.xy + detail_normal.xy * detail_normal_strength,
		max(0.001, base_normal.z * detail_normal.z)
	));
}

vec2 repeat_uv(vec2 coord_px, float scale_px) {
	return fract(coord_px / max(1.0, scale_px));
}

vec2 contour_tangent(vec3 shape_normal) {
	vec2 gradient = shape_normal.xy;
	if (dot(gradient, gradient) < 0.0001) {
		return vec2(1.0, 0.0);
	}
	vec2 normal_2d = normalize(gradient);
	return normalize(vec2(-normal_2d.y, normal_2d.x));
}

vec2 face_material_coord(vec3 shape_normal, float height_value) {
	vec2 tangent = contour_tangent(shape_normal);
	float along = abs(dot(world_pos, tangent));
	float progress = 1.0 - pow(clamp(height_value, 0.0, 1.0), 1.0 / max(0.01, face_power));
	float depth = clamp(progress, 0.0, 1.0) * max(1.0, face_height_px);
	return vec2(along, depth);
}

void fragment() {
	vec4 mask = texture(mask_texture, UV);
	float alpha = clamp(mask.a, 0.0, 1.0);
	if (alpha < 0.01) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		float top_mask = clamp(mask.r, 0.0, 1.0);
		float face_mask = clamp(mask.g, 0.0, 1.0);
		float back_mask = clamp(mask.b, 0.0, 1.0);
		float coverage_sum = top_mask + face_mask + back_mask;
		if (coverage_sum < 0.001) {
			top_mask = alpha;
			coverage_sum = alpha;
		}
		float total_mask = max(coverage_sum, 0.001);

		vec3 shape_normal = unpack_normal(texture(normal_texture, UV).rgb);
		float height_value = texture(height_texture, UV).r;
		vec2 top_uv = repeat_uv(world_pos, top_world_scale_px);
		vec2 face_uv = repeat_uv(face_material_coord(shape_normal, height_value), face_world_scale_px);

		vec3 top_color = texture(top_albedo_tex, top_uv).rgb;
		vec3 face_color = texture(face_albedo_tex, face_uv).rgb;
		vec3 back_color = face_color;
		vec3 surface_color = (
			top_color * top_mask +
			face_color * face_mask +
			back_color * back_mask
		) / total_mask;

		float edge_mix = clamp(min(top_mask, face_mask + back_mask) * edge_color_strength, 0.0, 1.0);
		surface_color = mix(surface_color, edge_color.rgb, edge_mix);
		vec3 final_color = surface_color;

		vec3 top_detail_normal = unpack_normal(texture(top_normal_tex, top_uv).rgb);
		vec3 face_detail_normal = unpack_normal(texture(face_normal_tex, face_uv).rgb);
		vec3 detail_normal = normalize(
			top_detail_normal * top_mask +
			face_detail_normal * (face_mask + back_mask) +
			vec3(0.0, 0.0, 1.0) * max(0.0, 1.0 - total_mask)
		);
		vec3 final_normal = blend_normals(shape_normal, detail_normal);

		COLOR = vec4(final_color, alpha);
		NORMAL_MAP = final_normal * 0.5 + 0.5;
	}
}
