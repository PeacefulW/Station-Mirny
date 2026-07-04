#include "grass_scatter.h"

#include "world_utils.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

namespace grass_scatter {
namespace {

// Раньше гора рисовалась НАД травой (z 300/301), поэтому любой промах клиренса
// был скрыт горой. Теперь гора ниже лесенки (Z_MOUNTAIN_TOP/PAGE = 19,
// mountain_object_occlusion.md), и клиренс должен видеть гору НАДЁЖНО, включая
// случаи, когда сама гора стоит в СОСЕДНЕМ чанке. Прежняя проверка сэмплировала
// только chunk-local terrain_ids (out-of-bounds -> "не гора"), поэтому пучки у
// шва чанка рядом с горой в соседнем чанке не получали клиренса вовсе — никакое
// увеличение радиуса это не чинило (tmp_grass_mountain_overlap_probe,
// 2026-07-04: тот же оффендер на 64px и 128px). Клиренс теперь читает
// mountain_solid_halo — тот же per-tile halo (WALL|FOOT, walkable=0,
// mountain_id>0), что WorldStreamer уже строит через 3x3 соседних чанка для
// mountain_top_mask_underlay (world_streamer.gd::_build_mountain_solid_halo).
constexpr float GRASS_MOUNTAIN_CLEARANCE_PX = 128.0f;

// --- GLSL field mirror -------------------------------------------------------
// One formula, two transcriptions: these functions mirror the aperiodic world
// fields of assets/shaders/ground_hybrid_material.gdshader, INCLUDING the
// macro-mass coverage modulator (sample_fields) and the procedural paths
// (sample_path). Any change to the field math there must be mirrored here in the
// same task (spec law). See
// docs/02_system_specs/world/plains_ground_field_composition.md.

struct Vec2 {
	float x = 0.0f;
	float y = 0.0f;
};

inline float fract_f(float p_value) {
	return p_value - std::floor(p_value);
}

inline float clamp01(float p_value) {
	return world_utils::saturate(p_value);
}

inline float smoothstep_f(float p_edge0, float p_edge1, float p_value) {
	const float t = clamp01((p_value - p_edge0) / (p_edge1 - p_edge0));
	return t * t * (3.0f - 2.0f * t);
}

inline float lerp_f(float p_from, float p_to, float p_weight) {
	return p_from + (p_to - p_from) * p_weight;
}

inline float remap_contrast(float p_value, float p_amount) {
	return clamp01((p_value - 0.5f) * p_amount + 0.5f);
}

inline float hash12(Vec2 p_point) {
	float px = fract_f(p_point.x * 0.1031f);
	float py = fract_f(p_point.y * 0.1031f);
	float pz = px;
	const float d = px * (py + 33.33f) + py * (pz + 33.33f) + pz * (px + 33.33f);
	px += d;
	py += d;
	pz += d;
	return fract_f((px + py) * pz);
}

inline Vec2 random_gradient(Vec2 p_point) {
	const float hx = hash12(p_point) * 2.0f - 1.0f;
	const float hy = hash12({ p_point.x + 17.31f, p_point.y - 41.77f }) * 2.0f - 1.0f;
	const float gx = hx + 0.001f;
	const float gy = hy - 0.001f;
	const float len = std::sqrt(gx * gx + gy * gy);
	if (len <= 0.000001f) {
		return { 1.0f, 0.0f };
	}
	return { gx / len, gy / len };
}

inline float gradient_noise(Vec2 p_point) {
	const float ix = std::floor(p_point.x);
	const float iy = std::floor(p_point.y);
	const float fx = p_point.x - ix;
	const float fy = p_point.y - iy;
	const float ux = fx * fx * fx * (fx * (fx * 6.0f - 15.0f) + 10.0f);
	const float uy = fy * fy * fy * (fy * (fy * 6.0f - 15.0f) + 10.0f);
	const Vec2 g00 = random_gradient({ ix, iy });
	const Vec2 g10 = random_gradient({ ix + 1.0f, iy });
	const Vec2 g01 = random_gradient({ ix, iy + 1.0f });
	const Vec2 g11 = random_gradient({ ix + 1.0f, iy + 1.0f });
	const float a = g00.x * fx + g00.y * fy;
	const float b = g10.x * (fx - 1.0f) + g10.y * fy;
	const float c = g01.x * fx + g01.y * (fy - 1.0f);
	const float d = g11.x * (fx - 1.0f) + g11.y * (fy - 1.0f);
	const float mixed = lerp_f(lerp_f(a, b, ux), lerp_f(c, d, ux), uy);
	return clamp01(mixed * 1.42f * 0.5f + 0.5f);
}

inline float fbm3(Vec2 p_point) {
	float value = 0.0f;
	float amplitude = 0.56f;
	float total = 0.0f;
	Vec2 p = p_point;
	for (int i = 0; i < 3; i++) {
		value += gradient_noise(p) * amplitude;
		total += amplitude;
		p = { p.x * 2.07f + 17.1f, p.y * 2.07f - 9.4f };
		amplitude *= 0.48f;
	}
	return value / std::max(total, 0.0001f);
}

inline float fbm2(Vec2 p_point) {
	float value = 0.0f;
	float amplitude = 0.60f;
	float total = 0.0f;
	Vec2 p = p_point;
	for (int i = 0; i < 2; i++) {
		value += gradient_noise(p) * amplitude;
		total += amplitude;
		p = { p.x * 2.11f - 13.7f, p.y * 2.11f + 21.3f };
		amplitude *= 0.50f;
	}
	return value / std::max(total, 0.0001f);
}

struct FieldSample {
	float grass_density = 0.0f;
	float orange_region = 0.0f;
};

FieldSample sample_fields(float p_world_x, float p_world_y, const float *p_params) {
	const Vec2 wp = { p_world_x, p_world_y };
	const float warp_x = fbm2({ wp.x / 1800.0f + 11.7f, wp.y / 1800.0f - 4.3f }) - 0.5f;
	const float warp_y = fbm2({ wp.x / 1650.0f - 7.9f, wp.y / 1650.0f + 23.1f }) - 0.5f;
	const float jitter_x = fbm2({ wp.x / 420.0f + 53.0f, wp.y / 420.0f + 19.0f }) - 0.5f;
	const float jitter_y = fbm2({ wp.x / 390.0f - 22.0f, wp.y / 390.0f + 67.0f }) - 0.5f;
	const Vec2 organic = {
		wp.x + warp_x * 660.0f + jitter_x * 170.0f,
		wp.y + warp_y * 660.0f + jitter_y * 170.0f,
	};

	const float grass_scale = std::max(p_params[PARAM_GRASS_FIELD_SCALE_PX], 1.0f);
	const float orange_scale = std::max(p_params[PARAM_ORANGE_FIELD_SCALE_PX], 1.0f);
	const float rock_scale = std::max(p_params[PARAM_ROCK_FIELD_SCALE_PX], 1.0f);

	float grass_field = remap_contrast(
			fbm3({ organic.x / grass_scale + 4.7f, organic.y / grass_scale + 13.9f }), 2.10f);
	// Macro-mass: long-wavelength coverage bias (mirror of the ground shader).
	const float macro_scale = std::max(p_params[PARAM_MACRO_MASS_SCALE_PX], 1.0f);
	const float macro_mass = fbm2({ wp.x / macro_scale + 91.7f, wp.y / macro_scale - 53.3f });
	const float macro_bias = (macro_mass - 0.5f) * 2.0f * p_params[PARAM_MACRO_MASS_STRENGTH];
	grass_field = clamp01(grass_field + (p_params[PARAM_GRASS_COVERAGE] - 0.5f) * 0.9f + macro_bias);

	const float orange_field = remap_contrast(
			fbm3({ organic.x / orange_scale - 27.3f, organic.y / orange_scale + 8.1f }), 1.30f);
	const float rock_field = fbm3({ organic.x / rock_scale + 15.5f, organic.y / rock_scale - 31.7f });

	const float rock_threshold = lerp_f(0.86f, 0.52f, clamp01(p_params[PARAM_ROCK_COVERAGE]));
	float rock_region = smoothstep_f(rock_threshold - 0.24f, rock_threshold + 0.24f, rock_field);
	rock_region *= 1.0f - smoothstep_f(0.30f, 0.62f, grass_field) * 0.78f;

	FieldSample sample;
	sample.grass_density = clamp01(grass_field * (1.0f - rock_region * 0.85f));
	const float orange_threshold = lerp_f(0.88f, 0.50f, clamp01(p_params[PARAM_ORANGE_COVERAGE]));
	sample.orange_region = smoothstep_f(orange_threshold - 0.22f, orange_threshold + 0.22f, orange_field) *
			smoothstep_f(0.44f, 0.80f, sample.grass_density);
	return sample;
}

// Поля гладкие (характерные масштабы сотни‑тысячи px), поэтому семплируются
// на грубой чанковой решётке и билинейно интерполируются по кандидатам:
// прямой per-candidate sample_fields стоил ~7 мс на чанк в debug-сборке.
constexpr int32_t FIELD_GRID_NODES = 13;

struct FieldGrid {
	float density[FIELD_GRID_NODES * FIELD_GRID_NODES] = {};
	float orange[FIELD_GRID_NODES * FIELD_GRID_NODES] = {};
	float step_px = 1.0f;
};

void build_field_grid(
		double p_chunk_origin_x,
		double p_chunk_origin_y,
		float p_chunk_size_px,
		const float *p_params,
		FieldGrid &r_grid) {
	r_grid.step_px = p_chunk_size_px / static_cast<float>(FIELD_GRID_NODES - 1);
	for (int32_t node_y = 0; node_y < FIELD_GRID_NODES; node_y++) {
		for (int32_t node_x = 0; node_x < FIELD_GRID_NODES; node_x++) {
			const float world_x = static_cast<float>(p_chunk_origin_x) + static_cast<float>(node_x) * r_grid.step_px;
			const float world_y = static_cast<float>(p_chunk_origin_y) + static_cast<float>(node_y) * r_grid.step_px;
			const FieldSample sample = sample_fields(world_x, world_y, p_params);
			const int32_t index = node_y * FIELD_GRID_NODES + node_x;
			r_grid.density[index] = sample.grass_density;
			r_grid.orange[index] = sample.orange_region;
		}
	}
}

FieldSample sample_field_grid(const FieldGrid &p_grid, float p_local_x, float p_local_y) {
	const float gx = world_utils::clamp_value(p_local_x / p_grid.step_px, 0.0f, static_cast<float>(FIELD_GRID_NODES - 1) - 0.0001f);
	const float gy = world_utils::clamp_value(p_local_y / p_grid.step_px, 0.0f, static_cast<float>(FIELD_GRID_NODES - 1) - 0.0001f);
	const int32_t ix = static_cast<int32_t>(gx);
	const int32_t iy = static_cast<int32_t>(gy);
	const float fx = gx - static_cast<float>(ix);
	const float fy = gy - static_cast<float>(iy);
	const int32_t i00 = iy * FIELD_GRID_NODES + ix;
	const int32_t i10 = i00 + 1;
	const int32_t i01 = i00 + FIELD_GRID_NODES;
	const int32_t i11 = i01 + 1;
	FieldSample sample;
	sample.grass_density = lerp_f(
			lerp_f(p_grid.density[i00], p_grid.density[i10], fx),
			lerp_f(p_grid.density[i01], p_grid.density[i11], fx),
			fy);
	sample.orange_region = lerp_f(
			lerp_f(p_grid.orange[i00], p_grid.orange[i10], fx),
			lerp_f(p_grid.orange[i01], p_grid.orange[i11], fx),
			fy);
	return sample;
}

// --- deterministic per-candidate hashing -------------------------------------

inline uint64_t candidate_hash(int64_t p_seed, int64_t p_chunk_x, int64_t p_chunk_y, int64_t p_cell_index) {
	uint64_t mixed = world_utils::splitmix64(static_cast<uint64_t>(p_seed) ^ 0x6772417353634154ULL);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_chunk_x) * 0x9e3779b185ebca87ULL);
	mixed = world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_chunk_y) * 0xc2b2ae3d27d4eb4fULL);
	return world_utils::splitmix64(mixed ^ static_cast<uint64_t>(p_cell_index) * 0x165667b19e3779f9ULL);
}

inline float hash_unit(uint64_t p_hash, uint64_t p_salt) {
	return static_cast<float>(world_utils::splitmix64(p_hash ^ p_salt) >> 40U) / 16777216.0f;
}

// halo — один байт на тайл, halo_side x halo_side, halo_side = chunk_size_tiles
// + 2*halo_radius_tiles; тайл (0,0) чанка живёт по индексу
// (halo_radius_tiles, halo_radius_tiles). Внешние тайлы взяты из 3x3 соседних
// чанков (см. комментарий у GRASS_MOUNTAIN_CLEARANCE_PX). local_x/local_y —
// chunk-local ПИКСЕЛИ, могут уходить за [0, chunk_size_px) в пределах halo.
//
// Раньше клиренс сэмплировал только 8 точек на фиксированном радиусе
// (кардинально + диагонально). Это могло ПЕРЕСКОЧИТЬ тонкую горную полосу:
// если она уже clearance_px, точка ровно на clearance_px могла упасть уже за
// ней, в чистой зоне, и с БОЛЬШИМ радиусом это происходило чаще (128px
// пропускал to, что ловил 96px — tmp_grass_mountain_overlap_probe,
// 2026-07-04). Вместо кольца точек проверяем ВСЕ тайлы halo в пределах
// clearance_px (полный диск), так что тонкую полосу пропустить нельзя.
bool has_grass_mountain_clearance(
		float p_local_x,
		float p_local_y,
		const uint8_t *p_halo,
		int32_t p_halo_side,
		int32_t p_halo_radius_tiles,
		float p_tile_size_px,
		float p_clearance_px) {
	const int32_t center_tile_x = static_cast<int32_t>(std::floor(p_local_x / p_tile_size_px)) + p_halo_radius_tiles;
	const int32_t center_tile_y = static_cast<int32_t>(std::floor(p_local_y / p_tile_size_px)) + p_halo_radius_tiles;
	const int32_t tile_reach = static_cast<int32_t>(std::ceil(p_clearance_px / p_tile_size_px));
	const float clearance_sq = p_clearance_px * p_clearance_px;
	for (int32_t dy = -tile_reach; dy <= tile_reach; dy++) {
		const int32_t ty = center_tile_y + dy;
		if (ty < 0 || ty >= p_halo_side) {
			continue;
		}
		const int64_t halo_row = static_cast<int64_t>(ty) * p_halo_side;
		for (int32_t dx = -tile_reach; dx <= tile_reach; dx++) {
			const int32_t tx = center_tile_x + dx;
			if (tx < 0 || tx >= p_halo_side) {
				continue;
			}
			const float dist_x_px = static_cast<float>(dx) * p_tile_size_px;
			const float dist_y_px = static_cast<float>(dy) * p_tile_size_px;
			if (dist_x_px * dist_x_px + dist_y_px * dist_y_px > clearance_sq) {
				continue;
			}
			if (p_halo[halo_row + tx] != 0) {
				return false;
			}
		}
	}
	return true;
}

} // namespace

Dictionary build_buffer(
		int64_t p_seed,
		int64_t p_chunk_x,
		int64_t p_chunk_y,
		const PackedInt32Array &p_terrain_ids,
		const PackedByteArray &p_lake_flags,
		const PackedByteArray &p_mountain_halo,
		int64_t p_mountain_halo_radius_tiles,
		const PackedFloat32Array &p_params) {
	Dictionary result;
	result["bucket_buffers"] = Array();
	result["instance_count"] = 0;
	if (p_params.size() < PARAM_COUNT) {
		result["error"] = "grass_scatter: params размер меньше PARAM_COUNT";
		return result;
	}
	const float *params = p_params.ptr();
	const int32_t chunk_size_tiles = static_cast<int32_t>(params[PARAM_CHUNK_SIZE_TILES]);
	const float tile_size_px = params[PARAM_TILE_SIZE_PX];
	const int32_t plains_terrain_id = static_cast<int32_t>(params[PARAM_PLAINS_TERRAIN_ID]);
	const int32_t grid_side = std::max(1, static_cast<int32_t>(params[PARAM_CANDIDATE_GRID_SIDE]));
	const int32_t instance_cap = std::max(0, static_cast<int32_t>(params[PARAM_INSTANCE_CAP]));
	const int64_t cell_count = static_cast<int64_t>(chunk_size_tiles) * chunk_size_tiles;
	if (chunk_size_tiles <= 0 || tile_size_px <= 0.0f) {
		result["error"] = "grass_scatter: некорректные размеры чанка";
		return result;
	}
	if (p_terrain_ids.size() < cell_count) {
		result["error"] = "grass_scatter: terrain_ids меньше площади чанка";
		return result;
	}
	const int32_t halo_radius_tiles = static_cast<int32_t>(p_mountain_halo_radius_tiles);
	const int32_t halo_side = chunk_size_tiles + halo_radius_tiles * 2;
	if (halo_radius_tiles <= 0 || p_mountain_halo.size() != static_cast<int64_t>(halo_side) * halo_side) {
		result["error"] = "grass_scatter: mountain_halo размер не совпадает с ожидаемым halo_side";
		return result;
	}
	const uint8_t *mountain_halo = p_mountain_halo.ptr();

	const float chunk_size_px = static_cast<float>(chunk_size_tiles) * tile_size_px;
	const float cell_px = chunk_size_px / static_cast<float>(grid_side);
	const double chunk_origin_x = static_cast<double>(p_chunk_x) * chunk_size_px;
	const double chunk_origin_y = static_cast<double>(p_chunk_y) * chunk_size_px;

	const int32_t *terrain_ids = p_terrain_ids.ptr();
	const uint8_t *lake_flags = p_lake_flags.size() >= cell_count ? p_lake_flags.ptr() : nullptr;

	// Разрез по абсолютным чанковым Y-полосам depth-лесенки; внутри полосы —
	// две корзины важности (крупные в голову, мелочь в хвост) для zoom-LOD.
	std::vector<float> large_buckets[DEPTH_STRIPES_PER_CHUNK];
	std::vector<float> small_buckets[DEPTH_STRIPES_PER_CHUNK];
	std::vector<float> shadow_buf;
	std::vector<float> spore_buf;
	int32_t emitted = 0;
	int32_t truncated = 0;

	const float shadow_size_scale = params[PARAM_SHADOW_SIZE_SCALE];
	const float shadow_alpha = params[PARAM_SHADOW_ALPHA];
	const float shadow_min_size_unit = params[PARAM_SHADOW_MIN_SIZE_UNIT];
	const float spore_orange_threshold = params[PARAM_SPORE_ORANGE_THRESHOLD];
	const float spore_chance = params[PARAM_SPORE_CHANCE];
	const float spore_size_px = params[PARAM_SPORE_SIZE_PX];

	FieldGrid field_grid;
	build_field_grid(chunk_origin_x, chunk_origin_y, chunk_size_px, params, field_grid);

	const float dry_frame_count = std::max(params[PARAM_DRY_FRAME_COUNT], 1.0f);
	const float orange_frame_base = std::max(params[PARAM_ORANGE_FRAME_BASE], 0.0f);
	const float orange_frame_count = std::max(params[PARAM_ORANGE_FRAME_COUNT], 1.0f);
	for (int32_t grid_y = 0; grid_y < grid_side && emitted < instance_cap; grid_y++) {
		for (int32_t grid_x = 0; grid_x < grid_side; grid_x++) {
			if (emitted >= instance_cap) {
				truncated++;
				continue;
			}
			const int64_t cell_index = static_cast<int64_t>(grid_y) * grid_side + grid_x;
			const uint64_t hash = candidate_hash(p_seed, p_chunk_x, p_chunk_y, cell_index);
			const float local_x = (static_cast<float>(grid_x) + 0.5f +
					(hash_unit(hash, 0x11ULL) - 0.5f) * 0.92f) * cell_px;
			const float local_y = (static_cast<float>(grid_y) + 0.5f +
					(hash_unit(hash, 0x13ULL) - 0.5f) * 0.92f) * cell_px;

			const int32_t tile_x = world_utils::clamp_value(
					static_cast<int32_t>(local_x / tile_size_px), 0, chunk_size_tiles - 1);
			const int32_t tile_y = world_utils::clamp_value(
					static_cast<int32_t>(local_y / tile_size_px), 0, chunk_size_tiles - 1);
			const int64_t tile_index = static_cast<int64_t>(tile_y) * chunk_size_tiles + tile_x;
			if (terrain_ids[tile_index] != plains_terrain_id) {
				continue;
			}
			if (lake_flags != nullptr && (lake_flags[tile_index] & 0x1U) != 0) {
				continue;
			}
			// Grass is only presentation, but mountain masks draw above it with
			// organic edges. Keep roots clear of the canonical mountain surface
			// (cross-chunk halo, not just this chunk's own tiles) so tufts cannot
			// peek out under the overlay.
			if (!has_grass_mountain_clearance(
						local_x,
						local_y,
						mountain_halo,
						halo_side,
						halo_radius_tiles,
						tile_size_px,
						GRASS_MOUNTAIN_CLEARANCE_PX)) {
				continue;
			}

			const FieldSample fields = sample_field_grid(field_grid, local_x, local_y);
				// Paths are a pointwise term (evaluated per-candidate, NOT through
				// the coarse field grid, so thin trails cannot alias). Thins tufts
				// along trails so they match the painted ground.
				const float path_open = sample_path(
						chunk_origin_x + static_cast<double>(local_x),
						chunk_origin_y + static_cast<double>(local_y),
						params[PARAM_PATH_SCALE_PX],
						params[PARAM_PATH_WIDTH],
						params[PARAM_PATH_WARP_PX],
						params[PARAM_PATH_STRENGTH]);
				const float grass_d = fields.grass_density * path_open;
				const float orange_acc = fields.orange_region * path_open;

			float acceptance = smoothstep_f(0.30f, 0.62f, grass_d) * 0.34f +
					smoothstep_f(0.62f, 0.86f, grass_d) * 0.30f;
			acceptance += orange_acc * params[PARAM_ORANGE_DENSITY_BOOST];
			acceptance = clamp01(acceptance * params[PARAM_DENSITY_SCALE]);
			if (hash_unit(hash, 0x17ULL) >= acceptance) {
				continue;
			}

			const float size_unit = hash_unit(hash, 0x1dULL);
			const float width = lerp_f(
					params[PARAM_TUFT_MIN_WIDTH_PX],
					params[PARAM_TUFT_MAX_WIDTH_PX],
					size_unit);
			const float height = lerp_f(
						params[PARAM_TUFT_MIN_HEIGHT_PX],
						params[PARAM_TUFT_MAX_HEIGHT_PX],
						hash_unit(hash, 0x1fULL)) *
					params[PARAM_HEIGHT_SCALE] * (1.0f + fields.orange_region * 0.15f);
			// Полёгшая трава: больше разброса наклона всего пучка.
			const float rotation = (hash_unit(hash, 0x25ULL) - 0.5f) * 2.0f * (14.0f * 3.14159265f / 180.0f);
			const float cos_r = std::cos(rotation);
			const float sin_r = std::sin(rotation);

			// Внутри биополя пучок берёт кадры оранжевого банка; окно отклика
			// авторское: ground-поле orange_region редко превышает ~0.5, а
			// земля читается оранжевой уже на слабых значениях.
			const float biofield_pick = smoothstep_f(
					params[PARAM_ORANGE_BANK_LOW], params[PARAM_ORANGE_BANK_HIGH], fields.orange_region);
			const bool use_biofield_bank = hash_unit(hash, 0x35ULL) < biofield_pick;
			float frame_index = 0.0f;
			float tint = lerp_f(params[PARAM_BASE_TINT_MIN], params[PARAM_BASE_TINT_MAX], hash_unit(hash, 0x2bULL));
			if (use_biofield_bank) {
				frame_index = orange_frame_base + std::floor(hash_unit(hash, 0x29ULL) * orange_frame_count);
			} else {
				frame_index = std::floor(hash_unit(hash, 0x29ULL) * dry_frame_count);
				tint *= 1.0f + fields.orange_region * params[PARAM_ORANGE_TINT_BOOST];
			}
			tint = world_utils::clamp_value(tint, 0.0f, 1.35f);
			const float phase = hash_unit(hash, 0x2fULL);
			const float alpha = lerp_f(params[PARAM_ALPHA_MIN], params[PARAM_ALPHA_MAX], hash_unit(hash, 0x31ULL));

			// MultiMesh TRANSFORM_2D + color layout (verified by buffer dump):
			// row0 = (x.x, y.x, 0, origin.x), row1 = (x.y, y.y, 0, origin.y).
			// Квад центрирован, поэтому КОРЕНЬ пучка (опора depth-лесенки) —
			// центр + полвысоты; бакет по центру систематически нырял под
			// объекты в зоне визуального контакта.
			const float root_local_y = local_y + height * 0.5f;
			const int64_t depth_stripe = world_utils::clamp_value<int64_t>(
					static_cast<int64_t>(std::floor(root_local_y / static_cast<float>(DEPTH_STRIPE_PX))),
					0,
					DEPTH_STRIPES_PER_CHUNK - 1);
			std::vector<float> &bucket = size_unit >= 0.55f
					? large_buckets[depth_stripe]
					: small_buckets[depth_stripe];
			const float instance[12] = {
				cos_r * width,
				-sin_r * height,
				0.0f,
				local_x,
				sin_r * width,
				cos_r * height,
				0.0f,
				local_y,
				frame_index / 255.0f,
				tint,
				phase,
				alpha,
			};
			bucket.insert(bucket.end(), instance, instance + 12);
			emitted++;

			// Контактная тень: плоское пятно у корня заметных пучков. Низкий
			// эллипс прижимает куст к земле; рисуется ниже всей лесенки травы.
			if (size_unit >= shadow_min_size_unit && shadow_alpha > 0.001f) {
				const float blob_w = width * shadow_size_scale;
				const float blob_h = blob_w * 0.42f;
				const float blob_alpha = shadow_alpha * lerp_f(0.7f, 1.0f, size_unit);
				const float shadow[12] = {
					blob_w, 0.0f, 0.0f, local_x,
					0.0f, blob_h, 0.0f, root_local_y,
					0.0f, 0.0f, 0.0f, blob_alpha,
				};
				shadow_buf.insert(shadow_buf.end(), shadow, shadow + 12);
			}

			// Спора: редкая светящаяся мошка над сильным биополе-ядром,
			// дрейфует по ветру в шейдере. Привязана к пучку, но висит выше.
			if (fields.orange_region >= spore_orange_threshold &&
					hash_unit(hash, 0x3bULL) < spore_chance) {
				const float spore_phase = hash_unit(hash, 0x3dULL);
				const float drift_seed = hash_unit(hash, 0x41ULL);
				const float spore_y = local_y - height * 0.55f - 8.0f;
				const float spore[12] = {
					spore_size_px, 0.0f, 0.0f, local_x,
					0.0f, spore_size_px, 0.0f, spore_y,
					spore_phase, drift_seed, 0.0f, 1.0f,
				};
				spore_buf.insert(spore_buf.end(), spore, spore + 12);
			}
		}
	}

	Array bucket_buffers;
	for (int32_t depth_stripe = 0; depth_stripe < DEPTH_STRIPES_PER_CHUNK; depth_stripe++) {
		const std::vector<float> &large = large_buckets[depth_stripe];
		const std::vector<float> &small = small_buckets[depth_stripe];
		PackedFloat32Array buffer;
		buffer.resize(static_cast<int64_t>(large.size() + small.size()));
		float *out = buffer.ptrw();
		std::copy(large.begin(), large.end(), out);
		std::copy(small.begin(), small.end(), out + large.size());
		bucket_buffers.append(buffer);
	}
	result["bucket_buffers"] = bucket_buffers;
	result["instance_count"] = emitted;

	PackedFloat32Array shadow_packed;
	shadow_packed.resize(static_cast<int64_t>(shadow_buf.size()));
	if (!shadow_buf.empty()) {
		std::copy(shadow_buf.begin(), shadow_buf.end(), shadow_packed.ptrw());
	}
	result["shadow_buffer"] = shadow_packed;

	PackedFloat32Array spore_packed;
	spore_packed.resize(static_cast<int64_t>(spore_buf.size()));
	if (!spore_buf.empty()) {
		std::copy(spore_buf.begin(), spore_buf.end(), spore_packed.ptrw());
	}
	result["spore_buffer"] = spore_packed;

	if (truncated > 0) {
		result["truncated_count"] = truncated;
	}
	return result;
}

float sample_grass_density(
		double p_world_x,
		double p_world_y,
		float p_grass_field_scale_px,
		float p_grass_coverage,
		float p_rock_field_scale_px,
		float p_rock_coverage,
		float p_macro_mass_scale_px,
		float p_macro_mass_strength) {
	float params[PARAM_COUNT] = {};
	params[PARAM_GRASS_FIELD_SCALE_PX] = p_grass_field_scale_px;
	params[PARAM_GRASS_COVERAGE] = p_grass_coverage;
	params[PARAM_ORANGE_FIELD_SCALE_PX] = p_grass_field_scale_px; // не влияет на grass_density
	params[PARAM_ORANGE_COVERAGE] = 0.5f;                         // не влияет на grass_density
	params[PARAM_ROCK_FIELD_SCALE_PX] = p_rock_field_scale_px;
	params[PARAM_ROCK_COVERAGE] = p_rock_coverage;
	params[PARAM_MACRO_MASS_SCALE_PX] = p_macro_mass_scale_px;
	params[PARAM_MACRO_MASS_STRENGTH] = p_macro_mass_strength;
	return sample_fields(static_cast<float>(p_world_x), static_cast<float>(p_world_y), params).grass_density;
}

// Mirror of sample_path() in assets/shaders/ground_hybrid_material.gdshader.
float sample_path(
		double p_world_x,
		double p_world_y,
		float p_path_scale_px,
		float p_path_width,
		float p_path_warp_px,
		float p_path_strength) {
	const float wx = static_cast<float>(p_world_x);
	const float wy = static_cast<float>(p_world_y);
	const float warp_div = std::max(p_path_scale_px * 0.5f, 1.0f);
	const float wn = fbm2({ wx / warp_div + 71.3f, wy / warp_div - 19.7f });
	const float ang = wn * 6.2831853f;
	const float ppx = wx + std::cos(ang) * p_path_warp_px;
	const float ppy = wy + std::sin(ang) * p_path_warp_px;
	const float scale = std::max(p_path_scale_px, 1.0f);
	const float s = fbm2({ ppx / scale + 13.1f, ppy / scale + 47.9f });
	const float d = std::fabs(s - 0.5f);
	const float path = 1.0f - smoothstep_f(p_path_width, p_path_width * 2.0f, d);
	return clamp01(1.0f - path * p_path_strength);
}

} // namespace grass_scatter
