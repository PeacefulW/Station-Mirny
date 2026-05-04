shader_type canvas_item;

uniform sampler2D water_albedo : repeat_enable, filter_linear;
uniform float water_world_scale_px = 1024.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec3 albedo = texture(water_albedo, world_pos / water_world_scale_px).rgb;
	COLOR = vec4(albedo, mask.a);
}
