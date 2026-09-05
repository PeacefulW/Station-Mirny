shader_type canvas_item;
render_mode blend_mix;

// Cheap mass pass. Ground records never compile the foliage/season/actor
// pipeline; sprite selection still comes from the shared descriptor tables.
global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform vec2 wind_gust_scroll_px;
global uniform float wind_gustiness;

uniform sampler2D world_body_base_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D render_descriptor_lut : filter_nearest, repeat_disable;
uniform sampler2D render_variant_crop_lut : filter_nearest, repeat_disable;
uniform sampler2D grass_gust_noise : filter_linear, repeat_enable;
uniform sampler2D ground_field_3 : repeat_disable, filter_linear;

uniform float render_descriptor_capacity = 64.0;
uniform float render_descriptor_lut_rows = 5.0;
uniform float render_variant_capacity = 256.0;
uniform vec2 ground_field_origin_world = vec2(0.0);
uniform vec2 ground_field_grid_size = vec2(1.0);
uniform float ground_field_step_px = 32.0;
uniform bool ground_field_ready = false;
uniform bool ground_profiles_visible = true;

uniform float grass_wind_sway_fraction = 0.085;
uniform float grass_storm_lean_fraction = 0.35;
uniform float grass_storm_lean_start = 0.45;
uniform float grass_gust_field_scale_px = 420.0;
uniform float grass_gust_field_anisotropy = 2.6;
uniform float grass_local_dir_min_deg = 5.0;
uniform float grass_local_dir_max_deg = 26.0;
uniform float grass_local_dir_gust_gain = 0.9;
uniform float grass_intra_tuft_flutter = 0.05;
uniform float grass_gust_contrast_low = 0.42;
uniform float grass_gust_contrast_high = 0.80;
uniform float grass_gust_noise_period_cells = 256.0;
uniform float grass_alpha_cutoff = 0.02;
uniform float grass_macro_warm_strength = 0.10;
uniform float grass_macro_dry_strength = 0.22;

varying vec4 instance_data;
varying vec2 v_world_pos;
varying float v_grass_gust;
varying vec4 v_render_crop;
varying vec4 v_pack_rect;
varying vec4 v_layout_flags;
varying float v_frame_index;

vec4 descriptor_row(float descriptor_id, float row) {
	return textureLod(
		render_descriptor_lut,
		vec2(
			(descriptor_id + 0.5) / max(render_descriptor_capacity, 1.0),
			(row + 0.5) / max(render_descriptor_lut_rows, 1.0)
		),
		0.0
	);
}

vec4 variant_crop(float descriptor_id, float frame_index) {
	return textureLod(
		render_variant_crop_lut,
		vec2(
			(frame_index + 0.5) / max(render_variant_capacity, 1.0),
			(descriptor_id + 0.5) / max(render_descriptor_capacity, 1.0)
		),
		0.0
	);
}

vec2 ground_field_uv(vec2 world_pos) {
	vec2 grid_coord = (world_pos - ground_field_origin_world) / max(ground_field_step_px, 0.001);
	return (grid_coord + vec2(0.5)) / max(ground_field_grid_size, vec2(1.0));
}

vec2 sprite_uv(vec2 mesh_uv) {
	return vec2(mesh_uv.x, 1.0 - mesh_uv.y);
}

vec2 packed_atlas_uv(vec2 local_uv, float frame_index, vec4 pack_rect, vec3 layout) {
	float safe_index = clamp(floor(frame_index + 0.5), 0.0, layout.z - 1.0);
	vec2 cell = vec2(mod(safe_index, layout.x), floor(safe_index / layout.x));
	vec2 family_uv = (cell + clamp(local_uv, vec2(0.0), vec2(1.0))) / layout.xy;
	return pack_rect.xy + family_uv * pack_rect.zw;
}

void vertex() {
	instance_data = COLOR;
	float descriptor_id = INSTANCE_CUSTOM.x;
	float frame_index = INSTANCE_CUSTOM.y;
	v_frame_index = frame_index;
	v_pack_rect = descriptor_row(descriptor_id, 0.0);
	v_layout_flags = descriptor_row(descriptor_id, 2.0);
	v_render_crop = variant_crop(descriptor_id, frame_index);
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_world_pos = world_pos;
	v_grass_gust = 0.0;
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	vec2 across = vec2(-dir.y, dir.x);
	vec2 gust_pos = world_pos - wind_gust_scroll_px;
	vec2 gust_uv = vec2(
		dot(gust_pos, dir) / max(grass_gust_field_scale_px, 1.0),
		dot(gust_pos, across) / max(grass_gust_field_scale_px * grass_gust_field_anisotropy, 1.0)
	);
	float gust = smoothstep(
		grass_gust_contrast_low,
		grass_gust_contrast_high,
		textureLod(
			grass_gust_noise,
			gust_uv / max(grass_gust_noise_period_cells, 1.0),
			0.0
		).r
	);
	v_grass_gust = gust;
	float wind_phase = instance_data.b * 6.28318530718;
	float primary = sin(wind_time * 0.92 + wind_phase);
	float flutter = sin(wind_time * 1.45 + wind_phase * 1.73 + UV.y * 1.30);
	float full_image_y = v_render_crop.y + (1.0 - UV.y) * v_render_crop.w;
	float blade_weight = smoothstep(0.05, 1.0, 1.0 - full_image_y);
	float amplitude_gate = smoothstep(0.0, 0.15, wind_strength);
	float ambient = primary * 0.07 + flutter * 0.05;
	float gust_sway = gust * (0.85 + primary * 0.30 + flutter * 0.18);
	float dir_field = textureLod(ground_field_3, ground_field_uv(world_pos), 0.0).b * 2.0 - 1.0;
	float local_amp = radians(mix(
		grass_local_dir_min_deg,
		grass_local_dir_max_deg,
		clamp(wind_gustiness, 0.0, 1.0)
	));
	float local_angle = local_amp * dir_field * (0.4 + gust * grass_local_dir_gust_gain) * amplitude_gate;
	float lca = cos(local_angle);
	float lsa = sin(local_angle);
	vec2 local_dir = vec2(dir.x * lca - dir.y * lsa, dir.x * lsa + dir.y * lca);
	vec2 local_across = vec2(-local_dir.y, local_dir.x);
	float storm_wobble = sin(wind_time * 2.3 + wind_phase * 1.31) * 0.22
		+ sin(wind_time * 3.7 + wind_phase) * 0.10;
	float storm_lean = grass_storm_lean_fraction
		* smoothstep(grass_storm_lean_start, 1.0, wind_strength)
		* (1.0 + storm_wobble);
	float oscillation = (gust_sway + ambient) * grass_wind_sway_fraction;
	float intra = sin(wind_time * 2.6 + wind_phase * 1.9 + UV.x * 6.28318530718 + UV.y * 3.0);
	float intra_amp = grass_intra_tuft_flutter * (0.35 + gust * 0.65);
	mat2 model_2x2 = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	float det = model_2x2[0].x * model_2x2[1].y - model_2x2[1].x * model_2x2[0].y;
	float safe_det = abs(det) > 0.000001 ? det : 0.000001;
	mat2 inv_model_2x2 = mat2(
		vec2(model_2x2[1].y, -model_2x2[0].y),
		vec2(-model_2x2[1].x, model_2x2[0].x)
	) / safe_det;
	float tuft_height_px = length(MODEL_MATRIX[1].xy) / max(v_render_crop.w, 0.001);
	float blade = blade_weight * blade_weight;
	vec2 world_offset = (
		local_dir * oscillation + dir * storm_lean + local_across * intra * intra_amp
	) * amplitude_gate * tuft_height_px * blade;
	VERTEX += inv_model_2x2 * world_offset;
}

void fragment() {
	if (!ground_profiles_visible || !ground_field_ready) {
		discard;
	}
	vec2 local_uv = v_render_crop.xy + sprite_uv(UV) * v_render_crop.zw;
	vec2 uv = packed_atlas_uv(local_uv, v_frame_index, v_pack_rect, v_layout_flags.xyz);
	vec4 atlas_color = texture(world_body_base_atlas, uv);
	if (atlas_color.a <= grass_alpha_cutoff) {
		discard;
	}
	float tint = clamp(instance_data.g, 0.0, 1.35);
	vec3 col = atlas_color.rgb * tint;
	vec4 grass_fields = texture(ground_field_3, ground_field_uv(v_world_pos));
	float warm = grass_fields.r - 0.5;
	float dry = grass_fields.g;
	col.r *= 1.0 + warm * grass_macro_warm_strength;
	col.b *= 1.0 - warm * grass_macro_warm_strength * 1.4;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(
		col,
		vec3(luma) * vec3(1.07, 1.0, 0.84),
		smoothstep(0.55, 0.92, dry) * grass_macro_dry_strength
	);
	COLOR = vec4(col, atlas_color.a * instance_data.a);
}
