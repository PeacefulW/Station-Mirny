#include "mountain_field.h"

#include "autotile_47.h"

#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <numeric>
#include <unordered_map>
#include <utility>

#include <godot_cpp/core/error_macros.hpp>

namespace mountain_field {

namespace {

constexpr float k_pi = 3.14159265358979323846f;
constexpr float k_two_pi = 2.0f * k_pi;

constexpr uint64_t k_seed_salt_domain_warp = 0x5f8d6d2c0a7b91f3ULL;
constexpr uint64_t k_seed_salt_macro = 0x3bd39e10cb0ef593ULL;
constexpr uint64_t k_seed_salt_ridge = 0xa2c6d11f74b93ce5ULL;
constexpr uint64_t k_seed_salt_hierarchical_id = 0x8d3c9b1f2746e5a1ULL;

constexpr int64_t k_legacy_world_wrap_width_tiles = 65536;
constexpr int64_t k_hierarchical_world_version = 6;
constexpr int32_t k_hierarchical_macro_cell_size_v6 = 1024;
constexpr int32_t k_hierarchical_macro_halo_v6 = 1;
constexpr int32_t k_hierarchical_min_label_cell_size_v6 = 8;

bool is_spawn_safety_area_impl(int64_t p_world_version, int64_t p_world_x, int64_t p_world_y) {
	if (p_world_version < 0) {
		return false;
	}
	// Version 4 worlds keep their original mountain output. The spawn-safe patch
	// returns in version 5 as part of the canonical base solve.
	if (p_world_version < 4) {
		return p_world_x >= 12 && p_world_x <= 20 && p_world_y >= 12 && p_world_y <= 20;
	}
	if (p_world_version < 5) {
		return false;
	}
	return p_world_x >= 12 && p_world_x <= 20 && p_world_y >= 12 && p_world_y <= 20;
}

template <typename T>
T clamp_value(T p_value, T p_min_value, T p_max_value) {
	return std::max(p_min_value, std::min(p_max_value, p_value));
}

float saturate(float p_value) {
	return clamp_value(p_value, 0.0f, 1.0f);
}

float smoothstep(float p_edge0, float p_edge1, float p_value) {
	if (p_edge0 == p_edge1) {
		return p_value < p_edge0 ? 0.0f : 1.0f;
	}
	const float t = saturate((p_value - p_edge0) / (p_edge1 - p_edge0));
	return t * t * (3.0f - 2.0f * t);
}

uint64_t splitmix64(uint64_t p_value) {
	p_value += 0x9e3779b97f4a7c15ULL;
	p_value = (p_value ^ (p_value >> 30U)) * 0xbf58476d1ce4e5b9ULL;
	p_value = (p_value ^ (p_value >> 27U)) * 0x94d049bb133111ebULL;
	return p_value ^ (p_value >> 31U);
}

uint64_t mix_seed(int64_t p_seed, int64_t p_world_version, uint64_t p_salt) {
	uint64_t mixed = splitmix64(static_cast<uint64_t>(p_seed) ^ p_salt);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	return mixed;
}

int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

int64_t sanitize_world_wrap_width(int64_t p_width_tiles) {
	return std::max<int64_t>(1, p_width_tiles);
}

int64_t wrap_world_x(int64_t p_world_x, int64_t p_world_wrap_width_tiles) {
	const int64_t width = sanitize_world_wrap_width(p_world_wrap_width_tiles);
	int64_t wrapped = p_world_x % width;
	if (wrapped < 0) {
		wrapped += width;
	}
	return wrapped;
}

int64_t wrap_cell_coord_x(int64_t p_cell_x, int32_t p_cell_size, int64_t p_world_wrap_width_tiles) {
	const int64_t width = sanitize_world_wrap_width(p_world_wrap_width_tiles);
	const int64_t cells_per_wrap = std::max<int64_t>(
		1,
		(width + static_cast<int64_t>(p_cell_size) - 1) / static_cast<int64_t>(p_cell_size)
	);
	int64_t wrapped = p_cell_x % cells_per_wrap;
	if (wrapped < 0) {
		wrapped += cells_per_wrap;
	}
	return wrapped;
}

int64_t wrapped_delta_x(int64_t p_origin_x, int64_t p_world_x, int64_t p_world_wrap_width_tiles) {
	const int64_t width = sanitize_world_wrap_width(p_world_wrap_width_tiles);
	int64_t delta = wrap_world_x(p_world_x, width) - wrap_world_x(p_origin_x, width);
	if (delta < 0) {
		delta += width;
	}
	return delta;
}

void project_wrapped_x_to_cylinder(
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_world_wrap_width_tiles,
	float &r_out_x,
	float &r_out_y,
	float &r_out_z
) {
	const float width = static_cast<float>(sanitize_world_wrap_width(p_world_wrap_width_tiles));
	float wrapped_x = std::fmod(static_cast<float>(p_world_x), width);
	if (wrapped_x < 0.0f) {
		wrapped_x += width;
	}
	const float theta = (wrapped_x / width) * k_two_pi;
	const float radius = width / k_two_pi;
	r_out_x = std::cos(theta) * radius;
	r_out_y = std::sin(theta) * radius;
	r_out_z = static_cast<float>(p_world_y);
}

Settings sanitize_settings(const Settings &p_settings) {
	Settings sanitized = p_settings;
	sanitized.density = saturate(sanitized.density);
	sanitized.scale = std::max(32.0f, sanitized.scale);
	sanitized.continuity = saturate(sanitized.continuity);
	sanitized.ruggedness = saturate(sanitized.ruggedness);
	sanitized.anchor_cell_size = clamp_value(sanitized.anchor_cell_size, 32, 512);
	sanitized.gravity_radius = clamp_value(sanitized.gravity_radius, 32, 256);
	sanitized.foot_band = clamp_value(sanitized.foot_band, 0.02f, 0.3f);
	sanitized.interior_margin = clamp_value(sanitized.interior_margin, 0, 4);
	sanitized.latitude_influence = clamp_value(sanitized.latitude_influence, -1.0f, 1.0f);
	sanitized.world_wrap_width_tiles = sanitize_world_wrap_width(sanitized.world_wrap_width_tiles);
	sanitized.ocean_band_tiles = std::max<int64_t>(0, sanitized.ocean_band_tiles);
	return sanitized;
}

Thresholds derive_thresholds_impl(const Settings &p_settings) {
	// Threshold derivation for M1:
	// - density shifts the wall threshold from safely above the sampled range at
	//   density 0.0 (effectively no mountains) down into the field as density
	//   grows
	// - foot_band widens the outer non-interior band downward from the wall
	//   threshold
	// - anchor threshold stays only slightly above the wall threshold so identity
	//   anchors can exist inside the same silhouette instead of disappearing into
	//   near-never-hit peak values
	const float t_wall = clamp_value(1.08f - p_settings.density * 1.05f, -0.25f, 1.2f);
	const float t_edge = std::max(-0.25f, t_wall - p_settings.foot_band);
	const float t_anchor = std::min(1.0f, t_wall + std::max(0.01f, p_settings.foot_band * 0.12f));
	return Thresholds{ t_edge, t_wall, std::max(t_wall, t_anchor) };
}

int make_noise_seed(uint64_t p_value) {
	return static_cast<int>(p_value & 0x7fffffffULL);
}

FastNoiseLite make_domain_warp_noise(uint64_t p_seed, const Settings &p_settings) {
	FastNoiseLite noise(make_noise_seed(p_seed));
	noise.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2);
	noise.SetFractalType(FastNoiseLite::FractalType_DomainWarpProgressive);
	noise.SetFractalOctaves(2 + static_cast<int>(std::round(p_settings.continuity * 2.0f)));
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetDomainWarpType(FastNoiseLite::DomainWarpType_OpenSimplex2);
	noise.SetFrequency(1.0f / std::max(64.0f, p_settings.scale * 0.75f));
	noise.SetDomainWarpAmp(p_settings.scale * (0.08f + p_settings.continuity * 0.27f));
	return noise;
}

FastNoiseLite make_macro_noise(uint64_t p_seed, const Settings &p_settings) {
	FastNoiseLite noise(make_noise_seed(p_seed));
	noise.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2S);
	noise.SetFractalType(FastNoiseLite::FractalType_FBm);
	noise.SetFractalOctaves(4);
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetFrequency(1.0f / std::max(32.0f, p_settings.scale));
	return noise;
}

FastNoiseLite make_ridge_noise(uint64_t p_seed, const Settings &p_settings) {
	FastNoiseLite noise(make_noise_seed(p_seed));
	noise.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2);
	noise.SetFractalType(FastNoiseLite::FractalType_Ridged);
	noise.SetFractalOctaves(3);
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetFrequency(1.0f / std::max(16.0f, p_settings.scale * 0.35f));
	return noise;
}

int32_t make_hierarchical_mountain_id(
	int64_t p_seed,
	int64_t p_world_version,
	int64_t p_cell_origin_x,
	int64_t p_cell_origin_y,
	int32_t p_cell_size,
	int64_t p_world_wrap_width_tiles
) {
	uint64_t mixed = mix_seed(p_seed, p_world_version, k_seed_salt_hierarchical_id);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(wrap_world_x(p_cell_origin_x, p_world_wrap_width_tiles)) * 0xc2b2ae3d27d4eb4fULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_cell_origin_y) * 0x165667b19e3779f9ULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_cell_size) * 0x94d049bb133111ebULL);
	const int32_t id = static_cast<int32_t>(mixed & 0x7fffffffULL);
	return id == 0 ? 1 : id;
}

} // namespace

Evaluator::Evaluator(int64_t p_seed, int64_t p_world_version, const Settings &p_settings) :
		settings_(sanitize_settings(p_settings)),
		thresholds_(derive_thresholds_impl(settings_)),
		seed_(p_seed),
		world_version_(p_world_version),
		domain_warp_noise_(make_domain_warp_noise(mix_seed(p_seed, p_world_version, k_seed_salt_domain_warp), settings_)),
		macro_noise_(make_macro_noise(mix_seed(p_seed, p_world_version, k_seed_salt_macro), settings_)),
		ridge_noise_(make_ridge_noise(mix_seed(p_seed, p_world_version, k_seed_salt_ridge), settings_)) {}

float Evaluator::sample_elevation(int64_t p_world_x, int64_t p_world_y) const {
	if (is_spawn_safety_area_impl(world_version_, p_world_x, p_world_y)) {
		return 0.0f;
	}
	float sample_x = 0.0f;
	float sample_y = 0.0f;
	float sample_z = 0.0f;
	project_wrapped_x_to_cylinder(
		p_world_x,
		p_world_y,
		settings_.world_wrap_width_tiles,
		sample_x,
		sample_y,
		sample_z
	);
	domain_warp_noise_.DomainWarp(sample_x, sample_y, sample_z);

	const float macro_raw = macro_noise_.GetNoise(sample_x, sample_y, sample_z);
	const float macro = saturate((macro_raw + 1.0f) * 0.5f);

	const float ridge_raw = ridge_noise_.GetNoise(sample_x, sample_y, sample_z);
	const float ridge = 1.0f - std::abs(ridge_raw);
	const float ridge_gate = smoothstep(0.35f, 0.8f, macro);

	const float latitude = std::tanh(static_cast<float>(p_world_y) / 4096.0f);
	const float latitude_bias = latitude * settings_.latitude_influence * 0.12f;
	const float elevation = macro + ridge_gate * ridge * settings_.ruggedness * 0.28f + latitude_bias;
	float gain = 1.0f;
	if (settings_.suppress_ocean_band_mountains && settings_.ocean_band_tiles > 0) {
		const float ocean_band = static_cast<float>(settings_.ocean_band_tiles);
		const float fade_end = std::max(ocean_band + 1.0f, ocean_band * 2.0f);
		gain = smoothstep(ocean_band, fade_end, static_cast<float>(p_world_y));
	}
	return saturate(elevation) * gain;
}

int32_t Evaluator::resolve_mountain_atlas_index(
	int64_t p_world_x,
	int64_t p_world_y,
	int32_t p_center_mountain_id,
	int32_t p_north_mountain_id,
	int32_t p_north_east_mountain_id,
	int32_t p_east_mountain_id,
	int32_t p_south_east_mountain_id,
	int32_t p_south_mountain_id,
	int32_t p_south_west_mountain_id,
	int32_t p_west_mountain_id,
	int32_t p_north_west_mountain_id
) const {
	if (p_center_mountain_id == 0) {
		return 0;
	}
	return static_cast<int32_t>(autotile_47::resolve_atlas_index(
		p_north_mountain_id == p_center_mountain_id,
		p_north_east_mountain_id == p_center_mountain_id,
		p_east_mountain_id == p_center_mountain_id,
		p_south_east_mountain_id == p_center_mountain_id,
		p_south_mountain_id == p_center_mountain_id,
		p_south_west_mountain_id == p_center_mountain_id,
		p_west_mountain_id == p_center_mountain_id,
		p_north_west_mountain_id == p_center_mountain_id,
		p_world_x,
		p_world_y,
		seed_
	));
}

const Settings &Evaluator::get_settings() const {
	return settings_;
}

const Thresholds &Evaluator::get_thresholds() const {
	return thresholds_;
}

struct Int64PairHash {
	size_t operator()(const std::pair<int64_t, int64_t> &p_key) const {
		uint64_t mixed = splitmix64(static_cast<uint64_t>(p_key.first));
		mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_key.second) * 0x9e3779b185ebca87ULL);
		return static_cast<size_t>(mixed);
	}
};

struct ProbeSummary {
	bool all_inside = true;
	bool all_outside = true;
	float representative_elevation = -std::numeric_limits<float>::infinity();
	int64_t representative_tile_x = 0;
	int64_t representative_tile_y = 0;
};

struct HierarchicalLeafRecord {
	int64_t canonical_origin_x = 0;
	int64_t canonical_origin_y = 0;
	int32_t cell_size = 0;
	float representative_elevation = 0.0f;
	int64_t representative_tile_x = 0;
	int64_t representative_tile_y = 0;
};

class DisjointSet {
public:
	explicit DisjointSet(int32_t p_size) :
			parent_(static_cast<size_t>(p_size), 0),
			rank_(static_cast<size_t>(p_size), 0) {
		std::iota(parent_.begin(), parent_.end(), 0);
	}

	int32_t find(int32_t p_index) {
		if (parent_[static_cast<size_t>(p_index)] != p_index) {
			parent_[static_cast<size_t>(p_index)] = find(parent_[static_cast<size_t>(p_index)]);
		}
		return parent_[static_cast<size_t>(p_index)];
	}

	void unite(int32_t p_a, int32_t p_b) {
		int32_t root_a = find(p_a);
		int32_t root_b = find(p_b);
		if (root_a == root_b) {
			return;
		}
		if (rank_[static_cast<size_t>(root_a)] < rank_[static_cast<size_t>(root_b)]) {
			std::swap(root_a, root_b);
		}
		parent_[static_cast<size_t>(root_b)] = root_a;
		if (rank_[static_cast<size_t>(root_a)] == rank_[static_cast<size_t>(root_b)]) {
			rank_[static_cast<size_t>(root_a)] = static_cast<uint8_t>(rank_[static_cast<size_t>(root_a)] + 1U);
		}
	}

private:
	std::vector<int32_t> parent_;
	std::vector<uint8_t> rank_;
};

class HierarchicalMacroBuilder {
public:
	HierarchicalMacroBuilder(int64_t p_seed, int64_t p_world_version, const Settings &p_settings) :
			seed_(p_seed),
			world_version_(p_world_version),
			evaluator_(p_seed, p_world_version, p_settings),
			thresholds_(evaluator_.get_thresholds()),
			world_wrap_width_tiles_(evaluator_.get_settings().world_wrap_width_tiles),
			macro_cell_size_(get_hierarchical_macro_cell_size(p_world_version)),
			macro_halo_(k_hierarchical_macro_halo_v6),
			min_label_cell_size_(get_hierarchical_min_label_cell_size(p_world_version)),
			min_cells_per_macro_axis_(macro_cell_size_ / min_label_cell_size_),
			region_min_cells_per_axis_((macro_halo_ * 2 + 1) * min_cells_per_macro_axis_),
			region_leaf_index_(static_cast<size_t>(region_min_cells_per_axis_ * region_min_cells_per_axis_), -1) {}

	HierarchicalMacroSolve build(int64_t p_macro_cell_x, int64_t p_macro_cell_y) {
		macro_cell_x_ = wrap_cell_coord_x(p_macro_cell_x, macro_cell_size_, world_wrap_width_tiles_);
		macro_cell_y_ = p_macro_cell_y;
		macro_origin_x_ = macro_cell_x_ * static_cast<int64_t>(macro_cell_size_);
		macro_origin_y_ = macro_cell_y_ * static_cast<int64_t>(macro_cell_size_);
		region_origin_display_x_ = macro_origin_x_ - static_cast<int64_t>(macro_halo_) * static_cast<int64_t>(macro_cell_size_);
		region_origin_display_y_ = macro_origin_y_ - static_cast<int64_t>(macro_halo_) * static_cast<int64_t>(macro_cell_size_);

		for (int32_t macro_offset_y = -macro_halo_; macro_offset_y <= macro_halo_; ++macro_offset_y) {
			for (int32_t macro_offset_x = -macro_halo_; macro_offset_x <= macro_halo_; ++macro_offset_x) {
				const int64_t display_origin_x = macro_origin_x_ + static_cast<int64_t>(macro_offset_x) * static_cast<int64_t>(macro_cell_size_);
				const int64_t display_origin_y = macro_origin_y_ + static_cast<int64_t>(macro_offset_y) * static_cast<int64_t>(macro_cell_size_);
				process_cell(display_origin_x, display_origin_y, macro_cell_size_);
			}
		}

		return finalize();
	}

private:
	static bool is_lexicographically_smaller(int64_t p_candidate_x, int64_t p_candidate_y, int64_t p_current_x, int64_t p_current_y) {
		return p_candidate_x < p_current_x || (p_candidate_x == p_current_x && p_candidate_y < p_current_y);
	}

	float sample_cached(int64_t p_world_x, int64_t p_world_y) {
		const std::pair<int64_t, int64_t> key = { wrap_world_x(p_world_x, world_wrap_width_tiles_), p_world_y };
		auto found = sample_cache_.find(key);
		if (found != sample_cache_.end()) {
			return found->second;
		}
		const float sampled = evaluator_.sample_elevation(p_world_x, p_world_y);
		sample_cache_.emplace(key, sampled);
		return sampled;
	}

	static std::vector<int64_t> build_probe_positions(int64_t p_origin, int32_t p_size, int32_t p_steps) {
		std::vector<int64_t> positions;
		positions.reserve(static_cast<size_t>(p_steps));
		if (p_steps <= 1) {
			positions.push_back(p_origin);
			return positions;
		}
		for (int32_t step = 0; step < p_steps; ++step) {
			const int64_t numerator = static_cast<int64_t>(p_size - 1) * static_cast<int64_t>(step);
			const int64_t offset = (numerator + static_cast<int64_t>(p_steps - 2)) / static_cast<int64_t>(p_steps - 1);
			positions.push_back(p_origin + offset);
		}
		return positions;
	}

	ProbeSummary summarize_probe_grid(int64_t p_origin_x, int64_t p_origin_y, int32_t p_size, int32_t p_steps) {
		ProbeSummary summary;
		const std::vector<int64_t> x_positions = build_probe_positions(p_origin_x, p_size, p_steps);
		const std::vector<int64_t> y_positions = build_probe_positions(p_origin_y, p_size, p_steps);
		for (int64_t probe_y : y_positions) {
			for (int64_t probe_x : x_positions) {
				const float elevation = sample_cached(probe_x, probe_y);
				const bool is_inside = elevation >= thresholds_.t_edge;
				summary.all_inside = summary.all_inside && is_inside;
				summary.all_outside = summary.all_outside && !is_inside;
				if (elevation > summary.representative_elevation ||
						(elevation == summary.representative_elevation &&
								is_lexicographically_smaller(probe_x, probe_y, summary.representative_tile_x, summary.representative_tile_y))) {
					summary.representative_elevation = elevation;
					summary.representative_tile_x = probe_x;
					summary.representative_tile_y = probe_y;
				}
			}
		}
		return summary;
	}

	bool resolve_leaf_is_solid(
		int64_t p_origin_x,
		int64_t p_origin_y,
		HierarchicalLeafRecord &r_out_leaf
	) {
		const std::vector<int64_t> x_positions = build_probe_positions(p_origin_x, min_label_cell_size_, 5);
		const std::vector<int64_t> y_positions = build_probe_positions(p_origin_y, min_label_cell_size_, 5);
		std::array<std::array<bool, 5>, 5> inside{};
		int32_t inside_count = 0;
		float best_elevation = -std::numeric_limits<float>::infinity();
		int64_t best_tile_x = x_positions[0];
		int64_t best_tile_y = y_positions[0];
		for (int32_t y_index = 0; y_index < 5; ++y_index) {
			for (int32_t x_index = 0; x_index < 5; ++x_index) {
				const float elevation = sample_cached(x_positions[static_cast<size_t>(x_index)], y_positions[static_cast<size_t>(y_index)]);
				const bool is_inside = elevation >= thresholds_.t_edge;
				inside[static_cast<size_t>(y_index)][static_cast<size_t>(x_index)] = is_inside;
				if (is_inside) {
					inside_count += 1;
				}
				if (elevation > best_elevation ||
						(elevation == best_elevation &&
								is_lexicographically_smaller(
									x_positions[static_cast<size_t>(x_index)],
									y_positions[static_cast<size_t>(y_index)],
									best_tile_x,
									best_tile_y
								))) {
					best_elevation = elevation;
					best_tile_x = x_positions[static_cast<size_t>(x_index)];
					best_tile_y = y_positions[static_cast<size_t>(y_index)];
				}
			}
		}

		const bool center_inside = inside[2][2];
		int32_t strong_faces = 0;
		const int32_t north_support = static_cast<int32_t>(inside[0][1]) + static_cast<int32_t>(inside[0][2]) + static_cast<int32_t>(inside[0][3]);
		const int32_t south_support = static_cast<int32_t>(inside[4][1]) + static_cast<int32_t>(inside[4][2]) + static_cast<int32_t>(inside[4][3]);
		const int32_t west_support = static_cast<int32_t>(inside[1][0]) + static_cast<int32_t>(inside[2][0]) + static_cast<int32_t>(inside[3][0]);
		const int32_t east_support = static_cast<int32_t>(inside[1][4]) + static_cast<int32_t>(inside[2][4]) + static_cast<int32_t>(inside[3][4]);
		strong_faces += north_support >= 2 ? 1 : 0;
		strong_faces += south_support >= 2 ? 1 : 0;
		strong_faces += west_support >= 2 ? 1 : 0;
		strong_faces += east_support >= 2 ? 1 : 0;

		// Version 6 keeps canonical mountain identity at an 8-tile minimum cell.
		// This preserves wall/foot silhouettes at chunk scale while suppressing
		// sub-8-tile bridges and noise from spawning separate mountain domains.
		const bool is_solid = inside_count >= 10 && (center_inside || strong_faces >= 2);
		if (!is_solid) {
			return false;
		}

		r_out_leaf.canonical_origin_x = wrap_world_x(p_origin_x, world_wrap_width_tiles_);
		r_out_leaf.canonical_origin_y = p_origin_y;
		r_out_leaf.cell_size = min_label_cell_size_;
		r_out_leaf.representative_elevation = best_elevation;
		r_out_leaf.representative_tile_x = wrap_world_x(best_tile_x, world_wrap_width_tiles_);
		r_out_leaf.representative_tile_y = best_tile_y;
		return true;
	}

	void process_cell(int64_t p_origin_x, int64_t p_origin_y, int32_t p_cell_size) {
		if (p_cell_size <= min_label_cell_size_) {
			HierarchicalLeafRecord leaf;
			if (resolve_leaf_is_solid(p_origin_x, p_origin_y, leaf)) {
				add_leaf(p_origin_x, p_origin_y, leaf);
			}
			return;
		}

		const ProbeSummary summary = summarize_probe_grid(p_origin_x, p_origin_y, p_cell_size, 3);
		if (summary.all_outside) {
			return;
		}
		if (summary.all_inside) {
			HierarchicalLeafRecord leaf;
			leaf.canonical_origin_x = wrap_world_x(p_origin_x, world_wrap_width_tiles_);
			leaf.canonical_origin_y = p_origin_y;
			leaf.cell_size = p_cell_size;
			leaf.representative_elevation = summary.representative_elevation;
			leaf.representative_tile_x = wrap_world_x(summary.representative_tile_x, world_wrap_width_tiles_);
			leaf.representative_tile_y = summary.representative_tile_y;
			add_leaf(p_origin_x, p_origin_y, leaf);
			return;
		}

		const int32_t child_size = p_cell_size / 2;
		for (int32_t child_y = 0; child_y < 2; ++child_y) {
			for (int32_t child_x = 0; child_x < 2; ++child_x) {
				process_cell(
					p_origin_x + static_cast<int64_t>(child_x) * static_cast<int64_t>(child_size),
					p_origin_y + static_cast<int64_t>(child_y) * static_cast<int64_t>(child_size),
					child_size
				);
			}
		}
	}

	void add_leaf(int64_t p_display_origin_x, int64_t p_display_origin_y, const HierarchicalLeafRecord &p_leaf) {
		const int32_t leaf_index = static_cast<int32_t>(leaves_.size());
		leaves_.push_back(p_leaf);
		const int32_t cells_per_axis = p_leaf.cell_size / min_label_cell_size_;
		const int32_t start_x = static_cast<int32_t>((p_display_origin_x - region_origin_display_x_) / static_cast<int64_t>(min_label_cell_size_));
		const int32_t start_y = static_cast<int32_t>((p_display_origin_y - region_origin_display_y_) / static_cast<int64_t>(min_label_cell_size_));
		for (int32_t local_y = 0; local_y < cells_per_axis; ++local_y) {
			for (int32_t local_x = 0; local_x < cells_per_axis; ++local_x) {
				const int32_t grid_x = start_x + local_x;
				const int32_t grid_y = start_y + local_y;
				region_leaf_index_[static_cast<size_t>(grid_y * region_min_cells_per_axis_ + grid_x)] = leaf_index;
			}
		}
	}

	static bool is_better_leaf(const HierarchicalLeafRecord &p_candidate, const HierarchicalLeafRecord &p_current) {
		if (p_candidate.representative_elevation != p_current.representative_elevation) {
			return p_candidate.representative_elevation > p_current.representative_elevation;
		}
		if (p_candidate.canonical_origin_x != p_current.canonical_origin_x) {
			return p_candidate.canonical_origin_x < p_current.canonical_origin_x;
		}
		if (p_candidate.canonical_origin_y != p_current.canonical_origin_y) {
			return p_candidate.canonical_origin_y < p_current.canonical_origin_y;
		}
		return p_candidate.cell_size < p_current.cell_size;
	}

	HierarchicalRepresentative make_domain_from_leaf(const HierarchicalLeafRecord &p_leaf) const {
		HierarchicalRepresentative domain;
		domain.cell_origin_x = p_leaf.canonical_origin_x;
		domain.cell_origin_y = p_leaf.canonical_origin_y;
		domain.cell_size = p_leaf.cell_size;
		domain.representative_tile_x = p_leaf.representative_tile_x;
		domain.representative_tile_y = p_leaf.representative_tile_y;
		domain.representative_elevation = p_leaf.representative_elevation;
		domain.mountain_id = make_hierarchical_mountain_id(
			seed_,
			world_version_,
			p_leaf.canonical_origin_x,
			p_leaf.canonical_origin_y,
			p_leaf.cell_size,
			world_wrap_width_tiles_
		);
		return domain;
	}

	HierarchicalMacroSolve finalize() {
		HierarchicalMacroSolve solve;
		solve.macro_cell_x = macro_cell_x_;
		solve.macro_cell_y = macro_cell_y_;
		solve.macro_origin_x = macro_origin_x_;
		solve.macro_origin_y = macro_origin_y_;
		solve.macro_cell_size = macro_cell_size_;
		solve.min_label_cell_size = min_label_cell_size_;
		solve.min_cells_per_macro_axis = min_cells_per_macro_axis_;
		solve.world_wrap_width_tiles = world_wrap_width_tiles_;
		solve.domain_index_per_min_cell.assign(static_cast<size_t>(min_cells_per_macro_axis_ * min_cells_per_macro_axis_), -1);

		if (leaves_.empty()) {
			return solve;
		}

		DisjointSet disjoint_set(static_cast<int32_t>(leaves_.size()));
		for (int32_t grid_y = 0; grid_y < region_min_cells_per_axis_; ++grid_y) {
			for (int32_t grid_x = 0; grid_x < region_min_cells_per_axis_; ++grid_x) {
				const int32_t index = grid_y * region_min_cells_per_axis_ + grid_x;
				const int32_t leaf_index = region_leaf_index_[static_cast<size_t>(index)];
				if (leaf_index < 0) {
					continue;
				}
				if (grid_x + 1 < region_min_cells_per_axis_) {
					const int32_t east_leaf = region_leaf_index_[static_cast<size_t>(index + 1)];
					if (east_leaf >= 0 && east_leaf != leaf_index) {
						disjoint_set.unite(leaf_index, east_leaf);
					}
				}
				if (grid_y + 1 < region_min_cells_per_axis_) {
					const int32_t south_leaf = region_leaf_index_[static_cast<size_t>(index + region_min_cells_per_axis_)];
					if (south_leaf >= 0 && south_leaf != leaf_index) {
						disjoint_set.unite(leaf_index, south_leaf);
					}
				}
			}
		}

		std::vector<int32_t> best_leaf_by_root(leaves_.size(), -1);
		for (int32_t leaf_index = 0; leaf_index < static_cast<int32_t>(leaves_.size()); ++leaf_index) {
			const int32_t root = disjoint_set.find(leaf_index);
			const int32_t current_best = best_leaf_by_root[static_cast<size_t>(root)];
			if (current_best < 0 || is_better_leaf(leaves_[static_cast<size_t>(leaf_index)], leaves_[static_cast<size_t>(current_best)])) {
				best_leaf_by_root[static_cast<size_t>(root)] = leaf_index;
			}
		}

		std::vector<int32_t> domain_index_by_root(leaves_.size(), -1);
		const int32_t interior_offset = macro_halo_ * min_cells_per_macro_axis_;
		for (int32_t local_y = 0; local_y < min_cells_per_macro_axis_; ++local_y) {
			for (int32_t local_x = 0; local_x < min_cells_per_macro_axis_; ++local_x) {
				const int32_t region_x = interior_offset + local_x;
				const int32_t region_y = interior_offset + local_y;
				const int32_t leaf_index = region_leaf_index_[static_cast<size_t>(region_y * region_min_cells_per_axis_ + region_x)];
				if (leaf_index < 0) {
					continue;
				}
				const int32_t root = disjoint_set.find(leaf_index);
				int32_t domain_index = domain_index_by_root[static_cast<size_t>(root)];
				if (domain_index < 0) {
					domain_index = static_cast<int32_t>(solve.domains.size());
					domain_index_by_root[static_cast<size_t>(root)] = domain_index;
					solve.domains.push_back(make_domain_from_leaf(leaves_[static_cast<size_t>(best_leaf_by_root[static_cast<size_t>(root)])]));
				}
				solve.domain_index_per_min_cell[static_cast<size_t>(local_y * min_cells_per_macro_axis_ + local_x)] = domain_index;
			}
		}

		return solve;
	}

	int64_t seed_ = 0;
	int64_t world_version_ = 0;
	Evaluator evaluator_;
	const Thresholds &thresholds_;
	int64_t world_wrap_width_tiles_ = k_legacy_world_wrap_width_tiles;
	int32_t macro_cell_size_ = 0;
	int32_t macro_halo_ = 0;
	int32_t min_label_cell_size_ = 0;
	int32_t min_cells_per_macro_axis_ = 0;
	int32_t region_min_cells_per_axis_ = 0;
	int64_t macro_cell_x_ = 0;
	int64_t macro_cell_y_ = 0;
	int64_t macro_origin_x_ = 0;
	int64_t macro_origin_y_ = 0;
	int64_t region_origin_display_x_ = 0;
	int64_t region_origin_display_y_ = 0;
	std::unordered_map<std::pair<int64_t, int64_t>, float, Int64PairHash> sample_cache_;
	std::vector<int32_t> region_leaf_index_;
	std::vector<HierarchicalLeafRecord> leaves_;
};

int64_t resolve_macro_local_x(int64_t p_macro_origin_x, int64_t p_world_x, int64_t p_world_wrap_width_tiles) {
	return wrapped_delta_x(p_macro_origin_x, p_world_x, p_world_wrap_width_tiles);
}

int32_t HierarchicalMacroSolve::resolve_mountain_id(int64_t p_world_x, int64_t p_world_y, float p_elevation, float p_edge_threshold) const {
	if (p_elevation < p_edge_threshold) {
		return 0;
	}
	if (min_label_cell_size <= 0 || min_cells_per_macro_axis <= 0) {
		return 0;
	}
	const int64_t local_x = resolve_macro_local_x(macro_origin_x, p_world_x, world_wrap_width_tiles);
	const int64_t local_y = p_world_y - macro_origin_y;
	if (local_x < 0 || local_y < 0 ||
			local_x >= static_cast<int64_t>(macro_cell_size) ||
			local_y >= static_cast<int64_t>(macro_cell_size)) {
		return 0;
	}
	const int32_t min_x = static_cast<int32_t>(local_x / static_cast<int64_t>(min_label_cell_size));
	const int32_t min_y = static_cast<int32_t>(local_y / static_cast<int64_t>(min_label_cell_size));
	const int32_t domain_index = domain_index_per_min_cell[static_cast<size_t>(min_y * min_cells_per_macro_axis + min_x)];
	if (domain_index < 0 || domain_index >= static_cast<int32_t>(domains.size())) {
		return 0;
	}
	return domains[static_cast<size_t>(domain_index)].mountain_id;
}

bool HierarchicalMacroSolve::is_representative_tile(int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) const {
	const int64_t canonical_world_x = wrap_world_x(p_world_x, world_wrap_width_tiles);
	for (const HierarchicalRepresentative &domain : domains) {
		if (domain.mountain_id != p_mountain_id) {
			continue;
		}
		if (domain.representative_tile_x == canonical_world_x && domain.representative_tile_y == p_world_y) {
			return true;
		}
	}
	return false;
}

bool is_spawn_safety_area_at_world(int64_t p_world_version, int64_t p_world_x, int64_t p_world_y) {
	return is_spawn_safety_area_impl(p_world_version, p_world_x, p_world_y);
}

bool uses_hierarchical_labeling(int64_t p_world_version) {
	return p_world_version >= k_hierarchical_world_version;
}

int32_t get_hierarchical_macro_cell_size(int64_t p_world_version) {
	return uses_hierarchical_labeling(p_world_version) ? k_hierarchical_macro_cell_size_v6 : 0;
}

int32_t get_hierarchical_min_label_cell_size(int64_t p_world_version) {
	return uses_hierarchical_labeling(p_world_version) ? k_hierarchical_min_label_cell_size_v6 : 0;
}

HierarchicalMacroSolve solve_hierarchical_macro(
	int64_t p_seed,
	int64_t p_world_version,
	int64_t p_macro_cell_x,
	int64_t p_macro_cell_y,
	const Settings &p_settings
) {
	ERR_FAIL_COND_V_MSG(
		!uses_hierarchical_labeling(p_world_version),
		HierarchicalMacroSolve{},
		"solve_hierarchical_macro requires hierarchical labeling (world_version >= 6)."
	);
	return HierarchicalMacroBuilder(p_seed, p_world_version, p_settings).build(p_macro_cell_x, p_macro_cell_y);
}

} // namespace mountain_field
