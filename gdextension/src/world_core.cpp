#include "world_core.h"
#include "autotile_47.h"
#include "mountain_field.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int64_t TERRAIN_MOUNTAIN_FOOT = 4;

constexpr int64_t SETTINGS_PACKED_LAYOUT_DENSITY = 0;
constexpr int64_t SETTINGS_PACKED_LAYOUT_SCALE = 1;
constexpr int64_t SETTINGS_PACKED_LAYOUT_CONTINUITY = 2;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RUGGEDNESS = 3;
constexpr int64_t SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE = 4;
constexpr int64_t SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS = 5;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FOOT_BAND = 6;
constexpr int64_t SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN = 7;
constexpr int64_t SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE = 8;
constexpr int64_t SETTINGS_PACKED_LAYOUT_MOUNTAIN_FIELD_COUNT = 9;
constexpr int64_t SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES = 9;
constexpr int64_t SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES = 10;
constexpr int64_t SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES = 11;
constexpr int64_t SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES = 12;
constexpr int64_t SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION = 13;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS = 14;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_AMOUNT = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 16;

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;
constexpr uint8_t MOUNTAIN_FLAG_INTERIOR = 1U << 0U;
constexpr uint8_t MOUNTAIN_FLAG_ANCHOR = 1U << 3U;
constexpr int64_t LEGACY_WORLD_WRAP_WIDTH_TILES = 65536;
constexpr int64_t WORLD_FOUNDATION_VERSION = 9;
constexpr int64_t MOUNTAIN_FINITE_WIDTH_VERSION = 10;
constexpr int64_t FOUNDATION_CHUNK_SIZE = 32;
constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr size_t HIERARCHICAL_CACHE_LIMIT = 64;

uint64_t splitmix64(uint64_t x) {
	x += 0x9e3779b97f4a7c15ULL;
	x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
	x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
	return x ^ (x >> 31U);
}

int64_t positive_mod(int64_t p_value, int64_t p_modulus) {
	if (p_modulus <= 0) {
		return p_value;
	}
	int64_t result = p_value % p_modulus;
	if (result < 0) {
		result += p_modulus;
	}
	return result;
}

int64_t wrap_foundation_world_x(int64_t p_world_x, const FoundationSettings &p_foundation_settings) {
	if (!p_foundation_settings.enabled) {
		return p_world_x;
	}
	return positive_mod(p_world_x, p_foundation_settings.width_tiles);
}

int64_t clamp_foundation_world_y(int64_t p_world_y, const FoundationSettings &p_foundation_settings) {
	if (!p_foundation_settings.enabled) {
		return p_world_y;
	}
	return std::max<int64_t>(0, std::min<int64_t>(p_world_y, p_foundation_settings.height_tiles - 1));
}

int64_t map_foundation_x_to_legacy_sample(int64_t p_world_x, const FoundationSettings &p_foundation_settings) {
	if (!p_foundation_settings.enabled) {
		return p_world_x;
	}
	const int64_t wrapped_x = wrap_foundation_world_x(p_world_x, p_foundation_settings);
	return static_cast<int64_t>(std::llround(
		(static_cast<double>(wrapped_x) * static_cast<double>(LEGACY_WORLD_WRAP_WIDTH_TILES)) /
		static_cast<double>(p_foundation_settings.width_tiles)
	));
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	if (!p_foundation_settings.enabled) {
		return p_world_x;
	}
	if (p_world_version < MOUNTAIN_FINITE_WIDTH_VERSION) {
		return map_foundation_x_to_legacy_sample(p_world_x, p_foundation_settings);
	}
	return wrap_foundation_world_x(p_world_x, p_foundation_settings);
}

Vector2i canonicalize_chunk_coord(Vector2i p_coord, const FoundationSettings &p_foundation_settings) {
	if (!p_foundation_settings.enabled) {
		return p_coord;
	}
	const int64_t width_chunks = std::max<int64_t>(1, p_foundation_settings.width_tiles / FOUNDATION_CHUNK_SIZE);
	const int64_t height_chunks = std::max<int64_t>(1, p_foundation_settings.height_tiles / FOUNDATION_CHUNK_SIZE);
	return Vector2i(
		static_cast<int32_t>(positive_mod(p_coord.x, width_chunks)),
		static_cast<int32_t>(std::max<int64_t>(0, std::min<int64_t>(p_coord.y, height_chunks - 1)))
	);
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

int64_t resolve_base_ground_atlas_index(int64_t world_x, int64_t world_y, int64_t seed) {
	// TODO: switch plains-ground edge solving to water adjacency once water
	// terrain exists. For now, ground always uses solid atlas variants only.
	return autotile_47::resolve_atlas_index(
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		world_x,
		world_y,
		seed
	);
}

int64_t resolve_mountain_base_atlas_index(
	int64_t seed,
	int64_t world_x,
	int64_t world_y,
	bool north,
	bool north_east,
	bool east,
	bool south_east,
	bool south,
	bool south_west,
	bool west,
	bool north_west
) {
	return autotile_47::resolve_atlas_index(
		north,
		north_east,
		east,
		south_east,
		south,
		south_west,
		west,
		north_west,
		world_x,
		world_y,
		seed
	);
}

mountain_field::Settings unpack_mountain_settings(const PackedFloat32Array &p_settings_packed) {
	mountain_field::Settings settings;
	settings.density = p_settings_packed[SETTINGS_PACKED_LAYOUT_DENSITY];
	settings.scale = p_settings_packed[SETTINGS_PACKED_LAYOUT_SCALE];
	settings.continuity = p_settings_packed[SETTINGS_PACKED_LAYOUT_CONTINUITY];
	settings.ruggedness = p_settings_packed[SETTINGS_PACKED_LAYOUT_RUGGEDNESS];
	settings.anchor_cell_size = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE]));
	settings.gravity_radius = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS]));
	settings.foot_band = p_settings_packed[SETTINGS_PACKED_LAYOUT_FOOT_BAND];
	settings.interior_margin = static_cast<int32_t>(std::lround(p_settings_packed[SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN]));
	settings.latitude_influence = p_settings_packed[SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE];
	return settings;
}

mountain_field::Settings make_effective_mountain_settings(
	int64_t p_world_version,
	mountain_field::Settings p_settings,
	const FoundationSettings &p_foundation_settings
) {
	if (p_foundation_settings.enabled && p_world_version >= MOUNTAIN_FINITE_WIDTH_VERSION) {
		p_settings.world_wrap_width_tiles = p_foundation_settings.width_tiles;
	} else {
		p_settings.world_wrap_width_tiles = LEGACY_WORLD_WRAP_WIDTH_TILES;
	}
	return p_settings;
}

FoundationSettings unpack_foundation_settings(int64_t p_world_version, const PackedFloat32Array &p_settings_packed) {
	FoundationSettings settings;
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return settings;
	}
	settings.enabled = true;
	settings.width_tiles = std::max<int64_t>(
		FOUNDATION_CHUNK_SIZE,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES]))
	);
	settings.height_tiles = std::max<int64_t>(
		FOUNDATION_CHUNK_SIZE,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES]))
	);
	settings.ocean_band_tiles = std::max<int64_t>(
		0,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES]))
	);
	settings.burning_band_tiles = std::max<int64_t>(
		0,
		static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES]))
	);
	settings.pole_orientation = static_cast<int64_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION]));
	settings.slope_bias = p_settings_packed[SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS];
	settings.river_amount = p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_AMOUNT];
	return settings;
}

int64_t expected_settings_count_for_version(int64_t p_world_version) {
	return p_world_version >= WORLD_FOUNDATION_VERSION ?
			SETTINGS_PACKED_LAYOUT_FIELD_COUNT :
			SETTINGS_PACKED_LAYOUT_MOUNTAIN_FIELD_COUNT;
}

Dictionary make_failure_result(const char *p_message) {
	Dictionary result;
	result["success"] = false;
	result["message"] = p_message;
	return result;
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

uint64_t make_cache_signature(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings,
	const FoundationSettings &p_foundation_settings
) {
	uint64_t signature = splitmix64(static_cast<uint64_t>(p_seed));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.density * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.scale * 1000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.continuity * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.ruggedness * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.anchor_cell_size));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.gravity_radius));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_settings.foot_band * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.interior_margin));
	signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_settings.latitude_influence + 1.0f) * 1000000.0f)));
	signature = splitmix64(signature ^ static_cast<uint64_t>(p_settings.world_wrap_width_tiles));
	if (p_foundation_settings.enabled) {
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.width_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.height_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.ocean_band_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.burning_band_tiles));
		signature = splitmix64(signature ^ static_cast<uint64_t>(p_foundation_settings.pole_orientation));
		signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround((p_foundation_settings.slope_bias + 1.0f) * 1000000.0f)));
		signature = splitmix64(signature ^ static_cast<uint64_t>(std::lround(p_foundation_settings.river_amount * 1000000.0f)));
	}
	return signature;
}

uint64_t make_macro_key(int64_t p_macro_x, int64_t p_macro_y) {
	uint64_t key = splitmix64(static_cast<uint64_t>(p_macro_x));
	key = splitmix64(key ^ static_cast<uint64_t>(p_macro_y) * 0x9e3779b185ebca87ULL);
	return key;
}

struct ChunkMacroGroup {
	int64_t macro_cell_x = 0;
	int64_t macro_cell_y = 0;
	std::vector<int32_t> chunk_indices;
};

} // namespace

struct WorldCore::HierarchicalMacroCache {
	struct Entry {
		uint64_t last_used_tick = 0;
		mountain_field::HierarchicalMacroSolve solve;
	};

	uint64_t signature = 0;
	uint64_t tick = 0;
	std::unordered_map<uint64_t, Entry> entries;
};

void WorldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_chunk_packets_batch", "seed", "coords", "world_version", "settings_packed"), &WorldCore::generate_chunk_packets_batch);
	ClassDB::bind_method(D_METHOD("resolve_world_foundation_spawn_tile", "seed", "world_version", "settings_packed"), &WorldCore::resolve_world_foundation_spawn_tile);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_world_foundation_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_foundation_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_foundation_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_foundation_overview, DEFVAL(1));
#endif
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()),
		world_prepass_snapshot_(std::make_unique<world_prepass::Snapshot>()) {}

WorldCore::~WorldCore() = default;

const mountain_field::HierarchicalMacroSolve &WorldCore::_get_or_build_hierarchical_macro_solve(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Settings &p_settings,
	const FoundationSettings &p_foundation_settings,
	int64_t p_macro_cell_x,
	int64_t p_macro_cell_y
) {
	HierarchicalMacroCache &cache = *hierarchical_macro_cache_;
	const uint64_t signature = make_cache_signature(p_seed, p_world_version, p_settings, p_foundation_settings);
	if (cache.signature != signature) {
		cache.signature = signature;
		cache.tick = 0;
		cache.entries.clear();
	}

	cache.tick += 1;
	const uint64_t key = make_macro_key(p_macro_cell_x, p_macro_cell_y);
	auto found = cache.entries.find(key);
	if (found != cache.entries.end()) {
		found->second.last_used_tick = cache.tick;
		return found->second.solve;
	}

	HierarchicalMacroCache::Entry entry;
	entry.last_used_tick = cache.tick;
	entry.solve = mountain_field::solve_hierarchical_macro(
		p_seed,
		p_world_version,
		p_macro_cell_x,
		p_macro_cell_y,
		p_settings
	);
	auto insert_result = cache.entries.emplace(key, std::move(entry));
	auto inserted = insert_result.first;

	if (cache.entries.size() > HIERARCHICAL_CACHE_LIMIT) {
		auto lru = cache.entries.end();
		for (auto iter = cache.entries.begin(); iter != cache.entries.end(); ++iter) {
			if (iter == inserted) {
				continue;
			}
			if (lru == cache.entries.end() || iter->second.last_used_tick < lru->second.last_used_tick) {
				lru = iter;
			}
		}
		if (lru != cache.entries.end()) {
			cache.entries.erase(lru);
		}
	}

	return inserted->second.solve;
}

const world_prepass::Snapshot &WorldCore::_get_or_build_world_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	const uint64_t signature = world_prepass::make_signature(
		p_seed,
		p_world_version,
		p_effective_mountain_settings,
		p_foundation_settings
	);
	if (world_prepass_snapshot_ == nullptr ||
			!world_prepass_snapshot_->valid ||
			world_prepass_snapshot_->signature != signature) {
		world_prepass_snapshot_ = world_prepass::build_snapshot(
			p_seed,
			p_world_version,
			p_mountain_evaluator,
			p_effective_mountain_settings,
			p_foundation_settings
		);
	}
	return *world_prepass_snapshot_;
}

Dictionary WorldCore::_generate_chunk_packet(
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings
) {
	p_coord = canonicalize_chunk_coord(p_coord, p_foundation_settings);
	PackedInt32Array terrain_ids;
	terrain_ids.resize(CELL_COUNT);
	PackedInt32Array terrain_atlas_indices;
	terrain_atlas_indices.resize(CELL_COUNT);
	PackedByteArray walkable_flags;
	walkable_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_id_per_tile;
	mountain_id_per_tile.resize(CELL_COUNT);
	PackedByteArray mountain_flags;
	mountain_flags.resize(CELL_COUNT);
	PackedInt32Array mountain_atlas_indices;
	mountain_atlas_indices.resize(CELL_COUNT);

	const mountain_field::Thresholds &mountain_thresholds = p_mountain_evaluator.get_thresholds();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	const int64_t mountain_border = std::max<int64_t>(1, p_effective_mountain_settings.interior_margin);
	const int64_t mountain_grid_side = CHUNK_SIZE + mountain_border * 2;
	std::vector<float> mountain_elevations(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0.0f);
	std::vector<int32_t> mountain_ids(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0);

	const mountain_field::HierarchicalMacroSolve *cached_macro_solve = nullptr;
	int64_t cached_macro_cell_x = std::numeric_limits<int64_t>::min();
	int64_t cached_macro_cell_y = std::numeric_limits<int64_t>::min();

	auto resolve_mountain_id_at_world = [&](int64_t p_world_x, int64_t p_world_y, float p_elevation) -> int32_t {
		if (p_elevation < mountain_thresholds.t_edge) {
			return 0;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			p_world_x,
			macro_cell_size,
			p_effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		if (cached_macro_solve == nullptr || macro_cell_x != cached_macro_cell_x || macro_cell_y != cached_macro_cell_y) {
			cached_macro_solve = &_get_or_build_hierarchical_macro_solve(
				p_seed,
				p_world_version,
				p_effective_mountain_settings,
				p_foundation_settings,
				macro_cell_x,
				macro_cell_y
			);
			cached_macro_cell_x = macro_cell_x;
			cached_macro_cell_y = macro_cell_y;
		}
		return cached_macro_solve->resolve_mountain_id(
			p_world_x,
			p_world_y,
			p_elevation,
			mountain_thresholds.t_edge
		);
	};

	auto is_component_representative_tile = [&](int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) -> bool {
		if (p_mountain_id <= 0) {
			return false;
		}
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			p_world_x,
			macro_cell_size,
			p_effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(p_world_y, macro_cell_size);
		const mountain_field::HierarchicalMacroSolve &solve = _get_or_build_hierarchical_macro_solve(
			p_seed,
			p_world_version,
			p_effective_mountain_settings,
			p_foundation_settings,
			macro_cell_x,
			macro_cell_y
		);
		return solve.is_representative_tile(p_world_x, p_world_y, p_mountain_id);
	};

	for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
		for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
				p_foundation_settings
			);
			const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
			const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
			float elevation = p_mountain_evaluator.sample_elevation(sample_world_x, world_y);
			if (is_foundation_spawn_safety_area_at_world(world_x, world_y, p_foundation_settings)) {
				elevation = 0.0f;
			}
			mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
			mountain_ids[static_cast<size_t>(sample_index)] = resolve_mountain_id_at_world(sample_world_x, world_y, elevation);
		}
	}

	for (int64_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
		for (int64_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
			const int64_t index = local_y * CHUNK_SIZE + local_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + local_x;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + local_y,
				p_foundation_settings
			);
			const int64_t sample_world_x = resolve_mountain_sample_x(world_x, p_world_version, p_foundation_settings);
			const int64_t grid_x = local_x + mountain_border;
			const int64_t grid_y = local_y + mountain_border;
			const int64_t grid_index = grid_y * mountain_grid_side + grid_x;

			const float elevation = mountain_elevations[static_cast<size_t>(grid_index)];
			const int32_t resolved_mountain_id = mountain_ids[static_cast<size_t>(grid_index)];
			uint8_t resolved_mountain_flags = 0U;
			int32_t resolved_mountain_atlas_index = 0;
			int64_t terrain_id = TERRAIN_PLAINS_GROUND;
			int64_t terrain_atlas_index = resolve_base_ground_atlas_index(world_x, world_y, p_seed);
			uint8_t walkable = 1U;

			if (resolved_mountain_id > 0) {
				const int32_t north_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)];
				const int32_t north_east_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t east_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))];
				const int32_t south_east_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))];
				const int32_t south_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)];
				const int32_t south_west_id = mountain_ids[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))];
				const int32_t west_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))];
				const int32_t north_west_id = mountain_ids[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))];

				const bool is_wall = elevation >= mountain_thresholds.t_wall;
				const bool is_foot = elevation >= mountain_thresholds.t_edge && elevation < mountain_thresholds.t_wall;
				if (is_wall) {
					resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_WALL);
				}
				if (is_foot) {
					resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_FOOT);
				}
				if (is_wall) {
					bool is_interior = p_effective_mountain_settings.interior_margin == 0;
					if (p_effective_mountain_settings.interior_margin > 0) {
						is_interior = true;
						for (int32_t distance = 1; distance <= p_effective_mountain_settings.interior_margin; ++distance) {
							const int32_t north_check_id = mountain_ids[static_cast<size_t>((grid_y - distance) * mountain_grid_side + grid_x)];
							const int32_t east_check_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + distance))];
							const int32_t south_check_id = mountain_ids[static_cast<size_t>((grid_y + distance) * mountain_grid_side + grid_x)];
							const int32_t west_check_id = mountain_ids[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - distance))];
							if (north_check_id != resolved_mountain_id ||
									east_check_id != resolved_mountain_id ||
									south_check_id != resolved_mountain_id ||
									west_check_id != resolved_mountain_id) {
								is_interior = false;
								break;
							}
							if (mountain_elevations[static_cast<size_t>((grid_y - distance) * mountain_grid_side + grid_x)] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + distance))] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>((grid_y + distance) * mountain_grid_side + grid_x)] < mountain_thresholds.t_wall ||
									mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - distance))] < mountain_thresholds.t_wall) {
								is_interior = false;
								break;
							}
						}
					}
					if (is_interior) {
						resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_INTERIOR);
					}
					if (is_component_representative_tile(sample_world_x, world_y, resolved_mountain_id)) {
						resolved_mountain_flags = static_cast<uint8_t>(resolved_mountain_flags | MOUNTAIN_FLAG_ANCHOR);
					}
				}

				resolved_mountain_atlas_index = p_mountain_evaluator.resolve_mountain_atlas_index(
					sample_world_x,
					world_y,
					resolved_mountain_id,
					north_id,
					north_east_id,
					east_id,
					south_east_id,
					south_id,
					south_west_id,
					west_id,
					north_west_id
				);

				const bool north_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
				const bool north_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool east_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool south_east_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x + 1))] >= mountain_thresholds.t_edge;
				const bool south_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + grid_x)] >= mountain_thresholds.t_edge;
				const bool south_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y + 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
				const bool west_is_mountain = mountain_elevations[static_cast<size_t>(grid_y * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;
				const bool north_west_is_mountain = mountain_elevations[static_cast<size_t>((grid_y - 1) * mountain_grid_side + (grid_x - 1))] >= mountain_thresholds.t_edge;

				if ((resolved_mountain_flags & MOUNTAIN_FLAG_WALL) != 0U) {
					terrain_id = TERRAIN_MOUNTAIN_WALL;
					terrain_atlas_index = resolve_mountain_base_atlas_index(
						p_seed,
						sample_world_x,
						world_y,
						north_is_mountain,
						north_east_is_mountain,
						east_is_mountain,
						south_east_is_mountain,
						south_is_mountain,
						south_west_is_mountain,
						west_is_mountain,
						north_west_is_mountain
					);
					walkable = 0U;
				} else if ((resolved_mountain_flags & MOUNTAIN_FLAG_FOOT) != 0U) {
					terrain_id = TERRAIN_MOUNTAIN_FOOT;
					terrain_atlas_index = resolve_mountain_base_atlas_index(
						p_seed,
						sample_world_x,
						world_y,
						north_is_mountain,
						north_east_is_mountain,
						east_is_mountain,
						south_east_is_mountain,
						south_is_mountain,
						south_west_is_mountain,
						west_is_mountain,
						north_west_is_mountain
					);
					walkable = 0U;
				}
			}

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
			mountain_id_per_tile.set(index, resolved_mountain_id);
			mountain_flags.set(index, resolved_mountain_flags);
			mountain_atlas_indices.set(index, resolved_mountain_atlas_index);
		}
	}

	Dictionary packet;
	packet["chunk_coord"] = p_coord;
	packet["world_seed"] = p_seed;
	packet["world_version"] = p_world_version;
	packet["terrain_ids"] = terrain_ids;
	packet["terrain_atlas_indices"] = terrain_atlas_indices;
	packet["walkable_flags"] = walkable_flags;
	packet["mountain_id_per_tile"] = mountain_id_per_tile;
	packet["mountain_flags"] = mountain_flags;
	packet["mountain_atlas_indices"] = mountain_atlas_indices;
	return packet;
}

Dictionary WorldCore::resolve_world_foundation_spawn_tile(
	int64_t p_seed,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return make_failure_result("World foundation spawn resolution requires world foundation version.");
	}
	const int64_t expected_settings_count = expected_settings_count_for_version(p_world_version);
	if (p_settings_packed.size() != expected_settings_count) {
		return make_failure_result("World foundation spawn resolution received an invalid settings payload size.");
	}
	if (!mountain_field::uses_hierarchical_labeling(p_world_version)) {
		return make_failure_result("World foundation spawn resolution requires hierarchical mountain labeling.");
	}

	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	if (!foundation_settings.enabled) {
		return make_failure_result("World foundation settings are disabled.");
	}

	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const world_prepass::Snapshot &snapshot = _get_or_build_world_prepass(
		p_seed,
		p_world_version,
		mountain_evaluator,
		effective_mountain_settings,
		foundation_settings
	);
	Dictionary result = world_prepass::resolve_spawn_tile(snapshot);
	result["grid_width"] = snapshot.grid_width;
	result["grid_height"] = snapshot.grid_height;
	result["coarse_cell_size_tiles"] = world_prepass::COARSE_CELL_SIZE_TILES;
	result["compute_time_ms"] = snapshot.compute_time_ms;
	return result;
}

#ifdef DEBUG_ENABLED
Dictionary WorldCore::get_world_foundation_snapshot(int64_t p_layer_mask, int64_t p_downscale_factor) {
	if (world_prepass_snapshot_ == nullptr || !world_prepass_snapshot_->valid) {
		return Dictionary();
	}
	return world_prepass::make_debug_snapshot(*world_prepass_snapshot_, p_layer_mask, p_downscale_factor);
}

Ref<Image> WorldCore::get_world_foundation_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (world_prepass_snapshot_ == nullptr || !world_prepass_snapshot_->valid) {
		return Ref<Image>();
	}
	return world_prepass::make_overview_image(*world_prepass_snapshot_, p_layer_mask, p_pixels_per_cell);
}
#endif

Array WorldCore::generate_chunk_packets_batch(
	int64_t p_seed,
	PackedVector2Array p_coords,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	Array packets;
	packets.resize(p_coords.size());
	if (p_coords.is_empty()) {
		return packets;
	}

	const int64_t expected_settings_count = expected_settings_count_for_version(p_world_version);
	ERR_FAIL_COND_V_MSG(
		p_settings_packed.size() != expected_settings_count,
		Array{},
		"WorldCore.generate_chunk_packets_batch received an invalid settings payload size."
	);
	ERR_FAIL_COND_V_MSG(
		!mountain_field::uses_hierarchical_labeling(p_world_version),
		Array{},
		"WorldCore.generate_chunk_packets_batch requires hierarchical mountain labeling (world_version >= 6)."
	);

	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const mountain_field::Evaluator mountain_evaluator(p_seed, p_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	if (foundation_settings.enabled) {
		_get_or_build_world_prepass(
			p_seed,
			p_world_version,
			mountain_evaluator,
			effective_mountain_settings,
			foundation_settings
		);
	}

	std::vector<ChunkMacroGroup> macro_groups;
	std::unordered_map<uint64_t, int32_t> group_index_by_key;
	for (int32_t index = 0; index < p_coords.size(); ++index) {
		const Vector2 coord_value = p_coords[index];
		const Vector2i chunk_coord = canonicalize_chunk_coord(Vector2i(
			static_cast<int32_t>(coord_value.x),
			static_cast<int32_t>(coord_value.y)
		), foundation_settings);
		const int64_t chunk_origin_x = resolve_mountain_sample_x(
			static_cast<int64_t>(chunk_coord.x) * CHUNK_SIZE,
			p_world_version,
			foundation_settings
		);
		const int64_t chunk_origin_y = clamp_foundation_world_y(
			static_cast<int64_t>(chunk_coord.y) * CHUNK_SIZE,
			foundation_settings
		);
		const int64_t macro_cell_x = resolve_macro_cell_x_for_world(
			chunk_origin_x,
			macro_cell_size,
			effective_mountain_settings.world_wrap_width_tiles
		);
		const int64_t macro_cell_y = resolve_macro_cell_y_for_world(chunk_origin_y, macro_cell_size);
		const uint64_t macro_key = make_macro_key(macro_cell_x, macro_cell_y);

		auto found = group_index_by_key.find(macro_key);
		if (found == group_index_by_key.end()) {
			ChunkMacroGroup group;
			group.macro_cell_x = macro_cell_x;
			group.macro_cell_y = macro_cell_y;
			macro_groups.push_back(std::move(group));
			const int32_t group_index = static_cast<int32_t>(macro_groups.size() - 1);
			group_index_by_key.emplace(macro_key, group_index);
			found = group_index_by_key.find(macro_key);
		}

		macro_groups[static_cast<size_t>(found->second)].chunk_indices.push_back(index);
	}

	for (const ChunkMacroGroup &group : macro_groups) {
		_get_or_build_hierarchical_macro_solve(
			p_seed,
			p_world_version,
			effective_mountain_settings,
			foundation_settings,
			group.macro_cell_x,
			group.macro_cell_y
		);
		for (int32_t packet_index : group.chunk_indices) {
			const Vector2 coord_value = p_coords[packet_index];
			const Vector2i chunk_coord = canonicalize_chunk_coord(Vector2i(
				static_cast<int32_t>(coord_value.x),
				static_cast<int32_t>(coord_value.y)
			), foundation_settings);
			packets[packet_index] = _generate_chunk_packet(
				p_seed,
				chunk_coord,
				p_world_version,
				mountain_evaluator,
				effective_mountain_settings,
				foundation_settings
			);
		}
	}
	return packets;
}
