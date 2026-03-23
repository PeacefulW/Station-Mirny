shader_type canvas_item;

uniform sampler2D hide_mask : filter_nearest;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float hide = texture(hide_mask, UV).r;
	COLOR = hide > 0.5 ? vec4(0.0, 0.0, 0.0, 0.0) : base;
}
