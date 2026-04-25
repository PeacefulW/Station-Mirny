#include "lake_footprint.h"
#include "world_utils.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include <godot_cpp/variant/vector2.hpp>

using world_utils::clamp_value;
using world_utils::splitmix64;

namespace lake_footprint {
namespace {

constexpr int32_t VERTEX_COUNT = 16;
constexpr double TWO_PI = 6.28318530717958647692;

double closest_wrapped_x(double p_x, double p_reference_x, int64_t p_width_tiles) {
	if (p_width_tiles <= 0) {
		return p_x;
	}
	const double width = static_cast<double>(p_width_tiles);
	return p_x - std::round((p_x - p_reference_x) / width) * width;
}

double vertex_scale(const LakeShape &p_shape, int32_t p_index) {
	const uint64_t noise = splitmix64(
		p_shape.shape_signature ^
		static_cast<uint64_t>(p_index) * 0x9e3779b185ebca87ULL
	);
	return 0.72 + (static_cast<double>(noise & 0xffffULL) / 65535.0) * 0.56;
}

double vertex_radius(const LakeShape &p_shape, int32_t p_index) {
	return static_cast<double>(p_shape.shallow_radius_tiles) * vertex_scale(p_shape, p_index);
}

} // namespace

LakeShape make_shape(
	double p_center_x_tiles,
	double p_center_y_tiles,
	float p_flow_accumulation,
	float p_valley,
	uint64_t p_shape_signature,
	float p_lake_radius_scale
) {
	const float flow = clamp_value(p_flow_accumulation, 0.0f, 1.0f);
	const float valley = clamp_value(p_valley, 0.0f, 1.0f);
	const float base_radius = clamp_value(48.0f + flow * 56.0f + valley * 24.0f, 48.0f, 144.0f);
	LakeShape shape;
	shape.center_x_tiles = p_center_x_tiles;
	shape.center_y_tiles = p_center_y_tiles;
	shape.shallow_radius_tiles = base_radius * p_lake_radius_scale;
	shape.deep_radius_tiles = shape.shallow_radius_tiles * (0.45f + valley * 0.20f);
	shape.deep_radius_tiles = clamp_value(
		shape.deep_radius_tiles,
		std::max(8.0f, shape.shallow_radius_tiles * 0.20f),
		shape.shallow_radius_tiles * 0.85f
	);
	shape.shape_signature = p_shape_signature;
	return shape;
}

uint8_t classify_tile(const LakeShape &p_shape, double p_world_x, double p_world_y, int64_t p_width_tiles) {
	if (p_shape.shallow_radius_tiles <= 0.0f) {
		return CLASS_NONE;
	}
	const double sample_x = closest_wrapped_x(p_world_x, p_shape.center_x_tiles, p_width_tiles);
	const double dx = sample_x - p_shape.center_x_tiles;
	const double dy = p_world_y - p_shape.center_y_tiles;
	const double distance = std::sqrt(dx * dx + dy * dy);
	if (distance <= std::numeric_limits<double>::epsilon()) {
		return CLASS_DEEP;
	}

	double bearing = std::atan2(dy, dx);
	if (bearing < 0.0) {
		bearing += TWO_PI;
	}
	const double segment = TWO_PI / static_cast<double>(VERTEX_COUNT);
	const int32_t vertex_index = std::min(
		VERTEX_COUNT - 1,
		static_cast<int32_t>(std::floor(bearing / segment))
	);
	const int32_t next_index = (vertex_index + 1) % VERTEX_COUNT;
	const double t = (bearing - static_cast<double>(vertex_index) * segment) / segment;
	const double interpolated_radius = vertex_radius(p_shape, vertex_index) +
			(vertex_radius(p_shape, next_index) - vertex_radius(p_shape, vertex_index)) * t;
	const double deep_factor = static_cast<double>(p_shape.deep_radius_tiles) /
			std::max(0.0001, static_cast<double>(p_shape.shallow_radius_tiles));
	if (distance > interpolated_radius) {
		return CLASS_NONE;
	}
	return distance > interpolated_radius * deep_factor ? CLASS_SHALLOW : CLASS_DEEP;
}

godot::PackedVector2Array build_polygon(const LakeShape &p_shape, int64_t p_width_tiles) {
	godot::PackedVector2Array polygon;
	polygon.resize(VERTEX_COUNT);
	for (int32_t index = 0; index < VERTEX_COUNT; ++index) {
		const double angle = (TWO_PI * static_cast<double>(index)) / static_cast<double>(VERTEX_COUNT);
		const double radius = vertex_radius(p_shape, index);
		const double vertex_x = closest_wrapped_x(
			p_shape.center_x_tiles + std::cos(angle) * radius,
			p_shape.center_x_tiles,
			p_width_tiles
		);
		polygon.set(
			index,
			godot::Vector2(
				static_cast<float>(vertex_x),
				static_cast<float>(p_shape.center_y_tiles + std::sin(angle) * radius)
			)
		);
	}
	return polygon;
}

} // namespace lake_footprint
