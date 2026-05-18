#include "terrain_visual_solver.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace {

constexpr int32_t PACKET_SCHEMA_VERSION = 1;
constexpr int32_t SOLVER_VERSION = 2;

constexpr uint8_t ZONE_EMPTY = 0;
constexpr uint8_t ZONE_TOP = 1;
constexpr uint8_t ZONE_EDGE = 2;
constexpr uint8_t ZONE_FACE = 3;
constexpr uint8_t ZONE_BACK = 4;

struct RecipePayload {
	StringName recipe_id = StringName();
	StringName surface_kind = StringName("rock");
	int32_t tile_size_px = 64;
	double rim_width_px = 6.0;
	double south_height_px = 64.0;
	double north_height_px = 0.0;
	double side_height_px = 0.0;
	double face_power = 1.0;
	double back_drop = 0.8;
	double crown_bevel_px = 0.0;
	double outer_corner_radius_px = 0.0;
	double inner_corner_radius_px = 0.0;
	double corner_round_px = 0.0;
	double diagonal_smooth_px = 0.0;
	double contour_relax = 0.0;
	double contour_warp_px = 0.0;
	double corner_variation = 0.0;
	double geometry_variance = 0.0;
	int32_t shape_supersampling = 1;
	double edge_debris = 0.0;
	double edge_color_strength = 0.0;
	bool contact_outline_enabled = false;
	double contact_outline_width_px = 0.0;
	Color contact_outline_color = Color(0.05, 0.045, 0.04, 1.0);
	double normal_strength = 2.0;
	double normal_detail_strength = 0.0;
	double height_to_normal_blur_radius_px = 0.0;
	bool bake_height_shading_for_reference = false;
	int64_t world_wrap_width_tiles = 0;
};

struct MapSdf {
	int64_t width = 0;
	int64_t height = 0;
	std::vector<double> values;

	double value_at(int64_t p_x, int64_t p_y) const;
	double value_at_clamped(int64_t p_x, int64_t p_y) const;
	double sample(double p_cell_x, double p_cell_y) const;
	double sample_clamped(double p_cell_x, double p_cell_y) const;
	Vector2 gradient(double p_cell_x, double p_cell_y, double p_step) const;
};

struct NearestBoundary {
	double distance_px = std::numeric_limits<double>::infinity();
	double normal_x = 0.0;
	double normal_y = 1.0;
};

struct OrganicSample {
	bool inside = false;
	uint8_t zone = ZONE_EMPTY;
	NearestBoundary boundary;
	double signed_distance_px = 0.0;
	double height = 0.0;
};

struct ShapeFieldSample {
	double value = 0.0;
	Vector2 gradient;
};

double clamp01(double p_value) {
	return std::clamp(p_value, 0.0, 1.0);
}

int32_t checked_pixel_size(int64_t p_tiles, int32_t p_tile_size_px) {
	return static_cast<int32_t>(p_tiles * static_cast<int64_t>(p_tile_size_px));
}

bool is_solid_tile(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	int64_t p_x,
	int64_t p_y
) {
	if (p_x < 0 || p_y < 0 || p_x >= p_width_tiles || p_y >= p_height_tiles) {
		return false;
	}
	const int64_t index = p_y * p_width_tiles + p_x;
	return p_solid_mask[static_cast<int32_t>(index)] != 0;
}

StringName get_string_name(
	const Dictionary &p_payload,
	const char *p_key,
	const StringName &p_fallback
) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::STRING_NAME) {
		return static_cast<StringName>(value);
	}
	if (value.get_type() == Variant::STRING) {
		return StringName(static_cast<String>(value));
	}
	return p_fallback;
}

int32_t get_int(const Dictionary &p_payload, const char *p_key, int32_t p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
		return static_cast<int32_t>(static_cast<int64_t>(value));
	}
	return p_fallback;
}

double get_double(const Dictionary &p_payload, const char *p_key, double p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
		return static_cast<double>(value);
	}
	return p_fallback;
}

bool get_bool(const Dictionary &p_payload, const char *p_key, bool p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::BOOL) {
		return static_cast<bool>(value);
	}
	return p_fallback;
}

Color get_color(const Dictionary &p_payload, const char *p_key, const Color &p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::COLOR) {
		return static_cast<Color>(value);
	}
	return p_fallback;
}

RecipePayload unpack_recipe_payload(const Dictionary &p_payload) {
	RecipePayload recipe;
	recipe.recipe_id = get_string_name(p_payload, "recipe_id", StringName());
	recipe.surface_kind = get_string_name(p_payload, "surface_kind", StringName("rock"));
	recipe.tile_size_px = std::clamp(get_int(p_payload, "tile_size_px", 64), 1, 4096);
	recipe.rim_width_px = std::max(0.0, get_double(p_payload, "rim_width_px", 6.0));
	recipe.south_height_px = std::max(0.0, get_double(p_payload, "south_height_px", 64.0));
	recipe.north_height_px = std::max(0.0, get_double(p_payload, "north_height_px", 0.0));
	recipe.side_height_px = std::max(0.0, get_double(p_payload, "side_height_px", 0.0));
	recipe.face_power = std::clamp(get_double(p_payload, "face_power", 1.0), 0.1, 8.0);
	recipe.back_drop = std::clamp(get_double(p_payload, "back_drop", 0.8), 0.0, 1.0);
	recipe.crown_bevel_px = std::max(0.0, get_double(p_payload, "crown_bevel_px", 0.0));
	recipe.outer_corner_radius_px =
			std::max(0.0, get_double(p_payload, "outer_corner_radius_px", 0.0));
	recipe.inner_corner_radius_px =
			std::max(0.0, get_double(p_payload, "inner_corner_radius_px", 0.0));
	recipe.corner_round_px = std::max(0.0, get_double(p_payload, "corner_round_px", 0.0));
	recipe.diagonal_smooth_px = std::max(0.0, get_double(p_payload, "diagonal_smooth_px", 0.0));
	recipe.contour_relax = std::clamp(get_double(p_payload, "contour_relax", 0.0), 0.0, 1.0);
	recipe.contour_warp_px = std::max(0.0, get_double(p_payload, "contour_warp_px", 0.0));
	recipe.corner_variation = std::clamp(get_double(p_payload, "corner_variation", 0.0), 0.0, 1.0);
	recipe.geometry_variance = std::clamp(get_double(p_payload, "geometry_variance", 0.0), 0.0, 1.0);
	recipe.shape_supersampling = std::clamp(get_int(p_payload, "shape_supersampling", 1), 1, 8);
	recipe.edge_debris = std::clamp(get_double(p_payload, "edge_debris", 0.0), 0.0, 1.0);
	recipe.edge_color_strength =
			std::clamp(get_double(p_payload, "edge_color_strength", 0.0), 0.0, 1.0);
	recipe.contact_outline_enabled = get_bool(p_payload, "contact_outline_enabled", false);
	recipe.contact_outline_width_px =
			std::max(0.0, get_double(p_payload, "contact_outline_width_px", 0.0));
	recipe.contact_outline_color = get_color(
		p_payload,
		"contact_outline_color",
		Color(0.05, 0.045, 0.04, 1.0)
	);
	recipe.normal_strength = std::max(0.0, get_double(p_payload, "normal_strength", 2.0));
	recipe.normal_detail_strength =
			std::max(0.0, get_double(p_payload, "normal_detail_strength", 0.0));
	recipe.height_to_normal_blur_radius_px =
			std::max(0.0, get_double(p_payload, "height_to_normal_blur_radius_px", 0.0));
	recipe.bake_height_shading_for_reference =
			get_bool(p_payload, "bake_height_shading_for_reference", false);
	recipe.world_wrap_width_tiles =
			std::max<int64_t>(0, static_cast<int64_t>(get_int(p_payload, "world_wrap_width_tiles", 0)));
	return recipe;
}

constexpr double INF_DISTANCE_SQ = 1.0e20;

double lerp(double p_a, double p_b, double p_t) {
	return p_a + (p_b - p_a) * p_t;
}

double fade(double p_t) {
	return p_t * p_t * (3.0 - 2.0 * p_t);
}

double MapSdf::value_at(int64_t p_x, int64_t p_y) const {
	if (width <= 0 || height <= 0 || values.empty()) {
		return 0.0;
	}
	if (p_x >= 0 && p_y >= 0 && p_x < width && p_y < height) {
		return values[static_cast<size_t>(p_y * width + p_x)];
	}

	const int64_t clamped_x = std::clamp<int64_t>(p_x, 0, width - 1);
	const int64_t clamped_y = std::clamp<int64_t>(p_y, 0, height - 1);
	const double edge_value = values[static_cast<size_t>(clamped_y * width + clamped_x)];
	const int64_t dx = p_x < 0 ? -p_x : (p_x >= width ? p_x - width + 1 : 0);
	const int64_t dy = p_y < 0 ? -p_y : (p_y >= height ? p_y - height + 1 : 0);
	return edge_value - std::sqrt(static_cast<double>(dx * dx + dy * dy));
}

double MapSdf::value_at_clamped(int64_t p_x, int64_t p_y) const {
	if (width <= 0 || height <= 0 || values.empty()) {
		return 0.0;
	}
	const int64_t clamped_x = std::clamp<int64_t>(p_x, 0, width - 1);
	const int64_t clamped_y = std::clamp<int64_t>(p_y, 0, height - 1);
	return values[static_cast<size_t>(clamped_y * width + clamped_x)];
}

double MapSdf::sample(double p_cell_x, double p_cell_y) const {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_cell_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_cell_y));
	const double tx = p_cell_x - static_cast<double>(x0);
	const double ty = p_cell_y - static_cast<double>(y0);

	const double nw = value_at(x0, y0);
	const double ne = value_at(x0 + 1, y0);
	const double sw = value_at(x0, y0 + 1);
	const double se = value_at(x0 + 1, y0 + 1);
	return lerp(lerp(nw, ne, tx), lerp(sw, se, tx), ty);
}

double MapSdf::sample_clamped(double p_cell_x, double p_cell_y) const {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_cell_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_cell_y));
	const double tx = p_cell_x - static_cast<double>(x0);
	const double ty = p_cell_y - static_cast<double>(y0);

	const double nw = value_at_clamped(x0, y0);
	const double ne = value_at_clamped(x0 + 1, y0);
	const double sw = value_at_clamped(x0, y0 + 1);
	const double se = value_at_clamped(x0 + 1, y0 + 1);
	return lerp(lerp(nw, ne, tx), lerp(sw, se, tx), ty);
}

Vector2 MapSdf::gradient(double p_cell_x, double p_cell_y, double p_step) const {
	const double step = std::max(p_step, 0.0001);
	const double dx = (
		sample(p_cell_x + step, p_cell_y) -
		sample(p_cell_x - step, p_cell_y)
	) / (step * 2.0);
	const double dy = (
		sample(p_cell_x, p_cell_y + step) -
		sample(p_cell_x, p_cell_y - step)
	) / (step * 2.0);
	return Vector2(static_cast<real_t>(dx), static_cast<real_t>(dy));
}

void distance_transform_1d(
	const std::vector<double> &p_features,
	std::vector<double> &r_distances
) {
	const auto first_feature = std::find_if(
		p_features.begin(),
		p_features.end(),
		[](double p_value) { return p_value < INF_DISTANCE_SQ * 0.5; }
	);
	if (first_feature == p_features.end()) {
		std::fill(r_distances.begin(), r_distances.end(), INF_DISTANCE_SQ);
		return;
	}

	const size_t count = p_features.size();
	std::vector<size_t> locations(count, 0);
	std::vector<double> boundaries(count + 1, 0.0);
	size_t active = 0;
	locations[0] = static_cast<size_t>(std::distance(p_features.begin(), first_feature));
	boundaries[0] = -std::numeric_limits<double>::infinity();
	boundaries[1] = std::numeric_limits<double>::infinity();

	auto intersection = [&](size_t p_candidate, size_t p_active) -> double {
		const double candidate = static_cast<double>(p_candidate);
		const double active_location = static_cast<double>(p_active);
		const double numerator = p_features[p_candidate] + candidate * candidate -
				p_features[p_active] - active_location * active_location;
		return numerator / (2.0 * candidate - 2.0 * active_location);
	};

	for (size_t candidate = locations[0] + 1; candidate < count; ++candidate) {
		if (p_features[candidate] >= INF_DISTANCE_SQ * 0.5) {
			continue;
		}

		double hit = intersection(candidate, locations[active]);
		while (hit <= boundaries[active]) {
			if (active == 0) {
				break;
			}
			--active;
			hit = intersection(candidate, locations[active]);
		}
		if (hit <= boundaries[active]) {
			active = 0;
		} else {
			++active;
		}
		locations[active] = candidate;
		boundaries[active] = hit;
		boundaries[active + 1] = std::numeric_limits<double>::infinity();
	}

	active = 0;
	for (size_t query = 0; query < count; ++query) {
		while (boundaries[active + 1] < static_cast<double>(query)) {
			++active;
		}
		const double feature = static_cast<double>(locations[active]);
		const double offset = static_cast<double>(query) - feature;
		r_distances[query] = offset * offset + p_features[locations[active]];
	}
}

template <typename IsFeature>
std::vector<double> squared_distance_to_features(
	int64_t p_width,
	int64_t p_height,
	IsFeature p_is_feature
) {
	std::vector<double> grid(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	for (int64_t y = 0; y < p_height; ++y) {
		for (int64_t x = 0; x < p_width; ++x) {
			if (p_is_feature(x, y)) {
				grid[static_cast<size_t>(y * p_width + x)] = 0.0;
			}
		}
	}

	std::vector<double> row_pass(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	const int64_t max_axis = std::max<int64_t>(std::max(p_width, p_height), 1);
	std::vector<double> line(static_cast<size_t>(max_axis), INF_DISTANCE_SQ);
	std::vector<double> transformed(static_cast<size_t>(max_axis), INF_DISTANCE_SQ);

	for (int64_t y = 0; y < p_height; ++y) {
		const size_t start = static_cast<size_t>(y * p_width);
		std::copy(grid.begin() + start, grid.begin() + start + p_width, line.begin());
		distance_transform_1d(
			std::vector<double>(line.begin(), line.begin() + p_width),
			transformed
		);
		std::copy(transformed.begin(), transformed.begin() + p_width, row_pass.begin() + start);
	}

	std::vector<double> distances(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	for (int64_t x = 0; x < p_width; ++x) {
		for (int64_t y = 0; y < p_height; ++y) {
			line[static_cast<size_t>(y)] = row_pass[static_cast<size_t>(y * p_width + x)];
		}
		distance_transform_1d(
			std::vector<double>(line.begin(), line.begin() + p_height),
			transformed
		);
		for (int64_t y = 0; y < p_height; ++y) {
			distances[static_cast<size_t>(y * p_width + x)] = transformed[static_cast<size_t>(y)];
		}
	}
	return distances;
}

MapSdf build_map_sdf(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles
) {
	MapSdf sdf;
	sdf.width = p_width_tiles;
	sdf.height = p_height_tiles;
	sdf.values.resize(static_cast<size_t>(p_width_tiles * p_height_tiles), 0.0);
	bool has_inside = false;
	for (int64_t y = 0; y < p_height_tiles && !has_inside; ++y) {
		for (int64_t x = 0; x < p_width_tiles; ++x) {
			if (is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, x, y)) {
				has_inside = true;
				break;
			}
		}
	}
	if (!has_inside) {
		std::fill(
			sdf.values.begin(),
			sdf.values.end(),
			-static_cast<double>(std::max<int64_t>(p_width_tiles, p_height_tiles))
		);
		return sdf;
	}

	const std::vector<double> inside_distance_sq = squared_distance_to_features(
		p_width_tiles,
		p_height_tiles,
		[&](int64_t p_x, int64_t p_y) {
			return is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, p_x, p_y);
		}
	);
	const int64_t padded_width = p_width_tiles + 2;
	const int64_t padded_height = p_height_tiles + 2;
	const std::vector<double> outside_distance_sq = squared_distance_to_features(
		padded_width,
		padded_height,
		[&](int64_t p_x, int64_t p_y) {
			if (p_x == 0 || p_y == 0 || p_x + 1 == padded_width || p_y + 1 == padded_height) {
				return true;
			}
			return !is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, p_x - 1, p_y - 1);
		}
	);

	for (int64_t y = 0; y < p_height_tiles; ++y) {
		for (int64_t x = 0; x < p_width_tiles; ++x) {
			const bool inside = is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, x, y);
			const double best_sq = inside ?
					outside_distance_sq[static_cast<size_t>((y + 1) * padded_width + x + 1)] :
					inside_distance_sq[static_cast<size_t>(y * p_width_tiles + x)];
			const double distance = std::max(std::sqrt(best_sq) - 0.5, 0.0);
			sdf.values[static_cast<size_t>(y * p_width_tiles + x)] = inside ? distance : -distance;
		}
	}
	return sdf;
}

uint8_t classify_zone(const RecipePayload &p_recipe, const NearestBoundary &p_boundary) {
	if (p_boundary.normal_y > 0.45 &&
			p_recipe.south_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.south_height_px) {
		return ZONE_FACE;
	}
	if (std::abs(p_boundary.normal_x) > 0.45 &&
			p_recipe.side_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.side_height_px) {
		return ZONE_FACE;
	}
	if (p_boundary.normal_y < -0.45 &&
			p_recipe.north_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.north_height_px) {
		return ZONE_BACK;
	}
	if (p_recipe.rim_width_px > 0.0 && p_boundary.distance_px <= p_recipe.rim_width_px) {
		return ZONE_EDGE;
	}
	return ZONE_TOP;
}

double directional_depth_px(const RecipePayload &p_recipe, const NearestBoundary &p_boundary) {
	if (p_boundary.normal_y > 0.45) {
		return std::max(0.0001, p_recipe.south_height_px);
	}
	if (std::abs(p_boundary.normal_x) > 0.45) {
		return std::max(0.0001, p_recipe.side_height_px);
	}
	if (p_boundary.normal_y < -0.45) {
		return std::max(0.0001, p_recipe.north_height_px);
	}
	return std::max(0.0001, p_recipe.rim_width_px);
}

double solve_height_norm(
	const RecipePayload &p_recipe,
	uint8_t p_zone,
	const NearestBoundary &p_boundary
) {
	if (p_zone == ZONE_EMPTY) {
		return 0.0;
	}
	if (p_zone == ZONE_TOP) {
		return 1.0;
	}
	if (p_zone == ZONE_EDGE) {
		const double edge_t = p_recipe.rim_width_px > 0.0 ?
				clamp01(p_boundary.distance_px / p_recipe.rim_width_px) :
				1.0;
		return 0.92 + edge_t * 0.08;
	}
	if (p_zone == ZONE_BACK) {
		const double back_t = p_recipe.north_height_px > 0.0 ?
				clamp01(p_boundary.distance_px / p_recipe.north_height_px) :
				1.0;
		return p_recipe.back_drop * back_t;
	}

	const double face_depth = directional_depth_px(p_recipe, p_boundary);
	const double face_t = std::pow(clamp01(p_boundary.distance_px / face_depth), p_recipe.face_power);
	return face_t;
}

double periodic_value_noise_x(
	const RecipePayload &p_recipe,
	double p_world_cell_x,
	double p_world_cell_y,
	double p_scale,
	double p_phase_x,
	double p_phase_y,
	int64_t p_seed
);

double edge_debris_height_offset(
	const RecipePayload &p_recipe,
	uint8_t p_zone,
	const NearestBoundary &p_boundary,
	int64_t p_seed,
	double p_world_cell_x,
	double p_world_cell_y
) {
	if (p_recipe.edge_debris <= 0.0 || p_zone == ZONE_EMPTY || p_zone == ZONE_TOP) {
		return 0.0;
	}
	const double edge_depth_px = std::max(
		1.0,
		std::max(p_recipe.rim_width_px, directional_depth_px(p_recipe, p_boundary))
	);
	const double edge_t = fade(clamp01(1.0 - p_boundary.distance_px / edge_depth_px));
	if (edge_t <= 0.0) {
		return 0.0;
	}
	const double debris = periodic_value_noise_x(
		p_recipe,
		p_world_cell_x,
		p_world_cell_y,
		4.75,
		11.0,
		3.0,
		p_seed + 7919
	) * 2.0 - 1.0;
	return debris * p_recipe.edge_debris * edge_t * 0.08;
}

uint64_t hash_u64(uint64_t p_value) {
	p_value ^= p_value >> 30;
	p_value *= 0xbf58476d1ce4e5b9ULL;
	p_value ^= p_value >> 27;
	p_value *= 0x94d049bb133111ebULL;
	p_value ^= p_value >> 31;
	return p_value;
}

double hash_noise(int64_t p_x, int64_t p_y, int64_t p_seed) {
	uint64_t value = static_cast<uint64_t>(p_seed) ^ 0x9e3779b97f4a7c15ULL;
	value ^= hash_u64(static_cast<uint64_t>(p_x) + 0x632be59bd9b4e019ULL);
	value ^= hash_u64(static_cast<uint64_t>(p_y) + 0x85157af5ULL);
	return static_cast<double>(hash_u64(value) & 0x00ffffffULL) / static_cast<double>(0x01000000ULL);
}

double value_noise(double p_x, double p_y, int64_t p_seed) {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_y));
	const double tx = fade(p_x - static_cast<double>(x0));
	const double ty = fade(p_y - static_cast<double>(y0));
	const double nw = hash_noise(x0, y0, p_seed);
	const double ne = hash_noise(x0 + 1, y0, p_seed);
	const double sw = hash_noise(x0, y0 + 1, p_seed);
	const double se = hash_noise(x0 + 1, y0 + 1, p_seed);
	return lerp(lerp(nw, ne, tx), lerp(sw, se, tx), ty);
}

double positive_mod(double p_value, double p_modulus) {
	if (p_modulus <= 0.0) {
		return p_value;
	}
	const double result = std::fmod(p_value, p_modulus);
	return result < 0.0 ? result + p_modulus : result;
}

double periodic_value_noise_x(
	const RecipePayload &p_recipe,
	double p_world_cell_x,
	double p_world_cell_y,
	double p_scale,
	double p_phase_x,
	double p_phase_y,
	int64_t p_seed
) {
	if (p_recipe.world_wrap_width_tiles <= 0) {
		return value_noise(
			p_world_cell_x * p_scale + p_phase_x,
			p_world_cell_y * p_scale + p_phase_y,
			p_seed
		);
	}
	const double wrap_width = std::max(1.0, static_cast<double>(p_recipe.world_wrap_width_tiles));
	const double phase_tiles = p_scale > 0.0001 ? p_phase_x / p_scale : 0.0;
	const double wrapped_x = positive_mod(p_world_cell_x + phase_tiles, wrap_width);
	const double theta = (wrapped_x / wrap_width) * 6.28318530717958647692;
	const double radius = std::max(0.25, wrap_width * p_scale / 6.28318530717958647692);
	return value_noise(
		std::cos(theta) * radius,
		std::sin(theta) * radius + p_world_cell_y * p_scale + p_phase_y,
		p_seed
	);
}

double contour_warp_offset_px(
	const RecipePayload &p_recipe,
	int64_t p_seed,
	double p_world_cell_x,
	double p_world_cell_y
) {
	if (p_recipe.contour_warp_px <= 0.0 || p_recipe.geometry_variance <= 0.0) {
		return 0.0;
	}
	const double broad = periodic_value_noise_x(
		p_recipe,
		p_world_cell_x,
		p_world_cell_y,
		0.83,
		0.0,
		0.0,
		p_seed
	);
	const double detail = periodic_value_noise_x(
		p_recipe,
		p_world_cell_x,
		p_world_cell_y,
		2.17,
		19.0,
		-7.0,
		p_seed + 1337
	);
	const double mixed = lerp(broad, detail, p_recipe.corner_variation);
	return (mixed * 2.0 - 1.0) * p_recipe.contour_warp_px * p_recipe.geometry_variance;
}

double contour_relax_erosion_px(const RecipePayload &p_recipe) {
	const double raw_erosion_px =
			p_recipe.crown_bevel_px * 0.60 +
			p_recipe.corner_round_px * 0.40 +
			p_recipe.diagonal_smooth_px * 0.18 +
			(p_recipe.outer_corner_radius_px + p_recipe.inner_corner_radius_px) * 0.12;
	return std::min(raw_erosion_px, static_cast<double>(p_recipe.tile_size_px) * 0.45);
}

double contour_shape_offset_px(
	const RecipePayload &p_recipe,
	const Vector2 &p_gradient
) {
	if (p_gradient.length() <= 0.0001 || p_recipe.contour_relax <= 0.0) {
		return 0.0;
	}
	const double curvature_t = clamp01((1.0 - static_cast<double>(p_gradient.length())) * 2.0);
	const double straight_edge_weight = 0.90;
	const double parity_weight = straight_edge_weight + (1.0 - straight_edge_weight) * curvature_t;
	const double preserved_corner_weight = straight_edge_weight * (1.0 - curvature_t * 0.95);
	const double small_feature_t = clamp01(
		(48.0 - static_cast<double>(p_recipe.tile_size_px)) / 32.0
	);
	const double erosion_weight = lerp(parity_weight, preserved_corner_weight, small_feature_t);
	return -p_recipe.contour_relax * contour_relax_erosion_px(p_recipe) * erosion_weight;
}

double contour_antialias_band_px(const RecipePayload &p_recipe) {
	return std::max(1.0, p_recipe.contour_warp_px + 1.0);
}

double organic_shape_radius_tiles(const RecipePayload &p_recipe, double p_raw_sdf_tiles) {
	if (p_recipe.contour_relax <= 0.0) {
		return 0.0;
	}
	const double corner_radius_px = p_raw_sdf_tiles >= 0.0 ?
			p_recipe.outer_corner_radius_px :
			p_recipe.inner_corner_radius_px;
	const double radius_px =
			p_recipe.diagonal_smooth_px * 0.45 +
			p_recipe.corner_round_px * 0.25 +
			corner_radius_px * 0.25 +
			p_recipe.crown_bevel_px * 0.10;
	if (radius_px <= 0.0) {
		return 0.0;
	}
	return std::clamp(radius_px / static_cast<double>(p_recipe.tile_size_px), 0.0, 1.15);
}

ShapeFieldSample organic_shape_field_sample(
	const MapSdf &p_sdf,
	const RecipePayload &p_recipe,
	double p_cell_x,
	double p_cell_y
) {
	ShapeFieldSample result;
	const double raw = p_sdf.sample(p_cell_x, p_cell_y);
	result.value = raw;
	result.gradient = p_sdf.gradient(p_cell_x, p_cell_y, 1.0 / static_cast<double>(p_recipe.tile_size_px));
	const double radius = organic_shape_radius_tiles(p_recipe, raw);
	if (radius <= 0.0001) {
		return result;
	}

	const double west = p_sdf.sample_clamped(p_cell_x - radius, p_cell_y);
	const double east = p_sdf.sample_clamped(p_cell_x + radius, p_cell_y);
	const double north = p_sdf.sample_clamped(p_cell_x, p_cell_y - radius);
	const double south = p_sdf.sample_clamped(p_cell_x, p_cell_y + radius);
	const double axial_sum = west + east + north + south;
	const double diagonal_sum =
			p_sdf.sample_clamped(p_cell_x - radius, p_cell_y - radius) +
			p_sdf.sample_clamped(p_cell_x + radius, p_cell_y - radius) +
			p_sdf.sample_clamped(p_cell_x - radius, p_cell_y + radius) +
			p_sdf.sample_clamped(p_cell_x + radius, p_cell_y + radius);
	const double blurred = (raw * 4.0 + axial_sum * 2.0 + diagonal_sum) / 16.0;
	const double corner_delta = blurred - raw;
	const Vector2 blurred_gradient(
		static_cast<real_t>((east - west) / (radius * 2.0)),
		static_cast<real_t>((south - north) / (radius * 2.0))
	);
	const double gradient_length = static_cast<double>(blurred_gradient.length());
	double directional_corner_t = 0.0;
	if (gradient_length > 0.0001) {
		const double nx = static_cast<double>(blurred_gradient.x) / gradient_length;
		const double ny = static_cast<double>(blurred_gradient.y) / gradient_length;
		directional_corner_t = clamp01(std::abs(nx * ny) * 2.0);
	}
	const double boundary_band_tiles = std::max(0.35, radius + 0.25);
	const double boundary_t = clamp01(1.0 - std::abs(raw) / boundary_band_tiles);
	const double influence = fade(boundary_t);
	const double blend = p_recipe.contour_relax * (0.75 + p_recipe.corner_variation * 0.25);
	const double corner_weight = 0.20 + directional_corner_t * 0.80;
	result.value = raw + corner_delta * corner_weight * blend * influence;
	result.gradient = result.gradient.lerp(blurred_gradient, blend * influence);
	return result;
}

OrganicSample sample_organic(
	const MapSdf &p_sdf,
	const RecipePayload &p_recipe,
	Vector2i p_input_world_origin_tile,
	int64_t p_seed,
	double p_sample_x,
	double p_sample_y
) {
	OrganicSample result;
	const double tile_size = static_cast<double>(p_recipe.tile_size_px);
	const double cell_x = p_sample_x / tile_size - 0.5;
	const double cell_y = p_sample_y / tile_size - 0.5;
	const double world_cell_x = static_cast<double>(p_input_world_origin_tile.x) + cell_x;
	const double world_cell_y = static_cast<double>(p_input_world_origin_tile.y) + cell_y;
	const ShapeFieldSample shape_sample = organic_shape_field_sample(p_sdf, p_recipe, cell_x, cell_y);
	const double sdf_value = shape_sample.value;
	const Vector2 gradient = shape_sample.gradient;
	double signed_distance_px = sdf_value * tile_size;
	signed_distance_px += contour_shape_offset_px(p_recipe, gradient);
	signed_distance_px += contour_warp_offset_px(p_recipe, p_seed, world_cell_x, world_cell_y);

	result.signed_distance_px = signed_distance_px;
	result.inside = signed_distance_px >= 0.0;
	if (!result.inside) {
		return result;
	}

	const double length = gradient.length();
	if (length > 0.0001) {
		result.boundary.normal_x = -static_cast<double>(gradient.x) / length;
		result.boundary.normal_y = -static_cast<double>(gradient.y) / length;
	}
	result.boundary.distance_px = std::max(0.0, signed_distance_px);
	result.zone = classify_zone(p_recipe, result.boundary);
	result.height = solve_height_norm(p_recipe, result.zone, result.boundary);
	result.height = clamp01(
		result.height +
		edge_debris_height_offset(
			p_recipe,
			result.zone,
			result.boundary,
			p_seed,
			world_cell_x,
			world_cell_y
		)
	);
	return result;
}

bool has_solid_margin_in_boundary_direction(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	Vector2i p_output_pos,
	Vector2i p_output_end,
	const RecipePayload &p_recipe,
	double p_sample_x,
	double p_sample_y,
	const NearestBoundary &p_boundary
) {
	if (p_output_end.x <= p_output_pos.x || p_output_end.y <= p_output_pos.y) {
		return false;
	}
	const double tile_size = static_cast<double>(p_recipe.tile_size_px);
	const int64_t tile_x = static_cast<int64_t>(std::floor(p_sample_x / tile_size - 0.5));
	const int64_t tile_y = static_cast<int64_t>(std::floor(p_sample_y / tile_size - 0.5));
	const int64_t clamped_output_x = std::clamp<int64_t>(
		tile_x,
		p_output_pos.x,
		p_output_end.x - 1
	);
	const int64_t clamped_output_y = std::clamp<int64_t>(
		tile_y,
		p_output_pos.y,
		p_output_end.y - 1
	);

	if (p_boundary.normal_y > 0.45 && p_output_end.y < p_height_tiles) {
		return is_solid_tile(
			p_solid_mask,
			p_width_tiles,
			p_height_tiles,
			clamped_output_x,
			p_output_end.y
		);
	}
	if (p_boundary.normal_y < -0.45 && p_output_pos.y > 0) {
		return is_solid_tile(
			p_solid_mask,
			p_width_tiles,
			p_height_tiles,
			clamped_output_x,
			p_output_pos.y - 1
		);
	}
	if (p_boundary.normal_x > 0.45 && p_output_end.x < p_width_tiles) {
		return is_solid_tile(
			p_solid_mask,
			p_width_tiles,
			p_height_tiles,
			p_output_end.x,
			clamped_output_y
		);
	}
	if (p_boundary.normal_x < -0.45 && p_output_pos.x > 0) {
		return is_solid_tile(
			p_solid_mask,
			p_width_tiles,
			p_height_tiles,
			p_output_pos.x - 1,
			clamped_output_y
		);
	}
	return false;
}

void suppress_internal_margin_boundary(
	OrganicSample &r_sample,
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	Vector2i p_output_pos,
	Vector2i p_output_end,
	const RecipePayload &p_recipe,
	double p_sample_x,
	double p_sample_y
) {
	if (!r_sample.inside || r_sample.zone == ZONE_TOP) {
		return;
	}
	if (!has_solid_margin_in_boundary_direction(
				p_solid_mask,
				p_width_tiles,
				p_height_tiles,
				p_output_pos,
				p_output_end,
				p_recipe,
				p_sample_x,
				p_sample_y,
				r_sample.boundary
			)) {
		return;
	}
	r_sample.zone = ZONE_TOP;
	r_sample.height = 1.0;
}

int32_t resolved_supersampling(const RecipePayload &p_recipe) {
	if (p_recipe.shape_supersampling <= 1) {
		return 1;
	}
	if (p_recipe.shape_supersampling <= 2) {
		return 2;
	}
	if (p_recipe.shape_supersampling <= 4) {
		return 4;
	}
	return 8;
}

bool should_supersample(const OrganicSample &p_center, const RecipePayload &p_recipe) {
	if (p_recipe.shape_supersampling <= 1) {
		return false;
	}
	const double contour_band_px = contour_antialias_band_px(p_recipe);
	return std::abs(p_center.signed_distance_px) <= contour_band_px;
}

void write_q16(uint8_t *r_bytes, int32_t p_pixel_index, double p_value) {
	const uint16_t q16 = static_cast<uint16_t>(
		std::round(clamp01(p_value) * static_cast<double>(std::numeric_limits<uint16_t>::max()))
	);
	const int32_t offset = p_pixel_index * 2;
	r_bytes[offset] = q16 & 0xff;
	r_bytes[offset + 1] = (q16 >> 8) & 0xff;
}

void write_normal_rgba8(
	uint8_t *r_bytes,
	int32_t p_pixel_index,
	double p_x,
	double p_y,
	double p_z
) {
	const double length = std::sqrt(p_x * p_x + p_y * p_y + p_z * p_z);
	const double safe_length = length > 0.0001 ? length : 1.0;
	const double nx = p_x / safe_length;
	const double ny = p_y / safe_length;
	const double nz = p_z / safe_length;
	const int32_t offset = p_pixel_index * 4;
	r_bytes[offset] = static_cast<uint8_t>(std::round((nx * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 1] = static_cast<uint8_t>(std::round((ny * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 2] = static_cast<uint8_t>(std::round((nz * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 3] = 255;
}

double sample_height(
	const std::vector<double> &p_heights,
	int32_t p_width,
	int32_t p_height,
	int32_t p_x,
	int32_t p_y
) {
	const int32_t clamped_x = std::clamp(p_x, 0, p_width - 1);
	const int32_t clamped_y = std::clamp(p_y, 0, p_height - 1);
	return p_heights[static_cast<size_t>(clamped_y * p_width + clamped_x)];
}

double sample_height_for_normal(
	const std::vector<double> &p_heights,
	int32_t p_width,
	int32_t p_height,
	int32_t p_x,
	int32_t p_y,
	double p_blur_radius_px
) {
	const int32_t radius = std::clamp(static_cast<int32_t>(std::round(p_blur_radius_px)), 0, 6);
	if (radius <= 0) {
		return sample_height(p_heights, p_width, p_height, p_x, p_y);
	}
	double sum = 0.0;
	int32_t count = 0;
	for (int32_t y = p_y - radius; y <= p_y + radius; ++y) {
		for (int32_t x = p_x - radius; x <= p_x + radius; ++x) {
			sum += sample_height(p_heights, p_width, p_height, x, y);
			++count;
		}
	}
	return count > 0 ? sum / static_cast<double>(count) : 0.0;
}

void write_material_uv(
	uint8_t *r_u,
	uint8_t *r_v,
	int32_t p_pixel_index,
	double p_x,
	double p_y,
	const RecipePayload &p_recipe,
	uint8_t p_zone,
	const NearestBoundary &p_boundary
) {
	const double tile_size = static_cast<double>(p_recipe.tile_size_px);
	double u = std::fmod(std::max(0.0, p_x), tile_size) / tile_size;
	double v = std::fmod(std::max(0.0, p_y), tile_size) / tile_size;

	if (p_zone == ZONE_FACE || p_zone == ZONE_BACK || p_zone == ZONE_EDGE) {
		const double tangent_x = -p_boundary.normal_y;
		const double tangent_y = p_boundary.normal_x;
		const double projected = p_x * tangent_x + p_y * tangent_y;
		u = std::fmod(std::abs(projected), tile_size) / tile_size;
		v = clamp01(p_boundary.distance_px / directional_depth_px(p_recipe, p_boundary));
	}

	write_q16(r_u, p_pixel_index, u);
	write_q16(r_v, p_pixel_index, v);
}

void increment_zone_counter(
	uint8_t p_zone,
	int64_t &r_top_pixels,
	int64_t &r_edge_pixels,
	int64_t &r_face_pixels,
	int64_t &r_back_pixels,
	int64_t &r_empty_pixels
) {
	switch (p_zone) {
		case ZONE_TOP:
			++r_top_pixels;
			break;
		case ZONE_EDGE:
			++r_edge_pixels;
			break;
		case ZONE_FACE:
			++r_face_pixels;
			break;
		case ZONE_BACK:
			++r_back_pixels;
			break;
		case ZONE_EMPTY:
		default:
			++r_empty_pixels;
			break;
	}
}

Dictionary build_packet_from_mask(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_input_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed,
	Rect2i p_output_rect_tiles,
	const char *p_entrypoint_name
) {
	Dictionary packet;
	const String entrypoint = String("TerrainVisualSolver.") + p_entrypoint_name;
	ERR_FAIL_COND_V_MSG(
		p_width_tiles < 0 || p_height_tiles < 0,
		packet,
		entrypoint + String(" received a negative mask dimension.")
	);

	const int64_t expected_mask_size = p_width_tiles * p_height_tiles;
	ERR_FAIL_COND_V_MSG(
		expected_mask_size != p_solid_mask.size(),
		packet,
		entrypoint + String(" received a mask size that does not match width * height.")
	);

	const Vector2i output_pos = p_output_rect_tiles.position;
	const Vector2i output_size = p_output_rect_tiles.size;
	const Vector2i output_end = output_pos + output_size;
	ERR_FAIL_COND_V_MSG(
		output_pos.x < 0 ||
			output_pos.y < 0 ||
			output_size.x < 0 ||
			output_size.y < 0 ||
			output_end.x > p_width_tiles ||
			output_end.y > p_height_tiles,
		packet,
		entrypoint + String(" received an output rect outside the input mask.")
	);

	const RecipePayload recipe = unpack_recipe_payload(p_recipe_payload);
	const int32_t pixel_width = checked_pixel_size(output_size.x, recipe.tile_size_px);
	const int32_t pixel_height = checked_pixel_size(output_size.y, recipe.tile_size_px);
	const int64_t pixel_count_64 = static_cast<int64_t>(pixel_width) * static_cast<int64_t>(pixel_height);
	ERR_FAIL_COND_V_MSG(
		pixel_count_64 > std::numeric_limits<int32_t>::max(),
		packet,
		entrypoint + String(" received an output rect that is too large for one packet.")
	);

	const int32_t pixel_count = static_cast<int32_t>(pixel_count_64);
	const MapSdf map_sdf = build_map_sdf(p_solid_mask, p_width_tiles, p_height_tiles);

	PackedByteArray zone_ids;
	PackedByteArray coverage_top;
	PackedByteArray coverage_edge;
	PackedByteArray coverage_face;
	PackedByteArray coverage_back;
	PackedByteArray height_q16;
	PackedByteArray normal_rgba8;
	PackedByteArray material_u_q16;
	PackedByteArray material_v_q16;

	zone_ids.resize(pixel_count);
	coverage_top.resize(pixel_count);
	coverage_edge.resize(pixel_count);
	coverage_face.resize(pixel_count);
	coverage_back.resize(pixel_count);
	height_q16.resize(pixel_count * 2);
	normal_rgba8.resize(pixel_count * 4);
	material_u_q16.resize(pixel_count * 2);
	material_v_q16.resize(pixel_count * 2);

	uint8_t *zone_ids_w = zone_ids.ptrw();
	uint8_t *coverage_top_w = coverage_top.ptrw();
	uint8_t *coverage_edge_w = coverage_edge.ptrw();
	uint8_t *coverage_face_w = coverage_face.ptrw();
	uint8_t *coverage_back_w = coverage_back.ptrw();
	uint8_t *height_q16_w = height_q16.ptrw();
	uint8_t *normal_rgba8_w = normal_rgba8.ptrw();
	uint8_t *material_u_q16_w = material_u_q16.ptrw();
	uint8_t *material_v_q16_w = material_v_q16.ptrw();

	std::vector<double> heights;
	heights.resize(static_cast<size_t>(pixel_count), 0.0);

	int64_t solid_pixels = 0;
	int64_t top_pixels = 0;
	int64_t edge_pixels = 0;
	int64_t face_pixels = 0;
	int64_t back_pixels = 0;
	int64_t empty_pixels = 0;

	const int64_t output_origin_px_x = static_cast<int64_t>(output_pos.x) * recipe.tile_size_px;
	const int64_t output_origin_px_y = static_cast<int64_t>(output_pos.y) * recipe.tile_size_px;

	for (int32_t y = 0; y < pixel_height; ++y) {
		for (int32_t x = 0; x < pixel_width; ++x) {
			const int32_t pixel_index = y * pixel_width + x;
			const int64_t input_x = output_origin_px_x + x;
			const int64_t input_y = output_origin_px_y + y;
			const double sample_x = static_cast<double>(input_x) + 0.5;
			const double sample_y = static_cast<double>(input_y) + 0.5;
			OrganicSample center_sample = sample_organic(
				map_sdf,
				recipe,
				p_input_world_origin_tile,
				p_seed,
				sample_x,
				sample_y
			);
			suppress_internal_margin_boundary(
				center_sample,
				p_solid_mask,
				p_width_tiles,
				p_height_tiles,
				output_pos,
				output_end,
				recipe,
				sample_x,
				sample_y
			);

			int32_t surface_samples = center_sample.inside ? 1 : 0;
			int32_t total_samples = 1;
			int32_t zone_samples[5] = { 0, 0, 0, 0, 0 };
			double height_sum = center_sample.inside ? center_sample.height : 0.0;
			OrganicSample material_sample = center_sample;
			if (center_sample.inside) {
				zone_samples[center_sample.zone] = 1;
			}

			if (should_supersample(center_sample, recipe)) {
				const int32_t supersampling = resolved_supersampling(recipe);
				surface_samples = 0;
				total_samples = supersampling * supersampling;
				height_sum = 0.0;
				for (int32_t zone_index = ZONE_EMPTY; zone_index <= ZONE_BACK; ++zone_index) {
					zone_samples[zone_index] = 0;
				}
				material_sample = OrganicSample();
				for (int32_t sample_y_index = 0; sample_y_index < supersampling; ++sample_y_index) {
					for (int32_t sample_x_index = 0; sample_x_index < supersampling; ++sample_x_index) {
						const double sub_sample_x = static_cast<double>(input_x) +
								(static_cast<double>(sample_x_index) + 0.5) /
										static_cast<double>(supersampling);
						const double sub_sample_y = static_cast<double>(input_y) +
								(static_cast<double>(sample_y_index) + 0.5) /
										static_cast<double>(supersampling);
						OrganicSample sub_sample = sample_organic(
							map_sdf,
							recipe,
							p_input_world_origin_tile,
							p_seed,
							sub_sample_x,
							sub_sample_y
						);
						suppress_internal_margin_boundary(
							sub_sample,
							p_solid_mask,
							p_width_tiles,
							p_height_tiles,
							output_pos,
							output_end,
							recipe,
							sub_sample_x,
							sub_sample_y
						);
						if (!sub_sample.inside) {
							continue;
						}
						++surface_samples;
						++zone_samples[sub_sample.zone];
						height_sum += sub_sample.height;
						if (!material_sample.inside ||
								zone_samples[sub_sample.zone] > zone_samples[material_sample.zone]) {
							material_sample = sub_sample;
						}
					}
				}
			}

			uint8_t zone = ZONE_EMPTY;
			for (int32_t zone_index = ZONE_TOP; zone_index <= ZONE_BACK; ++zone_index) {
				if (zone_samples[zone_index] > zone_samples[zone]) {
					zone = static_cast<uint8_t>(zone_index);
				}
			}
			if (surface_samples > 0) {
				++solid_pixels;
			}

			const uint8_t surface_coverage = static_cast<uint8_t>(
				std::round(
					clamp01(
						static_cast<double>(surface_samples) / static_cast<double>(total_samples)
					) *
					255.0
				)
			);
			const NearestBoundary boundary = material_sample.boundary;
			const double height = surface_samples > 0 ?
					height_sum / static_cast<double>(surface_samples) :
					0.0;
			heights[static_cast<size_t>(pixel_index)] = height;
			zone_ids_w[pixel_index] = zone;
			coverage_top_w[pixel_index] = zone == ZONE_TOP ? surface_coverage : 0;
			coverage_edge_w[pixel_index] = zone == ZONE_EDGE ? surface_coverage : 0;
			coverage_face_w[pixel_index] = zone == ZONE_FACE ? surface_coverage : 0;
			coverage_back_w[pixel_index] = zone == ZONE_BACK ? surface_coverage : 0;
			write_q16(height_q16_w, pixel_index, height);
			write_material_uv(
				material_u_q16_w,
				material_v_q16_w,
				pixel_index,
				sample_x,
				sample_y,
				recipe,
				zone,
				boundary
			);
			increment_zone_counter(
				zone,
				top_pixels,
				edge_pixels,
				face_pixels,
				back_pixels,
				empty_pixels
			);
		}
	}

	for (int32_t y = 0; y < pixel_height; ++y) {
		for (int32_t x = 0; x < pixel_width; ++x) {
			const int32_t pixel_index = y * pixel_width + x;
			const double normal_strength =
					recipe.normal_strength + recipe.normal_detail_strength * 0.25;
			const double dx = (
				sample_height_for_normal(
					heights,
					pixel_width,
					pixel_height,
					x + 1,
					y,
					recipe.height_to_normal_blur_radius_px
				) -
				sample_height_for_normal(
					heights,
					pixel_width,
					pixel_height,
					x - 1,
					y,
					recipe.height_to_normal_blur_radius_px
				)
			) * 0.5;
			const double dy = (
				sample_height_for_normal(
					heights,
					pixel_width,
					pixel_height,
					x,
					y + 1,
					recipe.height_to_normal_blur_radius_px
				) -
				sample_height_for_normal(
					heights,
					pixel_width,
					pixel_height,
					x,
					y - 1,
					recipe.height_to_normal_blur_radius_px
				)
			) * 0.5;
			write_normal_rgba8(
				normal_rgba8_w,
				pixel_index,
				-dx * normal_strength,
				-dy * normal_strength,
				1.0
			);
		}
	}

	Dictionary debug_counters;
	debug_counters["solver_version"] = SOLVER_VERSION;
	debug_counters["seed"] = p_seed;
	debug_counters["solid_pixels"] = solid_pixels;
	debug_counters["empty_pixels"] = empty_pixels;
	debug_counters["top_pixels"] = top_pixels;
	debug_counters["edge_pixels"] = edge_pixels;
	debug_counters["face_pixels"] = face_pixels;
	debug_counters["back_pixels"] = back_pixels;
	debug_counters["input_width_tiles"] = static_cast<int32_t>(p_width_tiles);
	debug_counters["input_height_tiles"] = static_cast<int32_t>(p_height_tiles);
	debug_counters["output_width_tiles"] = output_size.x;
	debug_counters["output_height_tiles"] = output_size.y;
	debug_counters["outline_polyline_count"] = 0;
	debug_counters["shape_field_version"] = 1;
	debug_counters["shape_field_radius_px"] = organic_shape_radius_tiles(recipe, 0.0) *
			static_cast<double>(recipe.tile_size_px);

	packet["schema_version"] = PACKET_SCHEMA_VERSION;
	packet["recipe_id"] = recipe.recipe_id;
	packet["surface_kind"] = recipe.surface_kind;
	packet["world_origin_tile"] = p_input_world_origin_tile + output_pos;
	packet["chunk_coord"] = p_chunk_coord;
	packet["dirty_rect_tiles"] = Rect2i(Vector2i(0, 0), output_size);
	packet["dirty_rect_px"] = Rect2i(Vector2i(0, 0), Vector2i(pixel_width, pixel_height));
	packet["tile_size_px"] = recipe.tile_size_px;
	packet["pixel_width"] = pixel_width;
	packet["pixel_height"] = pixel_height;
	packet["zone_ids"] = zone_ids;
	packet["coverage_top"] = coverage_top;
	packet["coverage_edge"] = coverage_edge;
	packet["coverage_face"] = coverage_face;
	packet["coverage_back"] = coverage_back;
	packet["height_q16"] = height_q16;
	packet["normal_rgba8"] = normal_rgba8;
	packet["material_u_q16"] = material_u_q16;
	packet["material_v_q16"] = material_v_q16;
	packet["outline_polylines"] = Array();
	packet["debug_counters"] = debug_counters;
	return packet;
}

} // namespace

void TerrainVisualSolver::_bind_methods() {
	ClassDB::bind_method(
		D_METHOD(
			"build_editor_preview_packet",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"preview_origin_tile",
			"seed"
		),
		&TerrainVisualSolver::build_editor_preview_packet
	);
	ClassDB::bind_method(
		D_METHOD(
			"build_chunk_visual_packet",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"world_origin_tile",
			"chunk_coord",
			"seed"
		),
		&TerrainVisualSolver::build_chunk_visual_packet
	);
	ClassDB::bind_method(
		D_METHOD(
			"build_chunk_visual_packet_with_halo",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"input_world_origin_tile",
			"chunk_coord",
			"seed",
			"output_rect_tiles"
		),
		&TerrainVisualSolver::build_chunk_visual_packet_with_halo
	);
	ClassDB::bind_method(
		D_METHOD(
			"copy_patch_field_bytes",
			"base_bytes",
			"patch_bytes",
			"base_pixel_size",
			"patch_pixel_size",
			"dst_rect",
			"src_rect",
			"bytes_per_pixel"
		),
		&TerrainVisualSolver::copy_patch_field_bytes
	);
}

Dictionary TerrainVisualSolver::build_editor_preview_packet(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_preview_origin_tile,
	int64_t p_seed
) const {
	return build_packet_from_mask(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_preview_origin_tile,
		Vector2i(0, 0),
		p_seed,
		Rect2i(
			Vector2i(0, 0),
			Vector2i(static_cast<int32_t>(p_width_tiles), static_cast<int32_t>(p_height_tiles))
		),
		"build_editor_preview_packet"
	);
}

Dictionary TerrainVisualSolver::build_chunk_visual_packet(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed
) const {
	Dictionary packet = build_editor_preview_packet(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_world_origin_tile,
		p_seed
	);
	if (packet.is_empty()) {
		return packet;
	}
	packet["world_origin_tile"] = p_world_origin_tile;
	packet["chunk_coord"] = p_chunk_coord;
	return packet;
}

Dictionary TerrainVisualSolver::build_chunk_visual_packet_with_halo(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_input_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed,
	Rect2i p_output_rect_tiles
) const {
	return build_packet_from_mask(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_input_world_origin_tile,
		p_chunk_coord,
		p_seed,
		p_output_rect_tiles,
		"build_chunk_visual_packet_with_halo"
	);
}

PackedByteArray TerrainVisualSolver::copy_patch_field_bytes(
	const PackedByteArray &p_base_bytes,
	const PackedByteArray &p_patch_bytes,
	Vector2i p_base_pixel_size,
	Vector2i p_patch_pixel_size,
	Rect2i p_dst_rect,
	Rect2i p_src_rect,
	int64_t p_bytes_per_pixel
) const {
	PackedByteArray result = p_base_bytes;
	ERR_FAIL_COND_V_MSG(
		p_bytes_per_pixel <= 0,
		result,
		"TerrainVisualSolver.copy_patch_field_bytes received non-positive bytes_per_pixel."
	);
	ERR_FAIL_COND_V_MSG(
		p_base_pixel_size.x <= 0 ||
			p_base_pixel_size.y <= 0 ||
			p_patch_pixel_size.x <= 0 ||
			p_patch_pixel_size.y <= 0,
		result,
		"TerrainVisualSolver.copy_patch_field_bytes received invalid pixel size."
	);
	ERR_FAIL_COND_V_MSG(
		p_dst_rect.size.x < 0 ||
			p_dst_rect.size.y < 0 ||
			p_src_rect.size.x != p_dst_rect.size.x ||
			p_src_rect.size.y != p_dst_rect.size.y,
		result,
		"TerrainVisualSolver.copy_patch_field_bytes received invalid copy rects."
	);
	ERR_FAIL_COND_V_MSG(
		p_dst_rect.position.x < 0 ||
			p_dst_rect.position.y < 0 ||
			p_src_rect.position.x < 0 ||
			p_src_rect.position.y < 0 ||
			p_dst_rect.position.x + p_dst_rect.size.x > p_base_pixel_size.x ||
			p_dst_rect.position.y + p_dst_rect.size.y > p_base_pixel_size.y ||
			p_src_rect.position.x + p_src_rect.size.x > p_patch_pixel_size.x ||
			p_src_rect.position.y + p_src_rect.size.y > p_patch_pixel_size.y,
		result,
		"TerrainVisualSolver.copy_patch_field_bytes received copy rects outside buffers."
	);

	const int64_t expected_base_size =
			static_cast<int64_t>(p_base_pixel_size.x) *
			static_cast<int64_t>(p_base_pixel_size.y) *
			p_bytes_per_pixel;
	const int64_t expected_patch_size =
			static_cast<int64_t>(p_patch_pixel_size.x) *
			static_cast<int64_t>(p_patch_pixel_size.y) *
			p_bytes_per_pixel;
	ERR_FAIL_COND_V_MSG(
		expected_base_size != p_base_bytes.size() || expected_patch_size != p_patch_bytes.size(),
		result,
		"TerrainVisualSolver.copy_patch_field_bytes received buffers with unexpected size."
	);

	uint8_t *dst_w = result.ptrw();
	const uint8_t *src_r = p_patch_bytes.ptr();
	const int64_t row_byte_count = static_cast<int64_t>(p_dst_rect.size.x) * p_bytes_per_pixel;
	for (int32_t row = 0; row < p_dst_rect.size.y; ++row) {
		const int64_t dst_start =
				(static_cast<int64_t>(p_dst_rect.position.y + row) * p_base_pixel_size.x +
				 p_dst_rect.position.x) *
				p_bytes_per_pixel;
		const int64_t src_start =
				(static_cast<int64_t>(p_src_rect.position.y + row) * p_patch_pixel_size.x +
				 p_src_rect.position.x) *
				p_bytes_per_pixel;
		std::copy(src_r + src_start, src_r + src_start + row_byte_count, dst_w + dst_start);
	}
	return result;
}
