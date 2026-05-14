#include "mountain_contour.h"

#include <algorithm>
#include <chrono>
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

struct RuntimeStyle {
	float south_height_px = 32.0f;
	float side_height_px = 16.0f;
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

float clamp_coord(float p_value, float p_max) {
	return std::max(0.0f, std::min(p_value, p_max));
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
	constexpr int32_t directions[4][2] = {
		{ 0, -1 },
		{ 1, 0 },
		{ 0, 1 },
		{ -1, 0 },
	};
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			if (!read_solid(p_solid_halo, halo_side, x + 1, y + 1)) {
				continue;
			}
			solid_local[static_cast<size_t>(y * p_chunk_size + x)] = 1U;
			++solid_sample_count;
			append_top_tile(top_vertices, top_indices, top_attributes, x, y, p_tile_size_px);
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
			for (const auto &direction : directions) {
				const int32_t dx = direction[0];
				const int32_t dy = direction[1];
				if (read_solid(p_solid_halo, halo_side, x + 1 + dx, y + 1 + dy)) {
					continue;
				}
				++boundary_edge_count;
				append_rim_edge(rim_vertices, rim_indices, rim_attributes, x, y, p_tile_size_px, style.rim_width_px, dx, dy);
				if (dy > 0) {
					append_south_face(face_vertices, face_indices, face_attributes, x, y, p_tile_size_px, style.south_height_px);
					if (style.outline_enabled) {
						append_south_outline(outline_vertices, outline_indices, outline_attributes, x, y, p_tile_size_px, style.south_height_px, style.outline_width_px);
					}
				}
			}
		}
	}

	godot::Array collision_loops;
	godot::Array collision_aabbs;
	std::vector<uint8_t> visited(static_cast<size_t>(p_chunk_size * p_chunk_size), 0U);
	std::vector<int32_t> queue;
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			const int32_t start_index = y * p_chunk_size + x;
			if (!read_local_solid(solid_local, p_chunk_size, x, y) || visited[static_cast<size_t>(start_index)] != 0U) {
				continue;
			}
			int32_t min_x = x;
			int32_t max_x = x;
			int32_t min_y = y;
			int32_t max_y = y;
			queue.clear();
			queue.push_back(start_index);
			visited[static_cast<size_t>(start_index)] = 1U;
			for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
				const int32_t index = queue[cursor];
				const int32_t cx = index % p_chunk_size;
				const int32_t cy = index / p_chunk_size;
				min_x = std::min(min_x, cx);
				max_x = std::max(max_x, cx);
				min_y = std::min(min_y, cy);
				max_y = std::max(max_y, cy);
				for (const auto &direction : directions) {
					const int32_t nx = cx + direction[0];
					const int32_t ny = cy + direction[1];
					if (!read_local_solid(solid_local, p_chunk_size, nx, ny)) {
						continue;
					}
					const int32_t neighbour_index = ny * p_chunk_size + nx;
					if (visited[static_cast<size_t>(neighbour_index)] != 0U) {
						continue;
					}
					visited[static_cast<size_t>(neighbour_index)] = 1U;
					queue.push_back(neighbour_index);
				}
			}
			append_component_collision(
				collision_loops,
				collision_aabbs,
				min_x,
				min_y,
				max_x,
				max_y,
				p_tile_size_px,
				style.south_height_px,
				style.outline_enabled ? style.outline_width_px : 0.0f
			);
		}
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
