#include "mountain_contour.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace mountain_contour {
namespace {

struct ContourPoint {
	float x = 0.0f;
	float y = 0.0f;
};

struct ContourSegment {
	godot::Vector2 a;
	godot::Vector2 b;
	godot::Vector2 outward;
};

struct RuntimeStyle {
	float south_height_px = 32.0f;
	float north_height_px = 0.0f;
	float side_height_px = 16.0f;
	float corner_round_px = 16.0f;
	float diagonal_smooth_px = 32.0f;
	float contour_relax = 1.0f;
	float contour_warp_px = 0.0f;
	float roughness = 0.0f;
	float corner_variation = 0.0f;
	float rim_width_px = 8.0f;
	float outline_width_px = 3.0f;
	uint32_t geometry_seed = 90213U;
	bool outline_enabled = true;
};

struct SdfField {
	int32_t side = 0;
	std::vector<uint8_t> inside;
	std::vector<float> values;
	bool has_inside = false;
};

struct SdfSampleGrid {
	int32_t columns = 0;
	int32_t rows = 0;
	float step_px = 4.0f;
	float max_x = 0.0f;
	float max_y = 0.0f;
	std::vector<float> values;
};

enum SeamTouchMask : int32_t {
	SEAM_WEST = 1,
	SEAM_EAST = 2,
	SEAM_NORTH = 4,
	SEAM_SOUTH = 8,
};

enum MaterialZone : int32_t {
	ZONE_TOP = 0,
	ZONE_FACE = 1,
	ZONE_RIM = 2,
	ZONE_OUTLINE = 3,
};

constexpr int32_t ATTRIBUTE_STRIDE = 8;
constexpr float SDF_VISUAL_STEP_PX = 4.0f;
constexpr float EDGE_NOISE_PERIOD_TILES = 8.0f;

enum FacadeSide : int32_t {
	FACADE_SOUTH = 0,
	FACADE_SIDE = 1,
	FACADE_DIAGONAL = 2,
};

struct ContourVertexAttributes {
	float edge_u = 0.0f;
	float edge_v = 0.0f;
	float signed_distance = 0.0f;
	float face_depth_px = 0.0f;
	float facade_side = 0.0f;
	float zone = 0.0f;
};

struct SdfPolyPoint {
	godot::Vector2 point;
	float signed_distance_px = 0.0f;
};

struct ProjectionPoint {
	godot::Vector2 point;
	float value = -1.0f;
	float depth_px = 0.0f;
};

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float smoothstep_float(float p_t) {
	return p_t * p_t * (3.0f - 2.0f * p_t);
}

float line_mask(float p_distance, float p_width) {
	return std::max(0.0f, std::min(1.0f - p_distance / std::max(0.001f, p_width), 1.0f));
}

int32_t positive_mod_i32(int32_t p_value, int32_t p_period) {
	if (p_period <= 0) {
		return 0;
	}
	const int32_t result = p_value % p_period;
	return result < 0 ? result + p_period : result;
}

float hash2d(int32_t p_x, int32_t p_y, uint32_t p_seed) {
	uint32_t n = static_cast<uint32_t>(p_x) * 374761393U
			+ static_cast<uint32_t>(p_y) * 668265263U
			+ p_seed * 1442695041U;
	n ^= n >> 13U;
	n *= 1274126177U;
	return static_cast<float>(n ^ (n >> 16U)) / 4294967295.0f;
}

float value_noise(float p_x, float p_y, uint32_t p_seed) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_y));
	const float tx = p_x - static_cast<float>(x0);
	const float ty = p_y - static_cast<float>(y0);
	const float sx = smoothstep_float(tx);
	const float sy = smoothstep_float(ty);
	const float v00 = hash2d(x0, y0, p_seed);
	const float v10 = hash2d(x0 + 1, y0, p_seed);
	const float v01 = hash2d(x0, y0 + 1, p_seed);
	const float v11 = hash2d(x0 + 1, y0 + 1, p_seed);
	return lerp_float(lerp_float(v00, v10, sx), lerp_float(v01, v11, sx), sy);
}

float value_noise_tiled(float p_x, float p_y, float p_period_x, float p_period_y, uint32_t p_seed) {
	if (p_period_x <= 0.000001f || p_period_y <= 0.000001f) {
		return value_noise(p_x, p_y, p_seed);
	}
	const int32_t period_x = static_cast<int32_t>(std::max(1.0f, std::round(p_period_x)));
	const int32_t period_y = static_cast<int32_t>(std::max(1.0f, std::round(p_period_y)));
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_y));
	const float tx = p_x - static_cast<float>(x0);
	const float ty = p_y - static_cast<float>(y0);
	const float sx = smoothstep_float(tx);
	const float sy = smoothstep_float(ty);
	const int32_t x1 = x0 + 1;
	const int32_t y1 = y0 + 1;
	const float v00 = hash2d(positive_mod_i32(x0, period_x), positive_mod_i32(y0, period_y), p_seed);
	const float v10 = hash2d(positive_mod_i32(x1, period_x), positive_mod_i32(y0, period_y), p_seed);
	const float v01 = hash2d(positive_mod_i32(x0, period_x), positive_mod_i32(y1, period_y), p_seed);
	const float v11 = hash2d(positive_mod_i32(x1, period_x), positive_mod_i32(y1, period_y), p_seed);
	return lerp_float(lerp_float(v00, v10, sx), lerp_float(v01, v11, sx), sy);
}

float fbm_tiled(float p_x, float p_y, float p_period_x, float p_period_y, int32_t p_octaves, uint32_t p_seed) {
	float amplitude = 1.0f;
	float frequency = 1.0f;
	float total = 0.0f;
	float weight = 0.0f;
	for (int32_t octave = 0; octave < p_octaves; ++octave) {
		total += value_noise_tiled(
			p_x * frequency,
			p_y * frequency,
			p_period_x * frequency,
			p_period_y * frequency,
			p_seed + static_cast<uint32_t>(octave) * 97U
		) * amplitude;
		weight += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.0f;
	}
	return weight <= 0.000001f ? 0.0f : total / weight;
}

ContourPoint midpoint(ContourPoint p_a, ContourPoint p_b) {
	return {
		(p_a.x + p_b.x) * 0.5f,
		(p_a.y + p_b.y) * 0.5f,
	};
}

godot::Vector2 midpoint_vec(godot::Vector2 p_a, godot::Vector2 p_b) {
	return (p_a + p_b) * 0.5f;
}

float clamp_coord(float p_value, float p_max) {
	return std::max(0.0f, std::min(p_value, p_max));
}

godot::Vector2 clamp_vec(godot::Vector2 p_value, float p_max) {
	return godot::Vector2(
		clamp_coord(p_value.x, p_max),
		clamp_coord(p_value.y, p_max)
	);
}

godot::Vector2 normalized_or(godot::Vector2 p_value, godot::Vector2 p_fallback) {
	const float length_sq = p_value.length_squared();
	if (length_sq <= 0.000001f) {
		return p_fallback;
	}
	return p_value / std::sqrt(length_sq);
}

bool read_solid(const godot::PackedByteArray &p_solid_halo, int32_t p_side, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_side || p_y >= p_side) {
		return false;
	}
	const int32_t index = p_y * p_side + p_x;
	return index >= 0 && index < p_solid_halo.size() && p_solid_halo[index] != 0;
}

bool read_local_solid(const std::vector<uint8_t> &p_solid_local, int32_t p_chunk_size, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_chunk_size || p_y >= p_chunk_size) {
		return false;
	}
	const int32_t index = p_y * p_chunk_size + p_x;
	return index >= 0 && index < static_cast<int32_t>(p_solid_local.size()) && p_solid_local[static_cast<size_t>(index)] != 0U;
}

ContourPoint sample_point(int32_t p_x, int32_t p_y, int32_t p_tile_size_px) {
	const float tile_size = static_cast<float>(p_tile_size_px);
	return {
		(static_cast<float>(p_x) - 0.5f) * tile_size,
		(static_cast<float>(p_y) - 0.5f) * tile_size,
	};
}

godot::Vector2 sample_vec(int32_t p_x, int32_t p_y, int32_t p_tile_size_px) {
	const float tile_size = static_cast<float>(p_tile_size_px);
	return godot::Vector2(
		(static_cast<float>(p_x) - 0.5f) * tile_size,
		(static_cast<float>(p_y) - 0.5f) * tile_size
	);
}

void append_vertex_attributes(
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_vertex,
	const ContourVertexAttributes &p_attributes,
	float p_tile_size_px
);

void append_polygon(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	std::initializer_list<ContourPoint> p_points,
	float p_chunk_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const int32_t base_index = r_vertices.size();
	for (const ContourPoint &point : p_points) {
		r_vertices.append(godot::Vector2(
			clamp_coord(point.x, p_chunk_px),
			clamp_coord(point.y, p_chunk_px)
		));
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

void append_polygon_runtime(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	std::initializer_list<godot::Vector2> p_points,
	float p_chunk_px,
	float p_edge_v,
	float p_signed_distance,
	float p_facade_side,
	float p_zone,
	float p_tile_size_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const int32_t base_index = r_vertices.size();
	for (const godot::Vector2 &point : p_points) {
		const godot::Vector2 clamped = clamp_vec(point, p_chunk_px);
		r_vertices.append(clamped);
		append_vertex_attributes(
			r_attributes,
			clamped,
			{
				clamped.x / std::max(1.0f, p_tile_size_px),
				p_edge_v,
				p_signed_distance,
				0.0f,
				p_facade_side,
				p_zone,
			},
			p_tile_size_px
		);
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

void append_case_mesh(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	int32_t p_case_code,
	ContourPoint p_tl,
	ContourPoint p_tr,
	ContourPoint p_br,
	ContourPoint p_bl,
	float p_chunk_px
) {
	const ContourPoint top = midpoint(p_tl, p_tr);
	const ContourPoint right = midpoint(p_tr, p_br);
	const ContourPoint bottom = midpoint(p_bl, p_br);
	const ContourPoint left = midpoint(p_tl, p_bl);

	switch (p_case_code) {
		case 0:
			return;
		case 1:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			return;
		case 2:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			return;
		case 3:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, left }, p_chunk_px);
			return;
		case 4:
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 5:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 6:
			append_polygon(r_vertices, r_indices, { p_tr, p_br, bottom, top }, p_chunk_px);
			return;
		case 7:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, bottom, left }, p_chunk_px);
			return;
		case 8:
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 9:
			append_polygon(r_vertices, r_indices, { p_tl, top, bottom, p_bl }, p_chunk_px);
			return;
		case 10:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 11:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, bottom, p_bl }, p_chunk_px);
			return;
		case 12:
			append_polygon(r_vertices, r_indices, { left, right, p_br, p_bl }, p_chunk_px);
			return;
		case 13:
			append_polygon(r_vertices, r_indices, { p_tl, top, right, p_br, p_bl }, p_chunk_px);
			return;
		case 14:
			append_polygon(r_vertices, r_indices, { top, p_tr, p_br, p_bl, left }, p_chunk_px);
			return;
		case 15:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, p_bl }, p_chunk_px);
			return;
		default:
			return;
	}
}

void append_case_top_mesh(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_case_code,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_chunk_px,
	const RuntimeStyle &p_style,
	float p_tile_size_px
) {
	const godot::Vector2 top = midpoint_vec(p_tl, p_tr);
	const godot::Vector2 right = midpoint_vec(p_tr, p_br);
	const godot::Vector2 bottom = midpoint_vec(p_bl, p_br);
	const godot::Vector2 left = midpoint_vec(p_tl, p_bl);
	const float edge_distance = std::max(
		1.0f,
		p_style.corner_round_px + p_style.diagonal_smooth_px * 0.25f + p_style.contour_warp_px * 4.0f
	);

	switch (p_case_code) {
		case 0:
			return;
		case 1:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 2:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 3:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, left }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 4:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 5:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 6:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, p_br, bottom, top }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 7:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, bottom, left }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 8:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 9:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, bottom, p_bl }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 10:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 11:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, bottom, p_bl }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 12:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { left, right, p_br, p_bl }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 13:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, right, p_br, p_bl }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 14:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { top, p_tr, p_br, p_bl, left }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 15:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, p_bl }, p_chunk_px, 1.0f, edge_distance, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		default:
			return;
	}
}

float read_style_float(const godot::Dictionary &p_style_params, const char *p_key, float p_default_value) {
	const godot::Variant value = p_style_params.get(p_key, p_default_value);
	if (value.get_type() == godot::Variant::NIL) {
		return p_default_value;
	}
	return static_cast<float>(static_cast<double>(value));
}

bool read_style_bool(const godot::Dictionary &p_style_params, const char *p_key, bool p_default_value) {
	const godot::Variant value = p_style_params.get(p_key, p_default_value);
	if (value.get_type() == godot::Variant::NIL) {
		return p_default_value;
	}
	return static_cast<bool>(value);
}

RuntimeStyle read_runtime_style(const godot::Dictionary &p_style_params) {
	RuntimeStyle style;
	style.south_height_px = std::max(0.0f, std::min(read_style_float(p_style_params, "south_height_px", style.south_height_px), 512.0f));
	style.north_height_px = std::max(0.0f, std::min(read_style_float(p_style_params, "north_height_px", style.north_height_px), 512.0f));
	style.side_height_px = std::max(0.0f, std::min(read_style_float(p_style_params, "side_height_px", style.side_height_px), 512.0f));
	style.corner_round_px = std::max(0.0f, std::min(read_style_float(p_style_params, "corner_round_px", style.corner_round_px), 256.0f));
	style.diagonal_smooth_px = std::max(0.0f, std::min(read_style_float(p_style_params, "diagonal_smooth_px", style.diagonal_smooth_px), 256.0f));
	style.contour_warp_px = std::max(0.0f, std::min(read_style_float(p_style_params, "contour_warp_px", style.contour_warp_px), 256.0f));
	style.roughness = std::max(0.0f, std::min(read_style_float(p_style_params, "roughness", style.roughness), 100.0f));
	style.corner_variation = std::max(0.0f, std::min(read_style_float(p_style_params, "corner_variation", style.corner_variation), 1.0f));
	style.rim_width_px = std::max(0.0f, std::min(read_style_float(p_style_params, "rim_width_px", style.rim_width_px), 256.0f));
	style.outline_width_px = std::max(0.0f, std::min(read_style_float(p_style_params, "mountain_outline_width_px", style.outline_width_px), 256.0f));
	style.outline_enabled = read_style_bool(p_style_params, "mountain_outline_enabled", style.outline_enabled);
	return style;
}

void append_vertex_attributes(
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_vertex,
	const ContourVertexAttributes &p_attributes,
	float p_tile_size_px
) {
	r_attributes.append(p_attributes.edge_u);
	r_attributes.append(p_attributes.edge_v);
	r_attributes.append(p_attributes.signed_distance);
	r_attributes.append(p_attributes.face_depth_px);
	r_attributes.append(p_attributes.facade_side);
	r_attributes.append(p_attributes.zone);
	r_attributes.append(p_vertex.x / p_tile_size_px);
	r_attributes.append(p_vertex.y / p_tile_size_px);
}

void append_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_a,
	godot::Vector2 p_b,
	godot::Vector2 p_c,
	godot::Vector2 p_d,
	const ContourVertexAttributes &p_attr_a,
	const ContourVertexAttributes &p_attr_b,
	const ContourVertexAttributes &p_attr_c,
	const ContourVertexAttributes &p_attr_d,
	float p_tile_size_px
) {
	const int32_t base_index = r_vertices.size();
	r_vertices.append(p_a);
	r_vertices.append(p_b);
	r_vertices.append(p_c);
	r_vertices.append(p_d);
	append_vertex_attributes(r_attributes, p_a, p_attr_a, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_b, p_attr_b, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_c, p_attr_c, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_d, p_attr_d, p_tile_size_px);
	r_indices.append(base_index);
	r_indices.append(base_index + 1);
	r_indices.append(base_index + 2);
	r_indices.append(base_index);
	r_indices.append(base_index + 2);
	r_indices.append(base_index + 3);
}

int32_t sdf_index(const SdfField &p_field, int32_t p_x, int32_t p_y) {
	return p_y * p_field.side + p_x;
}

SdfField build_sdf_field(const godot::PackedByteArray &p_solid_halo, int32_t p_side) {
	SdfField field;
	field.side = p_side;
	if (p_side <= 0 || p_solid_halo.size() != p_side * p_side) {
		return field;
	}
	const size_t sample_count = static_cast<size_t>(p_side * p_side);
	field.inside.resize(sample_count, 0U);
	field.values.resize(sample_count, 0.0f);
	for (int32_t y = 0; y < p_side; ++y) {
		for (int32_t x = 0; x < p_side; ++x) {
			const int32_t index = y * p_side + x;
			const bool inside = p_solid_halo[index] != 0;
			field.inside[static_cast<size_t>(index)] = inside ? 1U : 0U;
			field.has_inside = field.has_inside || inside;
		}
	}
	if (!field.has_inside) {
		const float fallback = -static_cast<float>(std::max(1, p_side));
		std::fill(field.values.begin(), field.values.end(), fallback);
		return field;
	}

	constexpr float no_feature_distance_sq = 1.0e20f;
	for (int32_t y = 0; y < p_side; ++y) {
		for (int32_t x = 0; x < p_side; ++x) {
			const int32_t index = y * p_side + x;
			const bool inside = field.inside[static_cast<size_t>(index)] != 0U;
			float best_sq = no_feature_distance_sq;
			if (inside) {
				for (int32_t feature_y = -1; feature_y <= p_side; ++feature_y) {
					for (int32_t feature_x = -1; feature_x <= p_side; ++feature_x) {
						const bool feature_inside = feature_x >= 0 && feature_y >= 0 && feature_x < p_side && feature_y < p_side
								&& field.inside[static_cast<size_t>(feature_y * p_side + feature_x)] != 0U;
						if (feature_inside) {
							continue;
						}
						const float dx = static_cast<float>(x - feature_x);
						const float dy = static_cast<float>(y - feature_y);
						best_sq = std::min(best_sq, dx * dx + dy * dy);
					}
				}
			} else {
				for (int32_t feature_y = 0; feature_y < p_side; ++feature_y) {
					for (int32_t feature_x = 0; feature_x < p_side; ++feature_x) {
						if (field.inside[static_cast<size_t>(feature_y * p_side + feature_x)] == 0U) {
							continue;
						}
						const float dx = static_cast<float>(x - feature_x);
						const float dy = static_cast<float>(y - feature_y);
						best_sq = std::min(best_sq, dx * dx + dy * dy);
					}
				}
			}
			const float distance = std::max(0.0f, std::sqrt(best_sq) - 0.5f);
			field.values[static_cast<size_t>(index)] = inside ? distance : -distance;
		}
	}
	return field;
}

float sdf_value_at(const SdfField &p_field, int32_t p_x, int32_t p_y) {
	if (p_field.side <= 0 || p_field.values.empty()) {
		return 0.0f;
	}
	if (p_x >= 0 && p_y >= 0 && p_x < p_field.side && p_y < p_field.side) {
		return p_field.values[static_cast<size_t>(sdf_index(p_field, p_x, p_y))];
	}
	if (!p_field.has_inside) {
		return -static_cast<float>(std::max(1, p_field.side));
	}
	constexpr float no_feature_distance_sq = 1.0e20f;
	float best_sq = no_feature_distance_sq;
	for (int32_t feature_y = 0; feature_y < p_field.side; ++feature_y) {
		for (int32_t feature_x = 0; feature_x < p_field.side; ++feature_x) {
			if (p_field.inside[static_cast<size_t>(sdf_index(p_field, feature_x, feature_y))] == 0U) {
				continue;
			}
			const float dx = static_cast<float>(p_x - feature_x);
			const float dy = static_cast<float>(p_y - feature_y);
			best_sq = std::min(best_sq, dx * dx + dy * dy);
		}
	}
	if (best_sq >= no_feature_distance_sq * 0.5f) {
		return -static_cast<float>(std::max(1, p_field.side));
	}
	return -std::max(0.0f, std::sqrt(best_sq) - 0.5f);
}

float sample_sdf_cells(const SdfField &p_field, float p_cell_x, float p_cell_y) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_cell_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_cell_y));
	const float tx = p_cell_x - static_cast<float>(x0);
	const float ty = p_cell_y - static_cast<float>(y0);
	const float nw = sdf_value_at(p_field, x0, y0);
	const float ne = sdf_value_at(p_field, x0 + 1, y0);
	const float sw = sdf_value_at(p_field, x0, y0 + 1);
	const float se = sdf_value_at(p_field, x0 + 1, y0 + 1);
	return lerp_float(lerp_float(nw, ne, tx), lerp_float(sw, se, tx), ty);
}

uint8_t sdf_corner_mask(const SdfField &p_field, float p_cell_x, float p_cell_y) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_cell_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_cell_y));
	uint8_t mask = 0U;
	mask |= sample_sdf_cells(p_field, static_cast<float>(x0), static_cast<float>(y0)) > 0.0f ? 1U : 0U;
	mask |= sample_sdf_cells(p_field, static_cast<float>(x0 + 1), static_cast<float>(y0)) > 0.0f ? 2U : 0U;
	mask |= sample_sdf_cells(p_field, static_cast<float>(x0 + 1), static_cast<float>(y0 + 1)) > 0.0f ? 4U : 0U;
	mask |= sample_sdf_cells(p_field, static_cast<float>(x0), static_cast<float>(y0 + 1)) > 0.0f ? 8U : 0U;
	return mask;
}

float weighted_sdf_average(
	const SdfField &p_field,
	float p_cell_x,
	float p_cell_y,
	std::initializer_list<std::initializer_list<float>> p_samples
) {
	float sum = 0.0f;
	float weight_sum = 0.0f;
	for (const std::initializer_list<float> &sample : p_samples) {
		if (sample.size() != 3) {
			continue;
		}
		auto iter = sample.begin();
		const float offset_x = *iter++;
		const float offset_y = *iter++;
		const float weight = *iter;
		sum += sample_sdf_cells(p_field, p_cell_x + offset_x, p_cell_y + offset_y) * weight;
		weight_sum += weight;
	}
	return sum / std::max(0.001f, weight_sum);
}

float average_sdf_neighborhood(const SdfField &p_field, float p_cell_x, float p_cell_y, float p_radius) {
	return weighted_sdf_average(
		p_field,
		p_cell_x,
		p_cell_y,
		{
			{ 0.0f, 0.0f, 4.0f },
			{ -p_radius, 0.0f, 2.0f },
			{ p_radius, 0.0f, 2.0f },
			{ 0.0f, -p_radius, 2.0f },
			{ 0.0f, p_radius, 2.0f },
			{ -p_radius, -p_radius, 1.0f },
			{ p_radius, -p_radius, 1.0f },
			{ -p_radius, p_radius, 1.0f },
			{ p_radius, p_radius, 1.0f },
		}
	);
}

float average_sdf_diagonals(const SdfField &p_field, float p_cell_x, float p_cell_y, float p_radius) {
	return weighted_sdf_average(
		p_field,
		p_cell_x,
		p_cell_y,
		{
			{ 0.0f, 0.0f, 2.0f },
			{ -p_radius, -p_radius, 1.0f },
			{ p_radius, -p_radius, 1.0f },
			{ -p_radius, p_radius, 1.0f },
			{ p_radius, p_radius, 1.0f },
		}
	);
}

float sample_controlled_sdf_px(
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_world_x,
	float p_world_y,
	float p_tile_size_px
) {
	const float cell_x = p_world_x / std::max(1.0f, p_tile_size_px) + 1.0f;
	const float cell_y = p_world_y / std::max(1.0f, p_tile_size_px) + 1.0f;
	float value = sample_sdf_cells(p_field, cell_x, cell_y);
	const float max_radius = std::max(1.0f, p_tile_size_px * 0.5f);
	const float active_radius_cells = std::min(
		0.75f,
		std::max(p_style.corner_round_px, p_style.diagonal_smooth_px) / std::max(1.0f, p_tile_size_px)
	);
	if (std::abs(value) > active_radius_cells + 0.75f) {
		return value * p_tile_size_px;
	}
	const float relax = 1.1f;
	const uint8_t corner_mask = sdf_corner_mask(p_field, cell_x, cell_y);
	const int32_t corner_count =
			((corner_mask & 1U) != 0U ? 1 : 0)
			+ ((corner_mask & 2U) != 0U ? 1 : 0)
			+ ((corner_mask & 4U) != 0U ? 1 : 0)
			+ ((corner_mask & 8U) != 0U ? 1 : 0);

	if (p_style.corner_round_px > 0.0f && (corner_count == 1 || corner_count == 3)) {
		const float strength = std::max(0.0f, std::min(p_style.corner_round_px / max_radius, 1.0f));
		const float radius = std::max(0.001f, std::min(p_style.corner_round_px / p_tile_size_px, 0.75f));
		const float smoothed = average_sdf_neighborhood(p_field, cell_x, cell_y, radius);
		value = lerp_float(value, smoothed, std::min(strength * 0.78f * relax, 0.9f));
	}
	if (p_style.corner_round_px > 0.0f) {
		const float strength = std::max(0.0f, std::min(p_style.corner_round_px / max_radius, 1.0f));
		const float radius = std::max(0.001f, std::min(p_style.corner_round_px / p_tile_size_px, 0.75f));
		const float smoothed = average_sdf_neighborhood(p_field, cell_x, cell_y, radius);
		value = lerp_float(value, smoothed, std::min(strength * 0.72f * relax, 0.88f));
	}
	if (p_style.diagonal_smooth_px > 0.0f) {
		const float strength = std::max(0.0f, std::min(p_style.diagonal_smooth_px / max_radius, 1.0f));
		const float radius = std::max(0.001f, std::min(p_style.diagonal_smooth_px / p_tile_size_px, 0.75f));
		const float smoothed = average_sdf_diagonals(p_field, cell_x, cell_y, radius);
		const float softened = lerp_float(value, smoothed, std::min(strength * 0.64f * relax, 0.82f));
		value = std::max(value, softened);
	}
	return value * p_tile_size_px;
}

SdfSampleGrid build_sdf_sample_grid(
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_max_x,
	float p_max_y,
	float p_tile_size_px
) {
	SdfSampleGrid grid;
	grid.step_px = SDF_VISUAL_STEP_PX;
	grid.max_x = std::max(0.0f, p_max_x);
	grid.max_y = std::max(0.0f, p_max_y);
	grid.columns = static_cast<int32_t>(std::ceil(grid.max_x / grid.step_px)) + 1;
	grid.rows = static_cast<int32_t>(std::ceil(grid.max_y / grid.step_px)) + 1;
	if (grid.columns <= 0 || grid.rows <= 0) {
		return grid;
	}
	grid.values.resize(static_cast<size_t>(grid.columns * grid.rows), 0.0f);
	for (int32_t y = 0; y < grid.rows; ++y) {
		const float world_y = std::min(static_cast<float>(y) * grid.step_px, grid.max_y);
		for (int32_t x = 0; x < grid.columns; ++x) {
			const float world_x = std::min(static_cast<float>(x) * grid.step_px, grid.max_x);
			grid.values[static_cast<size_t>(y * grid.columns + x)] = sample_controlled_sdf_px(
				p_field,
				p_style,
				world_x,
				world_y,
				p_tile_size_px
			);
		}
	}
	return grid;
}

float sdf_grid_world_x(const SdfSampleGrid &p_grid, int32_t p_x) {
	return std::min(static_cast<float>(std::max(0, p_x)) * p_grid.step_px, p_grid.max_x);
}

float sdf_grid_world_y(const SdfSampleGrid &p_grid, int32_t p_y) {
	return std::min(static_cast<float>(std::max(0, p_y)) * p_grid.step_px, p_grid.max_y);
}

float sdf_grid_node_value(const SdfSampleGrid &p_grid, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_grid.columns || p_y >= p_grid.rows || p_grid.values.empty()) {
		return 0.0f;
	}
	return p_grid.values[static_cast<size_t>(p_y * p_grid.columns + p_x)];
}

float sample_sdf_grid_px(
	const SdfSampleGrid &p_grid,
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_world_x,
	float p_world_y,
	float p_tile_size_px
) {
	if (p_world_x < 0.0f || p_world_y < 0.0f || p_world_x > p_grid.max_x || p_world_y > p_grid.max_y || p_grid.columns <= 1 || p_grid.rows <= 1) {
		return sample_controlled_sdf_px(p_field, p_style, p_world_x, p_world_y, p_tile_size_px);
	}
	const float grid_x = p_world_x / p_grid.step_px;
	const float grid_y = p_world_y / p_grid.step_px;
	const int32_t x0 = static_cast<int32_t>(std::floor(grid_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(grid_y));
	const int32_t x1 = std::min(x0 + 1, p_grid.columns - 1);
	const int32_t y1 = std::min(y0 + 1, p_grid.rows - 1);
	const float tx = grid_x - static_cast<float>(x0);
	const float ty = grid_y - static_cast<float>(y0);
	const float nw = sdf_grid_node_value(p_grid, x0, y0);
	const float ne = sdf_grid_node_value(p_grid, x1, y0);
	const float sw = sdf_grid_node_value(p_grid, x0, y1);
	const float se = sdf_grid_node_value(p_grid, x1, y1);
	return lerp_float(lerp_float(nw, ne, tx), lerp_float(sw, se, tx), ty);
}

godot::Vector2 sdf_gradient_px(
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	godot::Vector2 p_point,
	float p_tile_size_px
) {
	const float step = 1.0f;
	const float dx = (
		sample_controlled_sdf_px(p_field, p_style, p_point.x + step, p_point.y, p_tile_size_px)
		- sample_controlled_sdf_px(p_field, p_style, p_point.x - step, p_point.y, p_tile_size_px)
	) / (step * 2.0f);
	const float dy = (
		sample_controlled_sdf_px(p_field, p_style, p_point.x, p_point.y + step, p_tile_size_px)
		- sample_controlled_sdf_px(p_field, p_style, p_point.x, p_point.y - step, p_tile_size_px)
	) / (step * 2.0f);
	return godot::Vector2(dx, dy);
}

ContourVertexAttributes make_sdf_attributes(
	godot::Vector2 p_point,
	float p_signed_distance_px,
	float p_face_depth_px,
	float p_facade_side,
	float p_zone,
	float p_edge_width_px,
	float p_tile_size_px
) {
	const float edge_v = p_zone == static_cast<float>(ZONE_FACE) || p_zone == static_cast<float>(ZONE_OUTLINE)
			? std::max(0.0f, std::min(p_face_depth_px / std::max(1.0f, p_edge_width_px), 1.0f))
			: std::max(0.0f, std::min(p_signed_distance_px / std::max(1.0f, p_edge_width_px), 1.0f));
	return {
		p_point.x / std::max(1.0f, p_tile_size_px),
		edge_v,
		p_signed_distance_px,
		p_face_depth_px,
		p_facade_side,
		p_zone,
	};
}

void append_sdf_polygon(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	std::initializer_list<SdfPolyPoint> p_points,
	float p_edge_width_px,
	float p_zone,
	float p_tile_size_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const int32_t base_index = r_vertices.size();
	for (const SdfPolyPoint &point : p_points) {
		r_vertices.append(point.point);
		append_vertex_attributes(
			r_attributes,
			point.point,
			make_sdf_attributes(
				point.point,
				point.signed_distance_px,
				0.0f,
				static_cast<float>(FACADE_SOUTH),
				p_zone,
				p_edge_width_px,
				p_tile_size_px
			),
			p_tile_size_px
		);
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

SdfPolyPoint interpolate_sdf_crossing(SdfPolyPoint p_a, SdfPolyPoint p_b) {
	const float denom = p_a.signed_distance_px - p_b.signed_distance_px;
	const float t = std::abs(denom) <= 0.0001f ? 0.5f : std::max(0.0f, std::min(p_a.signed_distance_px / denom, 1.0f));
	return {
		p_a.point + (p_b.point - p_a.point) * t,
		0.0f,
	};
}

void append_sdf_top_cell(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const SdfPolyPoint &p_tl,
	const SdfPolyPoint &p_tr,
	const SdfPolyPoint &p_br,
	const SdfPolyPoint &p_bl,
	float p_edge_width_px,
	float p_tile_size_px
) {
	const bool tl_inside = p_tl.signed_distance_px >= 0.0f;
	const bool tr_inside = p_tr.signed_distance_px >= 0.0f;
	const bool br_inside = p_br.signed_distance_px >= 0.0f;
	const bool bl_inside = p_bl.signed_distance_px >= 0.0f;
	const int32_t case_code =
			(tl_inside ? 1 : 0)
			| (tr_inside ? 2 : 0)
			| (br_inside ? 4 : 0)
			| (bl_inside ? 8 : 0);
	if (case_code == 0) {
		return;
	}
	const SdfPolyPoint top = interpolate_sdf_crossing(p_tl, p_tr);
	const SdfPolyPoint right = interpolate_sdf_crossing(p_tr, p_br);
	const SdfPolyPoint bottom = interpolate_sdf_crossing(p_bl, p_br);
	const SdfPolyPoint left = interpolate_sdf_crossing(p_tl, p_bl);
	const float zone = static_cast<float>(ZONE_TOP);
	switch (case_code) {
		case 1:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 2:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 3:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, left }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 4:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 5:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_edge_width_px, zone, p_tile_size_px);
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 6:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tr, p_br, bottom, top }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 7:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, bottom, left }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 8:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 9:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, top, bottom, p_bl }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 10:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_edge_width_px, zone, p_tile_size_px);
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 11:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, bottom, p_bl }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 12:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { left, right, p_br, p_bl }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 13:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, top, right, p_br, p_bl }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 14:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { top, p_tr, p_br, p_bl, left }, p_edge_width_px, zone, p_tile_size_px);
			return;
		case 15:
			append_sdf_polygon(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, p_bl }, p_edge_width_px, zone, p_tile_size_px);
			return;
		default:
			return;
	}
}

void append_sdf_contour_cell(
	std::vector<ContourSegment> &r_segments,
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	const SdfPolyPoint &p_tl,
	const SdfPolyPoint &p_tr,
	const SdfPolyPoint &p_br,
	const SdfPolyPoint &p_bl,
	float p_tile_size_px,
	float p_chunk_px
) {
	const bool tl_inside = p_tl.signed_distance_px >= 0.0f;
	const bool tr_inside = p_tr.signed_distance_px >= 0.0f;
	const bool br_inside = p_br.signed_distance_px >= 0.0f;
	const bool bl_inside = p_bl.signed_distance_px >= 0.0f;
	const int32_t case_code =
			(tl_inside ? 1 : 0)
			| (tr_inside ? 2 : 0)
			| (br_inside ? 4 : 0)
			| (bl_inside ? 8 : 0);
	if (case_code == 0 || case_code == 15) {
		return;
	}
	const SdfPolyPoint top = interpolate_sdf_crossing(p_tl, p_tr);
	const SdfPolyPoint right = interpolate_sdf_crossing(p_tr, p_br);
	const SdfPolyPoint bottom = interpolate_sdf_crossing(p_bl, p_br);
	const SdfPolyPoint left = interpolate_sdf_crossing(p_tl, p_bl);
	auto push_segment = [&](godot::Vector2 p_a, godot::Vector2 p_b) {
		godot::Vector2 a = clamp_vec(p_a, p_chunk_px);
		godot::Vector2 b = clamp_vec(p_b, p_chunk_px);
		if (a.distance_squared_to(b) <= 0.001f) {
			return;
		}
		const godot::Vector2 mid = midpoint_vec(a, b);
		const godot::Vector2 gradient = sdf_gradient_px(p_field, p_style, mid, p_tile_size_px);
		const godot::Vector2 tangent = normalized_or(b - a, godot::Vector2(1.0f, 0.0f));
		const godot::Vector2 fallback = godot::Vector2(tangent.y, -tangent.x);
		const godot::Vector2 outward = normalized_or(-gradient, fallback);
		r_segments.push_back({ a, b, outward });
	};
	switch (case_code) {
		case 1:
		case 14:
			push_segment(top.point, left.point);
			return;
		case 2:
		case 13:
			push_segment(right.point, top.point);
			return;
		case 3:
		case 12:
			push_segment(right.point, left.point);
			return;
		case 4:
		case 11:
			push_segment(bottom.point, right.point);
			return;
		case 5:
			push_segment(top.point, left.point);
			push_segment(bottom.point, right.point);
			return;
		case 6:
		case 9:
			push_segment(bottom.point, top.point);
			return;
		case 7:
		case 8:
			push_segment(bottom.point, left.point);
			return;
		case 10:
			push_segment(right.point, top.point);
			push_segment(left.point, bottom.point);
			return;
		default:
			return;
	}
}

bool projected_south_depth(
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_world_x,
	float p_world_y,
	float p_tile_size_px,
	float &r_depth
) {
	if (p_style.south_height_px <= 0.0f) {
		return false;
	}
	if (sample_controlled_sdf_px(p_field, p_style, p_world_x, p_world_y, p_tile_size_px) >= 0.0f) {
		return false;
	}
	const int32_t steps = static_cast<int32_t>(std::ceil(p_style.south_height_px));
	float outside = 0.0f;
	float inside = -1.0f;
	for (int32_t step = 1; step <= steps; ++step) {
		const float depth = std::min(static_cast<float>(step), p_style.south_height_px);
		if (sample_controlled_sdf_px(p_field, p_style, p_world_x, p_world_y - depth, p_tile_size_px) >= 0.0f) {
			inside = depth;
			break;
		}
		outside = depth;
	}
	if (inside < 0.0f) {
		return false;
	}
	for (int32_t iteration = 0; iteration < 7; ++iteration) {
		const float mid = (outside + inside) * 0.5f;
		if (sample_controlled_sdf_px(p_field, p_style, p_world_x, p_world_y - mid, p_tile_size_px) >= 0.0f) {
			inside = mid;
		} else {
			outside = mid;
		}
	}
	r_depth = inside;
	return true;
}

bool projected_south_depth_grid(
	const SdfSampleGrid &p_grid,
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_world_x,
	float p_world_y,
	float p_tile_size_px,
	float &r_depth
) {
	if (p_style.south_height_px <= 0.0f) {
		return false;
	}
	if (sample_sdf_grid_px(p_grid, p_field, p_style, p_world_x, p_world_y, p_tile_size_px) >= 0.0f) {
		return false;
	}
	const int32_t steps = static_cast<int32_t>(std::ceil(p_style.south_height_px / p_grid.step_px));
	float outside = 0.0f;
	float inside = -1.0f;
	for (int32_t step = 1; step <= steps; ++step) {
		const float depth = std::min(static_cast<float>(step) * p_grid.step_px, p_style.south_height_px);
		if (sample_sdf_grid_px(p_grid, p_field, p_style, p_world_x, p_world_y - depth, p_tile_size_px) >= 0.0f) {
			inside = depth;
			break;
		}
		outside = depth;
	}
	if (inside < 0.0f) {
		return false;
	}
	for (int32_t iteration = 0; iteration < 6; ++iteration) {
		const float mid = (outside + inside) * 0.5f;
		if (sample_sdf_grid_px(p_grid, p_field, p_style, p_world_x, p_world_y - mid, p_tile_size_px) >= 0.0f) {
			inside = mid;
		} else {
			outside = mid;
		}
	}
	r_depth = inside;
	return true;
}

void append_projected_cell_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_a,
	godot::Vector2 p_b,
	godot::Vector2 p_c,
	godot::Vector2 p_d,
	float p_depth_px,
	float p_zone,
	float p_tile_size_px
) {
	const float edge_width = std::max(1.0f, p_depth_px);
	const float facade_side = static_cast<float>(FACADE_SOUTH);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_a,
		p_b,
		p_c,
		p_d,
		make_sdf_attributes(p_a, -p_depth_px, p_depth_px, facade_side, p_zone, edge_width, p_tile_size_px),
		make_sdf_attributes(p_b, -p_depth_px, p_depth_px, facade_side, p_zone, edge_width, p_tile_size_px),
		make_sdf_attributes(p_c, -p_depth_px, p_depth_px, facade_side, p_zone, edge_width, p_tile_size_px),
		make_sdf_attributes(p_d, -p_depth_px, p_depth_px, facade_side, p_zone, edge_width, p_tile_size_px),
		p_tile_size_px
	);
}

ProjectionPoint make_projection_point(
	const SdfSampleGrid &p_grid,
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_world_x,
	float p_world_y,
	float p_tile_size_px
) {
	float depth = 0.0f;
	const float sdf = sample_sdf_grid_px(p_grid, p_field, p_style, p_world_x, p_world_y, p_tile_size_px);
	if (projected_south_depth_grid(p_grid, p_field, p_style, p_world_x, p_world_y, p_tile_size_px, depth)) {
		const float top_margin = std::max(0.001f, depth);
		const float bottom_margin = std::max(0.001f, p_style.south_height_px - depth);
		const float side_margin = std::max(0.001f, -sdf);
		return {
			godot::Vector2(p_world_x, p_world_y),
			std::min(std::min(top_margin, bottom_margin), side_margin),
			depth,
		};
	}
	return {
		godot::Vector2(p_world_x, p_world_y),
		-std::max(0.001f, std::min(std::abs(sdf), std::max(1.0f, p_style.south_height_px))),
		sdf >= 0.0f ? 0.0f : p_style.south_height_px,
	};
}

ProjectionPoint interpolate_projection_crossing(const ProjectionPoint &p_a, const ProjectionPoint &p_b) {
	const float denom = p_a.value - p_b.value;
	const float t = std::abs(denom) <= 0.0001f ? 0.5f : std::max(0.0f, std::min(p_a.value / denom, 1.0f));
	return {
		p_a.point + (p_b.point - p_a.point) * t,
		0.0f,
		lerp_float(p_a.depth_px, p_b.depth_px, t),
	};
}

float projection_grid_value_at(
	const std::vector<ProjectionPoint> &p_points,
	int32_t p_columns,
	int32_t p_rows,
	float p_step_px,
	float p_max_x,
	float p_max_y,
	float p_world_x,
	float p_world_y
) {
	if (p_columns <= 1 || p_rows <= 1 || p_step_px <= 0.0f || p_points.empty()) {
		return -1.0f;
	}
	if (p_world_x < 0.0f || p_world_y < 0.0f || p_world_x > p_max_x || p_world_y > p_max_y) {
		return -1.0f;
	}
	const float grid_x = p_world_x / p_step_px;
	const float grid_y = p_world_y / p_step_px;
	const int32_t x0 = std::max(0, std::min(static_cast<int32_t>(std::floor(grid_x)), p_columns - 1));
	const int32_t y0 = std::max(0, std::min(static_cast<int32_t>(std::floor(grid_y)), p_rows - 1));
	const int32_t x1 = std::min(x0 + 1, p_columns - 1);
	const int32_t y1 = std::min(y0 + 1, p_rows - 1);
	const float tx = std::max(0.0f, std::min(grid_x - static_cast<float>(x0), 1.0f));
	const float ty = std::max(0.0f, std::min(grid_y - static_cast<float>(y0), 1.0f));
	const float nw = p_points[static_cast<size_t>(y0 * p_columns + x0)].value;
	const float ne = p_points[static_cast<size_t>(y0 * p_columns + x1)].value;
	const float sw = p_points[static_cast<size_t>(y1 * p_columns + x0)].value;
	const float se = p_points[static_cast<size_t>(y1 * p_columns + x1)].value;
	return lerp_float(lerp_float(nw, ne, tx), lerp_float(sw, se, tx), ty);
}

void append_projection_polygon(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	std::initializer_list<ProjectionPoint> p_points,
	const RuntimeStyle &p_style,
	float p_zone,
	float p_tile_size_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const float edge_width = std::max(1.0f, p_style.south_height_px + (p_zone == static_cast<float>(ZONE_OUTLINE) ? p_style.outline_width_px : 0.0f));
	const int32_t base_index = r_vertices.size();
	for (const ProjectionPoint &point : p_points) {
		const float depth = std::max(0.0f, std::min(point.depth_px, edge_width));
		r_vertices.append(point.point);
		append_vertex_attributes(
			r_attributes,
			point.point,
			make_sdf_attributes(
				point.point,
				-depth,
				depth,
				static_cast<float>(FACADE_SOUTH),
				p_zone,
				edge_width,
				p_tile_size_px
			),
			p_tile_size_px
		);
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

void append_projection_outline_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ProjectionPoint &p_a,
	const ProjectionPoint &p_b,
	const RuntimeStyle &p_style,
	float p_tile_size_px
) {
	if (!p_style.outline_enabled || p_style.outline_width_px <= 0.0f || p_a.point.distance_squared_to(p_b.point) <= 0.001f) {
		return;
	}
	const godot::Vector2 drop(0.0f, p_style.outline_width_px);
	const float edge_width = std::max(1.0f, p_style.south_height_px + p_style.outline_width_px);
	const float depth_a = std::max(p_a.depth_px, p_style.south_height_px);
	const float depth_b = std::max(p_b.depth_px, p_style.south_height_px);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_a.point,
		p_b.point,
		p_b.point + drop,
		p_a.point + drop,
		make_sdf_attributes(p_a.point, -depth_a, depth_a, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_OUTLINE), edge_width, p_tile_size_px),
		make_sdf_attributes(p_b.point, -depth_b, depth_b, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_OUTLINE), edge_width, p_tile_size_px),
		make_sdf_attributes(p_b.point + drop, -(depth_b + p_style.outline_width_px), depth_b + p_style.outline_width_px, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_OUTLINE), edge_width, p_tile_size_px),
		make_sdf_attributes(p_a.point + drop, -(depth_a + p_style.outline_width_px), depth_a + p_style.outline_width_px, static_cast<float>(FACADE_SOUTH), static_cast<float>(ZONE_OUTLINE), edge_width, p_tile_size_px),
		p_tile_size_px
	);
}

void append_projection_face_cell(
	godot::PackedVector2Array &r_face_vertices,
	godot::PackedInt32Array &r_face_indices,
	godot::PackedFloat32Array &r_face_attributes,
	godot::PackedVector2Array &r_outline_vertices,
	godot::PackedInt32Array &r_outline_indices,
	godot::PackedFloat32Array &r_outline_attributes,
	const std::vector<ProjectionPoint> &p_projection_points,
	int32_t p_projection_columns,
	int32_t p_projection_rows,
	const ProjectionPoint &p_tl,
	const ProjectionPoint &p_tr,
	const ProjectionPoint &p_br,
	const ProjectionPoint &p_bl,
	const RuntimeStyle &p_style,
	float p_step_px,
	float p_max_x,
	float p_max_y,
	float p_tile_size_px
) {
	const bool tl_inside = p_tl.value > 0.0f;
	const bool tr_inside = p_tr.value > 0.0f;
	const bool br_inside = p_br.value > 0.0f;
	const bool bl_inside = p_bl.value > 0.0f;
	const int32_t case_code =
			(tl_inside ? 1 : 0)
			| (tr_inside ? 2 : 0)
			| (br_inside ? 4 : 0)
			| (bl_inside ? 8 : 0);
	if (case_code == 0) {
		return;
	}
	const ProjectionPoint top = interpolate_projection_crossing(p_tl, p_tr);
	const ProjectionPoint right = interpolate_projection_crossing(p_tr, p_br);
	const ProjectionPoint bottom = interpolate_projection_crossing(p_bl, p_br);
	const ProjectionPoint left = interpolate_projection_crossing(p_tl, p_bl);
	const float face_zone = static_cast<float>(ZONE_FACE);

	switch (case_code) {
		case 1:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, top, left }, p_style, face_zone, p_tile_size_px);
			break;
		case 2:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tr, right, top }, p_style, face_zone, p_tile_size_px);
			break;
		case 3:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, p_tr, right, left }, p_style, face_zone, p_tile_size_px);
			break;
		case 4:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_br, bottom, right }, p_style, face_zone, p_tile_size_px);
			break;
		case 5:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, top, left }, p_style, face_zone, p_tile_size_px);
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_br, bottom, right }, p_style, face_zone, p_tile_size_px);
			break;
		case 6:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tr, p_br, bottom, top }, p_style, face_zone, p_tile_size_px);
			break;
		case 7:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, p_tr, p_br, bottom, left }, p_style, face_zone, p_tile_size_px);
			break;
		case 8:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_bl, left, bottom }, p_style, face_zone, p_tile_size_px);
			break;
		case 9:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, top, bottom, p_bl }, p_style, face_zone, p_tile_size_px);
			break;
		case 10:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tr, right, top }, p_style, face_zone, p_tile_size_px);
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_bl, left, bottom }, p_style, face_zone, p_tile_size_px);
			break;
		case 11:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, p_tr, right, bottom, p_bl }, p_style, face_zone, p_tile_size_px);
			break;
		case 12:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { left, right, p_br, p_bl }, p_style, face_zone, p_tile_size_px);
			break;
		case 13:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, top, right, p_br, p_bl }, p_style, face_zone, p_tile_size_px);
			break;
		case 14:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { top, p_tr, p_br, p_bl, left }, p_style, face_zone, p_tile_size_px);
			break;
		case 15:
			append_projection_polygon(r_face_vertices, r_face_indices, r_face_attributes, { p_tl, p_tr, p_br, p_bl }, p_style, face_zone, p_tile_size_px);
			break;
		default:
			break;
	}

	auto push_bottom_outline = [&](const ProjectionPoint &p_a, const ProjectionPoint &p_b) {
		const godot::Vector2 mid = midpoint_vec(p_a.point, p_b.point);
		const float above = projection_grid_value_at(
			p_projection_points,
			p_projection_columns,
			p_projection_rows,
			p_step_px,
			p_max_x,
			p_max_y,
			mid.x,
			mid.y - p_step_px * 0.55f
		);
		const float below = projection_grid_value_at(
			p_projection_points,
			p_projection_columns,
			p_projection_rows,
			p_step_px,
			p_max_x,
			p_max_y,
			mid.x,
			mid.y + p_step_px * 0.55f
		);
		if (above > 0.0f && below <= 0.0f) {
			append_projection_outline_segment(r_outline_vertices, r_outline_indices, r_outline_attributes, p_a, p_b, p_style, p_tile_size_px);
		}
	};

	switch (case_code) {
		case 1:
		case 14:
			push_bottom_outline(top, left);
			return;
		case 2:
		case 13:
			push_bottom_outline(right, top);
			return;
		case 3:
		case 12:
			push_bottom_outline(right, left);
			return;
		case 4:
		case 11:
			push_bottom_outline(bottom, right);
			return;
		case 5:
			push_bottom_outline(top, left);
			push_bottom_outline(bottom, right);
			return;
		case 6:
		case 9:
			push_bottom_outline(bottom, top);
			return;
		case 7:
		case 8:
			push_bottom_outline(bottom, left);
			return;
		case 10:
			push_bottom_outline(right, top);
			push_bottom_outline(left, bottom);
			return;
		default:
			return;
	}
}

void append_sdf_front_projection(
	godot::PackedVector2Array &r_face_vertices,
	godot::PackedInt32Array &r_face_indices,
	godot::PackedFloat32Array &r_face_attributes,
	godot::PackedVector2Array &r_outline_vertices,
	godot::PackedInt32Array &r_outline_indices,
	godot::PackedFloat32Array &r_outline_attributes,
	const SdfSampleGrid &p_grid,
	const SdfField &p_field,
	const RuntimeStyle &p_style,
	float p_chunk_px,
	float p_tile_size_px
) {
	const float step = SDF_VISUAL_STEP_PX;
	if (p_style.south_height_px <= 0.0f) {
		return;
	}
	const int32_t columns = static_cast<int32_t>(std::ceil(p_chunk_px / step)) + 1;
	const int32_t rows = static_cast<int32_t>(std::ceil(p_chunk_px / step)) + 1;
	if (columns <= 1 || rows <= 1) {
		return;
	}
	std::vector<ProjectionPoint> projection_points;
	projection_points.resize(static_cast<size_t>(columns * rows));
	for (int32_t y = 0; y < rows; ++y) {
		const float world_y = std::min(static_cast<float>(y) * step, p_chunk_px);
		for (int32_t x = 0; x < columns; ++x) {
			const float world_x = std::min(static_cast<float>(x) * step, p_chunk_px);
			projection_points[static_cast<size_t>(y * columns + x)] = make_projection_point(
				p_grid,
				p_field,
				p_style,
				world_x,
				world_y,
				p_tile_size_px
			);
		}
	}
	for (int32_t y = 0; y < rows - 1; ++y) {
		for (int32_t x = 0; x < columns - 1; ++x) {
			const ProjectionPoint &tl = projection_points[static_cast<size_t>(y * columns + x)];
			const ProjectionPoint &tr = projection_points[static_cast<size_t>(y * columns + x + 1)];
			const ProjectionPoint &br = projection_points[static_cast<size_t>((y + 1) * columns + x + 1)];
			const ProjectionPoint &bl = projection_points[static_cast<size_t>((y + 1) * columns + x)];
			append_projection_face_cell(
				r_face_vertices,
				r_face_indices,
				r_face_attributes,
				r_outline_vertices,
				r_outline_indices,
				r_outline_attributes,
				projection_points,
				columns,
				rows,
				tl,
				tr,
				br,
				bl,
				p_style,
				step,
				p_chunk_px,
				p_chunk_px,
				p_tile_size_px
			);
		}
	}
}

int32_t count_logical_boundary_edges(const std::vector<uint8_t> &p_solid_local, int32_t p_chunk_size) {
	int32_t boundary_edges = 0;
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			if (!read_local_solid(p_solid_local, p_chunk_size, x, y)) {
				continue;
			}
			boundary_edges += read_local_solid(p_solid_local, p_chunk_size, x - 1, y) ? 0 : 1;
			boundary_edges += read_local_solid(p_solid_local, p_chunk_size, x + 1, y) ? 0 : 1;
			boundary_edges += read_local_solid(p_solid_local, p_chunk_size, x, y - 1) ? 0 : 1;
			boundary_edges += read_local_solid(p_solid_local, p_chunk_size, x, y + 1) ? 0 : 1;
		}
	}
	return boundary_edges;
}

void append_contour_segment(
	std::vector<ContourSegment> &r_segments,
	godot::Vector2 p_a,
	godot::Vector2 p_b,
	godot::Vector2 p_solid_center,
	float p_chunk_px
) {
	godot::Vector2 a = clamp_vec(p_a, p_chunk_px);
	godot::Vector2 b = clamp_vec(p_b, p_chunk_px);
	if (a.distance_squared_to(b) <= 0.001f) {
		return;
	}
	godot::Vector2 midpoint = midpoint_vec(a, b);
	godot::Vector2 tangent = normalized_or(b - a, godot::Vector2(1.0f, 0.0f));
	godot::Vector2 fallback = godot::Vector2(tangent.y, -tangent.x);
	godot::Vector2 outward = normalized_or(midpoint - p_solid_center, fallback);
	r_segments.push_back({ a, b, outward });
}

godot::Vector2 solid_center_for_case(
	int32_t p_case_code,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl
) {
	godot::Vector2 center;
	float count = 0.0f;
	if ((p_case_code & 1) != 0) {
		center += p_tl;
		count += 1.0f;
	}
	if ((p_case_code & 2) != 0) {
		center += p_tr;
		count += 1.0f;
	}
	if ((p_case_code & 4) != 0) {
		center += p_br;
		count += 1.0f;
	}
	if ((p_case_code & 8) != 0) {
		center += p_bl;
		count += 1.0f;
	}
	return count > 0.0f ? center / count : midpoint_vec(p_tl, p_br);
}

void append_case_contour_segments(
	std::vector<ContourSegment> &r_segments,
	int32_t p_case_code,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_chunk_px
) {
	if (p_case_code == 0 || p_case_code == 15) {
		return;
	}
	const godot::Vector2 top = midpoint_vec(p_tl, p_tr);
	const godot::Vector2 right = midpoint_vec(p_tr, p_br);
	const godot::Vector2 bottom = midpoint_vec(p_bl, p_br);
	const godot::Vector2 left = midpoint_vec(p_tl, p_bl);
	const godot::Vector2 solid_center = solid_center_for_case(p_case_code, p_tl, p_tr, p_br, p_bl);
	switch (p_case_code) {
		case 1:
		case 14:
			append_contour_segment(r_segments, top, left, solid_center, p_chunk_px);
			return;
		case 2:
		case 13:
			append_contour_segment(r_segments, right, top, solid_center, p_chunk_px);
			return;
		case 3:
		case 12:
			append_contour_segment(r_segments, right, left, solid_center, p_chunk_px);
			return;
		case 4:
		case 11:
			append_contour_segment(r_segments, bottom, right, solid_center, p_chunk_px);
			return;
		case 5:
			append_contour_segment(r_segments, top, left, solid_center, p_chunk_px);
			append_contour_segment(r_segments, bottom, right, solid_center, p_chunk_px);
			return;
		case 6:
		case 9:
			append_contour_segment(r_segments, bottom, top, solid_center, p_chunk_px);
			return;
		case 7:
		case 8:
			append_contour_segment(r_segments, bottom, left, solid_center, p_chunk_px);
			return;
		case 10:
			append_contour_segment(r_segments, right, top, solid_center, p_chunk_px);
			append_contour_segment(r_segments, left, bottom, solid_center, p_chunk_px);
			return;
		default:
			return;
	}
}

float facade_side_for_outward(godot::Vector2 p_outward) {
	if (p_outward.y > 0.65f && std::abs(p_outward.x) < 0.35f) {
		return static_cast<float>(FACADE_SOUTH);
	}
	if (std::abs(p_outward.x) > 0.65f && std::abs(p_outward.y) < 0.35f) {
		return static_cast<float>(FACADE_SIDE);
	}
	return static_cast<float>(FACADE_DIAGONAL);
}

void append_rim_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px
) {
	if (p_style.rim_width_px <= 0.0f) {
		return;
	}
	const float rim_width = std::min(p_style.rim_width_px + p_style.corner_round_px * 0.125f, p_tile_size_px * 0.5f);
	const godot::Vector2 inward = -p_segment.outward;
	const float facade_side = facade_side_for_outward(p_segment.outward);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a,
		p_segment.b,
		p_segment.b + inward * rim_width,
		p_segment.a + inward * rim_width,
		{ p_edge_u_start, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_end, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_end, 1.0f, rim_width, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_start, 1.0f, rim_width, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		p_tile_size_px
	);
}

void append_face_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px
) {
	const float height = std::max(0.0f, p_segment.outward.y) * p_style.south_height_px
			+ std::abs(p_segment.outward.x) * p_style.side_height_px;
	if (height <= 0.0f) {
		return;
	}
	const godot::Vector2 drop(0.0f, height);
	const float facade_side = facade_side_for_outward(p_segment.outward);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a,
		p_segment.b,
		p_segment.b + drop,
		p_segment.a + drop,
		{ p_edge_u_start, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_end, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_end, 1.0f, -height, height, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_start, 1.0f, -height, height, facade_side, static_cast<float>(ZONE_FACE) },
		p_tile_size_px
	);
}

void append_outline_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px
) {
	if (!p_style.outline_enabled || p_style.outline_width_px <= 0.0f) {
		return;
	}
	const float height = std::max(0.0f, p_segment.outward.y) * p_style.south_height_px
			+ std::abs(p_segment.outward.x) * p_style.side_height_px;
	if (height <= 0.0f) {
		return;
	}
	const godot::Vector2 face_drop(0.0f, height);
	const godot::Vector2 outline_drop(0.0f, p_style.outline_width_px);
	const float facade_side = facade_side_for_outward(p_segment.outward);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a + face_drop,
		p_segment.b + face_drop,
		p_segment.b + face_drop + outline_drop,
		p_segment.a + face_drop + outline_drop,
		{ p_edge_u_start, 0.0f, -height, height, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_end, 0.0f, -height, height, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_end, 1.0f, -(height + p_style.outline_width_px), height + p_style.outline_width_px, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_start, 1.0f, -(height + p_style.outline_width_px), height + p_style.outline_width_px, facade_side, static_cast<float>(ZONE_OUTLINE) },
		p_tile_size_px
	);
}

godot::Dictionary make_runtime_result_shell(int32_t p_chunk_size, int32_t p_tile_size_px, int32_t p_halo_side, bool p_ready) {
	godot::Dictionary result;
	result["ready"] = p_ready;
	result["chunk_size"] = p_chunk_size;
	result["tile_size_px"] = p_tile_size_px;
	result["halo_side"] = p_halo_side;
	result["solid_sample_count"] = 0;
	result["visual_top_vertices"] = godot::PackedVector2Array();
	result["visual_top_indices"] = godot::PackedInt32Array();
	result["visual_top_attributes"] = godot::PackedFloat32Array();
	result["visual_face_vertices"] = godot::PackedVector2Array();
	result["visual_face_indices"] = godot::PackedInt32Array();
	result["visual_face_attributes"] = godot::PackedFloat32Array();
	result["visual_rim_vertices"] = godot::PackedVector2Array();
	result["visual_rim_indices"] = godot::PackedInt32Array();
	result["visual_rim_attributes"] = godot::PackedFloat32Array();
	result["visual_outline_vertices"] = godot::PackedVector2Array();
	result["visual_outline_indices"] = godot::PackedInt32Array();
	result["visual_outline_attributes"] = godot::PackedFloat32Array();
	result["collision_loops"] = godot::Array();
	result["collision_aabbs"] = godot::Array();
	result["boundary_edge_count"] = 0;
	result["seam_touch_mask"] = 0;
	result["compute_time_usec"] = 0;
	return result;
}

void append_component_collision(
	godot::Array &r_collision_loops,
	godot::Array &r_collision_aabbs,
	int32_t p_min_x,
	int32_t p_min_y,
	int32_t p_max_x,
	int32_t p_max_y,
	int32_t p_tile_size_px,
	float p_south_height_px,
	float p_outline_width_px
) {
	const float tile = static_cast<float>(p_tile_size_px);
	const float x0 = static_cast<float>(p_min_x) * tile;
	const float y0 = static_cast<float>(p_min_y) * tile;
	const float x1 = static_cast<float>(p_max_x + 1) * tile;
	const float y1 = static_cast<float>(p_max_y + 1) * tile + p_south_height_px + p_outline_width_px;
	godot::PackedVector2Array loop;
	loop.append(godot::Vector2(x0, y0));
	loop.append(godot::Vector2(x1, y0));
	loop.append(godot::Vector2(x1, y1));
	loop.append(godot::Vector2(x0, y1));
	r_collision_loops.append(loop);
	r_collision_aabbs.append(godot::Rect2(godot::Vector2(x0, y0), godot::Vector2(x1 - x0, y1 - y0)));
}

godot::Rect2 loop_aabb(const godot::PackedVector2Array &p_loop) {
	if (p_loop.is_empty()) {
		return godot::Rect2();
	}
	float min_x = p_loop[0].x;
	float min_y = p_loop[0].y;
	float max_x = p_loop[0].x;
	float max_y = p_loop[0].y;
	for (int32_t index = 1; index < p_loop.size(); ++index) {
		const godot::Vector2 point = p_loop[index];
		min_x = std::min(min_x, point.x);
		min_y = std::min(min_y, point.y);
		max_x = std::max(max_x, point.x);
		max_y = std::max(max_y, point.y);
	}
	return godot::Rect2(godot::Vector2(min_x, min_y), godot::Vector2(max_x - min_x, max_y - min_y));
}

void append_collision_triangles_from_mesh(
	godot::Array &r_collision_loops,
	godot::Array &r_collision_aabbs,
	const godot::PackedVector2Array &p_vertices,
	const godot::PackedInt32Array &p_indices
) {
	for (int32_t index = 0; index + 2 < p_indices.size(); index += 3) {
		const int32_t ia = p_indices[index];
		const int32_t ib = p_indices[index + 1];
		const int32_t ic = p_indices[index + 2];
		if (ia < 0 || ib < 0 || ic < 0 || ia >= p_vertices.size() || ib >= p_vertices.size() || ic >= p_vertices.size()) {
			continue;
		}
		godot::PackedVector2Array loop;
		loop.append(p_vertices[ia]);
		loop.append(p_vertices[ib]);
		loop.append(p_vertices[ic]);
		r_collision_loops.append(loop);
		r_collision_aabbs.append(loop_aabb(loop));
	}
}

} // namespace

godot::Dictionary build_debug_mesh(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px
) {
	godot::PackedVector2Array vertices;
	godot::PackedInt32Array indices;
	godot::Dictionary result;
	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = 0;
	result["halo_side"] = 0;

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = p_chunk_size + 2;
	if (p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}

	int32_t solid_sample_count = 0;
	for (int32_t y = 1; y <= p_chunk_size; ++y) {
		for (int32_t x = 1; x <= p_chunk_size; ++x) {
			if (read_solid(p_solid_halo, halo_side, x, y)) {
				++solid_sample_count;
			}
		}
	}

	const float chunk_px = static_cast<float>(p_chunk_size * p_tile_size_px);
	for (int32_t y = 0; y < halo_side - 1; ++y) {
		for (int32_t x = 0; x < halo_side - 1; ++x) {
			const bool tl_solid = read_solid(p_solid_halo, halo_side, x, y);
			const bool tr_solid = read_solid(p_solid_halo, halo_side, x + 1, y);
			const bool br_solid = read_solid(p_solid_halo, halo_side, x + 1, y + 1);
			const bool bl_solid = read_solid(p_solid_halo, halo_side, x, y + 1);
			const int32_t case_code =
					(tl_solid ? 1 : 0) |
					(tr_solid ? 2 : 0) |
					(br_solid ? 4 : 0) |
					(bl_solid ? 8 : 0);
			if (case_code == 0) {
				continue;
			}
			append_case_mesh(
				vertices,
				indices,
				case_code,
				sample_point(x, y, p_tile_size_px),
				sample_point(x + 1, y, p_tile_size_px),
				sample_point(x + 1, y + 1, p_tile_size_px),
				sample_point(x, y + 1, p_tile_size_px),
				chunk_px
			);
		}
	}

	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = solid_sample_count;
	result["halo_side"] = halo_side;
	return result;
}

godot::Dictionary build_runtime_result(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px,
	const godot::Dictionary &p_style_params
) {
	const auto start_time = std::chrono::steady_clock::now();
	const int32_t halo_side = p_chunk_size + 2;
	godot::Dictionary result = make_runtime_result_shell(p_chunk_size, p_tile_size_px, std::max(0, halo_side), false);
	if (p_chunk_size <= 0 || p_tile_size_px <= 0 || p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}

	const RuntimeStyle style = read_runtime_style(p_style_params);
	godot::PackedVector2Array top_vertices;
	godot::PackedInt32Array top_indices;
	godot::PackedFloat32Array top_attributes;
	godot::PackedVector2Array face_vertices;
	godot::PackedInt32Array face_indices;
	godot::PackedFloat32Array face_attributes;
	godot::PackedVector2Array rim_vertices;
	godot::PackedInt32Array rim_indices;
	godot::PackedFloat32Array rim_attributes;
	godot::PackedVector2Array outline_vertices;
	godot::PackedInt32Array outline_indices;
	godot::PackedFloat32Array outline_attributes;

	std::vector<uint8_t> solid_local(static_cast<size_t>(p_chunk_size * p_chunk_size), 0U);
	int32_t solid_sample_count = 0;
	int32_t boundary_edge_count = 0;
	int32_t seam_touch_mask = 0;
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			if (!read_solid(p_solid_halo, halo_side, x + 1, y + 1)) {
				continue;
			}
			solid_local[static_cast<size_t>(y * p_chunk_size + x)] = 1U;
			++solid_sample_count;
			if (x == 0) {
				seam_touch_mask |= SEAM_WEST;
			}
			if (x == p_chunk_size - 1) {
				seam_touch_mask |= SEAM_EAST;
			}
			if (y == 0) {
				seam_touch_mask |= SEAM_NORTH;
			}
			if (y == p_chunk_size - 1) {
				seam_touch_mask |= SEAM_SOUTH;
			}
		}
	}

	const float chunk_px = static_cast<float>(p_chunk_size * p_tile_size_px);
	std::vector<ContourSegment> contour_segments;
	const float tile_size_px = static_cast<float>(p_tile_size_px);
	const float edge_width_px = std::max(1.0f, std::min(style.rim_width_px, tile_size_px * 0.25f));
	const SdfField sdf_field = build_sdf_field(p_solid_halo, halo_side);
	const float sample_grid_max_y = chunk_px + style.south_height_px + (style.outline_enabled ? style.outline_width_px : 0.0f);
	const SdfSampleGrid sample_grid = build_sdf_sample_grid(sdf_field, style, chunk_px, sample_grid_max_y, tile_size_px);
	boundary_edge_count = count_logical_boundary_edges(solid_local, p_chunk_size);
	const int32_t visual_columns = std::max(0, static_cast<int32_t>(std::ceil(chunk_px / SDF_VISUAL_STEP_PX)));
	const int32_t visual_rows = std::max(0, static_cast<int32_t>(std::ceil(chunk_px / SDF_VISUAL_STEP_PX)));
	for (int32_t grid_y = 0; grid_y < visual_rows; ++grid_y) {
		const float y = sdf_grid_world_y(sample_grid, grid_y);
		const float y1 = sdf_grid_world_y(sample_grid, grid_y + 1);
		for (int32_t grid_x = 0; grid_x < visual_columns; ++grid_x) {
			const float x = sdf_grid_world_x(sample_grid, grid_x);
			const float x1 = sdf_grid_world_x(sample_grid, grid_x + 1);
			const SdfPolyPoint tl = {
				godot::Vector2(x, y),
				sdf_grid_node_value(sample_grid, grid_x, grid_y),
			};
			const SdfPolyPoint tr = {
				godot::Vector2(x1, y),
				sdf_grid_node_value(sample_grid, grid_x + 1, grid_y),
			};
			const SdfPolyPoint br = {
				godot::Vector2(x1, y1),
				sdf_grid_node_value(sample_grid, grid_x + 1, grid_y + 1),
			};
			const SdfPolyPoint bl = {
				godot::Vector2(x, y1),
				sdf_grid_node_value(sample_grid, grid_x, grid_y + 1),
			};
			append_sdf_top_cell(top_vertices, top_indices, top_attributes, tl, tr, br, bl, edge_width_px, tile_size_px);
			append_sdf_contour_cell(contour_segments, sdf_field, style, tl, tr, br, bl, tile_size_px, chunk_px);
		}
	}
	float edge_u_cursor = 0.0f;
	for (const ContourSegment &segment : contour_segments) {
		const float edge_u_start = edge_u_cursor / std::max(1.0f, tile_size_px);
		edge_u_cursor += segment.a.distance_to(segment.b);
		const float edge_u_end = edge_u_cursor / std::max(1.0f, tile_size_px);
		append_rim_segment(rim_vertices, rim_indices, rim_attributes, segment, style, edge_u_start, edge_u_end, tile_size_px);
		if (style.side_height_px > 0.0f || style.north_height_px > 0.0f) {
			append_face_segment(face_vertices, face_indices, face_attributes, segment, style, edge_u_start, edge_u_end, tile_size_px);
			append_outline_segment(outline_vertices, outline_indices, outline_attributes, segment, style, edge_u_start, edge_u_end, tile_size_px);
		}
	}
	if (style.side_height_px <= 0.0f && style.north_height_px <= 0.0f) {
		append_sdf_front_projection(
			face_vertices,
			face_indices,
			face_attributes,
			outline_vertices,
			outline_indices,
			outline_attributes,
			sample_grid,
			sdf_field,
			style,
			chunk_px,
			tile_size_px
		);
	}

	godot::Array collision_loops;
	godot::Array collision_aabbs;
	append_collision_triangles_from_mesh(collision_loops, collision_aabbs, top_vertices, top_indices);
	if (collision_loops.is_empty() && solid_sample_count > 0) {
		append_component_collision(
			collision_loops,
			collision_aabbs,
			0,
			0,
			p_chunk_size - 1,
			p_chunk_size - 1,
			p_tile_size_px,
			style.south_height_px,
			style.outline_enabled ? style.outline_width_px : 0.0f
		);
	}

	const auto end_time = std::chrono::steady_clock::now();
	const int64_t compute_time_usec = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time).count();
	result["ready"] = true;
	result["solid_sample_count"] = solid_sample_count;
	result["visual_top_vertices"] = top_vertices;
	result["visual_top_indices"] = top_indices;
	result["visual_top_attributes"] = top_attributes;
	result["visual_face_vertices"] = face_vertices;
	result["visual_face_indices"] = face_indices;
	result["visual_face_attributes"] = face_attributes;
	result["visual_rim_vertices"] = rim_vertices;
	result["visual_rim_indices"] = rim_indices;
	result["visual_rim_attributes"] = rim_attributes;
	result["visual_outline_vertices"] = outline_vertices;
	result["visual_outline_indices"] = outline_indices;
	result["visual_outline_attributes"] = outline_attributes;
	result["collision_loops"] = collision_loops;
	result["collision_aabbs"] = collision_aabbs;
	result["boundary_edge_count"] = boundary_edge_count;
	result["seam_touch_mask"] = seam_touch_mask;
	result["compute_time_usec"] = compute_time_usec;
	return result;
}

} // namespace mountain_contour
