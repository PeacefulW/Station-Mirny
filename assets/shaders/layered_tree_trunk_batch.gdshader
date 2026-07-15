shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D snow_mask_texture : filter_linear, repeat_disable;
uniform sampler2D wind_mask_texture : filter_linear, repeat_disable;
uniform float atlas_columns = 5.0;
uniform float atlas_rows = 1.0;
uniform float atlas_frame_count = 5.0;
uniform vec2 frame_texel_size = vec2(0.0013020833);
uniform float wind_strength_px = 3.0;
uniform float wind_speed = 1.18;
uniform float season_amount = 0.0;

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
	vec4 wind_mask = texture(wind_mask_texture, frame_uv(local_uv, frame_index));
	float wind = clamp(wind_mask.r * wind_mask.a, 0.0, 1.0);
	float trunk_wave = sin(TIME * wind_speed * 0.72 + local_uv.y * 4.3 + local_uv.x * 1.6);
	float branch_wave = sin(TIME * wind_speed * 1.25 + local_uv.y * 11.0 - local_uv.x * 2.2);
	float top_factor = smoothstep(0.18, 1.0, 1.0 - local_uv.y);
	float offset_px = (trunk_wave * 0.62 + branch_wave * 0.24) * wind_strength_px * 0.38 * wind * top_factor;
	vec2 sample_uv = clamp(local_uv - vec2(offset_px, 0.0) * local_texel_size, vec2(0.0), vec2(1.0));
	vec4 albedo = texture(TEXTURE, frame_uv(sample_uv, frame_index));
	float winter = clamp(season_amount, 0.0, 1.0);
	float frost = clamp(texture(snow_mask_texture, frame_uv(sample_uv, frame_index)).r, 0.0, 1.0);
	float luma = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 cold_bark = vec3(luma * 0.60 + 0.11, luma * 0.62 + 0.12, luma * 0.67 + 0.16);
	float bark_cool = smoothstep(0.10, 1.0, winter) * 0.56;
	albedo.rgb = mix(albedo.rgb, cold_bark, bark_cool);
	float frost_amount = smoothstep(0.12, 0.72, frost) * smoothstep(0.18, 1.0, winter) * 0.42;
	albedo.rgb = mix(albedo.rgb, vec3(0.78, 0.77, 0.72), frost_amount);
	albedo.a *= clamp(instance_data.a, 0.0, 1.0);
	COLOR = albedo;
}
