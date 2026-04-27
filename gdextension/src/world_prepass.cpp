#include "world_prepass.h"
#include "world_utils.h"

#include "third_party/FastNoiseLite.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <utility>
#include <vector>

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;
using world_utils::splitmix64;
using world_utils::positive_mod;
using world_utils::clamp_value;
using world_utils::saturate;

namespace world_prepass {
namespace {

constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr float SPAWN_MAX_WALL_DENSITY = 0.4f;
constexpr float SPAWN_MIN_VALLEY_SCORE = 0.45f;
constexpr float SPAWN_HYDRO_MIN = 0.28f;
constexpr float SPAWN_HYDRO_MAX = 0.74f;
constexpr float CONTINENT_NOISE_THRESHOLD = 0.28f;
constexpr uint64_t SEED_SALT_CONTINENT = 0xd1b54a32d192ed03ULL;
constexpr uint64_t SEED_SALT_RELIEF = 0x8a5cd789635d2dffULL;
constexpr uint64_t SEED_SALT_REGION = 0xc2b2ae3d27d4eb4fULL;
constexpr int64_t LAYER_MASK_HYDRO_HEIGHT = 1LL << 4;

enum class OverviewTerrainClass {
	Ground,
	MountainFoot,
	MountainWall,
};

uint64_t mix_seed(int64_t p_seed, int64_t p_world_version, uint64_t p_salt) {
	return world_utils::mix_seed(p_seed, p_world_version, p_salt);
}

int make_noise_seed(uint64_t p_value) {
	return static_cast<int>(p_value & 0x7fffffffULL);
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::resolve_mountain_sample_x(p_world_x, p_world_version, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
}

int64_t floor_div(int64_t p_value, int64_t p_divisor) {
	int64_t quotient = p_value / p_divisor;
	const int64_t remainder = p_value % p_divisor;
	if (remainder != 0 && ((remainder < 0) != (p_divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

int64_t resolve_macro_cell_x_for_world(
	int64_t p_world_x,
	int32_t p_macro_cell_size,
	int64_t p_world_wrap_width_tiles
) {
	return floor_div(
		positive_mod(p_world_x, p_world_wrap_width_tiles),
		static_cast<int64_t>(p_macro_cell_size)
	);
}

int64_t resolve_macro_cell_y_for_world(int64_t p_world_y, int32_t p_macro_cell_size) {
	return floor_div(p_world_y, static_cast<int64_t>(p_macro_cell_size));
}

uint64_t make_macro_key(int64_t p_macro_x, int64_t p_macro_y) {
	uint64_t key = splitmix64(static_cast<uint64_t>(p_macro_x));
	key = splitmix64(key ^ static_cast<uint64_t>(p_macro_y) * 0x9e3779b185ebca87ULL);
	return key;
}

int64_t wrap_foundation_world_x(
	int64_t p_world_x,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::wrap_foundation_world_x(
		p_world_x,
		p_foundation_settings.width_tiles,
		p_foundation_settings.enabled
	);
}

bool is_foundation_spawn_safety_area_at_world(
	int64_t p_world_x,
	int64_t p_world_y,
	const FoundationSettings &p_foundation_settings
) {
	if (!p_foundation_settings.enabled) {
		return false;
	}
	const int64_t safe_patch_size = SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1;
	const int64_t habitable_min_y = p_foundation_settings.ocean_band_tiles;
	const int64_t habitable_max_y = p_foundation_settings.height_tiles - p_foundation_settings.burning_band_tiles;
	const int64_t habitable_height = std::max<int64_t>(safe_patch_size, habitable_max_y - habitable_min_y);
	const int64_t start_x = std::max<int64_t>(0, p_foundation_settings.width_tiles / 2 - safe_patch_size / 2);
	const int64_t start_y = habitable_min_y + std::max<int64_t>(0, (habitable_height - safe_patch_size) / 2);
	const int64_t canonical_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	return canonical_x >= start_x && canonical_x < start_x + safe_patch_size &&
			p_world_y >= start_y && p_world_y < start_y + safe_patch_size;
}

FastNoiseLite make_noise(uint64_t p_seed, float p_frequency, int p_octaves = 3) {
	FastNoiseLite noise(make_noise_seed(p_seed));
	noise.SetNoiseType(FastNoiseLite::NoiseType_OpenSimplex2);
	noise.SetFractalType(FastNoiseLite::FractalType_FBm);
	noise.SetFractalOctaves(p_octaves);
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetFrequency(p_frequency);
	return noise;
}

float sample_cylindrical_noise(
	FastNoiseLite &p_noise,
	float p_world_x,
	float p_world_y,
	float p_width_tiles
) {
	constexpr float two_pi = 6.28318530717958647692f;
	const float wrapped_x = std::fmod(std::max(0.0f, p_world_x), std::max(1.0f, p_width_tiles));
	const float theta = (wrapped_x / std::max(1.0f, p_width_tiles)) * two_pi;
	const float radius = std::max(1.0f, p_width_tiles) / two_pi;
	return p_noise.GetNoise(std::cos(theta) * radius, std::sin(theta) * radius, p_world_y);
}

int32_t resolve_region_id(int64_t p_seed, int64_t p_world_version, int32_t p_x, int32_t p_y) {
	uint64_t mixed = mix_seed(p_seed, p_world_version, SEED_SALT_REGION);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_x / 4) * 0x165667b19e3779f9ULL);
	mixed = splitmix64(mixed ^ static_cast<uint64_t>(p_y / 4) * 0x94d049bb133111ebULL);
	return static_cast<int32_t>(mixed & 0x7fffffffULL);
}

PackedFloat32Array make_float_array(const std::vector<float> &p_values) {
	PackedFloat32Array result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

PackedInt32Array make_int_array(const std::vector<int32_t> &p_values) {
	PackedInt32Array result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

PackedByteArray make_byte_array(const std::vector<uint8_t> &p_values) {
	PackedByteArray result;
	result.resize(static_cast<int32_t>(p_values.size()));
	for (int32_t index = 0; index < static_cast<int32_t>(p_values.size()); ++index) {
		result.set(index, p_values[static_cast<size_t>(index)]);
	}
	return result;
}

void write_rgba(PackedByteArray &r_bytes, int32_t p_offset, uint8_t p_r, uint8_t p_g, uint8_t p_b, uint8_t p_a = 255) {
	r_bytes.set(p_offset, p_r);
	r_bytes.set(p_offset + 1, p_g);
	r_bytes.set(p_offset + 2, p_b);
	r_bytes.set(p_offset + 3, p_a);
}

class OverviewTerrainSampler {
public:
	OverviewTerrainSampler(
		int64_t p_seed,
		int64_t p_world_version,
		const mountain_field::Evaluator &p_mountain_evaluator,
		const FoundationSettings &p_foundation_settings
	) :
			seed_(p_seed),
			world_version_(p_world_version),
			mountain_evaluator_(p_mountain_evaluator),
			mountain_settings_(p_mountain_evaluator.get_settings()),
			mountain_thresholds_(p_mountain_evaluator.get_thresholds()),
			foundation_settings_(p_foundation_settings),
			macro_cell_size_(mountain_field::get_hierarchical_macro_cell_size(p_world_version)) {}

	OverviewTerrainClass sample_terrain_class(int64_t p_world_x, int64_t p_world_y) {
		const int64_t sample_world_x = resolve_mountain_sample_x(p_world_x, world_version_, foundation_settings_);
		float elevation = mountain_evaluator_.sample_elevation(sample_world_x, p_world_y);
		if (is_foundation_spawn_safety_area_at_world(p_world_x, p_world_y, foundation_settings_)) {
			elevation = 0.0f;
		}
		if (elevation < mountain_thresholds_.t_edge) {
			return OverviewTerrainClass::Ground;
		}
		if (mountain_field::uses_hierarchical_labeling(world_version_)) {
			const int32_t mountain_id = resolve_mountain_id_at_world(sample_world_x, p_world_y, elevation);
			if (mountain_id <= 0) {
				return OverviewTerrainClass::Ground;
			}
		}
		return elevation >= mountain_thresholds_.t_wall ?
				OverviewTerrainClass::MountainWall :
				OverviewTerrainClass::MountainFoot;
	}

private:
	int32_t resolve_mountain_id_at_world(int64_t p_world_x, int64_t p_world_y, float p_elevation) {
		if (macro_cell_size_ <= 0) {
			return 0;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			p_world_x,
			macro_cell_size_,
			mountain_settings_.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size_);
		const uint64_t macro_key = make_macro_key(macro_cell_x, macro_cell_y);
		auto found = macro_cache_.find(macro_key);
		if (found == macro_cache_.end()) {
			auto insert_result = macro_cache_.emplace(
				macro_key,
				mountain_field::solve_hierarchical_macro(
					seed_,
					world_version_,
					macro_cell_x,
					macro_cell_y,
					mountain_settings_
				)
			);
			found = insert_result.first;
		}
		return found->second.resolve_mountain_id(
			p_world_x,
			p_world_y,
			p_elevation,
			mountain_thresholds_.t_edge
		);
	}

	int64_t seed_ = 0;
	int64_t world_version_ = 0;
	const mountain_field::Evaluator &mountain_evaluator_;
	mountain_field::Settings mountain_settings_;
	const mountain_field::Thresholds &mountain_thresholds_;
	FoundationSettings foundation_settings_;
	int32_t macro_cell_size_ = 0;
	std::unordered_map<uint64_t, mountain_field::HierarchicalMacroSolve> macro_cache_;
};

} // namespace

int32_t Snapshot::index(int32_t p_x, int32_t p_y) const {
	return p_y * grid_width + p_x;
}

Vector2i Snapshot::node_to_tile_center(int32_t p_x, int32_t p_y) const {
	const int64_t x = std::min<int64_t>(width_tiles - 1, static_cast<int64_t>(p_x) * COARSE_CELL_SIZE_TILES + COARSE_CELL_SIZE_TILES / 2);
	const int64_t y = std::min<int64_t>(height_tiles - 1, static_cast<int64_t>(p_y) * COARSE_CELL_SIZE_TILES + COARSE_CELL_SIZE_TILES / 2);
	return Vector2i(static_cast<int32_t>(x), static_cast<int32_t>(y));
}

uint64_t make_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.width_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.height_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.ocean_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.burning_band_tiles));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.pole_orientation));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_foundation_settings.slope_bias + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.density * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.scale * 1000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.continuity * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.ruggedness * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.anchor_cell_size));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.gravity_radius));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_mountain_settings.foot_band * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.interior_margin));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_mountain_settings.latitude_influence + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_mountain_settings.world_wrap_width_tiles));
	return signature;
}

std::unique_ptr<Snapshot> build_snapshot(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	auto started_at = std::chrono::high_resolution_clock::now();
	std::unique_ptr<Snapshot> snapshot = std::make_unique<Snapshot>();
	snapshot->valid = p_foundation_settings.enabled;
	snapshot->seed = p_seed;
	snapshot->world_version = p_world_version;
	snapshot->signature = make_signature(p_seed, p_world_version, p_mountain_settings, p_foundation_settings);
	snapshot->width_tiles = p_foundation_settings.width_tiles;
	snapshot->height_tiles = p_foundation_settings.height_tiles;
	snapshot->ocean_band_tiles = p_foundation_settings.ocean_band_tiles;
	snapshot->burning_band_tiles = p_foundation_settings.burning_band_tiles;
	snapshot->grid_width = std::max<int32_t>(1, static_cast<int32_t>((p_foundation_settings.width_tiles + COARSE_CELL_SIZE_TILES - 1) / COARSE_CELL_SIZE_TILES));
	snapshot->grid_height = std::max<int32_t>(1, static_cast<int32_t>((p_foundation_settings.height_tiles + COARSE_CELL_SIZE_TILES - 1) / COARSE_CELL_SIZE_TILES));

	const int32_t node_count = snapshot->grid_width * snapshot->grid_height;
	snapshot->latitude_t.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->ocean_band_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->burning_band_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->continent_mask.assign(static_cast<size_t>(node_count), 0);
	snapshot->hydro_height.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_wall_density.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_foot_density.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->coarse_valley_score.assign(static_cast<size_t>(node_count), 0.0f);
	snapshot->biome_region_id.assign(static_cast<size_t>(node_count), 0);

	FastNoiseLite continent_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_CONTINENT), 1.0f / 2048.0f, 4);
	FastNoiseLite relief_noise = make_noise(mix_seed(p_seed, p_world_version, SEED_SALT_RELIEF), 1.0f / 1536.0f, 3);
	const mountain_field::Thresholds &thresholds = p_mountain_evaluator.get_thresholds();

	for (int32_t y = 0; y < snapshot->grid_height; ++y) {
		for (int32_t x = 0; x < snapshot->grid_width; ++x) {
			const int32_t index = snapshot->index(x, y);
			const int64_t center_x = snapshot->node_to_tile_center(x, y).x;
			const int64_t center_y = snapshot->node_to_tile_center(x, y).y;
			const float latitude = snapshot->height_tiles <= 1 ?
					0.0f :
					static_cast<float>(center_y) / static_cast<float>(snapshot->height_tiles - 1);
			const bool is_ocean_band = center_y < p_foundation_settings.ocean_band_tiles;
			const bool is_burning_band = center_y >= snapshot->height_tiles - p_foundation_settings.burning_band_tiles;
			const float continent_raw = saturate(
				(sample_cylindrical_noise(continent_noise, static_cast<float>(center_x), static_cast<float>(center_y), static_cast<float>(snapshot->width_tiles)) + 1.0f) * 0.5f
			);
			const bool is_continent = !is_ocean_band && !is_burning_band && continent_raw >= CONTINENT_NOISE_THRESHOLD;

			float elevation_sum = 0.0f;
			int32_t wall_count = 0;
			int32_t foot_count = 0;
			const int32_t sample_steps = 4;
			for (int32_t sample_y = 0; sample_y < sample_steps; ++sample_y) {
				for (int32_t sample_x = 0; sample_x < sample_steps; ++sample_x) {
					const int64_t world_x = static_cast<int64_t>(x) * COARSE_CELL_SIZE_TILES +
							((sample_x * 2 + 1) * COARSE_CELL_SIZE_TILES) / (sample_steps * 2);
					const int64_t world_y = std::min<int64_t>(
						snapshot->height_tiles - 1,
						static_cast<int64_t>(y) * COARSE_CELL_SIZE_TILES +
								((sample_y * 2 + 1) * COARSE_CELL_SIZE_TILES) / (sample_steps * 2)
					);
					const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
					const float elevation = p_mountain_evaluator.sample_elevation(sample_world_x, world_y);
					elevation_sum += elevation;
					if (elevation >= thresholds.t_wall) {
						wall_count += 1;
					} else if (elevation >= thresholds.t_edge) {
						foot_count += 1;
					}
				}
			}

			const float sample_count = static_cast<float>(sample_steps * sample_steps);
			const float mountain_average = elevation_sum / sample_count;
			const float relief = (sample_cylindrical_noise(relief_noise, static_cast<float>(center_x), static_cast<float>(center_y), static_cast<float>(snapshot->width_tiles)) + 1.0f) * 0.5f;
			const float slope = (latitude - 0.5f) * p_foundation_settings.slope_bias * 0.22f;
			const float wall_density = static_cast<float>(wall_count) / sample_count;
			const float foot_density = static_cast<float>(foot_count) / sample_count;
			const float valley = saturate(1.0f - wall_density - 0.5f * foot_density);
			const float hydro = saturate(mountain_average * 0.62f + relief * 0.32f + slope);

			snapshot->latitude_t[static_cast<size_t>(index)] = latitude;
			snapshot->ocean_band_mask[static_cast<size_t>(index)] = is_ocean_band ? 1U : 0U;
			snapshot->burning_band_mask[static_cast<size_t>(index)] = is_burning_band ? 1U : 0U;
			snapshot->continent_mask[static_cast<size_t>(index)] = is_continent ? 1U : 0U;
			snapshot->hydro_height[static_cast<size_t>(index)] = hydro;
			snapshot->coarse_wall_density[static_cast<size_t>(index)] = wall_density;
			snapshot->coarse_foot_density[static_cast<size_t>(index)] = foot_density;
			snapshot->coarse_valley_score[static_cast<size_t>(index)] = valley;
			snapshot->biome_region_id[static_cast<size_t>(index)] = resolve_region_id(p_seed, p_world_version, x, y);
		}
	}

	auto finished_at = std::chrono::high_resolution_clock::now();
	snapshot->compute_time_ms = std::chrono::duration<double, std::milli>(finished_at - started_at).count();
	return snapshot;
}

Dictionary make_debug_snapshot(const Snapshot &p_snapshot, int64_t p_layer_mask, int64_t p_downscale_factor) {
	Dictionary result;
	if (!p_snapshot.valid) {
		return result;
	}
	result["grid_width"] = p_snapshot.grid_width;
	result["grid_height"] = p_snapshot.grid_height;
	result["coarse_cell_size_tiles"] = COARSE_CELL_SIZE_TILES;
	result["world_width_tiles"] = p_snapshot.width_tiles;
	result["world_height_tiles"] = p_snapshot.height_tiles;
	result["ocean_band_tiles"] = p_snapshot.ocean_band_tiles;
	result["burning_band_tiles"] = p_snapshot.burning_band_tiles;
	result["seed"] = p_snapshot.seed;
	result["world_version"] = p_snapshot.world_version;
	result["signature"] = static_cast<int64_t>(p_snapshot.signature & 0x7fffffffffffffffULL);
	result["compute_time_ms"] = p_snapshot.compute_time_ms;
	result["layer_mask"] = p_layer_mask;
	result["downscale_factor"] = std::max<int64_t>(1, p_downscale_factor);
	result["latitude_t"] = make_float_array(p_snapshot.latitude_t);
	result["ocean_band_mask"] = make_byte_array(p_snapshot.ocean_band_mask);
	result["burning_band_mask"] = make_byte_array(p_snapshot.burning_band_mask);
	result["continent_mask"] = make_byte_array(p_snapshot.continent_mask);
	result["hydro_height"] = make_float_array(p_snapshot.hydro_height);
	result["coarse_wall_density"] = make_float_array(p_snapshot.coarse_wall_density);
	result["coarse_foot_density"] = make_float_array(p_snapshot.coarse_foot_density);
	result["coarse_valley_score"] = make_float_array(p_snapshot.coarse_valley_score);
	result["biome_region_id"] = make_int_array(p_snapshot.biome_region_id);
	return result;
}

float sample_snapshot_float_bilinear(
	const std::vector<float> &p_values,
	const Snapshot &p_snapshot,
	float p_x,
	float p_y
) {
	if (p_values.empty() || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return 0.0f;
	}
	const int32_t x0 = static_cast<int32_t>(std::floor(p_x));
	const int32_t y0 = clamp_value(static_cast<int32_t>(std::floor(p_y)), 0, p_snapshot.grid_height - 1);
	const int32_t x1 = x0 + 1;
	const int32_t y1 = clamp_value(y0 + 1, 0, p_snapshot.grid_height - 1);
	const float tx = p_x - static_cast<float>(std::floor(p_x));
	const float ty = p_y - static_cast<float>(std::floor(p_y));
	const int32_t wx0 = static_cast<int32_t>(positive_mod(x0, p_snapshot.grid_width));
	const int32_t wx1 = static_cast<int32_t>(positive_mod(x1, p_snapshot.grid_width));
	const float v00 = p_values[static_cast<size_t>(p_snapshot.index(wx0, y0))];
	const float v10 = p_values[static_cast<size_t>(p_snapshot.index(wx1, y0))];
	const float v01 = p_values[static_cast<size_t>(p_snapshot.index(wx0, y1))];
	const float v11 = p_values[static_cast<size_t>(p_snapshot.index(wx1, y1))];
	const float top = v00 + (v10 - v00) * tx;
	const float bottom = v01 + (v11 - v01) * tx;
	return top + (bottom - top) * ty;
}

void write_overview_rgba(
	PackedByteArray &r_bytes,
	int32_t p_offset,
	float p_hydro,
	float p_foot_density,
	float p_wall_density
) {
	const float hydro = saturate(p_hydro);
	const float foot = saturate(p_foot_density);
	const float wall = saturate(p_wall_density);
	if (wall > 0.0f) {
		const float rock = clamp_value(164.0f + wall * 74.0f, 0.0f, 255.0f);
		write_rgba(
			r_bytes,
			p_offset,
			static_cast<uint8_t>(rock),
			static_cast<uint8_t>(std::max(0.0f, rock - 4.0f)),
			static_cast<uint8_t>(std::max(0.0f, rock - 18.0f))
		);
		return;
	}
	if (foot > 0.0f) {
		const float lift = std::min(72.0f, foot * 120.0f);
		write_rgba(
			r_bytes,
			p_offset,
			static_cast<uint8_t>(clamp_value(106.0f + lift, 0.0f, 255.0f)),
			static_cast<uint8_t>(clamp_value(98.0f + lift * 0.62f, 0.0f, 255.0f)),
			static_cast<uint8_t>(clamp_value(74.0f + lift * 0.38f, 0.0f, 255.0f))
		);
		return;
	}
	const float base = clamp_value(42.0f + hydro * 24.0f, 0.0f, 255.0f);
	write_rgba(
		r_bytes,
		p_offset,
		static_cast<uint8_t>(base),
		static_cast<uint8_t>(std::min(255.0f, base + 18.0f)),
		static_cast<uint8_t>(std::max(0.0f, base - 4.0f))
	);
}

void write_height_rgba(PackedByteArray &r_bytes, int32_t p_offset, float p_hydro) {
	const float height = saturate(p_hydro);
	float r0 = 24.0f;
	float g0 = 38.0f;
	float b0 = 60.0f;
	float r1 = 58.0f;
	float g1 = 96.0f;
	float b1 = 86.0f;
	float segment_t = height / 0.42f;
	if (height > 0.42f) {
		r0 = r1;
		g0 = g1;
		b0 = b1;
		r1 = 156.0f;
		g1 = 132.0f;
		b1 = 82.0f;
		segment_t = (height - 0.42f) / 0.33f;
	}
	if (height > 0.75f) {
		r0 = r1;
		g0 = g1;
		b0 = b1;
		r1 = 235.0f;
		g1 = 230.0f;
		b1 = 202.0f;
		segment_t = (height - 0.75f) / 0.25f;
	}
	const float t = saturate(segment_t);
	write_rgba(
		r_bytes,
		p_offset,
		static_cast<uint8_t>(clamp_value(r0 + (r1 - r0) * t, 0.0f, 255.0f)),
		static_cast<uint8_t>(clamp_value(g0 + (g1 - g0) * t, 0.0f, 255.0f)),
		static_cast<uint8_t>(clamp_value(b0 + (b1 - b0) * t, 0.0f, 255.0f))
	);
}

Ref<Image> make_overview_image(
	const Snapshot &p_snapshot,
	const mountain_field::Evaluator &p_mountain_evaluator,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	int64_t p_layer_mask,
	int64_t p_pixels_per_cell
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return Ref<Image>();
	}
	const int32_t pixels_per_cell = clamp_value(static_cast<int32_t>(p_pixels_per_cell), 1, 8);
	const int32_t pixel_window_tiles = COARSE_CELL_SIZE_TILES / pixels_per_cell;
	constexpr int32_t pixel_sample_steps = 4;
	const int32_t image_width = p_snapshot.grid_width * pixels_per_cell;
	const int32_t image_height = p_snapshot.grid_height * pixels_per_cell;
	PackedByteArray bytes;
	bytes.resize(image_width * image_height * 4);
	const bool render_hydro_height = (p_layer_mask & LAYER_MASK_HYDRO_HEIGHT) != 0;
	if (render_hydro_height) {
		for (int32_t y = 0; y < image_height; ++y) {
			for (int32_t x = 0; x < image_width; ++x) {
				const float coarse_sample_x = (static_cast<float>(x) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
				const float coarse_sample_y = (static_cast<float>(y) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
				write_height_rgba(
					bytes,
					(y * image_width + x) * 4,
					sample_snapshot_float_bilinear(p_snapshot.hydro_height, p_snapshot, coarse_sample_x, coarse_sample_y)
				);
			}
		}
		return Image::create_from_data(image_width, image_height, false, Image::FORMAT_RGBA8, bytes);
	}
	OverviewTerrainSampler terrain_sampler(p_snapshot.seed, p_world_version, p_mountain_evaluator, p_foundation_settings);
	for (int32_t y = 0; y < image_height; ++y) {
		for (int32_t x = 0; x < image_width; ++x) {
			const float coarse_sample_x = (static_cast<float>(x) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
			const float coarse_sample_y = (static_cast<float>(y) + 0.5f) / static_cast<float>(pixels_per_cell) - 0.5f;
			const int64_t pixel_origin_tile_x = static_cast<int64_t>(x) * pixel_window_tiles;
			const int64_t pixel_origin_tile_y = static_cast<int64_t>(y) * pixel_window_tiles;
			int32_t wall_count = 0;
			int32_t foot_count = 0;
			for (int32_t sample_y = 0; sample_y < pixel_sample_steps; ++sample_y) {
				for (int32_t sample_x = 0; sample_x < pixel_sample_steps; ++sample_x) {
					const int64_t world_x = pixel_origin_tile_x +
							((sample_x * 2 + 1) * pixel_window_tiles) / (pixel_sample_steps * 2);
					const int64_t world_y_raw = pixel_origin_tile_y +
							((sample_y * 2 + 1) * pixel_window_tiles) / (pixel_sample_steps * 2);
					const int64_t world_y = std::min<int64_t>(p_snapshot.height_tiles - 1, world_y_raw);
					const OverviewTerrainClass terrain_class = terrain_sampler.sample_terrain_class(world_x, world_y);
					if (terrain_class == OverviewTerrainClass::MountainWall) {
						++wall_count;
					} else if (terrain_class == OverviewTerrainClass::MountainFoot) {
						++foot_count;
					}
				}
			}
			const float pixel_wall_density = static_cast<float>(wall_count) /
					static_cast<float>(pixel_sample_steps * pixel_sample_steps);
			const float pixel_foot_density = static_cast<float>(foot_count) /
					static_cast<float>(pixel_sample_steps * pixel_sample_steps);
			write_overview_rgba(
				bytes,
				(y * image_width + x) * 4,
				sample_snapshot_float_bilinear(p_snapshot.hydro_height, p_snapshot, coarse_sample_x, coarse_sample_y),
				pixel_foot_density,
				pixel_wall_density
			);
		}
	}
	return Image::create_from_data(image_width, image_height, false, Image::FORMAT_RGBA8, bytes);
}

Dictionary resolve_spawn_tile(const Snapshot &p_snapshot) {
	Dictionary result;
	if (!p_snapshot.valid) {
		result["success"] = false;
		result["message"] = "WorldPrePass snapshot is not valid.";
		return result;
	}

	float best_score = -std::numeric_limits<float>::infinity();
	int32_t best_index = -1;
	for (int32_t index = 0; index < p_snapshot.grid_width * p_snapshot.grid_height; ++index) {
		if (p_snapshot.ocean_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.burning_band_mask[static_cast<size_t>(index)] != 0 ||
				p_snapshot.continent_mask[static_cast<size_t>(index)] == 0 ||
				p_snapshot.coarse_wall_density[static_cast<size_t>(index)] >= SPAWN_MAX_WALL_DENSITY) {
			continue;
		}
		const float valley = p_snapshot.coarse_valley_score[static_cast<size_t>(index)];
		const float hydro = p_snapshot.hydro_height[static_cast<size_t>(index)];
		const float hydro_mid = 1.0f - saturate(std::abs(hydro - 0.52f) / 0.52f);
		const float wall_penalty = p_snapshot.coarse_wall_density[static_cast<size_t>(index)] * 0.75f;
		const bool preferred_band = valley >= SPAWN_MIN_VALLEY_SCORE && hydro >= SPAWN_HYDRO_MIN && hydro <= SPAWN_HYDRO_MAX;
		const float score = valley * 1.8f + hydro_mid * 0.9f - wall_penalty + (preferred_band ? 0.65f : 0.0f);
		if (score > best_score) {
			best_score = score;
			best_index = index;
		}
	}

	if (best_index < 0) {
		result["success"] = false;
		result["message"] = "No valid foundation spawn node found.";
		return result;
	}

	const int32_t node_x = best_index % p_snapshot.grid_width;
	const int32_t node_y = best_index / p_snapshot.grid_width;
	const Vector2i spawn_tile = p_snapshot.node_to_tile_center(node_x, node_y);
	const int32_t patch_size = static_cast<int32_t>(SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1);
	const int32_t rect_x = static_cast<int32_t>(clamp_value<int64_t>(
		static_cast<int64_t>(spawn_tile.x) - patch_size / 2,
		0,
		std::max<int64_t>(0, p_snapshot.width_tiles - patch_size)
	));
	const int32_t rect_y = static_cast<int32_t>(clamp_value<int64_t>(
		static_cast<int64_t>(spawn_tile.y) - patch_size / 2,
		0,
		std::max<int64_t>(0, p_snapshot.height_tiles - patch_size)
	));

	result["success"] = true;
	result["spawn_tile"] = spawn_tile;
	result["spawn_safe_patch_rect"] = Rect2i(Vector2i(rect_x, rect_y), Vector2i(patch_size, patch_size));
	result["node_coord"] = Vector2i(node_x, node_y);
	result["score"] = best_score;
	result["coarse_valley_score"] = p_snapshot.coarse_valley_score[static_cast<size_t>(best_index)];
	result["hydro_height"] = p_snapshot.hydro_height[static_cast<size_t>(best_index)];
	result["coarse_wall_density"] = p_snapshot.coarse_wall_density[static_cast<size_t>(best_index)];
	return result;
}

} // namespace world_prepass
