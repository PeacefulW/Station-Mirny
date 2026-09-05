shader_type canvas_item;
render_mode blend_mix;

// Painter-sensitive bodies share one pass. Families select descriptor data;
// only storage/lighting semantics branch, never a family id or sampler bank.
global uniform vec2 wind_direction;
global uniform float wind_strength;

uniform sampler2D world_body_base_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D world_foliage_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D world_snow_overlay_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D world_wind_mask_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D world_snow_mask_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D world_season_mask_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D actor_body_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D render_descriptor_lut : filter_nearest, repeat_disable;
uniform sampler2D render_variant_crop_lut : filter_nearest, repeat_disable;

uniform float render_descriptor_capacity = 64.0;
uniform float render_descriptor_lut_rows = 5.0;
uniform float render_variant_capacity = 256.0;
uniform float season_amount = 0.0;
uniform bool object_profiles_visible = true;
uniform bool actor_profiles_visible = true;
uniform float tree_wind_speed = 1.18;
uniform float leaf_drop_strength = 0.26;

const float FLAG_LAYERED = 1.0;
const float FLAG_SEASONAL_SIMPLE = 2.0;
const float FLAG_ACTOR = 4.0;

varying vec4 instance_data;
varying vec4 descriptor_body_rect;
varying vec4 descriptor_layout_flags;
varying vec4 descriptor_frame_pass;
varying vec4 render_crop;
varying float frame_index;

bool has_flag(float flags, float bit) {
	return mod(floor(flags / bit), 2.0) >= 1.0;
}

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

vec4 variant_crop(float descriptor_id, float variant_index) {
	return textureLod(
		render_variant_crop_lut,
		vec2(
			(variant_index + 0.5) / max(render_variant_capacity, 1.0),
			(descriptor_id + 0.5) / max(render_descriptor_capacity, 1.0)
		),
		0.0
	);
}

vec2 sprite_uv(vec2 mesh_uv) {
	return vec2(mesh_uv.x, 1.0 - mesh_uv.y);
}

vec2 packed_atlas_uv(
		vec2 local_uv,
		float variant_index,
		vec4 pack_rect,
		vec3 layout,
		vec2 frame_texel_size) {
	float safe_index = clamp(floor(variant_index + 0.5), 0.0, layout.z - 1.0);
	vec2 cell = vec2(mod(safe_index, layout.x), floor(safe_index / layout.x));
	vec2 half_texel = frame_texel_size * 0.5;
	vec2 family_uv = (
		cell + clamp(local_uv, half_texel, vec2(1.0) - half_texel)
	) / layout.xy;
	return pack_rect.xy + family_uv * pack_rect.zw;
}

vec4 alpha_over(vec4 top, vec4 bottom) {
	float out_alpha = top.a + bottom.a * (1.0 - top.a);
	if (out_alpha <= 0.00001) {
		return vec4(0.0);
	}
	vec3 out_rgb = (
		top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)
	) / out_alpha;
	return vec4(out_rgb, out_alpha);
}

vec4 layered_body(vec2 local_uv, vec2 screen_uv) {
	vec3 layout = descriptor_layout_flags.xyz;
	vec2 texel_size = descriptor_frame_pass.rg;
	float wind_strength_px = descriptor_frame_pass.b;
	vec2 mask_uv = packed_atlas_uv(
		local_uv, frame_index, descriptor_body_rect, layout, texel_size
	);
	vec4 wind_mask = texture(world_wind_mask_atlas, mask_uv);
	if (wind_mask.a <= 0.001) {
		discard;
	}
	float wind = clamp(wind_mask.r * wind_mask.a, 0.0, 1.0);
	float wind_gate = smoothstep(0.0, 0.12, wind_strength);
	float trunk_wave = sin(TIME * tree_wind_speed * 0.72 + local_uv.y * 4.3 + local_uv.x * 1.6);
	float branch_wave = sin(TIME * tree_wind_speed * 1.25 + local_uv.y * 11.0 - local_uv.x * 2.2);
	float top_factor = smoothstep(0.18, 1.0, 1.0 - local_uv.y);
	float trunk_offset_px = (trunk_wave * 0.62 + branch_wave * 0.24)
		* wind_strength_px * 0.38 * wind * top_factor * wind_gate;
	vec2 trunk_uv = clamp(
		local_uv - vec2(trunk_offset_px, 0.0) * texel_size,
		vec2(0.0),
		vec2(1.0)
	);
	vec2 trunk_atlas_uv = packed_atlas_uv(
		trunk_uv, frame_index, descriptor_body_rect, layout, texel_size
	);
	vec4 trunk = texture(world_body_base_atlas, trunk_atlas_uv);
	float winter = clamp(season_amount, 0.0, 1.0);
	if (winter > 0.001) {
		float frost = clamp(texture(world_snow_mask_atlas, trunk_atlas_uv).r, 0.0, 1.0);
		float trunk_luma = dot(trunk.rgb, vec3(0.299, 0.587, 0.114));
		vec3 cold_bark = vec3(
			trunk_luma * 0.60 + 0.11,
			trunk_luma * 0.62 + 0.12,
			trunk_luma * 0.67 + 0.16
		);
		trunk.rgb = mix(trunk.rgb, cold_bark, smoothstep(0.10, 1.0, winter) * 0.56);
		trunk.rgb = mix(
			trunk.rgb,
			vec3(0.78, 0.77, 0.72),
			smoothstep(0.12, 0.72, frost) * smoothstep(0.18, 1.0, winter) * 0.42
		);
	}

	float wave_a = sin(TIME * tree_wind_speed * 2.1 + local_uv.y * 19.0 + local_uv.x * 5.0);
	float wave_b = sin(TIME * tree_wind_speed * 1.3 + local_uv.y * 8.0 - local_uv.x * 3.0);
	float foliage_top_factor = smoothstep(0.24, 1.0, 1.0 - local_uv.y);
	float top_sway = sin(TIME * tree_wind_speed * 0.82 + local_uv.y * 3.0 + local_uv.x * 1.7);
	float foliage_offset_px = (
		wave_a * 0.52 + wave_b * 0.28 + top_sway * foliage_top_factor * 1.08
	) * wind_strength_px * wind * wind_gate;
	vec2 foliage_uv = clamp(
		local_uv - vec2(foliage_offset_px, 0.0) * texel_size,
		vec2(0.0),
		vec2(1.0)
	);
	vec2 foliage_atlas_uv = packed_atlas_uv(
		foliage_uv, frame_index, descriptor_body_rect, layout, texel_size
	);
	vec4 foliage = texture(world_foliage_atlas, foliage_atlas_uv);
	if (winter <= 0.001) {
		return alpha_over(foliage, trunk);
	}
	vec4 season = texture(world_season_mask_atlas, foliage_atlas_uv);
	float snow_cover = clamp(season.r, 0.0, 1.0);
	float foliage_luma = dot(foliage.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_leaf = vec3(
		foliage_luma * 0.48 + 0.13,
		foliage_luma * 0.49 + 0.14,
		foliage_luma * 0.53 + 0.17
	);
	vec3 buried_leaf = vec3(
		foliage_luma * 0.34 + 0.24,
		foliage_luma * 0.35 + 0.24,
		foliage_luma * 0.37 + 0.25
	);
	float full_winter = smoothstep(0.54, 1.0, winter);
	vec3 winter_leaf = mix(cold_leaf, buried_leaf, full_winter);
	float pale = clamp(
		winter * 0.90 + season.b * winter * 0.38 + snow_cover * winter * 0.62
			+ full_winter * 0.74,
		0.0,
		1.0
	);
	foliage.rgb = mix(foliage.rgb, winter_leaf, pale);
	float drop_order = clamp(season.g, 0.0, 1.0);
	float drop = smoothstep(drop_order * 0.90, drop_order * 0.90 + 0.12, winter);
	foliage.a *= 1.0 - drop * smoothstep(0.52, 1.0, winter) * leaf_drop_strength;
	foliage.a *= 1.0
		- smoothstep(0.16, 0.82, snow_cover) * smoothstep(0.42, 1.0, winter) * 0.38;
	vec4 snow = texture(world_snow_overlay_atlas, mask_uv);
	float snow_mask = clamp(texture(world_snow_mask_atlas, mask_uv).r, 0.0, 1.0);
	float threshold = mix(0.96, 0.08, winter);
	snow.a *= smoothstep(threshold - 0.10, threshold + 0.08, snow_mask)
		* smoothstep(0.06, 0.28, winter);
	return alpha_over(snow, alpha_over(foliage, trunk));
}

void vertex() {
	instance_data = COLOR;
	float descriptor_id = INSTANCE_CUSTOM.x;
	frame_index = INSTANCE_CUSTOM.y;
	descriptor_body_rect = descriptor_row(descriptor_id, 0.0);
	descriptor_layout_flags = descriptor_row(descriptor_id, 2.0);
	descriptor_frame_pass = descriptor_row(descriptor_id, 3.0);
	render_crop = variant_crop(descriptor_id, frame_index);
}

void fragment() {
	float flags = descriptor_layout_flags.a;
	bool actor = has_flag(flags, FLAG_ACTOR);
	if ((actor && !actor_profiles_visible) || (!actor && !object_profiles_visible)) {
		discard;
	}
	vec2 local_uv = render_crop.xy + sprite_uv(UV) * render_crop.zw;
	vec2 uv = packed_atlas_uv(
		local_uv,
		frame_index,
		descriptor_body_rect,
		descriptor_layout_flags.xyz,
		descriptor_frame_pass.rg
	);
	vec4 body;
	if (actor) {
		body = texture(actor_body_atlas, uv);
		body.rgb *= instance_data.rgb;
	} else if (has_flag(flags, FLAG_LAYERED)) {
		body = layered_body(local_uv, SCREEN_UV);
	} else {
		body = texture(world_body_base_atlas, uv);
		if (body.a <= 0.001) {
			discard;
		}
		body.rgb *= clamp(instance_data.g, 0.0, 1.0);
		if (has_flag(flags, FLAG_SEASONAL_SIMPLE)) {
			float winter = clamp(season_amount, 0.0, 1.0);
			if (winter > 0.001) {
				vec4 snow = texture(world_snow_overlay_atlas, uv);
				float mask = clamp(texture(world_snow_mask_atlas, uv).r, 0.0, 1.0);
				float threshold = mix(0.96, 0.08, winter);
				snow.a *= smoothstep(threshold - 0.10, threshold + 0.08, mask)
					* smoothstep(0.06, 0.28, winter);
				body = alpha_over(snow, body);
			}
		}
	}
	body.a *= clamp(instance_data.a, 0.0, 1.0);
	if (body.a <= 0.001) {
		discard;
	}
	COLOR = body;
}
