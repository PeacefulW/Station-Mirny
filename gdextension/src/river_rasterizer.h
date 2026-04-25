#ifndef STATION_MIRNY_RIVER_RASTERIZER_H
#define STATION_MIRNY_RIVER_RASTERIZER_H

#include "world_prepass.h"

#include <cstdint>
#include <vector>

namespace river_rasterizer {

constexpr int64_t RIVER_GENERATION_VERSION = 15;

constexpr uint8_t FLAG_RIVERBED = 1U << 0U;
constexpr uint8_t FLAG_LAKEBED = 1U << 1U;
constexpr uint8_t FLAG_OCEAN_DIRECTED = 1U << 2U;
constexpr uint8_t FLAG_SIDE_CHANNEL = 1U << 3U;
constexpr uint8_t FLAG_MOUTH_OR_DELTA = 1U << 4U;
constexpr uint8_t FLAG_DEBUG_ORPHAN = 1U << 5U;

constexpr uint8_t DEPTH_NONE = 0U;
constexpr uint8_t DEPTH_SHALLOW = 1U;
constexpr uint8_t DEPTH_DEEP = 2U;

struct RasterizedRegion {
	int32_t width = 0;
	int32_t height = 0;
	std::vector<uint8_t> flags;
	std::vector<uint8_t> depth;

	bool is_valid() const;
	int32_t index(int32_t p_x, int32_t p_y) const;
};

bool is_enabled_for_version(int64_t p_world_version);

RasterizedRegion rasterize_region(
	const world_prepass::Snapshot &p_snapshot,
	int64_t p_seed,
	int64_t p_world_version,
	const FoundationSettings &p_foundation_settings,
	int64_t p_origin_world_x,
	int64_t p_origin_world_y,
	int32_t p_width,
	int32_t p_height
);

} // namespace river_rasterizer

#endif
