#include "mountain_contour.h"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <vector>

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

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

std::vector<float> box_blur_once(
	const std::vector<float> &p_source,
	int32_t p_width,
	int32_t p_height,
	int32_t p_radius
) {
	if (p_radius <= 0 || p_width <= 0 || p_height <= 0) {
		return p_source;
	}
	std::vector<float> temp(static_cast<size_t>(p_width * p_height), 0.0f);
	std::vector<float> result(static_cast<size_t>(p_width * p_height), 0.0f);
	const float divisor = static_cast<float>(p_radius * 2 + 1);
	for (int32_t y = 0; y < p_height; ++y) {
		float sum = 0.0f;
		for (int32_t x = -p_radius; x <= p_radius; ++x) {
			const int32_t sample_x = std::max(0, std::min(p_width - 1, x));
			sum += p_source[static_cast<size_t>(y * p_width + sample_x)];
		}
		for (int32_t x = 0; x < p_width; ++x) {
			temp[static_cast<size_t>(y * p_width + x)] = sum / divisor;
			const int32_t remove_x = std::max(0, std::min(p_width - 1, x - p_radius));
			const int32_t add_x = std::max(0, std::min(p_width - 1, x + p_radius + 1));
			sum += p_source[static_cast<size_t>(y * p_width + add_x)];
			sum -= p_source[static_cast<size_t>(y * p_width + remove_x)];
		}
	}
	for (int32_t x = 0; x < p_width; ++x) {
		float sum = 0.0f;
		for (int32_t y = -p_radius; y <= p_radius; ++y) {
			const int32_t sample_y = std::max(0, std::min(p_height - 1, y));
			sum += temp[static_cast<size_t>(sample_y * p_width + x)];
		}
		for (int32_t y = 0; y < p_height; ++y) {
			result[static_cast<size_t>(y * p_width + x)] = sum / divisor;
			const int32_t remove_y = std::max(0, std::min(p_height - 1, y - p_radius));
			const int32_t add_y = std::max(0, std::min(p_height - 1, y + p_radius + 1));
			sum += temp[static_cast<size_t>(add_y * p_width + x)];
			sum -= temp[static_cast<size_t>(remove_y * p_width + x)];
		}
	}
	return result;
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
	double p_origin_world_y,
	const godot::PackedByteArray &p_cutout_halo
) {
	godot::Dictionary result;
	result["mask"] = godot::PackedByteArray();
	result["width"] = 0;
	result["height"] = 0;
	result["step_px"] = 0.0;
	result["solid_sample_count"] = 0;
	result["cutout_sample_count"] = 0;
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
	const bool cutout_shape_valid = p_cutout_halo.size() == p_solid_halo.size();
	godot::PackedByteArray bytes;
	bytes.resize(pixel_count);
	uint8_t *bytes_write = bytes.ptrw();
	godot::PackedByteArray roof_bytes;
	uint8_t *roof_bytes_write = nullptr;
	if (cutout_shape_valid) {
		roof_bytes.resize(pixel_count);
		roof_bytes_write = roof_bytes.ptrw();
	}

	int32_t solid_sample_count = 0;
	for (int32_t y = halo_radius_tiles; y < halo_radius_tiles + p_chunk_size; ++y) {
		for (int32_t x = halo_radius_tiles; x < halo_radius_tiles + p_chunk_size; ++x) {
			if (read_solid(p_solid_halo, halo_side, x, y)) {
				++solid_sample_count;
			}
		}
	}

	std::vector<float> field(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> temp(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> blurred(static_cast<size_t>(pixel_count), 0.0f);
	for (int32_t py = 0; py < height; ++py) {
		const int32_t tile_y = std::max(0, std::min(halo_side - 1, py / pixels_per_tile));
		for (int32_t px = 0; px < width; ++px) {
			const int32_t tile_x = std::max(0, std::min(halo_side - 1, px / pixels_per_tile));
			const bool roof_owned = read_solid(p_solid_halo, halo_side, tile_x, tile_y)
				|| (cutout_shape_valid && read_solid(p_cutout_halo, halo_side, tile_x, tile_y));
			field[static_cast<size_t>(py * width + px)] = roof_owned ? 1.0f : 0.0f;
		}
	}

	const int32_t blur_radius = std::max(2, (pixels_per_tile * 5) / 8);
	for (int32_t pass = 0; pass < 3; ++pass) {
		const std::vector<float> &src_h = pass == 0 ? field : blurred;
		for (int32_t y = 0; y < height; ++y) {
			float sum = 0.0f;
			for (int32_t x = -blur_radius; x <= blur_radius; ++x) {
				const int32_t sample_x = std::max(0, std::min(width - 1, x));
				sum += src_h[static_cast<size_t>(y * width + sample_x)];
			}
			for (int32_t x = 0; x < width; ++x) {
				temp[static_cast<size_t>(y * width + x)] = sum / static_cast<float>(blur_radius * 2 + 1);
				const int32_t remove_x = std::max(0, std::min(width - 1, x - blur_radius));
				const int32_t add_x = std::max(0, std::min(width - 1, x + blur_radius + 1));
				sum += src_h[static_cast<size_t>(y * width + add_x)];
				sum -= src_h[static_cast<size_t>(y * width + remove_x)];
			}
		}
		for (int32_t x = 0; x < width; ++x) {
			float sum = 0.0f;
			for (int32_t y = -blur_radius; y <= blur_radius; ++y) {
				const int32_t sample_y = std::max(0, std::min(height - 1, y));
				sum += temp[static_cast<size_t>(sample_y * width + x)];
			}
			for (int32_t y = 0; y < height; ++y) {
				blurred[static_cast<size_t>(y * width + x)] = sum / static_cast<float>(blur_radius * 2 + 1);
				const int32_t remove_y = std::max(0, std::min(height - 1, y - blur_radius));
				const int32_t add_y = std::max(0, std::min(height - 1, y + blur_radius + 1));
				sum += temp[static_cast<size_t>(add_y * width + x)];
				sum -= temp[static_cast<size_t>(remove_y * width + x)];
			}
		}
	}

	int32_t cutout_sample_count = 0;
	if (cutout_shape_valid) {
		for (int32_t index = 0; index < p_cutout_halo.size(); ++index) {
			if (p_cutout_halo[index] != 0) {
				++cutout_sample_count;
			}
		}
	}
	std::vector<float> cutout_blurred;
	if (cutout_sample_count > 0) {
		std::vector<float> cutout_field(static_cast<size_t>(pixel_count), 0.0f);
		for (int32_t py = 0; py < height; ++py) {
			const int32_t tile_y = std::max(0, std::min(halo_side - 1, py / pixels_per_tile));
			for (int32_t px = 0; px < width; ++px) {
				const int32_t tile_x = std::max(0, std::min(halo_side - 1, px / pixels_per_tile));
				cutout_field[static_cast<size_t>(py * width + px)] =
					read_solid(p_cutout_halo, halo_side, tile_x, tile_y) ? 1.0f : 0.0f;
			}
		}
		cutout_blurred = box_blur_once(
			cutout_field,
			width,
			height,
			std::max(1, pixels_per_tile / 4)
		);
	}

	for (int32_t py = 0; py < height; ++py) {
		const float world_y = static_cast<float>(p_origin_world_y) + (static_cast<float>(py) + 0.5f) * step_px;
		for (int32_t px = 0; px < width; ++px) {
			const float world_x = static_cast<float>(p_origin_world_x) + (static_cast<float>(px) + 0.5f) * step_px;
			const float broad = fbm_noise((world_x - 173.0f) / 420.0f, (world_y + 211.0f) / 420.0f);
			const float macro = fbm_noise(world_x / 220.0f, world_y / 220.0f);
			const float fine = fbm_noise((world_x + 91.0f) / 104.0f, (world_y - 37.0f) / 104.0f);
			const float disp_x = ((fbm_noise((world_x + 43.0f) / 360.0f, (world_y - 139.0f) / 360.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x - 211.0f) / 170.0f, (world_y + 79.0f) / 170.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 0.46f);
			const float disp_y = ((fbm_noise((world_x - 97.0f) / 380.0f, (world_y + 181.0f) / 380.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x + 157.0f) / 176.0f, (world_y - 223.0f) / 176.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 0.46f);
			const float threshold = 0.455f
					+ ((broad - 0.5f) * 0.150f)
					+ ((macro - 0.5f) * 0.150f)
					+ ((fine - 0.5f) * 0.035f);
			const float edge_width = 0.110f;
			const float field = sample_grid_bilinear(blurred, width, height, static_cast<float>(px) + disp_x, static_cast<float>(py) + disp_y);
			float alpha = smooth_float((field - (threshold - edge_width)) / (edge_width * 2.0f));
			alpha = std::max(0.0f, std::min(1.0f, alpha));
			const int32_t roof_byte_value = std::max(0, std::min(255, static_cast<int32_t>(std::lround(alpha * 255.0f))));
			if (roof_bytes_write != nullptr) {
				roof_bytes_write[py * width + px] = static_cast<uint8_t>(roof_byte_value);
			}
			if (!cutout_blurred.empty()) {
				const float cutout_field = sample_grid_bilinear(
					cutout_blurred,
					width,
					height,
					static_cast<float>(px) + disp_x * 0.32f,
					static_cast<float>(py) + disp_y * 0.32f
				);
				float cutout_alpha = smooth_float((cutout_field - 0.28f) / 0.44f);
				const int32_t tile_x = px / pixels_per_tile;
				const int32_t tile_y = py / pixels_per_tile;
				if (read_solid(p_cutout_halo, halo_side, tile_x, tile_y)) {
					const float local_x = std::fmod(static_cast<float>(px) + 0.5f, static_cast<float>(pixels_per_tile));
					const float local_y = std::fmod(static_cast<float>(py) + 0.5f, static_cast<float>(pixels_per_tile));
					const float core_min = static_cast<float>(pixels_per_tile) * 0.25f;
					const float core_max = static_cast<float>(pixels_per_tile) * 0.75f;
					if (local_x >= core_min && local_x <= core_max && local_y >= core_min && local_y <= core_max) {
						cutout_alpha = 1.0f;
					}
				}
				alpha *= 1.0f - cutout_alpha;
			}
			alpha = std::max(0.0f, std::min(1.0f, alpha));
			const int32_t byte_value = std::max(0, std::min(255, static_cast<int32_t>(std::lround(alpha * 255.0f))));
			bytes_write[py * width + px] = static_cast<uint8_t>(byte_value);
		}
	}

	result["mask"] = bytes;
	result["roof_mask"] = roof_bytes;
	result["width"] = width;
	result["height"] = height;
	result["step_px"] = static_cast<double>(step_px);
	result["solid_sample_count"] = solid_sample_count;
	result["cutout_sample_count"] = cutout_sample_count;
	result["halo_side"] = halo_side;
	result["halo_radius_tiles"] = halo_radius_tiles;
	result["pixels_per_tile"] = pixels_per_tile;
	return result;
}

godot::PackedByteArray compose_cover_mask(
	const godot::PackedByteArray &p_open_mask,
	const godot::PackedByteArray &p_roof_mask,
	const godot::PackedByteArray &p_visibility_halo,
	int32_t p_pixels_per_tile
) {
	if (p_open_mask.is_empty() || p_open_mask.size() != p_roof_mask.size()) {
		return godot::PackedByteArray();
	}
	const int32_t mask_side = static_cast<int32_t>(std::lround(std::sqrt(static_cast<double>(p_open_mask.size()))));
	const int32_t halo_side = static_cast<int32_t>(std::lround(std::sqrt(static_cast<double>(p_visibility_halo.size()))));
	const int32_t pixels_per_tile = std::max(1, p_pixels_per_tile);
	if (mask_side <= 0
			|| p_open_mask.size() != mask_side * mask_side
			|| halo_side <= 0
			|| p_visibility_halo.size() != halo_side * halo_side
			|| mask_side != halo_side * pixels_per_tile) {
		return godot::PackedByteArray();
	}

	bool has_visible_cutout = false;
	for (int32_t index = 0; index < p_visibility_halo.size(); ++index) {
		if (p_visibility_halo[index] != 0) {
			has_visible_cutout = true;
			break;
		}
	}
	if (!has_visible_cutout) {
		return p_roof_mask;
	}

	const int32_t pixel_count = mask_side * mask_side;
	std::vector<float> visibility_field(static_cast<size_t>(pixel_count), 0.0f);
	for (int32_t py = 0; py < mask_side; ++py) {
		const int32_t tile_y = std::min(halo_side - 1, py / pixels_per_tile);
		for (int32_t px = 0; px < mask_side; ++px) {
			const int32_t tile_x = std::min(halo_side - 1, px / pixels_per_tile);
			visibility_field[static_cast<size_t>(py * mask_side + px)] =
				read_solid(p_visibility_halo, halo_side, tile_x, tile_y) ? 1.0f : 0.0f;
		}
	}
	const std::vector<float> visibility_blurred = box_blur_once(
		visibility_field,
		mask_side,
		mask_side,
		std::max(1, pixels_per_tile / 4)
	);

	godot::PackedByteArray result;
	result.resize(pixel_count);
	uint8_t *result_write = result.ptrw();
	for (int32_t py = 0; py < mask_side; ++py) {
		const int32_t tile_y = py / pixels_per_tile;
		for (int32_t px = 0; px < mask_side; ++px) {
			const int32_t index = py * mask_side + px;
			const int32_t tile_x = px / pixels_per_tile;
			float reveal = smooth_float((visibility_blurred[static_cast<size_t>(index)] - 0.18f) / 0.64f);
			if (read_solid(p_visibility_halo, halo_side, tile_x, tile_y)) {
				const float local_x = std::fmod(static_cast<float>(px) + 0.5f, static_cast<float>(pixels_per_tile));
				const float local_y = std::fmod(static_cast<float>(py) + 0.5f, static_cast<float>(pixels_per_tile));
				const float core_min = static_cast<float>(pixels_per_tile) * 0.25f;
				const float core_max = static_cast<float>(pixels_per_tile) * 0.75f;
				if (local_x >= core_min && local_x <= core_max && local_y >= core_min && local_y <= core_max) {
					reveal = 1.0f;
				}
			}
			const int32_t roof_value = static_cast<int32_t>(p_roof_mask[index]);
			const int32_t open_value = static_cast<int32_t>(p_open_mask[index]);
			const int32_t cutout_delta = std::max(0, roof_value - open_value);
			const int32_t value = roof_value - static_cast<int32_t>(std::lround(static_cast<float>(cutout_delta) * reveal));
			result_write[index] = static_cast<uint8_t>(std::max(0, std::min(255, value)));
		}
	}
	return result;
}

} // namespace mountain_contour
