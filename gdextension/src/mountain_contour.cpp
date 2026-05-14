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
	float side_height_px = 16.0f;
	float corner_round_px = 16.0f;
	float diagonal_smooth_px = 32.0f;
	float contour_warp_px = 0.0f;
	float rim_width_px = 8.0f;
	float outline_width_px = 3.0f;
	bool outline_enabled = true;
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
	float p_edge_distance,
	float p_face_depth,
	float p_edge_kind,
	float p_material_zone,
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
	float p_edge_distance,
	float p_edge_kind,
	float p_material_zone,
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
			p_edge_distance,
			0.0f,
			p_edge_kind,
			p_material_zone,
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
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 2:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 3:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, left }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 4:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 5:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, left }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_br, bottom, right }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 6:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, p_br, bottom, top }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 7:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, bottom, left }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 8:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 9:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, bottom, p_bl }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 10:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tr, right, top }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_bl, left, bottom }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 11:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, right, bottom, p_bl }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 12:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { left, right, p_br, p_bl }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 13:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, top, right, p_br, p_bl }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 14:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { top, p_tr, p_br, p_bl, left }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
			return;
		case 15:
			append_polygon_runtime(r_vertices, r_indices, r_attributes, { p_tl, p_tr, p_br, p_bl }, p_chunk_px, edge_distance, 0.0f, static_cast<float>(ZONE_TOP), p_tile_size_px);
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
	style.side_height_px = std::max(0.0f, std::min(read_style_float(p_style_params, "side_height_px", style.side_height_px), 512.0f));
	style.corner_round_px = std::max(0.0f, std::min(read_style_float(p_style_params, "corner_round_px", style.corner_round_px), 256.0f));
	style.diagonal_smooth_px = std::max(0.0f, std::min(read_style_float(p_style_params, "diagonal_smooth_px", style.diagonal_smooth_px), 256.0f));
	style.contour_warp_px = std::max(0.0f, std::min(read_style_float(p_style_params, "contour_warp_px", style.contour_warp_px), 256.0f));
	style.rim_width_px = std::max(0.0f, std::min(read_style_float(p_style_params, "rim_width_px", style.rim_width_px), 256.0f));
	style.outline_width_px = std::max(0.0f, std::min(read_style_float(p_style_params, "mountain_outline_width_px", style.outline_width_px), 256.0f));
	style.outline_enabled = read_style_bool(p_style_params, "mountain_outline_enabled", style.outline_enabled);
	return style;
}

void append_vertex_attributes(
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_vertex,
	float p_edge_distance,
	float p_face_depth,
	float p_edge_kind,
	float p_material_zone,
	float p_tile_size_px
) {
	r_attributes.append(p_edge_distance);
	r_attributes.append(p_face_depth);
	r_attributes.append(p_edge_kind);
	r_attributes.append(p_vertex.x / p_tile_size_px);
	r_attributes.append(p_vertex.y / p_tile_size_px);
	r_attributes.append(p_material_zone);
}

void append_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_a,
	godot::Vector2 p_b,
	godot::Vector2 p_c,
	godot::Vector2 p_d,
	float p_edge_distance,
	float p_face_depth_a,
	float p_face_depth_b,
	float p_edge_kind,
	float p_material_zone,
	float p_tile_size_px
) {
	const int32_t base_index = r_vertices.size();
	r_vertices.append(p_a);
	r_vertices.append(p_b);
	r_vertices.append(p_c);
	r_vertices.append(p_d);
	append_vertex_attributes(r_attributes, p_a, p_edge_distance, p_face_depth_a, p_edge_kind, p_material_zone, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_b, p_edge_distance, p_face_depth_a, p_edge_kind, p_material_zone, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_c, p_edge_distance, p_face_depth_b, p_edge_kind, p_material_zone, p_tile_size_px);
	append_vertex_attributes(r_attributes, p_d, p_edge_distance, p_face_depth_b, p_edge_kind, p_material_zone, p_tile_size_px);
	r_indices.append(base_index);
	r_indices.append(base_index + 1);
	r_indices.append(base_index + 2);
	r_indices.append(base_index);
	r_indices.append(base_index + 2);
	r_indices.append(base_index + 3);
}

void append_top_tile(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_x,
	int32_t p_y,
	int32_t p_tile_size_px
) {
	const float tile = static_cast<float>(p_tile_size_px);
	const float x0 = static_cast<float>(p_x) * tile;
	const float y0 = static_cast<float>(p_y) * tile;
	const float x1 = x0 + tile;
	const float y1 = y0 + tile;
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		godot::Vector2(x0, y0),
		godot::Vector2(x1, y0),
		godot::Vector2(x1, y1),
		godot::Vector2(x0, y1),
		tile * 0.5f,
		0.0f,
		0.0f,
		0.0f,
		static_cast<float>(ZONE_TOP),
		tile
	);
}

void append_south_face(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_x,
	int32_t p_y,
	int32_t p_tile_size_px,
	float p_height_px
) {
	if (p_height_px <= 0.0f) {
		return;
	}
	const float tile = static_cast<float>(p_tile_size_px);
	const float x0 = static_cast<float>(p_x) * tile;
	const float y1 = static_cast<float>(p_y + 1) * tile;
	const float x1 = x0 + tile;
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		godot::Vector2(x0, y1),
		godot::Vector2(x1, y1),
		godot::Vector2(x1, y1 + p_height_px),
		godot::Vector2(x0, y1 + p_height_px),
		0.0f,
		0.0f,
		p_height_px,
		1.0f,
		static_cast<float>(ZONE_FACE),
		tile
	);
}

void append_south_outline(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_x,
	int32_t p_y,
	int32_t p_tile_size_px,
	float p_height_px,
	float p_outline_width_px
) {
	if (p_height_px <= 0.0f || p_outline_width_px <= 0.0f) {
		return;
	}
	const float tile = static_cast<float>(p_tile_size_px);
	const float x0 = static_cast<float>(p_x) * tile;
	const float y = static_cast<float>(p_y + 1) * tile + p_height_px;
	const float x1 = x0 + tile;
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		godot::Vector2(x0, y),
		godot::Vector2(x1, y),
		godot::Vector2(x1, y + p_outline_width_px),
		godot::Vector2(x0, y + p_outline_width_px),
		0.0f,
		0.0f,
		p_outline_width_px,
		3.0f,
		static_cast<float>(ZONE_OUTLINE),
		tile
	);
}

void append_rim_edge(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_x,
	int32_t p_y,
	int32_t p_tile_size_px,
	float p_rim_width_px,
	int32_t p_dir_x,
	int32_t p_dir_y
) {
	if (p_rim_width_px <= 0.0f) {
		return;
	}
	const float tile = static_cast<float>(p_tile_size_px);
	const float rim = std::min(p_rim_width_px, tile * 0.5f);
	const float x0 = static_cast<float>(p_x) * tile;
	const float y0 = static_cast<float>(p_y) * tile;
	const float x1 = x0 + tile;
	const float y1 = y0 + tile;
	if (p_dir_y < 0) {
		append_quad(r_vertices, r_indices, r_attributes, godot::Vector2(x0, y0), godot::Vector2(x1, y0), godot::Vector2(x1, y0 + rim), godot::Vector2(x0, y0 + rim), rim, 0.0f, 0.0f, 2.0f, static_cast<float>(ZONE_RIM), tile);
	} else if (p_dir_y > 0) {
		append_quad(r_vertices, r_indices, r_attributes, godot::Vector2(x1, y1), godot::Vector2(x0, y1), godot::Vector2(x0, y1 - rim), godot::Vector2(x1, y1 - rim), rim, 0.0f, 0.0f, 2.0f, static_cast<float>(ZONE_RIM), tile);
	} else if (p_dir_x < 0) {
		append_quad(r_vertices, r_indices, r_attributes, godot::Vector2(x0, y1), godot::Vector2(x0, y0), godot::Vector2(x0 + rim, y0), godot::Vector2(x0 + rim, y1), rim, 0.0f, 0.0f, 2.0f, static_cast<float>(ZONE_RIM), tile);
	} else if (p_dir_x > 0) {
		append_quad(r_vertices, r_indices, r_attributes, godot::Vector2(x1, y0), godot::Vector2(x1, y1), godot::Vector2(x1 - rim, y1), godot::Vector2(x1 - rim, y0), rim, 0.0f, 0.0f, 2.0f, static_cast<float>(ZONE_RIM), tile);
	}
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

void append_rim_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
	float p_tile_size_px
) {
	if (p_style.rim_width_px <= 0.0f) {
		return;
	}
	const float rim_width = std::min(p_style.rim_width_px + p_style.corner_round_px * 0.125f, p_tile_size_px * 0.5f);
	const godot::Vector2 inward = -p_segment.outward;
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a,
		p_segment.b,
		p_segment.b + inward * rim_width,
		p_segment.a + inward * rim_width,
		rim_width,
		0.0f,
		0.0f,
		2.0f,
		static_cast<float>(ZONE_RIM),
		p_tile_size_px
	);
}

void append_face_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
	float p_tile_size_px
) {
	const float height = std::max(0.0f, p_segment.outward.y) * p_style.south_height_px
			+ std::abs(p_segment.outward.x) * p_style.side_height_px;
	if (height <= 0.0f) {
		return;
	}
	const godot::Vector2 drop(0.0f, height);
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a,
		p_segment.b,
		p_segment.b + drop,
		p_segment.a + drop,
		0.0f,
		0.0f,
		height,
		1.0f,
		static_cast<float>(ZONE_FACE),
		p_tile_size_px
	);
}

void append_outline_segment(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	const RuntimeStyle &p_style,
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
	append_quad(
		r_vertices,
		r_indices,
		r_attributes,
		p_segment.a + face_drop,
		p_segment.b + face_drop,
		p_segment.b + face_drop + outline_drop,
		p_segment.a + face_drop + outline_drop,
		0.0f,
		0.0f,
		p_style.outline_width_px,
		3.0f,
		static_cast<float>(ZONE_OUTLINE),
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
			const godot::Vector2 tl = sample_vec(x, y, p_tile_size_px);
			const godot::Vector2 tr = sample_vec(x + 1, y, p_tile_size_px);
			const godot::Vector2 br = sample_vec(x + 1, y + 1, p_tile_size_px);
			const godot::Vector2 bl = sample_vec(x, y + 1, p_tile_size_px);
			append_case_top_mesh(
				top_vertices,
				top_indices,
				top_attributes,
				case_code,
				tl,
				tr,
				br,
				bl,
				chunk_px,
				style,
				static_cast<float>(p_tile_size_px)
			);
			const size_t segment_count_before = contour_segments.size();
			append_case_contour_segments(contour_segments, case_code, tl, tr, br, bl, chunk_px);
			boundary_edge_count += static_cast<int32_t>(contour_segments.size() - segment_count_before);
		}
	}
	for (const ContourSegment &segment : contour_segments) {
		append_rim_segment(rim_vertices, rim_indices, rim_attributes, segment, style, static_cast<float>(p_tile_size_px));
		append_face_segment(face_vertices, face_indices, face_attributes, segment, style, static_cast<float>(p_tile_size_px));
		append_outline_segment(outline_vertices, outline_indices, outline_attributes, segment, style, static_cast<float>(p_tile_size_px));
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
