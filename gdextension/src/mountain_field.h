#ifndef STATION_MIRNY_MOUNTAIN_FIELD_H
#define STATION_MIRNY_MOUNTAIN_FIELD_H

#include "third_party/FastNoiseLite.h"

#include <cstdint>

namespace mountain_field {

struct Settings {
	float density = 0.0f;
	float scale = 512.0f;
	float continuity = 0.65f;
	float ruggedness = 0.55f;
	int32_t anchor_cell_size = 128;
	int32_t gravity_radius = 96;
	float foot_band = 0.08f;
	int32_t interior_margin = 1;
	float latitude_influence = 0.0f;
};

struct Thresholds {
	float t_edge = 1.0f;
	float t_wall = 1.0f;
	float t_anchor = 1.0f;
};

class Evaluator {
public:
	Evaluator(int64_t p_seed, int64_t p_world_version, const Settings &p_settings);

	float sample_elevation(int64_t p_world_x, int64_t p_world_y) const;
	int32_t resolve_mountain_id(int64_t p_world_x, int64_t p_world_y) const;
	int32_t resolve_mountain_id(int64_t p_world_x, int64_t p_world_y, float p_elevation) const;
	bool is_anchor_tile(int64_t p_world_x, int64_t p_world_y, int32_t p_mountain_id) const;
	uint8_t resolve_mountain_flags(
		int64_t p_world_x,
		int64_t p_world_y,
		float p_elevation,
		int32_t p_center_mountain_id,
		int32_t p_north_mountain_id,
		int32_t p_east_mountain_id,
		int32_t p_south_mountain_id,
		int32_t p_west_mountain_id
	) const;
	int32_t resolve_mountain_atlas_index(
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
	) const;

	const Settings &get_settings() const;
	const Thresholds &get_thresholds() const;

private:
	Settings settings_;
	Thresholds thresholds_;
	int64_t seed_ = 0;
	int64_t world_version_ = 0;
	FastNoiseLite domain_warp_noise_;
	FastNoiseLite macro_noise_;
	FastNoiseLite ridge_noise_;
};

float sample_elevation(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings);
int32_t resolve_mountain_id(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings);
uint8_t resolve_mountain_flags(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings);
int32_t resolve_mountain_atlas_index(int64_t p_seed, int64_t p_world_version, int64_t p_world_x, int64_t p_world_y, const Settings &p_settings);

} // namespace mountain_field

#endif
