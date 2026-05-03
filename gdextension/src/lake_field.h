#ifndef STATION_MIRNY_LAKE_FIELD_H
#define STATION_MIRNY_LAKE_FIELD_H

#include "world_prepass.h"

#include <cstdint>
#include <unordered_map>

namespace lake_field {

using BasinMinElevationLookup = std::unordered_map<int32_t, float>;

void solve_lake_basins(
	world_prepass::Snapshot &r_snapshot,
	const LakeSettings &p_lake_settings,
	int64_t p_seed,
	int64_t p_world_version
);

BasinMinElevationLookup build_basin_min_elevation_lookup(const world_prepass::Snapshot &p_snapshot);

float resolve_basin_min_elevation(
	const BasinMinElevationLookup &p_lookup,
	int32_t p_lake_id,
	float p_fallback
);

float fbm_shore(
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_seed,
	int64_t p_world_version,
	float p_scale,
	float p_amplitude
);

} // namespace lake_field

#endif
