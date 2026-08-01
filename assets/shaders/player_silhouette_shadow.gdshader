shader_type canvas_item;
render_mode blend_mix, unshaded;

// I2 player baked-shadow material. Despite the legacy resource filename, this
// shader no longer derives a silhouette from the albedo frame. TEXTURE is the
// matching 76x48 Cycles shadow-catcher tile, already authored toward screen SE.
// The Sprite2D offset places its baked world-origin anchor at local (0, 0).

uniform vec2 shadow_direction = vec2(0.887216, 0.461354);
uniform float shadow_length_scale = 1.0;
uniform float shadow_softness_texels = 0.75;
uniform float shadow_opacity = 0.0;
uniform vec2 shadow_frame_size_px = vec2(76.0, 48.0);
uniform vec2 shadow_anchor_px = vec2(26.0, 14.0);

varying vec4 item_color;
varying vec2 output_local_position;

void vertex() {
	item_color = COLOR;
	vec2 direction = normalize(shadow_direction + vec2(0.000001));
	vec2 transverse = vec2(-direction.y, direction.x);
	float forward_distance = dot(VERTEX, direction);
	float transverse_distance = dot(VERTEX, transverse);
	// Expand the quad far enough for the forward cast. Fragment performs the
	// one-sided inverse map, so pixels behind the anchor remain at bake length
	// exactly like the layered-tree shadow material.
	VERTEX = (
		direction * forward_distance * max(shadow_length_scale, 0.001)
		+ transverse * transverse_distance
	);
	output_local_position = VERTEX;
}

vec2 clamped_region_uv(vec2 atlas_uv, vec4 region_rect, vec2 atlas_texel_size) {
	vec2 half_texel = atlas_texel_size * 0.5;
	vec2 region_min = region_rect.xy + half_texel;
	vec2 region_max = region_rect.xy + region_rect.zw - half_texel;
	return clamp(atlas_uv, region_min, region_max);
}

void fragment() {
	vec2 direction = normalize(shadow_direction + vec2(0.000001));
	vec2 transverse = vec2(-direction.y, direction.x);
	vec2 source_local_position = output_local_position;
	float forward_distance = dot(source_local_position, direction);
	if (forward_distance > 0.0) {
		float safe_scale = max(shadow_length_scale, 0.001);
		source_local_position -= (
			direction * forward_distance * (1.0 - 1.0 / safe_scale)
		);
	}
	vec2 local_uv = (source_local_position + shadow_anchor_px) / shadow_frame_size_px;
	if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThan(local_uv, vec2(1.0)))) {
		discard;
	}
	// REGION_RECT is the selected tile in full-atlas UV coordinates. Building
	// UV from the inverse-mapped local point prevents a stretched sample from
	// crossing into the next animation frame.
	vec4 region_rect = REGION_RECT;
	vec2 atlas_texel_size = region_rect.zw / shadow_frame_size_px;
	vec2 atlas_uv = region_rect.xy + local_uv * region_rect.zw;
	vec2 tap = transverse * atlas_texel_size * max(shadow_softness_texels, 0.0);

	vec4 baked = texture(TEXTURE, clamped_region_uv(atlas_uv, region_rect, atlas_texel_size));
	float alpha = (
		baked.a * 0.50
		+ texture(
			TEXTURE,
			clamped_region_uv(atlas_uv + tap, region_rect, atlas_texel_size)
		).a * 0.25
		+ texture(
			TEXTURE,
			clamped_region_uv(atlas_uv - tap, region_rect, atlas_texel_size)
		).a * 0.25
	);
	COLOR = vec4(
		baked.rgb * item_color.rgb,
		alpha * clamp(shadow_opacity, 0.0, 1.0) * item_color.a
	);
}
