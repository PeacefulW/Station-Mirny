shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D render_aux_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D render_descriptor_lut : filter_nearest, repeat_disable;
uniform sampler2D render_variant_crop_lut : filter_nearest, repeat_disable;
uniform float render_descriptor_capacity = 64.0;
uniform float render_descriptor_lut_rows = 5.0;
uniform float render_variant_capacity = 256.0;

varying vec4 instance_data;
varying vec4 pack_rect;
varying vec4 layout_flags;
varying vec4 crop;
varying float frame_index;

vec4 descriptor_row(float id, float row) {
	return textureLod(render_descriptor_lut, vec2(
		(id + 0.5) / render_descriptor_capacity,
		(row + 0.5) / render_descriptor_lut_rows
	), 0.0);
}

void vertex() {
	instance_data = COLOR;
	float id = INSTANCE_CUSTOM.x;
	frame_index = INSTANCE_CUSTOM.y;
	pack_rect = descriptor_row(id, 0.0);
	layout_flags = descriptor_row(id, 2.0);
	crop = textureLod(render_variant_crop_lut, vec2(
		(frame_index + 0.5) / render_variant_capacity,
		(id + 0.5) / render_descriptor_capacity
	), 0.0);
}

void fragment() {
	vec2 local_uv = crop.xy + vec2(UV.x, 1.0 - UV.y) * crop.zw;
	float index = clamp(floor(frame_index + 0.5), 0.0, layout_flags.z - 1.0);
	vec2 cell = vec2(mod(index, layout_flags.x), floor(index / layout_flags.x));
	vec2 family_uv = (cell + local_uv) / layout_flags.xy;
	vec4 color = texture(render_aux_atlas, pack_rect.xy + family_uv * pack_rect.zw);
	color.rgb *= instance_data.rgb;
	color.a *= instance_data.a;
	if (color.a <= 0.001) {
		discard;
	}
	COLOR = color;
}
