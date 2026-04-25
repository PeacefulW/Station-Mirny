#ifndef STATION_MIRNY_WORLD_UTILS_H
#define STATION_MIRNY_WORLD_UTILS_H

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace world_utils {

constexpr int64_t LEGACY_WORLD_WRAP_WIDTH_TILES = 65536;
constexpr int64_t MOUNTAIN_FINITE_WIDTH_VERSION = 10;

inline uint64_t splitmix64(uint64_t p_value) {
	p_value += 0x9e3779b97f4a7c15ULL;
	p_value = (p_value ^ (p_value >> 30U)) * 0xbf58476d1ce4e5b9ULL;
	p_value = (p_value ^ (p_value >> 27U)) * 0x94d049bb133111ebULL;
	return p_value ^ (p_value >> 31U);
}

inline uint64_t mix_seed(int64_t p_seed, int64_t p_world_version, uint64_t p_salt) {
	uint64_t mixed = splitmix64(static_cast<uint64_t>(p_seed) ^ p_salt);
	return splitmix64(mixed ^ static_cast<uint64_t>(p_world_version) * 0x9e3779b185ebca87ULL);
}

inline int64_t positive_mod(int64_t p_value, int64_t p_modulus) {
	if (p_modulus <= 0) {
		return p_value;
	}
	int64_t result = p_value % p_modulus;
	if (result < 0) {
		result += p_modulus;
	}
	return result;
}

inline int64_t wrap_foundation_world_x(int64_t p_world_x, int64_t p_width_tiles, bool p_enabled) {
	if (!p_enabled) {
		return p_world_x;
	}
	return positive_mod(p_world_x, p_width_tiles);
}

inline int64_t clamp_foundation_world_y(int64_t p_world_y, int64_t p_height_tiles, bool p_enabled) {
	if (!p_enabled) {
		return p_world_y;
	}
	return std::max<int64_t>(0, std::min<int64_t>(p_world_y, p_height_tiles - 1));
}

inline int64_t map_foundation_x_to_legacy_sample(int64_t p_world_x, int64_t p_width_tiles, bool p_enabled) {
	if (!p_enabled) {
		return p_world_x;
	}
	const int64_t wrapped_x = wrap_foundation_world_x(p_world_x, p_width_tiles, p_enabled);
	return static_cast<int64_t>(std::llround(
		(static_cast<double>(wrapped_x) * static_cast<double>(LEGACY_WORLD_WRAP_WIDTH_TILES)) /
		static_cast<double>(p_width_tiles)
	));
}

inline int64_t resolve_mountain_sample_x(
	int64_t p_world_x,
	int64_t p_world_version,
	int64_t p_width_tiles,
	bool p_enabled
) {
	if (!p_enabled) {
		return p_world_x;
	}
	if (p_world_version < MOUNTAIN_FINITE_WIDTH_VERSION) {
		return map_foundation_x_to_legacy_sample(p_world_x, p_width_tiles, p_enabled);
	}
	return wrap_foundation_world_x(p_world_x, p_width_tiles, p_enabled);
}

template <typename T>
T clamp_value(T p_value, T p_min_value, T p_max_value) {
	return std::max(p_min_value, std::min(p_max_value, p_value));
}

inline float saturate(float p_value) {
	return clamp_value(p_value, 0.0f, 1.0f);
}

} // namespace world_utils

#endif
