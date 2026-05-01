#include "world_core.h"
#include "autotile_47.h"
#include "hydrology_tile_classifier.h"
#include "mountain_field.h"
#include "world_utils.h"

#include <algorithm>
#include <array>
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
using world_utils::splitmix64;
using world_utils::positive_mod;
namespace htc = hydrology_tile_classifier;

namespace {

constexpr int64_t CHUNK_SIZE = 32;
constexpr int64_t CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

constexpr int64_t TERRAIN_PLAINS_GROUND = 0;
constexpr int64_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int64_t TERRAIN_MOUNTAIN_FOOT = 4;
constexpr int64_t TERRAIN_RIVERBED_SHALLOW = 5;
constexpr int64_t TERRAIN_RIVERBED_DEEP = 6;
constexpr int64_t TERRAIN_LAKEBED = 7;
constexpr int64_t TERRAIN_OCEAN_FLOOR = 8;
constexpr int64_t TERRAIN_SHORE = 9;
constexpr int64_t TERRAIN_FLOODPLAIN = 10;

constexpr uint8_t WATER_CLASS_NONE = 0U;
constexpr uint8_t WATER_CLASS_SHALLOW = 1U;
constexpr uint8_t WATER_CLASS_DEEP = 2U;
constexpr uint8_t WATER_CLASS_OCEAN = 3U;

constexpr int32_t HYDROLOGY_FLAG_RIVERBED = 1 << 0;
constexpr int32_t HYDROLOGY_FLAG_LAKEBED = 1 << 1;
constexpr int32_t HYDROLOGY_FLAG_SHORE = 1 << 2;
constexpr int32_t HYDROLOGY_FLAG_BANK = 1 << 3;
constexpr int32_t HYDROLOGY_FLAG_FLOODPLAIN = 1 << 4;
constexpr int32_t HYDROLOGY_FLAG_DELTA = 1 << 5;
constexpr int32_t HYDROLOGY_FLAG_BRAID_SPLIT = 1 << 6;
constexpr int32_t HYDROLOGY_FLAG_CONFLUENCE = 1 << 7;
constexpr int32_t HYDROLOGY_FLAG_SOURCE = 1 << 8;
constexpr int32_t HYDROLOGY_FLAG_FLOODPLAIN_NEAR = 1 << 9;
constexpr int32_t HYDROLOGY_FLAG_FLOODPLAIN_FAR = 1 << 10;
constexpr int32_t HYDROLOGY_LAKE_ID_OFFSET = 1000000;
constexpr int32_t HYDROLOGY_OCEAN_ID = 2000000;

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
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_ENABLED = 15;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT = 16;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_DENSITY = 17;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE = 18;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE = 19;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH = 20;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE = 21;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY = 22;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES = 23;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE = 24;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS = 25;
constexpr int64_t SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES = 26;
constexpr int64_t SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS = 27;

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;
constexpr uint8_t MOUNTAIN_FLAG_INTERIOR = 1U << 0U;
constexpr uint8_t MOUNTAIN_FLAG_ANCHOR = 1U << 3U;
constexpr int64_t LEGACY_WORLD_WRAP_WIDTH_TILES = world_utils::LEGACY_WORLD_WRAP_WIDTH_TILES;
constexpr int64_t WORLD_FOUNDATION_VERSION = 9;
constexpr int64_t WORLD_RIVER_VERSION = 17;
constexpr int64_t WORLD_DELTA_VERSION = 19;
constexpr int64_t WORLD_ORGANIC_WATER_VERSION = 20;
constexpr int64_t WORLD_OCEAN_SHORE_VERSION = 21;
constexpr int64_t WORLD_REFINED_RIVER_VERSION = 22;
constexpr int64_t WORLD_CURVATURE_RIVER_VERSION = 23;
constexpr int64_t WORLD_Y_CONFLUENCE_RIVER_VERSION = 24;
constexpr int64_t WORLD_BRAID_LOOP_RIVER_VERSION = 25;
constexpr int64_t WORLD_BASIN_CONTOUR_LAKE_VERSION = 26;
constexpr int64_t WORLD_ORGANIC_COASTLINE_VERSION = 27;
constexpr int64_t WORLD_HYDROLOGY_SHAPE_FIX_VERSION = 28;
constexpr int64_t WORLD_HEADLAND_COAST_VERSION = 29;
constexpr int64_t MOUNTAIN_FINITE_WIDTH_VERSION = world_utils::MOUNTAIN_FINITE_WIDTH_VERSION;
constexpr int64_t FOUNDATION_CHUNK_SIZE = 32;
constexpr int64_t HYDROLOGY_TRANSPARENT_OVERLAY_LAYER_MASK = 1LL << 6;
constexpr int64_t HYDROLOGY_LAYER_WINNER_LAYER_MASK = 1LL << 7;
constexpr int64_t SPAWN_SAFE_PATCH_MIN_TILE = 12;
constexpr int64_t SPAWN_SAFE_PATCH_MAX_TILE = 20;
constexpr size_t HIERARCHICAL_CACHE_LIMIT = 64;
constexpr int32_t RIVER_SEGMENT_RECORD_SIZE = 6;
constexpr float PI = 3.14159265358979323846f;

constexpr int32_t PREVIEW_MIPMAP_LEVELS = 6;

enum class PreviewPatchMode {
	Terrain,
	MountainId,
	MountainClassification
};

struct Rgba8 {
	uint8_t r = 0U;
	uint8_t g = 0U;
	uint8_t b = 0U;
	uint8_t a = 255U;
};

constexpr Rgba8 PREVIEW_COLOR_GROUND = { 46U, 59U, 46U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_GROUND = { 33U, 41U, 33U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_FOOT = { 214U, 143U, 51U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_WALL = { 59U, 171U, 224U, 255U };
constexpr Rgba8 PREVIEW_COLOR_CLASSIFICATION_INTERIOR = { 235U, 74U, 140U, 255U };
constexpr Rgba8 PREVIEW_COLOR_UNKNOWN = { 18U, 23U, 26U, 255U };

struct SegmentProjection {
	float distance = std::numeric_limits<float>::infinity();
	float signed_distance = 0.0f;
	float t = 0.0f;
};

struct RiverRasterEdge {
	float ax = 0.0f;
	float ay = 0.0f;
	float bx = 0.0f;
	float by = 0.0f;
	int32_t segment_id = 0;
	uint8_t stream_order = 0U;
	uint8_t flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
	float radius_scale = 1.0f;
	float curvature = 0.0f;
	float confluence_weight = 0.0f;
	float cumulative_start = 0.0f;
	float cumulative_end = 0.0f;
	float total_distance = 0.0f;
	float distance_at_source = 0.0f;
	float distance_to_terminal = 0.0f;
	float discharge_norm_start = 0.0f;
	float discharge_norm_end = 0.0f;
	float width_profile_scale_start = 1.0f;
	float width_profile_scale_end = 1.0f;
	float ford_narrowing_start = 0.0f;
	float ford_narrowing_end = 0.0f;
	uint64_t variation_seed = 0ULL;
	bool source = false;
	bool delta = false;
	bool braid_split = false;
	bool confluence = false;
	bool discharge_width_profile = false;
	bool organic = false;
	bool shape_quality_v2_fix = false;
};

struct RiverRasterSample {
	float distance = std::numeric_limits<float>::infinity();
	int32_t segment_id = 0;
	uint8_t stream_order = 0U;
	uint8_t flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
	float radius_scale = 1.0f;
	float signed_distance = 0.0f;
	float curvature = 0.0f;
	float confluence_weight = 0.0f;
	float cumulative_distance = 0.0f;
	float total_distance = 0.0f;
	float distance_at_source = 0.0f;
	float distance_to_terminal = 0.0f;
	float discharge_norm = 0.0f;
	float width_profile_scale = 1.0f;
	float ford_narrowing = 0.0f;
	bool shape_quality_v2_fix = false;
	bool source = false;
	bool delta = false;
	bool braid_split = false;
	bool confluence = false;
	bool discharge_width_profile = false;
};

bool is_foundation_overview_mountain_pixel(const PackedByteArray &p_bytes, int32_t p_offset) {
	const int32_t r = static_cast<int32_t>(p_bytes[p_offset]);
	const int32_t g = static_cast<int32_t>(p_bytes[p_offset + 1]);
	const int32_t b = static_cast<int32_t>(p_bytes[p_offset + 2]);
	const int32_t a = static_cast<int32_t>(p_bytes[p_offset + 3]);
	if (a != 255) {
		return false;
	}
	const bool wall_pixel = r >= 164 && r <= 238 && g == r - 4 && b == r - 18;
	const bool foot_pixel = r >= 107 && r <= 178 &&
			g >= 98 && g <= 143 &&
			b >= 74 && b <= 102 &&
			r > g && g > b;
	return wall_pixel || foot_pixel;
}

PackedByteArray make_foundation_mountain_render_mask(const Ref<Image> &p_foundation_image) {
	PackedByteArray mask;
	if (p_foundation_image.is_null()) {
		return mask;
	}
	const int32_t width = p_foundation_image->get_width();
	const int32_t height = p_foundation_image->get_height();
	if (width <= 0 || height <= 0) {
		return mask;
	}
	const PackedByteArray foundation_bytes = p_foundation_image->get_data();
	if (foundation_bytes.size() != width * height * 4) {
		return mask;
	}
	mask.resize(width * height);
	for (int32_t index = 0; index < width * height; ++index) {
		if (is_foundation_overview_mountain_pixel(foundation_bytes, index * 4)) {
			mask.set(index, 1U);
		}
	}
	return mask;
}

Ref<Image> blend_overview_images(
	const Ref<Image> &p_foundation_image,
	const Ref<Image> &p_hydrology_overlay,
	const PackedByteArray &p_foundation_mountain_mask
) {
	if (p_foundation_image.is_null() || p_hydrology_overlay.is_null()) {
		return Ref<Image>();
	}
	const int32_t width = p_foundation_image->get_width();
	const int32_t height = p_foundation_image->get_height();
	const int32_t overlay_width = p_hydrology_overlay->get_width();
	const int32_t overlay_height = p_hydrology_overlay->get_height();
	if (width <= 0 || height <= 0 || overlay_width <= 0 || overlay_height <= 0) {
		return Ref<Image>();
	}
	PackedByteArray foundation_bytes = p_foundation_image->get_data();
	const PackedByteArray overlay_bytes = p_hydrology_overlay->get_data();
	if (foundation_bytes.size() != width * height * 4 ||
			overlay_bytes.size() != overlay_width * overlay_height * 4) {
		return Ref<Image>();
	}
	(void)p_foundation_mountain_mask;
	for (int32_t y = 0; y < height; ++y) {
		const int32_t overlay_y = world_utils::clamp_value(
			static_cast<int32_t>((static_cast<int64_t>(y) * overlay_height) / height),
			0,
			overlay_height - 1
		);
		for (int32_t x = 0; x < width; ++x) {
			const int32_t overlay_x = world_utils::clamp_value(
				static_cast<int32_t>((static_cast<int64_t>(x) * overlay_width) / width),
				0,
				overlay_width - 1
			);
			const int32_t dst_index = y * width + x;
			const int32_t dst_offset = dst_index * 4;
			const int32_t src_offset = (overlay_y * overlay_width + overlay_x) * 4;
			const int32_t src_a = static_cast<int32_t>(overlay_bytes[src_offset + 3]);
			if (src_a <= 0) {
				continue;
			}
			if (src_a >= 255) {
				foundation_bytes.set(dst_offset, overlay_bytes[src_offset]);
				foundation_bytes.set(dst_offset + 1, overlay_bytes[src_offset + 1]);
				foundation_bytes.set(dst_offset + 2, overlay_bytes[src_offset + 2]);
				foundation_bytes.set(dst_offset + 3, 255);
				continue;
			}
			const int32_t inv_a = 255 - src_a;
			for (int32_t channel = 0; channel < 3; ++channel) {
				const int32_t src = static_cast<int32_t>(overlay_bytes[src_offset + channel]);
				const int32_t dst = static_cast<int32_t>(foundation_bytes[dst_offset + channel]);
				const int32_t blended = (src * src_a + dst * inv_a + 127) / 255;
				foundation_bytes.set(
					dst_offset + channel,
					static_cast<uint8_t>(world_utils::clamp_value(blended, 0, 255))
				);
			}
			foundation_bytes.set(dst_offset + 3, 255);
		}
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, foundation_bytes);
}

void write_rgba8(PackedByteArray &r_bytes, int32_t p_offset, Rgba8 p_color) {
	r_bytes.set(p_offset, p_color.r);
	r_bytes.set(p_offset + 1, p_color.g);
	r_bytes.set(p_offset + 2, p_color.b);
	r_bytes.set(p_offset + 3, p_color.a);
}

Rgba8 read_rgba8(const PackedByteArray &p_bytes, int32_t p_offset) {
	Rgba8 color;
	if (p_offset < 0 || p_offset + 3 >= p_bytes.size()) {
		return color;
	}
	color.r = p_bytes[p_offset];
	color.g = p_bytes[p_offset + 1];
	color.b = p_bytes[p_offset + 2];
	color.a = p_bytes[p_offset + 3];
	return color;
}

bool rgba8_equal(Rgba8 p_a, Rgba8 p_b) {
	return p_a.r == p_b.r && p_a.g == p_b.g && p_a.b == p_b.b && p_a.a == p_b.a;
}

Rgba8 to_rgba8(htc::DebugRgba8 p_color) {
	return { p_color.r, p_color.g, p_color.b, p_color.a };
}

Rgba8 to_rgba8(htc::PresentationRgba8 p_color) {
	return { p_color.r, p_color.g, p_color.b, p_color.a };
}

PreviewPatchMode resolve_preview_patch_mode(StringName p_render_mode) {
	const String mode = String(p_render_mode);
	if (mode == "mountain_id") {
		return PreviewPatchMode::MountainId;
	}
	if (mode == "mountain_classification") {
		return PreviewPatchMode::MountainClassification;
	}
	return PreviewPatchMode::Terrain;
}

Rgba8 hsv_to_rgb8(float p_h, float p_s, float p_v) {
	const float h = p_h - std::floor(p_h);
	const float s = world_utils::clamp_value(p_s, 0.0f, 1.0f);
	const float v = world_utils::clamp_value(p_v, 0.0f, 1.0f);
	const float scaled_h = h * 6.0f;
	const int32_t sector = static_cast<int32_t>(std::floor(scaled_h));
	const float f = scaled_h - static_cast<float>(sector);
	const float p = v * (1.0f - s);
	const float q = v * (1.0f - s * f);
	const float t = v * (1.0f - s * (1.0f - f));
	float r = v;
	float g = t;
	float b = p;
	switch (positive_mod(sector, 6)) {
		case 0:
			r = v;
			g = t;
			b = p;
			break;
		case 1:
			r = q;
			g = v;
			b = p;
			break;
		case 2:
			r = p;
			g = v;
			b = t;
			break;
		case 3:
			r = p;
			g = q;
			b = v;
			break;
		case 4:
			r = t;
			g = p;
			b = v;
			break;
		default:
			r = v;
			g = p;
			b = q;
			break;
	}
	return {
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(r * 255.0f)), 0, 255)),
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(g * 255.0f)), 0, 255)),
		static_cast<uint8_t>(world_utils::clamp_value(static_cast<int32_t>(std::lround(b * 255.0f)), 0, 255)),
		255U
	};
}

int32_t read_int32_at(const PackedInt32Array &p_values, int32_t p_index, int32_t p_fallback = 0) {
	return p_index >= 0 && p_index < p_values.size() ? p_values[p_index] : p_fallback;
}

int32_t read_byte_at(const PackedByteArray &p_values, int32_t p_index, int32_t p_fallback = 0) {
	return p_index >= 0 && p_index < p_values.size() ? static_cast<int32_t>(p_values[p_index]) : p_fallback;
}

uint8_t resolve_preview_floodplain_strength(
	int32_t p_terrain_id,
	int32_t p_hydrology_flags,
	uint8_t p_floodplain_strength
) {
	if (p_floodplain_strength > 0U) {
		return p_floodplain_strength;
	}
	if ((p_hydrology_flags & HYDROLOGY_FLAG_FLOODPLAIN_NEAR) != 0) {
		return 224U;
	}
	if ((p_hydrology_flags & HYDROLOGY_FLAG_FLOODPLAIN_FAR) != 0) {
		return 128U;
	}
	if (p_terrain_id == TERRAIN_FLOODPLAIN || (p_hydrology_flags & HYDROLOGY_FLAG_FLOODPLAIN) != 0) {
		return 160U;
	}
	return 0U;
}

Rgba8 resolve_preview_terrain_color(int32_t p_terrain_id) {
	switch (p_terrain_id) {
		case TERRAIN_MOUNTAIN_WALL:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::MountainWall));
		case TERRAIN_MOUNTAIN_FOOT:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::MountainFoot));
		case TERRAIN_RIVERBED_DEEP:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::RiverDeep));
		case TERRAIN_RIVERBED_SHALLOW:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::RiverShallow));
		case TERRAIN_LAKEBED:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::LakeShallow));
		case TERRAIN_OCEAN_FLOOR:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::OceanShelf));
		case TERRAIN_SHORE:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::RiverBank));
		case TERRAIN_FLOODPLAIN:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::Floodplain, 160U));
		default:
			return to_rgba8(htc::gameplay_winner_color(htc::HydroTileWinner::Ground));
	}
}

Rgba8 resolve_preview_winner_color(htc::HydroTileWinner p_winner, uint8_t p_floodplain_strength = 0U) {
	return to_rgba8(htc::gameplay_winner_color(p_winner, p_floodplain_strength));
}

Rgba8 resolve_preview_classification_color(int32_t p_mountain_flags) {
	if ((p_mountain_flags & MOUNTAIN_FLAG_INTERIOR) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_INTERIOR;
	}
	if ((p_mountain_flags & MOUNTAIN_FLAG_WALL) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_WALL;
	}
	if ((p_mountain_flags & MOUNTAIN_FLAG_FOOT) != 0) {
		return PREVIEW_COLOR_CLASSIFICATION_FOOT;
	}
	return PREVIEW_COLOR_CLASSIFICATION_GROUND;
}

Rgba8 resolve_preview_mountain_id_color(int32_t p_mountain_id, int32_t p_mountain_flags) {
	if (p_mountain_id <= 0) {
		return PREVIEW_COLOR_CLASSIFICATION_GROUND;
	}
	uint32_t hashed_id = static_cast<uint32_t>(p_mountain_id & 0x7fffffff);
	hashed_id = hashed_id ^ (hashed_id >> 16U);
	hashed_id *= 224682251U;
	hashed_id = hashed_id ^ (hashed_id >> 13U);
	const float hue = static_cast<float>(hashed_id & 1023U) / 1023.0f;
	const float saturation = std::min(0.92f, 0.58f + static_cast<float>((hashed_id >> 10U) & 63U) / 210.0f);
	float value = 0.72f;
	if ((p_mountain_flags & MOUNTAIN_FLAG_INTERIOR) != 0) {
		value = 0.84f;
	} else if ((p_mountain_flags & MOUNTAIN_FLAG_WALL) != 0) {
		value = 0.92f;
	}
	return hsv_to_rgb8(hue, saturation, value);
}

Rgba8 resolve_preview_patch_color(
	PreviewPatchMode p_mode,
	int32_t p_terrain_id,
	int32_t p_hydrology_id,
	int32_t p_hydrology_flags,
	uint8_t p_floodplain_strength,
	uint8_t p_water_class,
	int32_t p_mountain_id,
	int32_t p_mountain_flags
) {
	switch (p_mode) {
		case PreviewPatchMode::MountainId:
			return resolve_preview_mountain_id_color(p_mountain_id, p_mountain_flags);
		case PreviewPatchMode::MountainClassification:
			return resolve_preview_classification_color(p_mountain_flags);
		case PreviewPatchMode::Terrain:
		default:
			const htc::HydroTileWinner winner = htc::winner_from_packet(
				p_terrain_id,
				p_hydrology_id,
				p_hydrology_flags,
				p_water_class,
				static_cast<uint8_t>(p_mountain_flags)
			);
			return resolve_preview_winner_color(
				winner,
				winner == htc::HydroTileWinner::Floodplain ?
						resolve_preview_floodplain_strength(p_terrain_id, p_hydrology_flags, p_floodplain_strength) :
						0U
			);
	}
}

PackedByteArray downsample_preview_mipmap(
	const PackedByteArray &p_src,
	int32_t p_src_width,
	int32_t p_src_height,
	Rgba8 p_ground_color
) {
	const int32_t dst_width = std::max(1, p_src_width / 2);
	const int32_t dst_height = std::max(1, p_src_height / 2);
	PackedByteArray dst;
	dst.resize(dst_width * dst_height * 4);
	for (int32_t y = 0; y < dst_height; ++y) {
		for (int32_t x = 0; x < dst_width; ++x) {
			const int32_t sx = x * 2;
			const int32_t sy = y * 2;
			const int32_t sx1 = std::min(sx + 1, p_src_width - 1);
			const int32_t sy1 = std::min(sy + 1, p_src_height - 1);
			const std::array<int32_t, 4> offsets = {
				(sy * p_src_width + sx) * 4,
				(sy * p_src_width + sx1) * 4,
				(sy1 * p_src_width + sx) * 4,
				(sy1 * p_src_width + sx1) * 4
			};
			Rgba8 picked = p_ground_color;
			for (const int32_t offset : offsets) {
				const Rgba8 sample = read_rgba8(p_src, offset);
				if (!rgba8_equal(sample, p_ground_color)) {
					picked = sample;
					break;
				}
			}
			write_rgba8(dst, (y * dst_width + x) * 4, picked);
		}
	}
	return dst;
}

struct LakeRasterSample {
	int32_t lake_id = 0;
	bool is_lakebed = false;
	bool is_lake_edge = false;
	bool is_shore = false;
	uint8_t shore_strength = 0U;
};

struct V3LakeSdfSample {
	int32_t lake_id = 0;
	float signed_distance_tiles = std::numeric_limits<float>::infinity();
	bool is_lakebed = false;
	bool is_contour_band = false;
	uint8_t shore_strength = 0U;
};

struct OceanRasterSample {
	bool is_ocean_floor = false;
	bool is_shore = false;
	bool is_shallow_shelf = false;
	uint8_t shore_strength = 0U;
};

int64_t wrap_foundation_world_x(int64_t p_world_x, const FoundationSettings &p_foundation_settings) {
	return world_utils::wrap_foundation_world_x(p_world_x, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
}

int64_t clamp_foundation_world_y(int64_t p_world_y, const FoundationSettings &p_foundation_settings) {
	return world_utils::clamp_foundation_world_y(p_world_y, p_foundation_settings.height_tiles, p_foundation_settings.enabled);
}

int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings
) {
	return world_utils::resolve_mountain_sample_x(p_world_x, p_world_version, p_foundation_settings.width_tiles, p_foundation_settings.enabled);
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

bool uses_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_RIVER_VERSION;
}

bool uses_delta_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_DELTA_VERSION;
}

bool uses_organic_water_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_ORGANIC_WATER_VERSION;
}

bool uses_ocean_shore_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_OCEAN_SHORE_VERSION;
}

bool uses_organic_coastline_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_ORGANIC_COASTLINE_VERSION;
}

int64_t world_shape_seed_version(int64_t p_world_version) {
	return p_world_version >= WORLD_ORGANIC_COASTLINE_VERSION ?
			WORLD_BASIN_CONTOUR_LAKE_VERSION :
			p_world_version;
}

bool uses_refined_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_REFINED_RIVER_VERSION;
}

bool uses_curvature_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_CURVATURE_RIVER_VERSION;
}

bool uses_y_confluence_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_Y_CONFLUENCE_RIVER_VERSION;
}

bool uses_braid_loop_river_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_BRAID_LOOP_RIVER_VERSION;
}

bool uses_basin_contour_lake_generation(int64_t p_world_version) {
	return p_world_version >= WORLD_BASIN_CONTOUR_LAKE_VERSION;
}

bool uses_hydrology_visual_v3(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_HYDROLOGY_VISUAL_V3_VERSION;
}

bool uses_hydrology_clearance_v4(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_HYDROLOGY_CLEARANCE_V4_VERSION;
}

bool uses_river_discharge_width_v4(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION;
}

bool uses_estuary_delta_v4(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_ESTUARY_DELTA_V4_VERSION;
}

bool uses_lake_basin_continuity_v4(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_LAKE_BASIN_CONTINUITY_V4_VERSION;
}

int64_t hydrology_detail_seed_version(int64_t p_world_version) {
	return p_world_version >= mountain_field::WORLD_LAKES_ONLY_PRESET_V4_VERSION ?
			mountain_field::WORLD_LAKE_BASIN_CONTINUITY_V4_VERSION :
			p_world_version;
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

int64_t resolve_base_ground_atlas_index(
	int64_t world_x,
	int64_t world_y,
	int64_t seed,
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

float adjust_wrapped_x_near(float p_x, float p_anchor_x, float p_world_width_tiles) {
	if (p_world_width_tiles <= 1.0f) {
		return p_x;
	}
	float adjusted = p_x;
	const float half_width = p_world_width_tiles * 0.5f;
	while (adjusted - p_anchor_x > half_width) {
		adjusted -= p_world_width_tiles;
	}
	while (adjusted - p_anchor_x < -half_width) {
		adjusted += p_world_width_tiles;
	}
	return adjusted;
}

float smoothstep_unit(float p_value) {
	const float t = world_utils::saturate(p_value);
	return t * t * (3.0f - 2.0f * t);
}

float smoothstep(float p_edge0, float p_edge1, float p_value) {
	if (p_edge1 <= p_edge0) {
		return p_value >= p_edge1 ? 1.0f : 0.0f;
	}
	return smoothstep_unit((p_value - p_edge0) / (p_edge1 - p_edge0));
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float hash_grid_unit(uint64_t p_seed, int64_t p_x, int64_t p_y) {
	const uint64_t mixed = splitmix64(
		p_seed ^
		static_cast<uint64_t>(p_x) * 0x9e3779b185ebca87ULL ^
		static_cast<uint64_t>(p_y) * 0xc2b2ae3d27d4eb4fULL
	);
	return static_cast<float>(mixed & 0x00ffffffULL) / static_cast<float>(0x00ffffffULL);
}

float value_noise_2d(uint64_t p_seed, float p_x, float p_y) {
	const int64_t x0 = static_cast<int64_t>(std::floor(p_x));
	const int64_t y0 = static_cast<int64_t>(std::floor(p_y));
	const float tx = smoothstep_unit(p_x - static_cast<float>(x0));
	const float ty = smoothstep_unit(p_y - static_cast<float>(y0));
	const float v00 = hash_grid_unit(p_seed, x0, y0);
	const float v10 = hash_grid_unit(p_seed, x0 + 1, y0);
	const float v01 = hash_grid_unit(p_seed, x0, y0 + 1);
	const float v11 = hash_grid_unit(p_seed, x0 + 1, y0 + 1);
	const float vx0 = lerp_float(v00, v10, tx);
	const float vx1 = lerp_float(v01, v11, tx);
	return lerp_float(vx0, vx1, ty);
}

float signed_value_noise_2d(uint64_t p_seed, float p_x, float p_y) {
	return value_noise_2d(p_seed, p_x, p_y) * 2.0f - 1.0f;
}

SegmentProjection project_to_segment(float p_x, float p_y, const RiverRasterEdge &p_edge, float p_world_width_tiles) {
	const float px = adjust_wrapped_x_near(p_x, p_edge.ax, p_world_width_tiles);
	const float vx = p_edge.bx - p_edge.ax;
	const float vy = p_edge.by - p_edge.ay;
	const float wx = px - p_edge.ax;
	const float wy = p_y - p_edge.ay;
	const float length_sq = vx * vx + vy * vy;
	SegmentProjection projection;
	if (length_sq <= 0.0001f) {
		const float dx = px - p_edge.ax;
		const float dy = p_y - p_edge.ay;
		projection.distance = std::sqrt(dx * dx + dy * dy);
		return projection;
	}
	const float t = world_utils::clamp_value((wx * vx + wy * vy) / length_sq, 0.0f, 1.0f);
	const float nearest_x = p_edge.ax + vx * t;
	const float nearest_y = p_edge.ay + vy * t;
	const float dx = px - nearest_x;
	const float dy = p_y - nearest_y;
	projection.distance = std::sqrt(dx * dx + dy * dy);
	projection.signed_distance = (vx * dy - vy * dx) / std::sqrt(length_sq);
	projection.t = t;
	return projection;
}

struct RiverChannelRadii {
	float deep_radius = 0.0f;
	float bed_radius = 0.0f;
	float bank_radius = 0.0f;
};

RiverChannelRadii resolve_river_channel_radii(
	const RiverRasterSample &p_sample,
	float p_river_width_scale
) {
	const float order_f = std::max(1.0f, static_cast<float>(p_sample.stream_order));
	const float curvature_abs = std::abs(p_sample.curvature);
	const float curvature_radius_weight = p_sample.shape_quality_v2_fix ? 0.30f : 0.10f;
	const float confluence_weight = p_sample.confluence ? std::max(0.35f, p_sample.confluence_weight) : 0.0f;
	float edge_radius_scale = std::max(0.25f, p_sample.radius_scale);
	const bool use_discharge_width_profile = p_sample.discharge_width_profile;
	const bool use_v3_distance_taper = p_sample.total_distance > 0.001f && !use_discharge_width_profile;
	float delta_shore_fade = 0.0f;
	if (use_v3_distance_taper) {
		const float distance_t = world_utils::clamp_value(p_sample.cumulative_distance / p_sample.total_distance, 0.0f, 1.0f);
		const float source_taper = smoothstep(0.04f, 0.18f, distance_t);
		const float terminal_grow = lerp_float(1.0f, 1.45f, smoothstep(0.70f, 0.97f, distance_t));
		edge_radius_scale *= source_taper * terminal_grow;
		if (p_sample.delta) {
			const float fade_window = std::max(12.0f, p_river_width_scale * 16.0f);
			delta_shore_fade = 1.0f - smoothstep(0.0f, fade_window, p_sample.distance_to_terminal);
			edge_radius_scale *= lerp_float(0.90f, 1.10f, delta_shore_fade);
		}
	}
	RiverChannelRadii radii;
	if (use_discharge_width_profile) {
		const float profile_scale = world_utils::clamp_value(p_sample.width_profile_scale, 0.25f, 4.0f);
		const float ford = world_utils::saturate(p_sample.ford_narrowing);
		const float ford_bed_scale = lerp_float(1.0f, 0.72f, ford);
		const float ford_deep_scale = lerp_float(1.0f, 0.55f, ford);
		edge_radius_scale *= 1.0f + curvature_abs * curvature_radius_weight + confluence_weight * 0.06f;
		const float profile_radius_scale = edge_radius_scale * profile_scale;
		radii.deep_radius = std::max(0.48f, 0.58f * p_river_width_scale * profile_radius_scale * ford_deep_scale);
		radii.bed_radius = std::max(
			0.72f,
			radii.deep_radius + (0.78f + p_river_width_scale * 0.22f) * profile_radius_scale * ford_bed_scale
		);
		const float terminal_t = p_sample.total_distance > 0.001f ?
				1.0f - smoothstep(0.0f, 42.0f, p_sample.distance_to_terminal) :
				0.0f;
		const float delta_bank_extra = p_sample.delta ?
				lerp_float(1.9f, 3.8f, world_utils::saturate(terminal_t)) :
				1.45f;
		radii.bank_radius = radii.bed_radius + delta_bank_extra + confluence_weight * 0.55f;
		return radii;
	}
	edge_radius_scale *= 1.0f + curvature_abs * curvature_radius_weight + confluence_weight * 0.16f;
	radii.deep_radius = std::max(0.55f, (0.35f + order_f * 0.16f) * p_river_width_scale * edge_radius_scale);
	radii.bed_radius = std::max(use_v3_distance_taper ? 0.75f : 1.25f, radii.deep_radius + (0.9f + p_river_width_scale * 0.25f) * edge_radius_scale);
	const float delta_bank_extra = use_v3_distance_taper && p_sample.delta ?
			lerp_float(1.8f, 3.6f, delta_shore_fade) :
			2.6f;
	radii.bank_radius = radii.bed_radius + (p_sample.delta ? delta_bank_extra : 1.5f) + confluence_weight * 0.75f;
	return radii;
}

float resolve_curvature_thalweg_distance(const RiverRasterSample &p_sample, float p_deep_radius) {
	if (std::abs(p_sample.curvature) <= 0.001f) {
		return p_sample.distance;
	}
	const float thalweg_offset = -p_sample.curvature * p_deep_radius * 0.48f;
	return std::abs(p_sample.signed_distance - thalweg_offset);
}

float resolve_dynamic_river_radius_scale(const RiverRasterEdge &p_edge, const SegmentProjection &p_projection) {
	if (!p_edge.organic) {
		return p_edge.radius_scale;
	}
	const float order_f = std::max(1.0f, static_cast<float>(p_edge.stream_order));
	if (p_edge.shape_quality_v2_fix && p_edge.cumulative_end > p_edge.cumulative_start + 0.001f) {
		const float river_distance = lerp_float(p_edge.cumulative_start, p_edge.cumulative_end, p_projection.t);
		const uint64_t river_seed = splitmix64(p_edge.variation_seed);
		const float phase_a = hash_grid_unit(river_seed, 0, 0) * PI * 2.0f;
		const float phase_b = hash_grid_unit(river_seed, 1, 0) * PI * 2.0f;
		const float wavelength_a = 34.0f + order_f * 8.0f;
		const float wavelength_b = wavelength_a * 2.45f;
		const float wave_a = std::sin(phase_a + river_distance / wavelength_a * PI * 2.0f);
		const float wave_b = std::sin(phase_b + river_distance / wavelength_b * PI * 2.0f);
		const float amplitude = world_utils::clamp_value(0.045f + order_f * 0.006f, 0.045f, 0.08f);
		const float multiplier = 1.0f + wave_a * amplitude + wave_b * 0.025f;
		const float min_scale = std::max(0.72f, p_edge.radius_scale * 0.82f);
		const float max_scale = std::max(min_scale, p_edge.radius_scale * 1.20f);
		return world_utils::clamp_value(p_edge.radius_scale * multiplier, min_scale, max_scale);
	}
	const float phase_a = hash_grid_unit(p_edge.variation_seed, 0, 0) * PI * 2.0f;
	const float phase_b = hash_grid_unit(p_edge.variation_seed, 1, 0) * PI * 2.0f;
	const float wave_a = std::sin(phase_a + p_projection.t * (2.2f + order_f * 0.22f) * PI);
	const float wave_b = std::sin(phase_b + p_projection.t * (5.0f + order_f * 0.13f) * PI);
	const float amplitude = world_utils::clamp_value(0.16f + order_f * 0.018f, 0.16f, 0.34f);
	const float multiplier = 1.0f + wave_a * amplitude + wave_b * 0.08f;
	const float min_scale = std::max(0.58f, p_edge.radius_scale * 0.58f);
	const float max_scale = std::max(min_scale, p_edge.radius_scale * 1.70f);
	return world_utils::clamp_value(p_edge.radius_scale * multiplier, min_scale, max_scale);
}

RiverRasterSample sample_river_edges(
	const std::vector<RiverRasterEdge> &p_edges,
	float p_world_x,
	float p_world_y,
	float p_world_width_tiles
) {
	RiverRasterSample sample;
	for (const RiverRasterEdge &edge : p_edges) {
		const SegmentProjection projection = project_to_segment(p_world_x, p_world_y, edge, p_world_width_tiles);
		if (projection.distance >= sample.distance) {
			continue;
		}
		sample.distance = projection.distance;
		sample.segment_id = edge.segment_id;
		sample.stream_order = edge.stream_order;
		sample.flow_dir = edge.flow_dir;
		sample.radius_scale = resolve_dynamic_river_radius_scale(edge, projection);
		sample.signed_distance = projection.signed_distance;
		sample.curvature = edge.curvature;
		sample.confluence_weight = edge.confluence ? std::max(0.35f, edge.confluence_weight) : 0.0f;
		sample.cumulative_distance = lerp_float(edge.cumulative_start, edge.cumulative_end, projection.t);
		sample.total_distance = edge.total_distance;
		sample.distance_at_source = std::max(0.0f, sample.cumulative_distance);
		sample.distance_to_terminal = std::max(0.0f, edge.total_distance - sample.cumulative_distance);
		sample.discharge_norm = lerp_float(edge.discharge_norm_start, edge.discharge_norm_end, projection.t);
		sample.width_profile_scale = lerp_float(edge.width_profile_scale_start, edge.width_profile_scale_end, projection.t);
		sample.ford_narrowing = lerp_float(edge.ford_narrowing_start, edge.ford_narrowing_end, projection.t);
		sample.shape_quality_v2_fix = edge.shape_quality_v2_fix;
		sample.source = edge.source;
		sample.delta = edge.delta;
		sample.braid_split = edge.braid_split;
		sample.confluence = edge.confluence;
		sample.discharge_width_profile = edge.discharge_width_profile;
	}
	return sample;
}

bool is_river_ground_edge_blocker(
	const std::vector<RiverRasterEdge> &p_edges,
	int64_t p_world_x,
	int64_t p_world_y,
	float p_world_width_tiles,
	float p_river_width_scale
) {
	const RiverRasterSample river_sample = sample_river_edges(
		p_edges,
		static_cast<float>(p_world_x) + 0.5f,
		static_cast<float>(p_world_y) + 0.5f,
		p_world_width_tiles
	);
	if (river_sample.segment_id <= 0) {
		return false;
	}
	const RiverChannelRadii radii = resolve_river_channel_radii(river_sample, p_river_width_scale);
	return river_sample.distance <= radii.bank_radius;
}

bool lake_basin_continuity_river_shore_applies(
	const std::vector<RiverRasterEdge> &p_edges,
	int64_t p_world_x,
	int64_t p_world_y,
	float p_world_width_tiles,
	float p_river_width_scale,
	RiverRasterSample *r_river_sample
) {
	if (p_edges.empty()) {
		return false;
	}
	const RiverRasterSample river_sample = sample_river_edges(
		p_edges,
		static_cast<float>(p_world_x) + 0.5f,
		static_cast<float>(p_world_y) + 0.5f,
		p_world_width_tiles
	);
	if (r_river_sample != nullptr) {
		*r_river_sample = river_sample;
	}
	if (river_sample.segment_id <= 0) {
		return false;
	}
	const RiverChannelRadii radii = resolve_river_channel_radii(river_sample, p_river_width_scale);
	const float widened_lake_shore_radius = std::max(radii.bed_radius + 0.75f, radii.bank_radius * 1.15f);
	return river_sample.distance <= widened_lake_shore_radius;
}

std::vector<RiverRasterEdge> filter_river_edges_for_chunk(
	const std::vector<RiverRasterEdge> &p_edges,
	int64_t p_chunk_origin_x,
	int64_t p_chunk_origin_y,
	float p_world_width_tiles,
	float p_max_radius_tiles
) {
	std::vector<RiverRasterEdge> filtered;
	filtered.reserve(std::min<size_t>(p_edges.size(), 64));
	const float chunk_min_x = static_cast<float>(p_chunk_origin_x) - p_max_radius_tiles;
	const float chunk_max_x = static_cast<float>(p_chunk_origin_x + CHUNK_SIZE) + p_max_radius_tiles;
	const float chunk_min_y = static_cast<float>(p_chunk_origin_y) - p_max_radius_tiles;
	const float chunk_max_y = static_cast<float>(p_chunk_origin_y + CHUNK_SIZE) + p_max_radius_tiles;
	const float chunk_anchor_x = (chunk_min_x + chunk_max_x) * 0.5f;
	for (const RiverRasterEdge &edge : p_edges) {
		RiverRasterEdge adjusted = edge;
		adjusted.ax = adjust_wrapped_x_near(adjusted.ax, chunk_anchor_x, p_world_width_tiles);
		adjusted.bx = adjust_wrapped_x_near(adjusted.bx, adjusted.ax, p_world_width_tiles);
		const float min_x = std::min(adjusted.ax, adjusted.bx);
		const float max_x = std::max(adjusted.ax, adjusted.bx);
		const float min_y = std::min(adjusted.ay, adjusted.by);
		const float max_y = std::max(adjusted.ay, adjusted.by);
		if (max_x < chunk_min_x || min_x > chunk_max_x || max_y < chunk_min_y || min_y > chunk_max_y) {
			continue;
		}
		filtered.push_back(adjusted);
	}
	return filtered;
}

std::vector<RiverRasterEdge> convert_refined_edges_for_chunk(
	const std::vector<world_hydrology_prepass::RefinedRiverEdge> &p_edges,
	float p_chunk_anchor_x,
	float p_world_width_tiles
) {
	std::vector<RiverRasterEdge> converted;
	converted.reserve(p_edges.size());
	for (const world_hydrology_prepass::RefinedRiverEdge &refined : p_edges) {
		RiverRasterEdge edge;
		edge.ax = adjust_wrapped_x_near(refined.ax, p_chunk_anchor_x, p_world_width_tiles);
		edge.ay = refined.ay;
		edge.bx = adjust_wrapped_x_near(refined.bx, edge.ax, p_world_width_tiles);
		edge.by = refined.by;
		edge.segment_id = refined.segment_id;
		edge.stream_order = refined.stream_order;
		edge.flow_dir = refined.flow_dir;
		edge.radius_scale = refined.radius_scale;
		edge.curvature = refined.curvature;
		edge.confluence_weight = refined.confluence_weight;
		edge.cumulative_start = refined.cumulative_start;
		edge.cumulative_end = refined.cumulative_end;
		edge.total_distance = refined.total_distance;
		edge.distance_at_source = refined.distance_at_source;
		edge.distance_to_terminal = refined.distance_to_terminal;
		edge.discharge_norm_start = refined.discharge_norm_start;
		edge.discharge_norm_end = refined.discharge_norm_end;
		edge.width_profile_scale_start = refined.width_profile_scale_start;
		edge.width_profile_scale_end = refined.width_profile_scale_end;
		edge.ford_narrowing_start = refined.ford_narrowing_start;
		edge.ford_narrowing_end = refined.ford_narrowing_end;
		edge.variation_seed = refined.variation_seed;
		edge.source = refined.source;
		edge.delta = refined.delta;
		edge.braid_split = refined.braid_split;
		edge.confluence = refined.confluence;
		edge.discharge_width_profile = refined.discharge_width_profile;
		edge.organic = refined.organic;
		edge.shape_quality_v2_fix = refined.shape_quality_v2_fix;
		converted.push_back(edge);
	}
	return converted;
}

std::vector<RiverRasterEdge> build_river_raster_edges(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	const world_hydrology_prepass::RiverSettings &p_river_settings
) {
	std::vector<RiverRasterEdge> edges;
	if (!p_snapshot.valid || p_snapshot.river_segment_ranges.empty() || p_snapshot.river_path_node_indices.empty()) {
		return edges;
	}
	const bool enable_v1_r5 = uses_delta_generation(p_snapshot.world_version);
	const bool enable_organic = uses_organic_water_generation(p_snapshot.world_version);
	const float world_width_tiles = static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles));
	const float braid_chance = world_utils::saturate(p_river_settings.braid_chance);
	const float delta_scale = world_utils::clamp_value(p_river_settings.delta_scale, 0.0f, 2.0f);
	auto push_edge = [&](std::vector<RiverRasterEdge> &r_edges, const RiverRasterEdge &p_edge) {
		RiverRasterEdge adjusted = p_edge;
		adjusted.bx = adjust_wrapped_x_near(adjusted.bx, adjusted.ax, world_width_tiles);
		r_edges.push_back(adjusted);
	};
	auto push_meandered_edge = [&](std::vector<RiverRasterEdge> &r_edges, const RiverRasterEdge &p_edge) {
		if (!enable_organic || p_edge.delta || p_river_settings.meander_strength <= 0.01f) {
			push_edge(r_edges, p_edge);
			return;
		}
		const float dx = p_edge.bx - p_edge.ax;
		const float dy = p_edge.by - p_edge.ay;
		const float length = std::sqrt(dx * dx + dy * dy);
		if (length <= 6.0f) {
			push_edge(r_edges, p_edge);
			return;
		}
		const float inv_length = 1.0f / length;
		const float nx = -dy * inv_length;
		const float ny = dx * inv_length;
		const float side = (p_edge.variation_seed & 1ULL) != 0ULL ? 1.0f : -1.0f;
		const float selector = hash_grid_unit(p_edge.variation_seed, 2, 0);
		const float order_f = std::max(1.0f, static_cast<float>(p_edge.stream_order));
		const float amplitude_limit = std::min(length * 0.30f, static_cast<float>(p_snapshot.cell_size_tiles) * (0.34f + order_f * 0.035f));
		const float amplitude = amplitude_limit * world_utils::saturate(p_river_settings.meander_strength) * (0.55f + selector * 0.45f) * side;
		const float mid_t = 0.42f + hash_grid_unit(p_edge.variation_seed, 3, 0) * 0.16f;
		const float mx = p_edge.ax + dx * mid_t + nx * amplitude;
		const float my = p_edge.ay + dy * mid_t + ny * amplitude;
		RiverRasterEdge first = p_edge;
		first.bx = mx;
		first.by = my;
		RiverRasterEdge second = p_edge;
		second.ax = mx;
		second.ay = my;
		second.source = false;
		push_edge(r_edges, first);
		push_edge(r_edges, second);
	};
	auto push_branch_edge = [&](std::vector<RiverRasterEdge> &r_edges, const RiverRasterEdge &p_template, float p_ax, float p_ay, float p_bx, float p_by) {
		RiverRasterEdge branch = p_template;
		branch.ax = p_ax;
		branch.ay = p_ay;
		branch.bx = adjust_wrapped_x_near(p_bx, p_ax, world_width_tiles);
		branch.by = p_by;
		r_edges.push_back(branch);
	};
	for (size_t record_offset = 0; record_offset + RIVER_SEGMENT_RECORD_SIZE <= p_snapshot.river_segment_ranges.size(); record_offset += RIVER_SEGMENT_RECORD_SIZE) {
		const int32_t segment_id = p_snapshot.river_segment_ranges[record_offset];
		const int32_t path_offset = p_snapshot.river_segment_ranges[record_offset + 1];
		const int32_t path_length = p_snapshot.river_segment_ranges[record_offset + 2];
		if (segment_id <= 0 || path_offset < 0 || path_length < 2) {
			continue;
		}
		const int32_t path_end = path_offset + path_length;
		if (path_end > static_cast<int32_t>(p_snapshot.river_path_node_indices.size())) {
			continue;
		}
		for (int32_t path_index = path_offset; path_index < path_end - 1; ++path_index) {
			const int32_t from_node = p_snapshot.river_path_node_indices[static_cast<size_t>(path_index)];
			const int32_t to_node = p_snapshot.river_path_node_indices[static_cast<size_t>(path_index + 1)];
			if (from_node < 0 || to_node < 0 ||
					from_node >= p_snapshot.grid_width * p_snapshot.grid_height ||
					to_node >= p_snapshot.grid_width * p_snapshot.grid_height) {
				continue;
			}
			const Vector2i from_center = p_snapshot.node_to_tile_center(from_node % p_snapshot.grid_width, from_node / p_snapshot.grid_width);
			const Vector2i to_center = p_snapshot.node_to_tile_center(to_node % p_snapshot.grid_width, to_node / p_snapshot.grid_width);
			RiverRasterEdge edge;
			edge.ax = static_cast<float>(from_center.x) + 0.5f;
			edge.ay = static_cast<float>(from_center.y) + 0.5f;
			edge.bx = adjust_wrapped_x_near(static_cast<float>(to_center.x) + 0.5f, edge.ax, static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles)));
			edge.by = static_cast<float>(to_center.y) + 0.5f;
			edge.segment_id = segment_id;
			edge.stream_order = p_snapshot.river_stream_order.size() > static_cast<size_t>(from_node) ?
					p_snapshot.river_stream_order[static_cast<size_t>(from_node)] :
					1U;
			edge.flow_dir = p_snapshot.flow_dir.size() > static_cast<size_t>(from_node) ?
					p_snapshot.flow_dir[static_cast<size_t>(from_node)] :
					world_hydrology_prepass::FLOW_DIR_TERMINAL;
			edge.variation_seed = splitmix64(
				static_cast<uint64_t>(p_snapshot.seed) ^
				(static_cast<uint64_t>(hydrology_detail_seed_version(p_snapshot.world_version)) << 32U) ^
				(static_cast<uint64_t>(segment_id) * 0x9e3779b185ebca87ULL) ^
				(static_cast<uint64_t>(from_node) << 16U) ^
				static_cast<uint64_t>(to_node)
			);
			edge.organic = enable_organic;
			edge.source = path_index == path_offset;
			const bool from_lake = p_snapshot.lake_id.size() > static_cast<size_t>(from_node) &&
					p_snapshot.lake_id[static_cast<size_t>(from_node)] > 0;
			const bool to_lake = p_snapshot.lake_id.size() > static_cast<size_t>(to_node) &&
					p_snapshot.lake_id[static_cast<size_t>(to_node)] > 0;
			const bool to_ocean = p_snapshot.ocean_sink_mask.size() > static_cast<size_t>(to_node) &&
					p_snapshot.ocean_sink_mask[static_cast<size_t>(to_node)] != 0U;
			if (enable_v1_r5 && to_ocean && delta_scale > 0.0f) {
				edge.delta = true;
				edge.radius_scale = 1.0f + delta_scale * 0.85f;
			}
			push_meandered_edge(edges, edge);

			if (!enable_v1_r5) {
				continue;
			}
			const float dx = edge.bx - edge.ax;
			const float dy = edge.by - edge.ay;
			const float length = std::sqrt(dx * dx + dy * dy);
			if (length <= 8.0f) {
				continue;
			}
			const float inv_length = 1.0f / length;
			const float nx = -dy * inv_length;
			const float ny = dx * inv_length;
			const uint64_t branch_hash = splitmix64(
				static_cast<uint64_t>(p_snapshot.seed) ^
				(static_cast<uint64_t>(hydrology_detail_seed_version(p_snapshot.world_version)) << 32U) ^
				(static_cast<uint64_t>(segment_id) * 0x9e3779b185ebca87ULL) ^
				(static_cast<uint64_t>(from_node) << 16U) ^
				static_cast<uint64_t>(to_node)
			);
			const float branch_selector = static_cast<float>(branch_hash & 0x00ffffffULL) /
					static_cast<float>(0x00ffffffULL);
			const float side = (branch_hash & 0x01000000ULL) != 0ULL ? 1.0f : -1.0f;

			if (to_ocean && delta_scale > 0.0f) {
				const float fan_offset = (4.0f + static_cast<float>(edge.stream_order) * 0.65f) *
						std::max(0.75f, p_river_settings.width_scale) *
						delta_scale;
				for (int32_t branch_index = -1; branch_index <= 1; branch_index += 2) {
					RiverRasterEdge delta_branch = edge;
					delta_branch.delta = true;
					delta_branch.braid_split = true;
					delta_branch.source = false;
					delta_branch.radius_scale = std::max(edge.radius_scale, 1.15f + delta_scale * 0.55f);
					const float branch_side = static_cast<float>(branch_index);
					push_branch_edge(
						edges,
						delta_branch,
						edge.ax + dx * 0.30f,
						edge.ay + dy * 0.30f,
						edge.bx + nx * fan_offset * branch_side,
						edge.by + ny * fan_offset * branch_side
					);
				}
				continue;
			}

			if (braid_chance <= 0.0f || branch_selector > braid_chance ||
					edge.stream_order < 3U || from_lake || to_lake || to_ocean) {
				continue;
			}
			RiverRasterEdge split_branch = edge;
			split_branch.braid_split = true;
			split_branch.source = false;
			split_branch.radius_scale = 0.72f;
			const float branch_offset = std::max(2.5f, (1.75f + static_cast<float>(edge.stream_order) * 0.45f) *
					std::max(0.75f, p_river_settings.width_scale));
			const float sx = edge.ax + dx * 0.22f + nx * branch_offset * side;
			const float sy = edge.ay + dy * 0.22f + ny * branch_offset * side;
			const float ex = edge.ax + dx * 0.78f + nx * branch_offset * side;
			const float ey = edge.ay + dy * 0.78f + ny * branch_offset * side;
			push_branch_edge(edges, split_branch, edge.ax, edge.ay, sx, sy);
			push_branch_edge(edges, split_branch, sx, sy, ex, ey);
			push_branch_edge(edges, split_branch, ex, ey, edge.bx, edge.by);
		}
	}
	return edges;
}

int32_t sample_hydrology_node_index(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return -1;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(
		p_world_x / std::max<int32_t>(1, p_snapshot.cell_size_tiles),
		p_snapshot.grid_width
	));
	const int32_t node_y = world_utils::clamp_value(
		static_cast<int32_t>(p_world_y / std::max<int32_t>(1, p_snapshot.cell_size_tiles)),
		0,
		p_snapshot.grid_height - 1
	);
	return p_snapshot.index(node_x, node_y);
}

int32_t sample_lake_id_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y
) {
	if (!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_snapshot.lake_id.empty()) {
		return 0;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.lake_id.size())) {
		return 0;
	}
	return p_snapshot.lake_id[static_cast<size_t>(node_index)];
}

float sample_lake_depth_ratio_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y
) {
	if (!uses_basin_contour_lake_generation(p_snapshot.world_version) ||
			!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_snapshot.lake_depth_ratio.empty()) {
		return 1.0f;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.lake_depth_ratio.size())) {
		return 1.0f;
	}
	return world_utils::saturate(p_snapshot.lake_depth_ratio[static_cast<size_t>(node_index)]);
}

float sample_hydrology_float_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	int32_t p_node_x,
	int32_t p_node_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_values.empty()) {
		return p_fallback;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_values.size())) {
		return p_fallback;
	}
	return p_values[static_cast<size_t>(node_index)];
}

float sample_hydrology_float_bilinear(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	int64_t p_world_x,
	int64_t p_world_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0 ||
			p_values.empty()) {
		return p_fallback;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float gx = (static_cast<float>(p_world_x) + 0.5f) / cell_size - 0.5f;
	const float gy = (static_cast<float>(p_world_y) + 0.5f) / cell_size - 0.5f;
	const int32_t x0_raw = static_cast<int32_t>(std::floor(gx));
	const int32_t y0_raw = static_cast<int32_t>(std::floor(gy));
	const float tx = smoothstep_unit(gx - static_cast<float>(x0_raw));
	const float ty = smoothstep_unit(gy - static_cast<float>(y0_raw));
	const int32_t y0 = world_utils::clamp_value(y0_raw, 0, p_snapshot.grid_height - 1);
	const int32_t y1 = world_utils::clamp_value(y0_raw + 1, 0, p_snapshot.grid_height - 1);
	const float v00 = sample_hydrology_float_at_node(p_snapshot, p_values, x0_raw, y0, p_fallback);
	const float v10 = sample_hydrology_float_at_node(p_snapshot, p_values, x0_raw + 1, y0, p_fallback);
	const float v01 = sample_hydrology_float_at_node(p_snapshot, p_values, x0_raw, y1, p_fallback);
	const float v11 = sample_hydrology_float_at_node(p_snapshot, p_values, x0_raw + 1, y1, p_fallback);
	const float vx0 = lerp_float(v00, v10, tx);
	const float vx1 = lerp_float(v01, v11, tx);
	return lerp_float(vx0, vx1, ty);
}

int32_t sample_nearest_lake_id_for_tile(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0) {
		return 0;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float gx = (static_cast<float>(p_world_x) + 0.5f) / cell_size - 0.5f;
	const float gy = (static_cast<float>(p_world_y) + 0.5f) / cell_size - 0.5f;
	const int32_t node_x = static_cast<int32_t>(std::floor(gx + 0.5f));
	const int32_t node_y = world_utils::clamp_value(
		static_cast<int32_t>(std::floor(gy + 0.5f)),
		0,
		p_snapshot.grid_height - 1
	);
	int32_t best_lake_id = 0;
	float best_distance_sq = std::numeric_limits<float>::infinity();
	const float tile_x = static_cast<float>(p_world_x) + 0.5f;
	const float tile_y = static_cast<float>(p_world_y) + 0.5f;
	const float world_width = static_cast<float>(std::max<int64_t>(1, p_snapshot.width_tiles));
	const float max_distance = cell_size * 0.75f + 3.0f;
	for (int32_t dy = -1; dy <= 1; ++dy) {
		const int32_t sample_y = node_y + dy;
		if (sample_y < 0 || sample_y >= p_snapshot.grid_height) {
			continue;
		}
		for (int32_t dx = -1; dx <= 1; ++dx) {
			const int32_t sample_x_raw = node_x + dx;
			const int32_t lake_id = sample_lake_id_at_node(p_snapshot, sample_x_raw, sample_y);
			if (lake_id <= 0) {
				continue;
			}
			float node_center_x = static_cast<float>(sample_x_raw) * cell_size + cell_size * 0.5f;
			node_center_x = adjust_wrapped_x_near(node_center_x, tile_x, world_width);
			const float node_center_y = static_cast<float>(sample_y) * cell_size + cell_size * 0.5f;
			const float delta_x = tile_x - node_center_x;
			const float delta_y = tile_y - node_center_y;
			const float distance_sq = delta_x * delta_x + delta_y * delta_y;
			if (distance_sq < best_distance_sq) {
				best_distance_sq = distance_sq;
				best_lake_id = lake_id;
			}
		}
	}
	return best_distance_sq <= max_distance * max_distance ? best_lake_id : 0;
}

float sample_lake_water_level_for_id(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_lake_id,
	float p_fallback
) {
	if (p_lake_id <= 0 || p_lake_id >= static_cast<int32_t>(p_snapshot.lake_water_level_per_id.size())) {
		return p_fallback;
	}
	const float water_level = p_snapshot.lake_water_level_per_id[static_cast<size_t>(p_lake_id)];
	return std::isfinite(water_level) ? water_level : p_fallback;
}

float sample_lake_gradient_per_tile(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y,
	float p_hydro_elevation_at_tile
) {
	const float west = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.hydro_elevation,
		p_world_x - 1,
		p_world_y,
		p_hydro_elevation_at_tile
	);
	const float east = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.hydro_elevation,
		p_world_x + 1,
		p_world_y,
		p_hydro_elevation_at_tile
	);
	const float north = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.hydro_elevation,
		p_world_x,
		p_world_y - 1,
		p_hydro_elevation_at_tile
	);
	const float south = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.hydro_elevation,
		p_world_x,
		p_world_y + 1,
		p_hydro_elevation_at_tile
	);
	const float gx = (east - west) * 0.5f;
	const float gy = (south - north) * 0.5f;
	return std::max(0.0005f, std::sqrt(gx * gx + gy * gy));
}

float sample_lake_shoreline_noise_tiles(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_lake_id,
	int64_t p_world_x,
	int64_t p_world_y
) {
	const uint64_t seed = world_utils::mix_seed(
		p_snapshot.seed,
		hydrology_detail_seed_version(p_snapshot.world_version),
		0x3c6ef372fe94f82bULL ^ static_cast<uint64_t>(p_lake_id)
	);
	const float wavelength = 3.0f + hash_grid_unit(seed ^ 0x51ed27055247af03ULL, p_lake_id, 0) * 3.0f;
	const float amplitude_tiles = 1.0f + hash_grid_unit(seed ^ 0xd1b54a32d192ed03ULL, 0, p_lake_id) * 2.0f;
	const float coarse = signed_value_noise_2d(
		seed,
		static_cast<float>(p_world_x) / wavelength,
		static_cast<float>(p_world_y) / wavelength
	);
	const float fine = signed_value_noise_2d(
		seed ^ 0x9e3779b185ebca87ULL,
		static_cast<float>(p_world_x) / std::max(3.0f, wavelength * 0.58f),
		static_cast<float>(p_world_y) / std::max(3.0f, wavelength * 0.58f)
	);
	return (coarse * 0.72f + fine * 0.28f) * amplitude_tiles;
}

uint8_t resolve_v3_floodplain_strength_byte(float p_floodplain_potential) {
	const float strength_t = smoothstep(0.45f, 0.85f, world_utils::saturate(p_floodplain_potential));
	return static_cast<uint8_t>(world_utils::clamp_value(
		static_cast<int32_t>(std::lround(strength_t * 255.0f)),
		0,
		255
	));
}

V3LakeSdfSample resolve_v3_lake_sdf_sample(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y
) {
	V3LakeSdfSample sample;
	const int32_t lake_id_nearest = sample_nearest_lake_id_for_tile(p_snapshot, p_world_x, p_world_y);
	if (lake_id_nearest <= 0) {
		return sample;
	}

	const float filled_elevation_at_tile = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.filled_elevation,
		p_world_x,
		p_world_y,
		0.0f
	);
	const float hydro_elevation_at_tile = sample_hydrology_float_bilinear(
		p_snapshot,
		p_snapshot.hydro_elevation,
		p_world_x,
		p_world_y,
		filled_elevation_at_tile
	);
	const float water_level = sample_lake_water_level_for_id(
		p_snapshot,
		lake_id_nearest,
		filled_elevation_at_tile
	);
	const float gradient_per_tile = sample_lake_gradient_per_tile(
		p_snapshot,
		p_world_x,
		p_world_y,
		hydro_elevation_at_tile
	);
	const float unnoised_distance_tiles = (water_level - hydro_elevation_at_tile) / gradient_per_tile;
	const float periphery_weight = 1.0f - world_utils::saturate(
			(std::abs(unnoised_distance_tiles) - 1.0f) / 3.0f);
	const float shoreline_noise_tiles = sample_lake_shoreline_noise_tiles(
		p_snapshot,
		lake_id_nearest,
		p_world_x,
		p_world_y
	) * periphery_weight;
	const float shoreline_noise = shoreline_noise_tiles * gradient_per_tile;
	const float signed_distance_tiles = (water_level + shoreline_noise - hydro_elevation_at_tile) / gradient_per_tile;

	sample.lake_id = lake_id_nearest;
	sample.signed_distance_tiles = signed_distance_tiles;
	sample.is_lakebed = lake_id_nearest > 0 && hydro_elevation_at_tile <= water_level + shoreline_noise;
	sample.is_contour_band = std::abs(signed_distance_tiles) <= 1.0f;
	if (sample.is_contour_band) {
		const float shore_t = 1.0f - world_utils::saturate(std::abs(signed_distance_tiles));
		sample.shore_strength = static_cast<uint8_t>(world_utils::clamp_value(
			static_cast<int32_t>(std::lround(shore_t * 255.0f)),
			32,
			255
		));
	}
	return sample;
}

int32_t sample_ocean_mask_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y
) {
	if (!p_snapshot.valid || p_snapshot.ocean_sink_mask.empty()) {
		return 0;
	}
	if (p_node_y < 0) {
		return 1;
	}
	if (p_node_y >= p_snapshot.grid_height) {
		return 0;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.ocean_sink_mask.size())) {
		return 0;
	}
	return p_snapshot.ocean_sink_mask[static_cast<size_t>(node_index)] != 0U ? 1 : 0;
}

bool is_v3_ocean_mountain_suppression_tile(
	int64_t p_world_version,
	int64_t p_world_x,
	int64_t p_world_y,
	const FoundationSettings &p_foundation_settings,
	const world_hydrology_prepass::Snapshot *p_hydrology_snapshot
) {
	if (!uses_hydrology_visual_v3(p_world_version)) {
		return false;
	}
	if (p_foundation_settings.enabled &&
			p_foundation_settings.ocean_band_tiles > 0 &&
			p_world_y < p_foundation_settings.ocean_band_tiles) {
		return true;
	}
	if (p_hydrology_snapshot == nullptr || !p_hydrology_snapshot->valid) {
		return false;
	}
	const int32_t node_index = sample_hydrology_node_index(*p_hydrology_snapshot, p_world_x, p_world_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_hydrology_snapshot->ocean_sink_mask.size())) {
		return false;
	}
	return p_hydrology_snapshot->ocean_sink_mask[static_cast<size_t>(node_index)] != 0U;
}

float sample_ocean_shelf_ratio_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y
) {
	if (!uses_organic_coastline_generation(p_snapshot.world_version) ||
			!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_snapshot.ocean_shelf_depth_ratio.empty()) {
		return 1.0f;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.ocean_shelf_depth_ratio.size())) {
		return 1.0f;
	}
	return world_utils::saturate(p_snapshot.ocean_shelf_depth_ratio[static_cast<size_t>(node_index)]);
}

float sample_ocean_mouth_influence_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_x,
	int32_t p_node_y
) {
	if (!uses_organic_coastline_generation(p_snapshot.world_version) ||
			!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_snapshot.ocean_river_mouth_influence.empty()) {
		return 0.0f;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_snapshot.ocean_river_mouth_influence.size())) {
		return 0.0f;
	}
	return world_utils::saturate(p_snapshot.ocean_river_mouth_influence[static_cast<size_t>(node_index)]);
}

float sample_ocean_float_field_at_node(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	int32_t p_node_x,
	int32_t p_node_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_node_y < 0 || p_node_y >= p_snapshot.grid_height ||
			p_values.empty()) {
		return p_fallback;
	}
	const int32_t node_x = static_cast<int32_t>(positive_mod(p_node_x, p_snapshot.grid_width));
	const int32_t node_index = p_snapshot.index(node_x, p_node_y);
	if (node_index < 0 || node_index >= static_cast<int32_t>(p_values.size())) {
		return p_fallback;
	}
	return p_values[static_cast<size_t>(node_index)];
}

float sample_ocean_float_field_bilinear(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	const std::vector<float> &p_values,
	int64_t p_world_x,
	int64_t p_world_y,
	float p_fallback
) {
	if (!p_snapshot.valid || p_snapshot.grid_width <= 0 || p_snapshot.grid_height <= 0 ||
			p_values.empty()) {
		return p_fallback;
	}
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const float gx = (static_cast<float>(p_world_x) + 0.5f) / cell_size - 0.5f;
	const float gy = (static_cast<float>(p_world_y) + 0.5f) / cell_size - 0.5f;
	const int32_t x0_raw = static_cast<int32_t>(std::floor(gx));
	const int32_t y0_raw = static_cast<int32_t>(std::floor(gy));
	const float tx = smoothstep_unit(gx - static_cast<float>(x0_raw));
	const float ty = smoothstep_unit(gy - static_cast<float>(y0_raw));
	const int32_t y0 = world_utils::clamp_value(y0_raw, 0, p_snapshot.grid_height - 1);
	const int32_t y1 = world_utils::clamp_value(y0_raw + 1, 0, p_snapshot.grid_height - 1);
	const float v00 = sample_ocean_float_field_at_node(p_snapshot, p_values, x0_raw, y0, p_fallback);
	const float v10 = sample_ocean_float_field_at_node(p_snapshot, p_values, x0_raw + 1, y0, p_fallback);
	const float v01 = sample_ocean_float_field_at_node(p_snapshot, p_values, x0_raw, y1, p_fallback);
	const float v11 = sample_ocean_float_field_at_node(p_snapshot, p_values, x0_raw + 1, y1, p_fallback);
	const float vx0 = lerp_float(v00, v10, tx);
	const float vx1 = lerp_float(v01, v11, tx);
	return lerp_float(vx0, vx1, ty);
}

float sample_organic_coast_distance_tiles(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int64_t p_world_x,
	int64_t p_world_y
) {
	const float base_distance = sample_ocean_float_field_bilinear(
		p_snapshot,
		p_snapshot.ocean_coast_distance_tiles,
		p_world_x,
		p_world_y,
		-1024.0f
	);
	const float cell_size = static_cast<float>(std::max(1, p_snapshot.cell_size_tiles));
	const bool headland_coast = p_snapshot.world_version >= WORLD_HEADLAND_COAST_VERSION;
	const float coast_band_width = headland_coast ? cell_size * 5.0f : cell_size * 2.35f;
	const float near_coast = 1.0f - world_utils::saturate(std::abs(base_distance) / std::max(1.0f, coast_band_width));
	if (near_coast <= 0.0f) {
		return base_distance;
	}
	const float mouth_influence = world_utils::saturate(sample_ocean_float_field_bilinear(
		p_snapshot,
		p_snapshot.ocean_river_mouth_influence,
		p_world_x,
		p_world_y,
		0.0f
	));
	const uint64_t seed = world_utils::mix_seed(
		p_snapshot.seed,
		WORLD_HYDROLOGY_SHAPE_FIX_VERSION,
		0x2f14f965916a6f19ULL
	);
	const float coarse_noise = signed_value_noise_2d(
		seed,
		static_cast<float>(p_world_x) / std::max(8.0f, cell_size * 3.65f),
		static_cast<float>(p_world_y) / std::max(8.0f, cell_size * 3.65f)
	);
	const float fine_noise = signed_value_noise_2d(
		seed ^ 0x9e3779b185ebca87ULL,
		static_cast<float>(p_world_x) / std::max(4.0f, cell_size * 1.20f),
		static_cast<float>(p_world_y) / std::max(4.0f, cell_size * 1.20f)
	);
	float coastline_offset = (coarse_noise * 0.72f + fine_noise * 0.28f) * cell_size * 0.46f * near_coast;
	if (headland_coast) {
		const float headland_noise = signed_value_noise_2d(
			seed ^ 0xa5b2c3d4e5f60718ULL,
			static_cast<float>(p_world_x) / std::max(16.0f, cell_size * 8.0f),
			static_cast<float>(p_world_y) / std::max(16.0f, cell_size * 8.0f)
		);
		const float headland_offset = headland_noise * cell_size * 1.50f * near_coast;
		coastline_offset = (
			headland_offset +
			(coarse_noise * 0.72f + fine_noise * 0.28f) * cell_size * 0.46f
		) * near_coast;
	}
	const float mouth_scale = uses_estuary_delta_v4(p_snapshot.world_version) ?
			(2.10f + world_utils::clamp_value(p_snapshot.river_settings.delta_scale, 0.0f, 2.0f) * 0.55f) :
			0.72f;
	const float mouth_offset = mouth_influence * cell_size * mouth_scale * near_coast;
	return base_distance + coastline_offset + mouth_offset;
}

OceanRasterSample sample_ocean_raster(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_index,
	int64_t p_world_x,
	int64_t p_world_y,
	bool p_organic
) {
	OceanRasterSample sample;
	if (!p_snapshot.valid || p_node_index < 0 ||
			p_node_index >= static_cast<int32_t>(p_snapshot.ocean_sink_mask.size())) {
		return sample;
	}
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	const bool center_ocean = p_snapshot.ocean_sink_mask[static_cast<size_t>(p_node_index)] != 0U;
	const int32_t north_ocean = sample_ocean_mask_at_node(p_snapshot, node_x, node_y - 1);
	const int32_t east_ocean = sample_ocean_mask_at_node(p_snapshot, node_x + 1, node_y);
	const int32_t south_ocean = sample_ocean_mask_at_node(p_snapshot, node_x, node_y + 1);
	const int32_t west_ocean = sample_ocean_mask_at_node(p_snapshot, node_x - 1, node_y);
	const int32_t cell_size = std::max<int32_t>(1, p_snapshot.cell_size_tiles);
	const int32_t local_x = static_cast<int32_t>(positive_mod(p_world_x, cell_size));
	const int32_t local_y = world_utils::clamp_value(
		static_cast<int32_t>(p_world_y - static_cast<int64_t>(node_y) * cell_size),
		0,
		cell_size - 1
	);
	const int32_t shore_width = world_utils::clamp_value(cell_size / 3, 3, 7);
	const bool organic_coastline = p_organic && uses_organic_coastline_generation(p_snapshot.world_version);
	const float mouth_influence = organic_coastline ?
			std::max(
				sample_ocean_mouth_influence_at_node(p_snapshot, node_x, node_y),
				std::max(
					std::max(
						sample_ocean_mouth_influence_at_node(p_snapshot, node_x + 1, node_y),
						sample_ocean_mouth_influence_at_node(p_snapshot, node_x - 1, node_y)
					),
					std::max(
						sample_ocean_mouth_influence_at_node(p_snapshot, node_x, node_y + 1),
						sample_ocean_mouth_influence_at_node(p_snapshot, node_x, node_y - 1)
					)
				)
			) :
			0.0f;
	const float shelf_depth_ratio = sample_ocean_shelf_ratio_at_node(p_snapshot, node_x, node_y);
	auto ocean_noise = [&]() -> float {
		const uint64_t seed = world_utils::mix_seed(
			p_snapshot.seed,
			hydrology_detail_seed_version(p_snapshot.world_version),
			0x5f3564957a3c4e1bULL
		);
		const float scale = std::max(4.0f, static_cast<float>(cell_size) * 0.58f);
		return signed_value_noise_2d(
			seed,
			static_cast<float>(p_world_x) / scale,
			static_cast<float>(p_world_y) / scale
		);
	};
	auto effective_shore_width = [&]() -> float {
		if (!p_organic) {
			return static_cast<float>(shore_width);
		}
		return world_utils::clamp_value(
			static_cast<float>(shore_width) + ocean_noise() * 2.5f + mouth_influence * static_cast<float>(cell_size) * 0.32f,
			2.0f,
			std::min(static_cast<float>(shore_width) + 3.5f + mouth_influence * static_cast<float>(cell_size) * 0.42f, static_cast<float>(cell_size) * 0.62f)
		);
	};
	auto strength_for_distance = [&](float p_distance, float p_width) -> uint8_t {
		const float t = 1.0f - world_utils::saturate(p_distance / std::max(1.0f, p_width));
		return static_cast<uint8_t>(world_utils::clamp_value(
			static_cast<int32_t>(std::lround(t * 255.0f)),
			0,
			255
		));
	};

	if (organic_coastline && p_snapshot.world_version >= WORLD_HYDROLOGY_SHAPE_FIX_VERSION) {
		const float coast_distance = sample_organic_coast_distance_tiles(p_snapshot, p_world_x, p_world_y);
		const float mouth_influence_tile = world_utils::saturate(sample_ocean_float_field_bilinear(
			p_snapshot,
			p_snapshot.ocean_river_mouth_influence,
			p_world_x,
			p_world_y,
			0.0f
		));
		const float coast_width = world_utils::clamp_value(
			static_cast<float>(shore_width) + mouth_influence_tile * static_cast<float>(cell_size) * 0.22f,
			2.5f,
			static_cast<float>(cell_size) * 0.72f
		);
		if (std::abs(coast_distance) <= coast_width) {
			sample.is_shore = true;
			sample.shore_strength = strength_for_distance(std::abs(coast_distance), coast_width);
			return sample;
		}
		if (coast_distance > coast_width) {
			const float base_shelf_width = world_utils::clamp_value(
				static_cast<float>(p_snapshot.ocean_band_tiles) * 0.22f,
				static_cast<float>(cell_size) * 1.50f,
				static_cast<float>(cell_size) * 2.75f
			);
			const float local_shelf_width = base_shelf_width * (1.0f + mouth_influence_tile * 0.85f);
			const float shelf_ratio = world_utils::saturate(
				(coast_distance - coast_width * 0.35f) / std::max(1.0f, local_shelf_width) -
				mouth_influence_tile * 0.12f
			);
			sample.is_ocean_floor = true;
			sample.is_shallow_shelf = shelf_ratio < 0.72f;
			return sample;
		}
		return sample;
	}

	float best_distance = static_cast<float>(cell_size);
	if (center_ocean) {
		if (north_ocean == 0) {
			best_distance = std::min(best_distance, static_cast<float>(local_y));
		}
		if (east_ocean == 0) {
			best_distance = std::min(best_distance, static_cast<float>(cell_size - 1 - local_x));
		}
		if (south_ocean == 0) {
			best_distance = std::min(best_distance, static_cast<float>(cell_size - 1 - local_y));
		}
		if (west_ocean == 0) {
			best_distance = std::min(best_distance, static_cast<float>(local_x));
		}
		const float width = effective_shore_width();
		if (best_distance < width) {
			sample.is_shore = true;
			sample.shore_strength = strength_for_distance(best_distance, width);
			return sample;
		}
		sample.is_ocean_floor = true;
		sample.is_shallow_shelf = organic_coastline && shelf_depth_ratio < 0.72f;
		return sample;
	}

	auto consider_shore = [&](int32_t p_neighbor_ocean, int32_t p_distance) {
		if (p_neighbor_ocean == 0 || static_cast<float>(p_distance) >= best_distance) {
			return;
		}
		best_distance = static_cast<float>(p_distance);
	};
	consider_shore(north_ocean, local_y);
	consider_shore(east_ocean, cell_size - 1 - local_x);
	consider_shore(south_ocean, cell_size - 1 - local_y);
	consider_shore(west_ocean, local_x);
	const float width = effective_shore_width();
	if (best_distance < width) {
		sample.is_shore = true;
		sample.shore_strength = strength_for_distance(best_distance, width);
	}
	return sample;
}

LakeRasterSample sample_lake_raster(
	const world_hydrology_prepass::Snapshot &p_snapshot,
	int32_t p_node_index,
	int64_t p_world_x,
	int64_t p_world_y,
	bool p_organic
) {
	LakeRasterSample sample;
	if (!p_snapshot.valid || p_node_index < 0 ||
			p_node_index >= static_cast<int32_t>(p_snapshot.lake_id.size())) {
		return sample;
	}
	const int32_t node_x = p_node_index % p_snapshot.grid_width;
	const int32_t node_y = p_node_index / p_snapshot.grid_width;
	const int32_t center_lake_id = p_snapshot.lake_id[static_cast<size_t>(p_node_index)];
	const int32_t north_lake_id = sample_lake_id_at_node(p_snapshot, node_x, node_y - 1);
	const int32_t east_lake_id = sample_lake_id_at_node(p_snapshot, node_x + 1, node_y);
	const int32_t south_lake_id = sample_lake_id_at_node(p_snapshot, node_x, node_y + 1);
	const int32_t west_lake_id = sample_lake_id_at_node(p_snapshot, node_x - 1, node_y);
	const bool basin_contour = uses_basin_contour_lake_generation(p_snapshot.world_version);
	const float depth_ratio = basin_contour ? sample_lake_depth_ratio_at_node(p_snapshot, node_x, node_y) : 1.0f;
	const bool spill_node = basin_contour &&
			p_node_index >= 0 &&
			p_node_index < static_cast<int32_t>(p_snapshot.lake_spill_node_mask.size()) &&
			p_snapshot.lake_spill_node_mask[static_cast<size_t>(p_node_index)] != 0U;
	const int32_t cell_size = std::max<int32_t>(1, p_snapshot.cell_size_tiles);
	const int32_t local_x = static_cast<int32_t>(positive_mod(p_world_x, cell_size));
	const int32_t local_y = world_utils::clamp_value(
		static_cast<int32_t>(p_world_y - static_cast<int64_t>(node_y) * cell_size),
		0,
		cell_size - 1
	);
	const int32_t shore_width = world_utils::clamp_value(cell_size / 4, 2, 5);
	auto lake_noise = [&](int32_t p_lake_id) -> float {
		const uint64_t seed = world_utils::mix_seed(
			p_snapshot.seed,
			hydrology_detail_seed_version(p_snapshot.world_version),
			0x3c6ef372fe94f82bULL ^ static_cast<uint64_t>(p_lake_id)
		);
		const float scale = std::max(3.0f, static_cast<float>(cell_size) * 0.42f);
		return signed_value_noise_2d(
			seed,
			static_cast<float>(p_world_x) / scale,
			static_cast<float>(p_world_y) / scale
		);
	};
	auto strength_for_distance = [&](int32_t p_distance) -> uint8_t {
		const float t = 1.0f - world_utils::saturate(
				static_cast<float>(p_distance) / static_cast<float>(std::max(1, shore_width)));
		return static_cast<uint8_t>(world_utils::clamp_value(
			static_cast<int32_t>(std::lround(t * 255.0f)),
			0,
			255
		));
	};

	if (uses_hydrology_visual_v3(p_snapshot.world_version)) {
		const V3LakeSdfSample v3_lake = resolve_v3_lake_sdf_sample(p_snapshot, p_world_x, p_world_y);
		if (v3_lake.lake_id <= 0) {
			return sample;
		}
		sample.lake_id = v3_lake.lake_id;
		if (v3_lake.is_lakebed) {
			sample.is_lakebed = true;
			sample.is_lake_edge = v3_lake.is_contour_band || (spill_node && center_lake_id == v3_lake.lake_id);
			return sample;
		}
		if (v3_lake.is_contour_band) {
			sample.is_shore = true;
			sample.shore_strength = v3_lake.shore_strength;
		}
		return sample;
	}

	if (center_lake_id > 0) {
		sample.lake_id = center_lake_id;
		if (p_organic) {
			float nearest_open_edge_distance = static_cast<float>(cell_size);
			if (north_lake_id != center_lake_id) {
				nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(local_y));
			}
			if (east_lake_id != center_lake_id) {
				nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(cell_size - 1 - local_x));
			}
			if (south_lake_id != center_lake_id) {
				nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(cell_size - 1 - local_y));
			}
			if (west_lake_id != center_lake_id) {
				nearest_open_edge_distance = std::min(nearest_open_edge_distance, static_cast<float>(local_x));
			}
			if (nearest_open_edge_distance < static_cast<float>(cell_size)) {
				const float roughness_tiles = world_utils::clamp_value(static_cast<float>(cell_size) * 0.30f, 2.0f, 6.5f);
				const float lake_start = world_utils::clamp_value(
					static_cast<float>(shore_width) * (basin_contour ? 0.50f + (1.0f - depth_ratio) * 0.42f : 0.65f) +
							(lake_noise(center_lake_id) + 1.0f) * 0.5f * roughness_tiles,
					1.0f,
					static_cast<float>(cell_size) * 0.48f
				);
				if (nearest_open_edge_distance < lake_start) {
					sample.is_shore = true;
					sample.shore_strength = static_cast<uint8_t>(world_utils::clamp_value(
						static_cast<int32_t>(std::lround((1.0f - nearest_open_edge_distance / std::max(1.0f, lake_start)) * 220.0f)),
						32,
						220
					));
					return sample;
				}
				const float contour_edge_width = basin_contour ?
						static_cast<float>(shore_width) * (0.85f + (1.0f - depth_ratio) * 1.25f) :
						static_cast<float>(shore_width);
				sample.is_lake_edge = nearest_open_edge_distance < lake_start + contour_edge_width;
			}
		}
		sample.is_lakebed = true;
		if (basin_contour) {
			sample.is_lake_edge = sample.is_lake_edge || spill_node || depth_ratio < 0.46f;
		}
		if (!p_organic) {
			sample.is_lake_edge =
					(north_lake_id != center_lake_id && local_y < shore_width) ||
					(east_lake_id != center_lake_id && local_x >= cell_size - shore_width) ||
					(south_lake_id != center_lake_id && local_y >= cell_size - shore_width) ||
					(west_lake_id != center_lake_id && local_x < shore_width);
		}
		return sample;
	}

	int32_t best_distance = shore_width + 1;
	auto consider_shore = [&](int32_t p_lake_id, int32_t p_distance) {
		const int32_t effective_shore_width = p_organic && p_lake_id > 0 ?
				world_utils::clamp_value(
					static_cast<int32_t>(std::lround(static_cast<float>(shore_width) + lake_noise(p_lake_id) * 2.0f)),
					1,
					shore_width + 3
				) :
				shore_width;
		if (p_lake_id <= 0 || p_distance >= effective_shore_width || p_distance >= best_distance) {
			return;
		}
		best_distance = p_distance;
		sample.lake_id = p_lake_id;
		sample.is_shore = true;
		sample.shore_strength = strength_for_distance(p_distance);
	};
	consider_shore(north_lake_id, local_y);
	consider_shore(east_lake_id, cell_size - 1 - local_x);
	consider_shore(south_lake_id, cell_size - 1 - local_y);
	consider_shore(west_lake_id, local_x);
	return sample;
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
	if (p_foundation_settings.enabled && uses_hydrology_visual_v3(p_world_version)) {
		p_settings.ocean_band_tiles = p_foundation_settings.ocean_band_tiles;
		p_settings.suppress_ocean_band_mountains = true;
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
	return settings;
}

world_hydrology_prepass::RiverSettings unpack_river_settings(const PackedFloat32Array &p_settings_packed) {
	world_hydrology_prepass::RiverSettings settings;
	settings.enabled = p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_ENABLED] >= 0.5f;
	settings.target_trunk_count = std::max<int32_t>(
		0,
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT]))
	);
	settings.density = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_DENSITY]);
	settings.width_scale = world_utils::clamp_value(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE], 0.25f, 4.0f);
	settings.lake_chance = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE]);
	settings.meander_strength = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH]);
	settings.braid_chance = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE]);
	settings.shallow_crossing_frequency = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY]);
	settings.mountain_clearance_tiles = world_utils::clamp_value(
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES])),
		1,
		16
	);
	settings.delta_scale = world_utils::clamp_value(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE], 0.0f, 2.0f);
	settings.north_drainage_bias = world_utils::saturate(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS]);
	settings.hydrology_cell_size_tiles = world_utils::clamp_value(
		static_cast<int32_t>(std::llround(p_settings_packed[SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES])),
		8,
		64
	);
	return settings;
}

int64_t expected_settings_count_for_version(int64_t p_world_version) {
	if (uses_river_generation(p_world_version)) {
		return SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS;
	}
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
	ClassDB::bind_method(D_METHOD("make_world_preview_patch_image", "packet", "render_mode"), &WorldCore::make_world_preview_patch_image);
	ClassDB::bind_method(D_METHOD("resolve_world_foundation_spawn_tile", "seed", "world_version", "settings_packed"), &WorldCore::resolve_world_foundation_spawn_tile);
	ClassDB::bind_method(D_METHOD("build_world_hydrology_prepass", "seed", "world_version", "settings_packed"), &WorldCore::build_world_hydrology_prepass);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("get_world_foundation_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_foundation_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_foundation_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_foundation_overview, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_world_hydrology_snapshot", "layer_mask", "downscale_factor"), &WorldCore::get_world_hydrology_snapshot);
	ClassDB::bind_method(D_METHOD("get_world_hydrology_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_hydrology_overview, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_world_composite_overview", "layer_mask", "pixels_per_cell"), &WorldCore::get_world_composite_overview, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_world_hydrology_classifier_debug", "seed", "world_version", "settings_packed", "coords"), &WorldCore::get_world_hydrology_classifier_debug);
#endif
}

WorldCore::WorldCore() :
		hierarchical_macro_cache_(std::make_unique<HierarchicalMacroCache>()),
		world_prepass_snapshot_(std::make_unique<world_prepass::Snapshot>()),
		world_hydrology_prepass_snapshot_(std::make_unique<world_hydrology_prepass::Snapshot>()) {}

WorldCore::~WorldCore() = default;

Ref<Image> WorldCore::make_world_preview_patch_image(Dictionary p_packet, StringName p_render_mode) {
	const PreviewPatchMode mode = resolve_preview_patch_mode(p_render_mode);
	const PackedInt32Array terrain_ids = p_packet.get("terrain_ids", PackedInt32Array());
	const PackedInt32Array hydrology_ids = p_packet.get("hydrology_id_per_tile", PackedInt32Array());
	const PackedInt32Array hydrology_flags = p_packet.get("hydrology_flags", PackedInt32Array());
	const PackedByteArray floodplain_strength = p_packet.get("floodplain_strength", PackedByteArray());
	const PackedByteArray water_class = p_packet.get("water_class", PackedByteArray());
	const PackedInt32Array mountain_ids = p_packet.get("mountain_id_per_tile", PackedInt32Array());
	const PackedByteArray mountain_flags = p_packet.get("mountain_flags", PackedByteArray());
	const Rgba8 ground_color = mode == PreviewPatchMode::Terrain ?
			PREVIEW_COLOR_GROUND :
			PREVIEW_COLOR_CLASSIFICATION_GROUND;

	PackedByteArray base_level;
	base_level.resize(static_cast<int32_t>(CELL_COUNT * 4));
	for (int32_t index = 0; index < static_cast<int32_t>(CELL_COUNT); ++index) {
		const Rgba8 color = index < terrain_ids.size() ?
				resolve_preview_patch_color(
					mode,
					read_int32_at(terrain_ids, index),
					read_int32_at(hydrology_ids, index),
					read_int32_at(hydrology_flags, index),
					static_cast<uint8_t>(read_byte_at(floodplain_strength, index)),
					static_cast<uint8_t>(read_byte_at(water_class, index)),
					read_int32_at(mountain_ids, index),
					read_byte_at(mountain_flags, index)
				) :
				PREVIEW_COLOR_UNKNOWN;
		write_rgba8(base_level, index * 4, color);
	}

	std::vector<PackedByteArray> levels;
	levels.reserve(PREVIEW_MIPMAP_LEVELS);
	levels.push_back(base_level);
	int32_t current_width = static_cast<int32_t>(CHUNK_SIZE);
	int32_t current_height = static_cast<int32_t>(CHUNK_SIZE);
	while ((current_width > 1 || current_height > 1) &&
			static_cast<int32_t>(levels.size()) < PREVIEW_MIPMAP_LEVELS) {
		const PackedByteArray next = downsample_preview_mipmap(levels.back(), current_width, current_height, ground_color);
		levels.push_back(next);
		current_width = std::max(1, current_width / 2);
		current_height = std::max(1, current_height / 2);
	}

	PackedByteArray combined_bytes;
	for (const PackedByteArray &level : levels) {
		combined_bytes.append_array(level);
	}
	return Image::create_from_data(
		static_cast<int32_t>(CHUNK_SIZE),
		static_cast<int32_t>(CHUNK_SIZE),
		true,
		Image::FORMAT_RGBA8,
		combined_bytes
	);
}

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
	world_prepass_effective_mountain_settings_ = p_effective_mountain_settings;
	world_prepass_foundation_settings_ = p_foundation_settings;
	return *world_prepass_snapshot_;
}

const world_hydrology_prepass::Snapshot &WorldCore::_get_or_build_world_hydrology_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const world_hydrology_prepass::RiverSettings &p_river_settings,
	bool &r_cache_hit
) {
	const int64_t foundation_world_version = hydrology_detail_seed_version(p_world_version);
	const world_prepass::Snapshot &foundation_snapshot = _get_or_build_world_prepass(
		p_seed,
		foundation_world_version,
		p_mountain_evaluator,
		p_effective_mountain_settings,
		p_foundation_settings
	);
	const uint64_t signature = world_hydrology_prepass::make_signature(
		p_seed,
		p_world_version,
		foundation_snapshot.signature,
		p_foundation_settings,
		p_river_settings
	);
	r_cache_hit = world_hydrology_prepass_snapshot_ != nullptr &&
			world_hydrology_prepass_snapshot_->valid &&
			world_hydrology_prepass_snapshot_->signature == signature;
	if (!r_cache_hit) {
		world_hydrology_prepass_snapshot_ = world_hydrology_prepass::build_snapshot(
			p_seed,
			p_world_version,
			foundation_snapshot,
			p_mountain_evaluator,
			p_foundation_settings,
			p_river_settings
		);
	}
	return *world_hydrology_prepass_snapshot_;
}

Dictionary WorldCore::_generate_chunk_packet(
	int64_t p_seed,
	Vector2i p_coord,
	int64_t p_world_version,
	const mountain_field::Evaluator &p_mountain_evaluator,
	const mountain_field::Settings &p_effective_mountain_settings,
	const FoundationSettings &p_foundation_settings,
	const world_hydrology_prepass::Snapshot *p_hydrology_snapshot,
	const world_hydrology_prepass::RiverSettings *p_river_settings
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
	const bool has_hydrology = p_hydrology_snapshot != nullptr &&
			p_hydrology_snapshot->valid &&
			p_river_settings != nullptr &&
			p_river_settings->enabled;
	PackedInt32Array hydrology_id_per_tile;
	PackedInt32Array hydrology_flags;
	PackedByteArray floodplain_strength;
	PackedByteArray water_class;
	PackedByteArray flow_dir_quantized;
	PackedByteArray stream_order;
	PackedInt32Array water_atlas_indices;
	if (has_hydrology) {
		hydrology_id_per_tile.resize(CELL_COUNT);
		hydrology_flags.resize(CELL_COUNT);
		floodplain_strength.resize(CELL_COUNT);
		water_class.resize(CELL_COUNT);
		flow_dir_quantized.resize(CELL_COUNT);
		stream_order.resize(CELL_COUNT);
		water_atlas_indices.resize(CELL_COUNT);
	}
	const float river_width_scale = has_hydrology ? p_river_settings->width_scale : 1.0f;
	const bool has_v1_r5_hydrology = has_hydrology && uses_delta_generation(p_world_version);
	const bool has_organic_water = has_hydrology && uses_organic_water_generation(p_world_version);
	const bool has_ocean_shore = has_hydrology && uses_ocean_shore_generation(p_world_version);
	const bool has_refined_rivers = has_hydrology && uses_refined_river_generation(p_world_version) &&
			!p_hydrology_snapshot->refined_river_edges.empty();
	const bool has_curvature_rivers = has_refined_rivers && uses_curvature_river_generation(p_world_version);
	const bool has_y_confluence_rivers = has_refined_rivers && uses_y_confluence_river_generation(p_world_version);
	const bool has_braid_loop_rivers = has_refined_rivers && uses_braid_loop_river_generation(p_world_version);
	const bool has_hydrology_clearance_v4 = has_hydrology && uses_hydrology_clearance_v4(p_world_version);
	const bool has_river_discharge_width_v4 = has_hydrology && uses_river_discharge_width_v4(p_world_version);
	const int64_t mountain_clearance_tiles = has_hydrology_clearance_v4 ?
			std::max<int64_t>(1, p_river_settings->mountain_clearance_tiles) :
			0;
	const float max_river_radius = std::max(
		6.0f,
		4.0f + river_width_scale * 4.0f +
				(has_v1_r5_hydrology ? p_river_settings->delta_scale * 10.0f + p_river_settings->braid_chance * 4.0f : 0.0f) +
				(has_refined_rivers ? static_cast<float>(p_hydrology_snapshot->cell_size_tiles) * 0.65f : 0.0f) +
				(has_curvature_rivers ? static_cast<float>(p_hydrology_snapshot->cell_size_tiles) * 0.16f : 0.0f) +
				(has_y_confluence_rivers ? static_cast<float>(p_hydrology_snapshot->cell_size_tiles) * 0.18f : 0.0f) +
				(has_braid_loop_rivers ? static_cast<float>(p_hydrology_snapshot->cell_size_tiles) * 0.16f : 0.0f) +
				(has_river_discharge_width_v4 ? river_width_scale * 4.0f : 0.0f)
	);
	std::vector<RiverRasterEdge> river_edges;
	if (has_hydrology) {
		const int64_t chunk_origin_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE;
		const int64_t chunk_origin_y = clamp_foundation_world_y(static_cast<int64_t>(p_coord.y) * CHUNK_SIZE, p_foundation_settings);
		const float world_width_tiles = static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles));
		if (has_refined_rivers) {
			const std::vector<world_hydrology_prepass::RefinedRiverEdge> refined_edges =
					world_hydrology_prepass::query_refined_river_edges(
						*p_hydrology_snapshot,
						chunk_origin_x,
						chunk_origin_y,
						chunk_origin_x + CHUNK_SIZE - 1,
						chunk_origin_y + CHUNK_SIZE - 1,
						max_river_radius
					);
			river_edges = convert_refined_edges_for_chunk(
				refined_edges,
				static_cast<float>(chunk_origin_x) + static_cast<float>(CHUNK_SIZE) * 0.5f,
				world_width_tiles
			);
		} else {
			const std::vector<RiverRasterEdge> all_edges = build_river_raster_edges(*p_hydrology_snapshot, *p_river_settings);
			river_edges = filter_river_edges_for_chunk(
				all_edges,
				chunk_origin_x,
				chunk_origin_y,
				world_width_tiles,
				max_river_radius
			);
		}
	}

	const mountain_field::Thresholds &mountain_thresholds = p_mountain_evaluator.get_thresholds();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(p_world_version);
	const int64_t mountain_border = std::max<int64_t>(
		1,
		std::max<int64_t>(p_effective_mountain_settings.interior_margin, mountain_clearance_tiles + 1)
	);
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
			const bool suppress_ocean_mountain = is_v3_ocean_mountain_suppression_tile(
				p_world_version,
				world_x,
				world_y,
				p_foundation_settings,
				p_hydrology_snapshot
			);
			if (suppress_ocean_mountain || is_foundation_spawn_safety_area_at_world(world_x, world_y, p_foundation_settings)) {
				elevation = 0.0f;
			}
			mountain_elevations[static_cast<size_t>(sample_index)] = elevation;
			mountain_ids[static_cast<size_t>(sample_index)] = suppress_ocean_mountain ?
					0 :
					resolve_mountain_id_at_world(sample_world_x, world_y, elevation);
		}
	}

	std::vector<int64_t> terrain_id_grid(static_cast<size_t>(mountain_grid_side * mountain_grid_side), TERRAIN_PLAINS_GROUND);
	for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
		for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
			const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
			const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
			const int64_t world_y = clamp_foundation_world_y(
				static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
				p_foundation_settings
			);
			const float elevation = mountain_elevations[static_cast<size_t>(sample_index)];
			const int32_t mountain_id = mountain_ids[static_cast<size_t>(sample_index)];
			int64_t terrain_id = TERRAIN_PLAINS_GROUND;
			if (mountain_id > 0 && elevation >= mountain_thresholds.t_wall) {
				terrain_id = TERRAIN_MOUNTAIN_WALL;
			} else if (mountain_id > 0 && elevation >= mountain_thresholds.t_edge) {
				terrain_id = TERRAIN_MOUNTAIN_FOOT;
			}
			terrain_id_grid[static_cast<size_t>(sample_index)] = terrain_id;
		}
	}

	std::vector<float> mountain_clearance_distance_grid(
		static_cast<size_t>(mountain_grid_side * mountain_grid_side),
		1000000000.0f
	);
	if (has_hydrology_clearance_v4) {
		for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
			for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
				const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
				if (terrain_id_grid[static_cast<size_t>(sample_index)] == TERRAIN_MOUNTAIN_WALL ||
						terrain_id_grid[static_cast<size_t>(sample_index)] == TERRAIN_MOUNTAIN_FOOT) {
					mountain_clearance_distance_grid[static_cast<size_t>(sample_index)] = 0.0f;
					continue;
				}
				float nearest_distance = 1000000000.0f;
				for (int64_t offset_y = -mountain_clearance_tiles; offset_y <= mountain_clearance_tiles; ++offset_y) {
					const int64_t check_y = sample_y + offset_y;
					if (check_y < 0 || check_y >= mountain_grid_side) {
						continue;
					}
					for (int64_t offset_x = -mountain_clearance_tiles; offset_x <= mountain_clearance_tiles; ++offset_x) {
						const int64_t distance_sq = offset_x * offset_x + offset_y * offset_y;
						if (distance_sq > mountain_clearance_tiles * mountain_clearance_tiles) {
							continue;
						}
						const int64_t check_x = sample_x + offset_x;
						if (check_x < 0 || check_x >= mountain_grid_side) {
							continue;
						}
						const int64_t check_index = check_y * mountain_grid_side + check_x;
						if (terrain_id_grid[static_cast<size_t>(check_index)] != TERRAIN_MOUNTAIN_WALL &&
								terrain_id_grid[static_cast<size_t>(check_index)] != TERRAIN_MOUNTAIN_FOOT) {
							continue;
						}
						nearest_distance = std::min(nearest_distance, std::sqrt(static_cast<float>(distance_sq)));
					}
				}
				mountain_clearance_distance_grid[static_cast<size_t>(sample_index)] = nearest_distance;
			}
		}
	}

	std::vector<uint8_t> ground_edge_blocker_grid(static_cast<size_t>(mountain_grid_side * mountain_grid_side), 0U);
	if (has_hydrology) {
		const float world_width_tiles = static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles));
		for (int64_t sample_y = 0; sample_y < mountain_grid_side; ++sample_y) {
			for (int64_t sample_x = 0; sample_x < mountain_grid_side; ++sample_x) {
				const int64_t sample_index = sample_y * mountain_grid_side + sample_x;
				if (terrain_id_grid[static_cast<size_t>(sample_index)] != TERRAIN_PLAINS_GROUND) {
					continue;
				}
				const int64_t world_x = static_cast<int64_t>(p_coord.x) * CHUNK_SIZE + sample_x - mountain_border;
				const int64_t world_y = clamp_foundation_world_y(
					static_cast<int64_t>(p_coord.y) * CHUNK_SIZE + sample_y - mountain_border,
					p_foundation_settings
				);
				bool is_ground_edge_blocker = is_river_ground_edge_blocker(
					river_edges,
					world_x,
					world_y,
					world_width_tiles,
					river_width_scale
				);
				if (!is_ground_edge_blocker) {
					const int32_t hydrology_node_index = sample_hydrology_node_index(
						*p_hydrology_snapshot,
						world_x,
						world_y
					);
					if (hydrology_node_index >= 0) {
						const size_t node_index = static_cast<size_t>(hydrology_node_index);
						if (has_ocean_shore) {
							const OceanRasterSample ocean_sample = sample_ocean_raster(
								*p_hydrology_snapshot,
								hydrology_node_index,
								world_x,
								world_y,
								has_organic_water
							);
							is_ground_edge_blocker = ocean_sample.is_ocean_floor || ocean_sample.is_shore;
						}
						if (!is_ground_edge_blocker && !has_ocean_shore &&
								node_index < p_hydrology_snapshot->ocean_sink_mask.size() &&
								p_hydrology_snapshot->ocean_sink_mask[node_index] != 0U) {
							is_ground_edge_blocker = true;
						}
						if (!is_ground_edge_blocker) {
							const LakeRasterSample lake_sample = sample_lake_raster(
								*p_hydrology_snapshot,
								hydrology_node_index,
								world_x,
								world_y,
								has_organic_water
							);
							is_ground_edge_blocker = lake_sample.is_lakebed || lake_sample.is_shore;
						}
					}
				}
				if (is_ground_edge_blocker) {
					ground_edge_blocker_grid[static_cast<size_t>(sample_index)] = 1U;
				}
			}
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
			int64_t terrain_id = terrain_id_grid[static_cast<size_t>(grid_index)];
			int64_t terrain_atlas_index = 0;
			uint8_t walkable = terrain_id == TERRAIN_MOUNTAIN_WALL || terrain_id == TERRAIN_MOUNTAIN_FOOT ? 0U : 1U;
			int32_t resolved_hydrology_id = 0;
			int32_t resolved_hydrology_flags = 0;
			uint8_t resolved_floodplain_strength = 0U;
			uint8_t resolved_water_class = WATER_CLASS_NONE;
			uint8_t resolved_flow_dir = world_hydrology_prepass::FLOW_DIR_TERMINAL;
			uint8_t resolved_stream_order = 0U;
			int32_t resolved_water_atlas_index = 0;

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

			htc::HydrologyTileInputs classifier_inputs;
			classifier_inputs.base_terrain_id = static_cast<int32_t>(terrain_id);
			classifier_inputs.base_walkable = walkable;
			classifier_inputs.mountain_flags = resolved_mountain_flags;
			classifier_inputs.enforce_mountain_clearance = has_hydrology_clearance_v4;
			classifier_inputs.mountain_clearance_distance_tiles =
					mountain_clearance_distance_grid[static_cast<size_t>(grid_index)];
			classifier_inputs.required_mountain_clearance_tiles = static_cast<float>(mountain_clearance_tiles);
			uint8_t non_terrain_floodplain_strength = 0U;
			const bool hydrology_blocked =
					(resolved_mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) != 0U;
			if (has_hydrology && !hydrology_blocked) {
				const int32_t hydrology_node_index = sample_hydrology_node_index(
					*p_hydrology_snapshot,
					world_x,
					world_y
				);
				if (hydrology_node_index >= 0) {
					const size_t node_index = static_cast<size_t>(hydrology_node_index);
					const bool node_is_ocean = node_index < p_hydrology_snapshot->ocean_sink_mask.size() &&
							p_hydrology_snapshot->ocean_sink_mask[node_index] != 0U;
					const OceanRasterSample ocean_sample = has_ocean_shore ?
							sample_ocean_raster(
								*p_hydrology_snapshot,
								hydrology_node_index,
								world_x,
								world_y,
								has_organic_water
							) :
							OceanRasterSample();
					const bool ocean_raster_applies = has_ocean_shore ?
							(ocean_sample.is_ocean_floor || (node_is_ocean && ocean_sample.is_shore)) :
							node_is_ocean;
					if (ocean_raster_applies) {
						if (has_v1_r5_hydrology) {
							const RiverRasterSample river_sample = sample_river_edges(
								river_edges,
								static_cast<float>(world_x) + 0.5f,
								static_cast<float>(world_y) + 0.5f,
								static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles))
							);
							if (river_sample.segment_id > 0 && river_sample.delta) {
								classifier_inputs.ocean_delta = true;
								classifier_inputs.river_segment_id = river_sample.segment_id;
								classifier_inputs.river_extra_flags =
										(river_sample.braid_split ? HYDROLOGY_FLAG_BRAID_SPLIT : 0);
								classifier_inputs.river_flow_dir = river_sample.flow_dir;
								classifier_inputs.river_stream_order = static_cast<uint8_t>(world_utils::clamp_value(
									static_cast<int32_t>(river_sample.stream_order),
									1,
									255
								));
							}
						}
						if (!classifier_inputs.ocean_delta) {
							classifier_inputs.ocean_shore = has_ocean_shore && ocean_sample.is_shore;
							classifier_inputs.ocean_floor = !classifier_inputs.ocean_shore;
							classifier_inputs.ocean_shallow_shelf = ocean_sample.is_shallow_shelf;
							classifier_inputs.ocean_uses_stable_id = has_ocean_shore;
							classifier_inputs.ocean_shore_strength = ocean_sample.shore_strength;
						}
					} else {
						const LakeRasterSample lake_sample = sample_lake_raster(
							*p_hydrology_snapshot,
							hydrology_node_index,
							world_x,
							world_y,
							has_organic_water
						);
						if (lake_sample.is_lakebed) {
							bool shallow_edge = lake_sample.is_lake_edge;
							RiverRasterSample lake_river_sample;
							const bool lake_river_shore =
									!shallow_edge &&
									uses_lake_basin_continuity_v4(p_world_version) &&
									lake_basin_continuity_river_shore_applies(
										river_edges,
										world_x,
										world_y,
										static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles)),
										river_width_scale,
										&lake_river_sample
									);
							if (lake_river_shore) {
								shallow_edge = true;
							}
							classifier_inputs.lakebed = true;
							classifier_inputs.lake_edge = shallow_edge;
							classifier_inputs.lake_id = lake_sample.lake_id;
							classifier_inputs.lake_flow_dir = lake_river_shore ?
									lake_river_sample.flow_dir :
									(node_index < p_hydrology_snapshot->flow_dir.size() ?
									p_hydrology_snapshot->flow_dir[node_index] :
									world_hydrology_prepass::FLOW_DIR_TERMINAL);
							const uint8_t node_lake_stream_order = node_index < p_hydrology_snapshot->river_stream_order.size() ?
									p_hydrology_snapshot->river_stream_order[node_index] :
									0U;
							classifier_inputs.lake_stream_order = lake_river_shore ?
									std::max<uint8_t>(node_lake_stream_order, lake_river_sample.stream_order) :
									node_lake_stream_order;
						} else {
							const RiverRasterSample river_sample = sample_river_edges(
								river_edges,
								static_cast<float>(world_x) + 0.5f,
								static_cast<float>(world_y) + 0.5f,
								static_cast<float>(std::max<int64_t>(1, p_hydrology_snapshot->width_tiles))
							);
							bool river_applied = false;
							if (river_sample.segment_id > 0) {
								const float order_f = std::max(1.0f, static_cast<float>(river_sample.stream_order));
								const RiverChannelRadii radii = resolve_river_channel_radii(river_sample, river_width_scale);
								const int32_t river_extra_flags =
										(river_sample.source ? HYDROLOGY_FLAG_SOURCE : 0) |
										(river_sample.delta ? HYDROLOGY_FLAG_DELTA : 0) |
										(river_sample.braid_split ? HYDROLOGY_FLAG_BRAID_SPLIT : 0) |
										(river_sample.confluence ? HYDROLOGY_FLAG_CONFLUENCE : 0);
								if (river_sample.distance <= radii.bed_radius) {
									bool shallow_crossing = false;
									if (river_sample.discharge_width_profile) {
										shallow_crossing = river_sample.ford_narrowing >= 0.16f;
									} else {
										const uint64_t crossing_noise = splitmix64(
											static_cast<uint64_t>(p_seed) ^
											(static_cast<uint64_t>(river_sample.segment_id) << 32U) ^
											static_cast<uint64_t>(world_x * 73856093LL) ^
											static_cast<uint64_t>(world_y * 19349663LL)
										);
										const float crossing_threshold = world_utils::saturate(
											p_river_settings->shallow_crossing_frequency
										) * 0.18f;
										shallow_crossing =
												static_cast<float>(crossing_noise & 1023ULL) / 1023.0f < crossing_threshold;
									}
									const bool deep_water = order_f >= 4.0f &&
											resolve_curvature_thalweg_distance(river_sample, radii.deep_radius) <=
													radii.deep_radius * (1.0f + std::abs(river_sample.curvature) * 0.12f) &&
											!shallow_crossing;
									classifier_inputs.riverbed = true;
									classifier_inputs.river_deep = deep_water;
									classifier_inputs.river_segment_id = river_sample.segment_id;
									classifier_inputs.river_extra_flags = river_extra_flags;
									classifier_inputs.river_flow_dir = river_sample.flow_dir;
									classifier_inputs.river_stream_order = static_cast<uint8_t>(world_utils::clamp_value(
										static_cast<int32_t>(river_sample.stream_order),
										1,
										255
									));
									river_applied = true;
								} else if (river_sample.distance <= radii.bank_radius) {
									classifier_inputs.river_bank = true;
									classifier_inputs.river_segment_id = river_sample.segment_id;
									classifier_inputs.river_extra_flags = river_extra_flags;
									classifier_inputs.river_flow_dir = river_sample.flow_dir;
									classifier_inputs.river_stream_order = static_cast<uint8_t>(world_utils::clamp_value(
										static_cast<int32_t>(river_sample.stream_order),
										1,
										255
									));
									const float bank_t = 1.0f - world_utils::saturate(
										(river_sample.distance - radii.bed_radius) / std::max(0.01f, radii.bank_radius - radii.bed_radius)
									);
									classifier_inputs.river_bank_strength = static_cast<uint8_t>(world_utils::clamp_value(
										static_cast<int32_t>(std::lround(bank_t * 255.0f)),
										0,
										255
									));
									river_applied = true;
								}
							}
							if (!river_applied && lake_sample.is_shore) {
								classifier_inputs.lake_shore = true;
								classifier_inputs.lake_id = lake_sample.lake_id;
								classifier_inputs.lake_shore_strength = lake_sample.shore_strength;
							} else if (!river_applied && has_ocean_shore && ocean_sample.is_shore) {
								classifier_inputs.ocean_shore = true;
								classifier_inputs.ocean_shore_strength = ocean_sample.shore_strength;
							} else if (!river_applied && node_index < p_hydrology_snapshot->floodplain_potential.size()) {
								if (uses_hydrology_visual_v3(p_world_version)) {
									const float floodplain = sample_hydrology_float_bilinear(
										*p_hydrology_snapshot,
										p_hydrology_snapshot->floodplain_potential,
										world_x,
										world_y,
										0.0f
									);
									non_terrain_floodplain_strength = resolve_v3_floodplain_strength_byte(floodplain);
									if (non_terrain_floodplain_strength >= 96U) {
										classifier_inputs.floodplain = true;
										classifier_inputs.floodplain_strength = non_terrain_floodplain_strength;
										classifier_inputs.floodplain_flags = HYDROLOGY_FLAG_FLOODPLAIN |
												(non_terrain_floodplain_strength >= 192U ?
												 HYDROLOGY_FLAG_FLOODPLAIN_NEAR :
												 HYDROLOGY_FLAG_FLOODPLAIN_FAR);
									}
								} else {
									const float floodplain = p_hydrology_snapshot->floodplain_potential[node_index];
									if (floodplain > 0.62f) {
										classifier_inputs.floodplain = true;
										classifier_inputs.floodplain_flags = HYDROLOGY_FLAG_FLOODPLAIN;
										classifier_inputs.floodplain_strength = static_cast<uint8_t>(world_utils::clamp_value(
											static_cast<int32_t>(std::lround(floodplain * 255.0f)),
											0,
											255
										));
									}
								}
							}
						}
					}
				}
			}
			const htc::HydrologyTileDecision tile_decision = htc::classify_tile(classifier_inputs);
			terrain_id = tile_decision.terrain_id;
			walkable = tile_decision.walkable;
			resolved_hydrology_id = tile_decision.hydrology_id;
			resolved_hydrology_flags = tile_decision.hydrology_flags;
			resolved_floodplain_strength = tile_decision.floodplain_strength != 0U ?
					tile_decision.floodplain_strength :
					non_terrain_floodplain_strength;
			resolved_water_class = tile_decision.water_class;
			resolved_flow_dir = tile_decision.flow_dir;
			resolved_stream_order = tile_decision.stream_order;
			resolved_water_atlas_index = tile_decision.water_atlas_index;
			if (tile_decision.winner != htc::HydroTileWinner::Ground &&
					!htc::is_mountain_winner(tile_decision.winner)) {
				terrain_atlas_index = 0;
			}

			if (terrain_id == TERRAIN_PLAINS_GROUND) {
				const auto is_ground_edge_open = [&](int64_t p_offset_x, int64_t p_offset_y) -> bool {
					const int64_t sample_index = (grid_y + p_offset_y) * mountain_grid_side + (grid_x + p_offset_x);
					return ground_edge_blocker_grid[static_cast<size_t>(sample_index)] != 0U;
				};
				terrain_atlas_index = resolve_base_ground_atlas_index(
					world_x,
					world_y,
					p_seed,
					!is_ground_edge_open(0, -1),
					!is_ground_edge_open(1, -1),
					!is_ground_edge_open(1, 0),
					!is_ground_edge_open(1, 1),
					!is_ground_edge_open(0, 1),
					!is_ground_edge_open(-1, 1),
					!is_ground_edge_open(-1, 0),
					!is_ground_edge_open(-1, -1)
				);
			}

			terrain_ids.set(index, terrain_id);
			terrain_atlas_indices.set(index, terrain_atlas_index);
			walkable_flags.set(index, walkable);
			mountain_id_per_tile.set(index, resolved_mountain_id);
			mountain_flags.set(index, resolved_mountain_flags);
			mountain_atlas_indices.set(index, resolved_mountain_atlas_index);
			if (has_hydrology) {
				hydrology_id_per_tile.set(index, resolved_hydrology_id);
				hydrology_flags.set(index, resolved_hydrology_flags);
				floodplain_strength.set(index, resolved_floodplain_strength);
				water_class.set(index, resolved_water_class);
				flow_dir_quantized.set(index, resolved_flow_dir);
				stream_order.set(index, resolved_stream_order);
				water_atlas_indices.set(index, resolved_water_atlas_index);
			}
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
	if (has_hydrology) {
		packet["hydrology_id_per_tile"] = hydrology_id_per_tile;
		packet["hydrology_flags"] = hydrology_flags;
		packet["floodplain_strength"] = floodplain_strength;
		packet["water_class"] = water_class;
		packet["flow_dir_quantized"] = flow_dir_quantized;
		packet["stream_order"] = stream_order;
		packet["water_atlas_indices"] = water_atlas_indices;
	}
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

	const int64_t shape_world_version = world_shape_seed_version(p_world_version);
	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		shape_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	if (!foundation_settings.enabled) {
		return make_failure_result("World foundation settings are disabled.");
	}

	const mountain_field::Evaluator mountain_evaluator(p_seed, shape_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const world_prepass::Snapshot &snapshot = _get_or_build_world_prepass(
		p_seed,
		shape_world_version,
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

Dictionary WorldCore::build_world_hydrology_prepass(
	int64_t p_seed,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed
) {
	if (p_world_version < WORLD_FOUNDATION_VERSION) {
		return make_failure_result("World hydrology prepass requires world foundation version.");
	}
	if (p_settings_packed.size() != SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS) {
		return make_failure_result("World hydrology prepass received an invalid settings payload size.");
	}
	if (!mountain_field::uses_hierarchical_labeling(p_world_version)) {
		return make_failure_result("World hydrology prepass requires hierarchical mountain labeling.");
	}

	const int64_t shape_world_version = world_shape_seed_version(p_world_version);
	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const world_hydrology_prepass::RiverSettings river_settings = unpack_river_settings(p_settings_packed);
	if (!foundation_settings.enabled) {
		return make_failure_result("World foundation settings are disabled.");
	}
	if (!river_settings.enabled) {
		return make_failure_result("River settings are disabled.");
	}

	const mountain_field::Evaluator mountain_evaluator(p_seed, shape_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	bool cache_hit = false;
	const world_hydrology_prepass::Snapshot &snapshot = _get_or_build_world_hydrology_prepass(
		p_seed,
		p_world_version,
		mountain_evaluator,
		effective_mountain_settings,
		foundation_settings,
		river_settings,
		cache_hit
	);
	return world_hydrology_prepass::make_build_result(snapshot, cache_hit);
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
	const mountain_field::Evaluator mountain_evaluator(
		world_prepass_snapshot_->seed,
		world_prepass_snapshot_->world_version,
		world_prepass_effective_mountain_settings_
	);
	return world_prepass::make_overview_image(
		*world_prepass_snapshot_,
		mountain_evaluator,
		world_prepass_snapshot_->world_version,
		world_prepass_foundation_settings_,
		p_layer_mask,
		p_pixels_per_cell
	);
}

Dictionary WorldCore::get_world_hydrology_snapshot(int64_t p_layer_mask, int64_t p_downscale_factor) {
	if (world_hydrology_prepass_snapshot_ == nullptr || !world_hydrology_prepass_snapshot_->valid) {
		return Dictionary();
	}
	return world_hydrology_prepass::make_debug_snapshot(*world_hydrology_prepass_snapshot_, p_layer_mask, p_downscale_factor);
}

Ref<Image> WorldCore::get_world_hydrology_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (world_hydrology_prepass_snapshot_ == nullptr || !world_hydrology_prepass_snapshot_->valid) {
		return Ref<Image>();
	}
	return world_hydrology_prepass::make_overview_image(
		*world_hydrology_prepass_snapshot_,
		p_layer_mask,
		p_pixels_per_cell
	);
}

Ref<Image> WorldCore::get_world_composite_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell) {
	if (world_prepass_snapshot_ == nullptr || !world_prepass_snapshot_->valid ||
			world_hydrology_prepass_snapshot_ == nullptr || !world_hydrology_prepass_snapshot_->valid) {
		return Ref<Image>();
	}
	const mountain_field::Evaluator mountain_evaluator(
		world_prepass_snapshot_->seed,
		world_prepass_snapshot_->world_version,
		world_prepass_effective_mountain_settings_
	);
	const int64_t foundation_layer_mask = p_layer_mask & ~HYDROLOGY_TRANSPARENT_OVERLAY_LAYER_MASK;
	const Ref<Image> foundation_image = world_prepass::make_overview_image(
		*world_prepass_snapshot_,
		mountain_evaluator,
		world_prepass_snapshot_->world_version,
		world_prepass_foundation_settings_,
		foundation_layer_mask,
		p_pixels_per_cell
	);
	const int32_t hydrology_pixels_per_cell = foundation_image.is_valid() && world_hydrology_prepass_snapshot_->grid_width > 0 ?
			world_utils::clamp_value(
				static_cast<int32_t>(std::lround(
					static_cast<double>(std::max(1, foundation_image->get_width())) /
					static_cast<double>(world_hydrology_prepass_snapshot_->grid_width)
				)),
				1,
				8
			) :
			world_utils::clamp_value(static_cast<int32_t>(p_pixels_per_cell), 1, 8);
	const Ref<Image> hydrology_overlay = world_hydrology_prepass::make_overview_image(
		*world_hydrology_prepass_snapshot_,
		HYDROLOGY_TRANSPARENT_OVERLAY_LAYER_MASK,
		hydrology_pixels_per_cell
	);
	const PackedByteArray foundation_mountain_mask = make_foundation_mountain_render_mask(foundation_image);
	return blend_overview_images(foundation_image, hydrology_overlay, foundation_mountain_mask);
}

Dictionary WorldCore::get_world_hydrology_classifier_debug(
	int64_t p_seed,
	int64_t p_world_version,
	PackedFloat32Array p_settings_packed,
	PackedVector2Array p_coords
) {
	Dictionary result;
	result["success"] = false;
	result["world_version"] = p_world_version;
	result["sampled_tile_count"] = 0;
	result["overview_chunk_layer_mismatch_count"] = 0;
	result["preview_chunk_layer_mismatch_count"] = 0;
	result["overview_preview_chunk_layer_mismatch_count"] = 0;
	if (p_coords.is_empty()) {
		result["message"] = "No classifier debug coordinates supplied.";
		return result;
	}
	const Dictionary build_result = build_world_hydrology_prepass(p_seed, p_world_version, p_settings_packed);
	if (!static_cast<bool>(build_result.get("success", false))) {
		result["message"] = "Hydrology prepass build failed for classifier debug.";
		return result;
	}
	Array packets = generate_chunk_packets_batch(p_seed, p_coords, p_world_version, p_settings_packed);
	if (packets.size() != p_coords.size()) {
		result["message"] = "Chunk packet generation returned an unexpected packet count.";
		return result;
	}
	int32_t sampled_tile_count = 0;
	int32_t overview_chunk_mismatches = 0;
	int32_t preview_chunk_mismatches = 0;
	int32_t overview_preview_chunk_mismatches = 0;
	int32_t overview_sampled_tile_count = 0;
	Dictionary first_overview_mismatch;
	Dictionary first_preview_mismatch;
	const int32_t overview_pixels_per_cell = 2;
	const Ref<Image> overview_image = get_world_hydrology_overview(HYDROLOGY_LAYER_WINNER_LAYER_MASK, overview_pixels_per_cell);
	const bool has_overview_image =
			overview_image.is_valid() &&
			world_hydrology_prepass_snapshot_ != nullptr &&
			world_hydrology_prepass_snapshot_->valid &&
			overview_image->get_width() == world_hydrology_prepass_snapshot_->grid_width * overview_pixels_per_cell &&
			overview_image->get_height() == world_hydrology_prepass_snapshot_->grid_height * overview_pixels_per_cell;
	const PackedByteArray overview_bytes = has_overview_image ?
			overview_image->get_data() :
			PackedByteArray();
	for (int32_t packet_index = 0; packet_index < packets.size(); ++packet_index) {
		const Dictionary packet = packets[packet_index];
		const Ref<Image> preview_image = make_world_preview_patch_image(packet, StringName("terrain"));
		if (preview_image.is_null() || preview_image->get_width() <= 0 || preview_image->get_height() <= 0) {
			result["message"] = "Preview patch image generation failed for classifier debug.";
			return result;
		}
		const PackedByteArray preview_bytes = preview_image->get_data();
		const PackedInt32Array terrain_ids = packet.get("terrain_ids", PackedInt32Array());
		const PackedInt32Array hydrology_ids = packet.get("hydrology_id_per_tile", PackedInt32Array());
		const PackedInt32Array hydrology_flags = packet.get("hydrology_flags", PackedInt32Array());
		const PackedByteArray floodplain_strength = packet.get("floodplain_strength", PackedByteArray());
		const PackedByteArray water_class = packet.get("water_class", PackedByteArray());
		const PackedByteArray mountain_flags = packet.get("mountain_flags", PackedByteArray());
		const Vector2 chunk_coord = p_coords[packet_index];
		const int64_t chunk_origin_x = static_cast<int64_t>(chunk_coord.x) * CHUNK_SIZE;
		const int64_t chunk_origin_y = static_cast<int64_t>(chunk_coord.y) * CHUNK_SIZE;
		const int32_t count = std::min<int32_t>(
			static_cast<int32_t>(CELL_COUNT),
			std::min<int32_t>(
				terrain_ids.size(),
				std::min<int32_t>(mountain_flags.size(), water_class.size() > 0 ? water_class.size() : terrain_ids.size())
			)
		);
		for (int32_t tile_index = 0; tile_index < count; ++tile_index) {
			const int32_t hydrology_id = tile_index < hydrology_ids.size() ? hydrology_ids[tile_index] : 0;
			const int32_t flags = tile_index < hydrology_flags.size() ? hydrology_flags[tile_index] : 0;
			const uint8_t current_floodplain_strength = tile_index < floodplain_strength.size() ?
					floodplain_strength[tile_index] :
					0U;
			const uint8_t current_water_class = tile_index < water_class.size() ? water_class[tile_index] : WATER_CLASS_NONE;
			const uint8_t current_mountain_flags = tile_index < mountain_flags.size() ? mountain_flags[tile_index] : 0U;
			const htc::HydroTileWinner chunk_winner = htc::winner_from_packet(
				terrain_ids[tile_index],
				hydrology_id,
				flags,
				current_water_class,
				current_mountain_flags
			);
			const Rgba8 expected_preview_color = resolve_preview_winner_color(
				chunk_winner,
				chunk_winner == htc::HydroTileWinner::Floodplain ?
						resolve_preview_floodplain_strength(terrain_ids[tile_index], flags, current_floodplain_strength) :
						0U
			);
			const Rgba8 actual_preview_color = read_rgba8(preview_bytes, tile_index * 4);
			const bool preview_matches_chunk = rgba8_equal(actual_preview_color, expected_preview_color);
			if (!preview_matches_chunk) {
				if (first_preview_mismatch.is_empty()) {
					first_preview_mismatch["packet_index"] = packet_index;
					first_preview_mismatch["tile_index"] = tile_index;
					first_preview_mismatch["winner_code"] = htc::winner_code(chunk_winner);
				}
				preview_chunk_mismatches += 1;
			}

			bool overview_matches_chunk = true;
			if (has_overview_image && world_hydrology_prepass_snapshot_->cell_size_tiles > 0) {
				const int32_t local_x = tile_index % static_cast<int32_t>(CHUNK_SIZE);
				const int32_t local_y = tile_index / static_cast<int32_t>(CHUNK_SIZE);
				const int64_t world_x = chunk_origin_x + local_x;
				const int64_t world_y = world_utils::clamp_value(
					chunk_origin_y + local_y,
					0LL,
					std::max<int64_t>(0, world_hydrology_prepass_snapshot_->height_tiles - 1)
				);
				const int32_t cell_size = world_hydrology_prepass_snapshot_->cell_size_tiles;
				const int32_t cell_local_x = static_cast<int32_t>(positive_mod(world_x, cell_size));
				const int32_t cell_local_y = static_cast<int32_t>(positive_mod(world_y, cell_size));
				const int32_t pixel_x_in_cell = world_utils::clamp_value(
					(cell_local_x * overview_pixels_per_cell) / cell_size,
					0,
					overview_pixels_per_cell - 1
				);
				const int32_t pixel_y_in_cell = world_utils::clamp_value(
					(cell_local_y * overview_pixels_per_cell) / cell_size,
					0,
					overview_pixels_per_cell - 1
				);
				const int32_t pixel_center_x = static_cast<int32_t>(std::floor(
					(static_cast<float>(pixel_x_in_cell) + 0.5f) *
					static_cast<float>(cell_size) /
					static_cast<float>(overview_pixels_per_cell)
				));
				const int32_t pixel_center_y = static_cast<int32_t>(std::floor(
					(static_cast<float>(pixel_y_in_cell) + 0.5f) *
					static_cast<float>(cell_size) /
					static_cast<float>(overview_pixels_per_cell)
				));
				const bool is_overview_pixel_center =
						cell_local_x == pixel_center_x &&
						cell_local_y == pixel_center_y;
				if (is_overview_pixel_center) {
					const int32_t node_x = static_cast<int32_t>(positive_mod(world_x / cell_size, world_hydrology_prepass_snapshot_->grid_width));
					const int32_t node_y = world_utils::clamp_value(
						static_cast<int32_t>(world_y / cell_size),
						0,
						world_hydrology_prepass_snapshot_->grid_height - 1
					);
					const int32_t overview_width = overview_image->get_width();
					const int32_t overview_pixel_offset = (
						(node_y * overview_pixels_per_cell + pixel_y_in_cell) * overview_width +
						(node_x * overview_pixels_per_cell + pixel_x_in_cell)
					) * 4;
					if (overview_pixel_offset >= 0 && overview_pixel_offset + 3 < overview_bytes.size()) {
						const Rgba8 expected_overview_color = to_rgba8(htc::debug_winner_color(chunk_winner));
						const Rgba8 actual_overview_color = read_rgba8(overview_bytes, overview_pixel_offset);
						const htc::HydroTileWinner overview_winner = htc::winner_from_debug_color({
							actual_overview_color.r,
							actual_overview_color.g,
							actual_overview_color.b,
							actual_overview_color.a
						});
						const int32_t chunk_family = htc::winner_family_code(chunk_winner);
						const int32_t overview_family = htc::winner_family_code(overview_winner);
						const int32_t snapshot_index = world_hydrology_prepass_snapshot_->index(node_x, node_y);
						const int32_t snapshot_lake_id = world_hydrology_prepass_snapshot_->lake_id.size() > static_cast<size_t>(snapshot_index) ?
								world_hydrology_prepass_snapshot_->lake_id[static_cast<size_t>(snapshot_index)] :
								0;
						const bool hydrology_relevant =
								chunk_family >= 2 ||
								overview_family >= 2;
						const bool v4_closure_debug_agreement =
								p_world_version >= mountain_field::WORLD_HYDROLOGY_V4_CLOSURE_VERSION;
						const bool delta_ocean_river_hybrid =
								v4_closure_debug_agreement &&
								(flags & HYDROLOGY_FLAG_DELTA) != 0 &&
								((chunk_family == 2 && overview_family == 4) ||
										(chunk_family == 4 && overview_family == 2));
						const bool coastal_river_bank_hybrid =
								v4_closure_debug_agreement &&
								hydrology_id > 0 &&
								(flags & HYDROLOGY_FLAG_BANK) != 0 &&
								((chunk_family == 2 && overview_family == 4) ||
										(chunk_family == 4 && overview_family == 2));
						const bool lake_river_bank_hybrid =
								v4_closure_debug_agreement &&
								hydrology_id >= HYDROLOGY_LAKE_ID_OFFSET &&
								(flags & HYDROLOGY_FLAG_BANK) != 0 &&
								((chunk_family == 3 && overview_family == 4) ||
										(chunk_family == 4 && overview_family == 3));
						const bool lake_boundary_overview_only =
								v4_closure_debug_agreement &&
								chunk_family == 0 &&
								overview_family == 3;
						overview_matches_chunk = !hydrology_relevant || chunk_family == overview_family ||
								delta_ocean_river_hybrid || coastal_river_bank_hybrid ||
								lake_river_bank_hybrid || lake_boundary_overview_only;
						if (!overview_matches_chunk && first_overview_mismatch.is_empty()) {
							first_overview_mismatch["packet_index"] = packet_index;
							first_overview_mismatch["tile_index"] = tile_index;
							first_overview_mismatch["node_x"] = node_x;
							first_overview_mismatch["node_y"] = node_y;
							first_overview_mismatch["world_x"] = world_x;
							first_overview_mismatch["world_y"] = world_y;
							first_overview_mismatch["terrain_id"] = terrain_ids[tile_index];
							first_overview_mismatch["water_class"] = current_water_class;
							first_overview_mismatch["hydrology_id"] = hydrology_id;
							first_overview_mismatch["hydrology_flags"] = flags;
							first_overview_mismatch["winner_code"] = htc::winner_code(chunk_winner);
							first_overview_mismatch["overview_winner_code"] = htc::winner_code(overview_winner);
							first_overview_mismatch["winner_family_code"] = chunk_family;
							first_overview_mismatch["overview_winner_family_code"] = overview_family;
							first_overview_mismatch["snapshot_river_node"] =
									world_hydrology_prepass_snapshot_->river_node_mask.size() > static_cast<size_t>(snapshot_index) ?
									world_hydrology_prepass_snapshot_->river_node_mask[static_cast<size_t>(snapshot_index)] :
									0;
							first_overview_mismatch["snapshot_lake_id"] =
									snapshot_lake_id;
							first_overview_mismatch["snapshot_ocean_node"] =
									world_hydrology_prepass_snapshot_->ocean_sink_mask.size() > static_cast<size_t>(snapshot_index) ?
									world_hydrology_prepass_snapshot_->ocean_sink_mask[static_cast<size_t>(snapshot_index)] :
									0;
							first_overview_mismatch["actual_r"] = actual_overview_color.r;
							first_overview_mismatch["actual_g"] = actual_overview_color.g;
							first_overview_mismatch["actual_b"] = actual_overview_color.b;
							first_overview_mismatch["expected_r"] = expected_overview_color.r;
							first_overview_mismatch["expected_g"] = expected_overview_color.g;
							first_overview_mismatch["expected_b"] = expected_overview_color.b;
						}
						overview_sampled_tile_count += 1;
					}
				}
			}
			if (!overview_matches_chunk) {
				overview_chunk_mismatches += 1;
			}
			if (!overview_matches_chunk || !preview_matches_chunk) {
				overview_preview_chunk_mismatches += 1;
			}
			sampled_tile_count += 1;
		}
	}
	result["success"] = true;
	result["sampled_tile_count"] = sampled_tile_count;
	result["overview_chunk_layer_mismatch_count"] = overview_chunk_mismatches;
	result["preview_chunk_layer_mismatch_count"] = preview_chunk_mismatches;
	result["overview_preview_chunk_layer_mismatch_count"] = overview_preview_chunk_mismatches;
	result["overview_sampled_tile_count"] = overview_sampled_tile_count;
	result["first_overview_mismatch"] = first_overview_mismatch;
	result["first_preview_mismatch"] = first_preview_mismatch;
	if (world_hydrology_prepass_snapshot_ != nullptr && world_hydrology_prepass_snapshot_->valid) {
		result["mountain_clearance_blocked_node_count"] = world_hydrology_prepass_snapshot_->mountain_clearance_blocked_node_count;
		result["mountain_water_overlap_tile_count"] = world_hydrology_prepass_snapshot_->mountain_water_overlap_tile_count;
		result["river_tiles_adjacent_to_mountain_count"] = world_hydrology_prepass_snapshot_->river_tiles_adjacent_to_mountain_count;
		result["lake_tiles_adjacent_to_mountain_count"] = world_hydrology_prepass_snapshot_->lake_tiles_adjacent_to_mountain_count;
		result["river_mouths_without_terminal_widening_count"] = world_hydrology_prepass_snapshot_->river_mouths_without_terminal_widening_count;
		result["rivers_with_cut_endpoint_count"] = world_hydrology_prepass_snapshot_->rivers_with_cut_endpoint_count;
		result["overview_runtime_classifier_mismatch_count"] = overview_chunk_mismatches;
		result["river_width_profile_edge_count"] = world_hydrology_prepass_snapshot_->river_width_profile_edge_count;
		result["river_source_taper_edge_count"] = world_hydrology_prepass_snapshot_->river_source_taper_edge_count;
		result["river_terminal_expansion_edge_count"] = world_hydrology_prepass_snapshot_->river_terminal_expansion_edge_count;
		result["river_confluence_width_profile_edge_count"] = world_hydrology_prepass_snapshot_->river_confluence_width_profile_edge_count;
		result["river_ford_narrowing_edge_count"] = world_hydrology_prepass_snapshot_->river_ford_narrowing_edge_count;
	}
	return result;
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

	const int64_t shape_world_version = world_shape_seed_version(p_world_version);
	const FoundationSettings foundation_settings = unpack_foundation_settings(p_world_version, p_settings_packed);
	const mountain_field::Settings mountain_settings = make_effective_mountain_settings(
		p_world_version,
		unpack_mountain_settings(p_settings_packed),
		foundation_settings
	);
	const mountain_field::Evaluator mountain_evaluator(p_seed, shape_world_version, mountain_settings);
	const mountain_field::Settings &effective_mountain_settings = mountain_evaluator.get_settings();
	const int32_t macro_cell_size = mountain_field::get_hierarchical_macro_cell_size(shape_world_version);
	world_hydrology_prepass::RiverSettings river_settings;
	const world_hydrology_prepass::Snapshot *hydrology_snapshot = nullptr;
	if (uses_river_generation(p_world_version)) {
		river_settings = unpack_river_settings(p_settings_packed);
		ERR_FAIL_COND_V_MSG(
			!foundation_settings.enabled,
			Array{},
			"WorldCore.generate_chunk_packets_batch requires world foundation settings for river generation."
		);
		ERR_FAIL_COND_V_MSG(
			!river_settings.enabled,
			Array{},
			"WorldCore.generate_chunk_packets_batch requires enabled river settings for river generation."
		);
		bool hydrology_cache_hit = false;
		hydrology_snapshot = &_get_or_build_world_hydrology_prepass(
			p_seed,
			p_world_version,
			mountain_evaluator,
			effective_mountain_settings,
			foundation_settings,
			river_settings,
			hydrology_cache_hit
		);
		ERR_FAIL_COND_V_MSG(
			hydrology_snapshot == nullptr || !hydrology_snapshot->valid,
			Array{},
			"WorldCore.generate_chunk_packets_batch failed to build world hydrology prepass."
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
				foundation_settings,
				hydrology_snapshot,
				uses_river_generation(p_world_version) ? &river_settings : nullptr
			);
		}
	}
	return packets;
}
