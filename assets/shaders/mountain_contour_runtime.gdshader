shader_type canvas_item;

uniform sampler2D top_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D face_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D base_albedo_tex : repeat_enable, filter_linear;
uniform sampler2D top_modulation_tex : repeat_enable, filter_linear;
uniform sampler2D face_modulation_tex : repeat_enable, filter_linear;
uniform sampler2D top_normal_tex : repeat_enable, filter_linear;
uniform sampler2D face_normal_tex : repeat_enable, filter_linear;
uniform sampler2D edge_profile_lut : repeat_disable, filter_linear;
uniform sampler2D height_profile_lut : repeat_disable, filter_linear;

uniform vec4 top_tint : source_color = vec4(1.0);
uniform vec4 face_tint : source_color = vec4(1.0);
uniform vec4 edge_tint : source_color = vec4(0.18, 0.13, 0.09, 1.0);
uniform vec4 base_tint : source_color = vec4(1.0);

uniform float top_world_scale_px = 224.0;
uniform float face_world_scale_px = 112.0;
uniform float macro_world_scale_px = 448.0;
uniform float texture_scale = 1.0;
uniform float south_height_px = 32.0;
uniform float side_height_px = 0.0;
uniform float rim_width_px = 8.0;
uniform bool mountain_outline_enabled = true;
uniform float mountain_outline_width_px = 3.0;
uniform float normal_strength = 8.0;
uniform float normal_detail_strength = 4.0;
uniform float edge_debris = 0.8;
uniform float edge_color_strength = 0.35;

varying vec2 v_world_pos;
varying vec2 v_edge_uv;
varying vec4 v_packed_attr;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_edge_uv = UV;
	v_packed_attr = COLOR;
}

vec3 unpack_normal(vec3 packed_normal) {
	return normalize(packed_normal * 2.0 - 1.0);
}

float safe_scale(float scale_px) {
	return max(1.0, scale_px * max(0.01, texture_scale));
}

vec2 world_uv(float scale_px) {
	return v_world_pos / safe_scale(scale_px);
}

void fragment() {
	float edge_u = v_edge_uv.x;
	float edge_v = clamp(v_edge_uv.y, 0.0, 1.0);

	float signed_distance_px = (v_packed_attr.r - 0.5) * 256.0;
	float face_depth_norm = clamp(v_packed_attr.g, 0.0, 1.0);
	float facade_side = floor(v_packed_attr.b * 4.0 + 0.5);
	float zone = floor(v_packed_attr.a * 8.0 + 0.5);

	float max_face_depth_px = max(1.0, south_height_px + side_height_px + (mountain_outline_enabled ? mountain_outline_width_px : 0.0));
	float face_depth_px = face_depth_norm * max_face_depth_px;
	float height_norm = clamp(face_depth_px / max(1.0, south_height_px + side_height_px), 0.0, 1.0);

	vec2 top_uv = world_uv(top_world_scale_px);
	vec2 macro_uv = world_uv(macro_world_scale_px);
	vec2 face_uv = vec2(edge_u, face_depth_px / max(1.0, face_world_scale_px));

	vec3 top_albedo = texture(top_albedo_tex, top_uv).rgb;
	vec3 face_albedo = texture(face_albedo_tex, face_uv).rgb;
	vec3 base_albedo = texture(base_albedo_tex, macro_uv).rgb;

	float top_modulation = texture(top_modulation_tex, top_uv).r;
	float face_modulation = texture(face_modulation_tex, face_uv).r;

	vec3 top_normal = unpack_normal(texture(top_normal_tex, top_uv).rgb);
	vec3 face_normal = unpack_normal(texture(face_normal_tex, face_uv).rgb);

	float edge_profile = texture(edge_profile_lut, vec2(edge_v, 0.5)).r;
	float height_profile = texture(height_profile_lut, vec2(height_norm, 0.5)).r;

	vec3 color = top_albedo;
	vec3 material_normal = top_normal;
	float alpha = 1.0;

	if (zone < 0.5) {
		color = top_albedo * mix(0.85, 1.15, top_modulation);
		material_normal = top_normal;
	} else if (zone < 1.5) {
		float height_shade = mix(0.85, 1.0, height_profile);
		color = face_albedo * height_shade * mix(0.92, 1.08, face_modulation);
		material_normal = face_normal;
	} else if (zone < 2.5) {
		vec3 top_color = top_albedo * mix(0.85, 1.15, top_modulation);
		color = mix(top_color, edge_tint.rgb, edge_profile * edge_color_strength);
		material_normal = mix(top_normal, face_normal, 0.5);
	} else {
		color = edge_tint.rgb;
		material_normal = face_normal;
	}

	float shape_z;
	if (zone < 0.5) {
		shape_z = 1.0;
	} else if (zone < 1.5) {
		shape_z = mix(1.0, 0.2, height_norm);
	} else if (zone < 2.5) {
		shape_z = mix(1.0, 0.5, edge_profile);
	} else {
		shape_z = 0.2;
	}
	float shape_xy_amount = clamp(1.0 - shape_z * shape_z, 0.0, 1.0);
	vec2 facade_dir = vec2(
		facade_side > 1.5 ? sign(edge_u - floor(edge_u + 0.5)) * 0.5 : (facade_side > 0.5 ? 1.0 : 0.0),
		facade_side < 1.5 ? 1.0 : 0.5
	);
	vec3 shape_normal = normalize(vec3(facade_dir.x * shape_xy_amount, facade_dir.y * shape_xy_amount, shape_z));

	float material_weight = clamp(normal_strength / 16.0, 0.0, 1.0);
	vec3 final_normal = normalize(mix(vec3(0.0, 0.0, 1.0), normalize(shape_normal + material_normal * material_weight), clamp(normal_strength / 8.0, 0.0, 1.0)));

	float debris_t = clamp(edge_debris * edge_profile * (1.0 - height_norm), 0.0, 1.0);
	color = mix(color, color * 0.85, debris_t * 0.4);

	COLOR = vec4(color, alpha);
	NORMAL_MAP = final_normal * 0.5 + 0.5;
}
