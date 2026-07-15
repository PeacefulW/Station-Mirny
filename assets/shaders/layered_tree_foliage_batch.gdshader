shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform sampler2D season_mask_texture : filter_linear, repeat_disable;
uniform float atlas_columns = 5.0;
uniform float atlas_rows = 1.0;
uniform float atlas_frame_count = 5.0;
uniform vec2 frame_texel_size = vec2(0.0013020833);
uniform float wind_strength_px = 3.0;
uniform float wind_speed = 1.18;
uniform float season_amount = 0.0;
uniform float leaf_drop_strength = 0.26;

varying vec4 instance_data;

// Primitive QuadMesh uses the 3D V direction; PNG atlases use Canvas top-left.
vec2 sprite_uv(vec2 mesh_uv) {
	return vec2(mesh_uv.x, 1.0 - mesh_uv.y);
}

void vertex() {
	instance_data = COLOR;
}

vec2 frame_uv(vec2 local_uv, float frame_index) {
	float safe_index = clamp(floor(frame_index + 0.5), 0.0, atlas_frame_count - 1.0);
	vec2 cell = vec2(mod(safe_index, atlas_columns), floor(safe_index / atlas_columns));
	vec2 half_texel = frame_texel_size * 0.5;
	return (cell + clamp(local_uv, half_texel, vec2(1.0) - half_texel)) / vec2(atlas_columns, atlas_rows);
}

void fragment() {
	float frame_index = floor(clamp(instance_data.r, 0.0, 1.0) * 255.0 + 0.5);
	vec2 local_uv = sprite_uv(UV);
	vec2 local_texel_size = TEXTURE_PIXEL_SIZE * vec2(atlas_columns, atlas_rows);
	vec4 mask = texture(wind_mask_texture, frame_uv(local_uv, frame_index));
	float wind = clamp(mask.r * mask.a, 0.0, 1.0);
	float wave_a = sin(TIME * wind_speed * 2.1 + local_uv.y * 19.0 + local_uv.x * 5.0);
	float wave_b = sin(TIME * wind_speed * 1.3 + local_uv.y * 8.0 - local_uv.x * 3.0);
	float top_factor = smoothstep(0.24, 1.0, 1.0 - local_uv.y);
	float top_sway = sin(TIME * wind_speed * 0.82 + local_uv.y * 3.0 + local_uv.x * 1.7);
	float offset_px = (wave_a * 0.52 + wave_b * 0.28 + top_sway * top_factor * 1.08) * wind_strength_px * wind;
	vec2 sample_uv = clamp(local_uv - vec2(offset_px, 0.0) * local_texel_size, vec2(0.0), vec2(1.0));
	vec4 albedo = texture(TEXTURE, frame_uv(sample_uv, frame_index));
	vec4 season = texture(season_mask_texture, frame_uv(sample_uv, frame_index));
	float winter = clamp(season_amount, 0.0, 1.0);
	float snow_cover = clamp(season.r, 0.0, 1.0);
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_leaf = vec3(luma * 0.48 + 0.13, luma * 0.49 + 0.14, luma * 0.53 + 0.17);
	vec3 buried_leaf = vec3(luma * 0.34 + 0.24, luma * 0.35 + 0.24, luma * 0.37 + 0.25);
	float full_winter = smoothstep(0.54, 1.0, winter);
	vec3 winter_leaf = mix(cold_leaf, buried_leaf, full_winter);
	float pale = clamp(winter * 0.90 + season.b * winter * 0.38 + snow_cover * winter * 0.62 + full_winter * 0.74, 0.0, 1.0);
	albedo.rgb = mix(albedo.rgb, winter_leaf, pale);
	float drop_order = clamp(season.g, 0.0, 1.0);
	float drop = smoothstep(drop_order * 0.90, drop_order * 0.90 + 0.12, winter);
	float late_winter = smoothstep(0.52, 1.0, winter);
	albedo.a *= 1.0 - drop * late_winter * leaf_drop_strength;
	albedo.a *= 1.0 - smoothstep(0.16, 0.82, snow_cover) * smoothstep(0.42, 1.0, winter) * 0.38;
	albedo.a *= clamp(instance_data.a, 0.0, 1.0);
	COLOR = albedo;
}
