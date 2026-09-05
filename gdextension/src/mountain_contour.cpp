#include "mountain_contour.h"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <vector>

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace mountain_contour {
namespace {

struct ContourPoint {
	float x = 0.0f;
	float y = 0.0f;
};

ContourPoint midpoint(ContourPoint p_a, ContourPoint p_b) {
	return {
		(p_a.x + p_b.x) * 0.5f,
		(p_a.y + p_b.y) * 0.5f,
	};
}

float clamp_coord(float p_value, float p_max) {
	return std::max(0.0f, std::min(p_value, p_max));
}

bool read_solid(const godot::PackedByteArray &p_solid_halo, int32_t p_side, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_side || p_y >= p_side) {
		return false;
	}
	const int32_t index = p_y * p_side + p_x;
	return index >= 0 && index < p_solid_halo.size() && p_solid_halo[index] != 0;
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float smooth_float(float p_t) {
	const float t = std::max(0.0f, std::min(1.0f, p_t));
	return t * t * (3.0f - 2.0f * t);
}

float sample_grid_bilinear(const std::vector<float> &p_values, int32_t p_width, int32_t p_height, float p_x, float p_y) {
	const float x = std::max(0.0f, std::min(p_x, static_cast<float>(p_width - 1)));
	const float y = std::max(0.0f, std::min(p_y, static_cast<float>(p_height - 1)));
	const int32_t x0 = static_cast<int32_t>(std::floor(x));
	const int32_t y0 = static_cast<int32_t>(std::floor(y));
	const int32_t x1 = std::min(p_width - 1, x0 + 1);
	const int32_t y1 = std::min(p_height - 1, y0 + 1);
	const float tx = x - static_cast<float>(x0);
	const float ty = y - static_cast<float>(y0);
	const float a = p_values[static_cast<size_t>(y0 * p_width + x0)];
	const float b = p_values[static_cast<size_t>(y0 * p_width + x1)];
	const float c = p_values[static_cast<size_t>(y1 * p_width + x0)];
	const float d = p_values[static_cast<size_t>(y1 * p_width + x1)];
	return lerp_float(lerp_float(a, b, tx), lerp_float(c, d, tx), ty);
}

float hash_float(int32_t p_x, int32_t p_y) {
	uint32_t value = static_cast<uint32_t>(p_x) * 0x8da6b343U;
	value ^= static_cast<uint32_t>(p_y) * 0xd8163841U;
	value ^= value >> 13U;
	value *= 0x6c50b47cU;
	value ^= value >> 16U;
	return static_cast<float>(value & 0x00ffffffU) / static_cast<float>(0x00ffffffU);
}

float value_noise(float p_x, float p_y) {
	const int32_t ix = static_cast<int32_t>(std::floor(p_x));
	const int32_t iy = static_cast<int32_t>(std::floor(p_y));
	const float fx = p_x - static_cast<float>(ix);
	const float fy = p_y - static_cast<float>(iy);
	const float sx = smooth_float(fx);
	const float sy = smooth_float(fy);
	const float a = hash_float(ix, iy);
	const float b = hash_float(ix + 1, iy);
	const float c = hash_float(ix, iy + 1);
	const float d = hash_float(ix + 1, iy + 1);
	return lerp_float(
		lerp_float(a, b, sx),
		lerp_float(c, d, sx),
		sy
	);
}

float fbm_noise(float p_x, float p_y) {
	float value = 0.0f;
	float amplitude = 0.55f;
	float frequency = 1.0f;
	float total = 0.0f;
	for (int32_t octave = 0; octave < 4; ++octave) {
		value += value_noise(p_x * frequency, p_y * frequency) * amplitude;
		total += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.03f;
	}
	return total > 0.0f ? value / total : 0.5f;
}

std::vector<float> build_blurred_solid_field(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_halo_side,
	int32_t p_pixels_per_tile,
	int32_t p_width,
	int32_t p_height,
	int32_t p_blur_radius,
	int32_t p_origin_x = 0,
	int32_t p_origin_y = 0,
	int32_t p_full_width = 0,
	int32_t p_full_height = 0
) {
	if (p_full_width <= 0) {
		p_full_width = p_width;
	}
	if (p_full_height <= 0) {
		p_full_height = p_height;
	}
	const int32_t pixel_count = p_width * p_height;
	std::vector<float> field(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> temp(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> blurred(static_cast<size_t>(pixel_count), 0.0f);
	for (int32_t py = 0; py < p_height; ++py) {
		const int32_t global_y = std::max(0, std::min(p_full_height - 1, p_origin_y + py));
		const int32_t tile_y = std::max(0, std::min(p_halo_side - 1, global_y / p_pixels_per_tile));
		for (int32_t px = 0; px < p_width; ++px) {
			const int32_t global_x = std::max(0, std::min(p_full_width - 1, p_origin_x + px));
			const int32_t tile_x = std::max(0, std::min(p_halo_side - 1, global_x / p_pixels_per_tile));
			field[static_cast<size_t>(py * p_width + px)] =
					read_solid(p_solid_halo, p_halo_side, tile_x, tile_y) ? 1.0f : 0.0f;
		}
	}

	for (int32_t pass = 0; pass < 3; ++pass) {
		const std::vector<float> &src_h = pass == 0 ? field : blurred;
		for (int32_t y = 0; y < p_height; ++y) {
			float sum = 0.0f;
			for (int32_t x = -p_blur_radius; x <= p_blur_radius; ++x) {
				const int32_t sample_x = std::max(0, std::min(p_width - 1, x));
				sum += src_h[static_cast<size_t>(y * p_width + sample_x)];
			}
			for (int32_t x = 0; x < p_width; ++x) {
				temp[static_cast<size_t>(y * p_width + x)] =
						sum / static_cast<float>(p_blur_radius * 2 + 1);
				const int32_t remove_x = std::max(0, std::min(p_width - 1, x - p_blur_radius));
				const int32_t add_x = std::max(0, std::min(p_width - 1, x + p_blur_radius + 1));
				sum += src_h[static_cast<size_t>(y * p_width + add_x)];
				sum -= src_h[static_cast<size_t>(y * p_width + remove_x)];
			}
		}
		for (int32_t x = 0; x < p_width; ++x) {
			float sum = 0.0f;
			for (int32_t y = -p_blur_radius; y <= p_blur_radius; ++y) {
				const int32_t sample_y = std::max(0, std::min(p_height - 1, y));
				sum += temp[static_cast<size_t>(sample_y * p_width + x)];
			}
			for (int32_t y = 0; y < p_height; ++y) {
				blurred[static_cast<size_t>(y * p_width + x)] =
						sum / static_cast<float>(p_blur_radius * 2 + 1);
				const int32_t remove_y = std::max(0, std::min(p_height - 1, y - p_blur_radius));
				const int32_t add_y = std::max(0, std::min(p_height - 1, y + p_blur_radius + 1));
				sum += temp[static_cast<size_t>(add_y * p_width + x)];
				sum -= temp[static_cast<size_t>(remove_y * p_width + x)];
			}
		}
	}
	return blurred;
}

void write_organic_mask_region(
	uint8_t *p_bytes_write,
	const std::vector<float> &p_blurred,
	int32_t p_width,
	int32_t p_height,
	int32_t p_blurred_width,
	int32_t p_blurred_height,
	int32_t p_blurred_origin_x,
	int32_t p_blurred_origin_y,
	int32_t p_pixels_per_tile,
	float p_step_px,
	float p_origin_world_x,
	float p_origin_world_y,
	int32_t p_min_x,
	int32_t p_min_y,
	int32_t p_max_x,
	int32_t p_max_y
) {
	for (int32_t py = p_min_y; py < p_max_y; ++py) {
		const float world_y = p_origin_world_y + (static_cast<float>(py) + 0.5f) * p_step_px;
		for (int32_t px = p_min_x; px < p_max_x; ++px) {
			const float world_x = p_origin_world_x + (static_cast<float>(px) + 0.5f) * p_step_px;
			const float broad = fbm_noise((world_x - 173.0f) / 420.0f, (world_y + 211.0f) / 420.0f);
			const float macro = fbm_noise(world_x / 220.0f, world_y / 220.0f);
			const float fine = fbm_noise((world_x + 91.0f) / 104.0f, (world_y - 37.0f) / 104.0f);
			const float disp_x = ((fbm_noise((world_x + 43.0f) / 360.0f, (world_y - 139.0f) / 360.0f) - 0.5f) * static_cast<float>(p_pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x - 211.0f) / 170.0f, (world_y + 79.0f) / 170.0f) - 0.5f) * static_cast<float>(p_pixels_per_tile) * 0.46f);
			const float disp_y = ((fbm_noise((world_x - 97.0f) / 380.0f, (world_y + 181.0f) / 380.0f) - 0.5f) * static_cast<float>(p_pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x + 157.0f) / 176.0f, (world_y - 223.0f) / 176.0f) - 0.5f) * static_cast<float>(p_pixels_per_tile) * 0.46f);
			const float threshold = 0.455f
					+ ((broad - 0.5f) * 0.150f)
					+ ((macro - 0.5f) * 0.150f)
					+ ((fine - 0.5f) * 0.035f);
			const float edge_width = 0.110f;
			const float sample_x = std::max(
				0.0f,
				std::min(static_cast<float>(p_width - 1), static_cast<float>(px) + disp_x)
			) - static_cast<float>(p_blurred_origin_x);
			const float sample_y = std::max(
				0.0f,
				std::min(static_cast<float>(p_height - 1), static_cast<float>(py) + disp_y)
			) - static_cast<float>(p_blurred_origin_y);
			const float sampled_field = sample_grid_bilinear(
				p_blurred,
				p_blurred_width,
				p_blurred_height,
				sample_x,
				sample_y
			);
			float alpha = smooth_float((sampled_field - (threshold - edge_width)) / (edge_width * 2.0f));
			alpha = std::max(0.0f, std::min(1.0f, alpha));
			const int32_t byte_value = std::max(0, std::min(255, static_cast<int32_t>(std::lround(alpha * 255.0f))));
			p_bytes_write[py * p_width + px] = static_cast<uint8_t>(byte_value);
		}
	}
}

float rounded_box_sdf(float p_x, float p_y, float p_half_extent, float p_radius) {
	const float qx = std::fabs(p_x) - p_half_extent + p_radius;
	const float qy = std::fabs(p_y) - p_half_extent + p_radius;
	const float outside_x = std::max(qx, 0.0f);
	const float outside_y = std::max(qy, 0.0f);
	const float outside = std::sqrt(outside_x * outside_x + outside_y * outside_y);
	const float inside = std::min(std::max(qx, qy), 0.0f);
	return outside + inside - p_radius;
}

ContourPoint sample_point(int32_t p_x, int32_t p_y, int32_t p_tile_size_px) {
	const float tile_size = static_cast<float>(p_tile_size_px);
	return {
		(static_cast<float>(p_x) - 0.5f) * tile_size,
		(static_cast<float>(p_y) - 0.5f) * tile_size,
	};
}

void append_polygon(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	std::initializer_list<ContourPoint> p_points,
	float p_chunk_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const int32_t base_index = r_vertices.size();
	for (const ContourPoint &point : p_points) {
		r_vertices.append(godot::Vector2(
			clamp_coord(point.x, p_chunk_px),
			clamp_coord(point.y, p_chunk_px)
		));
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

void append_case_mesh(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	int32_t p_case_code,
	ContourPoint p_tl,
	ContourPoint p_tr,
	ContourPoint p_br,
	ContourPoint p_bl,
	float p_chunk_px
) {
	const ContourPoint top = midpoint(p_tl, p_tr);
	const ContourPoint right = midpoint(p_tr, p_br);
	const ContourPoint bottom = midpoint(p_bl, p_br);
	const ContourPoint left = midpoint(p_tl, p_bl);

	switch (p_case_code) {
		case 0:
			return;
		case 1:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			return;
		case 2:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			return;
		case 3:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, left }, p_chunk_px);
			return;
		case 4:
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 5:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 6:
			append_polygon(r_vertices, r_indices, { p_tr, p_br, bottom, top }, p_chunk_px);
			return;
		case 7:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, bottom, left }, p_chunk_px);
			return;
		case 8:
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 9:
			append_polygon(r_vertices, r_indices, { p_tl, top, bottom, p_bl }, p_chunk_px);
			return;
		case 10:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 11:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, bottom, p_bl }, p_chunk_px);
			return;
		case 12:
			append_polygon(r_vertices, r_indices, { left, right, p_br, p_bl }, p_chunk_px);
			return;
		case 13:
			append_polygon(r_vertices, r_indices, { p_tl, top, right, p_br, p_bl }, p_chunk_px);
			return;
		case 14:
			append_polygon(r_vertices, r_indices, { top, p_tr, p_br, p_bl, left }, p_chunk_px);
			return;
		case 15:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, p_bl }, p_chunk_px);
			return;
		default:
			return;
	}
}

} // namespace

godot::Dictionary build_debug_mesh(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px
) {
	godot::PackedVector2Array vertices;
	godot::PackedInt32Array indices;
	godot::Dictionary result;
	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = 0;
	result["halo_side"] = 0;

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = p_chunk_size + 2;
	if (p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}

	int32_t solid_sample_count = 0;
	for (int32_t y = 1; y <= p_chunk_size; ++y) {
		for (int32_t x = 1; x <= p_chunk_size; ++x) {
			if (read_solid(p_solid_halo, halo_side, x, y)) {
				++solid_sample_count;
			}
		}
	}

	const float chunk_px = static_cast<float>(p_chunk_size * p_tile_size_px);
	for (int32_t y = 0; y < halo_side - 1; ++y) {
		for (int32_t x = 0; x < halo_side - 1; ++x) {
			const bool tl_solid = read_solid(p_solid_halo, halo_side, x, y);
			const bool tr_solid = read_solid(p_solid_halo, halo_side, x + 1, y);
			const bool br_solid = read_solid(p_solid_halo, halo_side, x + 1, y + 1);
			const bool bl_solid = read_solid(p_solid_halo, halo_side, x, y + 1);
			const int32_t case_code =
					(tl_solid ? 1 : 0) |
					(tr_solid ? 2 : 0) |
					(br_solid ? 4 : 0) |
					(bl_solid ? 8 : 0);
			if (case_code == 0) {
				continue;
			}
			append_case_mesh(
				vertices,
				indices,
				case_code,
				sample_point(x, y, p_tile_size_px),
				sample_point(x + 1, y, p_tile_size_px),
				sample_point(x + 1, y + 1, p_tile_size_px),
				sample_point(x, y + 1, p_tile_size_px),
				chunk_px
			);
		}
	}

	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = solid_sample_count;
	result["halo_side"] = halo_side;
	return result;
}

godot::Dictionary build_halo_mask(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px,
	int32_t p_pixels_per_tile,
	double p_origin_world_x,
	double p_origin_world_y
) {
	godot::Dictionary result;
	result["mask"] = godot::PackedByteArray();
	result["width"] = 0;
	result["height"] = 0;
	result["step_px"] = 0.0;
	result["solid_sample_count"] = 0;
	result["halo_side"] = 0;

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = static_cast<int32_t>(std::lround(std::sqrt(static_cast<double>(p_solid_halo.size()))));
	if (p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}
	const int32_t halo_margin = halo_side - p_chunk_size;
	if (halo_margin < 2 || (halo_margin % 2) != 0) {
		return result;
	}
	const int32_t halo_radius_tiles = halo_margin / 2;
	const int32_t pixels_per_tile = std::max(4, std::min(p_pixels_per_tile, 32));
	const int32_t width = halo_side * pixels_per_tile;
	const int32_t height = halo_side * pixels_per_tile;
	const float step_px = static_cast<float>(p_tile_size_px) / static_cast<float>(pixels_per_tile);
	const int32_t pixel_count = width * height;
	godot::PackedByteArray bytes;
	bytes.resize(pixel_count);
	uint8_t *bytes_write = bytes.ptrw();

	int32_t solid_sample_count = 0;
	for (int32_t y = halo_radius_tiles; y < halo_radius_tiles + p_chunk_size; ++y) {
		for (int32_t x = halo_radius_tiles; x < halo_radius_tiles + p_chunk_size; ++x) {
			if (read_solid(p_solid_halo, halo_side, x, y)) {
				++solid_sample_count;
			}
		}
	}

	const int32_t blur_radius = std::max(2, (pixels_per_tile * 5) / 8);
	const std::vector<float> blurred = build_blurred_solid_field(
		p_solid_halo,
		halo_side,
		pixels_per_tile,
		width,
		height,
		blur_radius
	);
	write_organic_mask_region(
		bytes_write,
		blurred,
		width,
		height,
		width,
		height,
		0,
		0,
		pixels_per_tile,
		step_px,
		static_cast<float>(p_origin_world_x),
		static_cast<float>(p_origin_world_y),
		0,
		0,
		width,
		height
	);

	result["mask"] = bytes;
	result["width"] = width;
	result["height"] = height;
	result["step_px"] = static_cast<double>(step_px);
	result["solid_sample_count"] = solid_sample_count;
	result["halo_side"] = halo_side;
	result["halo_radius_tiles"] = halo_radius_tiles;
	result["pixels_per_tile"] = pixels_per_tile;
	return result;
}

godot::Dictionary patch_halo_mask(
	const godot::PackedByteArray &p_previous_mask,
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px,
	int32_t p_pixels_per_tile,
	int32_t p_changed_halo_x,
	int32_t p_changed_halo_y,
	double p_origin_world_x,
	double p_origin_world_y
) {
	godot::Dictionary result;
	result["mask"] = godot::PackedByteArray();
	result["width"] = 0;
	result["height"] = 0;
	result["step_px"] = 0.0;
	result["patch_min"] = godot::Vector2i();
	result["patch_size"] = godot::Vector2i();

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = static_cast<int32_t>(std::lround(std::sqrt(static_cast<double>(p_solid_halo.size()))));
	if (p_solid_halo.size() != halo_side * halo_side
			|| p_changed_halo_x < 0 || p_changed_halo_y < 0
			|| p_changed_halo_x >= halo_side || p_changed_halo_y >= halo_side) {
		return result;
	}
	const int32_t halo_margin = halo_side - p_chunk_size;
	if (halo_margin < 2 || (halo_margin % 2) != 0) {
		return result;
	}
	const int32_t pixels_per_tile = std::max(4, std::min(p_pixels_per_tile, 32));
	const int32_t width = halo_side * pixels_per_tile;
	const int32_t height = halo_side * pixels_per_tile;
	if (p_previous_mask.size() != width * height) {
		return result;
	}
	const float step_px = static_cast<float>(p_tile_size_px) / static_cast<float>(pixels_per_tile);
	const int32_t blur_radius = std::max(2, (pixels_per_tile * 5) / 8);
	const int32_t max_displacement = static_cast<int32_t>(
		std::ceil(static_cast<float>(pixels_per_tile) * (1.15f + 0.46f) * 0.5f)
	) + 6;
	const int32_t influence_radius = blur_radius * 3 + max_displacement;
	const int32_t min_x = std::max(0, p_changed_halo_x * pixels_per_tile - influence_radius);
	const int32_t min_y = std::max(0, p_changed_halo_y * pixels_per_tile - influence_radius);
	const int32_t max_x = std::min(width, (p_changed_halo_x + 1) * pixels_per_tile + influence_radius);
	const int32_t max_y = std::min(height, (p_changed_halo_y + 1) * pixels_per_tile + influence_radius);

	// A single mined tile only influences a small organic-contour window. The
	// old hot path rebuilt three full 384x384 blur passes before writing that
	// window, which alone could consume a 60 FPS frame. Build an expanded local
	// blur field instead. Three blur passes and the displacement sampler cannot
	// observe beyond this fixed support, so the resulting bytes are identical to
	// the authoritative full rebuild inside patch_min/patch_size.
	const int32_t blur_support = blur_radius * 3;
	const int32_t bilinear_guard = 2;
	const int32_t sample_min_x = min_x - max_displacement - bilinear_guard;
	const int32_t sample_min_y = min_y - max_displacement - bilinear_guard;
	const int32_t sample_max_x = max_x + max_displacement + bilinear_guard;
	const int32_t sample_max_y = max_y + max_displacement + bilinear_guard;
	const int32_t blurred_origin_x = sample_min_x - blur_support;
	const int32_t blurred_origin_y = sample_min_y - blur_support;
	const int32_t blurred_width = sample_max_x - sample_min_x + blur_support * 2;
	const int32_t blurred_height = sample_max_y - sample_min_y + blur_support * 2;
	const std::vector<float> blurred = build_blurred_solid_field(
		p_solid_halo,
		halo_side,
		pixels_per_tile,
		blurred_width,
		blurred_height,
		blur_radius,
		blurred_origin_x,
		blurred_origin_y,
		width,
		height
	);
	godot::PackedByteArray bytes = p_previous_mask.duplicate();
	uint8_t *bytes_write = bytes.ptrw();
	write_organic_mask_region(
		bytes_write,
		blurred,
		width,
		height,
		blurred_width,
		blurred_height,
		blurred_origin_x,
		blurred_origin_y,
		pixels_per_tile,
		step_px,
		static_cast<float>(p_origin_world_x),
		static_cast<float>(p_origin_world_y),
		min_x,
		min_y,
		max_x,
		max_y
	);

	result["mask"] = bytes;
	result["width"] = width;
	result["height"] = height;
	result["step_px"] = static_cast<double>(step_px);
	result["halo_side"] = halo_side;
	result["pixels_per_tile"] = pixels_per_tile;
	result["patch_min"] = godot::Vector2i(min_x, min_y);
	result["patch_size"] = godot::Vector2i(max_x - min_x, max_y - min_y);
	return result;
}

} // namespace mountain_contour
