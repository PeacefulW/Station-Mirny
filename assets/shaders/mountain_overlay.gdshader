shader_type canvas_item;

uniform sampler2D fog_mask : filter_nearest;
uniform vec4 fog_color : source_color = vec4(0.02, 0.02, 0.03, 0.96);

void fragment() {
	float fog = texture(fog_mask, UV).r;
	COLOR = fog > 0.5 ? fog_color : vec4(0.0, 0.0, 0.0, 0.0);
}
