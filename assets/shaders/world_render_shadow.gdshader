shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D world_shadow_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D actor_shadow_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D render_descriptor_lut : filter_nearest, repeat_disable;
uniform sampler2D render_variant_anchor_lut : filter_nearest, repeat_disable;

uniform float render_descriptor_capacity = 64.0;
uniform float render_descriptor_lut_rows = 5.0;
uniform float render_variant_capacity = 256.0;
uniform vec2 shadow_direction = vec2(0.887216, 0.461354);
uniform float shadow_length_scale = 1.0;
uniform float object_shadow_opacity = 0.0;
uniform float object_shadow_softness_texels = 0.75;
uniform float ground_shadow_opacity = 0.88;
uniform bool ground_profiles_visible = true;
uniform bool object_profiles_visible = true;
uniform bool actor_profiles_visible = true;

const float FLAG_ACTOR = 4.0;
const float FLAG_GROUND = 32.0;

varying vec4 instance_data;
varying vec4 custom_data;
varying vec4 descriptor_layout_flags;
varying vec4 descriptor_shadow_rect;
varying vec2 descriptor_shadow_frame_texel;
varying vec2 descriptor_variant_anchor;
varying vec2 actor_output_world_delta;
varying vec2 actor_anchor_world_delta;
varying vec2 actor_inverse_row_x;
varying vec2 actor_inverse_row_y;

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

vec2 variant_anchor(float descriptor_id, float variant_index) {
	return textureLod(
		render_variant_anchor_lut,
		vec2(
			(variant_index + 0.5) / max(render_variant_capacity, 1.0),
			(descriptor_id + 0.5) / max(render_descriptor_capacity, 1.0)
		),
		0.0
	).rg;
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

void vertex() {
	instance_data = COLOR;
	custom_data = INSTANCE_CUSTOM;
	bool compact_ground = custom_data.z > 0.0;
	if (compact_ground) {
		descriptor_layout_flags = vec4(0.0);
		descriptor_shadow_rect = vec4(0.0);
		descriptor_shadow_frame_texel = vec2(0.0);
		descriptor_variant_anchor = vec2(0.0);
	} else {
		descriptor_layout_flags = descriptor_row(custom_data.x, 2.0);
		descriptor_shadow_rect = descriptor_row(custom_data.x, 1.0);
		descriptor_shadow_frame_texel = descriptor_row(custom_data.x, 4.0).rg;
		descriptor_variant_anchor = variant_anchor(custom_data.x, custom_data.y);
	}
	float flags = descriptor_layout_flags.a;
	if (!compact_ground && has_flag(flags, FLAG_ACTOR)) {
		mat2 model_2x2 = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
		float det = model_2x2[0].x * model_2x2[1].y
			- model_2x2[1].x * model_2x2[0].y;
		float safe_det = abs(det) > 0.000001 ? det : 0.000001;
		mat2 inv_model_2x2 = mat2(
			vec2(model_2x2[1].y, -model_2x2[0].y),
			vec2(-model_2x2[1].x, model_2x2[0].x)
		) / safe_det;
		vec2 anchor_local = instance_data.gb - vec2(0.5);
		vec2 anchor_world = model_2x2 * anchor_local;
		vec2 output_world = model_2x2 * VERTEX;
		vec2 direction = normalize(shadow_direction + vec2(0.000001));
		vec2 delta = output_world - anchor_world;
		float forward_distance = dot(delta, direction);
		if (forward_distance > 0.0) {
			delta += direction * forward_distance * (max(custom_data.w, 0.001) - 1.0);
		}
		output_world = anchor_world + delta;
		VERTEX = inv_model_2x2 * output_world;
		actor_output_world_delta = output_world;
		actor_anchor_world_delta = anchor_world;
		actor_inverse_row_x = vec2(inv_model_2x2[0].x, inv_model_2x2[1].x);
		actor_inverse_row_y = vec2(inv_model_2x2[0].y, inv_model_2x2[1].y);
	}
}

void fragment() {
	if (custom_data.z > 0.0) {
		if (!ground_profiles_visible) {
			discard;
		}
		vec2 half_texel = TEXTURE_PIXEL_SIZE * 0.5;
		vec2 uv = mix(
			custom_data.xy + half_texel,
			custom_data.xy + custom_data.zw - half_texel,
			sprite_uv(UV)
		);
		vec4 shadow = texture(world_shadow_atlas, uv);
		shadow.a *= ground_shadow_opacity * clamp(instance_data.a, 0.0, 1.0);
		if (shadow.a <= 0.001) {
			discard;
		}
		COLOR = shadow;
	} else {
	float descriptor_id = custom_data.x;
	float variant_index = custom_data.y;
	vec4 layout_flags = descriptor_layout_flags;
	vec4 shadow_rect = descriptor_shadow_rect;
	vec2 shadow_frame_texel = descriptor_shadow_frame_texel;
	bool actor = has_flag(layout_flags.a, FLAG_ACTOR);
	if (actor) {
		if (!actor_profiles_visible) {
			discard;
		}
		vec2 direction = normalize(shadow_direction + vec2(0.000001));
		vec2 source_world = actor_output_world_delta;
		vec2 delta = source_world - actor_anchor_world_delta;
		float forward_distance = dot(delta, direction);
		if (forward_distance > 0.0) {
			float safe_scale = max(custom_data.w, 0.001);
			delta -= direction * forward_distance * (1.0 - 1.0 / safe_scale);
		}
		source_world = actor_anchor_world_delta + delta;
		vec2 source_local = vec2(
			dot(actor_inverse_row_x, source_world),
			dot(actor_inverse_row_y, source_world)
		) + vec2(0.5);
		if (any(lessThan(source_local, vec2(0.0)))
				|| any(greaterThan(source_local, vec2(1.0)))) {
			discard;
		}
		vec2 transverse = vec2(-direction.y, direction.x);
		vec2 tap = transverse * shadow_frame_texel * max(instance_data.r, 0.0);
		vec2 uv = packed_atlas_uv(
			source_local, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
		);
		vec2 uv_plus = packed_atlas_uv(
			source_local + tap, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
		);
		vec2 uv_minus = packed_atlas_uv(
			source_local - tap, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
		);
		vec4 baked = texture(actor_shadow_atlas, uv);
		float alpha = baked.a * 0.50
			+ texture(actor_shadow_atlas, uv_plus).a * 0.25
			+ texture(actor_shadow_atlas, uv_minus).a * 0.25;
		alpha *= clamp(instance_data.a, 0.0, 1.0);
		if (alpha <= 0.001) {
			discard;
		}
		COLOR = vec4(baked.rgb, alpha);
	} else {
	if (!object_profiles_visible) {
		discard;
	}
	vec4 output_crop = vec4(instance_data.rgb, custom_data.w);
	vec2 output_point = output_crop.xy + sprite_uv(UV) * output_crop.zw;
	vec2 anchor = descriptor_variant_anchor;
	vec2 direction = normalize(shadow_direction);
	vec2 delta = output_point - anchor;
	float forward_distance = dot(delta, direction);
	if (forward_distance > 0.0) {
		float safe_scale = max(shadow_length_scale, 0.001);
		delta -= direction * forward_distance * (1.0 - 1.0 / safe_scale);
	}
	vec2 source_uv = anchor + delta;
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		discard;
	}
	vec2 uv = packed_atlas_uv(
		source_uv, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
	);
	vec4 shadow = texture(world_shadow_atlas, uv);
	vec2 perpendicular = vec2(-direction.y, direction.x);
	vec2 blur_offset = perpendicular * shadow_frame_texel
		* max(object_shadow_softness_texels, 0.0);
	vec2 positive_uv = source_uv + blur_offset;
	vec2 negative_uv = source_uv - blur_offset;
	float positive_alpha = 0.0;
	float negative_alpha = 0.0;
	// Taps outside this variant contribute no coverage, rather than reading a
	// neighbouring packed atlas frame or extending its border alpha.
	if (!any(lessThan(positive_uv, vec2(0.0))) && !any(greaterThan(positive_uv, vec2(1.0)))) {
		positive_alpha = texture(world_shadow_atlas, packed_atlas_uv(
			positive_uv, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
		)).a;
	}
	if (!any(lessThan(negative_uv, vec2(0.0))) && !any(greaterThan(negative_uv, vec2(1.0)))) {
		negative_alpha = texture(world_shadow_atlas, packed_atlas_uv(
			negative_uv, variant_index, shadow_rect, layout_flags.xyz, shadow_frame_texel
		)).a;
	}
	shadow.a = (shadow.a * 0.50 + positive_alpha * 0.25 + negative_alpha * 0.25)
		* object_shadow_opacity * clamp(instance_data.a, 0.0, 1.0);
	if (shadow.a <= 0.001) {
		discard;
	}
	COLOR = shadow;
	}
	}
}
