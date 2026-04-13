#include "chunk_visual_kernels.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

#include <godot_cpp/classes/tile_map_layer.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace {

constexpr int REDRAW_PHASE_TERRAIN = 0;
constexpr int REDRAW_PHASE_COVER = 1;
constexpr int REDRAW_PHASE_CLIFF = 2;
constexpr int VISUAL_COMMAND_OP_SET = 0;
constexpr int VISUAL_COMMAND_OP_ERASE = 1;
constexpr int VISUAL_APPLY_BUFFER_STRIDE = 7;
constexpr int VISUAL_LAYER_TERRAIN = 0;
constexpr int VISUAL_LAYER_GROUND_FACE = 1;
constexpr int VISUAL_LAYER_ROCK = 2;
constexpr int VISUAL_LAYER_COVER = 3;
constexpr int VISUAL_LAYER_CLIFF = 4;
constexpr int PREBAKED_ROCK_VISUAL_NONE = 255;
constexpr int PREBAKED_CLIFF_NONE = 0;
constexpr int PREBAKED_CLIFF_SOUTH = 1;
constexpr int PREBAKED_CLIFF_WEST = 2;
constexpr int PREBAKED_CLIFF_EAST = 3;
constexpr int PREBAKED_CLIFF_TOP = 4;
constexpr int INTERIOR_FAMILY_TARGET_COUNT = 3;
constexpr int INTERIOR_FAMILY_WINDOW_SIZE = 3;
constexpr double INTERIOR_FAMILY_SCALE = 18.0;
constexpr double INTERIOR_FAMILY_DETAIL_SCALE = 9.0;
constexpr int INTERIOR_FAMILY_SEED = 13183;
constexpr int INTERIOR_VARIATION_SEED = 12345;
constexpr int INTERIOR_REHASH_SEED = 12442;
constexpr int INTERIOR_MACRO_DUST_SEED = 16001;
constexpr int INTERIOR_MACRO_MOSS_SEED = 16057;
constexpr int INTERIOR_MACRO_CRACK_SEED = 16111;
constexpr int INTERIOR_MACRO_PEBBLE_SEED = 16183;
constexpr int ECOTONE_BLEND_SEED = 18257;
constexpr double ECOTONE_BLEND_SCALE = 6.0;
constexpr double ECOTONE_BLEND_START = 0.18;
constexpr uint32_t HASH32_MASK = 0xffffffffu;

const Vector2i COVER_REVEAL_DIRS[8] = {
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
};

struct VisualTables {
	Array surface_palette_tiles;
	PackedByteArray wall_flip_class;
	PackedByteArray wall_flip_alt_count;
	int wall_base_count = 0;
	int terrain_tiles_per_row = 64;
	int ground_face_tiles_start = -1;
	int sand_face_tiles_start = -1;
	int interior_base_variant_count = 1;
	int interior_transform_count = 8;
	int terrain_source_id = 0;
	int overlay_source_id = 1;
	int surface_variation_none = 0;
	Vector2i tile_ground_dark = Vector2i(0, 0);
	Vector2i tile_ground = Vector2i(1, 0);
	Vector2i tile_ground_light = Vector2i(2, 0);
	Vector2i tile_mined_floor = Vector2i(5, 0);
	Vector2i tile_mountain_entrance = Vector2i(6, 0);
	Vector2i tile_water = Vector2i(7, 0);
	Vector2i tile_sand = Vector2i(8, 0);
	Vector2i tile_grass = Vector2i(9, 0);
	Vector2i tile_sparse_flora = Vector2i(10, 0);
	Vector2i tile_dense_flora = Vector2i(11, 0);
	Vector2i tile_clearing = Vector2i(12, 0);
	Vector2i tile_rocky_patch = Vector2i(13, 0);
	Vector2i tile_wet_patch = Vector2i(14, 0);
	Vector2i tile_ice = Vector2i(15, 0);
	Vector2i tile_scorched = Vector2i(16, 0);
	Vector2i tile_salt_flat = Vector2i(17, 0);
	Vector2i tile_dry_riverbed = Vector2i(18, 0);
	Vector2i tile_shadow_south = Vector2i(2, 0);
	Vector2i tile_shadow_west = Vector2i(6, 0);
	Vector2i tile_shadow_east = Vector2i(3, 0);
	Vector2i tile_top_edge = Vector2i(4, 0);
	int terrain_ground = 0;
	int terrain_rock = 1;
	int terrain_water = 2;
	int terrain_sand = 3;
	int terrain_grass = 4;
	int terrain_mined_floor = 5;
	int terrain_mountain_entrance = 6;
};

struct VisualRequestContext {
	Dictionary terrain_lookup;
	Dictionary height_lookup;
	Dictionary variation_lookup;
	Dictionary biome_lookup;
	Dictionary secondary_biome_lookup;
	Dictionary ecotone_lookup;
	PackedByteArray terrain_bytes;
	PackedFloat32Array height_bytes;
	PackedByteArray variation_bytes;
	PackedByteArray biome_bytes;
	PackedByteArray secondary_biome_bytes;
	PackedFloat32Array ecotone_values;
	PackedByteArray terrain_halo;
	Vector2i chunk_coord = Vector2i();
	int chunk_size = 64;
	bool is_underground = false;
	bool uses_native_arrays = false;
	VisualTables tables;
};

struct InteriorMacroContext {
	Vector2i chunk_coord = Vector2i();
	int chunk_size = 0;
	int samples_per_tile = 1;
	int interior_base_variant_count = 1;
	PackedByteArray interior_target_mask;
	Color sand_color = Color(1.0, 1.0, 1.0, 1.0);
	Color grass_color = Color(1.0, 1.0, 1.0, 1.0);
	Color ground_color = Color(1.0, 1.0, 1.0, 1.0);
};

struct LayeredCommandBuffers {
	PackedInt32Array terrain;
	PackedInt32Array ground_face;
	PackedInt32Array rock;
	PackedInt32Array cover;
	PackedInt32Array cliff;
	int command_count = 0;
};

inline int clampi_local(int value, int min_value, int max_value) {
	return value < min_value ? min_value : (value > max_value ? max_value : value);
}

inline double clampf_local(double value, double min_value, double max_value) {
	return value < min_value ? min_value : (value > max_value ? max_value : value);
}

inline double lerpf_local(double a, double b, double t) {
	return a + (b - a) * t;
}

uint32_t hash32_xy(int tile_x, int tile_y, int seed);
double hash32_to_unit_float(uint32_t h);
double smoothstep01(double t);
double sample_interior_family_noise(int global_x, int global_y, double scale, int seed);
int resolve_interior_family(int global_x, int global_y, int base_count);
bool load_interior_macro_context(const Dictionary &request, InteriorMacroContext &ctx);
Dictionary build_interior_macro_overlay_internal(const InteriorMacroContext &ctx);

inline Vector2i wall_def(int index) {
	return Vector2i(7 + index, 0);
}

bool supports_native_compute(const Dictionary &request) {
	const Dictionary tables = request.get("native_visual_tables", Dictionary());
	if (tables.is_empty()) {
		return false;
	}
	const String mode = request.get("mode", String());
	if (mode == "dirty") {
		return true;
	}
	if (mode != "phase") {
		return false;
	}
	const int phase = int(request.get("phase", -1));
	return phase == REDRAW_PHASE_TERRAIN || phase == REDRAW_PHASE_COVER || phase == REDRAW_PHASE_CLIFF;
}

bool load_tables(const Dictionary &request, VisualRequestContext &ctx) {
	const Dictionary tables = request.get("native_visual_tables", Dictionary());
	if (tables.is_empty()) {
		return false;
	}
	ctx.terrain_lookup = request.get("terrain_lookup", Dictionary());
	ctx.height_lookup = request.get("height_lookup", Dictionary());
	ctx.variation_lookup = request.get("variation_lookup", Dictionary());
	ctx.biome_lookup = request.get("biome_lookup", Dictionary());
	ctx.secondary_biome_lookup = request.get("secondary_biome_lookup", Dictionary());
	ctx.ecotone_lookup = request.get("ecotone_lookup", Dictionary());
	ctx.terrain_bytes = request.get("terrain_bytes", PackedByteArray());
	ctx.height_bytes = request.get("height_bytes", PackedFloat32Array());
	ctx.variation_bytes = request.get("variation_bytes", PackedByteArray());
	ctx.biome_bytes = request.get("biome_bytes", PackedByteArray());
	ctx.secondary_biome_bytes = request.get("secondary_biome_bytes", PackedByteArray());
	ctx.ecotone_values = request.get("ecotone_values", PackedFloat32Array());
	ctx.terrain_halo = request.get("terrain_halo", PackedByteArray());
	ctx.chunk_coord = request.get("chunk_coord", Vector2i());
	ctx.chunk_size = int(request.get("chunk_size", 64));
	ctx.is_underground = bool(request.get("is_underground", false));
	ctx.uses_native_arrays = !ctx.terrain_bytes.is_empty();

	ctx.tables.surface_palette_tiles = tables.get("surface_palette_tiles", Array());
	ctx.tables.wall_flip_class = tables.get("wall_flip_class", PackedByteArray());
	ctx.tables.wall_flip_alt_count = tables.get("wall_flip_alt_count", PackedByteArray());
	ctx.tables.wall_base_count = int(tables.get("wall_base_count", 0));
	ctx.tables.terrain_tiles_per_row = int(tables.get("terrain_tiles_per_row", 64));
	ctx.tables.ground_face_tiles_start = int(tables.get("ground_face_tiles_start", -1));
	ctx.tables.sand_face_tiles_start = int(tables.get("sand_face_tiles_start", -1));
	ctx.tables.interior_base_variant_count = int(tables.get("interior_base_variant_count", 1));
	ctx.tables.interior_transform_count = int(tables.get("interior_transform_count", 8));
	ctx.tables.terrain_source_id = int(tables.get("terrain_source_id", 0));
	ctx.tables.overlay_source_id = int(tables.get("overlay_source_id", 1));
	ctx.tables.surface_variation_none = int(tables.get("surface_variation_none", 0));
	ctx.tables.tile_ground_dark = tables.get("tile_ground_dark", ctx.tables.tile_ground_dark);
	ctx.tables.tile_ground = tables.get("tile_ground", ctx.tables.tile_ground);
	ctx.tables.tile_ground_light = tables.get("tile_ground_light", ctx.tables.tile_ground_light);
	ctx.tables.tile_mined_floor = tables.get("tile_mined_floor", ctx.tables.tile_mined_floor);
	ctx.tables.tile_mountain_entrance = tables.get("tile_mountain_entrance", ctx.tables.tile_mountain_entrance);
	ctx.tables.tile_water = tables.get("tile_water", ctx.tables.tile_water);
	ctx.tables.tile_sand = tables.get("tile_sand", ctx.tables.tile_sand);
	ctx.tables.tile_grass = tables.get("tile_grass", ctx.tables.tile_grass);
	ctx.tables.tile_sparse_flora = tables.get("tile_sparse_flora", ctx.tables.tile_sparse_flora);
	ctx.tables.tile_dense_flora = tables.get("tile_dense_flora", ctx.tables.tile_dense_flora);
	ctx.tables.tile_clearing = tables.get("tile_clearing", ctx.tables.tile_clearing);
	ctx.tables.tile_rocky_patch = tables.get("tile_rocky_patch", ctx.tables.tile_rocky_patch);
	ctx.tables.tile_wet_patch = tables.get("tile_wet_patch", ctx.tables.tile_wet_patch);
	ctx.tables.tile_ice = tables.get("tile_ice", ctx.tables.tile_ice);
	ctx.tables.tile_scorched = tables.get("tile_scorched", ctx.tables.tile_scorched);
	ctx.tables.tile_salt_flat = tables.get("tile_salt_flat", ctx.tables.tile_salt_flat);
	ctx.tables.tile_dry_riverbed = tables.get("tile_dry_riverbed", ctx.tables.tile_dry_riverbed);
	ctx.tables.tile_shadow_south = tables.get("tile_shadow_south", ctx.tables.tile_shadow_south);
	ctx.tables.tile_shadow_west = tables.get("tile_shadow_west", ctx.tables.tile_shadow_west);
	ctx.tables.tile_shadow_east = tables.get("tile_shadow_east", ctx.tables.tile_shadow_east);
	ctx.tables.tile_top_edge = tables.get("tile_top_edge", ctx.tables.tile_top_edge);
	ctx.tables.terrain_ground = int(tables.get("terrain_ground", ctx.tables.terrain_ground));
	ctx.tables.terrain_rock = int(tables.get("terrain_rock", ctx.tables.terrain_rock));
	ctx.tables.terrain_water = int(tables.get("terrain_water", ctx.tables.terrain_water));
	ctx.tables.terrain_sand = int(tables.get("terrain_sand", ctx.tables.terrain_sand));
	ctx.tables.terrain_grass = int(tables.get("terrain_grass", ctx.tables.terrain_grass));
	ctx.tables.terrain_mined_floor = int(tables.get("terrain_mined_floor", ctx.tables.terrain_mined_floor));
	ctx.tables.terrain_mountain_entrance = int(tables.get("terrain_mountain_entrance", ctx.tables.terrain_mountain_entrance));
	return true;
}

bool load_interior_macro_context(const Dictionary &request, InteriorMacroContext &ctx) {
	ctx.chunk_coord = request.get("chunk_coord", Vector2i());
	ctx.chunk_size = int(request.get("chunk_size", 0));
	ctx.samples_per_tile = int(request.get("samples_per_tile", 1));
	ctx.interior_base_variant_count = int(request.get("interior_base_variant_count", 1));
	ctx.interior_target_mask = request.get("interior_target_mask", PackedByteArray());
	ctx.sand_color = request.get("sand_color", Color(1.0, 1.0, 1.0, 1.0));
	ctx.grass_color = request.get("grass_color", Color(1.0, 1.0, 1.0, 1.0));
	ctx.ground_color = request.get("ground_color", Color(1.0, 1.0, 1.0, 1.0));
	const int tile_count = ctx.chunk_size * ctx.chunk_size;
	return ctx.chunk_size > 0
		&& ctx.samples_per_tile > 0
		&& tile_count > 0
		&& ctx.interior_target_mask.size() == tile_count;
}

inline Color darkened_color(const Color &color, double amount) {
	const double factor = clampf_local(1.0 - amount, 0.0, 1.0);
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a);
}

inline Color alpha_blend_colors(const Color &base, const Color &over) {
	if (over.a <= 0.0) {
		return base;
	}
	const double out_alpha = over.a + base.a * (1.0 - over.a);
	if (out_alpha <= 0.0) {
		return Color(0.0, 0.0, 0.0, 0.0);
	}
	return Color(
		(over.r * over.a + base.r * base.a * (1.0 - over.a)) / out_alpha,
		(over.g * over.a + base.g * base.a * (1.0 - over.a)) / out_alpha,
		(over.b * over.a + base.b * base.a * (1.0 - over.a)) / out_alpha,
		out_alpha
	);
}

inline uint8_t encode_color_channel(double value) {
	return static_cast<uint8_t>(clampi_local(static_cast<int>(std::round(clampf_local(value, 0.0, 1.0) * 255.0)), 0, 255));
}

Dictionary build_interior_macro_overlay_internal(const InteriorMacroContext &ctx) {
	Dictionary result;
	const int sample_size = ctx.chunk_size * ctx.samples_per_tile;
	result["sample_size"] = sample_size;
	result["has_visible_pixels"] = false;
	if (sample_size <= 0) {
		return result;
	}
	PackedByteArray pixels;
	pixels.resize(sample_size * sample_size * 4);
	uint8_t *pixel_data = pixels.ptrw();
	const Vector2i world_sample_origin(
		ctx.chunk_coord.x * sample_size,
		ctx.chunk_coord.y * sample_size
	);
	bool has_visible_pixels = false;
	for (int sample_y = 0; sample_y < sample_size; ++sample_y) {
		const int local_tile_y = sample_y / ctx.samples_per_tile;
		for (int sample_x = 0; sample_x < sample_size; ++sample_x) {
			const int local_tile_x = sample_x / ctx.samples_per_tile;
			const int local_index = local_tile_y * ctx.chunk_size + local_tile_x;
			if (ctx.interior_target_mask[local_index] == 0) {
				continue;
			}
			const int global_tile_x = ctx.chunk_coord.x * ctx.chunk_size + local_tile_x;
			const int global_tile_y = ctx.chunk_coord.y * ctx.chunk_size + local_tile_y;
			const int family_index = resolve_interior_family(global_tile_x, global_tile_y, ctx.interior_base_variant_count);
			double dust_bias = 1.0;
			double moss_bias = 1.0;
			double crack_bias = 1.0;
			switch (family_index) {
				case 0:
					dust_bias = 1.25;
					moss_bias = 0.70;
					break;
				case 1:
					dust_bias = 0.90;
					crack_bias = 1.25;
					break;
				case 2:
					moss_bias = 1.35;
					dust_bias = 0.75;
					break;
				default:
					break;
			}
			const int world_sample_x = world_sample_origin.x + sample_x;
			const int world_sample_y = world_sample_origin.y + sample_y;
			Color blended(0.0, 0.0, 0.0, 0.0);
			const double dust_field = sample_interior_family_noise(world_sample_x, world_sample_y, 44.0, INTERIOR_MACRO_DUST_SEED);
			const double dust_detail = sample_interior_family_noise(world_sample_x, world_sample_y, 17.0, INTERIOR_MACRO_DUST_SEED + 7);
			const double dust_alpha = clampf_local((dust_field - 0.58) * 0.30 + std::max(0.0, dust_detail - 0.72) * 0.18, 0.0, 0.18) * dust_bias;
			if (dust_alpha > 0.01) {
				blended = alpha_blend_colors(
					blended,
					Color(ctx.sand_color.r, ctx.sand_color.g, ctx.sand_color.b, std::min(0.22, dust_alpha))
				);
			}
			const double moss_field = sample_interior_family_noise(world_sample_x, world_sample_y, 31.0, INTERIOR_MACRO_MOSS_SEED);
			const double moss_detail = sample_interior_family_noise(world_sample_x, world_sample_y, 12.0, INTERIOR_MACRO_MOSS_SEED + 9);
			const double moss_alpha = clampf_local((moss_field - 0.66) * 0.34 + std::max(0.0, moss_detail - 0.74) * 0.10, 0.0, 0.16) * moss_bias;
			if (moss_alpha > 0.01) {
				const Color moss_color = darkened_color(ctx.grass_color, 0.42);
				blended = alpha_blend_colors(
					blended,
					Color(moss_color.r, moss_color.g, moss_color.b, std::min(0.18, moss_alpha))
				);
			}
			const double crack_distance = std::abs(sample_interior_family_noise(world_sample_x, world_sample_y, 14.0, INTERIOR_MACRO_CRACK_SEED) - 0.5);
			const double crack_support = sample_interior_family_noise(world_sample_x, world_sample_y, 28.0, INTERIOR_MACRO_CRACK_SEED + 13);
			if (crack_support > 0.54 && crack_distance < 0.035) {
				const double crack_alpha = (0.035 - crack_distance) * 2.9 * crack_bias;
				const Color crack_color = darkened_color(ctx.ground_color, 0.58);
				blended = alpha_blend_colors(
					blended,
					Color(crack_color.r, crack_color.g, crack_color.b, std::min(0.16, crack_alpha))
				);
			}
			const double pebble_gate = sample_interior_family_noise(world_sample_x, world_sample_y, 9.0, INTERIOR_MACRO_PEBBLE_SEED);
			if (pebble_gate > 0.62 && (hash32_xy(world_sample_x, world_sample_y, INTERIOR_MACRO_PEBBLE_SEED + 19) & 7u) == 0u) {
				const Color pebble_color = darkened_color(ctx.ground_color, 0.45);
				blended = alpha_blend_colors(
					blended,
					Color(pebble_color.r, pebble_color.g, pebble_color.b, 0.12)
				);
			}
			if (blended.a <= 0.0) {
				continue;
			}
			has_visible_pixels = true;
			const int pixel_index = (sample_y * sample_size + sample_x) * 4;
			pixel_data[pixel_index] = encode_color_channel(blended.r);
			pixel_data[pixel_index + 1] = encode_color_channel(blended.g);
			pixel_data[pixel_index + 2] = encode_color_channel(blended.b);
			pixel_data[pixel_index + 3] = encode_color_channel(blended.a);
		}
	}
	result["has_visible_pixels"] = has_visible_pixels;
	result["pixels"] = has_visible_pixels ? pixels : PackedByteArray();
	return result;
}

bool has_valid_center_arrays(const VisualRequestContext &ctx) {
	const int tile_count = ctx.chunk_size * ctx.chunk_size;
	return tile_count > 0
		&& ctx.terrain_bytes.size() == tile_count
		&& ctx.height_bytes.size() == tile_count
		&& ctx.variation_bytes.size() == tile_count
		&& ctx.biome_bytes.size() == tile_count;
}

bool has_valid_terrain_halo(const VisualRequestContext &ctx) {
	const int halo_stride = ctx.chunk_size + 2;
	return ctx.terrain_halo.size() == halo_stride * halo_stride;
}

Dictionary surface_palette(const VisualTables &tables, int biome_palette_index) {
	if (tables.surface_palette_tiles.is_empty()) {
		return Dictionary();
	}
	const int clamped_index = clampi_local(biome_palette_index, 0, tables.surface_palette_tiles.size() - 1);
	return tables.surface_palette_tiles[clamped_index];
}

Vector2i coords_for_linear_index(const VisualTables &tables, int index) {
	const int columns = std::max(1, tables.terrain_tiles_per_row);
	return Vector2i(index % columns, index / columns);
}

int terrain_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.uses_native_arrays) {
		if (local_tile.x >= 0 && local_tile.y >= 0 && local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size && has_valid_center_arrays(ctx)) {
			return ctx.terrain_bytes[local_tile.y * ctx.chunk_size + local_tile.x];
		}
		if (has_valid_terrain_halo(ctx)) {
			const int halo_stride = ctx.chunk_size + 2;
			const int halo_x = local_tile.x + 1;
			const int halo_y = local_tile.y + 1;
			if (halo_x >= 0 && halo_y >= 0 && halo_x < halo_stride && halo_y < halo_stride) {
				return ctx.terrain_halo[halo_y * halo_stride + halo_x];
			}
		}
	}
	return int(ctx.terrain_lookup.get(local_tile, ctx.tables.terrain_rock));
}

double height_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.uses_native_arrays && local_tile.x >= 0 && local_tile.y >= 0 && local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size && has_valid_center_arrays(ctx)) {
		return ctx.height_bytes[local_tile.y * ctx.chunk_size + local_tile.x];
	}
	return double(ctx.height_lookup.get(local_tile, 0.5));
}

int variation_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.uses_native_arrays && local_tile.x >= 0 && local_tile.y >= 0 && local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size && has_valid_center_arrays(ctx)) {
		return ctx.variation_bytes[local_tile.y * ctx.chunk_size + local_tile.x];
	}
	return int(ctx.variation_lookup.get(local_tile, ctx.tables.surface_variation_none));
}

int primary_biome_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.uses_native_arrays && local_tile.x >= 0 && local_tile.y >= 0 && local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size && has_valid_center_arrays(ctx)) {
		return ctx.biome_bytes[local_tile.y * ctx.chunk_size + local_tile.x];
	}
	return int(ctx.biome_lookup.get(local_tile, 0));
}

int secondary_biome_at(const VisualRequestContext &ctx, const Vector2i &local_tile, int fallback_value) {
	if (ctx.uses_native_arrays
		&& local_tile.x >= 0 && local_tile.y >= 0
		&& local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size
		&& has_valid_center_arrays(ctx)
		&& ctx.secondary_biome_bytes.size() == ctx.biome_bytes.size()) {
		return ctx.secondary_biome_bytes[local_tile.y * ctx.chunk_size + local_tile.x];
	}
	return int(ctx.secondary_biome_lookup.get(local_tile, fallback_value));
}

double ecotone_factor_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.uses_native_arrays
		&& local_tile.x >= 0 && local_tile.y >= 0
		&& local_tile.x < ctx.chunk_size && local_tile.y < ctx.chunk_size
		&& has_valid_center_arrays(ctx)
		&& ctx.ecotone_values.size() == ctx.biome_bytes.size()) {
		return ctx.ecotone_values[local_tile.y * ctx.chunk_size + local_tile.x];
	}
	return double(ctx.ecotone_lookup.get(local_tile, 0.0));
}

Vector2i to_global_tile(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	return Vector2i(
		ctx.chunk_coord.x * ctx.chunk_size + local_tile.x,
		ctx.chunk_coord.y * ctx.chunk_size + local_tile.y
	);
}

double resolve_ecotone_secondary_weight(double ecotone_factor) {
	const double normalized_factor = clampf_local(
		(ecotone_factor - ECOTONE_BLEND_START) / std::max(0.001, 1.0 - ECOTONE_BLEND_START),
		0.0,
		1.0
	);
	return 0.5 * smoothstep01(normalized_factor);
}

double sample_ecotone_blend_noise(int global_x, int global_y, double scale, int seed) {
	const double resolved_scale = std::max(1.0, scale);
	const double scaled_x = static_cast<double>(global_x) / resolved_scale;
	const double scaled_y = static_cast<double>(global_y) / resolved_scale;
	const int cell_x = static_cast<int>(std::floor(scaled_x));
	const int cell_y = static_cast<int>(std::floor(scaled_y));
	const double frac_x = smoothstep01(scaled_x - static_cast<double>(cell_x));
	const double frac_y = smoothstep01(scaled_y - static_cast<double>(cell_y));
	const double v00 = hash32_to_unit_float(hash32_xy(cell_x, cell_y, seed));
	const double v10 = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y, seed));
	const double v01 = hash32_to_unit_float(hash32_xy(cell_x, cell_y + 1, seed));
	const double v11 = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y + 1, seed));
	return lerpf_local(lerpf_local(v00, v10, frac_x), lerpf_local(v01, v11, frac_x), frac_y);
}

int biome_at(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	const int primary_biome_palette_index = primary_biome_at(ctx, local_tile);
	const int secondary_biome_palette_index = secondary_biome_at(ctx, local_tile, primary_biome_palette_index);
	if (secondary_biome_palette_index == primary_biome_palette_index) {
		return primary_biome_palette_index;
	}
	const double secondary_weight = resolve_ecotone_secondary_weight(ecotone_factor_at(ctx, local_tile));
	if (secondary_weight <= 0.0) {
		return primary_biome_palette_index;
	}
	const Vector2i global_tile = to_global_tile(ctx, local_tile);
	const double blend_noise = sample_ecotone_blend_noise(global_tile.x, global_tile.y, ECOTONE_BLEND_SCALE, ECOTONE_BLEND_SEED);
	return blend_noise < secondary_weight ? secondary_biome_palette_index : primary_biome_palette_index;
}

bool is_open_for_visual(const VisualRequestContext &ctx, int terrain_type) {
	return terrain_type != ctx.tables.terrain_rock;
}

bool is_open_exterior(const VisualRequestContext &ctx, int terrain_type) {
	return terrain_type == ctx.tables.terrain_ground
		|| terrain_type == ctx.tables.terrain_water
		|| terrain_type == ctx.tables.terrain_sand
		|| terrain_type == ctx.tables.terrain_grass;
}

bool is_open_for_surface_rock_visual(const VisualRequestContext &ctx, int terrain_type) {
	return is_open_exterior(ctx, terrain_type)
		|| terrain_type == ctx.tables.terrain_mined_floor
		|| terrain_type == ctx.tables.terrain_mountain_entrance;
}

bool is_open_for_surface_visual(const VisualRequestContext &ctx, int terrain_type, bool water_only) {
	return water_only ? terrain_type == ctx.tables.terrain_water : is_open_for_surface_rock_visual(ctx, terrain_type);
}

bool has_water_face_neighbor(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	for (const Vector2i &dir : COVER_REVEAL_DIRS) {
		if (terrain_at(ctx, local_tile + dir) == ctx.tables.terrain_water) {
			return true;
		}
	}
	return false;
}

bool is_surface_face_terrain(const VisualRequestContext &ctx, int terrain_type) {
	return terrain_type == ctx.tables.terrain_ground
		|| terrain_type == ctx.tables.terrain_grass
		|| terrain_type == ctx.tables.terrain_sand;
}

Vector2i ground_atlas_for_height(const VisualRequestContext &ctx, double height_value) {
	if (height_value < 0.38) return ctx.tables.tile_ground_dark;
	if (height_value > 0.62) return ctx.tables.tile_ground_light;
	return ctx.tables.tile_ground;
}

Vector2i get_surface_ground_tile(const VisualTables &tables, int biome_palette_index, double height_value) {
	const Dictionary palette = surface_palette(tables, biome_palette_index);
	if (height_value < 0.38) return palette.get("ground_dark", tables.tile_ground_dark);
	if (height_value > 0.62) return palette.get("ground_light", tables.tile_ground_light);
	return palette.get("ground", tables.tile_ground);
}

Vector2i get_surface_terrain_tile(const VisualTables &tables, int terrain_type, int biome_palette_index) {
	const Dictionary palette = surface_palette(tables, biome_palette_index);
	if (terrain_type == tables.terrain_water) return palette.get("water", tables.tile_water);
	if (terrain_type == tables.terrain_sand) return palette.get("sand", tables.tile_sand);
	if (terrain_type == tables.terrain_grass) return palette.get("grass", tables.tile_grass);
	return Vector2i(-1, -1);
}

Vector2i get_surface_variation_tile(const VisualTables &tables, int variation_id, int biome_palette_index) {
	const Dictionary palette = surface_palette(tables, biome_palette_index);
	switch (variation_id) {
		case 1: return palette.get("sparse_flora", tables.tile_sparse_flora);
		case 2: return palette.get("dense_flora", tables.tile_dense_flora);
		case 3: return palette.get("clearing", tables.tile_clearing);
		case 4: return palette.get("rocky_patch", tables.tile_rocky_patch);
		case 5: return palette.get("wet_patch", tables.tile_wet_patch);
		case 6: return palette.get("ice", tables.tile_ice);
		case 7: return palette.get("scorched", tables.tile_scorched);
		case 8: return palette.get("salt_flat", tables.tile_salt_flat);
		case 9: return palette.get("dry_riverbed", tables.tile_dry_riverbed);
		default: return Vector2i(-1, -1);
	}
}

Vector2i surface_ground_atlas(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (ctx.is_underground) {
		return ground_atlas_for_height(ctx, height_at(ctx, local_tile));
	}
	const int biome_palette_index = biome_at(ctx, local_tile);
	const Vector2i variation_tile = get_surface_variation_tile(ctx.tables, variation_at(ctx, local_tile), biome_palette_index);
	return variation_tile.x >= 0 ? variation_tile : get_surface_ground_tile(ctx.tables, biome_palette_index, height_at(ctx, local_tile));
}

int wall_def_index(const Vector2i &wall) {
	const int def_index = wall.x - 7;
	return def_index < 0 || def_index >= 47 ? -1 : def_index;
}

Vector2i get_wall_variant_coords(const VisualTables &tables, const Vector2i &base, int variant_index) {
	const int def_index = base.x - 7;
	if (def_index < 0 || tables.wall_base_count <= 0) {
		return base;
	}
	return coords_for_linear_index(tables, 7 + def_index + variant_index * tables.wall_base_count);
}

Vector2i get_face_coords(const VisualTables &tables, const Vector2i &wall, int biome_palette_index, int variant_index, bool sand_face) {
	const int def_index = wall_def_index(wall);
	if (def_index < 0) {
		return Vector2i(-1, -1);
	}
	if (biome_palette_index >= 0) {
		const Dictionary palette = surface_palette(tables, biome_palette_index);
		if (wall == wall_def(0)) {
			const int interior_start = int(palette.get(sand_face ? "sand_face_interior_start" : "ground_face_interior_start", -1));
			const int interior_count = int(palette.get(sand_face ? "sand_face_interior_count" : "ground_face_interior_count", 0));
			if (interior_start >= 0 && interior_count > 0) {
				return coords_for_linear_index(tables, interior_start + clampi_local(variant_index, 0, interior_count - 1));
			}
		}
		const int start = int(palette.get(sand_face ? "sand_face_start" : "ground_face_start", -1));
		if (start >= 0) {
			return coords_for_linear_index(tables, start + def_index);
		}
	}
	const int fallback_start = sand_face ? tables.sand_face_tiles_start : tables.ground_face_tiles_start;
	return fallback_start < 0 ? Vector2i(-1, -1) : coords_for_linear_index(tables, fallback_start + def_index);
}

uint32_t hash32_xy(int tile_x, int tile_y, int seed) {
	uint32_t h = static_cast<uint32_t>(
		static_cast<int64_t>(tile_x) * 374761393LL
		+ static_cast<int64_t>(tile_y) * 668265263LL
		+ static_cast<int64_t>(seed) * 1442695041LL
	);
	h = (h ^ (h >> 13)) & HASH32_MASK;
	h = (h * 1274126177u) & HASH32_MASK;
	h = (h ^ (h >> 16)) & HASH32_MASK;
	return h;
}

double hash32_to_unit_float(uint32_t h) {
	return static_cast<double>(h & HASH32_MASK) / static_cast<double>(HASH32_MASK);
}

double smoothstep01(double t) {
	const double clamped = clampf_local(t, 0.0, 1.0);
	return clamped * clamped * (3.0 - 2.0 * clamped);
}

int interior_family_count(int base_count) {
	return std::max(1, std::min(INTERIOR_FAMILY_TARGET_COUNT, base_count));
}

Vector2i interior_family_window(int base_count, int family_index) {
	const int family_count = interior_family_count(base_count);
	const int clamped_family = clampi_local(family_index, 0, family_count - 1);
	const int window_size = std::max(1, std::min(base_count, INTERIOR_FAMILY_WINDOW_SIZE));
	if (base_count <= window_size || family_count <= 1) {
		return Vector2i(0, base_count);
	}
	const int max_start = base_count - window_size;
	const int start = static_cast<int>(std::round(static_cast<double>(clamped_family * max_start) / static_cast<double>(family_count - 1)));
	return Vector2i(start, window_size);
}

double sample_interior_family_noise(int global_x, int global_y, double scale, int seed) {
	const double scaled_x = static_cast<double>(global_x) / scale;
	const double scaled_y = static_cast<double>(global_y) / scale;
	const int cell_x = static_cast<int>(std::floor(scaled_x));
	const int cell_y = static_cast<int>(std::floor(scaled_y));
	const double frac_x = smoothstep01(scaled_x - static_cast<double>(cell_x));
	const double frac_y = smoothstep01(scaled_y - static_cast<double>(cell_y));
	const double v00 = hash32_to_unit_float(hash32_xy(cell_x, cell_y, seed));
	const double v10 = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y, seed));
	const double v01 = hash32_to_unit_float(hash32_xy(cell_x, cell_y + 1, seed));
	const double v11 = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y + 1, seed));
	return lerpf_local(lerpf_local(v00, v10, frac_x), lerpf_local(v01, v11, frac_x), frac_y);
}

int resolve_interior_family(int global_x, int global_y, int base_count) {
	const int family_count = interior_family_count(base_count);
	if (family_count <= 1) {
		return 0;
	}
	const double macro_noise = sample_interior_family_noise(global_x, global_y, INTERIOR_FAMILY_SCALE, INTERIOR_FAMILY_SEED);
	const double detail_noise = sample_interior_family_noise(global_x, global_y, INTERIOR_FAMILY_DETAIL_SCALE, INTERIOR_FAMILY_SEED + 53);
	const double blended_noise = clampf_local(macro_noise * 0.82 + detail_noise * 0.18, 0.0, 0.999999);
	return std::min(family_count - 1, static_cast<int>(std::floor(blended_noise * family_count)));
}

int shift_interior_family_base(int base_index, const Vector2i &family_window, int step) {
	if (family_window.y <= 1) {
		return family_window.x;
	}
	return family_window.x + ((base_index - family_window.x + step) % family_window.y);
}

Vector2i raw_interior_variant(const VisualTables &tables, int global_x, int global_y, int family_index, int seed = INTERIOR_VARIATION_SEED) {
	const int base_count = tables.interior_base_variant_count;
	if (base_count <= 0) {
		return Vector2i();
	}
	const Vector2i family_window = interior_family_window(base_count, family_index);
	const uint32_t h = hash32_xy(global_x, global_y, seed);
	return Vector2i(
		family_window.x + static_cast<int>(h % static_cast<uint32_t>(family_window.y)),
		static_cast<int>((h >> 8) & static_cast<uint32_t>(std::max(1, tables.interior_transform_count) - 1))
	);
}

Vector2i interior_variant(const VisualTables &tables, int global_x, int global_y) {
	const int base_count = tables.interior_base_variant_count;
	if (base_count <= 0) {
		return Vector2i();
	}
	const int resolved_family = resolve_interior_family(global_x, global_y, base_count);
	const Vector2i family_window = interior_family_window(base_count, resolved_family);
	Vector2i resolved = raw_interior_variant(tables, global_x, global_y, resolved_family);
	const Vector2i left = raw_interior_variant(tables, global_x - 1, global_y, resolve_interior_family(global_x - 1, global_y, base_count));
	const Vector2i top = raw_interior_variant(tables, global_x, global_y - 1, resolve_interior_family(global_x, global_y - 1, base_count));
	const int transform_count = std::max(1, tables.interior_transform_count);
	if (resolved == left && resolved == top) {
		resolved = raw_interior_variant(tables, global_x, global_y, resolved_family, INTERIOR_REHASH_SEED);
	}
	if (resolved == left) {
		resolved.y = (resolved.y + 1) % transform_count;
	}
	if (resolved == top) {
		resolved.y = family_window.y > 1 ? resolved.y : (resolved.y + 3) % transform_count;
		if (family_window.y > 1) {
			resolved.x = shift_interior_family_base(resolved.x, family_window, 1);
		}
	}
	if (resolved == left || resolved == top) {
		resolved = raw_interior_variant(tables, global_x, global_y, resolved_family, INTERIOR_REHASH_SEED + 97);
		if (resolved == left) {
			resolved.y = (resolved.y + 5) % transform_count;
		}
		if (resolved == top) {
			resolved.y = family_window.y > 1 ? resolved.y : (resolved.y + 2) % transform_count;
			if (family_window.y > 1) {
				resolved.x = shift_interior_family_base(resolved.x, family_window, 2);
			}
		}
	}
	return resolved;
}

Vector2i variant_atlas(const VisualRequestContext &ctx, const Vector2i &base, int global_x, int global_y) {
	if (base == wall_def(0)) {
		return get_wall_variant_coords(ctx.tables, base, interior_variant(ctx.tables, global_x, global_y).x);
	}
	return get_wall_variant_coords(ctx.tables, base, 0);
}

int variant_alt_id(const VisualRequestContext &ctx, const Vector2i &base, int global_x, int global_y, bool allow_flip) {
	if (base == wall_def(0)) {
		return interior_variant(ctx.tables, global_x, global_y).y;
	}
	if (!allow_flip) {
		return 0;
	}
	const int def_index = base.x - 7;
	if (def_index < 0 || def_index >= ctx.tables.wall_flip_class.size()) {
		return 0;
	}
	const uint8_t *flip_class = ctx.tables.wall_flip_class.ptr();
	const int flip_class_id = static_cast<int>(flip_class[def_index]);
	if (flip_class_id <= 0 || flip_class_id >= ctx.tables.wall_flip_alt_count.size()) {
		return 0;
	}
	const uint8_t *alt_counts = ctx.tables.wall_flip_alt_count.ptr();
	const int alt_count = static_cast<int>(alt_counts[flip_class_id]);
	return alt_count <= 0 ? 0 : static_cast<int>(hash32_xy(global_x + 17, global_y + 31, 0) % static_cast<uint32_t>(alt_count));
}

int linear_index_for_coords(const VisualTables &tables, const Vector2i &coords) {
	if (coords.x < 0 || coords.y < 0) {
		return -1;
	}
	return coords.y * std::max(1, tables.terrain_tiles_per_row) + coords.x;
}

int pack_cover_mask(int atlas_index, int alt_id) {
	if (atlas_index < 0) {
		return -1;
	}
	return (atlas_index << 8) | (alt_id & 0xff);
}

Vector2i surface_visual_class(const VisualRequestContext &ctx, const Vector2i &local_tile, bool water_only) {
	const bool s = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(0, 1)), water_only);
	const bool n = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(0, -1)), water_only);
	const bool w = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 0)), water_only);
	const bool e = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 0)), water_only);
	const int count = int(s) + int(n) + int(w) + int(e);
	if (count == 4) return wall_def(46);
	if (count == 3) { if (!n) return wall_def(43); if (!s) return wall_def(42); if (!w) return wall_def(44); return wall_def(45); }
	if (count == 2) {
		if (s && w) return wall_def(36);
		if (s && e) return wall_def(38);
		if (n && w) return wall_def(32);
		if (n && e) return wall_def(34);
		return (w && e) ? wall_def(41) : wall_def(40);
	}
	if (count == 1) {
		if (s) {
			const bool ne = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)), water_only);
			const bool nw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)), water_only);
			if (ne && nw) return wall_def(23);
			if (ne) return wall_def(21);
			return nw ? wall_def(22) : wall_def(20);
		}
		if (n) {
			const bool se = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)), water_only);
			const bool sw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)), water_only);
			if (se && sw) return wall_def(19);
			if (se) return wall_def(17);
			return sw ? wall_def(18) : wall_def(16);
		}
		if (w) {
			const bool ne = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)), water_only);
			const bool se = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)), water_only);
			if (ne && se) return wall_def(31);
			if (ne) return wall_def(29);
			return se ? wall_def(30) : wall_def(28);
		}
		const bool nw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)), water_only);
		const bool sw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)), water_only);
		if (nw && sw) return wall_def(27);
		if (nw) return wall_def(25);
		return sw ? wall_def(26) : wall_def(24);
	}
	const bool d_sw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)), water_only);
	const bool d_se = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)), water_only);
	const bool d_ne = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)), water_only);
	const bool d_nw = is_open_for_surface_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)), water_only);
	const int d_count = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw);
	if (d_count == 4) return wall_def(15);
	if (d_count == 3) { if (!d_sw) return wall_def(11); if (!d_se) return wall_def(12); if (!d_nw) return wall_def(13); return wall_def(14); }
	if (d_count == 2) {
		if (d_sw && d_se) return wall_def(10);
		if (d_ne && d_nw) return wall_def(5);
		if (d_ne && d_se) return wall_def(6);
		if (d_nw && d_sw) return wall_def(9);
		return (d_ne && d_sw) ? wall_def(7) : wall_def(8);
	}
	if (d_sw) return wall_def(4);
	if (d_se) return wall_def(3);
	if (d_ne) return wall_def(1);
	return d_nw ? wall_def(2) : wall_def(0);
}

Vector2i rock_visual_class(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	const bool s = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(0, 1)));
	const bool n = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(0, -1)));
	const bool w = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 0)));
	const bool e = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 0)));
	const int count = int(s) + int(n) + int(w) + int(e);
	if (count == 4) return wall_def(46);
	if (count == 3) { if (!n) return wall_def(43); if (!s) return wall_def(42); if (!w) return wall_def(44); return wall_def(45); }
	if (count == 2) {
		if (s && w) return is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1))) ? wall_def(37) : wall_def(36);
		if (s && e) return is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1))) ? wall_def(39) : wall_def(38);
		if (n && w) return is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1))) ? wall_def(33) : wall_def(32);
		if (n && e) return is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1))) ? wall_def(35) : wall_def(34);
		return (w && e) ? wall_def(41) : wall_def(40);
	}
	if (count == 1) {
		if (s) {
			const bool ne = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)));
			const bool nw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)));
			if (ne && nw) return wall_def(23);
			if (ne) return wall_def(21);
			return nw ? wall_def(22) : wall_def(20);
		}
		if (n) {
			const bool se = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)));
			const bool sw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)));
			if (se && sw) return wall_def(19);
			if (se) return wall_def(17);
			return sw ? wall_def(18) : wall_def(16);
		}
		if (w) {
			const bool ne = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)));
			const bool se = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)));
			if (ne && se) return wall_def(31);
			if (ne) return wall_def(29);
			return se ? wall_def(30) : wall_def(28);
		}
		const bool nw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)));
		const bool sw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)));
		if (nw && sw) return wall_def(27);
		if (nw) return wall_def(25);
		return sw ? wall_def(26) : wall_def(24);
	}
	const bool d_sw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 1)));
	const bool d_se = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, 1)));
	const bool d_ne = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(1, -1)));
	const bool d_nw = is_open_for_visual(ctx, terrain_at(ctx, local_tile + Vector2i(-1, -1)));
	const int d_count = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw);
	if (d_count == 4) return wall_def(15);
	if (d_count == 3) { if (!d_sw) return wall_def(11); if (!d_se) return wall_def(12); if (!d_nw) return wall_def(13); return wall_def(14); }
	if (d_count == 2) {
		if (d_sw && d_se) return wall_def(10);
		if (d_ne && d_nw) return wall_def(5);
		if (d_ne && d_se) return wall_def(6);
		if (d_nw && d_sw) return wall_def(9);
		return (d_ne && d_sw) ? wall_def(7) : wall_def(8);
	}
	if (d_sw) return wall_def(4);
	if (d_se) return wall_def(3);
	if (d_ne) return wall_def(1);
	return d_nw ? wall_def(2) : wall_def(0);
}

bool is_cave_edge_rock(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	if (terrain_at(ctx, local_tile) != ctx.tables.terrain_rock) return false;
	bool has_open_neighbor = false;
	for (const Vector2i &dir : COVER_REVEAL_DIRS) {
		const int neighbor_type = terrain_at(ctx, local_tile + dir);
		if (is_open_exterior(ctx, neighbor_type)) return false;
		if (neighbor_type == ctx.tables.terrain_mined_floor || neighbor_type == ctx.tables.terrain_mountain_entrance) has_open_neighbor = true;
	}
	return has_open_neighbor;
}

bool is_exterior_surface_rock(const VisualRequestContext &ctx, const Vector2i &local_tile) {
	for (const Vector2i &dir : COVER_REVEAL_DIRS) {
		if (is_open_exterior(ctx, terrain_at(ctx, local_tile + dir))) return true;
	}
	return false;
}

PackedInt32Array *buffer_for_layer(LayeredCommandBuffers &buffers, int layer) {
	switch (layer) {
		case VISUAL_LAYER_TERRAIN:
			return &buffers.terrain;
		case VISUAL_LAYER_GROUND_FACE:
			return &buffers.ground_face;
		case VISUAL_LAYER_ROCK:
			return &buffers.rock;
		case VISUAL_LAYER_COVER:
			return &buffers.cover;
		case VISUAL_LAYER_CLIFF:
			return &buffers.cliff;
		default:
			return nullptr;
	}
}

void append_buffer_set_command(PackedInt32Array &buffer, const Vector2i &local_tile, int source_id, const Vector2i &atlas, int alt_id) {
	buffer.push_back(local_tile.x);
	buffer.push_back(local_tile.y);
	buffer.push_back(VISUAL_COMMAND_OP_SET);
	buffer.push_back(source_id);
	buffer.push_back(atlas.x);
	buffer.push_back(atlas.y);
	buffer.push_back(alt_id);
}

void append_buffer_erase_command(PackedInt32Array &buffer, const Vector2i &local_tile) {
	buffer.push_back(local_tile.x);
	buffer.push_back(local_tile.y);
	buffer.push_back(VISUAL_COMMAND_OP_ERASE);
	buffer.push_back(0);
	buffer.push_back(0);
	buffer.push_back(0);
	buffer.push_back(0);
}

void append_set_command(LayeredCommandBuffers &buffers, int layer, const Vector2i &local_tile, int source_id, const Vector2i &atlas, int alt_id) {
	PackedInt32Array *buffer = buffer_for_layer(buffers, layer);
	if (buffer == nullptr) {
		return;
	}
	append_buffer_set_command(*buffer, local_tile, source_id, atlas, alt_id);
	buffers.command_count += 1;
}

void append_erase_command(LayeredCommandBuffers &buffers, int layer, const Vector2i &local_tile) {
	PackedInt32Array *buffer = buffer_for_layer(buffers, layer);
	if (buffer == nullptr) {
		return;
	}
	append_buffer_erase_command(*buffer, local_tile);
	buffers.command_count += 1;
}

void append_ground_face_visual_command(const VisualRequestContext &ctx, const Vector2i &local_tile, int terrain_type, LayeredCommandBuffers &buffers, bool explicit_clear) {
	if (ctx.is_underground) {
		if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_GROUND_FACE, local_tile);
		return;
	}
	Vector2i atlas(-1, -1);
	int alt_id = 0;
	if (is_surface_face_terrain(ctx, terrain_type)) {
		Vector2i wall = wall_def(0);
		Vector2i interior = Vector2i();
		const Vector2i global_tile = to_global_tile(ctx, local_tile);
		if (has_water_face_neighbor(ctx, local_tile)) {
			wall = surface_visual_class(ctx, local_tile, true);
		} else {
			interior = interior_variant(ctx.tables, global_tile.x, global_tile.y);
			alt_id = interior.y;
		}
		const int biome_palette_index = biome_at(ctx, local_tile);
		if (terrain_type == ctx.tables.terrain_ground || terrain_type == ctx.tables.terrain_grass) atlas = get_face_coords(ctx.tables, wall, biome_palette_index, interior.x, false);
		else if (terrain_type == ctx.tables.terrain_sand) atlas = get_face_coords(ctx.tables, wall, biome_palette_index, interior.x, true);
	}
	if (atlas.x >= 0) append_set_command(buffers, VISUAL_LAYER_GROUND_FACE, local_tile, ctx.tables.terrain_source_id, atlas, alt_id);
	else if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_GROUND_FACE, local_tile);
}

void append_cover_visual_command(const VisualRequestContext &ctx, const Vector2i &local_tile, LayeredCommandBuffers &buffers, bool explicit_clear) {
	if (ctx.is_underground) {
		if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_COVER, local_tile);
		return;
	}
	const int terrain_type = terrain_at(ctx, local_tile);
	if (terrain_type != ctx.tables.terrain_mined_floor && !is_cave_edge_rock(ctx, local_tile)) {
		if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_COVER, local_tile);
		return;
	}
	const Vector2i base = is_exterior_surface_rock(ctx, local_tile) ? wall_def(20) : wall_def(0);
	const Vector2i global_tile = to_global_tile(ctx, local_tile);
	append_set_command(buffers, VISUAL_LAYER_COVER, local_tile, ctx.tables.terrain_source_id, variant_atlas(ctx, base, global_tile.x, global_tile.y), variant_alt_id(ctx, base, global_tile.x, global_tile.y, false));
}

void append_cliff_visual_command(const VisualRequestContext &ctx, const Vector2i &local_tile, LayeredCommandBuffers &buffers, bool explicit_clear) {
	if (ctx.is_underground) {
		if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_CLIFF, local_tile);
		return;
	}
	if (terrain_at(ctx, local_tile) != ctx.tables.terrain_rock) {
		if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_CLIFF, local_tile);
		return;
	}
	Vector2i overlay(-1, -1);
	if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(0, 1)))) overlay = ctx.tables.tile_shadow_south;
	else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 0)))) overlay = ctx.tables.tile_shadow_west;
	else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(1, 0)))) overlay = ctx.tables.tile_shadow_east;
	else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(0, -1)))) overlay = ctx.tables.tile_top_edge;
	if (overlay.x >= 0) append_set_command(buffers, VISUAL_LAYER_CLIFF, local_tile, ctx.tables.overlay_source_id, overlay, 0);
	else if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_CLIFF, local_tile);
}

void append_terrain_visual_commands(const VisualRequestContext &ctx, const Vector2i &local_tile, LayeredCommandBuffers &buffers, bool explicit_clear) {
	const int terrain_type = terrain_at(ctx, local_tile);
	Vector2i atlas = ctx.tables.tile_ground;
	Vector2i rock_atlas(-1, -1);
	int rock_alt_id = 0;
	const int biome_palette_index = biome_at(ctx, local_tile);
	int variation_id = ctx.tables.surface_variation_none;
	Vector2i variation_tile(-1, -1);
	if (!ctx.is_underground) {
		variation_id = variation_at(ctx, local_tile);
		variation_tile = get_surface_variation_tile(ctx.tables, variation_id, biome_palette_index);
	}
	if (terrain_type == ctx.tables.terrain_rock) {
		atlas = surface_ground_atlas(ctx, local_tile);
		Vector2i rock_visual = ctx.is_underground ? rock_visual_class(ctx, local_tile) : surface_visual_class(ctx, local_tile, false);
		const Vector2i global_tile = to_global_tile(ctx, local_tile);
		rock_atlas = variant_atlas(ctx, rock_visual, global_tile.x, global_tile.y);
		rock_alt_id = variant_alt_id(ctx, rock_visual, global_tile.x, global_tile.y, ctx.is_underground);
	} else if (terrain_type == ctx.tables.terrain_water) {
		atlas = variation_id == 6 && variation_tile.x >= 0 ? variation_tile : get_surface_terrain_tile(ctx.tables, terrain_type, biome_palette_index);
	} else if (terrain_type == ctx.tables.terrain_sand || terrain_type == ctx.tables.terrain_grass) {
		atlas = variation_tile.x >= 0 ? variation_tile : get_surface_terrain_tile(ctx.tables, terrain_type, biome_palette_index);
	} else if (terrain_type == ctx.tables.terrain_mined_floor) atlas = ctx.tables.tile_mined_floor;
	else if (terrain_type == ctx.tables.terrain_mountain_entrance) atlas = ctx.tables.tile_mountain_entrance;
	else atlas = variation_tile.x >= 0 ? variation_tile : surface_ground_atlas(ctx, local_tile);
	append_set_command(buffers, VISUAL_LAYER_TERRAIN, local_tile, ctx.tables.terrain_source_id, atlas, 0);
	append_ground_face_visual_command(ctx, local_tile, terrain_type, buffers, explicit_clear);
	if (rock_atlas.x >= 0) append_set_command(buffers, VISUAL_LAYER_ROCK, local_tile, ctx.tables.terrain_source_id, rock_atlas, rock_alt_id);
	else if (explicit_clear) append_erase_command(buffers, VISUAL_LAYER_ROCK, local_tile);
}

Dictionary build_prebaked_visual_payload_internal(const VisualRequestContext &ctx) {
	Dictionary result;
	if (!has_valid_center_arrays(ctx) || !has_valid_terrain_halo(ctx)) {
		return result;
	}
	const int tile_count = ctx.chunk_size * ctx.chunk_size;
	PackedByteArray rock_visual_class_bytes;
	PackedInt32Array ground_face_atlas;
	PackedInt32Array cover_mask;
	PackedByteArray cliff_overlay;
	PackedByteArray variant_id_bytes;
	PackedInt32Array alt_id_values;
	rock_visual_class_bytes.resize(tile_count);
	ground_face_atlas.resize(tile_count);
	cover_mask.resize(tile_count);
	cliff_overlay.resize(tile_count);
	variant_id_bytes.resize(tile_count);
	alt_id_values.resize(tile_count);
	for (int idx = 0; idx < tile_count; ++idx) {
		rock_visual_class_bytes[idx] = PREBAKED_ROCK_VISUAL_NONE;
		ground_face_atlas[idx] = -1;
		cover_mask[idx] = -1;
		cliff_overlay[idx] = PREBAKED_CLIFF_NONE;
		variant_id_bytes[idx] = 0;
		alt_id_values[idx] = 0;
	}
	for (int local_y = 0; local_y < ctx.chunk_size; ++local_y) {
		for (int local_x = 0; local_x < ctx.chunk_size; ++local_x) {
			const Vector2i local_tile(local_x, local_y);
			const int idx = local_y * ctx.chunk_size + local_x;
			const int terrain_type = terrain_at(ctx, local_tile);
			const Vector2i global_tile = to_global_tile(ctx, local_tile);
			Vector2i shared_base(-1, -1);
			Vector2i shared_interior = Vector2i();
			bool shared_has_interior = false;
			if (!ctx.is_underground && is_surface_face_terrain(ctx, terrain_type)) {
				Vector2i face_wall = wall_def(0);
				Vector2i interior = Vector2i();
				if (has_water_face_neighbor(ctx, local_tile)) {
					face_wall = surface_visual_class(ctx, local_tile, true);
				} else {
					interior = interior_variant(ctx.tables, global_tile.x, global_tile.y);
				}
				const int biome_palette_index = biome_at(ctx, local_tile);
				Vector2i face_atlas(-1, -1);
				if (terrain_type == ctx.tables.terrain_ground || terrain_type == ctx.tables.terrain_grass) {
					face_atlas = get_face_coords(ctx.tables, face_wall, biome_palette_index, interior.x, false);
				} else if (terrain_type == ctx.tables.terrain_sand) {
					face_atlas = get_face_coords(ctx.tables, face_wall, biome_palette_index, interior.x, true);
				}
				ground_face_atlas[idx] = linear_index_for_coords(ctx.tables, face_atlas);
				shared_base = face_wall;
				shared_interior = interior;
				shared_has_interior = face_wall == wall_def(0);
			}
			if (terrain_type == ctx.tables.terrain_rock) {
				const Vector2i rock_visual = ctx.is_underground ? rock_visual_class(ctx, local_tile) : surface_visual_class(ctx, local_tile, false);
				rock_visual_class_bytes[idx] = wall_def_index(rock_visual);
				shared_base = rock_visual;
				shared_has_interior = rock_visual == wall_def(0);
				if (shared_has_interior) {
					shared_interior = interior_variant(ctx.tables, global_tile.x, global_tile.y);
				}
			}
			if (!ctx.is_underground && (terrain_type == ctx.tables.terrain_mined_floor || is_cave_edge_rock(ctx, local_tile))) {
				const Vector2i cover_base = is_exterior_surface_rock(ctx, local_tile) ? wall_def(20) : wall_def(0);
				Vector2i cover_interior = Vector2i();
				int cover_alt_id = 0;
				int cover_variant = 0;
				if (cover_base == wall_def(0)) {
					cover_interior = interior_variant(ctx.tables, global_tile.x, global_tile.y);
					cover_variant = cover_interior.x;
					cover_alt_id = cover_interior.y;
					if (shared_base.x < 0) {
						shared_base = cover_base;
						shared_interior = cover_interior;
						shared_has_interior = true;
					}
				}
				const Vector2i cover_atlas = get_wall_variant_coords(ctx.tables, cover_base, cover_variant);
				cover_mask[idx] = pack_cover_mask(linear_index_for_coords(ctx.tables, cover_atlas), cover_alt_id);
			}
			if (!ctx.is_underground && terrain_type == ctx.tables.terrain_rock) {
				if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(0, 1)))) cliff_overlay[idx] = PREBAKED_CLIFF_SOUTH;
				else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(-1, 0)))) cliff_overlay[idx] = PREBAKED_CLIFF_WEST;
				else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(1, 0)))) cliff_overlay[idx] = PREBAKED_CLIFF_EAST;
				else if (is_open_exterior(ctx, terrain_at(ctx, local_tile + Vector2i(0, -1)))) cliff_overlay[idx] = PREBAKED_CLIFF_TOP;
			}
			variant_id_bytes[idx] = 0;
			if (shared_base.x >= 0) {
				if (shared_has_interior) {
					variant_id_bytes[idx] = shared_interior.x;
					alt_id_values[idx] = shared_interior.y;
				} else {
					alt_id_values[idx] = variant_alt_id(ctx, shared_base, global_tile.x, global_tile.y, ctx.is_underground);
				}
			}
		}
	}
	result["rock_visual_class"] = rock_visual_class_bytes;
	result["ground_face_atlas"] = ground_face_atlas;
	result["cover_mask"] = cover_mask;
	result["cliff_overlay"] = cliff_overlay;
	result["variant_id"] = variant_id_bytes;
	result["alt_id"] = alt_id_values;
	return result;
}

int apply_visual_buffer(TileMapLayer *layer, const PackedInt32Array &buffer, int32_t buffer_stride) {
	if (layer == nullptr || buffer.is_empty() || buffer_stride <= 0) {
		return 0;
	}
	const int command_limit = buffer.size() - buffer_stride + 1;
	if (command_limit <= 0) {
		return 0;
	}
	const int32_t *data = buffer.ptr();
	int applied_commands = 0;
	for (int index = 0; index < command_limit; index += buffer_stride) {
		const Vector2i local_tile(data[index], data[index + 1]);
		if (data[index + 2] == VISUAL_COMMAND_OP_SET) {
			layer->set_cell(
				local_tile,
				data[index + 3],
				Vector2i(data[index + 4], data[index + 5]),
				data[index + 6]
			);
		} else {
			layer->erase_cell(local_tile);
		}
		applied_commands += 1;
	}
	return applied_commands;
}

} // namespace

ChunkVisualKernels::ChunkVisualKernels() {}
ChunkVisualKernels::~ChunkVisualKernels() {}

void ChunkVisualKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_prebaked_visual_payload", "request"), &ChunkVisualKernels::build_prebaked_visual_payload);
	ClassDB::bind_method(D_METHOD("build_interior_macro_overlay", "request"), &ChunkVisualKernels::build_interior_macro_overlay);
	ClassDB::bind_method(D_METHOD("compute_visual_batch", "request"), &ChunkVisualKernels::compute_visual_batch);
	ClassDB::bind_method(
		D_METHOD(
			"apply_chunk_visual_buffers",
			"terrain_layer", "terrain_buffer",
			"ground_face_layer", "ground_face_buffer",
			"rock_layer", "rock_buffer",
			"cover_layer", "cover_buffer",
			"cliff_layer", "cliff_buffer",
			"buffer_stride"
		),
		&ChunkVisualKernels::apply_chunk_visual_buffers,
		DEFVAL(VISUAL_APPLY_BUFFER_STRIDE)
	);
}

Dictionary ChunkVisualKernels::build_prebaked_visual_payload(Dictionary p_request) const {
	VisualRequestContext ctx;
	if (!load_tables(p_request, ctx)) {
		return Dictionary();
	}
	return build_prebaked_visual_payload_internal(ctx);
}

Dictionary ChunkVisualKernels::build_interior_macro_overlay(Dictionary p_request) const {
	InteriorMacroContext ctx;
	if (!load_interior_macro_context(p_request, ctx)) {
		return Dictionary();
	}
	return build_interior_macro_overlay_internal(ctx);
}

Dictionary ChunkVisualKernels::compute_visual_batch(Dictionary p_request) const {
	Dictionary result;
	if (!supports_native_compute(p_request)) return result;
	VisualRequestContext ctx;
	if (!load_tables(p_request, ctx)) return result;
	const Array tiles = p_request.get("tiles", Array());
	const String mode = p_request.get("mode", String());
	result["mode"] = p_request.get("mode", StringName());
	result["phase"] = int(p_request.get("phase", -1));
	result["phase_name"] = p_request.get("phase_name", StringName("done"));
	result["start_index"] = int(p_request.get("start_index", -1));
	result["end_index"] = int(p_request.get("end_index", -1));
	result["tiles"] = tiles;
	result["tile_count"] = tiles.size();
	LayeredCommandBuffers buffers;
	result["buffer_stride"] = VISUAL_APPLY_BUFFER_STRIDE;
	if (mode == "phase") {
		const int phase = int(p_request.get("phase", -1));
		for (int i = 0; i < tiles.size(); ++i) {
			const Vector2i local_tile = tiles[i];
			if (phase == REDRAW_PHASE_TERRAIN) append_terrain_visual_commands(ctx, local_tile, buffers, false);
			else if (phase == REDRAW_PHASE_COVER) append_cover_visual_command(ctx, local_tile, buffers, false);
			else if (phase == REDRAW_PHASE_CLIFF) append_cliff_visual_command(ctx, local_tile, buffers, false);
		}
	} else if (mode == "dirty") {
		for (int i = 0; i < tiles.size(); ++i) {
			const Vector2i local_tile = tiles[i];
			append_terrain_visual_commands(ctx, local_tile, buffers, true);
			append_cover_visual_command(ctx, local_tile, buffers, true);
			append_cliff_visual_command(ctx, local_tile, buffers, true);
		}
	}
	result["terrain_buffer"] = buffers.terrain;
	result["ground_face_buffer"] = buffers.ground_face;
	result["rock_buffer"] = buffers.rock;
	result["cover_buffer"] = buffers.cover;
	result["cliff_buffer"] = buffers.cliff;
	result["command_count"] = buffers.command_count;
	return result;
}

int32_t ChunkVisualKernels::apply_chunk_visual_buffers(
	TileMapLayer *p_terrain_layer,
	const PackedInt32Array &p_terrain_buffer,
	TileMapLayer *p_ground_face_layer,
	const PackedInt32Array &p_ground_face_buffer,
	TileMapLayer *p_rock_layer,
	const PackedInt32Array &p_rock_buffer,
	TileMapLayer *p_cover_layer,
	const PackedInt32Array &p_cover_buffer,
	TileMapLayer *p_cliff_layer,
	const PackedInt32Array &p_cliff_buffer,
	int32_t p_buffer_stride
) const {
	int32_t applied_commands = 0;
	applied_commands += apply_visual_buffer(p_terrain_layer, p_terrain_buffer, p_buffer_stride);
	applied_commands += apply_visual_buffer(p_ground_face_layer, p_ground_face_buffer, p_buffer_stride);
	applied_commands += apply_visual_buffer(p_rock_layer, p_rock_buffer, p_buffer_stride);
	applied_commands += apply_visual_buffer(p_cover_layer, p_cover_buffer, p_buffer_stride);
	applied_commands += apply_visual_buffer(p_cliff_layer, p_cliff_buffer, p_buffer_stride);
	return applied_commands;
}
