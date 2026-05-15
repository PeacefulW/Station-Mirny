#include "mountain_contour.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
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

constexpr int32_t ATTRIBUTE_STRIDE = 8;
constexpr float DEFAULT_FACE_DEPTH_NORM = 256.0f;
constexpr int32_t ARC_SEGMENTS_PER_QUARTER = 4;
constexpr float MATH_PI = 3.14159265358979323846f;

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

enum FacadeSide : int32_t {
	FACADE_SOUTH = 0,
	FACADE_SIDE = 1,
	FACADE_DIAGONAL = 2,
};

struct RuntimeStyle {
	float south_height_px = 32.0f;
	float north_height_px = 0.0f;
	float side_height_px = 0.0f;
	float rim_width_px = 8.0f;
	float outline_width_px = 3.0f;
	float corner_round_px = 16.0f;
	bool outline_enabled = true;
};

struct ContourSegment {
	godot::Vector2 a;
	godot::Vector2 b;
	godot::Vector2 outward;
};

struct VertexAttr {
	float edge_u = 0.0f;
	float edge_v = 0.0f;
	float signed_distance_px = 0.0f;
	float face_depth_px = 0.0f;
	float facade_side = 0.0f;
	float zone = 0.0f;
};

float read_style_float(const godot::Dictionary &p_style, const char *p_key, float p_default) {
	const godot::Variant value = p_style.get(p_key, p_default);
	if (value.get_type() == godot::Variant::NIL) {
		return p_default;
	}
	return static_cast<float>(static_cast<double>(value));
}

bool read_style_bool(const godot::Dictionary &p_style, const char *p_key, bool p_default) {
	const godot::Variant value = p_style.get(p_key, p_default);
	if (value.get_type() == godot::Variant::NIL) {
		return p_default;
	}
	return static_cast<bool>(value);
}

RuntimeStyle read_runtime_style(const godot::Dictionary &p_style) {
	RuntimeStyle style;
	style.south_height_px = std::max(0.0f, std::min(read_style_float(p_style, "south_height_px", style.south_height_px), 512.0f));
	style.north_height_px = std::max(0.0f, std::min(read_style_float(p_style, "north_height_px", style.north_height_px), 512.0f));
	style.side_height_px = std::max(0.0f, std::min(read_style_float(p_style, "side_height_px", style.side_height_px), 512.0f));
	style.rim_width_px = std::max(0.0f, std::min(read_style_float(p_style, "rim_width_px", style.rim_width_px), 256.0f));
	style.outline_width_px = std::max(0.0f, std::min(read_style_float(p_style, "mountain_outline_width_px", style.outline_width_px), 256.0f));
	style.corner_round_px = std::max(0.0f, std::min(read_style_float(p_style, "corner_round_px", style.corner_round_px), 256.0f));
	style.outline_enabled = read_style_bool(p_style, "mountain_outline_enabled", style.outline_enabled);
	return style;
}

std::vector<godot::Vector2> build_arc_points(
	godot::Vector2 p_center,
	godot::Vector2 p_from,
	godot::Vector2 p_to,
	int32_t p_segments
) {
	std::vector<godot::Vector2> result;
	if (p_segments < 1) {
		p_segments = 1;
	}
	const godot::Vector2 v_from = p_from - p_center;
	const godot::Vector2 v_to = p_to - p_center;
	const float angle_from = std::atan2(v_from.y, v_from.x);
	float angle_to = std::atan2(v_to.y, v_to.x);
	float delta = angle_to - angle_from;
	while (delta > MATH_PI) {
		delta -= 2.0f * MATH_PI;
	}
	while (delta < -MATH_PI) {
		delta += 2.0f * MATH_PI;
	}
	const float radius = (v_from.length() + v_to.length()) * 0.5f;
	result.reserve(static_cast<size_t>(p_segments + 1));
	for (int32_t index = 0; index <= p_segments; ++index) {
		const float t = static_cast<float>(index) / static_cast<float>(p_segments);
		const float angle = angle_from + delta * t;
		result.push_back(p_center + godot::Vector2(std::cos(angle) * radius, std::sin(angle) * radius));
	}
	return result;
}

bool read_solid(const godot::PackedByteArray &p_halo, int32_t p_side, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_side || p_y >= p_side) {
		return false;
	}
	const int32_t index = p_y * p_side + p_x;
	return index >= 0 && index < p_halo.size() && p_halo[index] != 0;
}

godot::Vector2 normalized_or(godot::Vector2 p_value, godot::Vector2 p_fallback) {
	const float length_sq = p_value.length_squared();
	if (length_sq <= 0.000001f) {
		return p_fallback;
	}
	return p_value / std::sqrt(length_sq);
}

godot::Vector2 sample_corner(int32_t p_grid_x, int32_t p_grid_y, int32_t p_tile_size_px) {
	const float tile = static_cast<float>(p_tile_size_px);
	return godot::Vector2(
		(static_cast<float>(p_grid_x) - 0.5f) * tile,
		(static_cast<float>(p_grid_y) - 0.5f) * tile
	);
}

float facade_side_for_outward(godot::Vector2 p_outward) {
	if (p_outward.y > 0.65f && std::abs(p_outward.x) < 0.45f) {
		return static_cast<float>(FACADE_SOUTH);
	}
	if (std::abs(p_outward.x) > 0.65f && std::abs(p_outward.y) < 0.45f) {
		return static_cast<float>(FACADE_SIDE);
	}
	return static_cast<float>(FACADE_DIAGONAL);
}

float facade_height_for_outward(godot::Vector2 p_outward, const RuntimeStyle &p_style) {
	const float south = std::max(0.0f, p_outward.y) * p_style.south_height_px;
	const float north = std::max(0.0f, -p_outward.y) * p_style.north_height_px;
	const float side = std::abs(p_outward.x) * p_style.side_height_px;
	return south + north + side;
}

float max_face_depth(const RuntimeStyle &p_style) {
	const float outline = p_style.outline_enabled ? p_style.outline_width_px : 0.0f;
	return std::max(1.0f, p_style.south_height_px + p_style.side_height_px + p_style.north_height_px + outline);
}

void append_vertex(
	godot::PackedVector2Array &r_vertices,
	godot::PackedFloat32Array &r_attributes,
	godot::Vector2 p_point,
	const VertexAttr &p_attr,
	float p_tile_size_px,
	float p_face_depth_norm
) {
	r_vertices.append(p_point);
	r_attributes.append(p_attr.edge_u);
	r_attributes.append(p_attr.edge_v);
	r_attributes.append(p_attr.signed_distance_px);
	r_attributes.append(p_attr.face_depth_px / std::max(1.0f, p_face_depth_norm));
	r_attributes.append(p_attr.facade_side);
	r_attributes.append(p_attr.zone);
	r_attributes.append(p_point.x / std::max(1.0f, p_tile_size_px));
	r_attributes.append(p_point.y / std::max(1.0f, p_tile_size_px));
}

void append_triangle_fan(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const std::vector<godot::Vector2> &p_points,
	const std::vector<VertexAttr> &p_attrs,
	float p_tile_size_px,
	float p_face_depth_norm
) {
	if (p_points.size() < 3 || p_points.size() != p_attrs.size()) {
		return;
	}
	const int32_t base = r_vertices.size();
	for (size_t index = 0; index < p_points.size(); ++index) {
		append_vertex(r_vertices, r_attributes, p_points[index], p_attrs[index], p_tile_size_px, p_face_depth_norm);
	}
	for (int32_t fan = 1; fan < static_cast<int32_t>(p_points.size()) - 1; ++fan) {
		r_indices.append(base);
		r_indices.append(base + fan);
		r_indices.append(base + fan + 1);
	}
}

VertexAttr top_attr(godot::Vector2 p_point, float p_signed_distance_px, float p_tile_size_px) {
	(void)p_point;
	(void)p_tile_size_px;
	return {
		0.0f,
		1.0f,
		p_signed_distance_px,
		0.0f,
		static_cast<float>(FACADE_SOUTH),
		static_cast<float>(ZONE_TOP),
	};
}

godot::Vector2 solid_center_for_case(
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl
) {
	godot::Vector2 center;
	float count = 0.0f;
	if ((p_case & 1) != 0) { center += p_tl; count += 1.0f; }
	if ((p_case & 2) != 0) { center += p_tr; count += 1.0f; }
	if ((p_case & 4) != 0) { center += p_br; count += 1.0f; }
	if ((p_case & 8) != 0) { center += p_bl; count += 1.0f; }
	return count > 0.0f ? center / count : (p_tl + p_br) * 0.5f;
}

struct ConvexChamferData {
	godot::Vector2 solid_corner;
	godot::Vector2 first_midpoint;
	godot::Vector2 second_midpoint;
	godot::Vector2 chamfer_start;
	godot::Vector2 chamfer_end;
	godot::Vector2 arc_center;
};

ConvexChamferData build_convex_chamfer_data(
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_corner_round_px
) {
	const godot::Vector2 top = (p_tl + p_tr) * 0.5f;
	const godot::Vector2 right = (p_tr + p_br) * 0.5f;
	const godot::Vector2 bottom = (p_bl + p_br) * 0.5f;
	const godot::Vector2 left = (p_tl + p_bl) * 0.5f;
	const float radius = std::max(0.0f, std::min(p_corner_round_px, p_tile_size_px * 0.5f));
	ConvexChamferData data;
	switch (p_case) {
		case 1:
			data.solid_corner = p_tl;
			data.first_midpoint = top;
			data.second_midpoint = left;
			data.chamfer_start = p_tl + godot::Vector2(radius, 0.0f);
			data.chamfer_end = p_tl + godot::Vector2(0.0f, radius);
			data.arc_center = p_tl + godot::Vector2(radius, radius);
			break;
		case 2:
			data.solid_corner = p_tr;
			data.first_midpoint = right;
			data.second_midpoint = top;
			data.chamfer_start = p_tr + godot::Vector2(0.0f, radius);
			data.chamfer_end = p_tr + godot::Vector2(-radius, 0.0f);
			data.arc_center = p_tr + godot::Vector2(-radius, radius);
			break;
		case 4:
			data.solid_corner = p_br;
			data.first_midpoint = bottom;
			data.second_midpoint = right;
			data.chamfer_start = p_br + godot::Vector2(-radius, 0.0f);
			data.chamfer_end = p_br + godot::Vector2(0.0f, -radius);
			data.arc_center = p_br + godot::Vector2(-radius, -radius);
			break;
		case 8:
			data.solid_corner = p_bl;
			data.first_midpoint = left;
			data.second_midpoint = bottom;
			data.chamfer_start = p_bl + godot::Vector2(0.0f, -radius);
			data.chamfer_end = p_bl + godot::Vector2(radius, 0.0f);
			data.arc_center = p_bl + godot::Vector2(radius, -radius);
			break;
		default:
			data.solid_corner = p_tl;
			data.first_midpoint = top;
			data.second_midpoint = left;
			data.chamfer_start = p_tl;
			data.chamfer_end = p_tl;
			data.arc_center = p_tl;
			break;
	}
	return data;
}

std::vector<godot::Vector2> build_convex_contour_polyline(
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_corner_round_px
) {
	const ConvexChamferData data = build_convex_chamfer_data(
		p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
	);
	std::vector<godot::Vector2> polyline;
	polyline.push_back(data.first_midpoint);
	if (data.first_midpoint.distance_squared_to(data.chamfer_start) > 0.01f) {
		polyline.push_back(data.chamfer_start);
	}
	const std::vector<godot::Vector2> arc = build_arc_points(
		data.arc_center, data.chamfer_start, data.chamfer_end, ARC_SEGMENTS_PER_QUARTER
	);
	for (size_t index = 1; index + 1 < arc.size(); ++index) {
		polyline.push_back(arc[index]);
	}
	if (data.chamfer_end.distance_squared_to(data.second_midpoint) > 0.01f) {
		polyline.push_back(data.chamfer_end);
	}
	polyline.push_back(data.second_midpoint);
	return polyline;
}

struct ConcaveFilletData {
	godot::Vector2 outside_corner;
	godot::Vector2 first_midpoint;
	godot::Vector2 second_midpoint;
	godot::Vector2 fillet_start;
	godot::Vector2 fillet_end;
};

ConcaveFilletData build_concave_fillet_data(
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_corner_round_px
) {
	const godot::Vector2 top = (p_tl + p_tr) * 0.5f;
	const godot::Vector2 right = (p_tr + p_br) * 0.5f;
	const godot::Vector2 bottom = (p_bl + p_br) * 0.5f;
	const godot::Vector2 left = (p_tl + p_bl) * 0.5f;
	const float radius = std::max(0.0f, std::min(p_corner_round_px, p_tile_size_px * 0.5f));
	ConcaveFilletData data;
	switch (p_case) {
		case 7:
			data.outside_corner = p_bl;
			data.first_midpoint = bottom;
			data.second_midpoint = left;
			data.fillet_start = p_bl + godot::Vector2(radius, 0.0f);
			data.fillet_end = p_bl + godot::Vector2(0.0f, -radius);
			break;
		case 11:
			data.outside_corner = p_br;
			data.first_midpoint = right;
			data.second_midpoint = bottom;
			data.fillet_start = p_br + godot::Vector2(0.0f, -radius);
			data.fillet_end = p_br + godot::Vector2(-radius, 0.0f);
			break;
		case 13:
			data.outside_corner = p_tr;
			data.first_midpoint = top;
			data.second_midpoint = right;
			data.fillet_start = p_tr + godot::Vector2(-radius, 0.0f);
			data.fillet_end = p_tr + godot::Vector2(0.0f, radius);
			break;
		case 14:
			data.outside_corner = p_tl;
			data.first_midpoint = left;
			data.second_midpoint = top;
			data.fillet_start = p_tl + godot::Vector2(0.0f, radius);
			data.fillet_end = p_tl + godot::Vector2(radius, 0.0f);
			break;
		default:
			data.outside_corner = p_tl;
			data.first_midpoint = top;
			data.second_midpoint = left;
			data.fillet_start = p_tl;
			data.fillet_end = p_tl;
			break;
	}
	return data;
}

std::vector<godot::Vector2> build_concave_contour_polyline(
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_corner_round_px
) {
	const ConcaveFilletData data = build_concave_fillet_data(
		p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
	);
	std::vector<godot::Vector2> polyline;
	polyline.push_back(data.first_midpoint);
	if (data.first_midpoint.distance_squared_to(data.fillet_start) > 0.01f) {
		polyline.push_back(data.fillet_start);
	}
	const std::vector<godot::Vector2> arc = build_arc_points(
		data.outside_corner, data.fillet_start, data.fillet_end, ARC_SEGMENTS_PER_QUARTER
	);
	for (size_t index = 1; index + 1 < arc.size(); ++index) {
		polyline.push_back(arc[index]);
	}
	if (data.fillet_end.distance_squared_to(data.second_midpoint) > 0.01f) {
		polyline.push_back(data.fillet_end);
	}
	polyline.push_back(data.second_midpoint);
	return polyline;
}

void emit_top_case(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_face_depth_norm,
	float p_corner_round_px
) {
	if (p_case == 0) {
		return;
	}
	const godot::Vector2 top = (p_tl + p_tr) * 0.5f;
	const godot::Vector2 right = (p_tr + p_br) * 0.5f;
	const godot::Vector2 bottom = (p_bl + p_br) * 0.5f;
	const godot::Vector2 left = (p_tl + p_bl) * 0.5f;
	const float inside_d = static_cast<float>(p_tile_size_px) * 0.5f;
	const float edge_d = 0.0f;
	auto a = [&](godot::Vector2 p, float d) { return top_attr(p, d, p_tile_size_px); };
	std::vector<godot::Vector2> pts;
	std::vector<VertexAttr> attrs;
	auto emit = [&](std::initializer_list<godot::Vector2> p_pts, std::initializer_list<float> p_d) {
		pts.assign(p_pts.begin(), p_pts.end());
		attrs.clear();
		auto d_it = p_d.begin();
		for (auto pt_it = p_pts.begin(); pt_it != p_pts.end() && d_it != p_d.end(); ++pt_it, ++d_it) {
			attrs.push_back(a(*pt_it, *d_it));
		}
		append_triangle_fan(r_vertices, r_indices, r_attributes, pts, attrs, p_tile_size_px, p_face_depth_norm);
	};
	auto emit_convex_chamfer = [&]() {
		const ConvexChamferData data = build_convex_chamfer_data(
			p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
		);
		const std::vector<godot::Vector2> polyline = build_convex_contour_polyline(
			p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
		);
		std::vector<godot::Vector2> fan_pts;
		std::vector<VertexAttr> fan_attrs;
		fan_pts.push_back(data.arc_center);
		fan_attrs.push_back(a(data.arc_center, inside_d));
		for (const godot::Vector2 &point : polyline) {
			fan_pts.push_back(point);
			fan_attrs.push_back(a(point, edge_d));
		}
		append_triangle_fan(r_vertices, r_indices, r_attributes, fan_pts, fan_attrs, p_tile_size_px, p_face_depth_norm);
	};
	auto emit_concave_fillet = [&](
		std::initializer_list<godot::Vector2> p_solid_corners,
		std::initializer_list<float> p_solid_distances
	) {
		const std::vector<godot::Vector2> polyline = build_concave_contour_polyline(
			p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
		);
		std::vector<godot::Vector2> fan_pts;
		std::vector<VertexAttr> fan_attrs;
		auto d_it = p_solid_distances.begin();
		for (auto pt_it = p_solid_corners.begin(); pt_it != p_solid_corners.end() && d_it != p_solid_distances.end(); ++pt_it, ++d_it) {
			fan_pts.push_back(*pt_it);
			fan_attrs.push_back(a(*pt_it, *d_it));
		}
		for (const godot::Vector2 &point : polyline) {
			fan_pts.push_back(point);
			fan_attrs.push_back(a(point, edge_d));
		}
		append_triangle_fan(r_vertices, r_indices, r_attributes, fan_pts, fan_attrs, p_tile_size_px, p_face_depth_norm);
	};
	switch (p_case) {
		case 1: case 2: case 4: case 8:
			emit_convex_chamfer();
			return;
		case 3: emit({ p_tl, p_tr, right, left }, { inside_d, inside_d, edge_d, edge_d }); return;
		case 5:
			emit({ p_tl, top, left }, { inside_d, edge_d, edge_d });
			emit({ p_br, bottom, right }, { inside_d, edge_d, edge_d });
			return;
		case 6: emit({ p_tr, p_br, bottom, top }, { inside_d, inside_d, edge_d, edge_d }); return;
		case 7:
			emit_concave_fillet({ p_tl, p_tr, p_br }, { inside_d, inside_d, inside_d });
			return;
		case 9: emit({ p_tl, top, bottom, p_bl }, { inside_d, edge_d, edge_d, inside_d }); return;
		case 10:
			emit({ p_tr, right, top }, { inside_d, edge_d, edge_d });
			emit({ p_bl, left, bottom }, { inside_d, edge_d, edge_d });
			return;
		case 11:
			emit_concave_fillet({ p_bl, p_tl, p_tr }, { inside_d, inside_d, inside_d });
			return;
		case 12: emit({ left, right, p_br, p_bl }, { edge_d, edge_d, inside_d, inside_d }); return;
		case 13:
			emit_concave_fillet({ p_br, p_bl, p_tl }, { inside_d, inside_d, inside_d });
			return;
		case 14:
			emit_concave_fillet({ p_tr, p_br, p_bl }, { inside_d, inside_d, inside_d });
			return;
		case 15: emit({ p_tl, p_tr, p_br, p_bl }, { inside_d, inside_d, inside_d, inside_d }); return;
		default: return;
	}
}

void emit_contour_segments_for_case(
	std::vector<ContourSegment> &r_segments,
	int32_t p_case,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl,
	float p_tile_size_px,
	float p_corner_round_px
) {
	if (p_case == 0 || p_case == 15) {
		return;
	}
	const godot::Vector2 top = (p_tl + p_tr) * 0.5f;
	const godot::Vector2 right = (p_tr + p_br) * 0.5f;
	const godot::Vector2 bottom = (p_bl + p_br) * 0.5f;
	const godot::Vector2 left = (p_tl + p_bl) * 0.5f;
	const godot::Vector2 solid_center = solid_center_for_case(p_case, p_tl, p_tr, p_br, p_bl);
	auto push = [&](godot::Vector2 p_a, godot::Vector2 p_b) {
		if (p_a.distance_squared_to(p_b) <= 0.001f) {
			return;
		}
		const godot::Vector2 mid = (p_a + p_b) * 0.5f;
		const godot::Vector2 tangent = normalized_or(p_b - p_a, godot::Vector2(1.0f, 0.0f));
		const godot::Vector2 fallback = godot::Vector2(tangent.y, -tangent.x);
		const godot::Vector2 outward = normalized_or(mid - solid_center, fallback);
		r_segments.push_back({ p_a, p_b, outward });
	};
	auto push_convex_chamfer = [&]() {
		const std::vector<godot::Vector2> polyline = build_convex_contour_polyline(
			p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
		);
		for (size_t index = 0; index + 1 < polyline.size(); ++index) {
			push(polyline[index], polyline[index + 1]);
		}
	};
	auto push_concave_fillet = [&]() {
		const std::vector<godot::Vector2> polyline = build_concave_contour_polyline(
			p_case, p_tl, p_tr, p_br, p_bl, p_tile_size_px, p_corner_round_px
		);
		for (size_t index = 0; index + 1 < polyline.size(); ++index) {
			push(polyline[index], polyline[index + 1]);
		}
	};
	switch (p_case) {
		case 1: case 2: case 4: case 8:
			push_convex_chamfer();
			return;
		case 7: case 11: case 13: case 14:
			push_concave_fillet();
			return;
		case 3: case 12: push(right, left); return;
		case 5:
			push(top, left);
			push(bottom, right);
			return;
		case 6: case 9: push(bottom, top); return;
		case 10:
			push(right, top);
			push(left, bottom);
			return;
		default: return;
	}
}

void emit_face_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	float p_height,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px,
	float p_face_depth_norm
) {
	if (p_height <= 0.001f) {
		return;
	}
	const godot::Vector2 drop(0.0f, p_height);
	const float facade_side = facade_side_for_outward(p_segment.outward);
	std::vector<godot::Vector2> pts = {
		p_segment.a,
		p_segment.b,
		p_segment.b + drop,
		p_segment.a + drop,
	};
	std::vector<VertexAttr> attrs = {
		{ p_edge_u_start, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_end, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_end, 1.0f, 0.0f, p_height, facade_side, static_cast<float>(ZONE_FACE) },
		{ p_edge_u_start, 1.0f, 0.0f, p_height, facade_side, static_cast<float>(ZONE_FACE) },
	};
	append_triangle_fan(r_vertices, r_indices, r_attributes, pts, attrs, p_tile_size_px, p_face_depth_norm);
}

void emit_rim_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	float p_rim_width,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px,
	float p_face_depth_norm
) {
	if (p_rim_width <= 0.001f) {
		return;
	}
	const godot::Vector2 inward = -p_segment.outward * p_rim_width;
	const float facade_side = facade_side_for_outward(p_segment.outward);
	std::vector<godot::Vector2> pts = {
		p_segment.a,
		p_segment.b,
		p_segment.b + inward,
		p_segment.a + inward,
	};
	std::vector<VertexAttr> attrs = {
		{ p_edge_u_start, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_end, 0.0f, 0.0f, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_end, 1.0f, p_rim_width, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
		{ p_edge_u_start, 1.0f, p_rim_width, 0.0f, facade_side, static_cast<float>(ZONE_RIM) },
	};
	append_triangle_fan(r_vertices, r_indices, r_attributes, pts, attrs, p_tile_size_px, p_face_depth_norm);
}

void emit_outline_quad(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	godot::PackedFloat32Array &r_attributes,
	const ContourSegment &p_segment,
	float p_height,
	float p_outline_width,
	float p_edge_u_start,
	float p_edge_u_end,
	float p_tile_size_px,
	float p_face_depth_norm
) {
	if (p_outline_width <= 0.001f || p_segment.outward.y <= 0.05f) {
		return;
	}
	const godot::Vector2 base_drop(0.0f, p_height);
	const godot::Vector2 outline_drop(0.0f, p_outline_width);
	const float facade_side = facade_side_for_outward(p_segment.outward);
	std::vector<godot::Vector2> pts = {
		p_segment.a + base_drop,
		p_segment.b + base_drop,
		p_segment.b + base_drop + outline_drop,
		p_segment.a + base_drop + outline_drop,
	};
	std::vector<VertexAttr> attrs = {
		{ p_edge_u_start, 0.0f, 0.0f, p_height, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_end, 0.0f, 0.0f, p_height, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_end, 1.0f, 0.0f, p_height + p_outline_width, facade_side, static_cast<float>(ZONE_OUTLINE) },
		{ p_edge_u_start, 1.0f, 0.0f, p_height + p_outline_width, facade_side, static_cast<float>(ZONE_OUTLINE) },
	};
	append_triangle_fan(r_vertices, r_indices, r_attributes, pts, attrs, p_tile_size_px, p_face_depth_norm);
}

godot::PackedVector2Array build_tile_collision_loop(
	int32_t p_tile_x,
	int32_t p_tile_y,
	int32_t p_tile_size_px,
	bool p_extend_south,
	float p_south_extension_px
) {
	const float tile = static_cast<float>(p_tile_size_px);
	const float x0 = static_cast<float>(p_tile_x) * tile;
	const float y0 = static_cast<float>(p_tile_y) * tile;
	const float x1 = x0 + tile;
	const float y1 = y0 + tile + (p_extend_south ? p_south_extension_px : 0.0f);
	godot::PackedVector2Array loop;
	loop.append(godot::Vector2(x0, y0));
	loop.append(godot::Vector2(x1, y0));
	loop.append(godot::Vector2(x1, y1));
	loop.append(godot::Vector2(x0, y1));
	return loop;
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
	result["face_depth_norm_px"] = DEFAULT_FACE_DEPTH_NORM;
	return result;
}

void append_case_mesh_debug(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	int32_t p_case_code,
	godot::Vector2 p_tl,
	godot::Vector2 p_tr,
	godot::Vector2 p_br,
	godot::Vector2 p_bl
) {
	if (p_case_code == 0) {
		return;
	}
	const godot::Vector2 top = (p_tl + p_tr) * 0.5f;
	const godot::Vector2 right = (p_tr + p_br) * 0.5f;
	const godot::Vector2 bottom = (p_bl + p_br) * 0.5f;
	const godot::Vector2 left = (p_tl + p_bl) * 0.5f;
	auto fan = [&](std::initializer_list<godot::Vector2> p_pts) {
		if (p_pts.size() < 3) {
			return;
		}
		const int32_t base = r_vertices.size();
		for (const godot::Vector2 &point : p_pts) {
			r_vertices.append(point);
		}
		for (int32_t i = 1; i < static_cast<int32_t>(p_pts.size()) - 1; ++i) {
			r_indices.append(base);
			r_indices.append(base + i);
			r_indices.append(base + i + 1);
		}
	};
	switch (p_case_code) {
		case 1: fan({ p_tl, top, left }); return;
		case 2: fan({ p_tr, right, top }); return;
		case 3: fan({ p_tl, p_tr, right, left }); return;
		case 4: fan({ p_br, bottom, right }); return;
		case 5: fan({ p_tl, top, left }); fan({ p_br, bottom, right }); return;
		case 6: fan({ p_tr, p_br, bottom, top }); return;
		case 7: fan({ p_tl, p_tr, p_br, bottom, left }); return;
		case 8: fan({ p_bl, left, bottom }); return;
		case 9: fan({ p_tl, top, bottom, p_bl }); return;
		case 10: fan({ p_tr, right, top }); fan({ p_bl, left, bottom }); return;
		case 11: fan({ p_tl, p_tr, right, bottom, p_bl }); return;
		case 12: fan({ left, right, p_br, p_bl }); return;
		case 13: fan({ p_tl, top, right, p_br, p_bl }); return;
		case 14: fan({ top, p_tr, p_br, p_bl, left }); return;
		case 15: fan({ p_tl, p_tr, p_br, p_bl }); return;
		default: return;
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
			append_case_mesh_debug(
				vertices,
				indices,
				case_code,
				sample_corner(x, y, p_tile_size_px),
				sample_corner(x + 1, y, p_tile_size_px),
				sample_corner(x + 1, y + 1, p_tile_size_px),
				sample_corner(x, y + 1, p_tile_size_px)
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
	const float face_depth_norm = max_face_depth(style);
	const float tile_size_px = static_cast<float>(p_tile_size_px);

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
	int32_t seam_touch_mask = 0;
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			if (!read_solid(p_solid_halo, halo_side, x + 1, y + 1)) {
				continue;
			}
			solid_local[static_cast<size_t>(y * p_chunk_size + x)] = 1U;
			++solid_sample_count;
			if (x == 0) seam_touch_mask |= SEAM_WEST;
			if (x == p_chunk_size - 1) seam_touch_mask |= SEAM_EAST;
			if (y == 0) seam_touch_mask |= SEAM_NORTH;
			if (y == p_chunk_size - 1) seam_touch_mask |= SEAM_SOUTH;
		}
	}

	std::vector<ContourSegment> contour_segments;
	int32_t boundary_edge_count = 0;
	for (int32_t y = 0; y < halo_side - 1; ++y) {
		for (int32_t x = 0; x < halo_side - 1; ++x) {
			const bool tl = read_solid(p_solid_halo, halo_side, x, y);
			const bool tr = read_solid(p_solid_halo, halo_side, x + 1, y);
			const bool br = read_solid(p_solid_halo, halo_side, x + 1, y + 1);
			const bool bl = read_solid(p_solid_halo, halo_side, x, y + 1);
			const int32_t case_code =
					(tl ? 1 : 0) | (tr ? 2 : 0) | (br ? 4 : 0) | (bl ? 8 : 0);
			if (case_code == 0) {
				continue;
			}
			const godot::Vector2 c_tl = sample_corner(x, y, p_tile_size_px);
			const godot::Vector2 c_tr = sample_corner(x + 1, y, p_tile_size_px);
			const godot::Vector2 c_br = sample_corner(x + 1, y + 1, p_tile_size_px);
			const godot::Vector2 c_bl = sample_corner(x, y + 1, p_tile_size_px);
			emit_top_case(
				top_vertices,
				top_indices,
				top_attributes,
				case_code,
				c_tl, c_tr, c_br, c_bl,
				tile_size_px,
				face_depth_norm,
				style.corner_round_px
			);
			if (case_code != 15) {
				++boundary_edge_count;
				emit_contour_segments_for_case(
					contour_segments,
					case_code,
					c_tl, c_tr, c_br, c_bl,
					tile_size_px,
					style.corner_round_px
				);
			}
		}
	}

	float edge_u_cursor = 0.0f;
	for (const ContourSegment &segment : contour_segments) {
		const float edge_u_start = edge_u_cursor / std::max(1.0f, tile_size_px);
		const float segment_length = segment.a.distance_to(segment.b);
		edge_u_cursor += segment_length;
		const float edge_u_end = edge_u_cursor / std::max(1.0f, tile_size_px);
		const float height = facade_height_for_outward(segment.outward, style);

		emit_rim_quad(
			rim_vertices, rim_indices, rim_attributes,
			segment, style.rim_width_px,
			edge_u_start, edge_u_end,
			tile_size_px, face_depth_norm
		);
		emit_face_quad(
			face_vertices, face_indices, face_attributes,
			segment, height,
			edge_u_start, edge_u_end,
			tile_size_px, face_depth_norm
		);
		if (style.outline_enabled) {
			emit_outline_quad(
				outline_vertices, outline_indices, outline_attributes,
				segment, height, style.outline_width_px,
				edge_u_start, edge_u_end,
				tile_size_px, face_depth_norm
			);
		}
	}

	godot::Array collision_loops;
	godot::Array collision_aabbs;
	const float south_extension = style.south_height_px + (style.outline_enabled ? style.outline_width_px : 0.0f);
	for (int32_t y = 0; y < p_chunk_size; ++y) {
		for (int32_t x = 0; x < p_chunk_size; ++x) {
			if (solid_local[static_cast<size_t>(y * p_chunk_size + x)] == 0U) {
				continue;
			}
			const bool south_neighbour = read_solid(p_solid_halo, halo_side, x + 1, y + 2);
			const bool extend_south = !south_neighbour;
			godot::PackedVector2Array loop = build_tile_collision_loop(
				x, y, p_tile_size_px, extend_south, south_extension
			);
			godot::Rect2 aabb = loop_aabb(loop);
			collision_loops.append(loop);
			collision_aabbs.append(aabb);
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
	result["face_depth_norm_px"] = face_depth_norm;
	return result;
}

} // namespace mountain_contour
