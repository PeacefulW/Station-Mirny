#ifndef STATION_MIRNY_HYDROLOGY_TILE_CLASSIFIER_H
#define STATION_MIRNY_HYDROLOGY_TILE_CLASSIFIER_H

#include <cstdint>

namespace hydrology_tile_classifier {

constexpr int32_t TERRAIN_PLAINS_GROUND = 0;
constexpr int32_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int32_t TERRAIN_MOUNTAIN_FOOT = 4;
constexpr int32_t TERRAIN_RIVERBED_SHALLOW = 5;
constexpr int32_t TERRAIN_RIVERBED_DEEP = 6;
constexpr int32_t TERRAIN_LAKEBED = 7;
constexpr int32_t TERRAIN_OCEAN_FLOOR = 8;
constexpr int32_t TERRAIN_SHORE = 9;
constexpr int32_t TERRAIN_FLOODPLAIN = 10;

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

constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;

enum class HydroTileWinner : uint8_t {
	Ground = 0,
	MountainFoot,
	MountainWall,
	OceanDeep,
	OceanShelf,
	Shore,
	LakeDeep,
	LakeShallow,
	LakeShore,
	RiverDeep,
	RiverShallow,
	RiverBank,
	Floodplain
};

struct HydrologyTileDecision {
	HydroTileWinner winner = HydroTileWinner::Ground;
	int32_t terrain_id = TERRAIN_PLAINS_GROUND;
	uint8_t walkable = 1U;
	int32_t hydrology_id = 0;
	int32_t hydrology_flags = 0;
	uint8_t floodplain_strength = 0U;
	uint8_t water_class = WATER_CLASS_NONE;
	uint8_t flow_dir = 255U;
	uint8_t stream_order = 0U;
	int32_t water_atlas_index = 0;
};

struct DebugRgba8 {
	uint8_t r = 0U;
	uint8_t g = 0U;
	uint8_t b = 0U;
	uint8_t a = 255U;
};

struct PresentationRgba8 {
	uint8_t r = 0U;
	uint8_t g = 0U;
	uint8_t b = 0U;
	uint8_t a = 255U;
};

struct HydrologyTileInputs {
	int32_t base_terrain_id = TERRAIN_PLAINS_GROUND;
	uint8_t base_walkable = 1U;
	uint8_t mountain_flags = 0U;
	bool enforce_mountain_clearance = false;
	float mountain_clearance_distance_tiles = 1000000000.0f;
	float required_mountain_clearance_tiles = 0.0f;

	bool ocean_delta = false;
	bool ocean_floor = false;
	bool ocean_shore = false;
	bool ocean_shallow_shelf = false;
	bool ocean_uses_stable_id = true;
	uint8_t ocean_shore_strength = 0U;

	bool lakebed = false;
	bool lake_edge = false;
	bool lake_shore = false;
	int32_t lake_id = 0;
	uint8_t lake_flow_dir = 255U;
	uint8_t lake_stream_order = 0U;
	uint8_t lake_shore_strength = 0U;

	bool riverbed = false;
	bool river_deep = false;
	bool river_bank = false;
	int32_t river_segment_id = 0;
	int32_t river_extra_flags = 0;
	uint8_t river_flow_dir = 255U;
	uint8_t river_stream_order = 0U;
	uint8_t river_bank_strength = 0U;

	bool floodplain = false;
	uint8_t floodplain_strength = 0U;
	int32_t floodplain_flags = HYDROLOGY_FLAG_FLOODPLAIN;
};

HydrologyTileDecision classify_tile(const HydrologyTileInputs &p_inputs);
HydroTileWinner winner_from_packet(
	int32_t p_terrain_id,
	int32_t p_hydrology_id,
	int32_t p_hydrology_flags,
	uint8_t p_water_class,
	uint8_t p_mountain_flags
);
bool is_water_winner(HydroTileWinner p_winner);
bool is_mountain_winner(HydroTileWinner p_winner);
int32_t winner_code(HydroTileWinner p_winner);
int32_t winner_family_code(HydroTileWinner p_winner);
DebugRgba8 debug_winner_color(HydroTileWinner p_winner);
HydroTileWinner winner_from_debug_color(DebugRgba8 p_color);
PresentationRgba8 gameplay_winner_color(
	HydroTileWinner p_winner,
	uint8_t p_strength = 0U,
	uint8_t p_alpha = 255U
);

} // namespace hydrology_tile_classifier

#endif
