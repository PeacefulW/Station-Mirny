#include "rock_marching_squares.h"

#include <cstdint>
#include <deque>
#include <unordered_map>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace {

enum class Edge : int32_t {
	Top = 0,
	Right = 1,
	Bottom = 2,
	Left = 3,
};

struct PointKey {
	int32_t x = 0;
	int32_t y = 0;

	bool operator==(const PointKey &p_other) const {
		return x == p_other.x && y == p_other.y;
	}
};

struct Segment {
	PointKey a;
	PointKey b;
};

struct EdgePair {
	Edge a = Edge::Top;
	Edge b = Edge::Top;
};

struct CaseSegments {
	int32_t count = 0;
	EdgePair pairs[2];
};

constexpr CaseSegments CASE_SEGMENTS[16] = {
	{ 0, {} },
	{ 1, { { Edge::Left, Edge::Top } } },
	{ 1, { { Edge::Top, Edge::Right } } },
	{ 1, { { Edge::Left, Edge::Right } } },
	{ 1, { { Edge::Right, Edge::Bottom } } },
	{ 2, { { Edge::Left, Edge::Top }, { Edge::Right, Edge::Bottom } } },
	{ 1, { { Edge::Top, Edge::Bottom } } },
	{ 1, { { Edge::Left, Edge::Bottom } } },
	{ 1, { { Edge::Bottom, Edge::Left } } },
	{ 1, { { Edge::Top, Edge::Bottom } } },
	{ 2, { { Edge::Top, Edge::Right }, { Edge::Bottom, Edge::Left } } },
	{ 1, { { Edge::Right, Edge::Bottom } } },
	{ 1, { { Edge::Right, Edge::Left } } },
	{ 1, { { Edge::Top, Edge::Right } } },
	{ 1, { { Edge::Left, Edge::Top } } },
	{ 0, {} },
};

PointKey make_edge_point(int32_t p_x, int32_t p_y, Edge p_edge) {
	switch (p_edge) {
		case Edge::Top:
			return { p_x * 2 + 1, p_y * 2 };
		case Edge::Right:
			return { (p_x + 1) * 2, p_y * 2 + 1 };
		case Edge::Bottom:
			return { p_x * 2 + 1, (p_y + 1) * 2 };
		case Edge::Left:
		default:
			return { p_x * 2, p_y * 2 + 1 };
	}
}

uint64_t encode_point(PointKey p_point) {
	return (static_cast<uint64_t>(static_cast<uint32_t>(p_point.x)) << 32U) |
			static_cast<uint32_t>(p_point.y);
}

Vector2 to_vector2(PointKey p_point) {
	return Vector2(
		static_cast<double>(p_point.x) * 0.5,
		static_cast<double>(p_point.y) * 0.5
	);
}

bool is_rock_at(
	const PackedInt32Array &p_terrain_ids,
	int64_t p_width,
	int64_t p_x,
	int64_t p_y,
	int64_t p_rock_terrain_id
) {
	const int64_t index = p_y * p_width + p_x;
	return p_terrain_ids[static_cast<int32_t>(index)] == p_rock_terrain_id;
}

void add_segment(
	std::vector<Segment> &r_segments,
	std::unordered_map<uint64_t, std::vector<int32_t>> &r_adjacency,
	PointKey p_a,
	PointKey p_b
) {
	if (p_a == p_b) {
		return;
	}
	const int32_t segment_index = static_cast<int32_t>(r_segments.size());
	r_segments.push_back({ p_a, p_b });
	r_adjacency[encode_point(p_a)].push_back(segment_index);
	r_adjacency[encode_point(p_b)].push_back(segment_index);
}

int32_t find_next_segment(
	PointKey p_endpoint,
	const std::vector<Segment> &p_segments,
	const std::vector<bool> &p_used,
	const std::unordered_map<uint64_t, std::vector<int32_t>> &p_adjacency
) {
	const auto found = p_adjacency.find(encode_point(p_endpoint));
	if (found == p_adjacency.end()) {
		return -1;
	}
	for (const int32_t segment_index : found->second) {
		if (segment_index < 0 ||
				segment_index >= static_cast<int32_t>(p_segments.size()) ||
				p_used[static_cast<size_t>(segment_index)]) {
			continue;
		}
		return segment_index;
	}
	return -1;
}

PointKey other_endpoint(const Segment &p_segment, PointKey p_endpoint) {
	return p_segment.a == p_endpoint ? p_segment.b : p_segment.a;
}

PackedVector2Array make_polyline_from_points(const std::deque<PointKey> &p_points) {
	PackedVector2Array polyline;
	for (const PointKey &point : p_points) {
		polyline.append(to_vector2(point));
	}
	return polyline;
}

} // namespace

void RockMarchingSquares::_bind_methods() {
	ClassDB::bind_method(
		D_METHOD("extract_polylines", "terrain_ids", "width", "height", "rock_terrain_id"),
		&RockMarchingSquares::extract_polylines
	);
}

Array RockMarchingSquares::extract_polylines(
	const PackedInt32Array &p_terrain_ids,
	int64_t p_width,
	int64_t p_height,
	int64_t p_rock_terrain_id
) const {
	Array polylines;
	ERR_FAIL_COND_V_MSG(
		p_width < 0 || p_height < 0,
		polylines,
		"RockMarchingSquares.extract_polylines received a negative grid dimension."
	);
	const int64_t expected_size = p_width * p_height;
	ERR_FAIL_COND_V_MSG(
		expected_size != p_terrain_ids.size(),
		polylines,
		"RockMarchingSquares.extract_polylines received a terrain id count that does not match width * height."
	);
	if (p_width < 2 || p_height < 2) {
		return polylines;
	}

	std::vector<Segment> segments;
	segments.reserve(static_cast<size_t>((p_width - 1) * (p_height - 1)));
	std::unordered_map<uint64_t, std::vector<int32_t>> adjacency;

	for (int64_t y = 0; y < p_height - 1; ++y) {
		for (int64_t x = 0; x < p_width - 1; ++x) {
			int32_t case_index = 0;
			if (is_rock_at(p_terrain_ids, p_width, x, y, p_rock_terrain_id)) {
				case_index |= 1;
			}
			if (is_rock_at(p_terrain_ids, p_width, x + 1, y, p_rock_terrain_id)) {
				case_index |= 2;
			}
			if (is_rock_at(p_terrain_ids, p_width, x + 1, y + 1, p_rock_terrain_id)) {
				case_index |= 4;
			}
			if (is_rock_at(p_terrain_ids, p_width, x, y + 1, p_rock_terrain_id)) {
				case_index |= 8;
			}

			const CaseSegments &case_segments = CASE_SEGMENTS[case_index];
			for (int32_t segment_index = 0; segment_index < case_segments.count; ++segment_index) {
				const EdgePair &edge_pair = case_segments.pairs[segment_index];
				add_segment(
					segments,
					adjacency,
					make_edge_point(static_cast<int32_t>(x), static_cast<int32_t>(y), edge_pair.a),
					make_edge_point(static_cast<int32_t>(x), static_cast<int32_t>(y), edge_pair.b)
				);
			}
		}
	}

	std::vector<bool> used;
	used.resize(segments.size(), false);
	for (int32_t seed_index = 0; seed_index < static_cast<int32_t>(segments.size()); ++seed_index) {
		if (used[static_cast<size_t>(seed_index)]) {
			continue;
		}

		std::deque<PointKey> points;
		const Segment &seed = segments[static_cast<size_t>(seed_index)];
		points.push_back(seed.a);
		points.push_back(seed.b);
		used[static_cast<size_t>(seed_index)] = true;

		bool extended = true;
		while (extended) {
			extended = false;
			const int32_t back_segment_index = find_next_segment(points.back(), segments, used, adjacency);
			if (back_segment_index >= 0) {
				const Segment &segment = segments[static_cast<size_t>(back_segment_index)];
				points.push_back(other_endpoint(segment, points.back()));
				used[static_cast<size_t>(back_segment_index)] = true;
				extended = true;
				continue;
			}

			const int32_t front_segment_index = find_next_segment(points.front(), segments, used, adjacency);
			if (front_segment_index >= 0) {
				const Segment &segment = segments[static_cast<size_t>(front_segment_index)];
				points.push_front(other_endpoint(segment, points.front()));
				used[static_cast<size_t>(front_segment_index)] = true;
				extended = true;
			}
		}

		if (points.size() >= 2) {
			polylines.append(make_polyline_from_points(points));
		}
	}

	return polylines;
}
