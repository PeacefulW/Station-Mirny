#include "mountain_field.h"

#include "autotile_47.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace mountain_field {

namespace {

constexpr float k_pi = 3.14159265358979323846f;
constexpr float k_two_pi = 2.0f * k_pi;
constexpr float k_world_wrap_width_tiles = 65536.0f;

constexpr uint8_t k_flag_interior = 1U << 0U;
constexpr uint8_t k_flag_wall = 1U << 1U;
constexpr uint8_t k_flag_foot = 1U << 2U;
constexpr uint8_t k_flag_anchor = 1U << 3U;

constexpr uint64_t k_seed_salt_domain_warp = 0x5f8d6d2c0a7b91f3ULL;
constexpr uint64_t k_seed_salt_macro = 0x3bd39e10cb0ef593ULL;
constexpr uint64_t k_seed_salt_ridge = 0xa2c6d11f74b93ce5ULL;
constexpr uint64_t k_seed_salt_anchor_jitter = 0x4f9939c52dba41d1ULL;
constexpr uint64_t k_seed_salt_anchor_id = 0x6f27d13a2b4c5e91ULL;

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

void project_wrapped_x_to_cylinder(int64_t p_world_x, int64_t p_world_y, float &r_out_x, float &r_out_y, float &r_out_z) {
	float wrapped_x = std::fmod(static_cast<float>(p_world_x), k_world_wrap_width_tiles);
	if (wrapped_x < 0.0f) {
		wrapped_x += k_world_wrap_width_tiles;
	}
	const float theta = (wrapped_x / k_world_wrap_width_tiles) * k_two_pi;
	const float radius = k_world_wrap_width_tiles / k_two_pi;
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

int32_t make_anchor_mountain_id(int64_t p_seed, int64_t p_world_version, int64_t p_anchor_x, int64_t p_anchor_y) {
	uint64_t mixed = mix_seed(p_seed, p_world_version, k_seed_salt_anchor_id);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_anchor_x) * 0xc2b2ae3d27d4eb4fULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_anchor_y) * 0x165667b19e3779f9ULL);
	const int32_t id = static_cast<int32_t>(mixed & 0x7fffffffULL);
	return id == 0 ? 1 : id;
}

int32_t chebyshev_distance(int64_t p_ax, int64_t p_ay, int64_t p_bx, int64_t p_by) {
	const int64_t dx = std::llabs(p_ax - p_bx);
	const int64_t dy = std::llabs(p_ay - p_by);
	return static_cast<int32_t>(std::max(dx, dy));
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
	float sample_x = 0.0f;
	float sample_y = 0.0f;
	float sample_z = 0.0f;
	project_wrapped_x_to_cylinder(p_world_x, p_world_y, sample_x, sample_y, sample_z);
	domain_warp_noise_.DomainWarp(sample_x, sample_y, sample_z);

	const float macro_raw = macro_noise_.GetNoise(sample_x, sample_y, sample_z);
	const float macro = saturate((macro_raw + 1.0f) * 0.5f);

	const float ridge_raw = ridge_noise_.GetNoise(sample_x, sample_y, sample_z);
	const float ridge = 1.0f - std::abs(ridge_raw);
	const float ridge_gate = smoothstep(0.35f, 0.8f, macro);

	const float latitude = std::tanh(static_cast<float>(p_world_y) / 4096.0f);
	const float latitude_bias = latitude * settings_.latitude_influence * 0.12f;
	const float elevation = macro + ridge_gate * ridge * settings_.ruggedness * 0.28f + latitude_bias;
	return saturate(elevation);
}

int32_t Evaluator::resolve_mountain_id(int64_t p_world_x, int64_t p_world_y) const {
	return resolve_mountain_id(p_world_x, p_world_y, sample_elevation(p_world_x, p_world_y));
}

int32_t Evaluator::resolve_mountain_id(int64_t p_world_x, int64_t p_world_y, float p_elevation) const {
	if (p_elevation < thresholds_.t_edge) {
		return 0;
	}

	const int64_t anchor_cell_x = floor_div(p_world_x, settings_.anchor_cell_size);
	const int64_t anchor_cell_y = floor_div(p_world_y, settings_.anchor_cell_size);

	int32_t best_distance = settings_.gravity_radius + 1;
	int32_t best_mountain_id = 0;

	for (int64_t offset_y = -1; offset_y <= 1; ++offset_y) {
		for (int64_t offset_x = -1; offset_x <= 1; ++offset_x) {
			const int64_t candidate_cell_x = anchor_cell_x + offset_x;
			const int64_t candidate_cell_y = anchor_cell_y + offset_y;

			uint64_t jitter_seed = mix_seed(seed_, world_version_, k_seed_salt_anchor_jitter);
			jitter_seed = splitmix64(jitter_seed ^ static_cast<uint64_t>(candidate_cell_x) * 0x517cc1b727220a95ULL);
			jitter_seed = splitmix64(jitter_seed ^ static_cast<uint64_t>(candidate_cell_y) * 0x6eed0e9da4d94a4fULL);

			const int64_t local_x = static_cast<int64_t>(jitter_seed % static_cast<uint64_t>(settings_.anchor_cell_size));
			const int64_t local_y = static_cast<int64_t>((jitter_seed >> 16U) % static_cast<uint64_t>(settings_.anchor_cell_size));
			const int64_t anchor_world_x = candidate_cell_x * settings_.anchor_cell_size + local_x;
			const int64_t anchor_world_y = candidate_cell_y * settings_.anchor_cell_size + local_y;

			const float anchor_elevation = sample_elevation(anchor_world_x, anchor_world_y);
			if (anchor_elevation < thresholds_.t_anchor) {
				continue;
			}

			const int32_t distance = chebyshev_distance(anchor_world_x, anchor_world_y, p_world_x, p_world_y);
			if (distance > settings_.gravity_radius || distance >= best_distance) {
				continue;
			}

			best_distance = distance;
			best_mountain_id = make_anchor_mountain_id(seed_, world_version_, candidate_cell_x, candidate_cell_y);
		}
	}

	return best_mountain_id;
}

bool Evaluator::is_anchor_tile(int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) const {
	if (p_mountain_id == 0) {
		return false;
	}
	const int64_t anchor_cell_x = floor_div(p_world_x, settings_.anchor_cell_size);
	const int64_t anchor_cell_y = floor_div(p_world_y, settings_.anchor_cell_size);

	uint64_t jitter_seed = mix_seed(seed_, world_version_, k_seed_salt_anchor_jitter);
	jitter_seed = splitmix64(jitter_seed ^ static_cast<uint64_t>(anchor_cell_x) * 0x517cc1b727220a95ULL);
	jitter_seed = splitmix64(jitter_seed ^ static_cast<uint64_t>(anchor_cell_y) * 0x6eed0e9da4d94a4fULL);

	const int64_t local_x = static_cast<int64_t>(jitter_seed % static_cast<uint64_t>(settings_.anchor_cell_size));
	const int64_t local_y = static_cast<int64_t>((jitter_seed >> 16U) % static_cast<uint64_t>(settings_.anchor_cell_size));
	const int64_t anchor_world_x = anchor_cell_x * settings_.anchor_cell_size + local_x;
	const int64_t anchor_world_y = anchor_cell_y * settings_.anchor_cell_size + local_y;
	if (anchor_world_x != p_world_x || anchor_world_y != p_world_y) {
		return false;
	}
	if (sample_elevation(anchor_world_x, anchor_world_y) < thresholds_.t_anchor) {
		return false;
	}
	return make_anchor_mountain_id(seed_, world_version_, anchor_cell_x, anchor_cell_y) == p_mountain_id;
}

uint8_t Evaluator::resolve_mountain_flags(
	int64_t p_world_x,
	int64_t p_world_y,
	float p_elevation,
	int32_t p_center_mountain_id,
	int32_t p_north_mountain_id,
	int32_t p_east_mountain_id,
	int32_t p_south_mountain_id,
	int32_t p_west_mountain_id
) const {
	uint8_t flags = 0U;
	const bool is_wall = p_elevation >= thresholds_.t_wall;
	const bool is_foot = p_elevation >= thresholds_.t_edge && p_elevation < thresholds_.t_wall;
	if (is_wall) {
		flags = static_cast<uint8_t>(flags | k_flag_wall);
	}
	if (is_foot) {
		flags = static_cast<uint8_t>(flags | k_flag_foot);
	}

	if (p_center_mountain_id > 0 && is_wall) {
		bool is_interior = settings_.interior_margin == 0;
		if (settings_.interior_margin > 0) {
			is_interior = true;
			for (int32_t distance = 1; distance <= settings_.interior_margin; ++distance) {
				const int64_t north_world_y = p_world_y - distance;
				const int64_t east_world_x = p_world_x + distance;
				const int64_t south_world_y = p_world_y + distance;
				const int64_t west_world_x = p_world_x - distance;

				const int32_t north_id = distance == 1 ? p_north_mountain_id : resolve_mountain_id(p_world_x, north_world_y);
				const int32_t east_id = distance == 1 ? p_east_mountain_id : resolve_mountain_id(east_world_x, p_world_y);
				const int32_t south_id = distance == 1 ? p_south_mountain_id : resolve_mountain_id(p_world_x, south_world_y);
				const int32_t west_id = distance == 1 ? p_west_mountain_id : resolve_mountain_id(west_world_x, p_world_y);

				if (north_id != p_center_mountain_id ||
						east_id != p_center_mountain_id ||
						south_id != p_center_mountain_id ||
						west_id != p_center_mountain_id) {
					is_interior = false;
					break;
				}

				if (sample_elevation(p_world_x, north_world_y) < thresholds_.t_wall ||
						sample_elevation(east_world_x, p_world_y) < thresholds_.t_wall ||
						sample_elevation(p_world_x, south_world_y) < thresholds_.t_wall ||
						sample_elevation(west_world_x, p_world_y) < thresholds_.t_wall) {
					is_interior = false;
					break;
				}
			}
		}
		if (is_interior) {
			flags = static_cast<uint8_t>(flags | k_flag_interior);
		}
		if (is_anchor_tile(p_world_x, p_world_y, p_center_mountain_id)) {
			flags = static_cast<uint8_t>(flags | k_flag_anchor);
		}
	}

	return flags;
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

float sample_elevation(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings) {
	return Evaluator(p_seed, p_world_version, p_settings).sample_elevation(p_world_x, p_world_y);
}

int32_t resolve_mountain_id(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings) {
	return Evaluator(p_seed, p_world_version, p_settings).resolve_mountain_id(p_world_x, p_world_y);
}

uint8_t resolve_mountain_flags(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings) {
	const Evaluator evaluator(p_seed, p_world_version, p_settings);
	const float elevation = evaluator.sample_elevation(p_world_x, p_world_y);
	const int32_t center_mountain_id = evaluator.resolve_mountain_id(p_world_x, p_world_y, elevation);
	return evaluator.resolve_mountain_flags(
		p_world_x,
		p_world_y,
		elevation,
		center_mountain_id,
		evaluator.resolve_mountain_id(p_world_x, p_world_y - 1),
		evaluator.resolve_mountain_id(p_world_x + 1, p_world_y),
		evaluator.resolve_mountain_id(p_world_x, p_world_y + 1),
		evaluator.resolve_mountain_id(p_world_x - 1, p_world_y)
	);
}

int32_t resolve_mountain_atlas_index(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings) {
	const Evaluator evaluator(p_seed, p_world_version, p_settings);
	const int32_t center_mountain_id = evaluator.resolve_mountain_id(p_world_x, p_world_y);
	return evaluator.resolve_mountain_atlas_index(
		p_world_x,
		p_world_y,
		center_mountain_id,
		evaluator.resolve_mountain_id(p_world_x, p_world_y - 1),
		evaluator.resolve_mountain_id(p_world_x + 1, p_world_y - 1),
		evaluator.resolve_mountain_id(p_world_x + 1, p_world_y),
		evaluator.resolve_mountain_id(p_world_x + 1, p_world_y + 1),
		evaluator.resolve_mountain_id(p_world_x, p_world_y + 1),
		evaluator.resolve_mountain_id(p_world_x - 1, p_world_y + 1),
		evaluator.resolve_mountain_id(p_world_x - 1, p_world_y),
		evaluator.resolve_mountain_id(p_world_x - 1, p_world_y - 1)
	);
}

} // namespace mountain_field
