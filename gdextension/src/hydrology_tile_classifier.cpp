#include "hydrology_tile_classifier.h"

namespace hydrology_tile_classifier {

namespace {

constexpr PresentationRgba8 PRESENTATION_COLOR_GROUND = { 46U, 59U, 46U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_MOUNTAIN_FOOT = { 135U, 125U, 99U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_MOUNTAIN_WALL = { 219U, 212U, 194U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_OCEAN_DEEP = { 30U, 75U, 111U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_OCEAN_SHELF = { 52U, 118U, 145U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_OCEAN_SHORE = { 72U, 139U, 151U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_LAKE_DEEP = { 34U, 91U, 125U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_LAKE_SHALLOW = { 63U, 139U, 159U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_LAKE_SHORE = { 94U, 135U, 131U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_RIVER_DEEP = { 28U, 82U, 124U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_RIVER_SHALLOW = { 56U, 133U, 163U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_RIVER_BANK = { 88U, 119U, 105U, 255U };
constexpr PresentationRgba8 PRESENTATION_COLOR_FLOODPLAIN_WET = { 55U, 99U, 62U, 255U };

uint8_t clamp_u8(int32_t p_value) {
	if (p_value < 0) {
		return 0U;
	}
	if (p_value > 255) {
		return 255U;
	}
	return static_cast<uint8_t>(p_value);
}

PresentationRgba8 with_alpha(PresentationRgba8 p_color, uint8_t p_alpha) {
	p_color.a = p_alpha;
	return p_color;
}

PresentationRgba8 blend_color(PresentationRgba8 p_a, PresentationRgba8 p_b, uint8_t p_t, uint8_t p_alpha) {
	const int32_t inv_t = 255 - static_cast<int32_t>(p_t);
	return {
		clamp_u8((static_cast<int32_t>(p_a.r) * inv_t + static_cast<int32_t>(p_b.r) * p_t + 127) / 255),
		clamp_u8((static_cast<int32_t>(p_a.g) * inv_t + static_cast<int32_t>(p_b.g) * p_t + 127) / 255),
		clamp_u8((static_cast<int32_t>(p_a.b) * inv_t + static_cast<int32_t>(p_b.b) * p_t + 127) / 255),
		p_alpha
	};
}

HydroTileWinner base_winner_for(int32_t p_terrain_id, uint8_t p_mountain_flags) {
	if ((p_mountain_flags & MOUNTAIN_FLAG_WALL) != 0U || p_terrain_id == TERRAIN_MOUNTAIN_WALL) {
		return HydroTileWinner::MountainWall;
	}
	if ((p_mountain_flags & MOUNTAIN_FLAG_FOOT) != 0U || p_terrain_id == TERRAIN_MOUNTAIN_FOOT) {
		return HydroTileWinner::MountainFoot;
	}
	if (p_terrain_id == TERRAIN_FLOODPLAIN) {
		return HydroTileWinner::Floodplain;
	}
	return HydroTileWinner::Ground;
}

HydrologyTileDecision make_base_decision(const HydrologyTileInputs &p_inputs) {
	HydrologyTileDecision decision;
	decision.winner = base_winner_for(p_inputs.base_terrain_id, p_inputs.mountain_flags);
	decision.terrain_id = p_inputs.base_terrain_id;
	decision.walkable = p_inputs.base_walkable;
	return decision;
}

} // namespace

HydrologyTileDecision classify_tile(const HydrologyTileInputs &p_inputs) {
	HydrologyTileDecision decision = make_base_decision(p_inputs);
	const bool mountain_blocks_water =
			(p_inputs.mountain_flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) != 0U;

	if (p_inputs.ocean_delta) {
		decision.winner = HydroTileWinner::OceanDeep;
		decision.terrain_id = TERRAIN_OCEAN_FLOOR;
		decision.walkable = 0U;
		decision.hydrology_id = p_inputs.river_segment_id;
		decision.hydrology_flags = HYDROLOGY_FLAG_DELTA |
				(p_inputs.river_extra_flags & HYDROLOGY_FLAG_BRAID_SPLIT);
		decision.floodplain_strength = 255U;
		decision.water_class = WATER_CLASS_OCEAN;
		decision.flow_dir = p_inputs.river_flow_dir;
		decision.stream_order = p_inputs.river_stream_order;
		decision.water_atlas_index = static_cast<int32_t>(WATER_CLASS_OCEAN) * 16;
		return decision;
	}

	if (p_inputs.ocean_floor || p_inputs.ocean_shore) {
		if (p_inputs.ocean_shore) {
			decision.winner = HydroTileWinner::Shore;
			decision.terrain_id = TERRAIN_SHORE;
			decision.walkable = 1U;
			decision.hydrology_id = HYDROLOGY_OCEAN_ID;
			decision.hydrology_flags = HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK;
			decision.floodplain_strength = p_inputs.ocean_shore_strength;
			return decision;
		}
		decision.winner = p_inputs.ocean_shallow_shelf ? HydroTileWinner::OceanShelf : HydroTileWinner::OceanDeep;
		decision.terrain_id = TERRAIN_OCEAN_FLOOR;
		decision.walkable = p_inputs.ocean_shallow_shelf ? 1U : 0U;
		decision.hydrology_id = p_inputs.ocean_uses_stable_id ? HYDROLOGY_OCEAN_ID : 0;
		decision.water_class = p_inputs.ocean_shallow_shelf ? WATER_CLASS_SHALLOW : WATER_CLASS_OCEAN;
		decision.water_atlas_index = static_cast<int32_t>(decision.water_class) * 16;
		return decision;
	}

	if (mountain_blocks_water) {
		return decision;
	}

	const bool mountain_clearance_blocks_non_ocean_water =
			p_inputs.enforce_mountain_clearance &&
			p_inputs.mountain_clearance_distance_tiles <= p_inputs.required_mountain_clearance_tiles;
	if (mountain_clearance_blocks_non_ocean_water) {
		return decision;
	}

	if (p_inputs.lakebed && p_inputs.lake_id > 0) {
		const bool shallow_edge = p_inputs.lake_edge;
		decision.winner = shallow_edge ? HydroTileWinner::LakeShallow : HydroTileWinner::LakeDeep;
		decision.terrain_id = TERRAIN_LAKEBED;
		decision.walkable = shallow_edge ? 1U : 0U;
		decision.hydrology_id = HYDROLOGY_LAKE_ID_OFFSET + p_inputs.lake_id;
		decision.hydrology_flags = HYDROLOGY_FLAG_LAKEBED | (shallow_edge ? HYDROLOGY_FLAG_SHORE : 0);
		decision.water_class = shallow_edge ? WATER_CLASS_SHALLOW : WATER_CLASS_DEEP;
		decision.flow_dir = p_inputs.lake_flow_dir;
		decision.stream_order = p_inputs.lake_stream_order;
		decision.floodplain_strength = shallow_edge ? 128U : 0U;
		decision.water_atlas_index = static_cast<int32_t>(decision.water_class) * 16 +
				(decision.flow_dir < 8U ? static_cast<int32_t>(decision.flow_dir) : 0);
		return decision;
	}

	if (p_inputs.riverbed && p_inputs.river_segment_id > 0) {
		decision.winner = p_inputs.river_deep ? HydroTileWinner::RiverDeep : HydroTileWinner::RiverShallow;
		decision.terrain_id = p_inputs.river_deep ? TERRAIN_RIVERBED_DEEP : TERRAIN_RIVERBED_SHALLOW;
		decision.walkable = p_inputs.river_deep ? 0U : 1U;
		decision.hydrology_id = p_inputs.river_segment_id;
		decision.hydrology_flags = HYDROLOGY_FLAG_RIVERBED | p_inputs.river_extra_flags;
		decision.water_class = p_inputs.river_deep ? WATER_CLASS_DEEP : WATER_CLASS_SHALLOW;
		decision.flow_dir = p_inputs.river_flow_dir;
		decision.stream_order = p_inputs.river_stream_order;
		decision.water_atlas_index = static_cast<int32_t>(decision.water_class) * 16 +
				(decision.flow_dir < 8U ? static_cast<int32_t>(decision.flow_dir) : 0);
		return decision;
	}

	if (p_inputs.river_bank && p_inputs.river_segment_id > 0) {
		decision.winner = HydroTileWinner::RiverBank;
		decision.terrain_id = TERRAIN_SHORE;
		decision.walkable = 1U;
		decision.hydrology_id = p_inputs.river_segment_id;
		decision.hydrology_flags = HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK | p_inputs.river_extra_flags;
		decision.flow_dir = p_inputs.river_flow_dir;
		decision.stream_order = p_inputs.river_stream_order;
		decision.floodplain_strength = p_inputs.river_bank_strength;
		return decision;
	}

	if (p_inputs.lake_shore && p_inputs.lake_id > 0) {
		decision.winner = HydroTileWinner::LakeShore;
		decision.terrain_id = TERRAIN_SHORE;
		decision.walkable = 1U;
		decision.hydrology_id = HYDROLOGY_LAKE_ID_OFFSET + p_inputs.lake_id;
		decision.hydrology_flags = HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK;
		decision.floodplain_strength = p_inputs.lake_shore_strength;
		return decision;
	}

	if (p_inputs.floodplain) {
		decision.winner = HydroTileWinner::Floodplain;
		decision.terrain_id = TERRAIN_FLOODPLAIN;
		decision.walkable = 1U;
		decision.hydrology_flags = p_inputs.floodplain_flags;
		decision.floodplain_strength = p_inputs.floodplain_strength;
		return decision;
	}

	return decision;
}

HydroTileWinner winner_from_packet(
	int32_t p_terrain_id,
	int32_t p_hydrology_id,
	int32_t p_hydrology_flags,
	uint8_t p_water_class,
	uint8_t p_mountain_flags
) {
	if (p_terrain_id == TERRAIN_OCEAN_FLOOR) {
		return p_water_class == WATER_CLASS_SHALLOW ? HydroTileWinner::OceanShelf : HydroTileWinner::OceanDeep;
	}
	if (p_terrain_id == TERRAIN_LAKEBED) {
		return p_water_class == WATER_CLASS_SHALLOW ? HydroTileWinner::LakeShallow : HydroTileWinner::LakeDeep;
	}
	if (p_terrain_id == TERRAIN_RIVERBED_DEEP) {
		return HydroTileWinner::RiverDeep;
	}
	if (p_terrain_id == TERRAIN_RIVERBED_SHALLOW) {
		return HydroTileWinner::RiverShallow;
	}
	if (p_terrain_id == TERRAIN_SHORE) {
		if ((p_hydrology_flags & HYDROLOGY_FLAG_RIVERBED) != 0 || (p_hydrology_id > 0 && p_hydrology_id < HYDROLOGY_LAKE_ID_OFFSET)) {
			return HydroTileWinner::RiverBank;
		}
		if (p_hydrology_id >= HYDROLOGY_LAKE_ID_OFFSET && p_hydrology_id < HYDROLOGY_OCEAN_ID) {
			return HydroTileWinner::LakeShore;
		}
		return HydroTileWinner::Shore;
	}
	if (p_terrain_id == TERRAIN_FLOODPLAIN || (p_hydrology_flags & HYDROLOGY_FLAG_FLOODPLAIN) != 0) {
		return HydroTileWinner::Floodplain;
	}
	return base_winner_for(p_terrain_id, p_mountain_flags);
}

bool is_water_winner(HydroTileWinner p_winner) {
	return p_winner == HydroTileWinner::OceanDeep ||
			p_winner == HydroTileWinner::OceanShelf ||
			p_winner == HydroTileWinner::LakeDeep ||
			p_winner == HydroTileWinner::LakeShallow ||
			p_winner == HydroTileWinner::RiverDeep ||
			p_winner == HydroTileWinner::RiverShallow;
}

bool is_mountain_winner(HydroTileWinner p_winner) {
	return p_winner == HydroTileWinner::MountainFoot || p_winner == HydroTileWinner::MountainWall;
}

int32_t winner_code(HydroTileWinner p_winner) {
	return static_cast<int32_t>(p_winner);
}

int32_t winner_family_code(HydroTileWinner p_winner) {
	switch (p_winner) {
		case HydroTileWinner::MountainFoot:
		case HydroTileWinner::MountainWall:
			return 1;
		case HydroTileWinner::OceanDeep:
		case HydroTileWinner::OceanShelf:
		case HydroTileWinner::Shore:
			return 2;
		case HydroTileWinner::LakeDeep:
		case HydroTileWinner::LakeShallow:
		case HydroTileWinner::LakeShore:
			return 3;
		case HydroTileWinner::RiverDeep:
		case HydroTileWinner::RiverShallow:
		case HydroTileWinner::RiverBank:
		case HydroTileWinner::Floodplain:
			return 4;
		case HydroTileWinner::Ground:
		default:
			return 0;
	}
}

DebugRgba8 debug_winner_color(HydroTileWinner p_winner) {
	switch (p_winner) {
		case HydroTileWinner::OceanDeep:
			return { 20U, 64U, 150U, 255U };
		case HydroTileWinner::OceanShelf:
			return { 48U, 142U, 178U, 255U };
		case HydroTileWinner::Shore:
			return { 235U, 205U, 120U, 255U };
		case HydroTileWinner::LakeDeep:
			return { 32U, 92U, 170U, 255U };
		case HydroTileWinner::LakeShallow:
			return { 54U, 150U, 190U, 255U };
		case HydroTileWinner::LakeShore:
			return { 202U, 184U, 112U, 255U };
		case HydroTileWinner::RiverDeep:
			return { 18U, 82U, 176U, 255U };
		case HydroTileWinner::RiverShallow:
			return { 44U, 126U, 210U, 255U };
		case HydroTileWinner::RiverBank:
			return { 156U, 170U, 98U, 255U };
		case HydroTileWinner::Floodplain:
			return { 68U, 142U, 74U, 255U };
		case HydroTileWinner::MountainWall:
			return { 218U, 214U, 200U, 255U };
		case HydroTileWinner::MountainFoot:
			return { 150U, 134U, 96U, 255U };
		case HydroTileWinner::Ground:
		default:
			return { 42U, 58U, 42U, 255U };
	}
}

HydroTileWinner winner_from_debug_color(DebugRgba8 p_color) {
	const HydroTileWinner winners[] = {
		HydroTileWinner::Ground,
		HydroTileWinner::MountainFoot,
		HydroTileWinner::MountainWall,
		HydroTileWinner::OceanDeep,
		HydroTileWinner::OceanShelf,
		HydroTileWinner::Shore,
		HydroTileWinner::LakeDeep,
		HydroTileWinner::LakeShallow,
		HydroTileWinner::LakeShore,
		HydroTileWinner::RiverDeep,
		HydroTileWinner::RiverShallow,
		HydroTileWinner::RiverBank,
		HydroTileWinner::Floodplain,
	};
	for (const HydroTileWinner winner : winners) {
		const DebugRgba8 expected = debug_winner_color(winner);
		if (p_color.r == expected.r && p_color.g == expected.g &&
				p_color.b == expected.b && p_color.a == expected.a) {
			return winner;
		}
	}
	return HydroTileWinner::Ground;
}

PresentationRgba8 gameplay_winner_color(
	HydroTileWinner p_winner,
	uint8_t p_strength,
	uint8_t p_alpha
) {
	switch (p_winner) {
		case HydroTileWinner::MountainWall:
			return with_alpha(PRESENTATION_COLOR_MOUNTAIN_WALL, p_alpha);
		case HydroTileWinner::MountainFoot:
			return with_alpha(PRESENTATION_COLOR_MOUNTAIN_FOOT, p_alpha);
		case HydroTileWinner::OceanDeep:
			return with_alpha(PRESENTATION_COLOR_OCEAN_DEEP, p_alpha);
		case HydroTileWinner::OceanShelf:
			return with_alpha(PRESENTATION_COLOR_OCEAN_SHELF, p_alpha);
		case HydroTileWinner::Shore:
			return with_alpha(PRESENTATION_COLOR_OCEAN_SHORE, p_alpha);
		case HydroTileWinner::LakeDeep:
			return with_alpha(PRESENTATION_COLOR_LAKE_DEEP, p_alpha);
		case HydroTileWinner::LakeShallow:
			return with_alpha(PRESENTATION_COLOR_LAKE_SHALLOW, p_alpha);
		case HydroTileWinner::LakeShore:
			return with_alpha(PRESENTATION_COLOR_LAKE_SHORE, p_alpha);
		case HydroTileWinner::RiverDeep:
			return with_alpha(PRESENTATION_COLOR_RIVER_DEEP, p_alpha);
		case HydroTileWinner::RiverShallow:
			return with_alpha(PRESENTATION_COLOR_RIVER_SHALLOW, p_alpha);
		case HydroTileWinner::RiverBank:
			return with_alpha(PRESENTATION_COLOR_RIVER_BANK, p_alpha);
		case HydroTileWinner::Floodplain:
			return blend_color(PRESENTATION_COLOR_GROUND, PRESENTATION_COLOR_FLOODPLAIN_WET, p_strength, p_alpha);
		case HydroTileWinner::Ground:
		default:
			return with_alpha(PRESENTATION_COLOR_GROUND, p_alpha);
	}
}

} // namespace hydrology_tile_classifier
