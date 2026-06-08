shader_type canvas_item;
render_mode blend_mix;

uniform float atlas_columns = 8.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_count = 32.0;
uniform float animation_frames_per_group = 1.0;
uniform float animation_fps = 0.0;
uniform float wind_time = 0.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_strength_px = 0.0;

varying vec4 instance_data;

void vertex() {
	instance_data = COLOR;
	float wind_phase = instance_data.b * 6.28318530718;
	float sway = sin(wind_time + wind_phase) * wind_strength_px;
	VERTEX += normalize(wind_direction) * sway * UV.y;
}

void fragment() {
	float base_frame_index = floor(clamp(instance_data.r * 255.0 + 0.5, 0.0, atlas_frame_count - 1.0));
	float frame_index = base_frame_index;
	if (animation_frames_per_group > 1.0 && animation_fps > 0.0) {
		float phase_frame = floor(instance_data.b * animation_frames_per_group);
		float animation_frame = mod(floor(TIME * animation_fps) + phase_frame, animation_frames_per_group);
		frame_index = clamp(base_frame_index + animation_frame, 0.0, atlas_frame_count - 1.0);
	}
	float frame_x = mod(frame_index, atlas_columns);
	float frame_y = floor(frame_index / atlas_columns);
	vec2 atlas_cell_size = vec2(1.0 / atlas_columns, 1.0 / atlas_rows);
	// QuadMesh UV.y is inverted relative to PNG top-left orientation.
	vec2 atlas_sample_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 atlas_uv = (vec2(frame_x, frame_y) + atlas_sample_uv) * atlas_cell_size;
	vec4 atlas_color = texture(TEXTURE, atlas_uv);
	float tint = clamp(instance_data.g, 0.0, 1.0);
	COLOR = atlas_color * vec4(tint, tint, tint, instance_data.a);
}
