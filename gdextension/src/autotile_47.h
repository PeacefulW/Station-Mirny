#ifndef STATION_MIRNY_AUTOTILE_47_H
#define STATION_MIRNY_AUTOTILE_47_H

#include <cstdint>

namespace autotile_47 {

constexpr int64_t k_case_count = 47;
constexpr int64_t k_default_variant_count = 6;

int64_t resolve_atlas_index(
	bool p_n,
	bool p_ne,
	bool p_e,
	bool p_se,
	bool p_s,
	bool p_sw,
	bool p_w,
	bool p_nw,
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_seed,
	int64_t p_variant_count = k_default_variant_count
);

} // namespace autotile_47

#endif
