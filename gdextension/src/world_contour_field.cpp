#include "world_contour_field.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <vector>

#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace world_contour_field {
namespace {

constexpr float INF_DISTANCE_SQ = 1.0e20f;

enum class SurfaceZone {
	Top,
	Edge,
	Face,
	Back,
	Empty,
};

struct SurfaceSample {
	float height = 0.0f;
	SurfaceZone zone = SurfaceZone::Empty;
	float occupancy = 0.0f;
	float top_coverage = 0.0f;
	float face_coverage = 0.0f;
	float back_coverage = 0.0f;
};

struct ProjectedFacade {
	SurfaceZone zone = SurfaceZone::Empty;
	float depth = 0.0f;
	float max_depth = 0.0f;
};

struct TileSdf {
	int32_t width = 0;
	int32_t height = 0;
	int32_t outside_padding = 0;
	int32_t outside_width = 0;
	int32_t outside_height = 0;
	std::vector<float> values;
	std::vector<float> outside_values;

	float sample(float p_cell_x, float p_cell_y) const {
		if (width <= 0 || height <= 0 || values.empty()) {
			return 0.0f;
		}

		const int32_t x0 = static_cast<int32_t>(std::floor(p_cell_x));
		const int32_t y0 = static_cast<int32_t>(std::floor(p_cell_y));
		const float tx = p_cell_x - static_cast<float>(x0);
		const float ty = p_cell_y - static_cast<float>(y0);

		const float nw = value_at(x0, y0);
		const float ne = value_at(x0 + 1, y0);
		const float sw = value_at(x0, y0 + 1);
		const float se = value_at(x0 + 1, y0 + 1);
		const float north = lerp(nw, ne, tx);
		const float south = lerp(sw, se, tx);
		return lerp(north, south, ty);
	}

	float value_at(int32_t p_x, int32_t p_y) const {
		if (p_x >= 0 && p_y >= 0 && p_x < width && p_y < height) {
			return values[static_cast<size_t>(p_y * width + p_x)];
		}
		return outside_value_at(p_x, p_y);
	}

	float outside_value_at(int32_t p_x, int32_t p_y) const {
		if (outside_padding > 0) {
			const int32_t px = p_x + outside_padding;
			const int32_t py = p_y + outside_padding;
			if (px >= 0 && py >= 0 && px < outside_width && py < outside_height) {
				return outside_values[static_cast<size_t>(py * outside_width + px)];
			}
		}

		const int32_t max_x = width - 1;
		const int32_t max_y = height - 1;
		const int32_t clamped_x = std::clamp(p_x, 0, max_x);
		const int32_t clamped_y = std::clamp(p_y, 0, max_y);
		const float edge_value = values[static_cast<size_t>(clamped_y * width + clamped_x)];
		const int32_t dx = p_x < 0 ? -p_x : (p_x > max_x ? p_x - max_x : 0);
		const int32_t dy = p_y < 0 ? -p_y : (p_y > max_y ? p_y - max_y : 0);
		return edge_value - std::sqrt(static_cast<float>(dx * dx + dy * dy));
	}

	std::pair<float, float> gradient_with_step(float p_cell_x, float p_cell_y, float p_step) const {
		const float step = std::max(0.0001f, p_step);
		const float dx = (sample(p_cell_x + step, p_cell_y) - sample(p_cell_x - step, p_cell_y)) / (step * 2.0f);
		const float dy = (sample(p_cell_x, p_cell_y + step) - sample(p_cell_x, p_cell_y - step)) / (step * 2.0f);
		return { dx, dy };
	}

	static float lerp(float p_a, float p_b, float p_t) {
		return p_a + (p_b - p_a) * p_t;
	}
};

template <typename T>
T clamp_value(T p_value, T p_min, T p_max) {
	return std::max(p_min, std::min(p_value, p_max));
}

float lerp(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float smoothstep(float p_t) {
	const float t = clamp_value(p_t, 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

float line_mask(float p_distance, float p_width) {
	return clamp_value(1.0f - p_distance / std::max(0.001f, p_width), 0.0f, 1.0f);
}

uint8_t coverage_byte(float p_value) {
	return static_cast<uint8_t>(std::lround(clamp_value(p_value, 0.0f, 1.0f) * 255.0f));
}

uint8_t normal_byte(float p_value) {
	return static_cast<uint8_t>(std::lround(clamp_value(p_value * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f));
}

void write_u16_le(uint8_t *r_bytes, int32_t p_offset, uint16_t p_value) {
	r_bytes[p_offset] = static_cast<uint8_t>(p_value & 0xffU);
	r_bytes[p_offset + 1] = static_cast<uint8_t>((p_value >> 8U) & 0xffU);
}

uint16_t float_to_half_unit(float p_value) {
	const float value = clamp_value(p_value, 0.0f, 1.0f);
	if (value <= 0.0f) {
		return 0U;
	}
	if (value >= 1.0f) {
		return 0x3c00U;
	}

	int exponent = 0;
	const float mantissa = std::frexp(value, &exponent);
	int half_exponent = exponent + 14;
	if (half_exponent <= 0) {
		const int subnormal = static_cast<int>(std::lround(std::ldexp(value, 24)));
		return static_cast<uint16_t>(clamp_value(subnormal, 0, 0x03ff));
	}

	int half_mantissa = static_cast<int>(std::lround((mantissa * 2.0f - 1.0f) * 1024.0f));
	if (half_mantissa >= 1024) {
		half_mantissa = 0;
		++half_exponent;
	}
	return static_cast<uint16_t>((half_exponent << 10) | clamp_value(half_mantissa, 0, 0x03ff));
}

bool read_mask(const godot::PackedByteArray &p_mask, int32_t p_side, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_side || p_y >= p_side) {
		return false;
	}
	const int32_t index = p_y * p_side + p_x;
	return index >= 0 && index < p_mask.size() && p_mask[index] != 0;
}

void distance_transform_1d(const std::vector<float> &p_features, int32_t p_count, std::vector<float> &r_distances) {
	int32_t first_feature = -1;
	for (int32_t index = 0; index < p_count; ++index) {
		if (p_features[static_cast<size_t>(index)] < INF_DISTANCE_SQ * 0.5f) {
			first_feature = index;
			break;
		}
	}
	if (first_feature < 0) {
		std::fill(r_distances.begin(), r_distances.begin() + p_count, INF_DISTANCE_SQ);
		return;
	}

	std::vector<int32_t> parabola_locations(static_cast<size_t>(p_count), 0);
	std::vector<float> boundaries(static_cast<size_t>(p_count + 1), 0.0f);
	int32_t active = 0;
	parabola_locations[0] = first_feature;
	boundaries[0] = -std::numeric_limits<float>::infinity();
	boundaries[1] = std::numeric_limits<float>::infinity();

	auto intersection = [&](int32_t p_candidate, int32_t p_active) -> float {
		const float candidate_f = static_cast<float>(p_candidate);
		const float active_f = static_cast<float>(p_active);
		const float numerator = p_features[static_cast<size_t>(p_candidate)] + candidate_f * candidate_f -
				p_features[static_cast<size_t>(p_active)] - active_f * active_f;
		return numerator / (2.0f * candidate_f - 2.0f * active_f);
	};

	for (int32_t candidate = first_feature + 1; candidate < p_count; ++candidate) {
		if (p_features[static_cast<size_t>(candidate)] >= INF_DISTANCE_SQ * 0.5f) {
			continue;
		}
		float crossed_at = intersection(candidate, parabola_locations[static_cast<size_t>(active)]);
		while (crossed_at <= boundaries[static_cast<size_t>(active)]) {
			if (active == 0) {
				break;
			}
			--active;
			crossed_at = intersection(candidate, parabola_locations[static_cast<size_t>(active)]);
		}
		if (crossed_at <= boundaries[static_cast<size_t>(active)]) {
			active = 0;
		} else {
			++active;
		}
		parabola_locations[static_cast<size_t>(active)] = candidate;
		boundaries[static_cast<size_t>(active)] = crossed_at;
		boundaries[static_cast<size_t>(active + 1)] = std::numeric_limits<float>::infinity();
	}

	active = 0;
	for (int32_t query = 0; query < p_count; ++query) {
		while (boundaries[static_cast<size_t>(active + 1)] < static_cast<float>(query)) {
			++active;
		}
		const int32_t feature = parabola_locations[static_cast<size_t>(active)];
		const float offset = static_cast<float>(query - feature);
		r_distances[static_cast<size_t>(query)] =
				offset * offset + p_features[static_cast<size_t>(feature)];
	}
}

std::vector<float> squared_distance_to_features(
	int32_t p_width,
	int32_t p_height,
	const std::function<bool(int32_t, int32_t)> &p_is_feature
) {
	std::vector<float> grid(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	for (int32_t y = 0; y < p_height; ++y) {
		for (int32_t x = 0; x < p_width; ++x) {
			if (p_is_feature(x, y)) {
				grid[static_cast<size_t>(y * p_width + x)] = 0.0f;
			}
		}
	}

	std::vector<float> row_pass(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	const int32_t max_axis = std::max(1, std::max(p_width, p_height));
	std::vector<float> line(static_cast<size_t>(max_axis), INF_DISTANCE_SQ);
	std::vector<float> transformed(static_cast<size_t>(max_axis), INF_DISTANCE_SQ);

	for (int32_t y = 0; y < p_height; ++y) {
		const int32_t start = y * p_width;
		for (int32_t x = 0; x < p_width; ++x) {
			line[static_cast<size_t>(x)] = grid[static_cast<size_t>(start + x)];
		}
		distance_transform_1d(line, p_width, transformed);
		for (int32_t x = 0; x < p_width; ++x) {
			row_pass[static_cast<size_t>(start + x)] = transformed[static_cast<size_t>(x)];
		}
	}

	std::vector<float> out(static_cast<size_t>(p_width * p_height), INF_DISTANCE_SQ);
	for (int32_t x = 0; x < p_width; ++x) {
		for (int32_t y = 0; y < p_height; ++y) {
			line[static_cast<size_t>(y)] = row_pass[static_cast<size_t>(y * p_width + x)];
		}
		distance_transform_1d(line, p_height, transformed);
		for (int32_t y = 0; y < p_height; ++y) {
			out[static_cast<size_t>(y * p_width + x)] = transformed[static_cast<size_t>(y)];
		}
	}
	return out;
}

TileSdf compute_tile_sdf(const godot::PackedByteArray &p_mask, int32_t p_side, int32_t p_outside_padding) {
	TileSdf sdf;
	sdf.width = p_side;
	sdf.height = p_side;
	if (p_side <= 0 || p_mask.size() != p_side * p_side) {
		return sdf;
	}

	sdf.values.resize(static_cast<size_t>(p_side * p_side), 0.0f);
	bool has_inside = false;
	for (int32_t index = 0; index < p_mask.size(); ++index) {
		if (p_mask[index] != 0) {
			has_inside = true;
			break;
		}
	}
	if (!has_inside) {
		std::fill(sdf.values.begin(), sdf.values.end(), -static_cast<float>(std::max(1, p_side)));
		return sdf;
	}

	const std::vector<float> inside_distance_sq = squared_distance_to_features(
		p_side,
		p_side,
		[&](int32_t p_x, int32_t p_y) {
			return read_mask(p_mask, p_side, p_x, p_y);
		}
	);
	const int32_t padded_width = p_side + 2;
	const int32_t padded_height = p_side + 2;
	const std::vector<float> outside_distance_sq = squared_distance_to_features(
		padded_width,
		padded_height,
		[&](int32_t p_x, int32_t p_y) {
			if (p_x == 0 || p_y == 0 || p_x + 1 == padded_width || p_y + 1 == padded_height) {
				return true;
			}
			return !read_mask(p_mask, p_side, p_x - 1, p_y - 1);
		}
	);

	for (int32_t y = 0; y < p_side; ++y) {
		for (int32_t x = 0; x < p_side; ++x) {
			const int32_t index = y * p_side + x;
			const bool inside = read_mask(p_mask, p_side, x, y);
			const float best_sq = inside ?
					outside_distance_sq[static_cast<size_t>((y + 1) * padded_width + x + 1)] :
					inside_distance_sq[static_cast<size_t>(index)];
			const float distance = std::max(0.0f, std::sqrt(best_sq) - 0.5f);
			sdf.values[static_cast<size_t>(index)] = inside ? distance : -distance;
		}
	}

	sdf.outside_padding = std::max(0, p_outside_padding);
	if (sdf.outside_padding <= 0) {
		return sdf;
	}
	sdf.outside_width = p_side + sdf.outside_padding * 2;
	sdf.outside_height = p_side + sdf.outside_padding * 2;
	const std::vector<float> expanded_distance_sq = squared_distance_to_features(
		sdf.outside_width,
		sdf.outside_height,
		[&](int32_t p_x, int32_t p_y) {
			return read_mask(
				p_mask,
				p_side,
				p_x - sdf.outside_padding,
				p_y - sdf.outside_padding
			);
		}
	);
	sdf.outside_values.resize(static_cast<size_t>(sdf.outside_width * sdf.outside_height), 0.0f);
	for (int32_t y = 0; y < sdf.outside_height; ++y) {
		for (int32_t x = 0; x < sdf.outside_width; ++x) {
			const int32_t map_x = x - sdf.outside_padding;
			const int32_t map_y = y - sdf.outside_padding;
			float value = 0.0f;
			if (map_x >= 0 && map_y >= 0 && map_x < p_side && map_y < p_side) {
				value = sdf.values[static_cast<size_t>(map_y * p_side + map_x)];
			} else {
				const float best_sq = expanded_distance_sq[static_cast<size_t>(y * sdf.outside_width + x)];
				value = best_sq < INF_DISTANCE_SQ * 0.5f ?
						-std::max(0.0f, std::sqrt(best_sq) - 0.5f) :
						-static_cast<float>(std::max(1, p_side));
			}
			sdf.outside_values[static_cast<size_t>(y * sdf.outside_width + x)] = value;
		}
	}
	return sdf;
}

float positive_mod_float(float p_value, float p_mod) {
	if (p_mod <= 0.0f) {
		return 0.0f;
	}
	float result = std::fmod(p_value, p_mod);
	if (result < 0.0f) {
		result += p_mod;
	}
	return result;
}

float hash2d(int32_t p_x, int32_t p_y, uint32_t p_seed) {
	uint32_t n = static_cast<uint32_t>(p_x) * 374761393U +
			static_cast<uint32_t>(p_y) * 668265263U +
			p_seed * 1442695041U;
	n ^= n >> 13U;
	n *= 1274126177U;
	return static_cast<float>(n ^ (n >> 16U)) / static_cast<float>(std::numeric_limits<uint32_t>::max());
}

float value_noise(float p_x, float p_y, uint32_t p_seed) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_y));
	const float tx = p_x - static_cast<float>(x0);
	const float ty = p_y - static_cast<float>(y0);
	const float sx = smoothstep(tx);
	const float sy = smoothstep(ty);

	const float v00 = hash2d(x0, y0, p_seed);
	const float v10 = hash2d(x0 + 1, y0, p_seed);
	const float v01 = hash2d(x0, y0 + 1, p_seed);
	const float v11 = hash2d(x0 + 1, y0 + 1, p_seed);
	return lerp(lerp(v00, v10, sx), lerp(v01, v11, sx), sy);
}

float value_noise_tiled(float p_x, float p_y, float p_period_x, float p_period_y, uint32_t p_seed) {
	if (p_period_x <= 0.00001f || p_period_y <= 0.00001f) {
		return value_noise(p_x, p_y, p_seed);
	}
	const int32_t period_x = static_cast<int32_t>(std::max(1.0f, std::round(p_period_x)));
	const int32_t period_y = static_cast<int32_t>(std::max(1.0f, std::round(p_period_y)));
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_y));
	const float tx = p_x - static_cast<float>(x0);
	const float ty = p_y - static_cast<float>(y0);
	const float sx = smoothstep(tx);
	const float sy = smoothstep(ty);

	auto wrap = [](int32_t p_value, int32_t p_period) {
		const int32_t value = p_value % p_period;
		return value < 0 ? value + p_period : value;
	};
	const float v00 = hash2d(wrap(x0, period_x), wrap(y0, period_y), p_seed);
	const float v10 = hash2d(wrap(x0 + 1, period_x), wrap(y0, period_y), p_seed);
	const float v01 = hash2d(wrap(x0, period_x), wrap(y0 + 1, period_y), p_seed);
	const float v11 = hash2d(wrap(x0 + 1, period_x), wrap(y0 + 1, period_y), p_seed);
	return lerp(lerp(v00, v10, sx), lerp(v01, v11, sx), sy);
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
			p_seed + static_cast<uint32_t>(octave * 97)
		) * amplitude;
		weight += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.0f;
	}
	return weight <= 0.00001f ? 0.0f : total / weight;
}

float varied_smoothing_radius_cells(
	const world_contour_recipe::ContourRecipeV1 &p_recipe,
	uint32_t p_seed,
	float p_world_x,
	float p_world_y,
	float p_radius_px
) {
	const float tile_size = static_cast<float>(std::max(1, p_recipe.tile_size_px));
	float radius = std::max(0.001f, p_radius_px / tile_size);
	if (p_recipe.corner_variation > 0.0f) {
		const float period = std::max(1.0f, tile_size * 5.0f);
		const float noise = fbm_tiled(
			p_world_x * 0.037f + 13.0f,
			p_world_y * 0.037f + 29.0f,
			period * 0.037f,
			period * 0.037f,
			2,
			p_seed
		);
		radius *= 1.0f + (noise - 0.5f) * 2.0f * p_recipe.corner_variation * 0.45f;
	}
	return clamp_value(radius, 0.001f, 0.75f);
}

float weighted_sdf_average(const TileSdf &p_sdf, float p_cell_x, float p_cell_y, const float (*p_samples)[3], int32_t p_count) {
	float sum = 0.0f;
	float weight_sum = 0.0f;
	for (int32_t index = 0; index < p_count; ++index) {
		const float offset_x = p_samples[index][0];
		const float offset_y = p_samples[index][1];
		const float weight = p_samples[index][2];
		sum += p_sdf.sample(p_cell_x + offset_x, p_cell_y + offset_y) * weight;
		weight_sum += weight;
	}
	return sum / std::max(0.001f, weight_sum);
}

float average_sdf_neighborhood(const TileSdf &p_sdf, float p_cell_x, float p_cell_y, float p_radius) {
	const float samples[9][3] = {
		{ 0.0f, 0.0f, 4.0f },
		{ -p_radius, 0.0f, 2.0f },
		{ p_radius, 0.0f, 2.0f },
		{ 0.0f, -p_radius, 2.0f },
		{ 0.0f, p_radius, 2.0f },
		{ -p_radius, -p_radius, 1.0f },
		{ p_radius, -p_radius, 1.0f },
		{ -p_radius, p_radius, 1.0f },
		{ p_radius, p_radius, 1.0f },
	};
	return weighted_sdf_average(p_sdf, p_cell_x, p_cell_y, samples, 9);
}

float average_sdf_diagonals(const TileSdf &p_sdf, float p_cell_x, float p_cell_y, float p_radius) {
	const float samples[5][3] = {
		{ 0.0f, 0.0f, 2.0f },
		{ -p_radius, -p_radius, 1.0f },
		{ p_radius, -p_radius, 1.0f },
		{ -p_radius, p_radius, 1.0f },
		{ p_radius, p_radius, 1.0f },
	};
	return weighted_sdf_average(p_sdf, p_cell_x, p_cell_y, samples, 5);
}

uint8_t sdf_corner_mask(const TileSdf &p_sdf, float p_cell_x, float p_cell_y) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_cell_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_cell_y));
	return static_cast<uint8_t>((p_sdf.sample(static_cast<float>(x0), static_cast<float>(y0)) > 0.0f ? 1U : 0U) |
			(p_sdf.sample(static_cast<float>(x0 + 1), static_cast<float>(y0)) > 0.0f ? 2U : 0U) |
			(p_sdf.sample(static_cast<float>(x0 + 1), static_cast<float>(y0 + 1)) > 0.0f ? 4U : 0U) |
			(p_sdf.sample(static_cast<float>(x0), static_cast<float>(y0 + 1)) > 0.0f ? 8U : 0U));
}

bool diagonal_bridge_sdf_value(const TileSdf &p_sdf, float p_cell_x, float p_cell_y, float p_strength, float p_relax, float &r_value) {
	const int32_t x0 = static_cast<int32_t>(std::floor(p_cell_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(p_cell_y));
	const float u = clamp_value(p_cell_x - static_cast<float>(x0), 0.0f, 1.0f);
	const float v = clamp_value(p_cell_y - static_cast<float>(y0), 0.0f, 1.0f);
	auto corner_inside = [&](int32_t p_ox, int32_t p_oy) {
		return p_sdf.sample(static_cast<float>(x0 + p_ox), static_cast<float>(y0 + p_oy)) > 0.0f;
	};
	const uint8_t mask = static_cast<uint8_t>((corner_inside(0, 0) ? 1U : 0U) |
			(corner_inside(1, 0) ? 2U : 0U) |
			(corner_inside(1, 1) ? 4U : 0U) |
			(corner_inside(0, 1) ? 8U : 0U));
	float diagonal_distance = 0.0f;
	switch (mask & 0x0fU) {
		case 0b0101:
			diagonal_distance = std::abs(u - v);
			break;
		case 0b1010:
			diagonal_distance = std::abs(u + v - 1.0f);
			break;
		default:
			return false;
	}
	const float width = clamp_value(lerp(0.18f, 0.72f, p_strength), 0.04f, 0.74f) *
			clamp_value(0.85f + p_relax * 0.18f, 0.85f, 1.05f);
	if (diagonal_distance >= width) {
		return false;
	}

	const float endpoint_distance = std::min(std::min(u, 1.0f - u), std::min(v, 1.0f - v));
	const float endpoint_fade = line_mask(0.04f - endpoint_distance, 0.04f);
	if (endpoint_fade <= 0.001f) {
		return false;
	}
	const float bridge_strength = line_mask(diagonal_distance, width) * endpoint_fade;
	r_value = -lerp(0.018f, 0.105f, p_strength) * bridge_strength;
	return true;
}

float contour_distance_offset_px(
	const world_contour_recipe::ContourRecipeV1 &p_recipe,
	uint32_t p_seed,
	float p_world_x,
	float p_world_y
) {
	float offset = 0.0f;
	if (p_recipe.contour_warp_px > 0.0f) {
		const float period = std::max(1.0f, static_cast<float>(p_recipe.tile_size_px) * 8.0f);
		const float warp = fbm_tiled(
			p_world_x * 0.055f,
			p_world_y * 0.055f,
			period * 0.055f,
			period * 0.055f,
			2,
			p_seed + 5911U
		) - 0.5f;
		offset += warp * p_recipe.contour_warp_px;
	}

	const float rough_px = (p_recipe.roughness_px / 100.0f) * (static_cast<float>(p_recipe.tile_size_px) * 0.085f);
	if (rough_px > 0.0f) {
		const float period = std::max(1.0f, static_cast<float>(p_recipe.tile_size_px) * 8.0f);
		const float rough = fbm_tiled(
			p_world_x * 0.071f + 37.0f,
			p_world_y * 0.071f + 11.0f,
			period * 0.071f,
			period * 0.071f,
			3,
			p_seed + 8123U
		) - 0.5f;
		offset += rough * rough_px;
	}
	return offset;
}

float smoothed_sdf_value(
	const world_contour_recipe::ContourRecipeV1 &p_recipe,
	const TileSdf &p_sdf,
	uint32_t p_seed,
	float p_world_x,
	float p_world_y,
	float p_cell_x,
	float p_cell_y
) {
	const float tile_size = static_cast<float>(std::max(1, p_recipe.tile_size_px));
	float value = p_sdf.sample(p_cell_x, p_cell_y);
	const float relax = clamp_value(0.65f + p_recipe.contour_relax * 0.45f, 0.35f, 1.1f);
	const uint8_t corner_mask = sdf_corner_mask(p_sdf, p_cell_x, p_cell_y);
	int32_t corner_count = 0;
	for (int32_t bit = 0; bit < 4; ++bit) {
		if ((corner_mask & (1U << bit)) != 0U) {
			++corner_count;
		}
	}

	if (p_recipe.outer_corner_radius_px > 0.0f && corner_count == 1) {
		const float strength = clamp_value(p_recipe.outer_corner_radius_px / (tile_size * 0.5f), 0.0f, 1.0f);
		const float radius = varied_smoothing_radius_cells(p_recipe, p_seed + 1701U, p_world_x, p_world_y, p_recipe.outer_corner_radius_px);
		const float smoothed = average_sdf_neighborhood(p_sdf, p_cell_x, p_cell_y, radius);
		value = lerp(value, smoothed, clamp_value(strength * 1.08f * relax, 0.0f, 0.98f));
	}

	if (p_recipe.inner_corner_radius_px > 0.0f && corner_count == 3) {
		const float strength = clamp_value(p_recipe.inner_corner_radius_px / (tile_size * 0.5f), 0.0f, 1.0f);
		const float radius = varied_smoothing_radius_cells(p_recipe, p_seed + 1907U, p_world_x, p_world_y, p_recipe.inner_corner_radius_px);
		const float smoothed = average_sdf_neighborhood(p_sdf, p_cell_x, p_cell_y, radius);
		value = lerp(value, smoothed, clamp_value(strength * 1.08f * relax, 0.0f, 0.98f));
	}

	if (p_recipe.corner_round_px > 0.0f) {
		const float strength = clamp_value(p_recipe.corner_round_px / (tile_size * 0.5f), 0.0f, 1.0f);
		const float radius = varied_smoothing_radius_cells(p_recipe, p_seed + 2101U, p_world_x, p_world_y, p_recipe.corner_round_px);
		const float smoothed = average_sdf_neighborhood(p_sdf, p_cell_x, p_cell_y, radius);
		value = lerp(value, smoothed, clamp_value(strength * 0.96f * relax, 0.0f, 0.95f));
	}

	if (p_recipe.diagonal_smooth_px > 0.0f) {
		const float strength = clamp_value(p_recipe.diagonal_smooth_px / (tile_size * 0.5f), 0.0f, 1.0f);
		const float radius = varied_smoothing_radius_cells(p_recipe, p_seed + 3307U, p_world_x, p_world_y, p_recipe.diagonal_smooth_px);
		const float smoothed = average_sdf_diagonals(p_sdf, p_cell_x, p_cell_y, radius);
		const float softened = lerp(value, smoothed, clamp_value(strength * 0.64f * relax, 0.0f, 0.82f));
		value = std::max(value, softened);
		float bridge = 0.0f;
		if (diagonal_bridge_sdf_value(p_sdf, p_cell_x, p_cell_y, strength, relax, bridge)) {
			if (value >= 0.0f) {
				const float saddle_width = lerp(0.035f, 0.13f, strength) * (0.85f + relax * 0.15f);
				const float saddle = line_mask(value, saddle_width);
				value = lerp(value, bridge, saddle);
			} else {
				value = std::max(value, bridge);
			}
		}
	}
	return value;
}

float controlled_sdf_distance_px(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y
) {
	const world_contour_recipe::ContourRecipeV1 &recipe = p_input.recipe;
	const float tile_size = static_cast<float>(std::max(1, p_input.tile_size_px));
	const float cell_x = static_cast<float>(p_input.halo_tiles) + (p_world_x - tile_size * 0.5f) / tile_size;
	const float cell_y = static_cast<float>(p_input.halo_tiles) + (p_world_y - tile_size * 0.5f) / tile_size;
	const float field = smoothed_sdf_value(recipe, p_sdf, recipe.seed, p_world_x, p_world_y, cell_x, cell_y);
	return field * tile_size - contour_distance_offset_px(recipe, recipe.seed, p_world_x, p_world_y);
}

std::pair<float, float> controlled_sdf_gradient(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y
) {
	const float step = 1.0f;
	const float dx = (controlled_sdf_distance_px(p_input, p_sdf, p_world_x + step, p_world_y) -
			controlled_sdf_distance_px(p_input, p_sdf, p_world_x - step, p_world_y)) /
			(step * 2.0f);
	const float dy = (controlled_sdf_distance_px(p_input, p_sdf, p_world_x, p_world_y + step) -
			controlled_sdf_distance_px(p_input, p_sdf, p_world_x, p_world_y - step)) /
			(step * 2.0f);
	return { dx, dy };
}

float projected_axis_depth(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y,
	float p_direction_x,
	float p_direction_y,
	float p_max_depth
) {
	if (p_max_depth <= 0.0f) {
		return -1.0f;
	}
	const int32_t steps = static_cast<int32_t>(std::max(1.0f, std::ceil(p_max_depth)));
	float outside = 0.0f;
	float inside = -1.0f;
	for (int32_t step = 1; step <= steps; ++step) {
		const float depth = std::min(static_cast<float>(step), p_max_depth);
		const float sample_x = p_world_x + p_direction_x * depth;
		const float sample_y = p_world_y + p_direction_y * depth;
		if (controlled_sdf_distance_px(p_input, p_sdf, sample_x, sample_y) >= p_input.recipe.collision_threshold_px) {
			inside = depth;
			break;
		}
		outside = depth;
	}
	if (inside < 0.0f) {
		return -1.0f;
	}
	for (int32_t index = 0; index < 7; ++index) {
		const float mid = (outside + inside) * 0.5f;
		const float sample_x = p_world_x + p_direction_x * mid;
		const float sample_y = p_world_y + p_direction_y * mid;
		if (controlled_sdf_distance_px(p_input, p_sdf, sample_x, sample_y) >= p_input.recipe.collision_threshold_px) {
			inside = mid;
		} else {
			outside = mid;
		}
	}
	return inside;
}

bool projected_sdf_facade(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y,
	ProjectedFacade &r_facade
) {
	const world_contour_recipe::ContourRecipeV1 &recipe = p_input.recipe;
	bool has_best = false;
	auto add_candidate = [&](float p_dx, float p_dy, float p_depth, SurfaceZone p_zone) {
		const float depth = projected_axis_depth(p_input, p_sdf, p_world_x, p_world_y, p_dx, p_dy, p_depth);
		if (depth < 0.0f) {
			return;
		}
		const float progress = depth / std::max(1.0f, p_depth);
		const float best_progress = has_best ? r_facade.depth / std::max(1.0f, r_facade.max_depth) : 2.0f;
		if (!has_best || progress < best_progress) {
			r_facade.zone = p_zone;
			r_facade.depth = depth;
			r_facade.max_depth = p_depth;
			has_best = true;
		}
	};

	add_candidate(0.0f, -1.0f, recipe.south_height_px, SurfaceZone::Face);
	if (recipe.side_height_px > 0.0f) {
		add_candidate(1.0f, 0.0f, recipe.side_height_px, SurfaceZone::Face);
		add_candidate(-1.0f, 0.0f, recipe.side_height_px, SurfaceZone::Face);
	}
	if (recipe.north_height_px > 0.0f) {
		add_candidate(0.0f, 1.0f, recipe.north_height_px, SurfaceZone::Back);
	}
	return has_best;
}

float preview_edge_width_px(const world_contour_recipe::ContourRecipeV1 &p_recipe) {
	const float debris_width = static_cast<float>(p_recipe.tile_size_px) * 0.06f * clamp_value(p_recipe.edge_debris, 0.0f, 1.0f);
	return std::min(std::max(p_recipe.rim_width_px, debris_width), static_cast<float>(p_recipe.tile_size_px) * 0.25f);
}

float edge_height_for_progress(float p_progress) {
	return lerp(0.90f, 1.0f, clamp_value(p_progress, 0.0f, 1.0f));
}

float back_height_for_progress(const world_contour_recipe::ContourRecipeV1 &p_recipe, float p_progress) {
	return 1.0f - p_progress * p_recipe.back_drop;
}

float face_height_for_progress(const world_contour_recipe::ContourRecipeV1 &p_recipe, float p_progress) {
	return std::pow(1.0f - clamp_value(p_progress, 0.0f, 1.0f), p_recipe.face_power);
}

SurfaceSample surface_sample(float p_height, SurfaceZone p_zone, float p_occupancy) {
	SurfaceSample sample;
	sample.height = clamp_value(p_height, 0.0f, 1.0f);
	sample.zone = p_zone;
	sample.occupancy = clamp_value(p_occupancy, 0.0f, 1.0f);
	switch (p_zone) {
		case SurfaceZone::Top:
			sample.top_coverage = sample.occupancy;
			break;
		case SurfaceZone::Edge:
			sample.top_coverage = sample.occupancy;
			sample.face_coverage = sample.occupancy;
			break;
		case SurfaceZone::Face:
			sample.face_coverage = sample.occupancy;
			break;
		case SurfaceZone::Back:
			sample.back_coverage = sample.occupancy;
			break;
		case SurfaceZone::Empty:
		default:
			break;
	}
	return sample;
}

int32_t zone_index(SurfaceZone p_zone) {
	switch (p_zone) {
		case SurfaceZone::Top:
			return 0;
		case SurfaceZone::Edge:
			return 1;
		case SurfaceZone::Face:
			return 2;
		case SurfaceZone::Back:
			return 3;
		case SurfaceZone::Empty:
		default:
			return 4;
	}
}

SurfaceZone dominant_occupied_zone(const int32_t p_counts[5]) {
	int32_t best_index = 0;
	int32_t best_count = p_counts[0];
	for (int32_t index = 1; index < 4; ++index) {
		if (p_counts[index] > best_count) {
			best_index = index;
			best_count = p_counts[index];
		}
	}
	switch (best_index) {
		case 0:
			return SurfaceZone::Top;
		case 1:
			return SurfaceZone::Edge;
		case 2:
			return SurfaceZone::Face;
		case 3:
			return SurfaceZone::Back;
		default:
			return SurfaceZone::Empty;
	}
}

SurfaceSample sample_surface_at_world(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y
) {
	const world_contour_recipe::ContourRecipeV1 &recipe = p_input.recipe;
	const float signed_distance = controlled_sdf_distance_px(p_input, p_sdf, p_world_x, p_world_y) - recipe.collision_threshold_px;

	if (signed_distance < 0.0f) {
		const float max_projection = std::max(recipe.south_height_px, std::max(recipe.north_height_px, recipe.side_height_px));
		if (-signed_distance > max_projection + 1.5f) {
			return surface_sample(0.0f, SurfaceZone::Empty, 0.0f);
		}
		ProjectedFacade projected;
		if (projected_sdf_facade(p_input, p_sdf, p_world_x, p_world_y, projected)) {
			const float progress = clamp_value(projected.depth / std::max(1.0f, projected.max_depth), 0.0f, 1.0f);
			const float height = projected.zone == SurfaceZone::Back ?
					back_height_for_progress(recipe, progress) :
					face_height_for_progress(recipe, progress);
			return surface_sample(height, projected.zone, 1.0f);
		}
		const float tile_size = static_cast<float>(std::max(1, p_input.tile_size_px));
		const float cell_x = static_cast<float>(p_input.halo_tiles) + (p_world_x - tile_size * 0.5f) / tile_size;
		const float cell_y = static_cast<float>(p_input.halo_tiles) + (p_world_y - tile_size * 0.5f) / tile_size;
		const uint8_t corner_mask = sdf_corner_mask(p_sdf, cell_x, cell_y);
		int32_t corner_count = 0;
		for (int32_t bit = 0; bit < 4; ++bit) {
			if ((corner_mask & (1U << bit)) != 0U) {
				++corner_count;
			}
		}
		float corner_alpha = 0.0f;
		if (corner_count == 1 || corner_count == 3) {
			const float fx = cell_x - std::floor(cell_x);
			const float fy = cell_y - std::floor(cell_y);
			const float corner_distance = std::sqrt((fx - 0.5f) * (fx - 0.5f) + (fy - 0.5f) * (fy - 0.5f));
			corner_alpha = smoothstep((0.18f - corner_distance) / 0.18f) * 0.35f;
		}
		const float fallback_coverage = corner_alpha;
		if (fallback_coverage > 0.0f) {
			return surface_sample(0.0f, SurfaceZone::Edge, fallback_coverage);
		}
		return surface_sample(0.0f, SurfaceZone::Empty, 0.0f);
	}

	float height = 1.0f;
	SurfaceZone zone = SurfaceZone::Top;
	const float edge_width = preview_edge_width_px(recipe);
	if (edge_width > 0.0f && signed_distance <= edge_width) {
		const float progress = clamp_value(signed_distance / std::max(1.0f, edge_width), 0.0f, 1.0f);
		height = edge_height_for_progress(progress);
		zone = SurfaceZone::Edge;
	}

	if (recipe.crown_bevel_px > 0.0f && zone == SurfaceZone::Top && signed_distance < recipe.crown_bevel_px) {
		const float t = clamp_value(signed_distance / std::max(1.0f, recipe.crown_bevel_px), 0.0f, 1.0f);
		height = std::min(height, lerp(0.86f, 1.0f, t));
	}
	return surface_sample(height, zone, 1.0f);
}

int32_t surface_sample_count_for_pixel(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_center_x,
	float p_center_y,
	float p_pixel_size_px
) {
	const int32_t samples = std::max(1, std::min(2, p_input.recipe.shape_supersampling));
	if (samples <= 1) {
		return 1;
	}

	const float signed_distance = controlled_sdf_distance_px(p_input, p_sdf, p_center_x, p_center_y) - p_input.recipe.collision_threshold_px;
	const float aa_width = std::max(1.35f, p_pixel_size_px * 0.75f);
	if (std::abs(signed_distance) <= aa_width) {
		return samples;
	}

	const float max_projection = std::max(
		std::max(p_input.recipe.south_height_px, p_input.recipe.north_height_px),
		std::max(p_input.recipe.side_height_px, p_input.recipe.rim_width_px)
	);
	if (max_projection > 0.0f && std::abs(signed_distance + max_projection) <= aa_width) {
		return samples;
	}
	return 1;
}

SurfaceSample sample_surface_pixel(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_pixel_origin_x,
	float p_pixel_origin_y,
	float p_pixel_size_px
) {
	const float center_x = p_pixel_origin_x + p_pixel_size_px * 0.5f;
	const float center_y = p_pixel_origin_y + p_pixel_size_px * 0.5f;
	const int32_t samples = surface_sample_count_for_pixel(p_input, p_sdf, center_x, center_y, p_pixel_size_px);
	if (samples <= 1) {
		return sample_surface_at_world(p_input, p_sdf, center_x, center_y);
	}

	const float inv_samples = 1.0f / static_cast<float>(samples);
	const float total = static_cast<float>(samples * samples);
	float height_sum = 0.0f;
	float top_coverage = 0.0f;
	float face_coverage = 0.0f;
	float back_coverage = 0.0f;
	int32_t occupied = 0;
	int32_t zone_counts[5] = { 0, 0, 0, 0, 0 };

	for (int32_t sy = 0; sy < samples; ++sy) {
		for (int32_t sx = 0; sx < samples; ++sx) {
			const float sample_x = p_pixel_origin_x + (static_cast<float>(sx) + 0.5f) * inv_samples * p_pixel_size_px;
			const float sample_y = p_pixel_origin_y + (static_cast<float>(sy) + 0.5f) * inv_samples * p_pixel_size_px;
			const SurfaceSample sample = sample_surface_at_world(p_input, p_sdf, sample_x, sample_y);
			zone_counts[zone_index(sample.zone)] += 1;
			if (sample.zone != SurfaceZone::Empty) {
				height_sum += sample.height;
				++occupied;
			}
			top_coverage += sample.top_coverage;
			face_coverage += sample.face_coverage;
			back_coverage += sample.back_coverage;
		}
	}

	SurfaceSample result;
	if (occupied <= 0) {
		return result;
	}
	const float inv_total = 1.0f / total;
	result.height = height_sum / static_cast<float>(occupied);
	result.zone = dominant_occupied_zone(zone_counts);
	result.occupancy = static_cast<float>(occupied) * inv_total;
	result.top_coverage = top_coverage * inv_total;
	result.face_coverage = face_coverage * inv_total;
	result.back_coverage = back_coverage * inv_total;
	return result;
}

void encode_normal_from_height(
	const std::vector<float> &p_height,
	int32_t p_width,
	int32_t p_height_px,
	int32_t p_x,
	int32_t p_y,
	float p_strength,
	uint8_t &r_x,
	uint8_t &r_y,
	uint8_t &r_z
) {
	auto sample_height = [&](int32_t p_sx, int32_t p_sy) {
		const int32_t x = clamp_value(p_sx, 0, p_width - 1);
		const int32_t y = clamp_value(p_sy, 0, p_height_px - 1);
		return p_height[static_cast<size_t>(y * p_width + x)];
	};
	const float nw = sample_height(p_x - 1, p_y - 1);
	const float n = sample_height(p_x, p_y - 1);
	const float ne = sample_height(p_x + 1, p_y - 1);
	const float w = sample_height(p_x - 1, p_y);
	const float e = sample_height(p_x + 1, p_y);
	const float sw = sample_height(p_x - 1, p_y + 1);
	const float s = sample_height(p_x, p_y + 1);
	const float se = sample_height(p_x + 1, p_y + 1);
	const float dx = (ne + 2.0f * e + se - (nw + 2.0f * w + sw)) / 8.0f;
	const float dy = (sw + 2.0f * s + se - (nw + 2.0f * n + ne)) / 8.0f;
	float nx = -dx * p_strength;
	float ny = -dy * p_strength;
	float nz = 1.0f;
	const float length = std::sqrt(nx * nx + ny * ny + nz * nz);
	if (length > 0.0001f) {
		nx /= length;
		ny /= length;
		nz /= length;
	}
	r_x = normal_byte(nx);
	r_y = normal_byte(ny);
	r_z = normal_byte(nz);
}

void apply_mountain_bottom_outline_for_field(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	godot::PackedByteArray &r_mask,
	int32_t p_output_px,
	float p_render_to_logical_scale
) {
	const world_contour_recipe::ContourRecipeV1 &recipe = p_input.recipe;
	if (!recipe.outline_enabled || recipe.outline_width_px <= 0.0f) {
		return;
	}
	const int32_t output_px = p_output_px;
	const float outline_width_px = std::max(0.001f, recipe.outline_width_px);
	for (int32_t y = 0; y < output_px; ++y) {
		for (int32_t x = 0; x < output_px; ++x) {
			const int32_t offset = (y * output_px + x) * 4;
			if (r_mask[offset + 3] != 0U) {
				continue;
			}
			const float logical_x = (static_cast<float>(x) + 0.5f) * p_render_to_logical_scale;
			const float logical_y = (static_cast<float>(y) + 0.5f) * p_render_to_logical_scale;
			const float signed_distance = controlled_sdf_distance_px(p_input, p_sdf, logical_x, logical_y) - recipe.collision_threshold_px;
			if (signed_distance >= 0.0f || signed_distance <= -outline_width_px) {
				continue;
			}
			const float band = clamp_value((outline_width_px + signed_distance) / outline_width_px, 0.0f, 1.0f);
			const uint8_t alpha = coverage_byte(smoothstep(band) * 0.48f);
			r_mask.set(offset + 1, std::max<uint8_t>(r_mask[offset + 1], alpha));
			r_mask.set(offset + 3, std::max<uint8_t>(r_mask[offset + 3], alpha));
		}
	}
}

bool mask_has_alpha_coverage(const godot::PackedByteArray &p_mask) {
	const uint8_t *mask_read = p_mask.ptr();
	for (int32_t offset = 3; offset < p_mask.size(); offset += 4) {
		if (mask_read[offset] != 0U) {
			return true;
		}
	}
	return false;
}

float contour_collision_distance_px(
	const ContourChunkInputV1 &p_input,
	const TileSdf &p_sdf,
	float p_world_x,
	float p_world_y
) {
	const float base_distance = controlled_sdf_distance_px(p_input, p_sdf, p_world_x, p_world_y) - p_input.recipe.collision_threshold_px;
	const SurfaceSample visual_sample = sample_surface_at_world(p_input, p_sdf, p_world_x, p_world_y);
	if (visual_sample.zone == SurfaceZone::Empty || visual_sample.occupancy <= 0.40f) {
		return base_distance;
	}
	const float visible_distance = (visual_sample.occupancy - 0.40f) * std::max(4.0f, static_cast<float>(p_input.recipe.collision_sampling_px));
	return std::max(base_distance, visible_distance);
}

godot::Dictionary make_failure_result(const godot::String &p_message) {
	godot::Dictionary result;
	result["ready"] = false;
	result["message"] = p_message;
	return result;
}

godot::Dictionary get_dict(const godot::Dictionary &p_dict, const char *p_key) {
	const godot::Variant value = p_dict.get(p_key, godot::Dictionary());
	if (value.get_type() == godot::Variant::DICTIONARY) {
		return static_cast<godot::Dictionary>(value);
	}
	return godot::Dictionary();
}

ContourChunkInputV1 parse_input(const godot::Dictionary &p_input) {
	ContourChunkInputV1 input;
	input.chunk_coord = static_cast<godot::Vector2i>(p_input.get("chunk_coord", godot::Vector2i()));
	input.world_seed = static_cast<int64_t>(p_input.get("world_seed", 0));
	input.world_version = static_cast<int64_t>(p_input.get("world_version", 0));
	input.tile_size_px = static_cast<int32_t>(static_cast<int64_t>(p_input.get("tile_size_px", 64)));
	input.render_tile_size_px = static_cast<int32_t>(static_cast<int64_t>(p_input.get("render_tile_size_px", input.tile_size_px)));
	input.chunk_size_tiles = static_cast<int32_t>(static_cast<int64_t>(p_input.get("chunk_size_tiles", 16)));
	input.halo_tiles = static_cast<int32_t>(static_cast<int64_t>(p_input.get("halo_tiles", 1)));
	input.recipe_id = static_cast<godot::StringName>(p_input.get("recipe_id", godot::StringName()));
	input.solid_mask_with_halo = static_cast<godot::PackedByteArray>(p_input.get("solid_mask_with_halo", godot::PackedByteArray()));
	input.contour_class_mask_with_halo = static_cast<godot::PackedByteArray>(p_input.get("contour_class_mask_with_halo", input.solid_mask_with_halo));
	input.mountain_id_with_halo = static_cast<godot::PackedInt32Array>(p_input.get("mountain_id_with_halo", godot::PackedInt32Array()));
	input.diff_revision = static_cast<int64_t>(p_input.get("diff_revision", 0));
	input.recipe = world_contour_recipe::parse_recipe_v1(get_dict(p_input, "recipe"), input.recipe_id);

	if (!input.recipe.valid) {
		input.error = input.recipe.error;
		return input;
	}
	if (input.tile_size_px <= 0 || input.render_tile_size_px <= 0 || input.chunk_size_tiles <= 0 || input.halo_tiles < 0) {
		input.error = "ContourChunkInputV1 geometry fields must be positive.";
		return input;
	}
	if (input.recipe.tile_size_px != input.tile_size_px || input.recipe.chunk_size_tiles != input.chunk_size_tiles) {
		input.error = "ContourChunkInputV1 tile/chunk geometry must match ContourRecipeV1.";
		return input;
	}
	const int32_t side = input.chunk_size_tiles + input.halo_tiles * 2;
	if (input.solid_mask_with_halo.size() != side * side) {
		input.error = "ContourChunkInputV1 solid_mask_with_halo has invalid size.";
		return input;
	}
	if (!input.contour_class_mask_with_halo.is_empty() && input.contour_class_mask_with_halo.size() != side * side) {
		input.error = "ContourChunkInputV1 contour_class_mask_with_halo has invalid size.";
		return input;
	}
	if (!input.mountain_id_with_halo.is_empty() && input.mountain_id_with_halo.size() != side * side) {
		input.error = "ContourChunkInputV1 mountain_id_with_halo has invalid size.";
		return input;
	}
	input.valid = true;
	return input;
}

godot::Rect2i compute_solid_bounds_world_px(const ContourChunkInputV1 &p_input) {
	const int32_t side = p_input.chunk_size_tiles + p_input.halo_tiles * 2;
	int32_t min_x = p_input.chunk_size_tiles;
	int32_t min_y = p_input.chunk_size_tiles;
	int32_t max_x = -1;
	int32_t max_y = -1;
	for (int32_t local_y = 0; local_y < p_input.chunk_size_tiles; ++local_y) {
		for (int32_t local_x = 0; local_x < p_input.chunk_size_tiles; ++local_x) {
			const int32_t mask_x = local_x + p_input.halo_tiles;
			const int32_t mask_y = local_y + p_input.halo_tiles;
			if (!read_mask(p_input.solid_mask_with_halo, side, mask_x, mask_y)) {
				continue;
			}
			min_x = std::min(min_x, local_x);
			min_y = std::min(min_y, local_y);
			max_x = std::max(max_x, local_x);
			max_y = std::max(max_y, local_y);
		}
	}
	if (max_x < min_x || max_y < min_y) {
		return godot::Rect2i();
	}
	return godot::Rect2i(
		min_x * p_input.tile_size_px,
		min_y * p_input.tile_size_px,
		(max_x - min_x + 1) * p_input.tile_size_px,
		(max_y - min_y + 1) * p_input.tile_size_px
	);
}

} // namespace

godot::Dictionary build_contour_chunk(const godot::Dictionary &p_input) {
	const ContourChunkInputV1 input = parse_input(p_input);
	if (!input.valid) {
		return make_failure_result(input.error);
	}

	const int32_t side = input.chunk_size_tiles + input.halo_tiles * 2;
	const int32_t logical_output_px = input.chunk_size_tiles * input.tile_size_px;
	const int32_t output_px = input.chunk_size_tiles * input.render_tile_size_px;
	const int32_t pixel_count = output_px * output_px;
	const float render_to_logical_scale = static_cast<float>(input.tile_size_px) / static_cast<float>(input.render_tile_size_px);
	const int32_t collision_sample_px = std::max(1, input.recipe.collision_sampling_px);
	const int32_t collision_side = static_cast<int32_t>(std::ceil(static_cast<float>(logical_output_px) / static_cast<float>(collision_sample_px))) + 1;

	const int32_t outside_padding = std::max(
		input.halo_tiles + 2,
		static_cast<int32_t>(std::ceil(std::max(input.recipe.south_height_px, std::max(input.recipe.north_height_px, input.recipe.side_height_px)) /
				static_cast<float>(input.tile_size_px))) + 2
	);
	const TileSdf sdf = compute_tile_sdf(input.solid_mask_with_halo, side, outside_padding);

	godot::PackedByteArray mask_rgba8;
	mask_rgba8.resize(pixel_count * 4);
	godot::PackedByteArray height_r16;
	height_r16.resize(pixel_count * 2);
	godot::PackedByteArray normal_rgba8;
	normal_rgba8.resize(pixel_count * 4);
	uint8_t *mask_rgba8_write = mask_rgba8.ptrw();
	uint8_t *height_r16_write = height_r16.ptrw();
	std::vector<float> render_heights(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> occupancies(static_cast<size_t>(pixel_count), 0.0f);

	for (int32_t y = 0; y < output_px; ++y) {
		for (int32_t x = 0; x < output_px; ++x) {
			const int32_t index = y * output_px + x;
			const float logical_x = static_cast<float>(x) * render_to_logical_scale;
			const float logical_y = static_cast<float>(y) * render_to_logical_scale;
			const SurfaceSample sample = sample_surface_pixel(input, sdf, logical_x, logical_y, render_to_logical_scale);
			render_heights[static_cast<size_t>(index)] = sample.height;
			occupancies[static_cast<size_t>(index)] = sample.occupancy;

			const int32_t mask_offset = index * 4;
			mask_rgba8_write[mask_offset] = coverage_byte(sample.top_coverage);
			mask_rgba8_write[mask_offset + 1] = coverage_byte(sample.face_coverage);
			mask_rgba8_write[mask_offset + 2] = coverage_byte(sample.back_coverage);
			mask_rgba8_write[mask_offset + 3] = coverage_byte(sample.occupancy);

			const uint16_t height_value = float_to_half_unit(sample.height);
			write_u16_le(height_r16_write, index * 2, height_value);
		}
	}

	apply_mountain_bottom_outline_for_field(input, sdf, mask_rgba8, output_px, render_to_logical_scale);

	uint8_t *normal_rgba8_write = normal_rgba8.ptrw();
	const uint8_t *mask_rgba8_read = mask_rgba8.ptr();
	for (int32_t y = 0; y < output_px; ++y) {
		for (int32_t x = 0; x < output_px; ++x) {
			const int32_t index = y * output_px + x;
			const int32_t offset = index * 4;
			uint8_t nx = 128U;
			uint8_t ny = 128U;
			uint8_t nz = 255U;
			if (occupancies[static_cast<size_t>(index)] > 0.0f) {
				encode_normal_from_height(
					render_heights,
					output_px,
					output_px,
					x,
					y,
					input.recipe.normal_strength / std::max(1.0f, render_to_logical_scale),
					nx,
					ny,
					nz
				);
			}
			normal_rgba8_write[offset] = nx;
			normal_rgba8_write[offset + 1] = ny;
			normal_rgba8_write[offset + 2] = nz;
			normal_rgba8_write[offset + 3] = mask_rgba8_read[offset + 3];
		}
	}

	godot::PackedFloat32Array collision_sdf_f32;
	collision_sdf_f32.resize(collision_side * collision_side);
	float *collision_sdf_f32_write = collision_sdf_f32.ptrw();
	for (int32_t y = 0; y < collision_side; ++y) {
		for (int32_t x = 0; x < collision_side; ++x) {
			const float world_x = static_cast<float>(std::min(logical_output_px, x * collision_sample_px));
			const float world_y = static_cast<float>(std::min(logical_output_px, y * collision_sample_px));
			const float distance = contour_collision_distance_px(input, sdf, world_x, world_y);
			collision_sdf_f32_write[y * collision_side + x] = distance;
		}
	}

	godot::Dictionary result;
	result["chunk_coord"] = input.chunk_coord;
	result["recipe_id"] = input.recipe.recipe_id;
	result["diff_revision"] = input.diff_revision;
	result["pixel_size"] = godot::Vector2i(output_px, output_px);
	result["mask_rgba8"] = mask_rgba8;
	result["height_r16"] = height_r16;
	result["normal_rgba8"] = normal_rgba8;
	result["collision_sdf_f32"] = collision_sdf_f32;
	result["collision_origin_world_px"] = godot::Vector2i(
		input.chunk_coord.x * logical_output_px,
		input.chunk_coord.y * logical_output_px
	);
	result["collision_sample_px"] = collision_sample_px;
	result["collision_size"] = godot::Vector2i(collision_side, collision_side);
	result["collision_blocks_inside"] = input.recipe.collision_blocks_inside;
	result["solid_bounds_world_px"] = compute_solid_bounds_world_px(input);
	result["has_visual_coverage"] = mask_has_alpha_coverage(mask_rgba8);
	result["ready"] = true;
	return result;
}

} // namespace world_contour_field
