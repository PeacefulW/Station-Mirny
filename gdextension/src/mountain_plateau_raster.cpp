#include "mountain_plateau_raster.h"

#include "world_utils.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <deque>
#include <limits>
#include <thread>
#include <unordered_set>
#include <vector>

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace mountain_plateau_raster {
namespace {

constexpr int32_t TILE_SIZE_PX = 64;
constexpr int32_t CHUNK_SIZE = 16;
constexpr int32_t CHUNK_CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;
constexpr int32_t GROUND_BACKDROP_PADDING_TILES = 2;
constexpr int32_t ROUND_BLUR_PASSES = 2;
constexpr float SAMPLE_STEP_PX = 1.0f;

constexpr int32_t TERRAIN_LEGACY_BLOCKED = 1;
constexpr int32_t TERRAIN_MOUNTAIN_WALL = 3;
constexpr int32_t TERRAIN_MOUNTAIN_FOOT = 4;
constexpr uint8_t MOUNTAIN_FLAG_WALL = 1U << 1U;
constexpr uint8_t MOUNTAIN_FLAG_FOOT = 1U << 2U;

struct ColorF {
	float r = 0.0f;
	float g = 0.0f;
	float b = 0.0f;
	float a = 1.0f;
};

struct Vec3F {
	float x = 0.0f;
	float y = 0.0f;
	float z = 1.0f;
};

struct TileCoord {
	int32_t x = 0;
	int32_t y = 0;
};

struct ImageView {
	int32_t width = 0;
	int32_t height = 0;
	godot::PackedByteArray bytes;
};

struct AlphaBounds {
	int32_t min_x = 0;
	int32_t min_y = 0;
	int32_t max_x = -1;
	int32_t max_y = -1;
	bool has_pixels = false;
};

using RasterClock = std::chrono::steady_clock;

int64_t elapsed_ms_since(RasterClock::time_point p_started) {
	return std::chrono::duration_cast<std::chrono::milliseconds>(RasterClock::now() - p_started).count();
}

constexpr ColorF GROUND_COLOR = { 0.24f, 0.18f, 0.12f, 1.0f };
constexpr ColorF GROUND_DETAIL_COLOR = { 0.34f, 0.26f, 0.17f, 1.0f };
constexpr ColorF TOP_COLOR = { 0.76f, 0.31f, 0.10f, 1.0f };
constexpr ColorF TOP_LIGHT_COLOR = { 0.93f, 0.44f, 0.16f, 1.0f };
constexpr ColorF TOP_DARK_COLOR = { 0.39f, 0.13f, 0.04f, 1.0f };
constexpr ColorF FACE_TOP_COLOR = { 0.48f, 0.18f, 0.06f, 1.0f };
constexpr ColorF FACE_BOTTOM_COLOR = { 0.15f, 0.045f, 0.018f, 1.0f };
constexpr ColorF RIM_COLOR = { 0.17f, 0.055f, 0.02f, 1.0f };
constexpr ColorF RIM_LIGHT_COLOR = { 0.63f, 0.24f, 0.075f, 1.0f };
constexpr ColorF OUTLINE_COLOR = { 0.018f, 0.012f, 0.008f, 1.0f };

int64_t make_tile_key(int32_t p_x, int32_t p_y) {
	return (static_cast<int64_t>(p_x) << 32) ^ static_cast<uint32_t>(p_y);
}

bool is_fully_mountain_tile_rect(
	const std::unordered_set<int64_t> &p_mountain_keys,
	int32_t p_min_x,
	int32_t p_min_y,
	int32_t p_max_x,
	int32_t p_max_y
) {
	for (int32_t y = p_min_y; y <= p_max_y; ++y) {
		for (int32_t x = p_min_x; x <= p_max_x; ++x) {
			if (p_mountain_keys.find(make_tile_key(x, y)) == p_mountain_keys.end()) {
				return false;
			}
		}
	}
	return true;
}

bool is_mountain_terrain(int32_t p_terrain_id) {
	return p_terrain_id == TERRAIN_MOUNTAIN_WALL ||
			p_terrain_id == TERRAIN_MOUNTAIN_FOOT ||
			p_terrain_id == TERRAIN_LEGACY_BLOCKED;
}

float clamp01(float p_value) {
	return std::max(0.0f, std::min(1.0f, p_value));
}

float smoothstep(float p_edge0, float p_edge1, float p_value) {
	if (p_edge0 == p_edge1) {
		return p_value < p_edge0 ? 0.0f : 1.0f;
	}
	const float t = clamp01((p_value - p_edge0) / (p_edge1 - p_edge0));
	return t * t * (3.0f - 2.0f * t);
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float positive_fmod(float p_value, float p_modulus) {
	if (p_modulus <= 0.0f) {
		return p_value;
	}
	float result = std::fmod(p_value, p_modulus);
	if (result < 0.0f) {
		result += p_modulus;
	}
	return result;
}

ColorF lerp_color(ColorF p_a, ColorF p_b, float p_t) {
	const float t = clamp01(p_t);
	return {
		lerp_float(p_a.r, p_b.r, t),
		lerp_float(p_a.g, p_b.g, t),
		lerp_float(p_a.b, p_b.b, t),
		lerp_float(p_a.a, p_b.a, t),
	};
}

ColorF blend(ColorF p_base, ColorF p_overlay, float p_alpha) {
	return lerp_color(p_base, p_overlay, clamp01(p_alpha * p_overlay.a));
}

ColorF source_over(ColorF p_base, ColorF p_overlay, float p_alpha) {
	const float source_alpha = clamp01(p_alpha * p_overlay.a);
	const float base_alpha = clamp01(p_base.a);
	const float out_alpha = source_alpha + base_alpha * (1.0f - source_alpha);
	if (out_alpha <= 0.00001f) {
		return { 0.0f, 0.0f, 0.0f, 0.0f };
	}
	return {
		(p_overlay.r * source_alpha + p_base.r * base_alpha * (1.0f - source_alpha)) / out_alpha,
		(p_overlay.g * source_alpha + p_base.g * base_alpha * (1.0f - source_alpha)) / out_alpha,
		(p_overlay.b * source_alpha + p_base.b * base_alpha * (1.0f - source_alpha)) / out_alpha,
		out_alpha,
	};
}

uint8_t float_to_u8(float p_value) {
	return static_cast<uint8_t>(std::max(0, std::min(255, static_cast<int32_t>(std::lround(clamp01(p_value) * 255.0f)))));
}

void write_color(uint8_t *r_bytes, int64_t p_offset, ColorF p_color) {
	r_bytes[p_offset] = float_to_u8(p_color.r);
	r_bytes[p_offset + 1] = float_to_u8(p_color.g);
	r_bytes[p_offset + 2] = float_to_u8(p_color.b);
	r_bytes[p_offset + 3] = float_to_u8(p_color.a);
}

AlphaBounds rgba_alpha_bounds(
	const godot::PackedByteArray &p_bytes,
	int32_t p_width,
	int32_t p_height,
	uint8_t p_alpha_threshold
) {
	AlphaBounds bounds;
	if (p_width <= 0 || p_height <= 0 || p_bytes.size() < p_width * p_height * 4) {
		return bounds;
	}
	bounds.min_x = p_width;
	bounds.min_y = p_height;
	bounds.max_x = -1;
	bounds.max_y = -1;
	const uint8_t *read = p_bytes.ptr();
	for (int32_t y = 0; y < p_height; ++y) {
		for (int32_t x = 0; x < p_width; ++x) {
			const int64_t offset = (static_cast<int64_t>(y) * p_width + x) * 4 + 3;
			if (read[offset] <= p_alpha_threshold) {
				continue;
			}
			bounds.has_pixels = true;
			bounds.min_x = std::min(bounds.min_x, x);
			bounds.min_y = std::min(bounds.min_y, y);
			bounds.max_x = std::max(bounds.max_x, x);
			bounds.max_y = std::max(bounds.max_y, y);
		}
	}
	return bounds;
}

AlphaBounds expand_alpha_bounds(AlphaBounds p_bounds, int32_t p_width, int32_t p_height, int32_t p_padding_px) {
	if (!p_bounds.has_pixels || p_width <= 0 || p_height <= 0) {
		return p_bounds;
	}
	const int32_t padding = std::max(0, p_padding_px);
	p_bounds.min_x = std::max(0, p_bounds.min_x - padding);
	p_bounds.min_y = std::max(0, p_bounds.min_y - padding);
	p_bounds.max_x = std::min(p_width - 1, p_bounds.max_x + padding);
	p_bounds.max_y = std::min(p_height - 1, p_bounds.max_y + padding);
	return p_bounds;
}

godot::PackedByteArray crop_rgba_bytes(
	const godot::PackedByteArray &p_bytes,
	int32_t p_source_width,
	const AlphaBounds &p_bounds
) {
	godot::PackedByteArray cropped;
	if (!p_bounds.has_pixels || p_source_width <= 0) {
		return cropped;
	}
	const int32_t crop_width = p_bounds.max_x - p_bounds.min_x + 1;
	const int32_t crop_height = p_bounds.max_y - p_bounds.min_y + 1;
	if (crop_width <= 0 || crop_height <= 0) {
		return cropped;
	}
	cropped.resize(crop_width * crop_height * 4);
	const uint8_t *read = p_bytes.ptr();
	uint8_t *write = cropped.ptrw();
	for (int32_t y = 0; y < crop_height; ++y) {
		for (int32_t x = 0; x < crop_width; ++x) {
			const int64_t source_offset = (static_cast<int64_t>(p_bounds.min_y + y) * p_source_width + (p_bounds.min_x + x)) * 4;
			const int64_t target_offset = (static_cast<int64_t>(y) * crop_width + x) * 4;
			write[target_offset] = read[source_offset];
			write[target_offset + 1] = read[source_offset + 1];
			write[target_offset + 2] = read[source_offset + 2];
			write[target_offset + 3] = read[source_offset + 3];
		}
	}
	return cropped;
}

Vec3F normalize_vec3(Vec3F p_value) {
	const float length = std::sqrt(p_value.x * p_value.x + p_value.y * p_value.y + p_value.z * p_value.z);
	if (length <= 0.00001f) {
		return { 0.0f, 0.0f, 1.0f };
	}
	return { p_value.x / length, p_value.y / length, p_value.z / length };
}

float preset_float(const godot::Dictionary &p_preset, const char *p_key, float p_fallback) {
	const godot::StringName key(p_key);
	if (!p_preset.has(key)) {
		return p_fallback;
	}
	return static_cast<double>(p_preset.get(key, p_fallback));
}

bool preset_bool(const godot::Dictionary &p_preset, const char *p_key, bool p_fallback) {
	const godot::StringName key(p_key);
	if (!p_preset.has(key)) {
		return p_fallback;
	}
	return static_cast<bool>(p_preset.get(key, p_fallback));
}

float noise_i(int32_t p_x, int32_t p_y, int32_t p_salt) {
	int64_t value =
			static_cast<int64_t>(p_x) * 92837111LL +
			static_cast<int64_t>(p_y) * 689287499LL +
			static_cast<int64_t>(p_salt) * 283923481LL;
	value = world_utils::positive_mod(value * 1103515245LL + 12345LL, 100000LL);
	return static_cast<float>(value) / 99999.0f;
}

float value_noise(float p_world_x, float p_world_y, float p_scale_px, int32_t p_salt) {
	const float scale = std::max(p_scale_px, 1.0f);
	const int32_t gx = static_cast<int32_t>(std::floor(p_world_x / scale));
	const int32_t gy = static_cast<int32_t>(std::floor(p_world_y / scale));
	const float tx = smoothstep(0.0f, 1.0f, positive_fmod(p_world_x, scale) / scale);
	const float ty = smoothstep(0.0f, 1.0f, positive_fmod(p_world_y, scale) / scale);
	const float a = noise_i(gx, gy, p_salt);
	const float b = noise_i(gx + 1, gy, p_salt);
	const float c = noise_i(gx, gy + 1, p_salt);
	const float d = noise_i(gx + 1, gy + 1, p_salt);
	return lerp_float(lerp_float(a, b, tx), lerp_float(c, d, tx), ty);
}

float fbm_noise(float p_world_x, float p_world_y, float p_base_scale_px, int32_t p_salt, int32_t p_octaves) {
	float scale = std::max(p_base_scale_px, 1.0f);
	float amplitude = 0.5f;
	float value = 0.0f;
	float amplitude_sum = 0.0f;
	for (int32_t octave = 0; octave < p_octaves; ++octave) {
		const float sample_x = p_world_x + static_cast<float>(p_salt + octave * 37) * 3.17f;
		const float sample_y = p_world_y - static_cast<float>(p_salt + octave * 53) * 2.43f;
		value += value_noise(sample_x, sample_y, scale, p_salt + octave * 97) * amplitude;
		amplitude_sum += amplitude;
		scale *= 0.53f;
		amplitude *= 0.48f;
	}
	return amplitude_sum > 0.00001f ? value / amplitude_sum : 0.5f;
}

ColorF ground_color_at(int32_t p_x, int32_t p_y, float p_world_x, float p_world_y) {
	const int32_t coarse_x = static_cast<int32_t>(std::floor(p_world_x / 48.0f));
	const int32_t coarse_y = static_cast<int32_t>(std::floor(p_world_y / 48.0f));
	const float noise = noise_i(coarse_x, coarse_y, 19);
	ColorF color = lerp_color(GROUND_COLOR, GROUND_DETAIL_COLOR, noise * 0.18f);
	if (noise_i(p_x / 6, p_y / 6, 71) > 0.92f) {
		color = lerp_color(color, { 0.36f, 0.27f, 0.17f, 1.0f }, 0.10f);
	}
	return color;
}

ImageView image_view_from_ref(const godot::Ref<godot::Image> &p_image) {
	ImageView view;
	if (!p_image.is_valid() || p_image->is_empty()) {
		return view;
	}
	view.width = p_image->get_width();
	view.height = p_image->get_height();
	view.bytes = p_image->get_data();
	return view;
}

int32_t raster_worker_count(int32_t p_height) {
	const uint32_t hardware_threads = std::thread::hardware_concurrency();
	const int32_t available_threads = hardware_threads > 1U ? static_cast<int32_t>(hardware_threads - 1U) : 1;
	return std::max(1, std::min(p_height, std::min(available_threads, 8)));
}

template <typename Callable>
void parallel_for_range(int32_t p_count, Callable p_callable) {
	const int32_t worker_count = raster_worker_count(p_count);
	if (worker_count <= 1 || p_count < 96) {
		p_callable(0, p_count, 0);
		return;
	}
	std::vector<std::thread> workers;
	workers.reserve(static_cast<size_t>(worker_count));
	for (int32_t worker_index = 0; worker_index < worker_count; ++worker_index) {
		const int32_t start = (p_count * worker_index) / worker_count;
		const int32_t end = (p_count * (worker_index + 1)) / worker_count;
		workers.emplace_back([=, &p_callable]() {
			p_callable(start, end, worker_index);
		});
	}
	for (std::thread &worker : workers) {
		worker.join();
	}
}

template <typename Callable>
void parallel_for_rows(int32_t p_height, Callable p_callable) {
	parallel_for_range(p_height, p_callable);
}

ColorF sample_image(const ImageView &p_image, float p_world_x, float p_world_y, float p_source_scale) {
	if (p_image.width <= 0 || p_image.height <= 0 || p_image.bytes.size() < p_image.width * p_image.height * 4) {
		return { 1.0f, 1.0f, 1.0f, 1.0f };
	}
	const int32_t sample_x = world_utils::positive_mod(static_cast<int32_t>(std::floor(p_world_x * p_source_scale)), p_image.width);
	const int32_t sample_y = world_utils::positive_mod(static_cast<int32_t>(std::floor(p_world_y * p_source_scale)), p_image.height);
	const int64_t offset = (static_cast<int64_t>(sample_y) * p_image.width + sample_x) * 4;
	return {
		static_cast<float>(p_image.bytes[offset]) / 255.0f,
		static_cast<float>(p_image.bytes[offset + 1]) / 255.0f,
		static_cast<float>(p_image.bytes[offset + 2]) / 255.0f,
		static_cast<float>(p_image.bytes[offset + 3]) / 255.0f,
	};
}

ColorF top_color_at(
	int32_t p_x,
	int32_t p_y,
	float p_world_x,
	float p_world_y,
	const ImageView &p_top_image,
	float p_texture_scale,
	float p_texture_blend,
	float p_macro_scale_px,
	float p_macro_strength
) {
	const ColorF texture_color = sample_image(p_top_image, p_world_x, p_world_y, p_texture_scale);
	const float macro_noise = value_noise(p_world_x, p_world_y, p_macro_scale_px, 313);
	ColorF macro_color = lerp_color(TOP_COLOR, TOP_LIGHT_COLOR, std::max(0.0f, macro_noise - 0.5f) * p_macro_strength);
	macro_color = lerp_color(macro_color, TOP_DARK_COLOR, std::max(0.0f, 0.5f - macro_noise) * p_macro_strength);
	ColorF color = lerp_color(macro_color, texture_color, p_texture_blend);
	const int32_t detail_x = static_cast<int32_t>(std::floor(p_world_x));
	const int32_t detail_y = static_cast<int32_t>(std::floor(p_world_y));
	if (noise_i(detail_x / 5, detail_y / 5, 131) > 0.94f) {
		color = lerp_color(color, TOP_LIGHT_COLOR, 0.20f);
	}
	if (noise_i(detail_x / 9, detail_y / 9, 239) < 0.07f) {
		color = lerp_color(color, TOP_DARK_COLOR, 0.15f);
	}
	return color;
}

ColorF face_color_at(
	float p_world_x,
	float p_world_y,
	float p_depth,
	const ImageView &p_face_image,
	float p_texture_scale,
	float p_texture_blend,
	float p_face_darkening
) {
	const ColorF base = lerp_color(FACE_TOP_COLOR, FACE_BOTTOM_COLOR, clamp01(p_depth));
	const ColorF texture_color = sample_image(p_face_image, p_world_x, p_world_y, p_texture_scale);
	return lerp_color(lerp_color(base, texture_color, p_texture_blend), FACE_BOTTOM_COLOR, p_depth * p_face_darkening);
}

float mountain_normal_detail_height(
	float p_world_x,
	float p_world_y,
	float p_face_depth,
	float p_top_weight,
	float p_face_weight,
	float p_top_detail_strength,
	float p_face_detail_strength,
	float p_detail_scale_px,
	float p_macro_scale_px
) {
	const float detail_scale = std::max(p_detail_scale_px, 1.0f);
	const float macro_scale = std::max(p_macro_scale_px, 1.0f);
	const float warp_strength = std::min(macro_scale * 0.18f, 46.0f);
	const float warp_x = (fbm_noise(p_world_x, p_world_y, macro_scale * 0.92f, 701, 3) - 0.5f) * warp_strength;
	const float warp_y = (fbm_noise(p_world_x + 101.0f, p_world_y - 73.0f, macro_scale * 0.88f, 709, 3) - 0.5f) * warp_strength;
	const float world_x = p_world_x + warp_x;
	const float world_y = p_world_y + warp_y;
	const float broad = (fbm_noise(world_x - 53.0f, world_y + 29.0f, macro_scale * 0.82f, 727, 4) - 0.5f) * 2.0f;
	const float mid = (fbm_noise(world_x + 17.0f, world_y - 31.0f, detail_scale * 2.9f, 739, 3) - 0.5f) * 2.0f;
	const float fine = (fbm_noise(world_x - 11.0f, world_y + 5.0f, detail_scale * 1.35f, 751, 2) - 0.5f) * 2.0f;
	const float pit_source = fbm_noise(world_x + 67.0f, world_y - 43.0f, detail_scale * 5.4f, 761, 3);
	const float dent = -std::pow(std::max(0.0f, 0.46f - pit_source), 2.0f) * 1.35f;
	const float strata_noise = fbm_noise(world_x, world_y, macro_scale * 0.72f, 773, 4);
	const float strata_phase = (strata_noise - 0.5f) * 78.0f;
	const float strata = std::sin((world_y + strata_phase) * 0.055f) *
			(0.35f + fbm_noise(world_x + 23.0f, world_y, macro_scale * 0.44f, 787, 3) * 0.65f) *
			(1.0f - clamp01(p_face_depth) * 0.30f);
	const float top_detail = (broad * 0.16f + mid * 0.10f + fine * 0.035f + dent * 0.055f) * p_top_detail_strength;
	const float face_detail = (broad * 0.12f + mid * 0.075f + fine * 0.025f + dent * 0.085f + strata * 0.10f) * p_face_detail_strength;
	return p_top_weight * top_detail + p_face_weight * face_detail;
}

float mountain_normal_detail_height_fast(
	float p_world_x,
	float p_world_y,
	float p_face_depth,
	float p_top_weight,
	float p_face_weight,
	float p_top_detail_strength,
	float p_face_detail_strength,
	float p_detail_scale_px,
	float p_macro_scale_px
) {
	const float detail_scale = std::max(p_detail_scale_px, 1.0f);
	const float macro_scale = std::max(p_macro_scale_px, 1.0f);
	const float broad = (value_noise(p_world_x - 53.0f, p_world_y + 29.0f, macro_scale * 0.82f, 727) - 0.5f) * 2.0f;
	const float mid = (value_noise(p_world_x + 17.0f, p_world_y - 31.0f, detail_scale * 2.9f, 739) - 0.5f) * 2.0f;
	const float fine = (value_noise(p_world_x - 11.0f, p_world_y + 5.0f, detail_scale * 1.35f, 751) - 0.5f) * 2.0f;
	const float strata_phase = (value_noise(p_world_x, p_world_y, macro_scale * 0.72f, 773) - 0.5f) * 72.0f;
	const float strata = std::sin((p_world_y + strata_phase) * 0.055f) *
			(1.0f - clamp01(p_face_depth) * 0.30f);
	const float top_detail = (broad * 0.15f + mid * 0.08f + fine * 0.030f) * p_top_detail_strength;
	const float face_detail = (broad * 0.11f + mid * 0.065f + fine * 0.022f + strata * 0.085f) * p_face_detail_strength;
	return p_top_weight * top_detail + p_face_weight * face_detail;
}

float ground_normal_height(float p_world_x, float p_world_y) {
	const float warp_x = (fbm_noise(p_world_x, p_world_y, 160.0f, 1201, 3) - 0.5f) * 18.0f;
	const float warp_y = (fbm_noise(p_world_x - 31.0f, p_world_y + 47.0f, 148.0f, 1209, 3) - 0.5f) * 18.0f;
	const float world_x = p_world_x + warp_x;
	const float world_y = p_world_y + warp_y;
	const float broad = (fbm_noise(world_x - 19.0f, world_y + 41.0f, 118.0f, 1217, 4) - 0.5f) * 0.22f;
	const float mid = (fbm_noise(world_x + 7.0f, world_y - 13.0f, 54.0f, 1223, 3) - 0.5f) * 0.08f;
	const float fine = (fbm_noise(world_x - 29.0f, world_y + 3.0f, 28.0f, 1231, 2) - 0.5f) * 0.025f;
	return broad + mid + fine;
}

float sample_height_field(const std::vector<float> &p_height_field, int32_t p_width, int32_t p_height, int32_t p_x, int32_t p_y) {
	const int32_t x = std::max(0, std::min(p_width - 1, p_x));
	const int32_t y = std::max(0, std::min(p_height - 1, p_y));
	return p_height_field[static_cast<int64_t>(y) * p_width + x];
}

godot::PackedByteArray build_normal_bytes(
	const std::vector<float> &p_height_field,
	const std::vector<float> &p_coverage_field,
	int32_t p_width,
	int32_t p_height,
	float p_normal_strength,
	int64_t &r_normal_pixel_count
) {
	godot::PackedByteArray normal_bytes;
	const int64_t total_pixels = static_cast<int64_t>(p_width) * p_height;
	normal_bytes.resize(static_cast<int32_t>(total_pixels * 4));
	uint8_t *write = normal_bytes.ptrw();
	r_normal_pixel_count = 0;
	const int32_t worker_count = raster_worker_count(p_height);
	std::vector<int64_t> normal_counts(static_cast<size_t>(worker_count), 0);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t p_worker_index) {
		int64_t local_count = 0;
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			for (int32_t x = 0; x < p_width; ++x) {
			const int64_t index = static_cast<int64_t>(y) * p_width + x;
			if (p_coverage_field[index] <= 0.01f) {
				write_color(write, index * 4, { 0.5f, 0.5f, 1.0f, 1.0f });
				continue;
			}
			++local_count;
			const float dx = sample_height_field(p_height_field, p_width, p_height, x + 1, y) -
					sample_height_field(p_height_field, p_width, p_height, x - 1, y);
			const float dy = sample_height_field(p_height_field, p_width, p_height, x, y + 1) -
					sample_height_field(p_height_field, p_width, p_height, x, y - 1);
			const Vec3F normal = normalize_vec3({ -dx * p_normal_strength, -dy * p_normal_strength, 1.0f });
			write_color(write, index * 4, {
				normal.x * 0.5f + 0.5f,
				normal.y * 0.5f + 0.5f,
				normal.z * 0.5f + 0.5f,
				1.0f,
			});
			}
		}
		normal_counts[static_cast<size_t>(p_worker_index)] = local_count;
	});
	for (int64_t count : normal_counts) {
		r_normal_pixel_count += count;
	}
	return normal_bytes;
}

godot::PackedVector2Array build_radial_occluder_polygon(
	const std::vector<float> &p_top_alpha,
	int32_t p_width,
	int32_t p_height,
	float p_render_origin_x,
	float p_render_origin_y
) {
	double center_x = 0.0;
	double center_y = 0.0;
	double weight_sum = 0.0;
	for (int32_t y = 0; y < p_height; ++y) {
		for (int32_t x = 0; x < p_width; ++x) {
			const float alpha = p_top_alpha[static_cast<int64_t>(y) * p_width + x];
			if (alpha <= 0.55f) {
				continue;
			}
			center_x += (static_cast<double>(x) + 0.5) * alpha;
			center_y += (static_cast<double>(y) + 0.5) * alpha;
			weight_sum += alpha;
		}
	}

	godot::PackedVector2Array points;
	if (weight_sum <= 0.001) {
		return points;
	}
	center_x /= weight_sum;
	center_y /= weight_sum;

	constexpr int32_t POINT_COUNT = 128;
	const float max_radius = std::sqrt(static_cast<float>(p_width * p_width + p_height * p_height));
	for (int32_t point_index = 0; point_index < POINT_COUNT; ++point_index) {
		const float angle = (static_cast<float>(point_index) / static_cast<float>(POINT_COUNT)) * 6.28318530718f;
		const float dx = std::cos(angle);
		const float dy = std::sin(angle);
		float best_distance = 0.0f;
		for (float distance = 0.0f; distance <= max_radius; distance += 4.0f) {
			const int32_t x = static_cast<int32_t>(std::floor(center_x + dx * distance));
			const int32_t y = static_cast<int32_t>(std::floor(center_y + dy * distance));
			if (x < 0 || y < 0 || x >= p_width || y >= p_height) {
				break;
			}
			if (p_top_alpha[static_cast<int64_t>(y) * p_width + x] > 0.38f) {
				best_distance = distance;
			}
		}
		points.push_back(godot::Vector2(
			p_render_origin_x + (static_cast<float>(center_x) + dx * best_distance) * SAMPLE_STEP_PX,
			p_render_origin_y + (static_cast<float>(center_y) + dy * best_distance) * SAMPLE_STEP_PX
		));
	}
	return points;
}

std::vector<float> box_blur(const std::vector<float> &p_source, int32_t p_width, int32_t p_height, int32_t p_radius) {
	std::vector<float> horizontal(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		std::vector<float> row_prefix(static_cast<size_t>(p_width) + 1U, 0.0f);
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			row_prefix[0] = 0.0f;
			for (int32_t x = 0; x < p_width; ++x) {
				row_prefix[x + 1] = row_prefix[x] + p_source[row + x];
			}
			for (int32_t x = 0; x < p_width; ++x) {
				const int32_t start_x = std::max(0, x - p_radius);
				const int32_t end_x = std::min(p_width - 1, x + p_radius);
				horizontal[row + x] = (row_prefix[end_x + 1] - row_prefix[start_x]) / static_cast<float>(end_x - start_x + 1);
			}
		}
	});

	std::vector<float> result(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_range(p_width, [&](int32_t p_start_x, int32_t p_end_x, int32_t) {
		std::vector<float> column_prefix(static_cast<size_t>(p_height) + 1U, 0.0f);
		for (int32_t x = p_start_x; x < p_end_x; ++x) {
			column_prefix[0] = 0.0f;
			for (int32_t y = 0; y < p_height; ++y) {
				column_prefix[y + 1] = column_prefix[y] + horizontal[static_cast<int64_t>(y) * p_width + x];
			}
			for (int32_t y = 0; y < p_height; ++y) {
				const int32_t start_y = std::max(0, y - p_radius);
				const int32_t end_y = std::min(p_height - 1, y + p_radius);
				result[static_cast<int64_t>(y) * p_width + x] = (column_prefix[end_y + 1] - column_prefix[start_y]) / static_cast<float>(end_y - start_y + 1);
			}
		}
	});
	return result;
}

void stamp_center_blob(
	std::vector<float> &r_mask,
	int32_t p_width,
	int32_t p_height,
	float p_center_x,
	float p_center_y,
	float p_radius_px
) {
	const int32_t radius = std::max(1, static_cast<int32_t>(std::ceil(p_radius_px)));
	const int32_t start_x = std::max(0, static_cast<int32_t>(std::floor(p_center_x)) - radius);
	const int32_t end_x = std::min(p_width - 1, static_cast<int32_t>(std::ceil(p_center_x)) + radius);
	const int32_t start_y = std::max(0, static_cast<int32_t>(std::floor(p_center_y)) - radius);
	const int32_t end_y = std::min(p_height - 1, static_cast<int32_t>(std::ceil(p_center_y)) + radius);
	const float radius_sq = p_radius_px * p_radius_px;
	for (int32_t y = start_y; y <= end_y; ++y) {
		const float dy = (static_cast<float>(y) + 0.5f) - p_center_y;
		const int64_t row = static_cast<int64_t>(y) * p_width;
		for (int32_t x = start_x; x <= end_x; ++x) {
			const float dx = (static_cast<float>(x) + 0.5f) - p_center_x;
			const float distance_sq = dx * dx + dy * dy;
			if (distance_sq > radius_sq) {
				continue;
			}
			const float normalized = 1.0f - std::sqrt(distance_sq) / p_radius_px;
			const float stamp = smoothstep(0.0f, 1.0f, normalized);
			float &target = r_mask[row + x];
			target = target + stamp * (1.0f - target);
		}
	}
}

float sample_field_bilinear(const std::vector<float> &p_field, int32_t p_width, int32_t p_height, float p_x, float p_y) {
	if (p_width <= 0 || p_height <= 0) {
		return 0.0f;
	}
	const float clamped_x = std::max(0.0f, std::min(static_cast<float>(p_width - 1), p_x));
	const float clamped_y = std::max(0.0f, std::min(static_cast<float>(p_height - 1), p_y));
	const int32_t x0 = static_cast<int32_t>(std::floor(clamped_x));
	const int32_t y0 = static_cast<int32_t>(std::floor(clamped_y));
	const int32_t x1 = std::min(x0 + 1, p_width - 1);
	const int32_t y1 = std::min(y0 + 1, p_height - 1);
	const float tx = clamped_x - static_cast<float>(x0);
	const float ty = clamped_y - static_cast<float>(y0);
	const float a = p_field[static_cast<int64_t>(y0) * p_width + x0];
	const float b = p_field[static_cast<int64_t>(y0) * p_width + x1];
	const float c = p_field[static_cast<int64_t>(y1) * p_width + x0];
	const float d = p_field[static_cast<int64_t>(y1) * p_width + x1];
	return lerp_float(lerp_float(a, b, tx), lerp_float(c, d, tx), ty);
}

std::vector<float> build_organic_mask(
	const std::vector<float> &p_source,
	int32_t p_width,
	int32_t p_height,
	float p_render_origin_x,
	float p_render_origin_y,
	float p_threshold_center,
	float p_round_blur_radius_px,
	float p_domain_warp_px,
	float p_domain_warp_scale_px,
	float p_lobe_px,
	float p_lobe_scale_px
) {
	std::vector<float> result(static_cast<size_t>(p_width) * p_height, 0.0f);
	const float warp_scale = std::max(p_domain_warp_scale_px, 1.0f);
	const float lobe_scale = std::max(p_lobe_scale_px, 1.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			for (int32_t x = 0; x < p_width; ++x) {
				const int64_t index = static_cast<int64_t>(y) * p_width + x;
				const float world_x = p_render_origin_x + (static_cast<float>(x) + 0.5f) * SAMPLE_STEP_PX;
				const float world_y = p_render_origin_y + (static_cast<float>(y) + 0.5f) * SAMPLE_STEP_PX;
				float sample_x = static_cast<float>(x);
				float sample_y = static_cast<float>(y);
				if (p_domain_warp_px > 0.0f) {
					const float large_x = (value_noise(world_x, world_y, warp_scale, 401) - 0.5f) * 2.0f;
					const float large_y = (value_noise(world_x, world_y, warp_scale, 409) - 0.5f) * 2.0f;
					const float small_x = (value_noise(world_x + 19.0f, world_y - 11.0f, warp_scale * 0.47f, 421) - 0.5f) * 0.75f;
					const float small_y = (value_noise(world_x - 7.0f, world_y + 23.0f, warp_scale * 0.47f, 431) - 0.5f) * 0.75f;
					sample_x += (large_x + small_x) * p_domain_warp_px / SAMPLE_STEP_PX;
					sample_y += (large_y + small_y) * p_domain_warp_px / SAMPLE_STEP_PX;
				}
				float mask = sample_field_bilinear(p_source, p_width, p_height, sample_x, sample_y);
				if (p_lobe_px > 0.0f) {
					const float edge_band = 1.0f - clamp01(std::abs(mask - p_threshold_center) / 0.30f);
					if (edge_band > 0.0f) {
						const float broad = (value_noise(world_x, world_y, lobe_scale, 503) - 0.5f) * 2.0f;
						const float detail = (value_noise(world_x - 37.0f, world_y + 17.0f, lobe_scale * 0.55f, 541) - 0.5f) * 0.60f;
						const float lobe_bias = (broad + detail) * (p_lobe_px / std::max(p_round_blur_radius_px, 1.0f)) * edge_band;
						mask = clamp01(mask + lobe_bias);
					}
				}
				result[index] = mask;
			}
		}
	});
	return result;
}

float south_face_seed_at(
	const std::vector<float> &p_top_alpha,
	int32_t p_width,
	int32_t p_height,
	int32_t p_x,
	int32_t p_y,
	float p_side_suppression,
	float p_gate_start,
	float p_gate_end
) {
	const int32_t above_y = std::max(p_y - 1, 0);
	const int32_t below_y = std::min(p_y + 1, p_height - 1);
	const int32_t left_x = std::max(p_x - 1, 0);
	const int32_t right_x = std::min(p_x + 1, p_width - 1);
	const int64_t index = static_cast<int64_t>(p_y) * p_width + p_x;
	const float alpha = p_top_alpha[index];
	const float above = p_top_alpha[static_cast<int64_t>(above_y) * p_width + p_x];
	const float below = p_top_alpha[static_cast<int64_t>(below_y) * p_width + p_x];
	const float left = p_top_alpha[static_cast<int64_t>(p_y) * p_width + left_x];
	const float right = p_top_alpha[static_cast<int64_t>(p_y) * p_width + right_x];
	const float south_drop = std::max(0.0f, alpha - below);
	const float south_gradient = std::max(0.0f, above - below);
	const float side_gradient = std::abs(right - left);
	const float south_ratio = south_gradient / (south_gradient + side_gradient * p_side_suppression + 0.001f);
	const float direction_gate = smoothstep(p_gate_start, p_gate_end, south_ratio);
	return alpha * south_drop * direction_gate;
}

std::vector<float> box_blur_horizontal(const std::vector<float> &p_source, int32_t p_width, int32_t p_height, int32_t p_radius) {
	if (p_radius <= 0) {
		return p_source;
	}
	std::vector<float> result(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		std::vector<float> row_prefix(static_cast<size_t>(p_width) + 1U, 0.0f);
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			row_prefix[0] = 0.0f;
			for (int32_t x = 0; x < p_width; ++x) {
				row_prefix[x + 1] = row_prefix[x] + p_source[row + x];
			}
			for (int32_t x = 0; x < p_width; ++x) {
				const int32_t start_x = std::max(0, x - p_radius);
				const int32_t end_x = std::min(p_width - 1, x + p_radius);
				result[row + x] = (row_prefix[end_x + 1] - row_prefix[start_x]) / static_cast<float>(end_x - start_x + 1);
			}
		}
	});
	return result;
}

std::vector<float> filter_face_seed_by_horizontal_support(
	const std::vector<float> &p_source,
	int32_t p_width,
	int32_t p_height,
	int32_t p_radius,
	float p_min_support
) {
	if (p_radius <= 0 || p_min_support <= 0.0f) {
		return p_source;
	}
	std::vector<float> result(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		std::vector<float> row_prefix(static_cast<size_t>(p_width) + 1U, 0.0f);
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			row_prefix[0] = 0.0f;
			for (int32_t x = 0; x < p_width; ++x) {
				row_prefix[x + 1] = row_prefix[x] + (p_source[row + x] > 0.001f ? 1.0f : 0.0f);
			}
			for (int32_t x = 0; x < p_width; ++x) {
				const float value = p_source[row + x];
				if (value <= 0.001f) {
					continue;
				}
				const int32_t start_x = std::max(0, x - p_radius);
				const int32_t end_x = std::min(p_width - 1, x + p_radius);
				const float support = (row_prefix[end_x + 1] - row_prefix[start_x]) /
						static_cast<float>(end_x - start_x + 1);
				if (support < p_min_support) {
					continue;
				}
				result[row + x] = value;
			}
		}
	});
	return result;
}

std::vector<float> horizontal_binary_support(
	const std::vector<float> &p_source,
	int32_t p_width,
	int32_t p_height,
	int32_t p_radius,
	float p_threshold
) {
	std::vector<float> binary(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			for (int32_t x = 0; x < p_width; ++x) {
				binary[row + x] = p_source[row + x] > p_threshold ? 1.0f : 0.0f;
			}
		}
	});
	if (p_radius <= 0) {
		return binary;
	}
	return box_blur_horizontal(binary, p_width, p_height, p_radius);
}

void leash_smoothed_face_seed(
	std::vector<float> &r_face_seed,
	const std::vector<float> &p_raw_seed,
	int32_t p_width,
	int32_t p_height,
	int32_t p_radius,
	float p_min_support
) {
	if (p_radius <= 0 || p_min_support <= 0.0f) {
		return;
	}
	const std::vector<float> support = horizontal_binary_support(
		p_raw_seed,
		p_width,
		p_height,
		p_radius,
		0.001f
	);
	const float support_end = std::min(1.0f, p_min_support + 0.12f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			for (int32_t x = 0; x < p_width; ++x) {
				const int64_t index = row + x;
				if (r_face_seed[index] <= 0.0f) {
					continue;
				}
				const float gate = smoothstep(p_min_support, support_end, support[index]);
				r_face_seed[index] *= gate;
			}
		}
	});
}

void prune_narrow_top_lobes(
	std::vector<float> &r_top_alpha,
	int32_t p_width,
	int32_t p_height,
	int32_t p_radius,
	float p_min_support,
	float p_gate_width
) {
	if (p_radius <= 0 || p_min_support <= 0.0f) {
		return;
	}
	std::vector<float> binary(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			for (int32_t x = 0; x < p_width; ++x) {
				binary[row + x] = r_top_alpha[row + x] > 0.50f ? 1.0f : 0.0f;
			}
		}
	});
	const std::vector<float> support = box_blur(binary, p_width, p_height, p_radius);
	const float support_end = std::min(1.0f, p_min_support + std::max(p_gate_width, 0.001f));
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			const int64_t row = static_cast<int64_t>(y) * p_width;
			for (int32_t x = 0; x < p_width; ++x) {
				const int64_t index = row + x;
				if (r_top_alpha[index] <= 0.0f) {
					continue;
				}
				const float gate = smoothstep(p_min_support, support_end, support[index]);
				r_top_alpha[index] *= gate;
			}
		}
	});
}

void build_projected_face(
	const std::vector<float> &p_top_alpha,
	int32_t p_width,
	int32_t p_height,
	int32_t p_facade_samples,
	float p_side_suppression,
	float p_gate_start,
	float p_gate_end,
	int32_t p_seed_support_radius,
	float p_seed_min_support,
	int32_t p_seed_smooth_radius,
	float p_seed_gain,
	int32_t p_seed_leash_radius,
	float p_seed_leash_min_support,
	std::vector<float> &r_face_alpha,
	std::vector<float> &r_face_depth
) {
	r_face_alpha.assign(static_cast<size_t>(p_width) * p_height, 0.0f);
	r_face_depth.assign(static_cast<size_t>(p_width) * p_height, 0.0f);
	std::vector<float> face_seed(static_cast<size_t>(p_width) * p_height, 0.0f);
	parallel_for_rows(p_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			for (int32_t x = 0; x < p_width; ++x) {
				face_seed[static_cast<int64_t>(y) * p_width + x] = south_face_seed_at(
					p_top_alpha,
					p_width,
					p_height,
					x,
					y,
					p_side_suppression,
					p_gate_start,
					p_gate_end
				);
			}
		}
	});
	const std::vector<float> raw_face_seed = face_seed;
	face_seed = filter_face_seed_by_horizontal_support(
		face_seed,
		p_width,
		p_height,
		p_seed_support_radius,
		p_seed_min_support
	);
	face_seed = box_blur_horizontal(face_seed, p_width, p_height, p_seed_smooth_radius);
	leash_smoothed_face_seed(
		face_seed,
		raw_face_seed,
		p_width,
		p_height,
		p_seed_leash_radius,
		p_seed_leash_min_support
	);
	parallel_for_range(p_width, [&](int32_t p_start_x, int32_t p_end_x, int32_t) {
		std::deque<int32_t> candidates;
		for (int32_t x = p_start_x; x < p_end_x; ++x) {
			candidates.clear();
			for (int32_t y = 0; y < p_height; ++y) {
				const int32_t add_y = y - 1;
				if (add_y >= 0) {
					const float value = face_seed[static_cast<int64_t>(add_y) * p_width + x];
					if (value > 0.001f) {
						while (!candidates.empty()) {
							const int32_t back_y = candidates.back();
							const float back_value = face_seed[static_cast<int64_t>(back_y) * p_width + x];
							if (back_value >= value) {
								break;
							}
							candidates.pop_back();
						}
						candidates.push_back(add_y);
					}
				}
				const int32_t min_y = y - p_facade_samples;
				while (!candidates.empty() && candidates.front() < min_y) {
					candidates.pop_front();
				}
				const int64_t index = static_cast<int64_t>(y) * p_width + x;
				const float exposure = 1.0f - clamp01(p_top_alpha[index] * 1.15f);
				if (exposure <= 0.01f || candidates.empty()) {
					continue;
				}
				const int32_t best_y = candidates.front();
				const float best_alpha = clamp01(face_seed[static_cast<int64_t>(best_y) * p_width + x] * p_seed_gain) * exposure;
				if (best_alpha <= 0.0f) {
					continue;
				}
				r_face_alpha[index] = best_alpha;
				r_face_depth[index] = static_cast<float>(y - best_y) / static_cast<float>(p_facade_samples);
			}
		}
	});
}

float top_alpha_at(
	float p_mask_value,
	int32_t p_x,
	int32_t p_y,
	float p_render_origin_x,
	float p_render_origin_y,
	float p_center_value,
	float p_half_width,
	float p_warp_px,
	float p_warp_scale_px,
	float p_blur_radius_px
) {
	float center = p_center_value;
	if (p_warp_px > 0.0f) {
		const float edge_band = 1.0f - clamp01(std::abs(p_mask_value - center) / 0.24f);
		if (edge_band > 0.0f) {
			const float world_x = p_render_origin_x + (static_cast<float>(p_x) + 0.5f) * SAMPLE_STEP_PX;
			const float world_y = p_render_origin_y + (static_cast<float>(p_y) + 0.5f) * SAMPLE_STEP_PX;
			const float noise = value_noise(world_x, world_y, p_warp_scale_px, 907);
			center += (noise - 0.5f) * (p_warp_px / std::max(p_blur_radius_px, 1.0f)) * edge_band;
		}
	}
	return smoothstep(center - p_half_width, center + p_half_width, p_mask_value);
}

} // namespace

godot::Dictionary build_image(
	const godot::Array &p_packets,
	godot::Vector2i p_target_chunk,
	const godot::Dictionary &p_preset,
	const godot::Ref<godot::Image> &p_top_image,
	const godot::Ref<godot::Image> &p_face_image
) {
	const RasterClock::time_point total_started = RasterClock::now();
	godot::Dictionary result;
	result["ready"] = false;
	result["packet_count"] = p_packets.size();

	std::unordered_set<int64_t> mountain_keys;
	std::vector<TileCoord> mountain_tiles;
	std::vector<TileCoord> target_mountain_tiles;
	int32_t min_x = std::numeric_limits<int32_t>::max();
	int32_t min_y = std::numeric_limits<int32_t>::max();
	int32_t max_x = std::numeric_limits<int32_t>::min();
	int32_t max_y = std::numeric_limits<int32_t>::min();

	for (int32_t packet_index = 0; packet_index < p_packets.size(); ++packet_index) {
		const godot::Dictionary packet = p_packets[packet_index];
		const godot::Vector2i chunk_coord = packet.get("chunk_coord", godot::Vector2i());
		const godot::PackedInt32Array terrain_ids = packet.get("terrain_ids", godot::PackedInt32Array());
		const godot::PackedByteArray walkable_flags = packet.get("walkable_flags", godot::PackedByteArray());
		const godot::PackedByteArray mountain_flags = packet.get("mountain_flags", godot::PackedByteArray());
		const int32_t limit = std::min<int32_t>(terrain_ids.size(), CHUNK_CELL_COUNT);
		for (int32_t index = 0; index < limit; ++index) {
			const int32_t terrain_id = terrain_ids[index];
			if (!is_mountain_terrain(terrain_id)) {
				continue;
			}
			if (index < walkable_flags.size() && walkable_flags[index] != 0) {
				continue;
			}
			if (terrain_id != TERRAIN_LEGACY_BLOCKED && index < mountain_flags.size()) {
				const uint8_t flags = mountain_flags[index];
				if ((flags & (MOUNTAIN_FLAG_WALL | MOUNTAIN_FLAG_FOOT)) == 0U) {
					continue;
				}
			}
			const int32_t local_x = index % CHUNK_SIZE;
			const int32_t local_y = index / CHUNK_SIZE;
			const int32_t world_x = chunk_coord.x * CHUNK_SIZE + local_x;
			const int32_t world_y = chunk_coord.y * CHUNK_SIZE + local_y;
			const int64_t key = make_tile_key(world_x, world_y);
			if (!mountain_keys.insert(key).second) {
				continue;
			}
			mountain_tiles.push_back({ world_x, world_y });
			if (chunk_coord.x == p_target_chunk.x && chunk_coord.y == p_target_chunk.y) {
				target_mountain_tiles.push_back({ world_x, world_y });
			}
			min_x = std::min(min_x, world_x);
			min_y = std::min(min_y, world_y);
			max_x = std::max(max_x, world_x);
			max_y = std::max(max_y, world_y);
		}
	}
	const int64_t timing_collect_ms = elapsed_ms_since(total_started);

	if (mountain_tiles.empty()) {
		result["mountain_tile_count"] = 0;
		return result;
	}

	const bool runtime_mountain_only = preset_bool(p_preset, "runtime_mountain_only", false);
	const int32_t render_padding_tiles = runtime_mountain_only ?
			std::max(0, static_cast<int32_t>(std::lround(preset_float(p_preset, "runtime_padding_tiles", 1.0f)))) :
			GROUND_BACKDROP_PADDING_TILES;
	const float facade_height_px = preset_float(p_preset, "facade_height_px", 32.0f);
	const int32_t bounds_width = max_x - min_x + 1;
	const int32_t bounds_height = max_y - min_y + 1;
	int32_t render_min_x = min_x - render_padding_tiles;
	int32_t render_min_y = min_y - render_padding_tiles;
	int32_t render_max_x = max_x + render_padding_tiles;
	int32_t render_max_y = max_y + render_padding_tiles +
			static_cast<int32_t>(std::ceil(facade_height_px / static_cast<float>(TILE_SIZE_PX)));
	const bool runtime_clip_enabled = runtime_mountain_only && preset_bool(p_preset, "runtime_clip_enabled", false);
	float runtime_clip_half_width_px = 0.0f;
	float runtime_clip_half_height_px = 0.0f;
	if (runtime_clip_enabled) {
		const float clip_center_x = preset_float(p_preset, "runtime_clip_center_world_x", static_cast<float>((min_x + max_x + 1) * TILE_SIZE_PX) * 0.5f);
		const float clip_center_y = preset_float(p_preset, "runtime_clip_center_world_y", static_cast<float>((min_y + max_y + 1) * TILE_SIZE_PX) * 0.5f);
		const float clip_half_width = std::max(preset_float(p_preset, "runtime_clip_half_width_px", 1408.0f), static_cast<float>(TILE_SIZE_PX));
		const float clip_half_height = std::max(preset_float(p_preset, "runtime_clip_half_height_px", 1088.0f), static_cast<float>(TILE_SIZE_PX));
		runtime_clip_half_width_px = clip_half_width;
		runtime_clip_half_height_px = clip_half_height;
		const int32_t clip_min_x = static_cast<int32_t>(std::floor((clip_center_x - clip_half_width) / static_cast<float>(TILE_SIZE_PX)));
		const int32_t clip_max_x = static_cast<int32_t>(std::ceil((clip_center_x + clip_half_width) / static_cast<float>(TILE_SIZE_PX))) - 1;
		const int32_t clip_min_y = static_cast<int32_t>(std::floor((clip_center_y - clip_half_height - facade_height_px) / static_cast<float>(TILE_SIZE_PX)));
		const int32_t clip_max_y = static_cast<int32_t>(std::ceil((clip_center_y + clip_half_height + facade_height_px) / static_cast<float>(TILE_SIZE_PX))) - 1;
		if (clip_min_x <= render_max_x && clip_max_x >= render_min_x && clip_min_y <= render_max_y && clip_max_y >= render_min_y) {
			render_min_x = std::max(render_min_x, clip_min_x);
			render_min_y = std::max(render_min_y, clip_min_y);
			render_max_x = std::min(render_max_x, clip_max_x);
			render_max_y = std::min(render_max_y, clip_max_y);
		}
	}
	const int32_t render_tile_width = render_max_x - render_min_x + 1;
	const int32_t render_tile_height = render_max_y - render_min_y + 1;
	const float render_origin_x = static_cast<float>(render_min_x * TILE_SIZE_PX);
	const float render_origin_y = static_cast<float>(render_min_y * TILE_SIZE_PX);
	const float render_size_x = static_cast<float>(render_tile_width * TILE_SIZE_PX);
	const float render_size_y = static_cast<float>(render_tile_height * TILE_SIZE_PX) + facade_height_px;
	const int32_t image_width = static_cast<int32_t>(std::ceil(render_size_x / SAMPLE_STEP_PX));
	const int32_t image_height = static_cast<int32_t>(std::ceil(render_size_y / SAMPLE_STEP_PX));
	const int64_t total_pixels = static_cast<int64_t>(image_width) * image_height;
	const bool runtime_emit_normal_image = !runtime_mountain_only || preset_bool(p_preset, "runtime_emit_normal_image", true);
	const bool runtime_crop_visual_alpha = runtime_mountain_only && preset_bool(p_preset, "runtime_crop_visual_alpha", false);
	const bool runtime_edge_overlay_only = runtime_mountain_only && preset_bool(p_preset, "runtime_edge_overlay_only", false);
	const bool runtime_emit_top_mask = runtime_mountain_only && preset_bool(p_preset, "runtime_emit_top_mask", runtime_edge_overlay_only);
	const int32_t runtime_visual_crop_padding_px = std::max(
			0,
			static_cast<int32_t>(std::lround(preset_float(p_preset, "runtime_visual_crop_padding_px", 2.0f)))
	);
	const bool runtime_visual_clip_to_target_rect = runtime_mountain_only &&
			preset_bool(p_preset, "runtime_visual_clip_to_target_rect", false);
	const bool runtime_visual_owner_mask = runtime_mountain_only &&
			preset_bool(p_preset, "runtime_visual_owner_mask", false);
	const float runtime_visual_clip_min_world_x = preset_float(p_preset, "runtime_visual_clip_min_world_x", render_origin_x);
	const float runtime_visual_clip_min_world_y = preset_float(p_preset, "runtime_visual_clip_min_world_y", render_origin_y);
	const float runtime_visual_clip_max_world_x = preset_float(p_preset, "runtime_visual_clip_max_world_x", render_origin_x + render_size_x);
	const float runtime_visual_clip_max_world_y = preset_float(p_preset, "runtime_visual_clip_max_world_y", render_origin_y + render_size_y);
	const float runtime_visual_clip_feather_px = std::max(
			0.0f,
			preset_float(p_preset, "runtime_visual_clip_feather_px", 10.0f)
	);
	const float runtime_visual_overdraw_px = std::max(
			0.0f,
			preset_float(p_preset, "runtime_visual_overdraw_px", 0.0f)
	);
	const bool runtime_solid_top_fast_path = runtime_mountain_only &&
			preset_bool(p_preset, "runtime_solid_top_fast_path", true) &&
			is_fully_mountain_tile_rect(
				mountain_keys,
				render_min_x,
				render_min_y,
				render_max_x,
				render_max_y
			);

	if (runtime_solid_top_fast_path) {
		const ImageView top_image = image_view_from_ref(p_top_image);
		const float top_texture_scale = preset_float(p_preset, "top_texture_scale", 0.70f);
		const float top_texture_blend = preset_float(p_preset, "top_texture_blend", 0.34f);
		const float top_macro_scale_px = preset_float(p_preset, "top_macro_scale_px", 420.0f);
		const float top_macro_strength = preset_float(p_preset, "top_macro_strength", 0.10f);
		const float normal_strength = preset_float(p_preset, "normal_strength", 4.0f);
		const float normal_top_detail_strength = preset_float(p_preset, "normal_top_detail_strength", 0.72f);
		const float normal_face_detail_strength = preset_float(p_preset, "normal_face_detail_strength", 0.95f);
		const float normal_detail_scale_px = preset_float(p_preset, "normal_detail_scale_px", 18.0f);
		const float normal_macro_scale_px = preset_float(p_preset, "normal_macro_scale_px", 96.0f);
		const float hit_mask_threshold = preset_float(p_preset, "hit_mask_threshold", 0.52f);

		godot::PackedByteArray mountain_image_bytes;
		mountain_image_bytes.resize(static_cast<int32_t>(total_pixels * 4));
		uint8_t *mountain_write = mountain_image_bytes.ptrw();
		godot::PackedByteArray hit_mask;
		hit_mask.resize(static_cast<int32_t>(total_pixels));
		uint8_t *hit_write = hit_mask.ptrw();
		std::fill(hit_write, hit_write + total_pixels, static_cast<uint8_t>(1));

		std::vector<float> normal_height_field;
		std::vector<float> normal_coverage_field;
		if (runtime_emit_normal_image) {
			normal_height_field.assign(static_cast<size_t>(total_pixels), 1.0f);
			normal_coverage_field.assign(static_cast<size_t>(total_pixels), 1.0f);
		}
		const RasterClock::time_point paint_started = RasterClock::now();
		parallel_for_rows(image_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
			for (int32_t y = p_start_y; y < p_end_y; ++y) {
				for (int32_t x = 0; x < image_width; ++x) {
					const int64_t index = static_cast<int64_t>(y) * image_width + x;
					const float world_x = render_origin_x + (static_cast<float>(x) + 0.5f) * SAMPLE_STEP_PX;
					const float world_y = render_origin_y + (static_cast<float>(y) + 0.5f) * SAMPLE_STEP_PX;
					const ColorF top_color = top_color_at(
						x,
						y,
						world_x,
						world_y,
						top_image,
						top_texture_scale,
						top_texture_blend,
						top_macro_scale_px,
						top_macro_strength
					);
					write_color(mountain_write, index * 4, top_color);
					if (runtime_emit_normal_image) {
						const float detail_height = mountain_normal_detail_height_fast(
							world_x,
							world_y,
							0.0f,
							1.0f,
							0.0f,
							normal_top_detail_strength,
							normal_face_detail_strength,
							normal_detail_scale_px,
							normal_macro_scale_px
						);
						normal_height_field[index] = 1.0f + detail_height;
					}
				}
			}
		});
		const int64_t timing_paint_ms = elapsed_ms_since(paint_started);

		int64_t normal_pixel_count = 0;
		const RasterClock::time_point normal_started = RasterClock::now();
		godot::PackedByteArray normal_bytes;
		if (runtime_emit_normal_image) {
			normal_bytes = build_normal_bytes(
				normal_height_field,
				normal_coverage_field,
				image_width,
				image_height,
				normal_strength,
				normal_pixel_count
			);
		}
		const int64_t timing_normal_ms = elapsed_ms_since(normal_started);

		int32_t visual_image_width = image_width;
		int32_t visual_image_height = image_height;
		float visual_origin_x = render_origin_x;
		float visual_origin_y = render_origin_y;
		godot::PackedByteArray visual_mountain_image_bytes = mountain_image_bytes;
		bool runtime_visual_crop_applied = false;
		if (runtime_crop_visual_alpha) {
			AlphaBounds visual_bounds = rgba_alpha_bounds(mountain_image_bytes, image_width, image_height, 0);
			visual_bounds = expand_alpha_bounds(visual_bounds, image_width, image_height, runtime_visual_crop_padding_px);
			if (visual_bounds.has_pixels) {
				godot::PackedByteArray cropped_mountain_image_bytes = crop_rgba_bytes(mountain_image_bytes, image_width, visual_bounds);
				if (!cropped_mountain_image_bytes.is_empty()) {
					visual_mountain_image_bytes = cropped_mountain_image_bytes;
					visual_image_width = visual_bounds.max_x - visual_bounds.min_x + 1;
					visual_image_height = visual_bounds.max_y - visual_bounds.min_y + 1;
					visual_origin_x = render_origin_x + static_cast<float>(visual_bounds.min_x) * SAMPLE_STEP_PX;
					visual_origin_y = render_origin_y + static_cast<float>(visual_bounds.min_y) * SAMPLE_STEP_PX;
					runtime_visual_crop_applied = true;
				}
			}
		}

		result["ready"] = true;
		result["success"] = true;
		result["mountain_image"] = godot::Image::create_from_data(visual_image_width, visual_image_height, false, godot::Image::FORMAT_RGBA8, visual_mountain_image_bytes);
		if (runtime_emit_normal_image) {
			result["mountain_normal_image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, normal_bytes);
		}
		result["hit_mask"] = hit_mask;
		result["hit_mask_width"] = image_width;
		result["hit_mask_height"] = image_height;
		result["hit_mask_origin_world"] = godot::Vector2(render_origin_x, render_origin_y);
		result["hit_mask_step_px"] = SAMPLE_STEP_PX;
		result["hit_mask_threshold"] = hit_mask_threshold;
		result["hit_mask_solid_pixel_count"] = total_pixels;
		result["light_occluder_polygon"] = godot::PackedVector2Array();
		result["render_origin_world"] = godot::Vector2(visual_origin_x, visual_origin_y);
		result["render_size_world"] = godot::Vector2(
				static_cast<float>(visual_image_width) * SAMPLE_STEP_PX,
				static_cast<float>(visual_image_height) * SAMPLE_STEP_PX
		);
		result["mountain_tile_count"] = static_cast<int64_t>(mountain_tiles.size());
		result["bounds_position"] = godot::Vector2i(min_x, min_y);
		result["bounds_size"] = godot::Vector2i(bounds_width, bounds_height);
		result["sample_step_px"] = SAMPLE_STEP_PX;
		result["render_padding_tiles"] = render_padding_tiles;
		result["image_width"] = visual_image_width;
		result["image_height"] = visual_image_height;
		result["top_pixel_count"] = total_pixels;
		result["face_pixel_count"] = 0;
		result["rim_pixel_count"] = 0;
		result["normal_ready"] = runtime_emit_normal_image;
		result["normal_image_width"] = runtime_emit_normal_image ? image_width : 0;
		result["normal_image_height"] = runtime_emit_normal_image ? image_height : 0;
		result["normal_pixel_count"] = normal_pixel_count;
		result["ground_normal_pixel_count"] = 0;
		result["light_occluder_point_count"] = 0;
		result["normal_field_mode"] = "solid_top_fast_path";
		result["normal_detail_mode"] = "organic_fbm_broad_strata";
		result["normal_strength"] = normal_strength;
		result["normal_top_detail_strength"] = normal_top_detail_strength;
		result["normal_face_detail_strength"] = normal_face_detail_strength;
		result["normal_detail_scale_px"] = normal_detail_scale_px;
	result["normal_macro_scale_px"] = normal_macro_scale_px;
	result["runtime_fast_normals"] = true;
	result["facade_height_px"] = facade_height_px;
	result["top_texture_scale"] = top_texture_scale;
	result["shape_field_mode"] = "solid_top_fast_path";
		result["top_image_loaded"] = top_image.width > 0;
		result["face_image_loaded"] = image_view_from_ref(p_face_image).width > 0;
		result["runtime_mountain_only"] = runtime_mountain_only;
		result["runtime_clip_enabled"] = runtime_clip_enabled;
		result["runtime_clip_half_width_px"] = runtime_clip_half_width_px;
		result["runtime_clip_half_height_px"] = runtime_clip_half_height_px;
		result["runtime_emit_normal_image"] = runtime_emit_normal_image;
		result["runtime_crop_visual_alpha"] = runtime_crop_visual_alpha;
		result["runtime_visual_crop_applied"] = runtime_visual_crop_applied;
		result["runtime_visual_crop_padding_px"] = runtime_visual_crop_padding_px;
		result["runtime_visual_uncropped_image_width"] = image_width;
		result["runtime_visual_uncropped_image_height"] = image_height;
		result["runtime_edge_overlay_only"] = runtime_edge_overlay_only;
		result["runtime_visual_clip_to_target_rect"] = runtime_visual_clip_to_target_rect;
		result["runtime_visual_clip_feather_px"] = runtime_visual_clip_feather_px;
		result["runtime_visual_overdraw_px"] = runtime_visual_overdraw_px;
		result["runtime_solid_top_fast_path"] = true;
		result["native"] = true;
		result["timing_collect_ms"] = timing_collect_ms;
		result["timing_mask_stamp_ms"] = 0;
		result["timing_blur_ms"] = 0;
		result["timing_alpha_ms"] = 0;
		result["timing_face_project_ms"] = 0;
		result["timing_paint_ms"] = timing_paint_ms;
		result["timing_normal_ms"] = timing_normal_ms;
		result["timing_total_ms"] = elapsed_ms_since(total_started);
		return result;
	}

	const float shape_blob_radius_px = preset_float(p_preset, "shape_blob_radius_px", 76.0f);
	const float shape_domain_warp_px = preset_float(p_preset, "shape_domain_warp_px", 14.0f);
	const float shape_domain_warp_scale_px = preset_float(p_preset, "shape_domain_warp_scale_px", 288.0f);
	const float shape_lobe_px = preset_float(p_preset, "shape_lobe_px", 8.0f);
	const float shape_lobe_scale_px = preset_float(p_preset, "shape_lobe_scale_px", 168.0f);
	const RasterClock::time_point mask_started = RasterClock::now();
	std::vector<float> source_mask(static_cast<size_t>(total_pixels), 0.0f);
	for (const TileCoord &tile : mountain_tiles) {
		const float center_x = (static_cast<float>(tile.x - render_min_x) + 0.5f) * static_cast<float>(TILE_SIZE_PX);
		const float center_y = (static_cast<float>(tile.y - render_min_y) + 0.5f) * static_cast<float>(TILE_SIZE_PX);
		stamp_center_blob(source_mask, image_width, image_height, center_x, center_y, shape_blob_radius_px);
	}
	const int64_t timing_mask_stamp_ms = elapsed_ms_since(mask_started);

	const RasterClock::time_point blur_started = RasterClock::now();
	std::vector<float> smooth_mask = std::move(source_mask);
	const int32_t blur_radius = std::max(1, static_cast<int32_t>(std::lround(preset_float(p_preset, "round_blur_radius_px", 32.0f) / SAMPLE_STEP_PX)));
	for (int32_t pass_index = 0; pass_index < ROUND_BLUR_PASSES; ++pass_index) {
		smooth_mask = box_blur(smooth_mask, image_width, image_height, blur_radius);
	}
	const int64_t timing_blur_ms = elapsed_ms_since(blur_started);

	const RasterClock::time_point alpha_started = RasterClock::now();
	const float top_threshold_center = preset_float(p_preset, "top_threshold_center", 0.5f);
	const float top_threshold_half_width = std::max(preset_float(p_preset, "top_threshold_width", 0.016f) * 0.5f, 0.001f);
	const float edge_warp_px = preset_float(p_preset, "edge_warp_px", 0.0f);
	const float edge_warp_scale_px = preset_float(p_preset, "edge_warp_scale_px", 192.0f);
	const float round_blur_radius_px = preset_float(p_preset, "round_blur_radius_px", 32.0f);
	std::vector<float> organic_mask = build_organic_mask(
		smooth_mask,
		image_width,
		image_height,
		render_origin_x,
		render_origin_y,
		top_threshold_center,
		round_blur_radius_px,
		shape_domain_warp_px,
		shape_domain_warp_scale_px,
		shape_lobe_px,
		shape_lobe_scale_px
	);
	std::vector<float> top_alpha(static_cast<size_t>(total_pixels), 0.0f);
	parallel_for_rows(image_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			for (int32_t x = 0; x < image_width; ++x) {
				const int64_t index = static_cast<int64_t>(y) * image_width + x;
				top_alpha[index] = top_alpha_at(
					organic_mask[index],
					x,
					y,
					render_origin_x,
					render_origin_y,
					top_threshold_center,
					top_threshold_half_width,
					edge_warp_px,
					edge_warp_scale_px,
					round_blur_radius_px
				);
			}
		}
	});
	const int32_t top_lobe_prune_radius = std::max(
			0,
			static_cast<int32_t>(std::lround(preset_float(p_preset, "top_lobe_prune_radius_px", 0.0f) / SAMPLE_STEP_PX))
	);
	const float top_lobe_prune_min_support = std::max(0.0f, preset_float(p_preset, "top_lobe_prune_min_support", 0.0f));
	const float top_lobe_prune_gate_width = std::max(0.001f, preset_float(p_preset, "top_lobe_prune_gate_width", 0.14f));
	prune_narrow_top_lobes(
		top_alpha,
		image_width,
		image_height,
		top_lobe_prune_radius,
		top_lobe_prune_min_support,
		top_lobe_prune_gate_width
	);
	const int64_t timing_alpha_ms = elapsed_ms_since(alpha_started);

	const RasterClock::time_point face_started = RasterClock::now();
	std::vector<float> face_alpha;
	std::vector<float> face_depth;
	const int32_t facade_samples = std::max(1, static_cast<int32_t>(std::lround(facade_height_px / SAMPLE_STEP_PX)));
	const float facade_side_suppression = std::max(0.0f, preset_float(p_preset, "facade_side_suppression", 2.35f));
	const float facade_south_gate_start = clamp01(preset_float(p_preset, "facade_south_gate_start", 0.48f));
	const float facade_south_gate_end = std::max(
			facade_south_gate_start + 0.001f,
			clamp01(preset_float(p_preset, "facade_south_gate_end", 0.78f))
	);
	const int32_t facade_seed_smooth_radius = std::max(
			0,
			static_cast<int32_t>(std::lround(preset_float(p_preset, "facade_seed_smooth_radius_px", 18.0f) / SAMPLE_STEP_PX))
	);
	const int32_t facade_seed_support_radius = std::max(
			0,
			static_cast<int32_t>(std::lround(preset_float(p_preset, "facade_seed_support_radius_px", 0.0f) / SAMPLE_STEP_PX))
	);
	const float facade_seed_min_support = std::max(0.0f, preset_float(p_preset, "facade_seed_min_support", 0.0f));
	const float facade_seed_gain = std::max(0.0f, preset_float(p_preset, "facade_seed_gain", 4.0f));
	const int32_t facade_seed_leash_radius = std::max(
			0,
			static_cast<int32_t>(std::lround(preset_float(p_preset, "facade_seed_leash_radius_px", 0.0f) / SAMPLE_STEP_PX))
	);
	const float facade_seed_leash_min_support = std::max(
			0.0f,
			preset_float(p_preset, "facade_seed_leash_min_support", 0.0f)
	);
	build_projected_face(
		top_alpha,
		image_width,
		image_height,
		facade_samples,
		facade_side_suppression,
		facade_south_gate_start,
		facade_south_gate_end,
		facade_seed_support_radius,
		facade_seed_min_support,
		facade_seed_smooth_radius,
		facade_seed_gain,
		facade_seed_leash_radius,
		facade_seed_leash_min_support,
		face_alpha,
		face_depth
	);
	const int64_t timing_face_project_ms = elapsed_ms_since(face_started);

	std::vector<float> visual_owner_top_alpha;
	std::vector<float> visual_owner_face_alpha;
	bool visual_owner_mask_ready = false;
	if (runtime_visual_owner_mask && !target_mountain_tiles.empty()) {
		std::vector<float> owner_source_mask(static_cast<size_t>(total_pixels), 0.0f);
		for (const TileCoord &tile : target_mountain_tiles) {
			const float center_x = (static_cast<float>(tile.x - render_min_x) + 0.5f) * static_cast<float>(TILE_SIZE_PX);
			const float center_y = (static_cast<float>(tile.y - render_min_y) + 0.5f) * static_cast<float>(TILE_SIZE_PX);
			stamp_center_blob(owner_source_mask, image_width, image_height, center_x, center_y, shape_blob_radius_px);
		}
		std::vector<float> owner_smooth_mask = std::move(owner_source_mask);
		for (int32_t pass_index = 0; pass_index < ROUND_BLUR_PASSES; ++pass_index) {
			owner_smooth_mask = box_blur(owner_smooth_mask, image_width, image_height, blur_radius);
		}
		const std::vector<float> owner_organic_mask = build_organic_mask(
			owner_smooth_mask,
			image_width,
			image_height,
			render_origin_x,
			render_origin_y,
			top_threshold_center,
			round_blur_radius_px,
			shape_domain_warp_px,
			shape_domain_warp_scale_px,
			shape_lobe_px,
			shape_lobe_scale_px
		);
		visual_owner_top_alpha.assign(static_cast<size_t>(total_pixels), 0.0f);
		parallel_for_rows(image_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t) {
			for (int32_t y = p_start_y; y < p_end_y; ++y) {
				for (int32_t x = 0; x < image_width; ++x) {
					const int64_t index = static_cast<int64_t>(y) * image_width + x;
					visual_owner_top_alpha[index] = top_alpha_at(
						owner_organic_mask[index],
						x,
						y,
						render_origin_x,
						render_origin_y,
						top_threshold_center,
						top_threshold_half_width,
						edge_warp_px,
						edge_warp_scale_px,
						round_blur_radius_px
					);
				}
			}
		});
		std::vector<float> visual_owner_face_depth;
		build_projected_face(
			visual_owner_top_alpha,
			image_width,
			image_height,
			facade_samples,
			facade_side_suppression,
			facade_south_gate_start,
			facade_south_gate_end,
			facade_seed_support_radius,
			facade_seed_min_support,
			facade_seed_smooth_radius,
			facade_seed_gain,
			facade_seed_leash_radius,
			facade_seed_leash_min_support,
			visual_owner_face_alpha,
			visual_owner_face_depth
		);
		visual_owner_mask_ready = true;
	}

	const bool runtime_hit_mask_only = runtime_mountain_only && preset_bool(p_preset, "runtime_hit_mask_only", false);
	if (runtime_hit_mask_only) {
		const RasterClock::time_point hit_started = RasterClock::now();
		const float hit_mask_threshold = preset_float(p_preset, "hit_mask_threshold", 0.14f);
		godot::PackedByteArray hit_mask;
		hit_mask.resize(static_cast<int32_t>(total_pixels));
		uint8_t *hit_write = hit_mask.ptrw();
		const int32_t hit_worker_count = raster_worker_count(image_height);
		std::vector<int64_t> hit_counts(static_cast<size_t>(hit_worker_count), 0);
		std::vector<int64_t> top_counts(static_cast<size_t>(hit_worker_count), 0);
		std::vector<int64_t> face_counts(static_cast<size_t>(hit_worker_count), 0);
		parallel_for_rows(image_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t p_worker_index) {
			int64_t local_hit_count = 0;
			int64_t local_top_count = 0;
			int64_t local_face_count = 0;
			for (int32_t y = p_start_y; y < p_end_y; ++y) {
				for (int32_t x = 0; x < image_width; ++x) {
					const int64_t index = static_cast<int64_t>(y) * image_width + x;
					const float top_a = top_alpha[index];
					const float face_a = face_alpha[index];
					const float visual_top_a = top_a > 0.55f ? 1.0f : top_a;
					const float coverage = std::max(visual_top_a, face_a);
					if (coverage > hit_mask_threshold) {
						hit_write[index] = 1;
						++local_hit_count;
					} else {
						hit_write[index] = 0;
					}
					if (visual_top_a > 0.01f) {
						++local_top_count;
					}
					if (face_a > 0.01f) {
						++local_face_count;
					}
				}
			}
			hit_counts[static_cast<size_t>(p_worker_index)] = local_hit_count;
			top_counts[static_cast<size_t>(p_worker_index)] = local_top_count;
			face_counts[static_cast<size_t>(p_worker_index)] = local_face_count;
		});
		int64_t hit_mask_solid_pixel_count = 0;
		int64_t top_pixel_count = 0;
		int64_t face_pixel_count = 0;
		for (size_t index = 0; index < hit_counts.size(); ++index) {
			hit_mask_solid_pixel_count += hit_counts[index];
			top_pixel_count += top_counts[index];
			face_pixel_count += face_counts[index];
		}
		const int64_t timing_hit_ms = elapsed_ms_since(hit_started);

		result["ready"] = true;
		result["success"] = true;
		result["hit_mask"] = hit_mask;
		result["hit_mask_width"] = image_width;
		result["hit_mask_height"] = image_height;
		result["hit_mask_origin_world"] = godot::Vector2(render_origin_x, render_origin_y);
		result["hit_mask_step_px"] = SAMPLE_STEP_PX;
		result["hit_mask_threshold"] = hit_mask_threshold;
		result["hit_mask_solid_pixel_count"] = hit_mask_solid_pixel_count;
		result["render_origin_world"] = godot::Vector2(render_origin_x, render_origin_y);
		result["render_size_world"] = godot::Vector2(render_size_x, render_size_y);
		result["mountain_tile_count"] = static_cast<int64_t>(mountain_tiles.size());
		result["bounds_position"] = godot::Vector2i(min_x, min_y);
		result["bounds_size"] = godot::Vector2i(bounds_width, bounds_height);
		result["sample_step_px"] = SAMPLE_STEP_PX;
		result["render_padding_tiles"] = render_padding_tiles;
		result["image_width"] = image_width;
		result["image_height"] = image_height;
		result["top_pixel_count"] = top_pixel_count;
		result["face_pixel_count"] = face_pixel_count;
		result["rim_pixel_count"] = 0;
		result["normal_ready"] = false;
		result["normal_pixel_count"] = 0;
		result["light_occluder_point_count"] = 0;
		result["runtime_mountain_only"] = runtime_mountain_only;
		result["runtime_hit_mask_only"] = true;
		result["runtime_clip_enabled"] = runtime_clip_enabled;
		result["runtime_clip_half_width_px"] = runtime_clip_half_width_px;
		result["runtime_clip_half_height_px"] = runtime_clip_half_height_px;
		result["facade_projection_mode"] = "south_edge_seed";
		result["facade_side_suppression"] = facade_side_suppression;
		result["facade_south_gate_start"] = facade_south_gate_start;
		result["facade_south_gate_end"] = facade_south_gate_end;
		result["facade_seed_support_radius"] = facade_seed_support_radius;
		result["facade_seed_min_support"] = facade_seed_min_support;
		result["facade_seed_smooth_radius"] = facade_seed_smooth_radius;
		result["facade_seed_gain"] = facade_seed_gain;
		result["facade_seed_leash_radius"] = facade_seed_leash_radius;
		result["facade_seed_leash_min_support"] = facade_seed_leash_min_support;
		result["top_lobe_prune_radius"] = top_lobe_prune_radius;
		result["top_lobe_prune_min_support"] = top_lobe_prune_min_support;
		result["top_lobe_prune_gate_width"] = top_lobe_prune_gate_width;
		result["native"] = true;
		result["timing_collect_ms"] = timing_collect_ms;
		result["timing_mask_stamp_ms"] = timing_mask_stamp_ms;
		result["timing_blur_ms"] = timing_blur_ms;
		result["timing_alpha_ms"] = timing_alpha_ms;
		result["timing_face_project_ms"] = timing_face_project_ms;
		result["timing_paint_ms"] = timing_hit_ms;
		result["timing_normal_ms"] = 0;
		result["timing_total_ms"] = elapsed_ms_since(total_started);
		return result;
	}

	const ImageView top_image = image_view_from_ref(p_top_image);
	const ImageView face_image = image_view_from_ref(p_face_image);
	const float rim_center = preset_float(p_preset, "rim_threshold_center", 0.68f);
	const float rim_half_width = std::max(preset_float(p_preset, "rim_threshold_width", 0.02f) * 0.5f, 0.001f);
	const float rim_strength = preset_float(p_preset, "rim_strength", 0.92f);
	const float rim_light_strength = preset_float(p_preset, "rim_light_strength", 0.16f);
	const float outline_strength = preset_float(p_preset, "outline_strength", 0.85f);
	const float top_texture_scale = preset_float(p_preset, "top_texture_scale", 0.70f);
	const float top_texture_blend = preset_float(p_preset, "top_texture_blend", 0.34f);
	const float top_macro_scale_px = preset_float(p_preset, "top_macro_scale_px", 420.0f);
	const float top_macro_strength = preset_float(p_preset, "top_macro_strength", 0.10f);
	const float face_texture_scale = preset_float(p_preset, "face_texture_scale", 0.46f);
	const float face_texture_blend = preset_float(p_preset, "face_texture_blend", 0.42f);
	const float face_darkening = preset_float(p_preset, "face_darkening", 0.18f);
	const float normal_strength = preset_float(p_preset, "normal_strength", 4.0f);
	const float normal_top_detail_strength = preset_float(p_preset, "normal_top_detail_strength", 0.72f);
	const float normal_face_detail_strength = preset_float(p_preset, "normal_face_detail_strength", 0.95f);
	const float normal_detail_scale_px = preset_float(p_preset, "normal_detail_scale_px", 18.0f);
	const float normal_macro_scale_px = preset_float(p_preset, "normal_macro_scale_px", 96.0f);
	const bool runtime_fast_normals = runtime_mountain_only && preset_bool(p_preset, "runtime_fast_normals", true);
	const float hit_mask_threshold = preset_float(p_preset, "hit_mask_threshold", 0.14f);
	const bool emit_ground_surface = !runtime_mountain_only || preset_bool(p_preset, "runtime_ground_patch", false);
	const bool emit_ground_normal_surface = emit_ground_surface && !runtime_mountain_only;
	const bool emit_mountain_normal_surface = runtime_emit_normal_image;

	godot::PackedByteArray image_bytes;
	uint8_t *write = nullptr;
	if (!runtime_mountain_only) {
		image_bytes.resize(static_cast<int32_t>(total_pixels * 4));
		write = image_bytes.ptrw();
	}
	godot::PackedByteArray ground_image_bytes;
	uint8_t *ground_write = nullptr;
	if (emit_ground_surface) {
		ground_image_bytes.resize(static_cast<int32_t>(total_pixels * 4));
		ground_write = ground_image_bytes.ptrw();
	}
	godot::PackedByteArray mountain_image_bytes;
	mountain_image_bytes.resize(static_cast<int32_t>(total_pixels * 4));
	uint8_t *mountain_write = mountain_image_bytes.ptrw();
	godot::PackedByteArray hit_mask;
	hit_mask.resize(static_cast<int32_t>(total_pixels));
	uint8_t *hit_write = hit_mask.ptrw();
	godot::PackedByteArray top_mask;
	uint8_t *top_mask_write = nullptr;
	if (runtime_emit_top_mask) {
		top_mask.resize(static_cast<int32_t>(total_pixels));
		top_mask_write = top_mask.ptrw();
	}
	int64_t hit_mask_solid_pixel_count = 0;
	std::vector<float> normal_height_field;
	std::vector<float> normal_coverage_field;
	if (emit_mountain_normal_surface) {
		normal_height_field.assign(static_cast<size_t>(total_pixels), 0.0f);
		normal_coverage_field.assign(static_cast<size_t>(total_pixels), 0.0f);
	}
	std::vector<float> ground_normal_height_field;
	std::vector<float> ground_normal_coverage_field;
	if (emit_ground_normal_surface) {
		ground_normal_height_field.assign(static_cast<size_t>(total_pixels), 0.0f);
		ground_normal_coverage_field.assign(static_cast<size_t>(total_pixels), 1.0f);
	}
	int64_t top_pixel_count = 0;
	int64_t face_pixel_count = 0;
	int64_t rim_pixel_count = 0;
	const int32_t pixel_worker_count = raster_worker_count(image_height);
	std::vector<int64_t> hit_counts(static_cast<size_t>(pixel_worker_count), 0);
	std::vector<int64_t> top_counts(static_cast<size_t>(pixel_worker_count), 0);
	std::vector<int64_t> face_counts(static_cast<size_t>(pixel_worker_count), 0);
	std::vector<int64_t> rim_counts(static_cast<size_t>(pixel_worker_count), 0);
	const RasterClock::time_point paint_started = RasterClock::now();
	parallel_for_rows(image_height, [&](int32_t p_start_y, int32_t p_end_y, int32_t p_worker_index) {
		int64_t local_hit_count = 0;
		int64_t local_top_count = 0;
		int64_t local_face_count = 0;
		int64_t local_rim_count = 0;
		for (int32_t y = p_start_y; y < p_end_y; ++y) {
			for (int32_t x = 0; x < image_width; ++x) {
			const int64_t index = static_cast<int64_t>(y) * image_width + x;
			const float world_x = render_origin_x + (static_cast<float>(x) + 0.5f) * SAMPLE_STEP_PX;
			const float world_y = render_origin_y + (static_cast<float>(y) + 0.5f) * SAMPLE_STEP_PX;
			float visual_clip_alpha = 1.0f;
			float overlay_clip_alpha = 1.0f;
			if (runtime_visual_clip_to_target_rect) {
				if (world_x < runtime_visual_clip_min_world_x ||
						world_x >= runtime_visual_clip_max_world_x ||
						world_y < runtime_visual_clip_min_world_y ||
						world_y >= runtime_visual_clip_max_world_y) {
					visual_clip_alpha = 0.0f;
				} else if (runtime_visual_clip_feather_px > 0.0f) {
					const float distance_to_clip_edge = std::min(
							std::min(world_x - runtime_visual_clip_min_world_x, runtime_visual_clip_max_world_x - world_x),
							std::min(world_y - runtime_visual_clip_min_world_y, runtime_visual_clip_max_world_y - world_y)
					);
					visual_clip_alpha = smoothstep(0.0f, runtime_visual_clip_feather_px, distance_to_clip_edge);
				}
				const float overlay_min_x = runtime_visual_clip_min_world_x - runtime_visual_overdraw_px;
				const float overlay_min_y = runtime_visual_clip_min_world_y - runtime_visual_overdraw_px;
				const float overlay_max_x = runtime_visual_clip_max_world_x + runtime_visual_overdraw_px;
				const float overlay_max_y = runtime_visual_clip_max_world_y + runtime_visual_overdraw_px;
				if (world_x < overlay_min_x ||
						world_x >= overlay_max_x ||
						world_y < overlay_min_y ||
						world_y >= overlay_max_y) {
					overlay_clip_alpha = 0.0f;
				}
			}
			const bool in_visual_clip = visual_clip_alpha > 0.001f;
			const bool in_overlay_clip = overlay_clip_alpha > 0.001f;
			ColorF ground_color;
			ColorF color;
			const int32_t world_tile_x = static_cast<int32_t>(std::floor(world_x / static_cast<float>(TILE_SIZE_PX)));
			const int32_t world_tile_y = static_cast<int32_t>(std::floor(world_y / static_cast<float>(TILE_SIZE_PX)));
			const bool in_mountain_tile_footprint = mountain_keys.find(make_tile_key(world_tile_x, world_tile_y)) != mountain_keys.end();
			if (emit_ground_surface) {
				ground_color = ground_color_at(x, y, world_x, world_y);
				if (runtime_mountain_only && !in_mountain_tile_footprint) {
					ground_color.a = 0.0f;
				}
				if (emit_ground_normal_surface) {
					ground_normal_height_field[index] = ground_normal_height(world_x, world_y);
				}
			}
			if (!runtime_mountain_only) {
				color = ground_color;
			}
			ColorF mountain_color = { 0.0f, 0.0f, 0.0f, 0.0f };
			const float face_a = face_alpha[index];
			const float top_a = top_alpha[index];
			const float visual_top_a = top_a > 0.55f ? 1.0f : top_a;
			const float top_owner_alpha = runtime_visual_owner_mask ?
					(visual_owner_mask_ready ? visual_owner_top_alpha[static_cast<size_t>(index)] : 0.0f) :
					1.0f;
			const float face_owner_alpha = runtime_visual_owner_mask ?
					(visual_owner_mask_ready ? visual_owner_face_alpha[static_cast<size_t>(index)] : 0.0f) :
					1.0f;
			const float clipped_top_alpha = visual_top_a * overlay_clip_alpha * top_owner_alpha;
			const float clipped_face_alpha = face_a * visual_clip_alpha * face_owner_alpha;
			const float coverage = std::max(visual_top_a, face_a);
			const float hit_coverage = runtime_mountain_only ?
					std::max(clipped_top_alpha, clipped_face_alpha) :
					coverage;
			if (runtime_emit_top_mask) {
				top_mask_write[index] = in_overlay_clip ? float_to_u8(clipped_top_alpha) : 0;
			}
			if (hit_coverage > hit_mask_threshold) {
				hit_write[index] = 1;
				++local_hit_count;
			} else {
				hit_write[index] = 0;
			}
			if (coverage > 0.01f) {
				if (emit_mountain_normal_surface) {
					const float total_weight = std::max(visual_top_a + face_a, 0.001f);
					const float top_weight = visual_top_a / total_weight;
					const float face_weight = face_a / total_weight;
					const float top_height = visual_top_a * (0.80f + organic_mask[index] * 0.20f);
					const float face_height = face_a * (0.18f + (1.0f - clamp01(face_depth[index])) * 0.58f);
					const float detail_height = runtime_fast_normals ?
							mountain_normal_detail_height_fast(
								world_x,
								world_y,
								face_depth[index],
								top_weight,
								face_weight,
								normal_top_detail_strength,
								normal_face_detail_strength,
								normal_detail_scale_px,
								normal_macro_scale_px
							) :
							mountain_normal_detail_height(
								world_x,
								world_y,
								face_depth[index],
								top_weight,
								face_weight,
								normal_top_detail_strength,
								normal_face_detail_strength,
								normal_detail_scale_px,
								normal_macro_scale_px
							);
					normal_height_field[index] = std::max(top_height, face_height) + detail_height * coverage;
					normal_coverage_field[index] = coverage;
				}
			}
			if (in_visual_clip && clipped_face_alpha > 0.01f) {
				++local_face_count;
				const ColorF face_color = face_color_at(world_x, world_y, face_depth[index], face_image, face_texture_scale, face_texture_blend, face_darkening);
				mountain_color = source_over(mountain_color, face_color, clipped_face_alpha);
				if (!runtime_mountain_only) {
					color = blend(color, face_color, clipped_face_alpha);
				}
			}
			if (in_overlay_clip && clipped_top_alpha > 0.01f) {
				++local_top_count;
				if (!runtime_edge_overlay_only) {
					const ColorF top_color = top_color_at(x, y, world_x, world_y, top_image, top_texture_scale, top_texture_blend, top_macro_scale_px, top_macro_strength);
					mountain_color = source_over(mountain_color, top_color, clipped_top_alpha);
					if (!runtime_mountain_only) {
						color = blend(
							color,
							top_color,
							clipped_top_alpha
						);
					}
				}
				const float inner_alpha = smoothstep(rim_center - rim_half_width, rim_center + rim_half_width, organic_mask[index]);
				const float rim_alpha = clamp01(visual_top_a - inner_alpha);
				if (rim_alpha > 0.02f) {
					++local_rim_count;
					mountain_color = source_over(mountain_color, RIM_COLOR, rim_alpha * rim_strength * overlay_clip_alpha * top_owner_alpha);
					if (!runtime_mountain_only) {
						color = blend(color, RIM_COLOR, rim_alpha * rim_strength * overlay_clip_alpha * top_owner_alpha);
					}
				}
				const float rim_light = std::max(0.0f, inner_alpha - smoothstep(0.76f, 0.90f, organic_mask[index]));
				mountain_color = source_over(mountain_color, RIM_LIGHT_COLOR, rim_light * rim_light_strength * overlay_clip_alpha * top_owner_alpha);
				if (!runtime_mountain_only) {
					color = blend(color, RIM_LIGHT_COLOR, rim_light * rim_light_strength * overlay_clip_alpha * top_owner_alpha);
				}
			}
			const float current_face = face_alpha[index];
			if (in_visual_clip && clipped_face_alpha > 0.01f) {
				const float below = y + 1 < image_height ? face_alpha[static_cast<int64_t>(y + 1) * image_width + x] : 0.0f;
				const float bottom_outline_alpha = std::max(0.0f, std::min(outline_strength, (current_face - below) * 2.8f));
				if (bottom_outline_alpha > 0.01f) {
					mountain_color = source_over(mountain_color, OUTLINE_COLOR, bottom_outline_alpha * visual_clip_alpha * face_owner_alpha);
					if (!runtime_mountain_only) {
						color = blend(color, OUTLINE_COLOR, bottom_outline_alpha * visual_clip_alpha * face_owner_alpha);
					}
				}
			}
			if (!runtime_mountain_only) {
				write_color(write, index * 4, color);
			}
			if (emit_ground_surface) {
				write_color(ground_write, index * 4, ground_color);
			}
			write_color(mountain_write, index * 4, mountain_color);
			}
		}
		hit_counts[static_cast<size_t>(p_worker_index)] = local_hit_count;
		top_counts[static_cast<size_t>(p_worker_index)] = local_top_count;
		face_counts[static_cast<size_t>(p_worker_index)] = local_face_count;
		rim_counts[static_cast<size_t>(p_worker_index)] = local_rim_count;
	});
	for (size_t index = 0; index < hit_counts.size(); ++index) {
		hit_mask_solid_pixel_count += hit_counts[index];
		top_pixel_count += top_counts[index];
		face_pixel_count += face_counts[index];
		rim_pixel_count += rim_counts[index];
	}
	const int64_t timing_paint_ms = elapsed_ms_since(paint_started);
	int64_t normal_pixel_count = 0;
	const RasterClock::time_point normal_started = RasterClock::now();
	godot::PackedByteArray normal_bytes;
	if (emit_mountain_normal_surface) {
		normal_bytes = build_normal_bytes(
			normal_height_field,
			normal_coverage_field,
			image_width,
			image_height,
			normal_strength,
			normal_pixel_count
		);
	}
	const int64_t timing_normal_ms = elapsed_ms_since(normal_started);
	int64_t ground_normal_pixel_count = 0;
	godot::PackedByteArray ground_normal_bytes;
	if (emit_ground_normal_surface) {
		ground_normal_bytes = build_normal_bytes(
			ground_normal_height_field,
			ground_normal_coverage_field,
			image_width,
			image_height,
			1.75f,
			ground_normal_pixel_count
		);
	}
	godot::PackedVector2Array light_occluder_polygon = build_radial_occluder_polygon(
		top_alpha,
		image_width,
		image_height,
		render_origin_x,
		render_origin_y
	);

	int32_t visual_image_width = image_width;
	int32_t visual_image_height = image_height;
	float visual_origin_x = render_origin_x;
	float visual_origin_y = render_origin_y;
	godot::PackedByteArray visual_mountain_image_bytes = mountain_image_bytes;
	bool runtime_visual_crop_applied = false;
	if (runtime_crop_visual_alpha) {
		AlphaBounds visual_bounds = rgba_alpha_bounds(mountain_image_bytes, image_width, image_height, 0);
		visual_bounds = expand_alpha_bounds(visual_bounds, image_width, image_height, runtime_visual_crop_padding_px);
		if (visual_bounds.has_pixels) {
			godot::PackedByteArray cropped_mountain_image_bytes = crop_rgba_bytes(mountain_image_bytes, image_width, visual_bounds);
			if (!cropped_mountain_image_bytes.is_empty()) {
				visual_mountain_image_bytes = cropped_mountain_image_bytes;
				visual_image_width = visual_bounds.max_x - visual_bounds.min_x + 1;
				visual_image_height = visual_bounds.max_y - visual_bounds.min_y + 1;
				visual_origin_x = render_origin_x + static_cast<float>(visual_bounds.min_x) * SAMPLE_STEP_PX;
				visual_origin_y = render_origin_y + static_cast<float>(visual_bounds.min_y) * SAMPLE_STEP_PX;
				runtime_visual_crop_applied = true;
			}
		}
	}

	result["ready"] = true;
	result["success"] = true;
	if (!runtime_mountain_only) {
		result["image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, image_bytes);
	}
	if (!runtime_mountain_only) {
		result["normal_image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, normal_bytes);
	}
	if (emit_ground_surface) {
		result["ground_image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, ground_image_bytes);
	}
	if (emit_ground_normal_surface) {
		result["ground_normal_image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, ground_normal_bytes);
	}
	result["mountain_image"] = godot::Image::create_from_data(visual_image_width, visual_image_height, false, godot::Image::FORMAT_RGBA8, visual_mountain_image_bytes);
	if (emit_mountain_normal_surface) {
		result["mountain_normal_image"] = godot::Image::create_from_data(image_width, image_height, false, godot::Image::FORMAT_RGBA8, normal_bytes);
	}
	result["hit_mask"] = hit_mask;
	result["hit_mask_width"] = image_width;
	result["hit_mask_height"] = image_height;
	result["hit_mask_origin_world"] = godot::Vector2(render_origin_x, render_origin_y);
	result["hit_mask_step_px"] = SAMPLE_STEP_PX;
	result["hit_mask_threshold"] = hit_mask_threshold;
	result["hit_mask_solid_pixel_count"] = hit_mask_solid_pixel_count;
	if (runtime_emit_top_mask) {
		result["top_mask"] = top_mask;
		result["top_mask_width"] = image_width;
		result["top_mask_height"] = image_height;
		result["top_mask_origin_world"] = godot::Vector2(render_origin_x, render_origin_y);
		result["top_mask_step_px"] = SAMPLE_STEP_PX;
	}
	result["light_occluder_polygon"] = light_occluder_polygon;
	result["render_origin_world"] = godot::Vector2(visual_origin_x, visual_origin_y);
	result["render_size_world"] = godot::Vector2(
			static_cast<float>(visual_image_width) * SAMPLE_STEP_PX,
			static_cast<float>(visual_image_height) * SAMPLE_STEP_PX
	);
	result["mountain_tile_count"] = static_cast<int64_t>(mountain_tiles.size());
	result["target_mountain_tile_count"] = static_cast<int64_t>(target_mountain_tiles.size());
	result["bounds_position"] = godot::Vector2i(min_x, min_y);
	result["bounds_size"] = godot::Vector2i(bounds_width, bounds_height);
	result["sample_step_px"] = SAMPLE_STEP_PX;
	result["render_padding_tiles"] = render_padding_tiles;
	result["image_width"] = visual_image_width;
	result["image_height"] = visual_image_height;
	result["top_pixel_count"] = top_pixel_count;
	result["face_pixel_count"] = face_pixel_count;
	result["rim_pixel_count"] = rim_pixel_count;
	result["normal_ready"] = emit_mountain_normal_surface;
	result["normal_image_width"] = emit_mountain_normal_surface ? image_width : 0;
	result["normal_image_height"] = emit_mountain_normal_surface ? image_height : 0;
	result["normal_pixel_count"] = normal_pixel_count;
	result["ground_normal_pixel_count"] = ground_normal_pixel_count;
	result["light_occluder_point_count"] = light_occluder_polygon.size();
	result["normal_field_mode"] = "heightfield_world_noise";
	result["normal_detail_mode"] = "organic_fbm_broad_strata";
	result["normal_strength"] = normal_strength;
	result["normal_top_detail_strength"] = normal_top_detail_strength;
	result["normal_face_detail_strength"] = normal_face_detail_strength;
	result["normal_detail_scale_px"] = normal_detail_scale_px;
	result["normal_macro_scale_px"] = normal_macro_scale_px;
	result["runtime_fast_normals"] = runtime_fast_normals;
	result["facade_height_px"] = facade_height_px;
	result["top_texture_scale"] = top_texture_scale;
	result["shape_field_mode"] = "center_blob_domain_warp";
	result["shape_blob_radius_px"] = shape_blob_radius_px;
	result["shape_domain_warp_px"] = shape_domain_warp_px;
	result["shape_domain_warp_scale_px"] = shape_domain_warp_scale_px;
	result["shape_lobe_px"] = shape_lobe_px;
	result["shape_lobe_scale_px"] = shape_lobe_scale_px;
	result["facade_projection_mode"] = "south_edge_seed";
	result["facade_side_suppression"] = facade_side_suppression;
	result["facade_south_gate_start"] = facade_south_gate_start;
	result["facade_south_gate_end"] = facade_south_gate_end;
	result["facade_seed_support_radius"] = facade_seed_support_radius;
	result["facade_seed_min_support"] = facade_seed_min_support;
	result["facade_seed_smooth_radius"] = facade_seed_smooth_radius;
	result["facade_seed_gain"] = facade_seed_gain;
	result["facade_seed_leash_radius"] = facade_seed_leash_radius;
	result["facade_seed_leash_min_support"] = facade_seed_leash_min_support;
	result["top_lobe_prune_radius"] = top_lobe_prune_radius;
	result["top_lobe_prune_min_support"] = top_lobe_prune_min_support;
	result["top_lobe_prune_gate_width"] = top_lobe_prune_gate_width;
	result["top_image_loaded"] = top_image.width > 0;
	result["face_image_loaded"] = face_image.width > 0;
	result["runtime_mountain_only"] = runtime_mountain_only;
	result["runtime_clip_enabled"] = runtime_clip_enabled;
	result["runtime_clip_half_width_px"] = runtime_clip_half_width_px;
	result["runtime_clip_half_height_px"] = runtime_clip_half_height_px;
	result["runtime_emit_normal_image"] = runtime_emit_normal_image;
	result["runtime_emit_top_mask"] = runtime_emit_top_mask;
	result["runtime_crop_visual_alpha"] = runtime_crop_visual_alpha;
	result["runtime_visual_crop_applied"] = runtime_visual_crop_applied;
	result["runtime_visual_crop_padding_px"] = runtime_visual_crop_padding_px;
	result["runtime_visual_uncropped_image_width"] = image_width;
	result["runtime_visual_uncropped_image_height"] = image_height;
	result["runtime_edge_overlay_only"] = runtime_edge_overlay_only;
	result["runtime_visual_clip_to_target_rect"] = runtime_visual_clip_to_target_rect;
	result["runtime_visual_owner_mask"] = runtime_visual_owner_mask;
	result["runtime_visual_clip_feather_px"] = runtime_visual_clip_feather_px;
	result["runtime_visual_overdraw_px"] = runtime_visual_overdraw_px;
	result["native"] = true;
	result["timing_collect_ms"] = timing_collect_ms;
	result["timing_mask_stamp_ms"] = timing_mask_stamp_ms;
	result["timing_blur_ms"] = timing_blur_ms;
	result["timing_alpha_ms"] = timing_alpha_ms;
	result["timing_face_project_ms"] = timing_face_project_ms;
	result["timing_paint_ms"] = timing_paint_ms;
	result["timing_normal_ms"] = timing_normal_ms;
	result["timing_total_ms"] = elapsed_ms_since(total_started);
	return result;
}

} // namespace mountain_plateau_raster
