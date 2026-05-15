#include "mountain_contour.h"

#include <algorithm>
#include <initializer_list>

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace mountain_contour {
namespace {

struct ContourPoint {
	float x = 0.0f;
	float y = 0.0f;
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

} // namespace mountain_contour
