shader_type canvas_item;
render_mode blend_mix;

#include "res://assets/shaders/includes/world_height_shadow_receiver.gdshaderinc"

uniform float atlas_columns = 1.0;
uniform float atlas_rows = 1.0;
uniform float atlas_frame_count = 1.0;
uniform vec2 frame_texel_size = vec2(0.0013020833);

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
	vec4 albedo = texture(TEXTURE, frame_uv(sprite_uv(UV), frame_index));
	float tint = clamp(instance_data.g, 0.0, 1.0);
	albedo.rgb *= tint;
	albedo.rgb = apply_world_height_shadow(albedo.rgb, SCREEN_UV);
	albedo.a *= clamp(instance_data.a, 0.0, 1.0);
	COLOR = albedo;
}
